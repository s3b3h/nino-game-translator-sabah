// SPDX-License-Identifier: AGPL-3.0-only

using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using CouchSubs.App.Controls;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views;

/// <summary>
/// Nino ana ekranı (Mac ile aynı düzen): ortada seçili arayüz (1. Salon, 2. Cam düğme; Ayarlar › Arayüz), altında
/// uyarı kartları, en altta PS5 ve TV durumuyla Çeviri kısayolu.
/// </summary>
public partial class MainView : UserControl
{
    private readonly AppController controller;
    // Çeviri sürerken PS5 ve TV bağlanamıyorsa güvenlik duvarı kartı önerilir.
    private readonly DispatcherTimer connectionWatch = new() { Interval = TimeSpan.FromSeconds(5) };

    public MainView(AppController controller)
    {
        this.controller = controller;
        DataContext = controller;
        InitializeComponent();
        ShowHome();
        controller.PropertyChanged += OnChanged;
        connectionWatch.Tick += async (_, _) => await controller.CheckConnectionsAsync();
        Loaded += (_, _) => connectionWatch.Start();
        Unloaded += (_, _) =>
        {
            controller.PropertyChanged -= OnChanged;
            connectionWatch.Stop();
        };
        Refresh();
        ShowStrip();
        ShowUpdate();
        ShowGame();
        _ = controller.CheckForUpdateAsync();
    }

    private void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AppController.IsRunning) or nameof(AppController.TranslatorStatus) or nameof(AppController.ModelInstalled)
            or nameof(AppController.OnlineIssue) or nameof(AppController.CanStart) or nameof(AppController.IsStarting))
            Refresh();
        if (e.PropertyName is nameof(AppController.Settings))
        {
            ShowHome();
            ShowStrip();
        }
        if (e.PropertyName is nameof(AppController.Ps5StatusText) or nameof(AppController.Ps5Tone) or nameof(AppController.TvStatusText)
            or nameof(AppController.TvTone) or nameof(AppController.IsRunning) or nameof(AppController.SessionState)
            or nameof(AppController.ConsoleTitle) or nameof(AppController.TranslationSourceText))
            ShowStrip();
        // Nino: salon sahnesi konsola göre değişir (PS5'li ya da Xbox'lı görsel).
        if (e.PropertyName is nameof(AppController.IsXbox)) ShowHome();
        if (e.PropertyName is nameof(AppController.IsRunning) or nameof(AppController.PlayedGame) or nameof(AppController.AskingGame))
            ShowGame();
        if (e.PropertyName is nameof(AppController.UpdateVersion) or nameof(AppController.Updating)
            or nameof(AppController.UpdateProgress) or nameof(AppController.UpdateError))
            ShowUpdate();
    }

    private void ShowUpdate()
    {
        var text = Localizer.Current;
        UpdateCard.Visibility = controller.UpdateVersion is null ? Visibility.Collapsed : Visibility.Visible;
        UpdateTitle.Text = text["A new version of Nino is available: %@"].Replace("%@", controller.UpdateVersion ?? "");
        UpdateButton.Content = text[controller.CanUpdateItself ? "Update now" : "Download"];
        UpdateButton.IsEnabled = !controller.Updating;
        UpdateBar.Visibility = controller.Updating ? Visibility.Visible : Visibility.Collapsed;
        UpdateBar.Value = controller.UpdateProgress;
        UpdateErrorText.Text = controller.UpdateError ?? "";
        UpdateErrorText.Visibility = controller.UpdateError is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private (HomeStyle style, bool xbox)? shownHome;

    /// <summary>
    /// Ayarlardaki arayüz: Salon ya da Cam düğme (değişince yeniden kurulur). Salon sahnesi konsol değişince de yeniden
    /// kurulur (Xbox'lı salonun görseli ve ölçüleri ayrıdır).
    /// </summary>
    private void ShowHome()
    {
        var style = controller.Settings.HomeStyle;
        var wanted = (style, xbox: style == HomeStyle.LivingRoom && Home.XboxScene(controller));
        if (shownHome == wanted) return;
        shownHome = wanted;
        HomeHost.Content = style == HomeStyle.LivingRoom ? new LivingRoomScene(controller) : new GlassToggleView(controller);
    }

    /// <summary>
    /// Alt şerit: PS5 ve TV (renkli nokta ve kısa durum), sağda o an kullanılan çeviri (GTA 6 tanınınca Nino'nun havuzu,
    /// yoksa seçili motor; <see cref="AppController.TranslationSourceText"/>).
    /// </summary>
    private void ShowStrip()
    {
        var text = Localizer.Current;
        EngineValue.Text = controller.TranslationSourceText;
        // Çeviri kapalıyken eşleşmiş PS5 için kısa yazı (uzun durum yazısı şeride sığmıyordu).
        Ps5Label.Text = controller.UsesGameWindow ? text["Game window"] : controller.UsesCaptureCard ? text["Capture card"] : controller.ConsoleTitle;
        var pairedPs5 = controller.Settings.VideoSource == VideoSource.Ps5 && !controller.IsXbox && controller.Settings.FrameSource == FrameSource.Ps5;
        Ps5Value.Text = pairedPs5 && !controller.IsRunning && controller.Console is { } console
            ? text["%@ · ready"].Replace("%@", string.IsNullOrEmpty(console.Name) ? "PS5" : console.Name)
            : controller.Ps5StatusText;
        Ps5Dot.Fill = ToneBrush(controller.Ps5Tone);
        var tvVisible = controller.ShowsOnTv;
        TvDot.Visibility = TvText.Visibility = tvVisible ? Visibility.Visible : Visibility.Collapsed;
        TvValue.Text = controller.HasTv ? controller.TvStatusText : text["Connect a TV"] + " ›";
        TvDot.Fill = controller.HasTv ? ToneBrush(controller.TvTone) : (System.Windows.Media.Brush)FindResource("warningBrush");
    }

    private System.Windows.Media.Brush ToneBrush(StatusTone tone) => (System.Windows.Media.Brush)FindResource(tone switch
    {
        StatusTone.Good => "successBrush",
        StatusTone.Warning => "warningBrush",
        _ => "textSecondaryBrush",
    });

    /// <summary>TV kurulmamışsa şeritteki TV yazısı sihirbazın TV adımını açar.</summary>
    private void OnTvClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (!controller.HasTv) controller.Step = OnboardingStep.Tv;
    }

    private async void OnUpdate(object sender, RoutedEventArgs e) => await controller.InstallUpdateAsync();

    private void Refresh()
    {
        var running = controller.IsRunning;
        ModelCard.Visibility = controller.ModelInstalled ? Visibility.Collapsed : Visibility.Visible;
        EngineCard.Visibility = controller.TranslatorStatus == TranslatorStatus.EngineFailed ? Visibility.Visible : Visibility.Collapsed;
        LanguageCard.Visibility = controller.TranslatorStatus == TranslatorStatus.Unsupported ? Visibility.Visible : Visibility.Collapsed;
        // Çevrimiçi motor çeviremiyor; satırlar bu arada cihaz üstü modelle geliyor.
        var issue = running ? controller.OnlineIssue : null;
        OnlineCard.Visibility = issue is null ? Visibility.Collapsed : Visibility.Visible;
        if (issue is { } state)
        {
            var engine = controller.Settings.OnlineEngine;
            OnlineTitle.Text = Localizer.Current.Format("%@ is not translating right now", engine.DisplayName());
            OnlineReason.Text = state.Describe(engine, Localizer.Current, controller.Settings.LocalAiServer) + " " + Localizer.Current["Meanwhile the free translation is used."];
        }
    }

    private void OnSettings(object sender, RoutedEventArgs e) => SettingsWindow.Open(Window.GetWindow(this), controller);

    private void OnHistory(object sender, RoutedEventArgs e) => HistoryWindow.Open(Window.GetWindow(this), controller);

    private void OnDownload(object sender, RoutedEventArgs e) => controller.StartModelDownload();

    /// <summary>
    /// Oyun dilinin Windows yazı tanıma paketini yönetici izniyle kurar (Add-WindowsCapability), sonra okumayı
    /// yeni paketle yeniden başlatır.
    /// </summary>
    private async void OnInstallOcr(object sender, RoutedEventArgs e)
    {
        var language = controller.Settings.SourceLanguage;
        var script = $"Get-WindowsCapability -Online | Where-Object {{ $_.Name -like 'Language.OCR~~~{language}-*' -and $_.State -ne 'Installed' }} | Select-Object -First 1 | Add-WindowsCapability -Online";
        InstallOcr.IsEnabled = false;
        try
        {
            using var process = Process.Start(new ProcessStartInfo("powershell.exe", $"-NoProfile -WindowStyle Hidden -Command \"{script}\"")
            {
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden,
            });
            if (process is not null) await process.WaitForExitAsync();
            if (!controller.IsRunning) return;
            controller.Stop();
            await controller.StartAsync();
        }
        catch (System.ComponentModel.Win32Exception) { /* izin verilmedi */ }
        finally { InstallOcr.IsEnabled = true; }
    }

    private void OnLanguageSettings(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("ms-settings:regionlanguage") { UseShellExecute = true });

    /// <summary>
    /// Oynanan oyun karosu (yalnız çeviri sürerken): "Oynanan oyun: X · Değiştir" ya da "Hangi oyunu oynuyorsunuz?" kartı
    /// (Mac, iPhone ve Android ile aynı metin ve davranış).
    /// </summary>
    private void ShowGame()
    {
        var text = Localizer.Current;
        GameCard.Visibility = controller.IsRunning ? Visibility.Visible : Visibility.Collapsed;
        var asking = controller.AskingGame;
        GameRow.Visibility = asking ? Visibility.Collapsed : Visibility.Visible;
        GameAsk.Visibility = asking ? Visibility.Visible : Visibility.Collapsed;
        PlayedGameText.Text = controller.PlayedGame ?? text["Not known"];
        GameChangeButton.Content = text[controller.PlayedGame is null ? "Choose" : "Change"];
        if (asking) ShowGameSuggestions();
        else GameSearch.Text = "";
    }

    private void ShowGameSuggestions()
    {
        var typed = GameSearch.Text.Trim();
        var suggestions = controller.GameSuggestions(typed).Take(5).ToList();
        var last = controller.LastPlayedGame;
        GameList.Children.Clear();
        foreach (var name in suggestions)
        {
            var label = new DockPanel();
            if (name == last)
            {
                var note = new TextBlock { Text = Localizer.Current["Last played"], Style = (Style)FindResource("CaptionText"), VerticalAlignment = VerticalAlignment.Center };
                DockPanel.SetDock(note, Dock.Right);
                label.Children.Add(note);
            }
            label.Children.Add(new TextBlock { Text = name, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center });
            var button = new Button
            {
                Content = label, Style = (Style)FindResource("GhostButton"), HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Stretch, Margin = new Thickness(0, 2, 0, 2),
            };
            button.Click += (_, _) => controller.ChooseGame(name);
            GameList.Children.Add(button);
        }
        var custom = typed.Length > 0 && !suggestions.Any(n => GameName.Key(n) == GameName.Key(typed));
        GameCustom.Visibility = custom ? Visibility.Visible : Visibility.Collapsed;
        GameCustom.Content = Localizer.Current.Format("Not listed: use “%@”", typed);
    }

    private void OnChangeGame(object sender, RoutedEventArgs e) => controller.AskGame();

    private void OnDontAskGame(object sender, RoutedEventArgs e) => controller.DismissGame();

    private void OnGameSearch(object sender, TextChangedEventArgs e) => ShowGameSuggestions();

    private void OnGameSearchKey(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != System.Windows.Input.Key.Enter || GameSearch.Text.Trim() is not { Length: > 0 } typed) return;
        controller.ChooseGame(typed);
        e.Handled = true;
    }

    private void OnCustomGame(object sender, RoutedEventArgs e) => controller.ChooseGame(GameSearch.Text.Trim());
}
