// SPDX-License-Identifier: AGPL-3.0-only
// Nino: Ayarlar › Hakkında › Sorun Bildir (Mac'teki ile aynı alanlar ve metinler). Kodla kurulur.

using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using CouchSubs.App.Services;
using CouchSubs.Core;
using CouchSubs.Shell;
using Image = System.Windows.Controls.Image;
using TextBox = System.Windows.Controls.TextBox;

namespace CouchSubs.App.Views;

/// <summary>
/// Açıklama (zorunlu), en çok 3 fotoğraf (dosya seçici, sürükle-bırak ya da Ctrl+V ile ekran görüntüsü), isteğe bağlı
/// iletişim bilgisi ve "Uygulama günlüğünü ekle" (varsayılan açık). Gönderim başarılıysa teşekkür edip kapanır; olmazsa
/// form olduğu gibi kalır ve yeniden denenebilir. İstek <see cref="ProblemReport"/>'ta kurulur.
/// </summary>
public sealed class ReportProblemWindow : Window
{
    private sealed record Photo(BitmapSource Picture, byte[] Jpeg);

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(60) };
    private static string T(string key) => Localizer.Current[key];

    private readonly AppController controller;
    private readonly List<Photo> photos = [];
    private readonly TextBox description = new()
    {
        AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, Height = 140, MaxLength = ProblemReport.MaxText,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalContentAlignment = VerticalAlignment.Top, Padding = new Thickness(12, 10, 12, 10),
    };
    private readonly TextBox contact = new() { MaxLength = ProblemReport.MaxContact };
    private readonly CheckBox includeLog = new() { IsChecked = true, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(16, 0, 0, 0) };
    private readonly WrapPanel photoRow = new();
    private readonly Button addPhoto = new() { Width = 88, Height = 88, Margin = new Thickness(0, 0, 8, 8) };
    private readonly TextBlock error = new() { TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed, Margin = new Thickness(0, 12, 0, 0) };
    private readonly ProgressBar progress = new() { IsIndeterminate = true, Height = 3, Margin = new Thickness(0, 12, 0, 0), Visibility = Visibility.Collapsed };
    private readonly Button send = new() { Content = T("Send"), MinWidth = 120, IsEnabled = false };
    private readonly Button cancel = new() { Content = T("Cancel"), MinWidth = 100, Margin = new Thickness(0, 0, 12, 0), IsCancel = true };
    private bool sending;

    private ReportProblemWindow(AppController controller)
    {
        this.controller = controller;
        Title = T("Report a Problem");
        Width = 540;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        AllowDrop = true;
        SetResourceReference(BackgroundProperty, "windowBackgroundBrush");
        SetResourceReference(ForegroundProperty, "textPrimaryBrush");

        var title = new TextBlock { Text = T("Report a Problem"), Margin = new Thickness(0, 0, 0, 16) };
        title.SetResourceReference(StyleProperty, "TitleText");

        // Çok satırlı kutu: temadaki şablon metni dikeyde ortalar; yazı yukarıdan başlasın.
        description.Loaded += (_, _) =>
        {
            if (description.Template?.FindName("PART_ContentHost", description) is FrameworkElement host) host.VerticalAlignment = VerticalAlignment.Stretch;
        };
        description.TextChanged += (_, _) => send.IsEnabled = !sending && ProblemReport.CanSend(description.Text);
        var descriptionPrompt = T("What happened? Which game, what did you expect?");
        AutomationNamed(description, descriptionPrompt);
        AutomationNamed(contact, T("How can we reach you? (optional)"));

        addPhoto.SetResourceReference(StyleProperty, "SecondaryButton");
        addPhoto.Content = new TextBlock { Text = "+", FontSize = 28, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        addPhoto.ToolTip = T("Add photo");
        AutomationNamed(addPhoto, T("Add photo"));
        addPhoto.Click += (_, _) => PickPhotos();
        var photoHint = Hint(T("Up to 3 photos. You can also drag images here or paste a screenshot with Ctrl+V."));

        var logTitle = new TextBlock { Text = T("Include app log") };
        logTitle.SetResourceReference(StyleProperty, "HeadlineText");
        var logRow = new DockPanel { Margin = new Thickness(0, 16, 0, 0) };
        DockPanel.SetDock(includeLog, Dock.Right);
        AutomationNamed(includeLog, T("Include app log"));
        logRow.Children.Add(includeLog);
        logRow.Children.Add(new StackPanel { VerticalAlignment = VerticalAlignment.Center, Children = { logTitle, Hint(T("Helps us find the problem. No passwords or keys are included.")) } });

        var privacy = Hint(T("Your description, photos and (if on) the app log are sent to Nino's server so we can fix the problem. Don't include passwords."));
        privacy.SetResourceReference(StyleProperty, "CaptionText");
        privacy.Margin = new Thickness(0, 16, 0, 0);
        error.SetResourceReference(StyleProperty, "ErrorText");

        send.SetResourceReference(StyleProperty, "PrimaryButton");
        send.IsDefault = false; // Enter açıklamada yeni satır açar.
        send.Click += async (_, _) => await SendAsync();
        cancel.Click += (_, _) => Close();

        Content = new StackPanel
        {
            Margin = new Thickness(28),
            Children =
            {
                title,
                WithPlaceholder(description, descriptionPrompt),
                new StackPanel { Margin = new Thickness(0, 16, 0, 0), Children = { photoRow, photoHint } },
                WithPlaceholder(contact, T("How can we reach you? (optional)"), new Thickness(0, 16, 0, 0)),
                logRow,
                privacy,
                error,
                progress,
                new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 20, 0, 0), Children = { cancel, send } },
            },
        };
        ShowPhotos();

        // Sürükle-bırak: metin kutusu dosyayı kendisi almasın diye önizleme olaylarında karşılanır.
        PreviewDragOver += OnDragOver;
        PreviewDragEnter += OnDragOver;
        PreviewDrop += OnDrop;
        // Ctrl+V: panoda görüntü ya da dosya varsa fotoğraf olarak eklenir, yoksa metin kutusu metni yapıştırır.
        InputBindings.Add(new KeyBinding(ApplicationCommands.Paste, Key.V, ModifierKeys.Control));
        CommandManager.AddPreviewCanExecuteHandler(this, OnCanPaste);
        CommandManager.AddPreviewExecutedHandler(this, OnPaste);
        Loaded += (_, _) => description.Focus();
    }

    public static void Open(Window? owner, AppController controller) => OwnedWindow.Show(owner, () => new ReportProblemWindow(controller));

    private static void AutomationNamed(DependencyObject element, string name) =>
        System.Windows.Automation.AutomationProperties.SetName(element, name);

    private static TextBlock Hint(string text)
    {
        var block = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) };
        block.SetResourceReference(StyleProperty, "HintText");
        return block;
    }

    /// <summary>Kutu boşken soluk yer tutucu yazı (temadaki TextBox'ta yok).</summary>
    internal static Grid WithPlaceholder(TextBox box, string text, Thickness margin = default)
    {
        var placeholder = new TextBlock
        {
            Text = text, IsHitTestVisible = false, TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(box.Padding.Left + 3, box.AcceptsReturn ? box.Padding.Top + 1 : 0, box.Padding.Right, 0),
            VerticalAlignment = box.AcceptsReturn ? VerticalAlignment.Top : VerticalAlignment.Center,
        };
        placeholder.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        placeholder.Opacity = 0.75;
        box.TextChanged += (_, _) => placeholder.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        return new Grid { Margin = margin, Children = { box, placeholder } };
    }

    // --- Fotoğraflar ---

    private void ShowPhotos()
    {
        photoRow.Children.Clear();
        foreach (var photo in photos)
        {
            var picture = new Image { Source = photo.Picture, Stretch = Stretch.UniformToFill, Width = 88, Height = 88 };
            RenderOptions.SetBitmapScalingMode(picture, BitmapScalingMode.HighQuality);
            var frame = new Border { Width = 88, Height = 88, CornerRadius = new CornerRadius(12), ClipToBounds = true, BorderThickness = new Thickness(1), Child = picture };
            frame.SetResourceReference(Border.BorderBrushProperty, "borderBrush");
            // Köşeler gerçekten yuvarlak kesilsin.
            frame.Clip = new RectangleGeometry(new Rect(0, 0, 88, 88), 12, 12);
            var remove = new Button
            {
                Content = "✕", Width = 26, Height = 26, MinHeight = 0, Padding = new Thickness(0), FontSize = 12,
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 4, 4, 0),
                ToolTip = T("Remove photo"),
            };
            remove.SetResourceReference(StyleProperty, "SecondaryButton");
            AutomationNamed(remove, T("Remove photo"));
            var current = photo;
            remove.Click += (_, _) => { photos.Remove(current); ShowPhotos(); };
            photoRow.Children.Add(new Grid { Margin = new Thickness(0, 0, 8, 8), Children = { frame, remove } });
        }
        if (photos.Count < ProblemReport.MaxImages) photoRow.Children.Add(addPhoto);
    }

    private void PickPhotos()
    {
        var picker = new Microsoft.Win32.OpenFileDialog
        {
            Title = T("Add photo"),
            Multiselect = true,
            Filter = $"{T("Images")}|*.png;*.jpg;*.jpeg;*.heic;*.heif;*.webp;*.bmp;*.gif;*.tif;*.tiff",
        };
        if (picker.ShowDialog(this) == true) _ = AddAsync(picker.FileNames.Select(path => (Func<BitmapSource?>)(() => ReportImages.Load(path))));
    }

    /// <summary>Görüntüleri sırayla açar (arayüz iş parçacığında), JPEG'e çevirir (arka planda) ve ekler; en çok 3.</summary>
    private async Task AddAsync(IEnumerable<Func<BitmapSource?>> sources)
    {
        HideError();
        var failed = false;
        foreach (var open in sources)
        {
            if (photos.Count >= ProblemReport.MaxImages) break;
            try
            {
                if (open() is not { } picture) continue;
                var jpeg = await Task.Run(() => ReportImages.Jpeg(picture));
                if (jpeg is null) { failed = true; continue; }
                if (photos.Count >= ProblemReport.MaxImages) break;
                photos.Add(new Photo(picture, jpeg));
                ShowPhotos();
            }
            catch (Exception exception) when (exception is NotSupportedException or FileFormatException or IOException
                                              or UnauthorizedAccessException or ArgumentException or InvalidOperationException or COMException)
            {
                failed = true;
            }
        }
        if (failed) ShowError(T("This image could not be opened."));
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(DataFormats.FileDrop)) return;
        e.Effects = photos.Count < ProblemReport.MaxImages && !sending ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is not string[] files) return;
        e.Handled = true;
        if (sending) return;
        _ = AddAsync(files.Where(ReportImages.IsImageFile).Select(path => (Func<BitmapSource?>)(() => ReportImages.Load(path))));
    }

    private void OnCanPaste(object sender, CanExecuteRoutedEventArgs e)
    {
        if (e.Command != ApplicationCommands.Paste || !ReportImages.PastesPicture()) return;
        e.CanExecute = !sending && photos.Count < ProblemReport.MaxImages;
        e.Handled = true;
    }

    private void OnPaste(object sender, ExecutedRoutedEventArgs e)
    {
        if (e.Command != ApplicationCommands.Paste || !ReportImages.PastesPicture()) return;
        e.Handled = true;
        try { _ = AddAsync(ReportImages.FromClipboardSources()); }
        catch (COMException) { ShowError(T("This image could not be opened.")); }
    }

    // --- Gönderim ---

    private void ShowError(string text)
    {
        error.Text = text;
        error.Visibility = Visibility.Visible;
    }

    private void HideError() => error.Visibility = Visibility.Collapsed;

    private void SetSending(bool value)
    {
        sending = value;
        send.Content = value ? T("Sending…") : T("Send");
        send.IsEnabled = !value && ProblemReport.CanSend(description.Text);
        description.IsReadOnly = contact.IsReadOnly = value;
        includeLog.IsEnabled = addPhoto.IsEnabled = value is false;
        progress.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
        Cursor = value ? Cursors.AppStarting : null;
    }

    private async Task SendAsync()
    {
        if (sending || !ProblemReport.CanSend(description.Text)) return;
        HideError();
        if (ProblemReport.Endpoint(NinoPool.ConfiguredEndpoint(Path.Combine(AppPaths.Data, "pool"))) is not { } endpoint)
        {
            ShowError(T("The report could not be sent. Check your internet connection and try again."));
            return;
        }
        SetSending(true);
        var text = description.Text;
        var reach = contact.Text;
        var withLog = includeLog.IsChecked == true;
        var jpegs = photos.Select(photo => photo.Jpeg).ToList();
        var app = AppVersion.Current(Assembly.GetEntryAssembly() ?? typeof(ReportProblemWindow).Assembly);
        var language = controller.Settings.TargetLanguage;
        var poolInstall = controller.PoolInstallId;
        // Cihaz bilgileri (sürüm, bilgisayarın modeli, sistem, TV, konsol): ne kullanıldığı sorulmadan görülsün.
        var device = controller.DeviceSummary(app);
        ProblemReport.Result result;
        try
        {
            result = await Task.Run(async () =>
            {
                var log = withLog ? ProblemReport.CollectLogs(LogFiles()) : null;
                var install = ProblemReport.InstallId(poolInstall, Path.Combine(AppPaths.Data, "report-install.txt"));
                var payload = ProblemReport.Build(install, app, language, text, reach, log, jpegs, device);
                return await ProblemReport.SendAsync(Http, endpoint, payload);
            });
        }
        finally { SetSending(false); }
        // Gönderim sürerken pencere kapatıldıysa sonucu gösterecek yer yok.
        if (!IsVisible) return;

        switch (result.Outcome)
        {
            case ProblemReport.Outcome.Sent: ShowThanks(); break;
            case ProblemReport.Outcome.RateLimited: ShowError(T("You've sent many reports today. Please try again tomorrow.")); break;
            case ProblemReport.Outcome.TooLarge: ShowError(T("The report is too large. Remove a photo and try again.")); break;
            case ProblemReport.Outcome.Rejected: ShowError(T("The report was not accepted. Please check the description and try again.")); break;
            default: ShowError(T("The report could not be sent. Check your internet connection and try again.")); break;
        }
    }

    /// <summary>
    /// Uygulamanın kendi günlükleri (%LOCALAPPDATA%\Nino): hata.log (StartupGuard), remoteplay.log, altyazi.log
    /// (SubtitleLog) ve tvinstall.log; her birinin sonundan payı kadar. Toplam en çok 60 000 karakter.
    /// </summary>
    private static IEnumerable<(string Path, int Budget)> LogFiles() =>
    [
        (StartupGuard.LogPath, 10000),
        (Path.Combine(AppPaths.Data, "remoteplay.log"), 18000),
        (SubtitleLog.DefaultPath, 24000),
        (LiveServices.TvInstallLogPath, 8000),
    ];

    private void ShowThanks()
    {
        var check = new TextBlock { Text = "✓", FontSize = 40, HorizontalAlignment = HorizontalAlignment.Center };
        check.SetResourceReference(TextBlock.ForegroundProperty, "successBrush");
        var thanks = new TextBlock { Text = T("Thanks! We received your report."), TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 20) };
        thanks.SetResourceReference(StyleProperty, "HeadlineText");
        var close = new Button { Content = T("Close"), MinWidth = 120, HorizontalAlignment = HorizontalAlignment.Center, IsDefault = true, IsCancel = true };
        close.SetResourceReference(StyleProperty, "PrimaryButton");
        close.Click += (_, _) => Close();
        Content = new StackPanel { Margin = new Thickness(28, 36, 28, 28), Children = { check, thanks, close } };
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2.5) };
        timer.Tick += (_, _) => { timer.Stop(); if (IsVisible) Close(); };
        Closed += (_, _) => timer.Stop();
        timer.Start();
    }
}
