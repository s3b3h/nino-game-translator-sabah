// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı (Mac: CaptureCardPlayer.swift).

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using CouchSubs.App.Controls;
using CouchSubs.App.Services;
using CouchSubs.App.Theme;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views;

/// <summary>
/// Yakalama kartından gelen oyunu bu bilgisayarda gösteren pencere (TV'si ya da monitörü akıllı olmayanlar için:
/// PS5 → kart → bilgisayar → ekran). Ana ekranda kenarsız tam ekran açılır; Esc pencereye alır ya da yeniden tam ekran
/// yapar. Pencereyi kapatmak çeviriyi durdurur. Altyazı penceresi bunun üstünde, oyun alanının altına oturur
/// (bu pencere en üstte durmaz; en üstteki altyazı penceresidir).
/// </summary>
public sealed class CaptureCardPlayerWindow : Window
{
    /// <summary>Oyun alanının ekrandaki yeri (ekran pikseliyle) ya da null (küçültüldü, kapandı).</summary>
    public event Action<ScreenArea?>? GameAreaChanged;
    /// <summary>Kullanıcı pencereyi kapattı.</summary>
    public event Action? UserClosed;

    public CardVideoSurface Surface { get; } = new();

    private readonly TextBlock hint;
    private readonly DispatcherTimer cursorTimer = new() { Interval = TimeSpan.FromSeconds(2.5) };
    private bool fullScreen;
    private bool closingQuietly;
    private ScreenArea? reported;
    private Rect windowed = Rect.Empty;

    public CaptureCardPlayerWindow()
    {
        Title = "Nino";
        Background = Brushes.Black;
        ShowActivated = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        RightToLeft.KeepLeftToRight(this);
        try { Icon = new System.Windows.Media.Imaging.BitmapImage(new Uri("pack://application:,,,/Assets/CouchSubs.ico")); }
        catch { /* simge yoksa pencere yine açılır */ }

        hint = new TextBlock
        {
            Text = Localizer.Current["Esc: full screen on or off · Closing this window stops the translation"],
            Foreground = Brushes.White, FontSize = 15, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center,
        };
        var hintBox = new Border
        {
            Child = hint, Background = new SolidColorBrush(Color.FromArgb(150, 0, 0, 0)), CornerRadius = new CornerRadius(18),
            Padding = new Thickness(18, 9, 18, 9), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 28, 0, 0), IsHitTestVisible = false,
        };
        if (RightToLeft.Interface) hintBox.FlowDirection = FlowDirection.RightToLeft;
        var root = new Grid { Background = Brushes.Black };
        root.Children.Add(Surface);
        root.Children.Add(hintBox);
        Content = root;
        // İpucu birkaç saniye görünür, sonra yavaşça kaybolur.
        Loaded += (_, _) => hintBox.BeginAnimation(OpacityProperty,
            new DoubleAnimation(1, 0, TimeSpan.FromSeconds(0.8)) { BeginTime = TimeSpan.FromSeconds(4) });

        SizeChanged += (_, _) => Report();
        LocationChanged += (_, _) => Report();
        StateChanged += (_, _) => Report();
        Surface.SizeChanged += (_, _) => Report();
        KeyDown += (_, e) =>
        {
            if (e.Key != Key.Escape) return;
            e.Handled = true;
            ToggleFullScreen();
        };
        // Oyun sırasında fare imleci bir süre durunca gizlenir.
        MouseMove += (_, _) =>
        {
            Cursor = null;
            cursorTimer.Stop();
            cursorTimer.Start();
        };
        cursorTimer.Tick += (_, _) =>
        {
            cursorTimer.Stop();
            Cursor = Cursors.None;
        };
        Closed += (_, _) =>
        {
            cursorTimer.Stop();
            SleepGuard.KeepDisplayOn(false);
            GameAreaChanged?.Invoke(null);
            if (!closingQuietly) UserClosed?.Invoke();
        };
    }

    /// <summary>Ana ekranda tam ekran açar.</summary>
    public void ShowFullScreen()
    {
        EnterFullScreen();
        Show();
        Activate();
        cursorTimer.Start();
        SleepGuard.KeepDisplayOn(true);
    }

    public void ToggleFullScreen()
    {
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        if (fullScreen) LeaveFullScreen();
        else EnterFullScreen();
        Activate();
    }

    /// <summary>Çeviri durdu: pencere kapanır, <see cref="UserClosed"/> çağrılmaz.</summary>
    public void CloseQuietly()
    {
        closingQuietly = true;
        try { Close(); }
        catch (InvalidOperationException) { /* pencere zaten kapanmış */ }
    }

    private void EnterFullScreen()
    {
        if (IsLoaded && WindowState == WindowState.Normal) windowed = new Rect(Left, Top, Width, Height);
        fullScreen = true;
        // Kenarsız ve büyütülmüş pencere görev çubuğunu da örter. Ana ekranda açılsın diye önce oraya taşınır.
        WindowState = WindowState.Normal;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        var screen = SystemParameters.WorkArea;
        Left = screen.Left;
        Top = screen.Top;
        Width = Math.Max(640, screen.Width / 2);
        Height = Math.Max(360, screen.Height / 2);
        WindowState = WindowState.Maximized;
    }

    private void LeaveFullScreen()
    {
        fullScreen = false;
        WindowState = WindowState.Normal;
        WindowStyle = WindowStyle.SingleBorderWindow;
        ResizeMode = ResizeMode.CanResize;
        var area = SystemParameters.WorkArea;
        if (windowed.IsEmpty)
        {
            var width = Math.Min(1280, area.Width * 0.8);
            var height = width * 9 / 16 + SystemParameters.WindowCaptionHeight + 2 * SystemParameters.ResizeFrameHorizontalBorderHeight;
            windowed = new Rect(area.Left + (area.Width - width) / 2, area.Top + (area.Height - height) / 2, width, height);
        }
        Left = windowed.Left;
        Top = windowed.Top;
        Width = windowed.Width;
        Height = windowed.Height;
    }

    /// <summary>
    /// Görüntünün durduğu 16:9 alan, ekran pikseliyle (altyazı penceresi sistem DPI'ıyla WPF birimine çevirir; uygulama
    /// sistem DPI'ıyla çalıştığından <see cref="Visual.PointToScreen"/> aynı birimi verir).
    /// </summary>
    private void Report()
    {
        ScreenArea? area = null;
        if (WindowState != WindowState.Minimized && IsVisible && Surface.ActualWidth > 0 && PresentationSource.FromVisual(Surface) is not null)
        {
            var parent = (FrameworkElement)Surface.Parent;
            var topLeft = parent.PointToScreen(new Point(0, 0));
            var bottomRight = parent.PointToScreen(new Point(parent.ActualWidth, parent.ActualHeight));
            area = CaptureCardRules.GameArea(new ScreenArea(topLeft.X, topLeft.Y, bottomRight.X - topLeft.X, bottomRight.Y - topLeft.Y));
        }
        if (area == reported) return;
        reported = area;
        GameAreaChanged?.Invoke(area);
    }
}
