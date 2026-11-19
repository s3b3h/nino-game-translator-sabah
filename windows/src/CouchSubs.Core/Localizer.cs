// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Text;
using System.Text.Json;

namespace CouchSubs.Core;

/// <summary>
/// Ekran metinleri. Mac uygulamasının Localizable.xcstrings dosyası gömülüdür ve doğrudan okunur;
/// böylece iki uygulama aynı çevirileri kullanır. Anahtar İngilizce metnin kendisidir.
/// </summary>
public sealed class Localizer
{
    private static readonly Lazy<Dictionary<string, Dictionary<string, string>>> Catalog = new(LoadCatalog);
    private readonly string language;

    private Localizer(string language) => this.language = language;

    /// <summary>Nino'nun arayüz dilleri (Mac'in Localizable.xcstrings dosyasındakiler); Filipince Apple gibi "fil".</summary>
    private static readonly string[] Interfaces = ["tr", "ar", "hi", "id", "th", "vi", "ur", "bn", "ms", "fil", "nl"];

    /// <summary>Listedeki dillerden biri (Türkçe, Arapça, Hintçe…), değilse İngilizce.</summary>
    public static Localizer ForLanguage(string language)
    {
        var code = language.ToLowerInvariant();
        if (code.StartsWith("fil") || code == "tl") return new("fil");
        var two = code.Length >= 2 ? code[..2] : code;
        return new(Interfaces.Contains(two) ? two : "en");
    }

    /// <summary>Windows'un arayüz diline göre: listedeki dillerden biri, değilse İngilizce.</summary>
    public static Localizer Current { get; } = ForLanguage(CultureInfo.CurrentUICulture.TwoLetterISOLanguageName);

    public string Language => language;

    /// <summary>Arayüz sağdan sola mı (Arapça, Urduca).</summary>
    public bool IsRightToLeft => language is "ar" or "ur";

    public string this[string key] =>
        // Nino: bu dilde çevirisi olmayan metin İngilizcesiyle gösterilir.
        !Catalog.Value.TryGetValue(key, out var values) ? key
        : values.TryGetValue(language, out var value) ? value
        : values.TryGetValue("en", out var english) ? english : key;

    /// <summary>
    /// Metni arayüz dilinin kurallarıyla büyük harfe çevirir: Türkçede "i" → "İ", "ı" → "I" (dilden bağımsız çeviri
    /// "İNDIRME" gibi yanlış yazardı). Büyük harfi olmayan yazılarda (Arapça, Hintçe, Tayca…) metin aynı kalır.
    /// </summary>
    public string Upper(string value)
    {
        try { return value.ToUpper(CultureInfo.GetCultureInfo(language)); }
        catch (CultureNotFoundException) { return value.ToUpperInvariant(); }
    }

    /// <summary>xcstrings biçim belirteçlerini (%@, %lld, %1$@ …) verilen değerlerle doldurur.</summary>
    public string Format(string key, params object[] args) => Fill(this[key], args);

    /// <summary>Türkçesi (ya da verilen dili) eksik anahtarlar.</summary>
    public static IReadOnlyList<string> MissingTranslations(string language) =>
        [.. Catalog.Value.Where(entry => !entry.Value.ContainsKey(language)).Select(entry => entry.Key)];

    internal static string Fill(string format, object[] args)
    {
        var result = new StringBuilder();
        var next = 0;
        for (var i = 0; i < format.Length; i++)
        {
            if (format[i] != '%' || i + 1 >= format.Length) { result.Append(format[i]); continue; }
            if (format[i + 1] == '%') { result.Append('%'); i++; continue; }
            var j = i + 1;
            var position = -1;
            var digits = j;
            while (digits < format.Length && char.IsDigit(format[digits])) digits++;
            if (digits > j && digits < format.Length && format[digits] == '$')
            {
                position = int.Parse(format.AsSpan(j, digits - j), CultureInfo.InvariantCulture) - 1;
                j = digits + 1;
            }
            // Uzunluk belirteçleri (l, ll, h) atlanır; ardından gelen harf türdür.
            while (j < format.Length && format[j] is 'l' or 'h' or 'q' or 'z') j++;
            if (j >= format.Length || !"@dDiuUxXfgs".Contains(format[j])) { result.Append(format[i]); continue; }
            var index = position >= 0 ? position : next++;
            result.Append(index < args.Length ? Convert.ToString(args[index], CultureInfo.CurrentCulture) : "");
            i = j;
        }
        return result.ToString();
    }

    private static Dictionary<string, Dictionary<string, string>> LoadCatalog()
    {
        var catalog = new Dictionary<string, Dictionary<string, string>>();
        using (var stream = typeof(Localizer).Assembly.GetManifestResourceStream("Localizable.xcstrings")
            ?? throw new InvalidOperationException("Localizable.xcstrings uygulamaya gömülmemiş"))
            Read(stream, catalog);
        // Nino: yalnız Windows'a ait metinler (aynı biçim); aynı anahtar varsa Windows'unki geçerlidir.
        using (var windows = typeof(Localizer).Assembly.GetManifestResourceStream("Windows.xcstrings"))
            if (windows is not null) Read(windows, catalog);
        return catalog;
    }

    private static void Read(Stream stream, Dictionary<string, Dictionary<string, string>> catalog)
    {
        using var document = JsonDocument.Parse(stream);
        foreach (var entry in document.RootElement.GetProperty("strings").EnumerateObject())
        {
            var values = new Dictionary<string, string>();
            if (entry.Value.TryGetProperty("localizations", out var localizations))
                foreach (var localization in localizations.EnumerateObject())
                    if (localization.Value.TryGetProperty("stringUnit", out var unit) && unit.TryGetProperty("value", out var value))
                        values[localization.Name] = value.GetString() ?? entry.Name;
            catalog[entry.Name] = values;
        }
    }
}
