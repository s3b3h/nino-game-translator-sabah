// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı (Mac: CaptureCardSetup.swift ile aynı sayfalar ve metinler).
// Görünümler kodla kurulur: yanlış kaynak adı derlemede yakalanır.

using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using CouchSubs.App.Controls;
using CouchSubs.App.Services;
using CouchSubs.App.Theme;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views;

/// <summary>Kart rehberinin ve önizlemenin ortak küçük parçaları.</summary>
internal static class CardUi
{
    // Segoe Fluent Icons
    public const string Cable = "";      // Connect
    public const string Monitor = "";    // TVMonitor
    public const string Laptop = "";     // DeviceLaptopNoPic
    public const string Lock = "";
    public const string Unlock = "";
    public const string Info = "";
    public const string Headphone = "";
    public const string Circle = "";     // CircleRing
    public const string CircleFill = ""; // CompletedSolid

    public static string T(string key) => Localizer.Current[key];

    public static TextBlock Glyph(string glyph, double size, string brush)
    {
        var text = new TextBlock { Text = glyph, FontSize = size };
        text.SetResourceReference(FrameworkElement.StyleProperty, "GlyphText");
        text.SetResourceReference(TextBlock.ForegroundProperty, brush);
        return text;
    }

    public static TextBlock Text(string text, string style, string? brush = null)
    {
        var block = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap };
        block.SetResourceReference(FrameworkElement.StyleProperty, style);
        if (brush is not null) block.SetResourceReference(TextBlock.ForegroundProperty, brush);
        return block;
    }

    /// <summary>Simge ve yanında sarılan yazı (bilgi satırları).</summary>
    public static FrameworkElement Label(string glyph, string text, string brush, string style = "HintText")
    {
        var row = new DockPanel();
        var icon = Glyph(glyph, 16, brush);
        icon.VerticalAlignment = VerticalAlignment.Top;
        icon.Margin = new Thickness(0, 2, 10, 0);
        DockPanel.SetDock(icon, Dock.Left);
        row.Children.Add(icon);
        row.Children.Add(Text(text, style, brush));
        return row;
    }

    public static Button Button(string text, string style, RoutedEventHandler click)
    {
        var button = new Button { Content = text };
        button.SetResourceReference(FrameworkElement.StyleProperty, style);
        button.Click += click;
        return button;
    }

    /// <summary>İçeriği olduğu gibi gösteren, tıklanabilir ve klavyeyle seçilebilir düğme (büyük seçim karoları).</summary>
    public static Button Plain(UIElement content, RoutedEventHandler click)
    {
        var template = new ControlTemplate(typeof(Button)) { VisualTree = new FrameworkElementFactory(typeof(ContentPresenter)) };
        var button = new Button
        {
            Content = content, Template = template, Cursor = Cursors.Hand, HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch, FocusVisualStyle = null,
        };
        button.Click += click;
        return button;
    }
}

/// <summary>
/// Kartın canlı önizlemesi, durum etiketi, ne yapılacağı ve (birden çok aygıt varsa) aygıt seçici. Rehberin son
/// sayfasında ve ayarlarda kullanılır. Kart tek uygulamaya açılabildiği için çeviri sürerken önizleme açılmaz; çeviri
/// başlarken önizleme kartı hemen bırakır.
/// </summary>
public sealed class CaptureCardCheck : UserControl
{
    private readonly AppController controller;
    private readonly CardVideoSurface surface = new();
    private readonly StackPanel placeholder = new() { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock placeholderGlyph;
    private readonly TextBlock placeholderText = new() { FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Color.FromArgb(217, 255, 255, 255)), TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(16, 8, 16, 0) };
    private readonly Ellipse chipDot = new() { Width = 7, Height = 7, Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock chipText = new() { Foreground = Brushes.White, FontSize = 11, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
    private readonly ContentControl detail = new() { Margin = new Thickness(0, 12, 0, 0), Focusable = false };
    private readonly Button permission;
    private readonly StackPanel devicePanel = new() { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 0) };
    private readonly ComboBox devicePicker = new() { MinWidth = 260 };
    private CaptureCardCapture? probe;
    private IReadOnlyList<CaptureCardInfo> devices = [];
    private CaptureCardStatus status = CaptureCardStatus.Stopped;
    private bool loadingDevices;

    public CaptureCardCheck(AppController controller, double previewHeight = 220)
    {
        this.controller = controller;
        placeholderGlyph = CardUi.Glyph(CardUi.Cable, 30, "onAccentBrush");
        placeholderGlyph.Foreground = placeholderText.Foreground;
        placeholderGlyph.HorizontalAlignment = HorizontalAlignment.Center;
        placeholder.Children.Add(placeholderGlyph);
        placeholder.Children.Add(placeholderText);

        var chip = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(128, 0, 0, 0)), CornerRadius = new CornerRadius(12), Height = 24,
            Padding = new Thickness(10, 0, 10, 0), Margin = new Thickness(10), HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top, Child = new StackPanel { Orientation = Orientation.Horizontal, Children = { chipDot, chipText } },
        };
        var screen = new Grid { Children = { surface, placeholder, chip } };
        var frame = new Border { Background = Brushes.Black, Height = previewHeight, ClipToBounds = true, Child = screen };
        frame.SetResourceReference(Border.CornerRadiusProperty, "radius.control");
        // Köşeler yuvarlak kalsın (görüntü köşeden taşmasın).
        frame.SizeChanged += (_, _) => frame.Clip = new RectangleGeometry(new Rect(0, 0, frame.ActualWidth, frame.ActualHeight), 14, 14);
        RightToLeft.KeepLeftToRight(frame);

        permission = CardUi.Button(CardUi.T("Open Camera Settings"), "SecondaryButton", (_, _) => OpenPrivacy());
        permission.Margin = new Thickness(0, 12, 0, 0);
        var deviceLabel = CardUi.Text(CardUi.T("Capture device"), "BodyText");
        deviceLabel.VerticalAlignment = VerticalAlignment.Center;
        deviceLabel.Margin = new Thickness(0, 0, 12, 0);
        devicePanel.Children.Add(deviceLabel);
        devicePanel.Children.Add(devicePicker);
        devicePicker.SelectionChanged += (_, _) => OnDeviceChosen();

        Content = new StackPanel { Children = { frame, detail, permission, devicePanel } };
        Loaded += (_, _) =>
        {
            controller.PropertyChanged += OnControllerChanged;
            StartProbe();
        };
        Unloaded += (_, _) =>
        {
            controller.PropertyChanged -= OnControllerChanged;
            StopProbe();
        };
        Show();
    }

    private bool Busy => controller.IsRunning || controller.IsStarting;

    private void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is not (nameof(AppController.IsRunning) or nameof(AppController.IsStarting))) return;
        // Çeviri başlarken kart hemen bırakılır (kart aynı anda tek okuyucuya açılır); bitince önizleme geri gelir.
        if (Busy) StopProbe();
        else StartProbe();
    }

    private void StartProbe()
    {
        if (probe is not null || Busy)
        {
            Show();
            return;
        }
        var capture = new CaptureCardCapture { PreferredId = controller.PreferredCardId, VideoSink = surface };
        capture.StatusChanged += next => Dispatcher.BeginInvoke(() =>
        {
            if (probe != capture) return;
            status = next;
            Show();
        });
        capture.DevicesChanged += () => Dispatcher.BeginInvoke(() =>
        {
            if (probe == capture) _ = LoadDevicesAsync();
        });
        probe = capture;
        status = CaptureCardStatus.Stopped;
        capture.Start();
        _ = LoadDevicesAsync();
        Show();
    }

    private void StopProbe()
    {
        if (probe is null) return;
        probe.VideoSink = null;
        probe.Stop();
        probe = null;
        status = CaptureCardStatus.Stopped;
        surface.Clear();
        Show();
    }

    private async Task LoadDevicesAsync()
    {
        devices = await CaptureCardCapture.VideoDevicesAsync();
        loadingDevices = true;
        devicePicker.Items.Clear();
        devicePicker.Items.Add(new ComboBoxItem { Content = CardUi.T("Automatic"), Tag = "" });
        foreach (var device in devices) devicePicker.Items.Add(new ComboBoxItem { Content = device.Name, Tag = device.Id });
        var chosen = controller.PreferredCardId ?? "";
        devicePicker.SelectedItem = devicePicker.Items.Cast<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == chosen) ?? devicePicker.Items[0];
        loadingDevices = false;
        Show();
    }

    private void OnDeviceChosen()
    {
        if (loadingDevices || devicePicker.SelectedItem is not ComboBoxItem { Tag: string id }) return;
        controller.PreferredCardId = id.Length == 0 ? null : id;
        if (probe is null) return;
        probe.PreferredId = controller.PreferredCardId;
        surface.Clear();
        probe.Refresh();
    }

    private static void OpenPrivacy()
    {
        try { Process.Start(new ProcessStartInfo("ms-settings:privacy-webcam") { UseShellExecute = true }); }
        catch (Exception error) { SubtitleLog.Write($"kamera ayarları açılamadı: {error.Message}"); }
    }

    private void Show()
    {
        var running = Busy;
        var state = status.State;
        var tone = state switch
        {
            CaptureCardState.Capturing => StatusTone.Good,
            CaptureCardState.Stopped => StatusTone.Idle,
            _ => StatusTone.Warning,
        };
        chipDot.SetResourceReference(Shape.FillProperty, tone switch
        {
            StatusTone.Good => "successBrush",
            StatusTone.Warning => "warningBrush",
            _ => "textSecondaryBrush",
        });
        chipText.Text = status.HasPicture ? status.Name ?? "" : CardUi.T(state == CaptureCardState.NeedsPermission ? "No permission" : "No card found");
        // Kart görüntü veriyorsa (siyah da olsa) önizlemenin üstüne yazı konmaz.
        placeholder.Visibility = status.HasPicture && !running ? Visibility.Collapsed : Visibility.Visible;
        placeholderGlyph.Text = state == CaptureCardState.NeedsPermission ? CardUi.Lock : CardUi.Cable;
        placeholderText.Text = running ? CardUi.T("The live preview is off while translating.")
            : CardUi.T(state == CaptureCardState.NeedsPermission ? "Camera permission needed" : "Looking for your capture card…");
        if (running) chipText.Text = controller.CardStatus.Name ?? CardUi.T("Capture card");

        string? message = running ? null : state switch
        {
            CaptureCardState.Capturing => "The card is working. You can see the PS5 picture.",
            CaptureCardState.BlackPicture => "The card is connected but the picture is black. Turn the PS5 on and turn off HDCP (previous step).",
            CaptureCardState.NeedsPermission => "Capture cards appear as a camera in Windows. In Settings › Privacy & security › Camera, turn on camera access and Let desktop apps access your camera, then try again.",
            CaptureCardState.NoCard => "Plug the card into a USB 3 port on this computer. If you use a hub, try a port on the computer itself.",
            _ => null,
        };
        detail.Content = message is null ? null
            : CardUi.Label(tone == StatusTone.Good ? Glyphs.Check : Glyphs.Warning, CardUi.T(message), tone == StatusTone.Good ? "successBrush" : "warningBrush");
        detail.Visibility = message is null ? Visibility.Collapsed : Visibility.Visible;
        permission.Visibility = !running && state == CaptureCardState.NeedsPermission ? Visibility.Visible : Visibility.Collapsed;
        devicePanel.Visibility = devices.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
        devicePanel.IsEnabled = !running;
    }
}

/// <summary>
/// Yakalama kartı kurulum rehberi: 1) nasıl bağlanacağı, 2) PS5'te HDCP, 3) kartı takıp görüntüyü görmek. Kurulum
/// sihirbazında (PS5 adımlarının yerine) ve ayarlarda ayrı bir pencerede açılır.
/// </summary>
public sealed class CaptureCardGuide : UserControl
{
    private const int Pages = 3;
    private readonly AppController controller;
    private readonly bool inWindow;
    private readonly Action? close;
    private readonly ContentControl pageHost = new() { Focusable = false };
    private readonly StackPanel dots = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private readonly Button back;
    private readonly Button next;
    private int page;
    private bool toTv;

    /// <param name="close">Ayarlardaki pencerede: rehber bitince ya da vazgeçilince pencereyi kapatır. Sihirbazda null.</param>
    public CaptureCardGuide(AppController controller, Action? close = null)
    {
        this.controller = controller;
        this.close = close;
        inWindow = close is not null;
        toTv = controller.UsesCaptureCard && controller.ShowsOnTv;

        back = CardUi.Button("", "GhostButton", (_, _) => Back());
        back.SetResourceReference(MinHeightProperty, "size.buttonLarge");
        back.MinWidth = 120;
        next = CardUi.Button("", "PrimaryButton", (_, _) => Next());
        next.SetResourceReference(MinHeightProperty, "size.buttonLarge");
        next.MinWidth = 200;
        next.IsDefault = true;
        next.HorizontalAlignment = HorizontalAlignment.Right;
        var buttons = new Grid { Margin = new Thickness(0, 16, 0, 0), Children = { dots, back, next } };
        DockPanel.SetDock(buttons, Dock.Bottom);

        var card = new Card
        {
            Padding = new Thickness(0),
            Content = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = new Border { Padding = new Thickness(32), Child = pageHost } },
        };
        Content = new DockPanel { LastChildFill = true, Children = { buttons, card } };
        ShowPage(animate: false);
    }

    private void Back()
    {
        if (page > 0)
        {
            page--;
            ShowPage();
        }
        else if (inWindow) close!();
        else controller.CancelCaptureCardSetup();
    }

    private void Next()
    {
        if (page < Pages - 1)
        {
            page++;
            ShowPage();
            return;
        }
        controller.FinishCaptureCardSetup(toTv);
        close?.Invoke();
    }

    private void ShowPage(bool animate = true)
    {
        var content = page switch
        {
            0 => LayoutPage(),
            1 => HdcpPage(),
            _ => CheckPage(),
        };
        pageHost.Content = content;
        if (animate)
        {
            // Yeni sayfa yandan kayarak ve belirerek gelir (Arapçada öteki yandan).
            var shift = new TranslateTransform(RightToLeft.Interface ? -28 : 28, 0);
            content.RenderTransform = shift;
            var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
            shift.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(320)) { EasingFunction = ease });
            content.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(260)));
        }
        back.Content = CardUi.T(page == 0 && inWindow ? "Cancel" : "Back");
        next.Content = CardUi.T(page < Pages - 1 ? "Continue" : "Done");
        dots.Children.Clear();
        for (var i = 0; i < Pages; i++)
        {
            var dot = new Border { Width = i == page ? 24 : 7, Height = 7, CornerRadius = new CornerRadius(3.5), Margin = new Thickness(3.5, 0, 3.5, 0) };
            if (i <= page) dot.SetResourceReference(Border.BackgroundProperty, "accentBrush");
            else dot.SetResourceReference(Border.BackgroundProperty, "borderBrush");
            dots.Children.Add(dot);
        }
        System.Windows.Automation.AutomationProperties.SetName(dots, Localizer.Current.Format("Step %lld of %lld", page + 1, Pages));
    }

    // MARK: Sayfalar

    private FrameworkElement LayoutPage()
    {
        var tiles = new StackPanel();
        tiles.Children.Add(Choice(!toTv, CardUi.T("Monitor or a TV without apps"),
            CardUi.T("Nino shows the game full screen on this computer with its sound, and the translation on top. Connect the computer to the screen with HDMI."),
            [Glyphs.Controller, CardUi.Cable, CardUi.Laptop, CardUi.Monitor], () => Choose(false)));
        var smart = Choice(toTv, CardUi.T("Smart TV with the Nino app"),
            CardUi.T("Needs a card with HDMI out (passthrough). The game goes straight to the TV with no extra delay; Nino reads the card and sends the translation to the TV app."),
            [Glyphs.Controller, CardUi.Cable, Glyphs.Tv], () => Choose(true));
        smart.Margin = new Thickness(0, 12, 0, 0);
        tiles.Children.Add(smart);
        return new StepLayout
        {
            Title = CardUi.T("How is your PS5 connected?"),
            Message = CardUi.T("A capture card takes the PS5 picture over HDMI and gives it to this computer over USB. No second PSN account or Remote Play needed."),
            Content = tiles,
        };
    }

    private void Choose(bool tv)
    {
        if (toTv == tv) return;
        toTv = tv;
        pageHost.Content = LayoutPage();
    }

    private static FrameworkElement HdcpPage()
    {
        var rows = new StackPanel();
        rows.Children.Add(new NumberedRow { Number = 1, Text = CardUi.T("Connect the PS5 directly to a TV or monitor for a moment (the setting can't be changed through the card).") });
        rows.Children.Add(new NumberedRow { Number = 2, Text = CardUi.T("On the PS5, open Settings › System › HDMI.") });
        rows.Children.Add(new NumberedRow { Number = 3, Text = CardUi.T("Turn off Enable HDCP. Then connect the PS5 to the card's HDMI in.") });
        var netflix = CardUi.Label(CardUi.Info, CardUi.T("While HDCP is off, video apps like Netflix don't play on the PS5. Turn it back on to watch them."), "textSecondaryBrush");
        netflix.Margin = new Thickness(0, 8, 0, 12);
        rows.Children.Add(netflix);
        rows.Children.Add(CardUi.Label(CardUi.Headphone, CardUi.T("If a headset is plugged into the controller, the PS5 sends the sound there and the card gets no sound."), "textSecondaryBrush"));
        return new StepLayout
        {
            Title = CardUi.T("Turn off HDCP on the PS5"),
            Message = CardUi.T("The PS5 blocks capture cards with a copy protection called HDCP. Games are not affected; you only do this once."),
            Content = rows,
        };
    }

    private FrameworkElement CheckPage() => new StepLayout
    {
        Title = CardUi.T("Plug in the card"),
        Message = CardUi.T(toTv
            ? "Connect PS5 → card HDMI in, card HDMI out → TV, and the card's USB → this computer."
            : "Connect PS5 → card HDMI in, and the card's USB → this computer. Then connect this computer to your screen."),
        Content = new CaptureCardCheck(controller),
    };

    /// <summary>Bağlantı seçeneği: seçim halkası, başlık, açıklama ve kablo şeması (PS5 → kart → …).</summary>
    private static Button Choice(bool selected, string title, string detail, string[] chain, Action choose)
    {
        var ring = CardUi.Glyph(selected ? CardUi.CircleFill : CardUi.Circle, 22, selected ? "accentBrush" : "textSecondaryBrush");
        ring.VerticalAlignment = VerticalAlignment.Top;
        ring.Margin = new Thickness(0, 0, 16, 0);
        var heading = CardUi.Text(title, "HeadlineText");
        var description = CardUi.Text(detail, "HintText");
        description.Margin = new Thickness(0, 6, 0, 0);
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 0) };
        for (var i = 0; i < chain.Length; i++)
        {
            if (i > 0)
            {
                var arrow = CardUi.Text(RightToLeft.Interface ? "←" : "→", "CaptionText");
                arrow.VerticalAlignment = VerticalAlignment.Center;
                arrow.Margin = new Thickness(8, 0, 8, 0);
                row.Children.Add(arrow);
            }
            var icon = CardUi.Glyph(chain[i], 16, "accentTextBrush");
            icon.HorizontalAlignment = HorizontalAlignment.Center;
            var box = new Border { Width = 36, Height = 30, CornerRadius = new CornerRadius(8), Child = icon };
            box.SetResourceReference(Border.BackgroundProperty, "accentSoftBrush");
            row.Children.Add(box);
        }
        var text = new StackPanel { Children = { heading, description, row } };
        var body = new DockPanel();
        DockPanel.SetDock(ring, Dock.Left);
        body.Children.Add(ring);
        body.Children.Add(text);
        var tile = new Card { Kind = selected ? TileKind.Active : TileKind.Normal, Content = body };
        var button = CardUi.Plain(tile, (_, _) => choose());
        System.Windows.Automation.AutomationProperties.SetName(button, title);
        System.Windows.Automation.AutomationProperties.SetItemStatus(button, selected ? "selected" : "");
        return button;
    }
}

/// <summary>Ayarlardan açılan rehber penceresi (rehber bitince yalnız seçim kaydedilir).</summary>
public sealed class CaptureCardGuideWindow : Window
{
    private CaptureCardGuideWindow(AppController controller)
    {
        Title = CardUi.T("Connection guide");
        Width = 760;
        Height = 760;
        MinWidth = 620;
        MinHeight = 560;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        SetResourceReference(BackgroundProperty, "windowBackgroundBrush");
        SetResourceReference(ForegroundProperty, "textPrimaryBrush");
        var guide = new CaptureCardGuide(controller, Close);
        guide.SetResourceReference(MarginProperty, "pad.screen");
        Content = guide;
    }

    public static void Open(Window? owner, AppController controller) =>
        new CaptureCardGuideWindow(controller) { Owner = owner }.ShowDialog();
}
