// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı ("Cihaz bilgileri"nin TV, konsol ve durum satırları).

using System.Text.RegularExpressions;
using CouchSubs.Core;
using CouchSubs.Core.LgTv;
using CouchSubs.RemotePlay;

namespace CouchSubs.Shell;

/// <summary>
/// "Cihaz bilgileri"nin (<see cref="DeviceInfo"/>) TV, konsol ve durum satırları. Değerler yalnız sabit sözcüklerden ve
/// seçeneklerin adlarından kurulur: TV'nin, PS5'in ve Xbox'ın kullanıcının verdiği adı, ağ adresi, seçilen pencerenin
/// başlığı ve yakalama kartının adı girmez (ekrandaki durum yazısı bunları içerir, o yüzden kullanılmaz). Değerler
/// çevrilmez: özet sunucuya gider ve ekip okur (Sistem sağlığı'ndaki Ayrıntılar gibi).
/// </summary>
public static class DeviceReport
{
    /// <summary>
    /// TV'nin markası, (biliniyorsa) TV uygulamasının sürümü ve TV uygulaması şu an bağlı mı:
    /// "LG webOS · TV uygulaması 3.4.0 · bağlı" (Mac'teki deviceTV ile aynı sözcükler). TV'nin modeli bu uygulamada
    /// bilinmez (TV yalnız kullanıcının değiştirebildiği adını bildirir), o yüzden yazılmaz. TV yoksa null.
    /// </summary>
    public static string? Tv(LgTv? tv, string? appVersion, bool connected)
    {
        if (tv is null) return null;
        var parts = new List<string> { tv.Brand switch { TvBrand.Samsung => "Samsung Tizen", TvBrand.AndroidTv => "Android TV", _ => "LG webOS" } };
        if (IsVersion(appVersion)) parts.Add($"TV uygulaması {appVersion!.Trim()}");
        parts.Add(connected ? "bağlı" : "bağlı değil");
        return string.Join(" · ", parts);
    }

    /// <summary>Konsol ve görüntünün okunduğu yol: "PS5 · Remote Play", "Xbox Series X · uzaktan oynatma", "Yakalama kartı".</summary>
    public static string Console(UserSettings settings, GameConsoleKind kind, XboxConsole? xbox)
    {
        // Yakalama kartına hangi konsolun takılı olduğu bilinmez.
        if (settings.VideoSource == VideoSource.Card) return "Yakalama kartı";
        if (settings.VideoSource == VideoSource.Window)
            return settings.GameConsole == GameConsole.Xbox ? "Xbox · oyun penceresi" : "PS5 · oyun penceresi";
        if (kind == GameConsoleKind.Xbox) return $"{XboxModel(xbox?.Model)} · uzaktan oynatma";
        return settings.FrameSource switch
        {
            FrameSource.RemotePlayWindow => "PS5 · Remote Play penceresi" + settings.RemotePlayApp switch
            {
                RemotePlayApp.Sony => " (PS Remote Play)",
                RemotePlayApp.Chiaki => " (chiaki-ng)",
                _ => "",
            },
            FrameSource.CaptureWindow => "Seçilen pencere",
            _ => "PS5 · Remote Play",
        };
    }

    /// <summary>
    /// Şu anki durum: çeviri açık mı, görüntü kaynağının durumu ve (koptuysa) nedeni; PS5'in bildirdiği kod varsa o da
    /// ("çeviri açık, PS5: Disconnected (Rejected 0x80108bff)"). <paramref name="lastDisconnect"/> son kopmanın nedenidir
    /// (<see cref="HealthSnapshot.LastDisconnect"/>).
    /// </summary>
    public static string Status(bool running, UserSettings settings, GameConsoleKind kind, SessionState session,
                                GameWindowStatus window, CaptureCardState card, string? lastDisconnect = null)
    {
        var text = running ? "çeviri açık" : "çeviri kapalı";
        if (settings.VideoSource == VideoSource.Window) text += $", pencere: {window}";
        else if (settings.VideoSource == VideoSource.Card) text += $", kart: {card}";
        else
        {
            text += $", {(kind == GameConsoleKind.Xbox ? "Xbox" : "PS5")}: {session.Phase}";
            if (session is { Phase: SessionPhase.Disconnected, Reason: { Kind: not DisconnectKind.Stopped } reason })
                text += Code(reason.Detail) is { } code ? $" ({reason.Kind} {code})" : $" ({reason.Kind})";
        }
        // Yalnız nedenin adı ("ConsoleAsleep"); başka bir şey gelirse yazılmaz.
        if (lastDisconnect is { Length: > 0 and <= 40 } last && last.All(char.IsAsciiLetter)) text += $", son kopma: {last}";
        return text;
    }

    /// <summary>"XboxSeriesX" → "Xbox Series X". Beklenmeyen bir değer (boş, başka biçim) yalnız "Xbox" olur.</summary>
    public static string XboxModel(string? model) =>
        model is not null && Regex.IsMatch(model, "^Xbox[A-Za-z0-9]{1,20}$")
            ? Regex.Replace(model, "(?<=[a-z0-9])(?=[A-Z])", " ")
            : "Xbox";

    /// <summary>Ayrıntı yalnız konsolun bildirdiği kodsa ("0x80108b12") alınır; adres ya da serbest metin alınmaz.</summary>
    private static string? Code(string? detail) =>
        detail?.Trim() is { } text && Regex.IsMatch(text, "^0x[0-9a-fA-F]{1,8}$") ? text : null;

    /// <summary>Sürüm gibi görünen değer ("3.4.0", "0.2.6-beta.3"); başka bir metin TV satırına girmez.</summary>
    private static bool IsVersion(string? value) =>
        value is not null && Regex.IsMatch(value.Trim(), @"^[0-9][0-9A-Za-z.\-+]{0,30}$");
}
