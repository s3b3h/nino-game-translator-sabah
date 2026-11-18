// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using CouchSubs.App.Theme;

namespace CouchSubs.App.Controls;

/// <summary>
/// Nino robotu (design/bot-png, uygulamaya kaynak olarak gömülü). Her 4–5 saniyede bir ~150 ms göz kırpar; istenirse
/// yavaşça yukarı aşağı süzülür, "düşünürken" hafifçe sallanır. Windows'ta "Animasyonları göster" kapalıysa (hareketi
/// azalt) robot kıpırdamaz. Arapça arayüzde aynalanmaz (şapkadaki bayrak ters dönmesin).
/// </summary>
public sealed class NinoBot : Image
{
    private static readonly BitmapImage Open = Load("nino-bot-256.png");
    private static readonly BitmapImage Blink = Load("nino-bot-blink-256.png");
    private static readonly Random Chance = new();

    public static readonly DependencyProperty BobProperty = DependencyProperty.Register(nameof(Bob), typeof(bool), typeof(NinoBot),
        new PropertyMetadata(false, (d, _) => ((NinoBot)d).Animate()));
    public static readonly DependencyProperty ThinkingProperty = DependencyProperty.Register(nameof(Thinking), typeof(bool), typeof(NinoBot),
        new PropertyMetadata(false, (d, _) => ((NinoBot)d).Animate()));
    public static readonly DependencyProperty BlinksProperty = DependencyProperty.Register(nameof(Blinks), typeof(bool), typeof(NinoBot),
        new PropertyMetadata(true));

    private readonly DispatcherTimer blinkTimer = new();
    private readonly TranslateTransform lift = new();
    private readonly RotateTransform tilt = new();

    /// <summary>Yavaşça yukarı aşağı süzülsün mü (yüzen düğme).</summary>
    public bool Bob { get => (bool)GetValue(BobProperty); set => SetValue(BobProperty, value); }
    /// <summary>Cevap beklenirken hafifçe sallansın mı.</summary>
    public bool Thinking { get => (bool)GetValue(ThinkingProperty); set => SetValue(ThinkingProperty, value); }
    /// <summary>Göz kırpsın mı (küçük avatarlarda kapatılır).</summary>
    public bool Blinks { get => (bool)GetValue(BlinksProperty); set => SetValue(BlinksProperty, value); }

    public NinoBot()
    {
        Source = Open;
        Stretch = Stretch.Uniform;
        Focusable = false;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        RenderTransformOrigin = new Point(0.5, 0.9);
        RenderTransform = new TransformGroup { Children = { tilt, lift } };
        RightToLeft.KeepLeftToRight(this);
        blinkTimer.Tick += OnBlinkTick;
        Loaded += (_, _) => { ScheduleBlink(); Animate(); };
        Unloaded += (_, _) => { blinkTimer.Stop(); Source = Open; Stop(); };
    }

    /// <summary>Hareketi azalt: Windows'ta "Animasyonları göster" kapalı.</summary>
    public static bool ReduceMotion => !SystemParameters.ClientAreaAnimation;

    private static BitmapImage Load(string name)
    {
        var image = new BitmapImage();
        image.BeginInit();
        image.UriSource = new Uri($"pack://application:,,,/Assets/Bot/{name}", UriKind.Absolute);
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.EndInit();
        image.Freeze();
        return image;
    }

    private void ScheduleBlink()
    {
        blinkTimer.Stop();
        if (!Blinks || ReduceMotion || !IsLoaded) return;
        Source = Open;
        blinkTimer.Interval = TimeSpan.FromMilliseconds(4000 + Chance.Next(1000));
        blinkTimer.Start();
    }

    private void OnBlinkTick(object? sender, EventArgs e)
    {
        if (Source == Open)
        {
            Source = Blink;
            blinkTimer.Interval = TimeSpan.FromMilliseconds(150);
        }
        else ScheduleBlink();
    }

    private void Stop()
    {
        lift.BeginAnimation(TranslateTransform.YProperty, null);
        tilt.BeginAnimation(RotateTransform.AngleProperty, null);
    }

    private void Animate()
    {
        Stop();
        if (!IsLoaded || ReduceMotion) return;
        var ease = new SineEase { EasingMode = EasingMode.EaseInOut };
        if (Bob || Thinking)
        {
            var height = Math.Max(2, (double.IsNaN(Height) ? ActualHeight : Height) * 0.05);
            lift.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(-height, height, TimeSpan.FromSeconds(Thinking ? 0.45 : 1.6))
            {
                AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = ease,
            });
        }
        if (Thinking)
        {
            tilt.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(-6, 6, TimeSpan.FromSeconds(0.6))
            {
                AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = ease,
            });
        }
    }
}

/// <summary>
/// Ana ekranın ve kurulum sihirbazının sağ altındaki yuvarlak "Nino'ya Sor" düğmesi: yumuşak beyaz daire, hafif gölge,
/// içinde süzülen ve göz kırpan robot.
/// </summary>
public sealed class AskNinoButton : Button
{
    public const double Diameter = 60;

    public AskNinoButton(string name)
    {
        Width = Height = Diameter;
        Cursor = Cursors.Hand;
        FocusVisualStyle = null;
        ToolTip = name;
        AutomationProperties.SetName(this, name);
        AutomationProperties.SetHelpText(this, name);

        var circle = new Ellipse
        {
            Fill = new SolidColorBrush(Color.FromArgb(0xF5, 0xFF, 0xFF, 0xFF)),
            Stroke = new SolidColorBrush(Color.FromArgb(0x1F, 0x0B, 0x16, 0x33)),
            StrokeThickness = 1,
            Effect = new DropShadowEffect { BlurRadius = 16, ShadowDepth = 3, Direction = 270, Opacity = 0.22, Color = Color.FromRgb(0x0B, 0x16, 0x33) },
        };
        var focus = new Ellipse { StrokeThickness = 2, Margin = new Thickness(-4), Visibility = Visibility.Collapsed };
        focus.SetResourceReference(Shape.StrokeProperty, "accentTextBrush");
        var bot = new NinoBot { Width = 44, Height = 44, Bob = true, Margin = new Thickness(0, 2, 0, 0) };

        var face = new Grid { RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = new ScaleTransform(1, 1), Children = { circle, bot, focus } };
        Template = new ControlTemplate(typeof(Button)) { VisualTree = new FrameworkElementFactory(typeof(ContentPresenter)) };
        Content = face;

        void Scale(double to)
        {
            var transform = (ScaleTransform)face.RenderTransform;
            if (NinoBot.ReduceMotion) { transform.ScaleX = transform.ScaleY = to; return; }
            var animation = new DoubleAnimation(to, TimeSpan.FromMilliseconds(140)) { EasingFunction = new QuadraticEase() };
            transform.BeginAnimation(ScaleTransform.ScaleXProperty, animation);
            transform.BeginAnimation(ScaleTransform.ScaleYProperty, animation);
        }
        MouseEnter += (_, _) => Scale(1.07);
        MouseLeave += (_, _) => Scale(1);
        PreviewMouseLeftButtonDown += (_, _) => Scale(0.95);
        PreviewMouseLeftButtonUp += (_, _) => Scale(IsMouseOver ? 1.07 : 1);
        IsKeyboardFocusedChanged += (_, _) => focus.Visibility = IsKeyboardFocused ? Visibility.Visible : Visibility.Collapsed;
    }
}
