// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı (Mac: CaptureCardCapture.swift ile aynı kurallar).

using CouchSubs.RemotePlay;

namespace CouchSubs.Shell;

/// <summary>
/// Bilgisayara takılı bir görüntü aygıtının özeti (Windows API'sinden bağımsız; seçim kuralları bununla sınanır).
/// </summary>
/// <param name="Group">Aygıtın kabı (Windows'ta System.Devices.ContainerId): aynı USB kartın görüntü ve ses aygıtı aynı
/// kaptadır. Bilinmiyorsa boş.</param>
public sealed record CaptureCardInfo(string Id, string Name, string Group = "");

public enum CaptureCardState
{
    Stopped,
    /// <summary>Windows'un kamera izni kapalı (Ayarlar › Gizlilik ve güvenlik › Kamera).</summary>
    NeedsPermission,
    /// <summary>Takılı kart bulunamadı.</summary>
    NoCard,
    /// <summary>Kart bağlı ama görüntü simsiyah: PS5 kapalı, kablo takılı değil ya da PS5'te HDCP açık.</summary>
    BlackPicture,
    Capturing,
}

/// <summary>Kartın durumu ve (bağlıysa) adı.</summary>
public sealed record CaptureCardStatus(CaptureCardState State, string? Name = null)
{
    public static readonly CaptureCardStatus Stopped = new(CaptureCardState.Stopped);
    public static readonly CaptureCardStatus NeedsPermission = new(CaptureCardState.NeedsPermission);
    public static readonly CaptureCardStatus NoCard = new(CaptureCardState.NoCard);
    public static CaptureCardStatus BlackPicture(string name) => new(CaptureCardState.BlackPicture, name);
    public static CaptureCardStatus Capturing(string name) => new(CaptureCardState.Capturing, name);

    /// <summary>Kart görüntü veriyor (siyah da olsa).</summary>
    public bool HasPicture => State is CaptureCardState.Capturing or CaptureCardState.BlackPicture;
}

/// <summary>
/// Takılı aygıtlar arasından oyunun geldiği kartı seçer. HDMI yakalama kartları Windows'ta kamera gibi görünür (UVC);
/// dizüstünün kamerası ya da takılı bir web kamerası da aynı listede çıkar. Adı bilinen bir karta benzeyen önce seçilir.
/// </summary>
public static class CaptureCardPicker
{
    /// <summary>Kart adlarında sık geçen parçalar (küçük harf).</summary>
    public static readonly IReadOnlyList<string> Hints =
        ["capture", "hdmi", "elgato", "avermedia", "live gamer", "game", "cam link", "razer", "ripsaw", "ugreen", "usb video",
         "uvc", "hd60", "4k x", "4k s", "magewell", "video"];

    /// <summary>Web kamerası olduğu belli olanlar (yakalama kartı değil).</summary>
    public static readonly IReadOnlyList<string> Cameras =
        ["webcam", "logitech", "brio", "c920", "c922", "integrated camera", "integrated webcam", "front", "rear", "ir camera",
         "hd camera", "facetime"];

    /// <param name="preferred">Kullanıcının seçtiği aygıt (takılıysa o).</param>
    public static CaptureCardInfo? Pick(IEnumerable<CaptureCardInfo> devices, string? preferred = null)
    {
        var list = devices.ToList();
        if (preferred is not null && list.FirstOrDefault(d => d.Id == preferred) is { } chosen) return chosen;
        var usable = list.Where(d => !Matches(d.Name, Cameras)).ToList();
        return usable.FirstOrDefault(d => Matches(d.Name, Hints)) ?? usable.FirstOrDefault();
    }

    /// <summary>
    /// Bilgisayarın kendi aygıtlarının (yerleşik kamera, mikrofon, takılı PCIe kart) ortak kabı: bununla eşleştirmek
    /// bilgisayarın mikrofonunu hoparlöre verirdi.
    /// </summary>
    public const string SystemGroup = "{00000000-0000-0000-ffff-ffffffffffff}";

    /// <summary>Kartın ses aygıtı: aynı kaptaki (aynı USB aygıtı), yoksa adı benzeyen; bulunamazsa null (ses çalınmaz).</summary>
    public static CaptureCardInfo? Audio(CaptureCardInfo card, IEnumerable<CaptureCardInfo> devices)
    {
        var list = devices.ToList();
        var ownGroup = card.Group.Length > 0 && !string.Equals(card.Group, SystemGroup, StringComparison.OrdinalIgnoreCase)
                       && !string.Equals(card.Group.Trim('{', '}'), SystemGroup.Trim('{', '}'), StringComparison.OrdinalIgnoreCase);
        if (ownGroup && list.FirstOrDefault(d => string.Equals(d.Group, card.Group, StringComparison.OrdinalIgnoreCase)) is { } same)
            return same;
        var name = card.Name.ToLowerInvariant();
        if (name.Length == 0) return null;
        return list.FirstOrDefault(d =>
        {
            var other = d.Name.ToLowerInvariant();
            return other.Length > 0 && (other.Contains(name) || name.Contains(other));
        });
    }

    private static bool Matches(string name, IReadOnlyList<string> parts)
    {
        var lower = name.ToLowerInvariant();
        return parts.Any(lower.Contains);
    }
}

/// <summary>Karenin neredeyse tamamen siyah olup olmadığı (PS5'te HDCP açıkken kart simsiyah görüntü verir).</summary>
public static class BlackFrame
{
    /// <summary>En parlak örneğin bile bu değeri geçmediği kare siyahtır.</summary>
    public const int Threshold = 24;

    /// <summary>BGRA satırlarından seyrek örnek alır (her <paramref name="step"/> pikselde bir).</summary>
    public static bool IsBlack(ReadOnlySpan<byte> bgra, int width, int height, int stride, int step = 32)
    {
        for (var y = step / 2; y < height; y += step)
        {
            var row = y * stride;
            for (var x = step / 2; x < width; x += step)
            {
                var p = row + x * 4;
                if (p + 2 >= bgra.Length) return true;
                if (bgra[p] > Threshold || bgra[p + 1] > Threshold || bgra[p + 2] > Threshold) return false;
            }
        }
        return true;
    }
}

/// <summary>
/// Siyah görüntü bekçisi: kare bu kadar saniye art arda siyah gelirse "siyah görüntü" (HDCP uyarısı) denir; tek bir
/// karanlık sahne ya da yükleme ekranı uyarı çıkarmaz.
/// </summary>
public sealed class BlackPictureWatch(double seconds = BlackPictureWatch.DefaultSeconds)
{
    public const double DefaultSeconds = 4;
    private double? blackSince;

    /// <summary>Yeni karenin sonucu; <paramref name="now"/> saniye cinsinden. Dönen: görüntü siyah sayılıyor mu.</summary>
    public bool Update(bool black, double now)
    {
        if (!black)
        {
            blackSince = null;
            return false;
        }
        blackSince ??= now;
        return now - blackSince.Value >= seconds;
    }

    public void Reset() => blackSince = null;
}

/// <summary>Yakalama kartına ait küçük kurallar.</summary>
public static class CaptureCardRules
{
    public const int OutputWidth = 1920;
    public const int OutputHeight = 1080;
    /// <summary>Okuma hattına saniyede verilen kare (kart saniyede 60 verir; okuma zaten önceki kare bitmeden yenisini almaz).</summary>
    public const int FramesPerSecond = 10;

    /// <summary>Okuma hattı için durum: görüntü geliyorsa (siyah da olsa) akış sürüyor sayılır.</summary>
    public static SessionState SessionState(CaptureCardStatus status) => status.State switch
    {
        CaptureCardState.Capturing or CaptureCardState.BlackPicture => RemotePlay.SessionState.Streaming,
        CaptureCardState.Stopped => RemotePlay.SessionState.Disconnected(DisconnectKind.Stopped),
        _ => RemotePlay.SessionState.Connecting,
    };

    /// <summary>Oyun penceresinin içerik alanında görüntünün durduğu 16:9 alan (pencere ne boyda olursa olsun ortalanır).</summary>
    public static ScreenArea GameArea(ScreenArea content) => GameWindowRules.GameArea(content);

    /// <summary>Okuma hattına kare verme zamanı geldi mi (saniyede <see cref="FramesPerSecond"/> kare).</summary>
    public static bool DueForPipeline(double now, double lastEmit) => now - lastEmit >= 1.0 / FramesPerSecond - 0.002;

    /// <summary>
    /// Kartın sunduğu biçimlerden okunacak olan: önce tam 1920 × 1080, sonra en akıcı (60'a kadar), sonra 1080'e en yakın
    /// boy, en son sıkıştırılmamış görüntü (NV12, YUY2; MJPG çözmek gecikme ve işlemci yükü ekler).
    /// </summary>
    public static CardVideoFormat? PickFormat(IEnumerable<CardVideoFormat> formats) => formats
        .Where(f => f.Width > 0 && f.Height > 0 && f.FramesPerSecond > 0)
        .OrderByDescending(f => f.Width == OutputWidth && f.Height == OutputHeight)
        .ThenByDescending(f => Math.Round(Math.Min(f.FramesPerSecond, 60)))
        .ThenBy(f => Math.Abs(f.Height - OutputHeight))
        .ThenByDescending(f => IsUncompressed(f.Subtype))
        .FirstOrDefault();

    public static bool IsUncompressed(string subtype) =>
        subtype.ToUpperInvariant() is "NV12" or "YUY2" or "RGB32" or "ARGB32" or "BGRA8" or "UYVY" or "I420" or "IYUV";
}

/// <summary>Kartın sunduğu bir görüntü biçimi (Windows API'sinden bağımsız).</summary>
public sealed record CardVideoFormat(int Width, int Height, double FramesPerSecond, string Subtype);

/// <summary>Yakalama kartından okuyan görüntü kaynağı (Windows'taki gerçeği CouchSubs.App'te).</summary>
public interface ICaptureCardStream : IStreamSession
{
    /// <summary>Kartın durumu; herhangi bir iş parçacığından.</summary>
    event Action<CaptureCardStatus>? CardStatusChanged;
    /// <summary>Oyunu gösteren penceredeki oyun alanının ekrandaki yeri (ekran pikseliyle) ya da null.</summary>
    event Action<ScreenArea?>? GameAreaChanged;
    /// <summary>Kullanıcı oyunu gösteren pencereyi kapattı (çeviri durmalı).</summary>
    event Action? PlayerClosed;
    /// <summary>Oyun penceresini tam ekrana alır ya da tam ekrandan çıkarır (pencere yoksa bir şey yapmaz).</summary>
    void ToggleFullScreen();
}
