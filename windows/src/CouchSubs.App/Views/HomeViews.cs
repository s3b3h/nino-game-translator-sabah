// SPDX-License-Identifier: AGPL-3.0-only
// Nino: ana ekranın iki arayüzü (Mac'teki LivingRoomScene ve GlassTranslateToggle ile aynı davranış ve metinler).
// 1. Salon: duvarda TV, sehpa, konsol ve priz; fiş prize takılınca (tıklama ya da sürükleme) çeviri başlar, mavi LED'ler
//    yanar, TV'de Nino açılır ve Türkçe altyazı akar; fiş çekilince durur. Fiş çıkıkken TV'de ne yapılacağı yazar, priz
//    yanıp söner; TV'nin sağ üstünde toplam indirme durur. Ölçüler ve fiş/kablo hesabı: LivingRoomLayout (Shell).
// 2. Cam düğme: sağa kayınca bayrak kırmızısı,
//    üstte canlı TV. Görünümler kodla kurulur: yanlış kaynak adı derlemede yakalanır (Windows'ta çalıştırılmadan yazıldı).

using System.ComponentModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using CouchSubs.App.Controls;
using CouchSubs.Core;
using CouchSubs.RemotePlay;
using CouchSubs.Shell;
using CouchSubs.App.Theme;

namespace CouchSubs.App.Views;

/// <summary>İki arayüzün ortak işleri: çeviriyi aç/kapat, renkler, metinler.</summary>
internal static class Home
{
    public static readonly Color FlagRed = Color.FromRgb(0xE3, 0x0A, 0x17);
    public static readonly Color FlagDeep = Color.FromRgb(0xA8, 0x05, 0x14);
    public static readonly Color LedBlue = Color.FromRgb(0x1F, 0x5C, 0xFF);

    public static string T(string key) => Localizer.Current[key];

    /// <summary>Fiş/düğme takılı mı: çeviri açık ya da açılıyor (başlatma başarısız olursa kendiliğinden geri düşer).</summary>
    public static bool On(AppController c) => c.IsRunning || c.IsStarting;

    /// <summary>
    /// Aç/kapat. Hazırlık sürerken (bir saniyeden kısa) kapatılırsa hazırlık biter bitmez durdurulur; tıklama kaybolmaz.
    /// PS5 kurulmamışsa sihirbaz açılır.
    /// </summary>
    public static async void Toggle(AppController c)
    {
        try
        {
            if (c.IsStarting)
            {
                while (c.IsStarting) await Task.Delay(50);
                if (c.IsRunning) c.Stop();
                return;
            }
            if (c.IsRunning) c.Stop();
            else if (c.CanStart) await c.StartAsync();
            // Nino: yakalama kartıyla altyazı TV'ye gidiyorsa eksik olan yalnız TV'dir (PS5 eşleştirmesi gerekmez).
            else c.Step = c.UsesCaptureCard ? OnboardingStep.Tv : OnboardingStep.Console;
        }
        catch (Exception error)
        {
            StartupGuard.Log("Çeviri açılıp kapatılamadı", error);
            StartupGuard.Show(Application.Current, StartupGuard.ErrorMessage(error));
        }
    }

    /// <summary>TV ekranındaki yazı: PS5 görüntüsü gelmiyorsa bağlantının durumu, sonra son Türkçe satır.</summary>
    public static (string text, bool subtitle) ScreenText(AppController c)
    {
        if (c.SessionState.Phase != SessionPhase.Streaming) return (c.Ps5StatusText, false);
        return string.IsNullOrEmpty(c.LastTranslation) ? (T("Waiting for the next subtitle…"), false) : (c.LastTranslation, true);
    }

    /// <summary>
    /// Salon sahnesi Xbox'lı mı: Ayarlar › Bağlantı'daki konsol seçimi (Mac'teki settings.gameConsole) ya da kurulumda
    /// seçilen Xbox (doğrudan Xbox bağlantısı).
    /// </summary>
    public static bool XboxScene(AppController c) => c.Settings.GameConsole == GameConsole.Xbox || c.IsXbox;

    public static Image Picture(string asset, double width, double height, Stretch stretch = Stretch.Uniform) => new()
    {
        Source = new BitmapImage(new Uri($"pack://application:,,,/Assets/{asset}")),
        Width = width,
        Height = height,
        Stretch = stretch,
    };

    /// <summary>
    /// Nino: fiş takılı değilken TV ekranı. Ortada ne yapılacağı ("Çalıştırmak için fişi prize sürükleyiniz"; eskiden
    /// "SİNYAL YOK"): büyük harf, tek aralıklı, beyaz %40, ortalı. <paramref name="scale"/>: Mac'teki 588 noktalık
    /// ekrandan sahnedeki ekrana büyütme (ölçüler Mac'tekilerle aynı).
    /// </summary>
    public static Grid StandbyScreen(double scale)
    {
        var screen = new Grid { Background = Brushes.Black };
        screen.Children.Add(new TextBlock
        {
            Text = Localizer.Current.Upper(T("Drag the plug to the socket to start")),
            FontFamily = new FontFamily("Consolas, Courier New"),
            FontWeight = FontWeights.SemiBold,
            FontSize = 13 * scale,
            Foreground = new SolidColorBrush(Color.FromArgb(0x66, 0xFF, 0xFF, 0xFF)),
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = TextAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(40 * scale, 0, 40 * scale, 0),
        });
        return screen;
    }

    private static readonly Color HudGreen = Color.FromRgb(0x7B, 0xE8, 0x7B);

    /// <summary>
    /// Göstergenin yazı tipi: sistemdeki "Impact" (kendisi zaten kalın, olduğu gibi kullanılır); yoksa sistemin en kalın
    /// yazısı (Segoe UI Black). Oyunun kendi logosu ya da yazı tipi kullanılmaz.
    /// </summary>
    private static readonly Lazy<(FontFamily Family, FontWeight Weight)> HudFont = new(() =>
    {
        try
        {
            if (Fonts.SystemFontFamilies.Any(family => string.Equals(family.Source, "Impact", StringComparison.OrdinalIgnoreCase)))
                return (new FontFamily("Impact"), FontWeights.Normal);
        }
        catch (Exception) { /* yazı tipi listesi okunamadı: sistem yazısı */ }
        return (new FontFamily("Segoe UI"), FontWeights.Black);
    });

    /// <summary>
    /// Nino: toplam indirme göstergesi (TV'nin sağ üstü). Oyunlardaki para göstergesi gibi: kalın, hafif eğik (−0.12
    /// yatırma), siyah çerçeveli; üstte küçük beyaz başlık, altında yeşil sayı. Sayı sunucudan geldiği gibi yazılır
    /// (binlik ayırıcı yerel biçimde); üstüne ekleme yapılmaz. <paramref name="countsUp"/>: sayı 1, 2, 3 diye başlayıp
    /// hızlanarak toplama fırlar (bkz. <see cref="CountUp"/>).
    /// </summary>
    public static FrameworkElement DownloadHud(int total, double scale, bool countsUp = false)
    {
        var title = T("Total downloads");
        var arabic = TargetLanguage.ContainsArabic(title);
        var top = Outlined(Localizer.Current.Upper(title), 11 * scale, Brushes.White, 1 * scale, scale);
        var number = Outlined(DownloadCounter.Format(total, CultureInfo.CurrentCulture), 27 * scale, new SolidColorBrush(HudGreen), 1.5 * scale, scale);
        number.Margin = new Thickness(0, 1 * scale, 0, 0);
        var hud = new StackPanel
        {
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 18 * scale, 18 * scale, 0),
            IsHitTestVisible = false,
        };
        hud.Children.Add(top);
        hud.Children.Add(number);
        if (countsUp && !NinoBot.ReduceMotion && total > 3) CountUp(number, total);
        // Hafif eğim: x' = x − 0.12·y + 3 (Arapça yazıda harfleri bozmasın diye yok).
        if (!arabic) hud.RenderTransform = new MatrixTransform(1, 0, -0.12, 1, 3 * scale, 0);
        return hud;
    }

    /// <summary>
    /// Nino (kullanıcı isteği, 21 Kasım 2026; Mac: DownloadHUD countsUp): canlı ekran açılınca sayı 1, 2, 3 diye yavaş
    /// başlar (her biri 280 ms), sonra 1,55 sn'de hızlanarak (p^2,6) toplam sayıya fırlar; sonda oyunun "görev tamam"
    /// yazısı gibi büyüyüp yeşil parlayarak yerine oturur (<see cref="Punch"/>). Sayının bütün katmanları (çerçeve,
    /// gölge, renkli yazı) birlikte güncellenir.
    /// </summary>
    private static void CountUp(Grid number, int total)
    {
        var blocks = number.Children.OfType<TextBlock>().ToList();
        void Show(int value)
        {
            var text = DownloadCounter.Format(value, CultureInfo.CurrentCulture);
            foreach (var block in blocks) block.Text = text;
        }
        foreach (var block in blocks) System.Windows.Documents.Typography.SetNumeralAlignment(block, FontNumeralAlignment.Tabular);
        Show(1);
        const double step = 280, duration = 1550;
        var clock = System.Diagnostics.Stopwatch.StartNew();
        var timer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(16) };
        timer.Tick += (_, _) =>
        {
            var ms = clock.Elapsed.TotalMilliseconds;
            // İlk üç sayı tek tek görünür.
            if (ms < 3 * step)
            {
                Show((int)(ms / step) + 1);
                return;
            }
            var p = Math.Min(1, (ms - 3 * step) / duration);
            Show(Math.Max(3, (int)Math.Round(Math.Pow(p, 2.6) * total)));
            if (p < 1) return;
            timer.Stop();
            Show(total);
            Punch(number);
        };
        // Gösterge ekrandan kalkınca sayaç da durur.
        number.Unloaded += (_, _) => timer.Stop();
        timer.Start();
    }

    /// <summary>Sayının sonundaki vuruş: sağ kenarına göre 1,32 katına yaylanarak büyür, yeşil parlar, sonra yerine oturur.</summary>
    private static void Punch(Grid number)
    {
        static KeyTime At(double ms) => KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(ms));
        var grow = new ScaleTransform(1, 1);
        number.RenderTransformOrigin = new Point(1, 0.5);
        number.RenderTransform = grow;
        // Parıltı: WPF bulanıklığı Mac'tekinin iki katı yazılır (yarıçapı farklı ölçer).
        var glow = new DropShadowEffect { Color = HudGreen, ShadowDepth = 0, BlurRadius = 28, Opacity = 0 };
        number.Effect = glow;
        var size = new DoubleAnimationUsingKeyFrames { FillBehavior = FillBehavior.Stop };
        size.KeyFrames.Add(new EasingDoubleKeyFrame(1.32, At(220), new BackEase { Amplitude = 0.5, EasingMode = EasingMode.EaseOut }));
        size.KeyFrames.Add(new LinearDoubleKeyFrame(1.32, At(260)));
        size.KeyFrames.Add(new EasingDoubleKeyFrame(1, At(710), new BackEase { Amplitude = 0.3, EasingMode = EasingMode.EaseOut }));
        var shine = new DoubleAnimationUsingKeyFrames { FillBehavior = FillBehavior.Stop };
        shine.KeyFrames.Add(new EasingDoubleKeyFrame(0.95, At(220), new QuadraticEase { EasingMode = EasingMode.EaseOut }));
        shine.KeyFrames.Add(new LinearDoubleKeyFrame(0.95, At(260)));
        shine.KeyFrames.Add(new EasingDoubleKeyFrame(0, At(710), new QuadraticEase { EasingMode = EasingMode.EaseOut }));
        // Bitince parıltı katmanı kalkar (görünmeyen gölge boşuna çizilmesin).
        shine.Completed += (_, _) => number.Effect = null;
        grow.BeginAnimation(ScaleTransform.ScaleXProperty, size);
        grow.BeginAnimation(ScaleTransform.ScaleYProperty, size);
        glow.BeginAnimation(DropShadowEffect.OpacityProperty, shine);
    }

    /// <summary>
    /// Siyah çerçeveli yazı: yazının siyah kopyaları sekiz yöne <paramref name="weight"/> kadar kaydırılır (çerçeve),
    /// altına bir derinlik gölgesi iner, en üstte renkli yazı durur.
    /// </summary>
    private static Grid Outlined(string text, double size, Brush color, double weight, double scale)
    {
        var (family, fontWeight) = HudFont.Value;
        var grid = new Grid { HorizontalAlignment = HorizontalAlignment.Right };
        void Add(Brush brush, double dx, double dy, double opacity = 1) => grid.Children.Add(new TextBlock
        {
            Text = text,
            FontFamily = family,
            FontWeight = fontWeight,
            FontSize = size,
            Foreground = brush,
            Opacity = opacity,
            RenderTransform = dx == 0 && dy == 0 ? Transform.Identity : new TranslateTransform(dx, dy),
        });
        // Derinlik: çerçevenin alt kenarı bir adım daha aşağı iner.
        var depth = weight + 1 * scale;
        foreach (var dx in new[] { -weight, 0, weight })
        {
            Add(Brushes.Black, dx, weight + depth, 0.9);
            Add(Brushes.Black, dx, weight + depth / 2, 0.9);
        }
        foreach (var dx in new[] { -weight, 0, weight })
            foreach (var dy in new[] { -weight, 0, weight })
                if (dx != 0 || dy != 0) Add(Brushes.Black, dx, dy);
        Add(color, 0, 0);
        return grid;
    }

    /// <summary>Canlı TV ekranı: koyu oyun sahnesi, sol üstte CANLI, altta satır (yarı saydam kutu, beyaz kalın yazı).</summary>
    public static (Grid screen, TextBlock line, Border lineBox) LiveScreen(double width, double height, double fontSize)
    {
        var screen = new Grid
        {
            Width = width,
            Height = height,
            Background = new LinearGradientBrush(Color.FromRgb(0x17, 0x1F, 0x3D), Color.FromRgb(0x26, 0x17, 0x2E), 45),
        };
        var pill = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(0x66, 0, 0, 0)),
            CornerRadius = new CornerRadius(height * 0.04),
            Padding = new Thickness(height * 0.03, height * 0.012, height * 0.03, height * 0.012),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(height * 0.05),
        };
        var pillRow = new StackPanel { Orientation = Orientation.Horizontal };
        var dot = new Ellipse { Width = height * 0.025, Height = height * 0.025, Fill = new SolidColorBrush(FlagRed), Margin = new Thickness(0, 0, height * 0.02, 0) };
        dot.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(1, 0.3, TimeSpan.FromSeconds(1)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
        pillRow.Children.Add(dot);
        pillRow.Children.Add(new TextBlock { Text = T("LIVE"), Foreground = Brushes.White, FontWeight = FontWeights.Bold, FontSize = height * 0.035, VerticalAlignment = VerticalAlignment.Center });
        pill.Child = pillRow;
        screen.Children.Add(pill);
        var line = new TextBlock
        {
            Foreground = Brushes.White,
            FontWeight = FontWeights.SemiBold,
            FontSize = fontSize,
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = TextAlignment.Center,
        };
        var lineBox = new Border
        {
            Child = line,
            CornerRadius = new CornerRadius(fontSize * 0.2),
            Padding = new Thickness(fontSize * 0.5, fontSize * 0.2, fontSize * 0.5, fontSize * 0.2),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(width * 0.06, 0, width * 0.06, height * 0.08),
            MaxWidth = width * 0.88,
        };
        screen.Children.Add(lineBox);
        return (screen, line, lineBox);
    }

    /// <summary>
    /// Nino: havuz öncelikli oyunda (GTA 6) TV ekranının fonu: mor-pembe-turuncu gün batımı, ufukta güneş, üstünde %30
    /// karartma (Mac'teki SunsetBackdrop). Nino'nun kendi çizimidir: oyunun logosu ya da görseli kullanılmaz.
    /// Bulanıklık (BlurEffect) kullanılmaz: Mac'te güneş ayrı, saydam kenarlı bir katmanken bulanıklık onu siyah köşeli
    /// bir blok olarak çiziyordu. Fon yalnız ekranı tam kaplayan geçişlerden oluşur; buzlu görünümü geçişlerin yumuşaklığı
    /// verir, bozulacak bir şey kalmaz.
    /// </summary>
    public static Grid SunsetBackdrop(double width, double height)
    {
        // Yalnız bir geçiş: güneş yok (kullanıcı ortada sarı bir şey istemiyor). Renkler Mac'teki GameBackdrop.swift ile aynı.
        var sky = new LinearGradientBrush { StartPoint = new Point(0.5, 0), EndPoint = new Point(0.5, 1) };
        sky.GradientStops.Add(new GradientStop(Color.FromRgb(26, 20, 87), 0));
        sky.GradientStops.Add(new GradientStop(Color.FromRgb(117, 41, 158), 0.40));
        sky.GradientStops.Add(new GradientStop(Color.FromRgb(237, 74, 153), 0.74));
        sky.GradientStops.Add(new GradientStop(Color.FromRgb(255, 140, 122), 1));
        var backdrop = new Grid { Width = width, Height = height, IsHitTestVisible = false };
        backdrop.Children.Add(new Rectangle { Fill = sky });
        backdrop.Children.Add(new Rectangle { Fill = new SolidColorBrush(Color.FromArgb(0x47, 0, 0, 0)) });
        return backdrop;
    }

    /// <summary>Soldan sağa üç renkli LED geçişi (GTA 6: solda pembe, sağda açık mavi).</summary>
    public static LinearGradientBrush LedGlow(Color left, Color middle, Color right)
    {
        var brush = new LinearGradientBrush { StartPoint = new Point(0, 0.5), EndPoint = new Point(1, 0.5) };
        brush.GradientStops.Add(new GradientStop(left, 0));
        brush.GradientStops.Add(new GradientStop(middle, 0.5));
        brush.GradientStops.Add(new GradientStop(right, 1));
        return brush;
    }

    public static void ShowLine(TextBlock line, Border box, (string text, bool subtitle) value)
    {
        if (line.Text == TargetLanguage.DisplayText(value.text)) return;
        RightToLeft.SetSubtitle(line, value.text);
        line.Foreground = value.subtitle ? Brushes.White : new SolidColorBrush(Color.FromArgb(0xAA, 0xFF, 0xFF, 0xFF));
        line.FontWeight = value.subtitle ? FontWeights.SemiBold : FontWeights.Normal;
        box.Background = value.subtitle ? new SolidColorBrush(Color.FromArgb(0xB0, 0, 0, 0)) : Brushes.Transparent;
        box.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(300)));
    }
}

/// <summary>
/// 1. arayüz: salon sahnesi. Görsel sabit (1672×941, saydam zemin; PS5'li ya da Xbox'lı salon); üstüne TV ekranının içi,
/// kablo ve fiş, arkasına mavi LED'ler ve prizin ışığı çizilir. Sehpa pencerenin ortasında durur (görselin sağında priz ve
/// konsol var). Koordinatlar Mac'tekiyle aynı (<see cref="LivingRoomLayout"/>; görseller de aynı dosyalar).
/// </summary>
public sealed class LivingRoomScene : UserControl
{
    private readonly LivingRoomLayout layout;
    private readonly Rect ScreenRect, TvRect, StandRect;
    private readonly Point Socket, Hanging;
    /// <summary>Sehpayı ortalamak için sahnenin soluna eklenen boşluk (PS5'li sahnede 72, Xbox'lıda 6).</summary>
    private readonly double Shift;

    private readonly AppController controller;
    private readonly Canvas leds = new() { Opacity = 0, IsHitTestVisible = false };
    /// <summary>Nino: fiş takılı değilken prizin kenarlarından taşan, yanıp sönen ışık (geniş ve dar katman).</summary>
    private readonly Canvas socketGlow = new() { IsHitTestVisible = false };
    private Rectangle glowWide = null!, glowTight = null!;
    private readonly Grid screenHost;
    /// <summary>Nino: toplam indirme göstergesi; bekleme ekranında da canlı ekranda da aynı yerde (sağ üst) durur.</summary>
    private readonly Grid hudHost;
    private int? hudTotal;
    /// <summary>Gösterge canlı ekran için mi kuruldu: canlı ekrana her girişte sayı baştan sayılır.</summary>
    private bool hudLive;
    /// <summary>
    /// Nino (kullanıcı isteği, 21 Kasım 2026; Mac: LivingRoomScene.introHold): açılışta fiş bir an (0,9 sn) çekik görünür,
    /// sonra yaylanarak prize takılır (çeviri kendiliğinden başlasa da). Gösteri uygulama her açıldığında bir kez oynar
    /// (sahne yeniden kurulunca, örneğin ayarlardan dönünce, yeniden oynamaz).
    /// </summary>
    private static bool introPlayed;
    private bool introHold = !introPlayed;
    private DispatcherTimer? introTimer;
    /// <summary>Fişin prize yaylanarak gidişi (her karede <see cref="drag"/> küçülür, kablo da fişle birlikte çizilir).</summary>
    private DispatcherTimer? plugSpring;
    private readonly DispatcherTimer downloadsTimer = new() { Interval = TimeSpan.FromSeconds(DownloadCounter.RefreshSeconds) };
    private readonly Path cable = new()
    {
        Stroke = new SolidColorBrush(Color.FromRgb(0x0F, 0x0F, 0x0F)),
        StrokeThickness = LivingRoomLayout.CableWidth,
        StrokeStartLineCap = PenLineCap.Round,
        StrokeEndLineCap = PenLineCap.Round,
        StrokeLineJoin = PenLineJoin.Round,
        Effect = new DropShadowEffect { BlurRadius = 6, ShadowDepth = 2, Direction = 270, Opacity = 0.25 },
        IsHitTestVisible = false,
    };
    private readonly Canvas plug = new() { Width = 120, Height = 140, Background = Brushes.Transparent, Cursor = Cursors.Hand };
    private readonly Grid offScreen;
    private Grid? splash;
    private readonly Grid liveScreen;
    private readonly TextBlock liveLine;
    private readonly Border liveBox;
    /// <summary>Nino: havuz öncelikli oyunda (GTA 6) canlı ekranın arkasındaki gün batımı; öbür oyunlarda gizli.</summary>
    private readonly Grid sunset;
    /// <summary>LED'ler: TV'nin arkasındaki geniş ışık, TV'nin kenarındaki dar ışık, sehpanın altındaki ışık ve ince şerit.</summary>
    private Rectangle ledWide = null!, ledTight = null!, ledUnder = null!, ledStrip = null!;
    /// <summary>LED'ler GTA 6 renklerinde mi (pembe, mor, mavi); değilse her zamanki mavi.</summary>
    private bool? ledsGta;
    private bool plugged;
    private bool splashDone = true;
    private Point? dragStart;
    private Vector drag;

    private const double SceneWidth = LivingRoomLayout.CanvasWidth, SceneHeight = LivingRoomLayout.CanvasHeight;

    private static Point At(ScenePoint point) => new(point.X, point.Y);
    private static Rect At(SceneRect rect) => new(rect.X, rect.Y, rect.Width, rect.Height);

    public LivingRoomScene(AppController controller)
    {
        this.controller = controller;
        // Nino: sahne konsola göre değişir (konsol değişince MainView sahneyi yeniden kurar).
        layout = LivingRoomLayout.For(Home.XboxScene(controller));
        ScreenRect = At(layout.Screen);
        TvRect = At(layout.TvFrame);
        StandRect = At(layout.StandFrame);
        Socket = At(layout.Socket);
        Hanging = At(layout.Hanging);
        Shift = layout.Shift;
        screenHost = new Grid { Width = ScreenRect.Width, Height = ScreenRect.Height, ClipToBounds = true };
        hudHost = new Grid { Width = ScreenRect.Width, Height = ScreenRect.Height, ClipToBounds = true, IsHitTestVisible = false };
        offScreen = Home.StandbyScreen(layout.ScreenScale);
        // Nino: sahne Arapça arayüzde aynalanmaz.
        RightToLeft.KeepLeftToRight(this);
        var canvas = new Canvas { Width = SceneWidth + Shift, Height = SceneHeight };
        var scene = new Canvas { Width = SceneWidth, Height = SceneHeight };
        Canvas.SetLeft(scene, Shift);
        canvas.Children.Add(scene);

        BuildLeds();
        scene.Children.Add(leds);
        // Prizin ışığı görselin arkasında: priz görselin parçasıdır, ışık kenarlarından taşar.
        BuildSocketGlow();
        scene.Children.Add(socketGlow);
        // Xbox'lı görsel 1671 piksel genişliğindedir; Mac'teki gibi sahnenin ölçüsüne (1672×941) yayılır.
        scene.Children.Add(Home.Picture(layout.Image, SceneWidth, SceneHeight, Stretch.Fill));

        var black = new Rectangle { Width = ScreenRect.Width, Height = ScreenRect.Height, Fill = Brushes.Black };
        Place(black, ScreenRect.X, ScreenRect.Y);
        scene.Children.Add(black);
        (liveScreen, liveLine, liveBox) = Home.LiveScreen(ScreenRect.Width, ScreenRect.Height, 46);
        // Fon en arkada: CANLI rozeti ve altyazı önünde kalır.
        sunset = Home.SunsetBackdrop(ScreenRect.Width, ScreenRect.Height);
        sunset.Visibility = Visibility.Collapsed;
        liveScreen.Children.Insert(0, sunset);
        Place(screenHost, ScreenRect.X, ScreenRect.Y);
        scene.Children.Add(screenHost);
        Place(hudHost, ScreenRect.X, ScreenRect.Y);
        scene.Children.Add(hudHost);

        // Prize tıklamak da fişi takar/çıkarır.
        var socketHit = new Rectangle { Width = 120, Height = 120, Fill = Brushes.Transparent, Cursor = Cursors.Hand };
        Place(socketHit, Socket.X - 60, Socket.Y - 60);
        socketHit.MouseLeftButtonUp += (_, _) => Home.Toggle(controller);
        scene.Children.Add(socketHit);
        scene.Children.Add(cable);
        // Xbox görselinde kablo yoktur: kablo konsolun arkasındaki girişten küçük bir fiş başıyla çıkar.
        if (layout.CableLead.Count == 0)
        {
            var head = new Rectangle { Width = 14, Height = 12, RadiusX = 3, RadiusY = 3, Fill = new SolidColorBrush(Color.FromRgb(0x14, 0x14, 0x14)), IsHitTestVisible = false };
            Place(head, layout.CableStart.X - 7, layout.CableStart.Y - 6);
            scene.Children.Add(head);
        }
        plug.MouseLeftButtonDown += OnPlugDown;
        plug.MouseMove += OnPlugMove;
        plug.MouseLeftButtonUp += OnPlugUp;
        scene.Children.Add(plug);

        Content = new Viewbox { Stretch = Stretch.Uniform, StretchDirection = StretchDirection.DownOnly, Child = canvas };
        ToolTip = Home.T("Plug in to turn on Turkish subtitles");
        controller.PropertyChanged += OnChanged;
        // Toplam indirme: açılışta ve sonra aralıklarla yenilenir (alınamazsa son bilinen sayı kalır).
        downloadsTimer.Tick += (_, _) => _ = controller.RefreshDownloadsAsync();
        Loaded += (_, _) =>
        {
            _ = controller.RefreshDownloadsAsync();
            downloadsTimer.Start();
            if (introHold && introTimer is null)
            {
                introPlayed = true;
                introTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(NinoBot.ReduceMotion ? 1 : 900) };
                introTimer.Tick += (_, _) =>
                {
                    introTimer.Stop();
                    introHold = false;
                    Refresh(springPlug: true);
                };
                introTimer.Start();
            }
        };
        Unloaded += (_, _) =>
        {
            controller.PropertyChanged -= OnChanged;
            downloadsTimer.Stop();
            introTimer?.Stop();
            StopPlugSpring();
        };
        plugged = Wanted;
        leds.Opacity = plugged ? 1 : 0;
        ShowSocketGlow(animated: false);
        ShowScreen();
        DrawPlug();
    }

    private static void Place(UIElement element, double x, double y)
    {
        Canvas.SetLeft(element, x);
        Canvas.SetTop(element, y);
    }

    private void BuildLeds()
    {
        ledWide = new Rectangle { Width = TvRect.Width + 40, Height = TvRect.Height + 40, RadiusX = 30, RadiusY = 30, Effect = new BlurEffect { Radius = 90 } };
        Place(ledWide, TvRect.X - 20, TvRect.Y - 20);
        ledTight = new Rectangle { Width = TvRect.Width + 10, Height = TvRect.Height + 10, RadiusX = 10, RadiusY = 10, Effect = new BlurEffect { Radius = 24 } };
        Place(ledTight, TvRect.X - 5, TvRect.Y - 5);
        ledUnder = new Rectangle { Width = StandRect.Width - 60, Height = 40, RadiusX = 20, RadiusY = 20, Effect = new BlurEffect { Radius = 50 } };
        Place(ledUnder, StandRect.X + 30, StandRect.Bottom - 14);
        ledStrip = new Rectangle { Width = StandRect.Width - 90, Height = 8, RadiusX = 4, RadiusY = 4, Effect = new BlurEffect { Radius = 8 } };
        Place(ledStrip, StandRect.X + 45, StandRect.Bottom - 4);
        leds.Children.Add(ledWide);
        leds.Children.Add(ledTight);
        leds.Children.Add(ledUnder);
        leds.Children.Add(ledStrip);
        ColorLeds();
    }

    /// <summary>
    /// Prizin ışığı: prizin (kenarı 86 sahne pikseli) arkasında iki katman. Geniş, bulanık açık mavi kare (kenar + 26) ve
    /// dar, parlak kare (kenar + 8). Bulanıklık LED'lerdeki gibi Mac'tekinin iki katı yazılır (WPF yarıçapı farklı ölçer).
    /// </summary>
    private void BuildSocketGlow()
    {
        const double side = LivingRoomLayout.SocketSize;
        glowWide = new Rectangle { Width = side + 26, Height = side + 26, RadiusX = 16, RadiusY = 16, Fill = new SolidColorBrush(Color.FromRgb(77, 168, 255)), Effect = new BlurEffect { Radius = 36 } };
        Place(glowWide, Socket.X - (side + 26) / 2, Socket.Y - (side + 26) / 2);
        glowTight = new Rectangle { Width = side + 8, Height = side + 8, RadiusX = 12, RadiusY = 12, Fill = new SolidColorBrush(Color.FromRgb(158, 214, 255)), Effect = new BlurEffect { Radius = 10 } };
        Place(glowTight, Socket.X - (side + 8) / 2, Socket.Y - (side + 8) / 2);
        socketGlow.Children.Add(glowWide);
        socketGlow.Children.Add(glowTight);
    }

    /// <summary>
    /// Fiş takılı değilken ışık 0,95 sn'de gidip gelen yumuşak bir nabızla yanıp söner (geniş katman 0,3 ↔ 0,95, dar
    /// katman 0,45 ↔ 1); fiş takılınca 0,5 sn'de söner. Windows'ta animasyonlar kapalıysa yanıp sönmez, sabit yanar.
    /// </summary>
    private void ShowSocketGlow(bool animated)
    {
        var still = NinoBot.ReduceMotion;
        if (!plugged)
        {
            if (still)
            {
                glowWide.BeginAnimation(OpacityProperty, null);
                glowTight.BeginAnimation(OpacityProperty, null);
                glowWide.Opacity = 0.95;
                glowTight.Opacity = 1;
            }
            else
            {
                glowWide.BeginAnimation(OpacityProperty, Pulse(0.3, 0.95));
                glowTight.BeginAnimation(OpacityProperty, Pulse(0.45, 1));
            }
        }
        var fade = new DoubleAnimation(plugged ? 0 : 1, TimeSpan.FromMilliseconds(animated && !still ? 500 : 0));
        // Söndükten sonra nabız durur (görünmeyen ışık boşuna canlanmasın).
        fade.Completed += (_, _) =>
        {
            if (!plugged) return;
            glowWide.BeginAnimation(OpacityProperty, null);
            glowTight.BeginAnimation(OpacityProperty, null);
        };
        socketGlow.BeginAnimation(OpacityProperty, fade);
    }

    private static DoubleAnimation Pulse(double from, double to) => new(from, to, TimeSpan.FromSeconds(0.95))
    {
        AutoReverse = true,
        RepeatBehavior = RepeatBehavior.Forever,
        EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut },
    };

    /// <summary>
    /// LED'lerin rengi: her zamanki mavi; GTA 6 tanınınca (havuz öncelikli oyun, fonla aynı koşul) oyunun renkleri, soldan
    /// sağa pembe, mor, mavi (Mac'teki leds). Boyutlar ve bulanıklık aynı kalır; yalnız dolgu değişir.
    /// </summary>
    private void ColorLeds()
    {
        var gta = controller.LiveGamePoolFirst;
        if (ledsGta == gta) return;
        ledsGta = gta;
        if (gta)
        {
            var wide = Home.LedGlow(Color.FromRgb(255, 61, 158), Color.FromRgb(189, 128, 245), Color.FromRgb(77, 199, 255));
            var tight = Home.LedGlow(Color.FromRgb(255, 133, 199), Color.FromRgb(214, 179, 255), Color.FromRgb(148, 224, 255));
            ledWide.Fill = wide;
            ledUnder.Fill = wide;
            ledTight.Fill = tight;
            ledStrip.Fill = tight;
        }
        else
        {
            var blue = new SolidColorBrush(Home.LedBlue);
            ledWide.Fill = blue;
            ledUnder.Fill = blue;
            ledTight.Fill = new SolidColorBrush(Color.FromRgb(0x4D, 0x8C, 0xFF));
            ledStrip.Fill = new SolidColorBrush(Color.FromRgb(0x73, 0xA6, 0xFF));
        }
    }

    /// <summary>Fiş prizde mi olmalı: çeviri açık ya da açılıyor, açılış gösterisinin beklemesi de bitti.</summary>
    private bool Wanted => Home.On(controller) && !introHold;

    private void OnChanged(object? sender, PropertyChangedEventArgs e) => Dispatcher.BeginInvoke(() => Refresh());

    private void Refresh(bool springPlug = false)
    {
        var now = Wanted;
        if (now != plugged)
        {
            plugged = now;
            leds.BeginAnimation(OpacityProperty, new DoubleAnimation(now ? 1 : 0, TimeSpan.FromMilliseconds(800)));
            // Her takışta açılış animasyonu baştan oynar.
            splashDone = !now;
            splash = null;
            ShowSocketGlow(animated: true);
            StopPlugSpring();
            if (springPlug && now && !NinoBot.ReduceMotion && dragStart is null) SpringPlug();
            else DrawPlug();
        }
        ColorLeds();
        ShowScreen();
    }

    /// <summary>
    /// Fiş sarktığı yerden prize yayla gider (Mac: spring response 0,55, damping 0,7): sönümlü yay, hafifçe aşıp oturur.
    /// Yol boyunca fiş gövdesiyle görünür, oturunca kapağa döner.
    /// </summary>
    private void SpringPlug()
    {
        var from = Hanging - Socket;
        const double response = 0.55, damping = 0.7, length = 0.9;
        var omega = 2 * Math.PI / response;
        var omegaD = omega * Math.Sqrt(1 - damping * damping);
        var clock = System.Diagnostics.Stopwatch.StartNew();
        drag = from;
        DrawPlug();
        plugSpring = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(16) };
        plugSpring.Tick += (_, _) =>
        {
            var t = clock.Elapsed.TotalSeconds;
            if (t >= length)
            {
                StopPlugSpring();
                DrawPlug();
                return;
            }
            // Kalan yol: e^(−ζωt)·(cos ω_d t + ζω/ω_d · sin ω_d t), 1'den 0'a iner.
            var left = Math.Exp(-damping * omega * t) * (Math.Cos(omegaD * t) + damping * omega / omegaD * Math.Sin(omegaD * t));
            drag = from * left;
            DrawPlug();
        };
        plugSpring.Start();
    }

    private void StopPlugSpring()
    {
        if (plugSpring is null) return;
        plugSpring.Stop();
        plugSpring = null;
        drag = new Vector();
    }

    private void ShowScreen()
    {
        UIElement wanted;
        if (!plugged) wanted = offScreen;
        else if (!splashDone) wanted = splash ??= MakeSplash();
        else
        {
            Home.ShowLine(liveLine, liveBox, Home.ScreenText(controller));
            sunset.Visibility = controller.LiveGamePoolFirst ? Visibility.Visible : Visibility.Collapsed;
            wanted = liveScreen;
        }
        ShowHud();
        if (screenHost.Children.Count == 1 && screenHost.Children[0] == wanted) return;
        screenHost.Children.Clear();
        screenHost.Children.Add(wanted);
    }

    /// <summary>
    /// Toplam indirme göstergesi: fiş takılı değilken (bekleme ekranı) ve canlı ekranda aynı yerde, sağ üstte; açılış
    /// animasyonu oynarken gizli. Sayı hiç alınamadıysa görünmez. Açılış gösterisinin beklemesinde de gizli: sayı fiş
    /// takılınca canlı ekranda sayılarak çıkar (Mac: TVStandbyScreen(downloads: introHold ? nil : …)).
    /// </summary>
    private void ShowHud()
    {
        var total = controller.DownloadTotal;
        var live = plugged && splashDone;
        if (total != hudTotal || live != hudLive)
        {
            // Canlı ekrana girince (ya da sayı canlı ekrandayken ilk kez gelince) sayı 1, 2, 3 diye sayılır.
            var countsUp = live && (!hudLive || hudTotal is null);
            hudTotal = total;
            hudLive = live;
            hudHost.Children.Clear();
            if (total is { } value) hudHost.Children.Add(Home.DownloadHud(value, layout.ScreenScale, countsUp));
        }
        hudHost.Visibility = !introHold && (!plugged || splashDone) ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>Nino'nun açılışı TV'de: logo bulanıktan netleşerek büyür, arkasında ışık, sonra ad ve slogan; ~2,4 sn.</summary>
    private Grid MakeSplash()
    {
        var root = new Grid
        {
            Background = new RadialGradientBrush(Color.FromRgb(0x10, 0x26, 0x5C), Color.FromRgb(0x04, 0x08, 0x16)),
        };
        var glow = new Ellipse { Width = 360, Height = 360, Fill = new SolidColorBrush(Color.FromArgb(0x55, 0x1F, 0x5C, 0xFF)), Effect = new BlurEffect { Radius = 80 }, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 0, 120) };
        var logo = Home.Picture("logo.png", 230, 230);
        logo.VerticalAlignment = VerticalAlignment.Center;
        logo.Margin = new Thickness(0, 0, 0, 120);
        logo.RenderTransformOrigin = new Point(0.5, 0.5);
        var scale = new ScaleTransform(0.72, 0.72);
        logo.RenderTransform = scale;
        logo.Opacity = 0;
        var words = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 300, 0, 0), Opacity = 0 };
        words.Children.Add(new TextBlock { Text = "Nino", Foreground = Brushes.White, FontSize = 64, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center });
        words.Children.Add(new TextBlock { Text = Home.T("Your games, in Turkish."), Foreground = new SolidColorBrush(Color.FromArgb(0xAA, 0xFF, 0xFF, 0xFF)), FontSize = 26, HorizontalAlignment = HorizontalAlignment.Center });
        root.Children.Add(glow);
        root.Children.Add(logo);
        root.Children.Add(words);
        var spring = new BackEase { Amplitude = 0.3, EasingMode = EasingMode.EaseOut };
        logo.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(700)));
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(0.72, 1, TimeSpan.FromMilliseconds(900)) { EasingFunction = spring });
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(0.72, 1, TimeSpan.FromMilliseconds(900)) { EasingFunction = spring });
        words.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(600)) { BeginTime = TimeSpan.FromMilliseconds(650) });
        var leave = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(450)) { BeginTime = TimeSpan.FromMilliseconds(2350) };
        leave.Completed += (_, _) =>
        {
            if (splash != root) return;
            splashDone = true;
            ShowScreen();
        };
        root.BeginAnimation(OpacityProperty, leave);
        return root;
    }

    // --- Fiş ---

    private Point PlugPoint => (plugged ? Socket : Hanging) + drag;

    /// <summary>
    /// Fiş çıkıkken sehpanın yanından sarkar (siyah gövde, iki metal uç); uçlar dinlenirken aşağı bakar, prize yaklaştıkça
    /// prize döner (<see cref="LivingRoomLayout.PlugTurn(ScenePoint)"/>). Takılıyken prizin önünde yuvarlak kapak. Kablo
    /// konsoldan (PS5'te görseldeki kablonun üstünden) başlar ve fişin arkasına fişin ekseni boyunca girer.
    /// </summary>
    private void DrawPlug()
    {
        var p = PlugPoint;
        var seated = plugged && drag.Length == 0;
        plug.Children.Clear();
        if (seated)
        {
            var cap = new Ellipse
            {
                Width = 58,
                Height = 58,
                Fill = new LinearGradientBrush(Color.FromRgb(0x3D, 0x3D, 0x3D), Color.FromRgb(0x0A, 0x0A, 0x0A), 45),
                Stroke = new SolidColorBrush(Color.FromArgb(0x2E, 0xFF, 0xFF, 0xFF)),
                StrokeThickness = 1.5,
                Effect = new DropShadowEffect { BlurRadius = 12, ShadowDepth = 4, Opacity = 0.45 },
            };
            Place(cap, 31, 41);
            plug.Children.Add(cap);
        }
        else
        {
            // Parçalar fişin ortasına (60, 70) göre dizilir: üstte kablo boğazı, gövde, altta iki uç (toplam 88 yüksek).
            // Hepsi birlikte fişin ortası çevresinde döner; tıklama alanı (120×140) dönmez. Gölge dönmeyen katmandadır
            // (hep aşağı düşer).
            var turned = new Canvas { RenderTransform = new RotateTransform(layout.PlugTurn(new ScenePoint(p.X, p.Y)) * 180 / Math.PI, 60, 70) };
            var neck = new Rectangle { Width = 13, Height = 14, RadiusX = 5, RadiusY = 5, Fill = new SolidColorBrush(Color.FromRgb(0x0F, 0x0F, 0x0F)) };
            Place(neck, 53.5, 26);
            var body = new Rectangle
            {
                Width = 36,
                Height = 50,
                RadiusX = 9,
                RadiusY = 9,
                Fill = new LinearGradientBrush(Color.FromRgb(0x38, 0x38, 0x38), Color.FromRgb(0x0A, 0x0A, 0x0A), 0),
                Stroke = new SolidColorBrush(Color.FromArgb(0x24, 0xFF, 0xFF, 0xFF)),
                StrokeThickness = 1,
            };
            Place(body, 42, 40);
            turned.Children.Add(neck);
            turned.Children.Add(body);
            foreach (var x in new[] { 47.0, 67.0 })
            {
                var pin = new Rectangle { Width = 6, Height = 24, RadiusX = 3, RadiusY = 3, Fill = new LinearGradientBrush(Color.FromRgb(0xEB, 0xEB, 0xEB), Color.FromRgb(0x99, 0x99, 0x99), 0) };
                Place(pin, x, 90);
                turned.Children.Add(pin);
            }
            var shadowed = new Canvas { IsHitTestVisible = false, Effect = new DropShadowEffect { BlurRadius = 8, ShadowDepth = 3, Direction = 270, Opacity = 0.3 } };
            shadowed.Children.Add(turned);
            plug.Children.Add(shadowed);
        }
        Place(plug, p.X - 60, p.Y - 70);

        var shape = layout.Cable(new ScenePoint(p.X, p.Y), seated);
        var figure = new PathFigure { StartPoint = At(shape.Lead[0]), IsFilled = false };
        foreach (var point in shape.Lead.Skip(1)) figure.Segments.Add(new LineSegment(At(point), true));
        figure.Segments.Add(new BezierSegment(At(shape.Control1), At(shape.Control2), At(shape.End), true));
        cable.Data = new PathGeometry([figure]);
    }

    private void OnPlugDown(object sender, MouseButtonEventArgs e)
    {
        StopPlugSpring();
        dragStart = e.GetPosition(this);
        drag = new Vector();
        plug.CaptureMouse();
        e.Handled = true;
    }

    private void OnPlugMove(object sender, MouseEventArgs e)
    {
        if (dragStart is not { } start || e.LeftButton != MouseButtonState.Pressed) return;
        // Viewbox ölçeği: ekrandaki hareket görselin piksellerine çevrilir.
        var scale = ((Viewbox)Content).ActualWidth / (SceneWidth + Shift);
        drag = (e.GetPosition(this) - start) / (scale > 0 ? scale : 1);
        DrawPlug();
    }

    private void OnPlugUp(object sender, MouseButtonEventArgs e)
    {
        plug.ReleaseMouseCapture();
        var moved = drag;
        var end = (plugged ? Socket : Hanging) + moved;
        dragStart = null;
        drag = new Vector();
        DrawPlug();
        if (moved.Length < 6)
        {
            Home.Toggle(controller);
            return;
        }
        var nearSocket = (end - Socket).Length < 140;
        if (nearSocket != plugged) Home.Toggle(controller);
    }
}

/// <summary>
/// 2. arayüz: ortada cam anahtar. Kapalıyken soğuk mavi-gri, açılınca küre sağa kayar, iz bayrak kırmızısına döner ve
/// kürenin içinde ay yıldız belirir; çeviri açıkken üstte canlı TV iner.
/// </summary>
public sealed class GlassToggleView : UserControl
{
    private const double TrackWidth = 400, TrackHeight = 92, Knob = 116;
    private readonly AppController controller;
    private readonly Border redTrack;
    private readonly Grid knob;
    private readonly TranslateTransform knobMove = new();
    private readonly UIElement powerGlyph, crescent;
    private readonly Ellipse knobDisk;
    private readonly StackPanel offLabel, onLabel;
    private readonly TextBlock offTitle, offSub;
    private readonly Border tv;
    private readonly TextBlock tvLine;
    private readonly Border tvBox;
    private readonly TextBlock tvSource;
    private readonly TextBlock description;
    private bool on;

    public GlassToggleView(AppController controller)
    {
        this.controller = controller;
        // Nino: kayan düğme Arapça arayüzde aynalanmaz.
        RightToLeft.KeepLeftToRight(this);
        var root = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };

        // Canlı TV (çeviri açıkken).
        var (screen, line, box) = Home.LiveScreen(580, 326, 30);
        tvLine = line;
        tvBox = box;
        var tvFrame = new Border { Background = new SolidColorBrush(Color.FromRgb(0x0D, 0x0D, 0x12)), CornerRadius = new CornerRadius(18), Padding = new Thickness(7), Child = new Border { CornerRadius = new CornerRadius(12), ClipToBounds = true, Child = screen } };
        var stand = new StackPanel();
        stand.Children.Add(tvFrame);
        stand.Children.Add(new Rectangle { Width = 34, Height = 14, Fill = new SolidColorBrush(Color.FromRgb(0x1F, 0x1F, 0x26)) });
        stand.Children.Add(new Rectangle { Width = 150, Height = 6, RadiusX = 3, RadiusY = 3, Fill = new SolidColorBrush(Color.FromRgb(0x1F, 0x1F, 0x26)) });
        tvSource = new TextBlock { FontStyle = FontStyles.Italic, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 10, 0, 0), TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 580 };
        tvSource.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        stand.Children.Add(tvSource);
        tv = new Border { Child = stand, Margin = new Thickness(0, 0, 0, 24), Visibility = Visibility.Collapsed };
        root.Children.Add(tv);

        // Anahtar.
        var track = new Grid { Width = TrackWidth, Height = TrackHeight, Cursor = Cursors.Hand, HorizontalAlignment = HorizontalAlignment.Center };
        track.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(TrackHeight / 2),
            Background = new LinearGradientBrush(Color.FromRgb(0x78, 0x8C, 0xB3), Color.FromRgb(0x4D, 0x5C, 0x85), 90),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x73, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(1),
            Effect = new DropShadowEffect { BlurRadius = 30, ShadowDepth = 8, Opacity = 0.3, Color = Color.FromRgb(0x4D, 0x5C, 0x85) },
        });
        redTrack = new Border
        {
            CornerRadius = new CornerRadius(TrackHeight / 2),
            Background = new LinearGradientBrush(Home.FlagRed, Home.FlagDeep, 90),
            Opacity = 0,
            Effect = new DropShadowEffect { BlurRadius = 40, ShadowDepth = 6, Opacity = 0.6, Color = Home.FlagRed },
        };
        track.Children.Add(redTrack);
        track.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(TrackHeight / 2),
            Margin = new Thickness(3),
            Background = new LinearGradientBrush(Color.FromArgb(0x59, 0xFF, 0xFF, 0xFF), Color.FromArgb(0, 0xFF, 0xFF, 0xFF), 90),
            IsHitTestVisible = false,
        });

        offTitle = new TextBlock { FontSize = 22, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Right };
        offSub = new TextBlock { FontSize = 12, Foreground = new SolidColorBrush(Color.FromArgb(0xCC, 0xFF, 0xFF, 0xFF)), HorizontalAlignment = HorizontalAlignment.Right };
        offLabel = new StackPanel { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 30, 0), IsHitTestVisible = false };
        offLabel.Children.Add(offTitle);
        offLabel.Children.Add(offSub);
        onLabel = new StackPanel { HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(34, 0, 0, 0), Opacity = 0, IsHitTestVisible = false };
        onLabel.Children.Add(new TextBlock { Text = Home.T("Turkish"), FontSize = 26, FontWeight = FontWeights.Bold, Foreground = Brushes.White });
        onLabel.Children.Add(new TextBlock { Text = Home.T("Subtitles are on"), FontSize = 12, Foreground = new SolidColorBrush(Color.FromArgb(0xD9, 0xFF, 0xFF, 0xFF)) });
        track.Children.Add(offLabel);
        track.Children.Add(onLabel);

        // Cam küre: renkli disk, simge (güç / ay yıldız), buzlu cam, kenar ışığı ve sol üstte parlama.
        knob = new Grid { Width = Knob, Height = Knob, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(-(Knob - TrackHeight) / 2, 0, 0, 0), RenderTransform = knobMove, IsHitTestVisible = false };
        knobDisk = new Ellipse { Width = Knob * 0.62, Height = Knob * 0.62, Fill = new SolidColorBrush(Color.FromRgb(0x5C, 0x6E, 0x99)) };
        knob.Children.Add(knobDisk);
        powerGlyph = new TextBlock { Text = c_PowerGlyph, FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), FontSize = 30, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        knob.Children.Add(powerGlyph);
        crescent = CrescentStar(Knob * 0.45);
        crescent.Opacity = 0;
        knob.Children.Add(crescent);
        knob.Children.Add(new Ellipse { Fill = new SolidColorBrush(Color.FromArgb(0x30, 0xFF, 0xFF, 0xFF)) });
        knob.Children.Add(new Ellipse { StrokeThickness = 2, Stroke = new LinearGradientBrush(Color.FromArgb(0xF2, 0xFF, 0xFF, 0xFF), Color.FromArgb(0x60, 0xFF, 0xFF, 0xFF), 45) });
        knob.Children.Add(new Ellipse
        {
            Width = Knob * 0.55,
            Height = Knob * 0.28,
            Fill = new LinearGradientBrush(Color.FromArgb(0xA6, 0xFF, 0xFF, 0xFF), Color.FromArgb(0, 0xFF, 0xFF, 0xFF), 90),
            VerticalAlignment = VerticalAlignment.Top,
            HorizontalAlignment = HorizontalAlignment.Left,
            Margin = new Thickness(Knob * 0.1, Knob * 0.08, 0, 0),
        });
        knob.Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 8, Opacity = 0.2 };
        track.Children.Add(knob);
        track.MouseLeftButtonUp += (_, _) => Home.Toggle(controller);
        root.Children.Add(track);

        description = new TextBlock { Text = Home.T("Nino reads the PS5's English subtitles and shows them in Turkish on your TV."), TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center, MaxWidth = 440, Margin = new Thickness(0, 28, 0, 0) };
        description.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        root.Children.Add(description);

        Content = root;
        controller.PropertyChanged += OnChanged;
        Unloaded += (_, _) => controller.PropertyChanged -= OnChanged;
        on = Home.On(controller);
        Apply(animated: false);
    }

    private const string c_PowerGlyph = "";

    /// <summary>Bayraktaki ay yıldız: kırmızı zemin üstünde beyaz ay ve ucu aya bakan beş köşeli yıldız.</summary>
    internal static UIElement CrescentStar(double size)
    {
        var canvas = new Canvas { Width = size, Height = size, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        var r = size * 0.42;
        var moon = Geometry.Combine(new EllipseGeometry(new Point(size * 0.42, size / 2), r, r),
            new EllipseGeometry(new Point(size * 0.42 + r * 0.32, size / 2), r * 0.8, r * 0.8), GeometryCombineMode.Exclude, null);
        canvas.Children.Add(new Path { Data = moon, Fill = Brushes.White });
        var star = new PathFigure { IsClosed = true, IsFilled = true };
        var center = new Point(size * 0.8, size / 2);
        double outer = size * 0.17, inner = outer * 0.382;
        for (var i = 0; i < 10; i++)
        {
            var angle = Math.PI + i * Math.PI / 5;
            var radius = i % 2 == 0 ? outer : inner;
            var point = new Point(center.X + Math.Cos(angle) * radius, center.Y + Math.Sin(angle) * radius);
            if (i == 0) star.StartPoint = point; else star.Segments.Add(new LineSegment(point, true));
        }
        canvas.Children.Add(new Path { Data = new PathGeometry([star]), Fill = Brushes.White });
        return canvas;
    }

    private void OnChanged(object? sender, PropertyChangedEventArgs e) => Dispatcher.BeginInvoke(() =>
    {
        var now = Home.On(controller);
        var changed = now != on;
        on = now;
        Apply(animated: changed);
    });

    private void Apply(bool animated)
    {
        var duration = TimeSpan.FromMilliseconds(animated ? 550 : 0);
        var ease = new BackEase { Amplitude = 0.25, EasingMode = EasingMode.EaseOut };
        double travel = TrackWidth - TrackHeight, target = on ? 1 : 0;
        knobMove.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(target * travel, duration) { EasingFunction = ease });
        redTrack.BeginAnimation(OpacityProperty, new DoubleAnimation(target, duration));
        onLabel.BeginAnimation(OpacityProperty, new DoubleAnimation(target, duration));
        offLabel.BeginAnimation(OpacityProperty, new DoubleAnimation(1 - target, duration));
        powerGlyph.BeginAnimation(OpacityProperty, new DoubleAnimation(1 - target, duration));
        crescent.BeginAnimation(OpacityProperty, new DoubleAnimation(target, duration));
        knobDisk.Fill = new SolidColorBrush(on ? Home.FlagRed : Color.FromRgb(0x5C, 0x6E, 0x99));

        offTitle.Text = Home.T(controller.IsStarting ? "Connecting…" : controller.CanStart ? "Turn on" : "Connect your PS5");
        offSub.Text = Home.T(controller.CanStart || controller.IsStarting ? "Turkish subtitles" : "Tap to start setup");
        tv.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        description.Visibility = on ? Visibility.Collapsed : Visibility.Visible;
        if (on)
        {
            Home.ShowLine(tvLine, tvBox, Home.ScreenText(controller));
            tvSource.Text = controller.LastSource;
        }
    }
}
