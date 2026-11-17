// SPDX-License-Identifier: AGPL-3.0-only

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views;

/// <summary>Altyazının yeri (TV, bilgisayar ekranı, ikisi) ve bilgisayar ekranındaki pencerenin seçenekleri.</summary>
public partial class SubtitleOutputCard : UserControl
{
    private AppController? controller;
    private bool loading;
    private bool subscribed;

    public SubtitleOutputCard()
    {
        InitializeComponent();
        // Ayarlardaki bölümler değişince kart görsel ağaçtan çıkıp yeniden girer; abonelik buna göre açılıp kapanır.
        Loaded += (_, _) => Subscribe();
        Unloaded += (_, _) =>
        {
            if (controller is not null && subscribed) controller.PropertyChanged -= OnChanged;
            subscribed = false;
        };
    }

    private void Subscribe()
    {
        if (controller is null || subscribed) return;
        controller.PropertyChanged += OnChanged;
        subscribed = true;
        Refresh();
    }

    /// <summary>Ayarlarda açıklamalar da gösterilir; ana ekranda kart kısa kalır.</summary>
    public bool Detailed { get; set; }

    internal void Attach(AppController attached)
    {
        controller = attached;
        Subscribe();
    }

    private void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AppController.Settings) or nameof(AppController.OverlayAdjusting) or nameof(AppController.IsRunning)) Refresh();
    }

    private void Refresh()
    {
        if (controller is null) return;
        loading = true;
        var settings = controller.Settings;
        (settings.Output switch { SubtitleOutput.Computer => OutputComputer, SubtitleOutput.Both => OutputBoth, _ => OutputTv }).IsChecked = true;
        // Nino: Xbox'ta PS5'e doğrudan bağlanma yok; pencere seçeneği "Xbox penceresi" olur (Windows'ta Greenlight anılmaz).
        var xbox = settings.GameConsole == GameConsole.Xbox;
        (xbox ? ConsoleXbox : ConsolePs5).IsChecked = true;
        SourcePs5.Visibility = xbox ? Visibility.Collapsed : Visibility.Visible;
        SourceWindow.Content = Localizer.Current[xbox ? "Xbox window" : "Remote Play window"];
        (controller.UsesGameWindow ? SourceWindow : controller.UsesCaptureCard ? SourceCard : SourcePs5).IsChecked = true;
        var ps5 = controller.Settings.VideoSource == VideoSource.Ps5;
        SourceHint.Text = Localizer.Current[controller.UsesCaptureCard
            ? "Connect the PS5 to the capture card and the card to this computer. No second account needed. Turn off Settings › System › HDMI › Enable HDCP on the PS5."
            : ps5 ? "Subtitles show on your TV, in the Nino TV app."
            : xbox ? "Start Remote play in the Xbox app or at xbox.com/play. Nino reads that window and shows the translation."
            : "Play in PS Remote Play or chiaki-ng on this computer. Nino reads that window and shows the translation on top of the game. No second account needed."];
        SourceHint.Visibility = Detailed || controller.UsesGameWindow || ps5 ? Visibility.Visible : Visibility.Collapsed;
        ShowCard();
        // Oyun bu bilgisayardaysa altyazı her zaman pencerenin üstündedir; TV seçimi gösterilmez.
        // Nino: PS5 yolunda altyazı her zaman TV uygulamasındadır; yer seçimi yalnız Capture Card'da gösterilir.
        OutputCaption.Visibility = OutputGroup.Visibility = controller.UsesCaptureCard ? Visibility.Visible : Visibility.Collapsed;
        ComputerPanel.Visibility = controller.ShowsOnComputer ? Visibility.Visible : Visibility.Collapsed;
        WindowHint.Visibility = Detailed ? Visibility.Visible : Visibility.Collapsed;
        ClickThrough.IsChecked = settings.OverlayClickThrough;
        ClickThroughHint.Visibility = Detailed || settings.OverlayClickThrough ? Visibility.Visible : Visibility.Collapsed;
        ClickThroughHint.Text = HotkeyText.Sentence(settings, HotkeyAction.ClickThrough,
            "When on, clicks go through to the window below. Press %@ to turn it off.");
        Adjust.IsEnabled = !controller.OverlayAdjusting;
        loading = false;
    }

    /// <summary>Nino: Capture Card seçiliyse düzenin tek satırlık açıklaması, ayarlarda canlı önizleme ve bağlantı rehberi.</summary>
    private void ShowCard()
    {
        var card = controller!.UsesCaptureCard;
        CardPanel.Visibility = card ? Visibility.Visible : Visibility.Collapsed;
        if (!card)
        {
            CardPreview.Content = null;
            return;
        }
        CardLayoutHint.Text = Localizer.Current[controller.ShowsOnTv
            ? "TV: the PS5 picture goes to the TV through the card's HDMI out. Nino reads the card and sends the translation to the TV app."
            : "Computer: Nino shows the game full screen with its sound and the translation on top. Connect this computer to your TV or monitor."];
        // Kart tek okuyucuya açılır: çeviri sürerken önizleme açılmaz (önizleme bunu kendisi de bilir).
        var preview = Detailed && !controller.IsRunning;
        if (preview && CardPreview.Content is null) CardPreview.Content = new CaptureCardCheck(controller, previewHeight: 170);
        else if (!preview) CardPreview.Content = null;
        CardPreview.Visibility = preview ? Visibility.Visible : Visibility.Collapsed;
        CardGuide.IsEnabled = !controller.IsRunning;
    }

    private void OnCardGuide(object sender, RoutedEventArgs e)
    {
        if (controller is null) return;
        // Rehberin önizlemesi kartı açar; bu kartın önizlemesi o sırada bırakılır.
        CardPreview.Content = null;
        CaptureCardGuideWindow.Open(Window.GetWindow(this), controller);
        Refresh();
    }

    private void OnConsole(object sender, RoutedEventArgs e)
    {
        if (loading || controller is null || sender is not RadioButton { Tag: string tag }) return;
        controller.SwitchConsole(Enum.Parse<GameConsole>(tag));
    }

    private void OnSource(object sender, RoutedEventArgs e)
    {
        if (loading || controller is null || sender is not RadioButton { Tag: string tag }) return;
        controller.Settings = controller.Settings with { VideoSource = Enum.Parse<VideoSource>(tag) };
    }

    private void OnOutput(object sender, RoutedEventArgs e)
    {
        if (loading || controller is null || sender is not RadioButton { Tag: string tag }) return;
        controller.Settings = controller.Settings with { Output = Enum.Parse<SubtitleOutput>(tag) };
    }

    private void OnClickThrough(object sender, RoutedEventArgs e)
    {
        if (loading || controller is null) return;
        controller.Settings = controller.Settings with { OverlayClickThrough = ClickThrough.IsChecked == true };
    }

    private void OnAdjust(object sender, RoutedEventArgs e)
    {
        if (controller is not null) controller.OverlayAdjusting = true;
    }
}
