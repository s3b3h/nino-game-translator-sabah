// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı (Mac: GameWindowCapture.swift ile aynı kurallar).

using CouchSubs.RemotePlay;

namespace CouchSubs.Shell;

/// <summary>
/// Oyun görüntüsünün nereden okunduğu. <see cref="Ps5"/>: PS5'e ikinci hesapla bağlanılır. <see cref="Window"/>: oyun bu
/// bilgisayarda PS Remote Play ya da chiaki-ng penceresinde oynanır; görüntü o pencereden okunur, çeviri pencerenin
/// üstünde gösterilir (monitörde oynayanlar için; PS5 eşleştirmesi ve ikinci hesap gerekmez). <see cref="Card"/>: görüntü bu
/// bilgisayara takılı HDMI yakalama kartından okunur; altyazı TV'ye (geçişli kart) ya da bu bilgisayara gider.
/// </summary>
[System.Text.Json.Serialization.JsonConverter(typeof(System.Text.Json.Serialization.JsonStringEnumConverter<VideoSource>))]
public enum VideoSource { Ps5, Window, Card }

/// <summary>Ekrandaki bir pencerenin özeti (Windows API'sinden bağımsız; seçim kuralları bununla sınanır).</summary>
/// <param name="Client">Pencerenin içerik alanı (başlık çubuğu ve kenarlık hariç), ekran pikseliyle.</param>
public sealed record GameWindowInfo(IntPtr Handle, string ProcessName, string Title, ScreenArea Client);

public enum GameWindowStatus { Stopped, LookingForWindow, Capturing }

/// <summary>Oyun penceresini seçme ve içindeki oyun alanını bulma kuralları.</summary>
public static class GameWindowRules
{
    /// <summary>Süreç adında ya da başlıkta aranan parçalar (küçük harf).</summary>
    public static readonly IReadOnlyList<string> Wanted = ["remoteplay", "remote play", "chiaki"];

    public const double MinWidth = 320;
    public const double MinHeight = 180;
    public const double Aspect = 16.0 / 9.0;

    /// <summary>En büyük eşleşen pencere oyundur (Remote Play'in giriş ya da ayar pencereleri daha küçüktür).</summary>
    public static GameWindowInfo? Pick(IEnumerable<GameWindowInfo> windows, IReadOnlyList<string>? wanted = null)
    {
        wanted ??= Wanted;
        return windows
            .Where(w =>
            {
                var name = (w.ProcessName + " " + w.Title).ToLowerInvariant();
                return wanted.Any(name.Contains) && w.Client.Width >= MinWidth && w.Client.Height >= MinHeight;
            })
            .OrderByDescending(w => w.Client.Width * w.Client.Height)
            .FirstOrDefault();
    }

    /// <summary>
    /// İçerik alanında oyunun durduğu 16:9 alan: Remote Play görüntüyü pencereye sığdırıp ortalar. Hesap piksellerden
    /// değil ölçüden yapılır (karanlık sahnelerde siyah bant aramak yanılır).
    /// </summary>
    public static ScreenArea GameArea(ScreenArea client)
    {
        var width = client.Width;
        var height = width / Aspect;
        if (height > client.Height)
        {
            height = client.Height;
            width = height * Aspect;
        }
        width = Math.Round(width);
        height = Math.Round(height);
        return new ScreenArea(Math.Round(client.Left + (client.Width - width) / 2), Math.Round(client.Top + (client.Height - height) / 2),
                              width, height);
    }

    public static SessionState SessionState(GameWindowStatus status) => status switch
    {
        GameWindowStatus.Capturing => RemotePlay.SessionState.Streaming,
        GameWindowStatus.LookingForWindow => RemotePlay.SessionState.Connecting,
        _ => RemotePlay.SessionState.Disconnected(DisconnectKind.Stopped),
    };

    /// <summary>
    /// Altyazı penceresinin oyun alanına oturan yeri: oyunun %90'ı genişliğinde, alt kenarından %3 yukarıda.
    /// Birimler oyun alanınınkiyle aynıdır (çağıran WPF birimine çevirir).
    /// </summary>
    public static OverlayBounds OverlayOver(ScreenArea game, double height)
    {
        var width = Math.Round(game.Width * 0.9);
        var bottom = game.Bottom - game.Height * 0.03;
        return new OverlayBounds(Math.Round(game.Left + (game.Width - width) / 2), Math.Round(bottom - height), width);
    }
}

/// <summary>Oyun penceresinden okuyan görüntü kaynağı (Windows'taki gerçeği CouchSubs.App'te).</summary>
public interface IGameWindowStream : IStreamSession
{
    /// <summary>Pencere durumu ve okunan uygulamanın adı; herhangi bir iş parçacığından.</summary>
    event Action<GameWindowStatus, string?>? WindowStatusChanged;
    /// <summary>Oyun alanının ekrandaki yeri (ekran pikseliyle) ya da null; herhangi bir iş parçacığından.</summary>
    event Action<ScreenArea?>? GameAreaChanged;
}
