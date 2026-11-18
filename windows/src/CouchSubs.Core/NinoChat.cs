// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Nino: "Nino'ya Sor" sohbetinin durumu (arayüzsüz). Uygulama açık kaldıkça bellekte durur (pencere kapanınca da),
/// uygulama kapanınca silinir. Yerel karşılama ve hata/uyarı baloncukları (<see cref="EntryKind.Notice"/>) sunucuya
/// gönderilmez. "Yeni sohbet" eski bir gönderimin cevabını yok sayar (nesil sayacı).
/// </summary>
public sealed class NinoChat
{
    public enum EntryKind { User, Nino, Notice }

    public sealed class Entry
    {
        public required EntryKind Kind { get; init; }
        public string Text { get; init; } = "";
        public IReadOnlyList<byte[]> Jpegs { get; init; } = [];
        /// <summary>Nino cevabında: robot ekibe bildirim gönderdiyse bildirimin kimliği ("Bildirim gönderildi ✓").</summary>
        public string? Report { get; init; }
        /// <summary>Uyarıda: neden (Disabled, RateLimited, Busy, Rejected, Failed).</summary>
        public NinoAssistant.Outcome Outcome { get; init; }
        /// <summary>Uyarıda: "Tekrar dene" gösterilsin mi (ağ ve sunucu hataları).</summary>
        public bool CanRetry => Kind == EntryKind.Notice && Outcome == NinoAssistant.Outcome.Failed;
    }

    /// <summary>Uygulama oturumu boyunca tek sohbet.</summary>
    public static NinoChat Session { get; } = new();

    private readonly List<Entry> entries = [];
    private int generation;

    public IReadOnlyList<Entry> Entries => entries;

    /// <summary>Cevap bekleniyor mu (yazıyor baloncuğu; Gönder kapalı).</summary>
    public bool Waiting { get; private set; }

    /// <summary>Henüz hiç mesaj yazılmadı mı (öneri düğmeleri yalnız o zaman görünür).</summary>
    public bool IsEmpty => entries.Count == 0;

    /// <summary>Sohbet değişti (mesaj eklendi, bekleme başladı ya da bitti, sıfırlandı).</summary>
    public event Action? Changed;

    /// <summary>Sunucuya gidecek mesajlar: kullanıcı ve Nino; uyarılar hariç.</summary>
    public IReadOnlyList<NinoAssistant.Turn> Turns() =>
    [
        .. entries.Where(entry => entry.Kind != EntryKind.Notice).Select(entry =>
            new NinoAssistant.Turn(entry.Kind == EntryKind.User ? NinoAssistant.Role.User : NinoAssistant.Role.Assistant, entry.Text, entry.Jpegs)),
    ];

    /// <summary>Sohbeti temizler; süren gönderimin cevabı gelirse yok sayılır.</summary>
    public void Reset()
    {
        generation++;
        entries.Clear();
        Waiting = false;
        Changed?.Invoke();
    }

    /// <summary>
    /// Kullanıcının mesajını ekler ve gönderir. <paramref name="send"/> sohbeti alır, sonucu döner (ağ hatası da bir sonuçtur).
    /// Beklerken ya da mesaj boşsa false.
    /// </summary>
    public async Task<bool> SendAsync(string text, IReadOnlyList<byte[]> jpegs,
                                      Func<IReadOnlyList<NinoAssistant.Turn>, Task<NinoAssistant.Result>> send)
    {
        if (Waiting || !NinoAssistant.CanSend(text, jpegs.Count)) return false;
        entries.Add(new Entry { Kind = EntryKind.User, Text = text.Trim(), Jpegs = [.. jpegs.Take(NinoAssistant.MaxImagesPerMessage)] });
        await RunAsync(send);
        return true;
    }

    /// <summary>Son mesaj "Tekrar dene"yle yeniden gönderilir: son uyarı kaldırılır, sohbet aynen yeniden gider.</summary>
    public async Task<bool> RetryAsync(Func<IReadOnlyList<NinoAssistant.Turn>, Task<NinoAssistant.Result>> send)
    {
        if (Waiting || entries.Count == 0 || !entries[^1].CanRetry) return false;
        entries.RemoveAt(entries.Count - 1);
        await RunAsync(send);
        return true;
    }

    private async Task RunAsync(Func<IReadOnlyList<NinoAssistant.Turn>, Task<NinoAssistant.Result>> send)
    {
        var mine = generation;
        Waiting = true;
        Changed?.Invoke();
        NinoAssistant.Result result;
        try { result = await send(Turns()); }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or IOException or ArgumentException)
        {
            result = new NinoAssistant.Result(NinoAssistant.Outcome.Failed);
        }
        // "Yeni sohbet"ten sonra gelen eski cevap yeni sohbete karışmaz.
        if (mine != generation) return;
        Waiting = false;
        entries.Add(result.Outcome == NinoAssistant.Outcome.Replied
            ? new Entry { Kind = EntryKind.Nino, Text = result.Reply ?? "", Report = result.Report }
            : new Entry { Kind = EntryKind.Notice, Outcome = result.Outcome });
        Changed?.Invoke();
    }
}
