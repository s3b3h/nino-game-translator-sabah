// SPDX-License-Identifier: AGPL-3.0-only

using System.Text;

namespace CouchSubs.Core;

/// <summary>
/// Nino: çeviri dili (hedef dil) yardımcıları (Mac: core/Sources/CouchSubsCore/TargetLanguage.swift, aynı kurallar).
/// Varsayılan Türkçe; Arapça seçilebilir. Sözlük, ek kuralları, Türkçe düzeltmeler, oyun paketleri ve dublaj yalnız
/// Türkçe hedefte çalışır; çevrimiçi motorlar ve ücretsiz çeviri Arapçaya da çevirir.
/// </summary>
public static class TargetLanguage
{
    public const string Turkish = "tr";
    public const string Arabic = "ar";

    /// <summary>Seçilebilen çeviri dilleri (kod, kendi dilindeki adı).</summary>
    public static IReadOnlyList<(string Code, string Name)> Choices { get; } = [(Turkish, "Türkçe"), (Arabic, "العربية")];

    public static string Code(string language) =>
        language.Length >= 2 ? language[..2].ToLowerInvariant() : language.ToLowerInvariant();

    public static bool IsTurkish(string target) => Code(target) == Turkish;

    public static bool IsArabic(string target) => Code(target) == Arabic;

    /// <summary>Nino'nun çevirebildiği hedef mi (Türkçe ya da Arapça).</summary>
    public static bool IsSupported(string target) => IsTurkish(target) || IsArabic(target);

    /// <summary>İstemlerde kullanılan İngilizce dil adı.</summary>
    public static string EnglishName(string target) => IsArabic(target) ? "Arabic" : "Turkish";

    /// <summary>İlk açılışta çeviri dili: Windows'un arayüz dili Arapçaysa Arapça, değilse Türkçe.</summary>
    public static string Preferred(string uiLanguage) => Code(uiLanguage) == Arabic ? Arabic : Turkish;

    /// <summary>Arap yazısının harfleri (Arapça, ek harfler ve sunum biçimleri).</summary>
    public static bool IsArabicLetter(char c) => c switch
    {
        >= 'ؠ' and <= 'ي' => true,
        >= 'ٮ' and <= 'ۓ' => true,
        >= 'ۺ' and <= 'ۿ' => true,
        >= 'ݐ' and <= 'ݿ' => true,
        >= 'ࢠ' and <= 'ࣿ' => true,
        >= 'ﭐ' and <= '﷿' => true,
        >= 'ﹰ' and <= '﻿' => true,
        _ => false,
    };

    /// <summary>Yazıda Arap harfi var mı (gösterim yönü buna göre seçilir).</summary>
    public static bool ContainsArabic(string text) => text.Any(IsArabicLetter);

    /// <summary>
    /// Yazı zaten hedef dilde mi: Arapça hedefte Arap harfli yazı (PS5'in Arapça menüsü) çevirmene gönderilmez.
    /// </summary>
    public static bool IsAlready(string text, string target) => IsArabic(target) && ContainsArabic(text);

    /// <summary>
    /// Sağdan sola gösterim: Arap harfi varsa her paragrafın başına sağdan sola işareti (U+200F) konur; satır Latin harfli
    /// konuşmacı adıyla başlasa da ("ARTHUR: …") sağdan dizilir. Arap harfi yoksa yazı olduğu gibi döner.
    /// </summary>
    public static string DisplayText(string text)
    {
        if (!ContainsArabic(text)) return text;
        const char Mark = '‏';
        var builder = new StringBuilder(text.Length + 4);
        foreach (var paragraph in text.Split('\n'))
        {
            if (builder.Length > 0) builder.Append('\n');
            if (!paragraph.StartsWith(Mark)) builder.Append(Mark);
            builder.Append(paragraph);
        }
        return builder.ToString();
    }
}

/// <summary>
/// Arapça hedefte Arap harfli satırı çevirmene göndermeden olduğu gibi döndürür; hat bunu "zaten hedef dilde" sayar ve
/// göstermez. Türkçe hedefte satırlar doğrudan çevirmene gider.
/// </summary>
public sealed class TargetScriptGuard(ITextTranslator inner, string target) : ITextTranslator
{
    public ITextTranslator Inner { get; } = inner;

    public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default) =>
        TargetLanguage.IsAlready(text, target) ? Task.FromResult(text) : Inner.TranslateAsync(text, cancellationToken);

    public IReadOnlyList<Dubbing.SpokenLine> SpokenLines(string text) => Inner.SpokenLines(text);

    public bool Prefetches => Inner.Prefetches;

    public void Prefetch(string text)
    {
        if (!TargetLanguage.IsAlready(text, target)) Inner.Prefetch(text);
    }
}
