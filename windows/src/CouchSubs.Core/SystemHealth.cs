// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;

namespace CouchSubs.Core;

/// <summary>
/// Nino: Ayarlar › Sistem sağlığı (Mac'teki HealthRecorder ile aynı). Çeviri sürerken PS5 bağlantısının, görüntü akışının
/// ve çevirinin ne kadar sağlıklı olduğunu sayar; <see cref="HealthReport"/> bu sayılardan her satır için yeşil/sarı/kırmızı
/// bir karar çıkarır. Sayılar oturum bitince silinmez (kullanıcı Ayarlar'ı çoğu zaman kötü geçen oturumdan sonra açar);
/// yeni oturum başlayınca sıfırlanır. Hız testi bilerek yok: sorun hız değil, kaybolan paketler (bkz. Mac'teki not).
/// </summary>
public sealed class HealthRecorder
{
    public static HealthRecorder Shared { get; } = new();

    private const int KeptTranslations = 200;
    private readonly object gate = new();
    private readonly Func<DateTime> now;
    private HealthSnapshot current = new();
    private DateTime? streamingSince;
    /// <summary>Görüntü durdu, yeni anahtar kare bekleniyor: libchiaki bir durmada birkaç FEC satırı yazar; bir kez sayılır.</summary>
    private bool stalled;
    private readonly List<int> translationTimes = [];

    public HealthRecorder(Func<DateTime>? clock = null) => now = clock ?? (() => DateTime.UtcNow);

    /// <summary>Yeni oturum: önceki oturumun sayıları silinir.</summary>
    public void SessionStarted()
    {
        lock (gate)
        {
            current = new HealthSnapshot { Active = true, StartedAt = now() };
            streamingSince = null;
            stalled = false;
            translationTimes.Clear();
        }
    }

    /// <summary>Oturum bitti: sayılar kalır, akış süresi kapanır.</summary>
    public void SessionEnded()
    {
        lock (gate)
        {
            CloseStreaming();
            current = current with { Active = false, StreamingNow = false };
        }
    }

    public void Connecting()
    {
        lock (gate) current = current with { ConnectAttempts = current.ConnectAttempts + 1 };
    }

    public void Streaming()
    {
        lock (gate)
        {
            current = current with { Connects = current.Connects + 1, StreamingNow = true };
            streamingSince ??= now();
        }
    }

    /// <summary><paramref name="reason"/>: bağlantının neden koptuğu; kullanıcının durdurması (null) kopma sayılmaz.</summary>
    public void Disconnected(string? reason)
    {
        lock (gate)
        {
            var drops = current.StreamingNow && reason is not null ? current.Drops + 1 : current.Drops;
            current = current with { Drops = drops, LastDisconnect = reason ?? current.LastDisconnect, StreamingNow = false };
            CloseStreaming();
        }
    }

    /// <summary>Remote Play (libchiaki) günlük satırı; saniyede yüz kez gelebilir, hızlı döner.</summary>
    public void RemotePlayLine(string line)
    {
        if (line.Contains("Send Buffer re-sending packet", StringComparison.Ordinal))
            lock (gate) current = current with { Resends = current.Resends + 1 };
        else if (line.Contains("Send Buffer overflow", StringComparison.Ordinal))
            lock (gate) current = current with { Overflows = current.Overflows + 1 };
        else if (line.Contains("FEC failed", StringComparison.Ordinal) || line.Contains("Video FEC failure", StringComparison.Ordinal))
            lock (gate)
            {
                if (!stalled) current = current with { Stalls = current.Stalls + 1 };
                stalled = true;
            }
        else if (line.Contains("Received IDR frame", StringComparison.Ordinal))
            lock (gate) stalled = false;
        else if (line.Contains("corrupt frame", StringComparison.Ordinal))
            lock (gate) current = current with { CorruptFrames = current.CorruptFrames + 1 };
    }

    /// <summary>Ekrana giden bir altyazı satırı; <paramref name="translationMs"/> paketten gelen satırda null.</summary>
    public void Line(int? translationMs)
    {
        lock (gate)
        {
            current = current with { Lines = current.Lines + 1 };
            if (translationMs is not { } ms) return;
            translationTimes.Add(ms);
            if (translationTimes.Count > KeptTranslations) translationTimes.RemoveAt(0);
            current = current with { Translations = current.Translations + 1, TranslationMaxMs = Math.Max(current.TranslationMaxMs, ms) };
        }
    }

    public HealthSnapshot Snapshot()
    {
        lock (gate)
        {
            var extra = streamingSince is { } since ? (now() - since).TotalSeconds : 0;
            return current with { StreamingSeconds = current.StreamingSeconds + extra, TranslationMedianMs = Median(translationTimes) };
        }
    }

    private void CloseStreaming()
    {
        if (streamingSince is { } since) current = current with { StreamingSeconds = current.StreamingSeconds + (now() - since).TotalSeconds };
        streamingSince = null;
    }

    internal static int? Median(List<int> values)
    {
        if (values.Count == 0) return null;
        var sorted = values.OrderBy(v => v).ToList();
        return sorted[sorted.Count / 2];
    }
}

/// <summary>Bir oturumun sağlık sayıları.</summary>
public sealed record HealthSnapshot
{
    public bool Active { get; init; }
    public DateTime? StartedAt { get; init; }
    public bool StreamingNow { get; init; }
    public double StreamingSeconds { get; init; }
    public int ConnectAttempts { get; init; }
    public int Connects { get; init; }
    /// <summary>Görüntü gelirken kopan bağlantılar.</summary>
    public int Drops { get; init; }
    public string? LastDisconnect { get; init; }
    /// <summary>Kaybolup yeniden gönderilen paketler.</summary>
    public int Resends { get; init; }
    /// <summary>Gönderim tamponu taştı (paketler sığmadı).</summary>
    public int Overflows { get; init; }
    /// <summary>Görüntünün durduğu anlar.</summary>
    public int Stalls { get; init; }
    /// <summary>Bozuk kare bildirimleri; sağlıklı bağlantıda da olur, tek başına karar vermez.</summary>
    public int CorruptFrames { get; init; }
    public int Lines { get; init; }
    public int Translations { get; init; }
    public int? TranslationMedianMs { get; init; }
    public int TranslationMaxMs { get; init; }

    /// <summary>Hiç ölçüm yok (çeviri hiç başlamadı).</summary>
    public bool IsEmpty => StartedAt is null;

    internal double StreamingMinutes => StreamingSeconds / 60;

    /// <summary>Bu kadar akış olmadan oran hesaplanmaz (ilk saniyelerdeki tek durma "dakikada 60" görünmesin).</summary>
    internal const double MinimumMinutes = 0.5;

    /// <summary>Dakikada kaybolan paket (yeniden gönderim + taşma).</summary>
    public double? LossPerMinute => StreamingMinutes >= MinimumMinutes ? (Resends + Overflows) / StreamingMinutes : null;

    /// <summary>Dakikada görüntü durması.</summary>
    public double? StallsPerMinute => StreamingMinutes >= MinimumMinutes ? Stalls / StreamingMinutes : null;
}

/// <summary>Sistem sağlığı ekranındaki bir satırın kararı.</summary>
public enum HealthLevel { Unknown, Good, Warning, Problem }

/// <summary>Bilgisayarın ağa nasıl bağlı olduğu (uygulama bulur, çekirdek yalnız karar verir).</summary>
public enum NetworkKind { Wired, Wifi, Other, Offline, Unknown }

/// <summary>
/// Sayılardan satır kararları; sınırlar Mac'tekilerle aynıdır (15 Kasım 2026'daki iki günlükle ayarlandı: Wi-Fi'deki Mac
/// dakikada ~1.370 kayıp paket ve 5,1 görüntü durması; kablolu sağlıklı Mac 0 kayıp ve 1,1 durma).
/// </summary>
public static class HealthReport
{
    public const double LossWarning = 10;
    public const double LossProblem = 100;
    public const double StallWarning = 2.5;
    public const double StallProblem = 4;
    public const int TranslationWarningMs = 1500;
    public const int TranslationProblemMs = 3000;
    public const int DropWarning = 3;

    /// <summary>Görüntü akışı: kayıp paket ve durmalar.</summary>
    public static HealthLevel Stream(HealthSnapshot s)
    {
        if (s.LossPerMinute is not { } loss || s.StallsPerMinute is not { } stalls) return HealthLevel.Unknown;
        if (loss >= LossProblem || stalls >= StallProblem) return HealthLevel.Problem;
        if (loss >= LossWarning || stalls >= StallWarning) return HealthLevel.Warning;
        return HealthLevel.Good;
    }

    /// <summary>PS5 bağlantısı: hiç bağlanamadı mı, sık mı kopuyor.</summary>
    public static HealthLevel Connection(HealthSnapshot s)
    {
        if (s.IsEmpty) return HealthLevel.Unknown;
        if (s.Connects == 0) return s.ConnectAttempts >= 2 ? HealthLevel.Problem : HealthLevel.Unknown;
        return s.Drops >= DropWarning ? HealthLevel.Warning : HealthLevel.Good;
    }

    /// <summary>Çeviri süresi (ortanca).</summary>
    public static HealthLevel Translation(HealthSnapshot s)
    {
        if (s.TranslationMedianMs is not { } median) return HealthLevel.Unknown;
        if (median >= TranslationProblemMs) return HealthLevel.Problem;
        if (median >= TranslationWarningMs) return HealthLevel.Warning;
        return HealthLevel.Good;
    }

    /// <summary>Ağ: kablo iyi; Wi-Fi tek başına ne iyi ne kötü, görüntü ölçülünce karar verilir (ölçülmeden yeşil gösterilmez).</summary>
    public static HealthLevel Network(NetworkKind kind, HealthLevel stream) => kind switch
    {
        NetworkKind.Wired => HealthLevel.Good,
        NetworkKind.Offline => HealthLevel.Problem,
        NetworkKind.Unknown => HealthLevel.Unknown,
        _ => stream,
    };

    /// <summary>Ayrıntılar için düz metin özeti (destek için kopyalanır; altyazı metni ve adres içermez).</summary>
    public static string Summary(HealthSnapshot s, NetworkKind network)
    {
        var tr = CultureInfo.InvariantCulture;
        string Rate(double? value) => value is { } v ? v.ToString("0.0", tr) + "/dk" : "-";
        return string.Join("\n",
            $"ağ: {network.ToString().ToLowerInvariant()}",
            $"akış: {s.StreamingMinutes.ToString("0.0", tr)} dk, bağlanma denemesi {s.ConnectAttempts}, bağlandı {s.Connects}, akışta kopma {s.Drops}",
            $"son kopma sebebi: {s.LastDisconnect ?? "-"}",
            $"yeniden gönderim {s.Resends}, tampon taşması {s.Overflows} (kayıp {Rate(s.LossPerMinute)})",
            $"görüntü durması {s.Stalls} ({Rate(s.StallsPerMinute)}), bozuk kare bildirimi {s.CorruptFrames}",
            $"altyazı satırı {s.Lines}, çeviri {s.Translations}, ortanca {(s.TranslationMedianMs is { } m ? m + " ms" : "-")}, en uzun {s.TranslationMaxMs} ms");
    }
}

/// <summary>Bilgisayarın şu anki ağ türü: varsayılan ağ geçidi olan, çalışan arabirimin türünden (izin istemez).</summary>
public static class NetworkKinds
{
    public static NetworkKind Detect()
    {
        try
        {
            var active = System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces()
                .Where(n => n.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up
                            && n.NetworkInterfaceType != System.Net.NetworkInformation.NetworkInterfaceType.Loopback
                            && n.GetIPProperties().GatewayAddresses.Count > 0)
                .ToList();
            if (active.Count == 0) return NetworkKind.Offline;
            if (active.Any(n => n.NetworkInterfaceType is System.Net.NetworkInformation.NetworkInterfaceType.Ethernet
                    or System.Net.NetworkInformation.NetworkInterfaceType.GigabitEthernet
                    or System.Net.NetworkInformation.NetworkInterfaceType.FastEthernetT))
                return NetworkKind.Wired;
            if (active.Any(n => n.NetworkInterfaceType == System.Net.NetworkInformation.NetworkInterfaceType.Wireless80211))
                return NetworkKind.Wifi;
            return NetworkKind.Other;
        }
        catch (Exception)
        {
            return NetworkKind.Unknown;
        }
    }
}
