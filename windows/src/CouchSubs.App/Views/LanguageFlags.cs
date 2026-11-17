// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı.

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using CouchSubs.Core;

namespace CouchSubs.App.Views;

/// <summary>
/// Çeviri dillerinin küçük, sade bayrakları (22×15). Windows bayrak emojisini harf olarak gösterdiği için ("TR")
/// bayraklar şekillerle çizilir; küçük boyda tanınacak kadar sadedir.
/// </summary>
public static class LanguageFlags
{
    private const double W = 22, H = 15;

    /// <summary>Bayrak ve dilin kendi adı yan yana (açılır listelerin satırı).</summary>
    public static FrameworkElement Row(string code, string name)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, FlowDirection = FlowDirection.LeftToRight };
        row.Children.Add(Flag(code));
        row.Children.Add(new TextBlock { Text = name, Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
        return row;
    }

    public static FrameworkElement Flag(string code)
    {
        var canvas = new Canvas
        {
            Width = W, Height = H, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center,
            Clip = new RectangleGeometry(new Rect(0, 0, W, H), 2.5, 2.5), FlowDirection = FlowDirection.LeftToRight,
        };
        switch (TargetLanguage.Code(code))
        {
            case "ar":
                canvas.Background = Brush(0x00, 0x6C, 0x35);
                // Yazı yerine iki ince beyaz çizgi, altta kılıç.
                Add(canvas, Rect(12, 1.2, Brushes.White), 5, 4.2);
                Add(canvas, Rect(9, 1.2, Brushes.White), 6.5, 6.6);
                Add(canvas, Rect(13, 1, Brushes.White), 4.5, 10.2);
                Add(canvas, Rect(1, 2.4, Brushes.White), 15.5, 9.5);
                break;
            case "hi":
                Stripes(canvas, Brush(0xFF, 0x99, 0x33), Brushes.White, Brush(0x13, 0x88, 0x08));
                Add(canvas, new Ellipse { Width = 4, Height = 4, Stroke = Brush(0x00, 0x00, 0x80), StrokeThickness = 0.9 }, 9, 5.5);
                break;
            case "id":
                Stripes(canvas, Brush(0xCE, 0x11, 0x26), Brushes.White);
                break;
            case "th":
                var red = Brush(0xA5, 0x19, 0x31);
                canvas.Background = red;
                Add(canvas, Rect(W, 2.5, Brushes.White), 0, 2.5);
                Add(canvas, Rect(W, 5, Brush(0x2D, 0x2A, 0x4A)), 0, 5);
                Add(canvas, Rect(W, 2.5, Brushes.White), 0, 10);
                break;
            case "vi":
                canvas.Background = Brush(0xDA, 0x25, 0x1D);
                Add(canvas, Star(4.2, Brush(0xFF, 0xFF, 0x00)), 11, 7.8);
                break;
            case "ur":
                canvas.Background = Brush(0x01, 0x41, 0x1C);
                Add(canvas, Rect(5.5, H, Brushes.White), 0, 0);
                Crescent(canvas, Brush(0x01, 0x41, 0x1C), 9.2, 3.6, 7.4);
                Add(canvas, Star(1.6, Brushes.White), 16.4, 5.6);
                break;
            case "bn":
                canvas.Background = Brush(0x00, 0x6A, 0x4E);
                Add(canvas, new Ellipse { Width = 8.4, Height = 8.4, Fill = Brush(0xF4, 0x2A, 0x41) }, 5.6, 3.3);
                break;
            case "ms":
                canvas.Background = Brushes.White;
                for (var i = 0; i < 14; i += 2) Add(canvas, Rect(W, H / 14 + 0.1, Brush(0xCC, 0x00, 0x01)), 0, i * H / 14);
                Add(canvas, Rect(11, 8.6, Brush(0x01, 0x00, 0x66)), 0, 0);
                Crescent(canvas, Brush(0x01, 0x00, 0x66), 1.6, 1.6, 5.4, Brush(0xFF, 0xCC, 0x00));
                Add(canvas, Star(1.5, Brush(0xFF, 0xCC, 0x00)), 7.8, 4.3);
                break;
            case "tl":
                Stripes(canvas, Brush(0x00, 0x38, 0xA8), Brush(0xCE, 0x11, 0x26));
                var triangle = new Polygon { Fill = Brushes.White };
                triangle.Points.Add(new Point(0, 0));
                triangle.Points.Add(new Point(11, H / 2));
                triangle.Points.Add(new Point(0, H));
                canvas.Children.Add(triangle);
                Add(canvas, new Ellipse { Width = 3, Height = 3, Fill = Brush(0xFC, 0xD1, 0x16) }, 2.6, 6);
                break;
            case "nl":
                Stripes(canvas, Brush(0xAE, 0x1C, 0x28), Brushes.White, Brush(0x21, 0x46, 0x8B));
                break;
            default:
                var flagRed = Brush(0xE3, 0x0A, 0x17);
                canvas.Background = flagRed;
                Crescent(canvas, flagRed, 4.2, 3.7, 7.6);
                Add(canvas, Star(2.1, Brushes.White), 13.4, 7.5);
                break;
        }
        return canvas;
    }

    /// <summary>Yatay şeritler, eşit yükseklikte, yukarıdan aşağı.</summary>
    private static void Stripes(Canvas canvas, params Brush[] colors)
    {
        var height = H / colors.Length;
        for (var i = 0; i < colors.Length; i++) Add(canvas, Rect(W, height + 0.2, colors[i]), 0, i * height);
    }

    /// <summary>Hilal: dolu daire, sağa kaydırılmış zemin rengindeki daireyle oyulur.</summary>
    private static void Crescent(Canvas canvas, Brush background, double left, double top, double size, Brush? color = null)
    {
        Add(canvas, new Ellipse { Width = size, Height = size, Fill = color ?? Brushes.White }, left, top);
        var inner = size * 0.8;
        Add(canvas, new Ellipse { Width = inner, Height = inner, Fill = background }, left + size * 0.22, top + (size - inner) / 2);
    }

    private static Rectangle Rect(double width, double height, Brush fill) => new() { Width = width, Height = height, Fill = fill };

    private static SolidColorBrush Brush(byte r, byte g, byte b) => new(Color.FromRgb(r, g, b));

    private static void Add(Canvas canvas, UIElement element, double left, double top)
    {
        Canvas.SetLeft(element, left);
        Canvas.SetTop(element, top);
        canvas.Children.Add(element);
    }

    /// <summary>Beş köşeli yıldız; (0,0) merkezde.</summary>
    private static Polygon Star(double radius, Brush fill)
    {
        var star = new Polygon { Fill = fill };
        for (var i = 0; i < 10; i++)
        {
            var r = i % 2 == 0 ? radius : radius * 0.42;
            var angle = Math.PI / 2 + i * Math.PI / 5;
            star.Points.Add(new Point(r * Math.Cos(angle), -r * Math.Sin(angle)));
        }
        return star;
    }
}
