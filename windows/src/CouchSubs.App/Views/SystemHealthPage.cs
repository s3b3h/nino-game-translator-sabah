// SPDX-License-Identifier: AGPL-3.0-only
// Nino: Ayarlar › Sistem sağlığı (Mac'teki SystemHealthView ile aynı satırlar, eşikler ve metinler). Kodla kurulur.

using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using CouchSubs.App.Controls;
using CouchSubs.App.Services;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views;

/// <summary>
/// Her satır yeşil/sarı/kırmızı ve sorun varsa ne yapılacağı; altta bilen biri için ayrıntılar (ham sayılar, son günlük
/// satırları), kopyalama ve yalnız günlük dosyalarını içeren zip. Sayılar iki saniyede bir yenilenir.
/// </summary>
public sealed class SystemHealthPage : UserControl
{
    private readonly AppController controller;
    private readonly StackPanel rows = new();
    private readonly TextBlock hint = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) };
    private readonly System.Windows.Controls.TextBox details = new() { IsReadOnly = true, FontFamily = new FontFamily("Consolas"), FontSize = 12, Height = 260, TextWrapping = TextWrapping.NoWrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto };
    private readonly TextBlock exportError = new() { TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed };
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(2) };
    /// <summary>Nino: "Cihaz bilgileri" kartının satırları; yalnız değerler değişince yeniden kurulur.</summary>
    private readonly StackPanel deviceRows = new();
    private readonly Button copyDevice = new() { HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 12, 0, 0) };
    private string shownDevice = "";
    private DateTime? deviceCopiedAt;
    private static readonly string ThisVersion = AppVersion.Current(Assembly.GetEntryAssembly() ?? typeof(SystemHealthPage).Assembly);

    private static string T(string key) => Localizer.Current[key];

    public SystemHealthPage(AppController controller)
    {
        this.controller = controller;
        hint.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        exportError.SetResourceReference(TextBlock.ForegroundProperty, "warningBrush");
        var checks = new Card { Content = new StackPanel { Children = { hint, rows } }, Margin = new Thickness(0, 0, 0, 16) };

        var copy = new Button { Content = T("Copy details"), Margin = new Thickness(0, 0, 8, 0) };
        copy.Click += (_, _) =>
        {
            try
            {
                Clipboard.SetText(details.Text);
                copy.Content = T("Copied");
            }
            catch (System.Runtime.InteropServices.COMException) { }
        };
        var save = new Button { Content = T("Save logs as zip") };
        save.Click += (_, _) => SaveLogs();
        var privacy = new TextBlock
        {
            Text = T("If something does not work, send the zip to whoever helps you. The logs contain the subtitles Nino read, the PS5's name and its address on your home network, but no password, key or account information."),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 8, 0, 0),
        };
        privacy.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        var expander = new Expander
        {
            Header = new TextBlock { Text = T("Details"), FontWeight = FontWeights.SemiBold },
            Content = new StackPanel
            {
                Margin = new Thickness(0, 12, 0, 0),
                Children = { details, new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 0), Children = { copy, save } }, exportError, privacy },
            },
        };
        expander.Expanded += (_, _) => copy.Content = T("Copied") == (string)copy.Content ? T("Copy details") : copy.Content;
        var detailsCard = new Card { Content = expander };

        // Nino: Cihaz bilgileri. Sorun Bildir ve Nino'ya Sor bildirimlerine eklenen özetin aynısı; kullanıcı ne gittiğini görür.
        var deviceHint = new TextBlock
        {
            Text = T("Added to your problem reports so we can see what you use without asking. It contains no names, serial numbers or addresses."),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 12),
        };
        deviceHint.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        copyDevice.Content = T("Copy device info");
        copyDevice.Click += (_, _) =>
        {
            try
            {
                Clipboard.SetText(controller.DeviceSummary(ThisVersion));
                copyDevice.Content = T("Copied");
                deviceCopiedAt = DateTime.UtcNow;
            }
            catch (System.Runtime.InteropServices.COMException) { }
        };
        var deviceCard = new Card
        {
            Title = T("Device info"),
            Content = new StackPanel { Children = { deviceHint, deviceRows, copyDevice } },
            Margin = new Thickness(0, 16, 0, 0),
        };

        Content = new StackPanel
        {
            Children =
            {
                checks,
                // TV uygulamasının kurulum adımları ve hatası ("Tekrar dene"); eskiden Hakkında'daydı (Mac ile aynı).
                new Steps.TvAppCard { Margin = new Thickness(0, 0, 0, 16) },
                detailsCard,
                deviceCard,
            },
        };
        timer.Tick += (_, _) => Refresh();
        Loaded += (_, _) => { Refresh(); timer.Start(); };
        Unloaded += (_, _) => timer.Stop();
    }

    private static Brush Level(HealthLevel level) => (Brush)Application.Current.FindResource(level switch
    {
        HealthLevel.Good => "successBrush",
        HealthLevel.Warning => "warningBrush",
        HealthLevel.Problem => "dangerBrush",
        _ => "textSecondaryBrush",
    });

    private static string LevelText(HealthLevel level) => T(level switch
    {
        HealthLevel.Good => "Good",
        HealthLevel.Warning => "Could be better",
        HealthLevel.Problem => "Problem",
        _ => "Not measured yet",
    });

    private void Refresh()
    {
        var s = HealthRecorder.Shared.Snapshot();
        var network = NetworkKinds.Detect();
        var stream = HealthReport.Stream(s);
        hint.Text = s.IsEmpty ? T("Start translation and play for a few minutes; Nino measures the connection while you play.")
            : !s.Active ? T("Results of the last translation session. They are measured again when you start translation.") : "";
        hint.Visibility = hint.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;

        rows.Children.Clear();
        AddRow(T("This Mac's network").Replace("Mac", "PC"), HealthReport.Network(network, stream), NetworkText(network),
            network == NetworkKind.Offline
                ? T("This Mac is not connected to a network. Connect it to the same modem as the PS5.")
                : T("The PS5 picture is losing data. Connect this Mac to the modem with a cable (a USB-C Ethernet adapter works). If that is not possible, move closer to the modem and use 5 GHz Wi-Fi."));
        AddRow(T("PS5 connection"), HealthReport.Connection(s), ConnectionText(s), ConnectionAdvice(s.LastDisconnect));
        AddRow(T("PS5 picture"), stream, StreamText(s),
            T("When the picture freezes, Nino cannot read the subtitles. Connect both the PS5 and this Mac to the modem with a cable."));
        AddRow(T("Translation speed"), HealthReport.Translation(s), TranslationText(s),
            controller.OnlineTranslationActive || controller.Settings.OnlineEngine == TranslationEngine.Local
                ? T("Translation is slow. Choose the Free engine in Settings › Translation and see whether it gets faster.")
                : T("Translation is slow. Close other heavy apps on this Mac and try again."));
        var tvLevel = !controller.IsRunning || !controller.ShowsOnTv ? HealthLevel.Unknown : controller.TvClients > 0 ? HealthLevel.Good : HealthLevel.Problem;
        AddRow("TV", tvLevel, !controller.ShowsOnTv ? T("Subtitles are not sent to a TV") : !controller.IsRunning ? T("Not started") : controller.TvClients > 0 ? T("Connected") : T("Not connected"),
            T("The TV app is not connected. Open the Nino app on the TV and check that the TV is on the same network as this Mac."));

        if (!details.IsKeyboardFocusWithin) details.Text = Details(s, network);
        RefreshDevice();
    }

    /// <summary>Satırın sabit adının ("app", "tv" …) ekrandaki karşılığı.</summary>
    private static string DeviceLabel(string id) => T(id switch
    {
        "app" => "App version",
        "device" => "Device model",
        "system" => "Operating system",
        "tv" => "TV",
        "console" => "Console",
        _ => "Current status",
    });

    /// <summary>Cihaz bilgileri: her değer bir satır (solda adı, sağda değeri). Değerler değişmediyse dokunulmaz.</summary>
    private void RefreshDevice()
    {
        // "Kopyalandı" yazısı birkaç saniye sonra düğmenin adına döner.
        if (deviceCopiedAt is { } at && DateTime.UtcNow - at > TimeSpan.FromSeconds(3))
        {
            deviceCopiedAt = null;
            copyDevice.Content = T("Copy device info");
        }
        var list = controller.DeviceRows(ThisVersion);
        var summary = DeviceInfo.Summary(list);
        if (summary == shownDevice && deviceRows.Children.Count > 0) return;
        shownDevice = summary;
        deviceRows.Children.Clear();
        foreach (var row in list)
        {
            if (deviceRows.Children.Count > 0) deviceRows.Children.Add(new Separator { Margin = new Thickness(0, 8, 0, 8) });
            var line = new DockPanel();
            var label = new TextBlock { Text = DeviceLabel(row.Id), FontWeight = FontWeights.SemiBold, Width = 190, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 12, 0) };
            DockPanel.SetDock(label, Dock.Left);
            line.Children.Add(label);
            var value = new TextBlock { Text = row.Value, TextWrapping = TextWrapping.Wrap };
            value.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
            line.Children.Add(value);
            deviceRows.Children.Add(line);
        }
    }

    /// <summary>Satır: nokta, ad, durum; sarı ya da kırmızıysa altında ne yapılacağı. (Mac'e özgü "Mac" sözcüğü PC olur.)</summary>
    private void AddRow(string title, HealthLevel level, string value, string advice)
    {
        if (rows.Children.Count > 0) rows.Children.Add(new Separator { Margin = new Thickness(0, 8, 0, 8) });
        var head = new DockPanel();
        var state = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(state, Dock.Right);
        state.Children.Add(new System.Windows.Shapes.Ellipse { Width = 8, Height = 8, Fill = Level(level), Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center });
        var stateText = new TextBlock { Text = LevelText(level), FontWeight = FontWeights.SemiBold, Foreground = level == HealthLevel.Unknown ? Level(level) : Level(level) };
        state.Children.Add(stateText);
        head.Children.Add(state);
        head.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold });
        var panel = new StackPanel();
        panel.Children.Add(head);
        var valueText = new TextBlock { Text = value, TextWrapping = TextWrapping.Wrap };
        valueText.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        panel.Children.Add(valueText);
        if (level is HealthLevel.Warning or HealthLevel.Problem)
            panel.Children.Add(new TextBlock { Text = ForPc(advice), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) });
        rows.Children.Add(panel);
    }

    /// <summary>Metinler Mac'le ortak; Windows'ta "Mac" yerine "PC", USB-C adaptör yerine genel kablo önerisi.</summary>
    private static string ForPc(string text) => text
        .Replace(" (a USB-C Ethernet adapter works)", "").Replace(" (USB-C Ethernet adaptörü olur)", "")
        .Replace("this Mac", "this PC").Replace("This Mac", "This PC").Replace("bu Mac", "bu bilgisayar").Replace("Bu Mac", "Bu bilgisayar");

    private static string NetworkText(NetworkKind kind) => kind switch
    {
        NetworkKind.Wired => T("Cable"),
        NetworkKind.Wifi => T("Wi-Fi"),
        NetworkKind.Other => T("Other connection"),
        NetworkKind.Offline => T("No network"),
        _ => T("Checking…"),
    };

    private static string ConnectionText(HealthSnapshot s)
    {
        if (s.IsEmpty) return T("Not started");
        if (s.Connects == 0) return Localizer.Current.Format("Could not connect (%d tries)", s.ConnectAttempts);
        return s.Drops == 0 ? T("Connected, no drops") : Localizer.Current.Format("Dropped %d times while playing", s.Drops);
    }

    private static string ConnectionAdvice(string? reason) => reason switch
    {
        "ConsoleAsleep" => T("The PS5 is off or asleep. Turn it on, or turn on “Stay connected to the internet” in its rest mode settings."),
        "InUse" => T("Remote Play is being used on another device. Close it there."),
        "LoginPasscode" => T("The second account has a PS5 login passcode. Remove it on the PS5."),
        "RemotePlayDisabled" => T("Remote Play is turned off on the PS5. On the PS5, open Settings › System › Remote Play and turn on Enable Remote Play, then start again."),
        "RegistrationInvalid" or "Refused" => T("The PS5 did not accept this Mac. Pair the PS5 again from Settings › About Nino › Set up again."),
        "NotFound" => T("The PS5 did not answer on the network. Check that it is on (or in rest mode) and on the same network as this Mac."),
        _ => T("The connection to the PS5 keeps dropping. Connect both the PS5 and this Mac to the modem with a cable."),
    };

    private static string StreamText(HealthSnapshot s)
    {
        if (s.LossPerMinute is not { } loss || s.StallsPerMinute is not { } stalls)
            return s.IsEmpty ? T("Not started") : T("Measuring…");
        return T("%1$@ lost packets and %2$@ freezes per minute")
            .Replace("%1$@", loss.ToString("0")).Replace("%2$@", stalls.ToString("0.0"));
    }

    private static string TranslationText(HealthSnapshot s)
    {
        if (s.TranslationMedianMs is not { } median) return s.IsEmpty ? T("Not started") : T("No line translated yet");
        return T("%1$@ s per line (%2$d lines)").Replace("%1$@", (median / 1000.0).ToString("0.0")).Replace("%2$d", s.Translations.ToString());
    }

    private string Details(HealthSnapshot s, NetworkKind network)
    {
        var tvApp = controller.TvApp;
        return string.Join("\n",
            $"Nino {typeof(SystemHealthPage).Assembly.GetName().Version}, Windows {Environment.OSVersion.Version}, {Environment.ProcessorCount} çekirdek",
            $"motor: {(controller.OnlineTranslationActive ? controller.Settings.OnlineEngine.ToString() : "ücretsiz")}, çeviri: {(controller.IsRunning ? "sürüyor" : "durdu")}, PS5: {controller.SessionState.Phase}",
            $"TV: {(controller.Tv is { } tv ? tv.Brand.ToString() : "yok")}, bağlı TV uygulaması {controller.TvClients}, TV uygulaması: {tvApp.Kind}{(tvApp.Version is { } v ? " " + v : "")}{(tvApp.Error is { } err ? " hata " + err : "")}",
            HealthReport.Summary(s, network),
            "",
            "— altyazi.log (son satırlar) —",
            Tail(SubtitleLog.DefaultPath, 40),
            "",
            "— tvinstall.log (son satırlar) —",
            Tail(LiveServices.TvInstallLogPath, 8));
    }

    private static string Tail(string path, int count)
    {
        try
        {
            if (!File.Exists(path)) return "-";
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            stream.Seek(Math.Max(0, stream.Length - 65536), SeekOrigin.Begin);
            using var reader = new StreamReader(stream);
            var lines = reader.ReadToEnd().Split('\n', StringSplitOptions.RemoveEmptyEntries);
            return string.Join("\n", lines.TakeLast(count));
        }
        catch (IOException) { return "-"; }
    }

    /// <summary>Yalnız günlük dosyalarını (ve ayrıntıları) zip'ler, İndirilenler'e koyar ve Gezgin'de gösterir.</summary>
    private void SaveLogs()
    {
        exportError.Visibility = Visibility.Collapsed;
        try
        {
            var folder = Path.GetDirectoryName(SubtitleLog.DefaultPath)!;
            var downloads = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
            Directory.CreateDirectory(downloads);
            var target = Path.Combine(downloads, $"Nino-kayitlar-{DateTime.Now:yyyy-MM-dd-HH-mm-ss}.zip");
            using (var zip = ZipFile.Open(target, ZipArchiveMode.Create))
            {
                foreach (var file in Directory.EnumerateFiles(folder).Where(f => Path.GetFileName(f).Contains(".log")))
                {
                    using var source = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                    using var entry = zip.CreateEntry(Path.GetFileName(file)).Open();
                    source.CopyTo(entry);
                }
                using var writer = new StreamWriter(zip.CreateEntry("ayrintilar.txt").Open());
                writer.Write(details.Text);
            }
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{target}\"") { UseShellExecute = true });
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            exportError.Text = T("The logs could not be saved.") + " (" + error.Message + ")";
            exportError.Visibility = Visibility.Visible;
        }
    }
}

/// <summary>Baştan Kur: "TV'den itibaren yeniden kur" (PS5 hesabı kalır) ya da "Her şeyi sıfırla" (Mac ile aynı).</summary>
public sealed class ResetChoiceWindow : Window
{
    public enum Choice { Cancel, FromTv, Everything }

    public Choice Result { get; private set; } = Choice.Cancel;

    private ResetChoiceWindow()
    {
        Title = Localizer.Current["Set up again?"];
        SizeToContent = SizeToContent.WidthAndHeight;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        SetResourceReference(BackgroundProperty, "windowBackgroundBrush");
        SetResourceReference(ForegroundProperty, "textPrimaryBrush");
        var message = new TextBlock
        {
            Text = Localizer.Current["From the TV: your PS5 account and PS5 pairing stay; only the TV connection is set up again. Reset everything: the saved PS5, account and TV connection are removed and you sign in to PSN again."],
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 460,
            Margin = new Thickness(0, 0, 0, 20),
        };
        Button Make(string key, Choice choice, string? style = null)
        {
            var button = new Button { Content = Localizer.Current[key], Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(16, 0, 16, 0) };
            if (style is not null) button.Style = (Style)Application.Current.FindResource(style);
            button.Click += (_, _) => { Result = choice; Close(); };
            return button;
        }
        var everything = Make("Reset everything", Choice.Everything);
        everything.SetResourceReference(ForegroundProperty, "dangerBrush");
        var cancel = Make("Cancel", Choice.Cancel);
        cancel.IsCancel = true;
        Content = new StackPanel
        {
            Margin = new Thickness(24),
            Children =
            {
                message,
                new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Children = { cancel, everything, Make("Set up again from the TV", Choice.FromTv, "PrimaryButton") } },
            },
        };
    }

    public static Choice Ask(Window owner)
    {
        var window = new ResetChoiceWindow { Owner = owner };
        window.ShowDialog();
        return window.Result;
    }
}
