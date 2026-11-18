// SPDX-License-Identifier: AGPL-3.0-only

using System.ComponentModel;
using System.Windows;
using System.Windows.Interop;
using CouchSubs.App.Controls;
using CouchSubs.App.Services;
using CouchSubs.App.Views;
using CouchSubs.Core;
using CouchSubs.Shell;
using Microsoft.Win32;

namespace CouchSubs.App;

/// <summary>Uygulamanın tek penceresi: kurulum bitmediyse sihirbaz, bittiyse ana ekran.</summary>
public partial class ShellWindow : Window
{
    private readonly AppController controller;
    private bool showingMain;
    private GlobalHotkeys? hotkeys;
    private readonly AskNinoButton askNino = new(Localizer.Current["Ask Nino"])
    {
        HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
    };
    /// <summary>Nino: çeviri başlayınca robotun yanında 7 sn "Altyazı Çevirisi Başladı" balonu (yalnız ana ekranda).</summary>
    private readonly NinoStartedBubble startedBubble = new(Localizer.Current["Nino: Subtitle Translation Started. Enjoy the Game!"])
    {
        HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Bottom,
        // Robotun (sol 36, alt 84, 60 px) sağında, dikeyde ortasında.
        Margin = new Thickness(36 + AskNinoButton.Diameter + 12, 0, 0, 84 + 6),
    };
    private bool wasRunning;

    public ShellWindow(AppController controller)
    {
        this.controller = controller;
        InitializeComponent();
        // Nino: "Nino'ya Sor" hem ana ekranda hem kurulum sihirbazında (takılınan yer) görünür.
        askNino.Click += (_, _) => AskNinoWindow.Open(controller);
        Root.Children.Add(askNino);
        Root.Children.Add(startedBubble);
        wasRunning = controller.IsRunning;
        controller.PropertyChanged += OnChanged;
        // Bilgisayar uykudan uyanınca bağlantılar hemen yenilenir.
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
        // Kısayollar (varsayılan Num 0, 1, 2, 3, 5, 7, 8, 9 ve Ctrl+Shift+rakam; Ayarlar › Kısayollar'da değişir) yalnız
        // çeviri sürerken tutulur.
        SourceInitialized += (_, _) =>
        {
            hotkeys = new GlobalHotkeys(new WindowInteropHelper(this).Handle, OnHotkey);
            ApplyHotkeys();
        };
        // Bilgisayarda gösterilecek çeviriler küçük, üstte duran bir kutuda çıkar.
        controller.PcResultReady += PcResultWindow.Display;
        // Bilgisayar ekranındaki altyazı penceresi (altyazı yokken gizli). Kurulamazsa uygulama onsuz açılır.
        SubtitleOverlayWindow? overlay = null;
        try
        {
            overlay = SubtitleOverlayWindow.Attach(controller);
        }
        catch (Exception error)
        {
            StartupGuard.Log("Altyazı penceresi kurulamadı", error);
            StartupGuard.Show(Application.Current, StartupGuard.OverlayFailedMessage(error));
        }
        Closed += (_, _) =>
        {
            controller.PcResultReady -= PcResultWindow.Display;
            overlay?.Detach();
            hotkeys?.Dispose();
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
            controller.Dispose();
        };
        ShowScreen(force: true);
    }

    private void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AppController.Step)) ShowScreen();
        if (e.PropertyName == nameof(AppController.IsRunning)) UpdateStartedBubble();
        if (e.PropertyName is nameof(AppController.IsRunning) or nameof(AppController.HotkeysPaused) or nameof(AppController.Settings))
            ApplyHotkeys();
    }

    /// <summary>Kısayol tablosu ayarlardan gelir; Ayarlar'da yeni tuş beklenirken kısayollar bırakılır.</summary>
    private void ApplyHotkeys()
    {
        if (hotkeys is null) return;
        hotkeys.Bindings = HotkeyTable.Resolve(controller.Settings.Hotkeys);
        hotkeys.Enabled = controller.IsRunning && !controller.HotkeysPaused;
    }

    private void OnHotkey(HotkeyAction action)
    {
        switch (action)
        {
            case HotkeyAction.ExtraRegion1: _ = controller.TranslateExtraRegionAsync(1); break;
            case HotkeyAction.ExtraRegion2: _ = controller.TranslateExtraRegionAsync(2); break;
            case HotkeyAction.ExtraRegion3: _ = controller.TranslateExtraRegionAsync(3); break;
            case HotkeyAction.PauseSubtitles: controller.ToggleSubtitles(); break;
            case HotkeyAction.Snapshot: controller.RequestSnapshot(); break;
            case HotkeyAction.FreeArea: FreeAreaWindow.Open(controller); break;
            case HotkeyAction.Screen: _ = controller.TranslateScreenAsync(); break;
            case HotkeyAction.ClickThrough: controller.ToggleClickThrough(); break;
        }
    }

    private void ShowScreen(bool force = false)
    {
        var main = controller.Step == OnboardingStep.Done;
        if (!force && main == showingMain) return;
        showingMain = main;
        Host.Content = main ? new MainView(controller) : new OnboardingView(controller);
        // Düğme alttaki düğmelerin üstünde durur: ana ekranda durum şeridinin (Çeviri ›), sihirbazda Devam düğmesinin üstünde,
        // kartın kaydırma çubuğundan uzakta.
        // Ana ekranda sağ altta fiş ve kablo durur (PS5 ve Xbox sahnesi); robot sol alta geçer.
        askNino.HorizontalAlignment = main ? HorizontalAlignment.Left : HorizontalAlignment.Right;
        askNino.Margin = main ? new Thickness(36, 0, 0, 84) : new Thickness(0, 0, 44, 100);
        if (!main) startedBubble.Hide();
    }

    /// <summary>Çeviri yeni başladıysa ve ana ekrandaysak balon 7 sn gösterilir; çeviri durunca hemen kalkar.</summary>
    private void UpdateStartedBubble()
    {
        var running = controller.IsRunning;
        var started = running && !wasRunning;
        wasRunning = running;
        if (started && controller.Step == OnboardingStep.Done) startedBubble.Show();
        else if (!running) startedBubble.Hide(TimeSpan.FromMilliseconds(250));
    }

    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Resume) Dispatcher.Invoke(controller.SystemResumed);
    }
}
