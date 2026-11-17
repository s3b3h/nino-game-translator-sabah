// SPDX-License-Identifier: AGPL-3.0-only

using System.Text;

namespace CouchSubs.Core;

/// <summary>
/// Nino: çeviri dili (hedef dil) yardımcıları (Mac: core/Sources/CouchSubsCore/TargetLanguage.swift, aynı kurallar).
/// Varsayılan Türkçe; Arapça, Hintçe, Endonezce ve öbürleri seçilebilir. Sözlük, ek kuralları, Türkçe düzeltmeler, oyun
/// paketleri ve dublaj yalnız Türkçe hedefte çalışır; çevrimiçi motorlar öbür dillere de çevirir. Filipince, ilk iki harfle
/// Fince ("fi") sanılmasın diye Tagalogca koduyla ("tl") tutulur.
/// </summary>
public static class TargetLanguage
{
    public const string Turkish = "tr";
    public const string Arabic = "ar";

    /// <summary>Seçilebilen çeviri dilleri (kod, kendi dilindeki adı); Türkçe hep ilk sırada.</summary>
    public static IReadOnlyList<(string Code, string Name)> Choices { get; } =
    [
        (Turkish, "Türkçe"), (Arabic, "العربية"), ("hi", "हिन्दी"), ("id", "Bahasa Indonesia"), ("th", "ไทย"),
        ("vi", "Tiếng Việt"), ("ur", "اردو"), ("bn", "বাংলা"), ("ms", "Bahasa Melayu"), ("tl", "Filipino"),
        ("nl", "Nederlands"),
    ];

    public static string Code(string language) =>
        language.Length >= 2 ? language[..2].ToLowerInvariant() : language.ToLowerInvariant();

    public static bool IsTurkish(string target) => Code(target) == Turkish;

    public static bool IsArabic(string target) => Code(target) == Arabic;

    /// <summary>Nino'nun çevirebildiği hedef mi (listedeki dillerden biri).</summary>
    public static bool IsSupported(string target) => Choices.Any(choice => choice.Code == Code(target));

    /// <summary>Dilin kendi adı ("Türkçe", "हिन्दी"); listede yoksa kodu.</summary>
    public static string NativeName(string target) =>
        Choices.FirstOrDefault(choice => choice.Code == Code(target)).Name ?? target;

    /// <summary>İstemlerde kullanılan İngilizce dil adı.</summary>
    public static string EnglishName(string target) => Code(target) switch
    {
        "ar" => "Arabic",
        "hi" => "Hindi",
        "id" => "Indonesian",
        "th" => "Thai",
        "vi" => "Vietnamese",
        "ur" => "Urdu",
        "bn" => "Bengali",
        "ms" => "Malay",
        "tl" => "Filipino",
        "nl" => "Dutch",
        _ => "Turkish",
    };

    /// <summary>DeepL'in çevirebildiği hedef diller (Hintçe, Urduca, Bengalce, Malayca ve Filipince yok).</summary>
    public static bool DeepLSupports(string target) => Code(target) is "tr" or "ar" or "id" or "th" or "vi" or "nl";

    /// <summary>İlk açılışta çeviri dili: Windows'un arayüz dili listedeyse o, değilse Türkçe.</summary>
    public static string Preferred(string uiLanguage)
    {
        var language = uiLanguage.StartsWith("fil", StringComparison.OrdinalIgnoreCase) ? "tl" : Code(uiLanguage);
        return IsSupported(language) ? language : Turkish;
    }

    /// <summary>Sağdan sola yazılan hedef dil mi (Arapça, Urduca).</summary>
    public static bool IsRightToLeft(string target) => Code(target) is "ar" or "ur";

    /// <summary>Kendine özgü yazısı olan diller: Tay, Devanagari (Hintçe), Bengal.</summary>
    private static (char From, char To)? OwnScript(string target) => Code(target) switch
    {
        "th" => ('\u0E00', '\u0E7F'),
        "hi" => ('\u0900', '\u097F'),
        "bn" => ('\u0980', '\u09FF'),
        _ => null,
    };

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
    /// Yazı zaten hedef dilde mi: Arapça ve Urducada Arap harfli, Tayca, Hintçe ve Bengalcede o dilin yazısıyla yazılmış
    /// yazı (İngilizce oyunda çıkmaz, PS5'in kendi menüsüdür) çevirmene gönderilmez.
    /// </summary>
    public static bool IsAlready(string text, string target)
    {
        if (IsRightToLeft(target) && ContainsArabic(text)) return true;
        return OwnScript(target) is var (from, to) && text.Any(c => c >= from && c <= to);
    }

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
/// Hedef dilin yazısıyla yazılmış satırı (ör. Arapça hedefte Arap harfli satır) çevirmene göndermeden olduğu gibi döndürür; hat bunu "zaten hedef dilde" sayar ve
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
