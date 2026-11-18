// SPDX-License-Identifier: AGPL-3.0-only

using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CouchSubs.Core;

namespace CouchSubs.App.Services;

/// <summary>
/// Nino: Sorun Bildir fotoğrafları. Dosya ya da panodaki görüntü WIC ile açılır (PNG, JPEG, BMP, GIF, TIFF; HEIC/WebP
/// Windows'ta kodlayıcısı kuruluysa), saydamlık beyaz zemine alınır, en uzun kenar 1600 piksele indirilir ve JPEG yapılır.
/// Sığdırma döngüsü (kalite, sonra boyut) <see cref="ProblemReport.FitJpeg"/>'dadır.
/// </summary>
internal static class ReportImages
{
    /// <summary>Dosyadan dondurulmuş (iş parçacıkları arasında kullanılabilir) görüntü. Açılamazsa istisna fırlatır.</summary>
    public static BitmapSource Load(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        return Load(stream);
    }

    public static BitmapSource Load(Stream stream)
    {
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        var frame = decoder.Frames[0];
        BitmapSource result = Oriented(frame, Orientation(frame));
        result = Opaque(result, honorAlpha: true);
        result.Freeze();
        return result;
    }

    /// <summary>
    /// Panodaki görüntü. Ekran alıntısı araçları PNG de koyar (saydamlığı doğru); yalnız DIB varsa WPF'in verdiği görüntünün
    /// alfa kanalı çoğu zaman sıfırdır, o yüzden alfa yok sayılır.
    /// </summary>
    public static BitmapSource? FromClipboard()
    {
        if (Clipboard.GetData("PNG") is MemoryStream png)
        {
            try { return Load(png); }
            catch (Exception error) when (error is NotSupportedException or FileFormatException or ArgumentException) { }
        }
        if (Clipboard.GetImage() is not { } image) return null;
        var result = Opaque(image, honorAlpha: false);
        result.Freeze();
        return result;
    }

    /// <summary>Gönderilecek JPEG (en çok <paramref name="maxBytes"/>, varsayılan <see cref="ProblemReport.TargetImageBytes"/>); hiçbir denemede sığmazsa null.</summary>
    public static byte[]? Jpeg(BitmapSource source, int maxBytes = ProblemReport.TargetImageBytes) =>
        ProblemReport.FitJpeg((maxSide, quality) => Encode(source, maxSide, quality), maxBytes);

    /// <summary>Açılabilecek görüntü dosyası mı (uzantıya göre). Sorun Bildir ve Nino'ya Sor aynı listeyi kullanır.</summary>
    public static bool IsImageFile(string path) =>
        Path.GetExtension(path).ToLowerInvariant() is ".png" or ".jpg" or ".jpeg" or ".heic" or ".heif" or ".webp" or ".bmp" or ".gif" or ".tif" or ".tiff";

    /// <summary>Dosya seçicinin süzgeci.</summary>
    public const string PickerPattern = "*.png;*.jpg;*.jpeg;*.heic;*.heif;*.webp;*.bmp;*.gif;*.tif;*.tiff";

    private static bool ClipboardHasPicture()
    {
        try { return Clipboard.ContainsImage() || Clipboard.ContainsFileDropList(); }
        catch (System.Runtime.InteropServices.COMException) { return false; }
    }

    /// <summary>
    /// Ctrl+V fotoğraf olarak mı yapıştırılsın: panoda görüntü ya da dosya var ve (Excel, OneNote gibi hem metin hem görüntü
    /// koyanlarda) imleç bir metin kutusunda değil.
    /// </summary>
    public static bool PastesPicture()
    {
        if (!ClipboardHasPicture()) return false;
        try { return System.Windows.Input.Keyboard.FocusedElement is not System.Windows.Controls.TextBox || !Clipboard.ContainsText(); }
        catch (System.Runtime.InteropServices.COMException) { return false; }
    }

    /// <summary>Panodaki görüntüler: dosya listesi varsa içindeki görüntü dosyaları, yoksa panodaki görüntünün kendisi.</summary>
    public static IEnumerable<Func<BitmapSource?>> FromClipboardSources()
    {
        if (Clipboard.ContainsFileDropList())
            return [.. Clipboard.GetFileDropList().Cast<string>().Where(IsImageFile).Select(path => (Func<BitmapSource?>)(() => Load(path)))];
        return [FromClipboard];
    }

    private static byte[] Encode(BitmapSource source, int maxSide, int quality)
    {
        var (width, height) = ProblemReport.FitSize(source.PixelWidth, source.PixelHeight, maxSide);
        BitmapSource scaled = width == source.PixelWidth && height == source.PixelHeight ? source
            : new TransformedBitmap(source, new ScaleTransform((double)width / source.PixelWidth, (double)height / source.PixelHeight));
        var encoder = new JpegBitmapEncoder { QualityLevel = quality };
        encoder.Frames.Add(BitmapFrame.Create(scaled));
        using var output = new MemoryStream();
        encoder.Save(output);
        return output.ToArray();
    }

    private static bool HasAlpha(PixelFormat format) =>
        format == PixelFormats.Bgra32 || format == PixelFormats.Pbgra32 || format == PixelFormats.Rgba64
        || format == PixelFormats.Prgba64 || format == PixelFormats.Rgba128Float || format == PixelFormats.Prgba128Float;

    /// <summary>JPEG'de saydamlık yok: saydam yerler beyaz zemine çizilir (siyah görünmesin), sonra 24 bit renk.</summary>
    private static BitmapSource Opaque(BitmapSource source, bool honorAlpha)
    {
        if (honorAlpha && HasAlpha(source.Format))
        {
            var visual = new DrawingVisual();
            using (var context = visual.RenderOpen())
            {
                var area = new Rect(0, 0, source.PixelWidth, source.PixelHeight);
                context.DrawRectangle(Brushes.White, null, area);
                context.DrawImage(source, area);
            }
            var target = new RenderTargetBitmap(source.PixelWidth, source.PixelHeight, 96, 96, PixelFormats.Pbgra32);
            target.Render(visual);
            source = target;
        }
        return source.Format == PixelFormats.Bgr24 ? source : new FormatConvertedBitmap(source, PixelFormats.Bgr24, null, 0);
    }

    /// <summary>Telefon fotoğraflarının EXIF yönü (1 düz, 3 ters, 6 saat yönünde 90°, 8 saat yönünün tersine 90°).</summary>
    private static int Orientation(BitmapFrame frame)
    {
        try
        {
            return frame.Metadata is BitmapMetadata metadata && metadata.GetQuery("System.Photo.Orientation") is ushort value ? value : 1;
        }
        // Yön isteğe bağlı: okunamazsa fotoğraf düz kabul edilir, açılış bozulmasın.
        catch (Exception) { return 1; }
    }

    private static BitmapSource Oriented(BitmapSource source, int orientation)
    {
        var angle = orientation switch { 3 => 180, 6 => 90, 8 => 270, _ => 0 };
        return angle == 0 ? source : new TransformedBitmap(source, new RotateTransform(angle));
    }
}
