// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core.Dubbing;

namespace CouchSubs.Core;

/// <summary>
/// Nino: havuz öncelikli oyunlarda (sunucunun <c>poolFirst</c> listesi, varsayılan GTA 6) satır önce Nino'nun çeviri
/// havuzuna (sunucuda Claude) sorulur; kullanıcının kendi motoru (Gemini, DeepL, yapay zekâ, yerel model) hiç
/// çağrılmaz. Sunucu süresinde cevap vermezse, hata verirse ya da günlük bütçe dolduysa altyazı boş kalmasın diye yalnız
/// cihazın ücretsiz çevirisine (Windows'ta Marian) düşülür. Öbür oyunlarda her şey eskisi gibi kullanıcının motoruna gider.
/// Mac'te PoolFirstTranslator.swift, Android'de PoolFirstTranslator.kt ile aynı davranış.
/// </summary>
/// <param name="engine">Kullanıcının seçtiği çevirmen (öbür oyunlar için).</param>
/// <param name="free">Ücretsiz yerel çevirmen (havuz cevap vermezse).</param>
/// <param name="poolFirst">Şu an oynanan oyun havuz öncelikli mi.</param>
/// <param name="ask">Satırı sunucuya sorar ve süresinde gelmezse null döner (<see cref="TranslationPool.TranslateFirstAsync"/>).</param>
public sealed class PoolFirstTranslator(ITextTranslator engine, ITextTranslator free, Func<bool> poolFirst,
    Func<string, CancellationToken, Task<string?>> ask) : ITextTranslator
{
    public ITextTranslator Engine { get; } = engine;

    /// <summary>Son satırı kim çevirdi: "havuz", "ücretsiz" ya da "motor" (günlük ve testler için).</summary>
    public string LastSource { get; private set; } = "";

    /// <summary>Günlük için (havuzdan gelmedi, ücretsize düşüldü vb.).</summary>
    public Action<string>? Log { get; set; }

    public async Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        if (!poolFirst())
        {
            LastSource = "motor";
            return await Engine.TranslateAsync(text, cancellationToken).ConfigureAwait(false);
        }
        string? pooled = null;
        try
        {
            pooled = await ask(text, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            pooled = null;
        }
        if (!string.IsNullOrWhiteSpace(pooled))
        {
            LastSource = "havuz";
            return pooled;
        }
        LastSource = "ücretsiz";
        Log?.Invoke("havuz öncelikli oyun: sunucudan çeviri gelmedi, ücretsiz çeviri kullanıldı");
        return await free.TranslateAsync(text, cancellationToken).ConfigureAwait(false);
    }

    public IReadOnlyList<SpokenLine> SpokenLines(string text) => LastSource == "motor" ? Engine.SpokenLines(text) : [];

    /// <summary>Okuma hattı bunu kurulurken bir kez okur; motorunki geçerli kalır (davranışı yalnız zamanlamayı değiştirir).</summary>
    public bool Prefetches => Engine.Prefetches;

    /// <summary>Havuz öncelikli oyunda motorun ön çevirisi de başlatılmaz (kullanıcının anahtarı harcanmasın).</summary>
    public void Prefetch(string text)
    {
        if (!poolFirst()) Engine.Prefetch(text);
    }

    public bool TranslatesTogether => !poolFirst() && Engine.TranslatesTogether;

    public async Task<IReadOnlyList<string>> TranslateAllAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default)
    {
        if (!poolFirst()) return await Engine.TranslateAllAsync(texts, cancellationToken).ConfigureAwait(false);
        var result = new List<string>(texts.Count);
        foreach (var text in texts) result.Add(await TranslateAsync(text, cancellationToken).ConfigureAwait(false));
        return result;
    }
}
