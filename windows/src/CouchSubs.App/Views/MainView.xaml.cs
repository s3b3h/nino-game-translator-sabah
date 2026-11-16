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
            or nameof(AppController.TvTone) or nameof(AppController.IsRunning) or nameof(AppController.SessionState))
            ShowStrip();
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

    private HomeStyle? shownHome;

    /// <summary>Ayarlardaki arayüz: Salon ya da Cam düğme (değişince yeniden kurulur).</summary>
    private void ShowHome()
    {
        var style = controller.Settings.HomeStyle;
        if (shownHome == style) return;
        shownHome = style;
        HomeHost.Content = style == HomeStyle.LivingRoom ? new LivingRoomScene(controller) : new GlassToggleView(controller);
    }

    /// <summary>Alt şerit: PS5 ve TV (renkli nokta ve kısa durum), sağda seçili çeviri motoru.</summary>
    private void ShowStrip()
    {
        var text = Localizer.Current;
        var settings = controller.Settings;
        EngineValue.Text = settings.Engine == TranslationEngine.Free ? text["Free"] : settings.Engine.DisplayName();
        // Çeviri kapalıyken eşleşmiş PS5 için kısa yazı (uzun durum yazısı şeride sığmıyordu).
        Ps5Label.Text = controller.UsesGameWindow ? text["Game window"] : controller.UsesCaptureCard ? text["Capture card"] : "PS5";
        Ps5Value.Text = controller.Settings.VideoSource == VideoSource.Ps5 && !controller.IsRunning && controller.Console is { } console
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
}
