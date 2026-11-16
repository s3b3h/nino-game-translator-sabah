// SPDX-License-Identifier: AGPL-3.0-only

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using CouchSubs.App.Theme;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views.Steps;

public partial class WelcomeStep : UserControl
{
    public WelcomeStep()
    {
        InitializeComponent();
        // Arapça arayüzde de bayraklar sağ üstte kalır (sağdan sola düzende "Left" görünürde sağdır).
        if (RightToLeft.Interface) Flags.HorizontalAlignment = HorizontalAlignment.Left;
        DataContextChanged += (_, e) =>
        {
            if (e.OldValue is AppController old) old.PropertyChanged -= OnControllerChanged;
            if (e.NewValue is AppController controller) controller.PropertyChanged += OnControllerChanged;
            ShowFlags();
        };
        Unloaded += (_, _) =>
        {
            if (DataContext is AppController controller) controller.PropertyChanged -= OnControllerChanged;
        };
    }

    private AppController? Controller => DataContext as AppController;

    /// <summary>Nino: oyunu bu bilgisayarda Remote Play ile oynayanlar PS5 ve TV adımlarını atlar.</summary>
    private void OnGameWindow(object sender, RoutedEventArgs e) => Controller?.UseGameWindowSetup();

    private void OnXbox(object sender, RoutedEventArgs e) => Controller?.UseXboxWindowSetup();

    /// <summary>Nino: Capture Card olanlar ikinci hesap ve PS5 eşleştirmesi yerine kart rehberine geçer.</summary>
    private void OnCaptureCard(object sender, RoutedEventArgs e) => Controller?.UseCaptureCardSetup();

    private void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AppController.Settings)) ShowFlags();
    }

    /// <summary>Nino: çeviri dili için yalnız bayraklar; seçili olan tam renkli ve ince mavi halkalı, öteki soluk.</summary>
    private void ShowFlags()
    {
        Flags.Children.Clear();
        if (Controller is not { } controller) return;
        foreach (var (code, name) in TargetLanguage.Choices)
        {
            var selected = controller.Settings.TargetLanguage == code;
            var ring = new Border
            {
                Width = 34, Height = 34, CornerRadius = new CornerRadius(17), Margin = new Thickness(3, 0, 3, 0),
                BorderThickness = new Thickness(1.5),
                Background = new SolidColorBrush(Color.FromArgb(selected ? (byte)26 : (byte)0, 255, 255, 255)),
                Opacity = selected ? 1 : 0.45,
                Cursor = Cursors.Hand,
                ToolTip = name,
                Child = Flag(code),
                FlowDirection = FlowDirection.LeftToRight,
            };
            if (selected) ring.SetResourceReference(Border.BorderBrushProperty, "accentBrush");
            else ring.BorderBrush = Brushes.Transparent;
            AutomationPropertiesHelper.SetName(ring, name);
            ring.MouseLeftButtonUp += (_, _) => controller.Settings = controller.Settings with { TargetLanguage = code };
            Flags.Children.Add(ring);
        }
    }

    /// <summary>Küçük, sade bayrak (22×15): Türkiye ya da Suudi Arabistan (Arapça).</summary>
    private static FrameworkElement Flag(string code)
    {
        const double W = 22, H = 15;
        var canvas = new Canvas { Width = W, Height = H, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
                                  Clip = new RectangleGeometry(new Rect(0, 0, W, H), 2.5, 2.5) };
        if (code == TargetLanguage.Arabic)
        {
            canvas.Background = new SolidColorBrush(Color.FromRgb(0x00, 0x6C, 0x35));
            // Yazı yerine iki ince beyaz çizgi, altta kılıç: küçük boyda sade bir simge.
            Add(canvas, new Rectangle { Width = 12, Height = 1.2, Fill = Brushes.White }, 5, 4.2);
            Add(canvas, new Rectangle { Width = 9, Height = 1.2, Fill = Brushes.White }, 6.5, 6.6);
            Add(canvas, new Rectangle { Width = 13, Height = 1, Fill = Brushes.White }, 4.5, 10.2);
            Add(canvas, new Rectangle { Width = 1, Height = 2.4, Fill = Brushes.White }, 15.5, 9.5);
        }
        else
        {
            var red = new SolidColorBrush(Color.FromRgb(0xE3, 0x0A, 0x17));
            canvas.Background = red;
            Add(canvas, new Ellipse { Width = 7.6, Height = 7.6, Fill = Brushes.White }, 4.2, 3.7);
            Add(canvas, new Ellipse { Width = 6.1, Height = 6.1, Fill = red }, 5.9, 4.45);
            Add(canvas, Star(2.1), 13.4, 7.5);
        }
        return canvas;
    }

    private static void Add(Canvas canvas, UIElement element, double left, double top)
    {
        Canvas.SetLeft(element, left);
        Canvas.SetTop(element, top);
        canvas.Children.Add(element);
    }

    /// <summary>Beş köşeli beyaz yıldız; (0,0) merkezde.</summary>
    private static Polygon Star(double radius)
    {
        var star = new Polygon { Fill = Brushes.White };
        for (var i = 0; i < 10; i++)
        {
            var r = i % 2 == 0 ? radius : radius * 0.42;
            var angle = Math.PI / 2 + i * Math.PI / 5;
            star.Points.Add(new Point(r * Math.Cos(angle), -r * Math.Sin(angle)));
        }
        return star;
    }
}

/// <summary>Ekran okuyucu adı (AutomationProperties.Name).</summary>
internal static class AutomationPropertiesHelper
{
    public static void SetName(DependencyObject element, string name) =>
        System.Windows.Automation.AutomationProperties.SetName(element, name);
}
