// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// "Ekranı çevir": karenin tamamı bir kez okunur, yazılar yerlerine göre gruplara ayrılır (menü, görev paneli, bilgi
/// kutusu, altyazı...) ve her grup ayrı çevrilir. TV her çeviriyi kendi İngilizce yazısının üstüne, o yazının
/// boyutunda koyar. Sürekli çalışmaz; kullanıcı tuşa basınca bir kez yapılır (Mac: CouchSubsCore/ScreenTranslation.swift).
/// </summary>
public static class ScreenTranslation
{
    /// <summary>Ekrandaki bir yazı grubu.</summary>
    /// <param name="Paragraphs">Grubun ayrı ayrı çevrilecek parçaları (başlık, cümle, menü satırı...).</param>
    /// <param name="Box">Grubun karedeki yeri, kenarlara oranla.</param>
    /// <param name="LineHeight">Satırlarının tipik yüksekliği, karenin yüksekliğine oranla; TV yazı boyunu buna göre seçer.</param>
    public sealed record Group(IReadOnlyList<string> Paragraphs, TextBox Box, double LineHeight);

    /// <param name="Translation">Parçaların çevirisi, her parça ayrı satırda.</param>
    public sealed record Item(string Source, string Translation, TextBox Box, double LineHeight)
    {
        /// <summary>Birden çok parça var: TV satır satır, sola yaslı gösterir.</summary>
        public bool Paragraphs => Translation.Contains('\n');
        /// <summary>Nino: kutusuz, oyunun kendi yazısı gibi gölgeli sade yazı.</summary>
        public bool Plain { get; init; }
        /// <summary>Nino: eğik yazı (telefon araması).</summary>
        public bool Italic { get; init; }
        /// <summary>
        /// Nino: oyunun kendi kutusunun rengi ("#e9e9ec"); verilmişse Türkçe o kutunun üstüne, aynı zeminle ve
        /// <see cref="Ink"/> renginde yazılır (GTA 6 telefon mesaj balonları).
        /// </summary>
        public string? Fill { get; init; }
        public string? Ink { get; init; }
        /// <summary>Nino: yazının dönme açısı (derece, saat yönü artı): eğik tutulan telefonun balonları da eğiktir.</summary>
        public double? Angle { get; init; }
        /// <summary>Nino: zeminin saydamlığı (0–1; <see cref="Fill"/> ile).</summary>
        public double? Alpha { get; init; }
        /// <summary>Nino: oyunun kutusunun üstünde değil yanında duran balon (TV daha yuvarlak, gölgeli çizer).</summary>
        public bool Side { get; init; }
        /// <summary>Nino: yazısız zemin (telefonun yanındaki mesajlaşma paneli); balonlar onun üstünde durur.</summary>
        public bool Backdrop { get; init; }
        /// <summary>Nino: harita kartının Türkçesi; TV oyunun kartı gibi çizer.</summary>
        public bool Card { get; init; }
    }

    /// <summary>Kalabalık ekranda TV'yi kutuyla doldurmamak ve çeviriyi uzatmamak için en çok bu kadar grup çevrilir.</summary>
    public const int MaxGroups = 30;

    /// <summary>
    /// Kareyi okuyup gruplarını sırayla çevirir. Her grup çevrilince o ana kadarki bütün sonuçlarla
    /// <paramref name="progress"/> çağrılır; böylece TV çeviriler hazırlandıkça dolar. Çevirisi aslıyla aynı olan
    /// (ad, sayı, zaten Türkçe yazı) grup gösterilmez. Çevirmen kullanılamıyorsa <see cref="TranslatorException"/> fırlatır.
    /// </summary>
    public static async Task<IReadOnlyList<Item>> TranslateAsync(
        Frame frame, ITextReader reader, ITextTranslator translator,
        Action<IReadOnlyList<Item>>? progress = null, CancellationToken cancellationToken = default)
    {
        // Küçük karede (720p) köşe yazıları birkaç piksel boyundadır; büyütmek yazı tanımanın onları da bulmasını sağlar.
        var reading = await Task.Run(() => reader.ReadLines(frame.Height < 900 ? frame.Scaled(2) : frame, false), cancellationToken)
            .ConfigureAwait(false);
        return await TranslateAsync(reading, translator, progress, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// Okunmuş karenin gruplarını çevirir. Çevirmen parçaları tek istekte çevirebiliyorsa (yapay zekâ) ekranın bütün
    /// parçaları birlikte gider ve sonuç bir kerede gelir; yoksa gruplar sırayla çevrilip hazırlandıkça bildirilir.
    /// </summary>
    public static async Task<IReadOnlyList<Item>> TranslateAsync(
        Reading reading, ITextTranslator translator,
        Action<IReadOnlyList<Item>>? progress = null, CancellationToken cancellationToken = default)
    {
        var items = new List<Item>();
        var groups = Groups(reading);
        if (translator.TranslatesTogether)
        {
            var paragraphs = groups.SelectMany(group => group.Paragraphs).ToList();
            if (paragraphs.Count == 0) return items;
            var translations = await translator.TranslateAllAsync(paragraphs, cancellationToken).ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
            var next = 0;
            foreach (var group in groups)
            {
                var translated = Enumerable.Range(next, group.Paragraphs.Count)
                    .Select(i => i < translations.Count ? translations[i] : paragraphs[i]).ToList();
                next += group.Paragraphs.Count;
                if (Build(group, translated) is { } item) items.Add(item);
            }
            if (items.Count > 0) progress?.Invoke([.. items]);
            return items;
        }
        foreach (var group in groups)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var translated = new List<string>(group.Paragraphs.Count);
            foreach (var paragraph in group.Paragraphs)
                translated.Add(await translator.TranslateAsync(paragraph, cancellationToken).ConfigureAwait(false));
            if (Build(group, translated) is not { } item) continue;
            items.Add(item);
            progress?.Invoke([.. items]);
        }
        return items;
    }

    /// <summary>Grubun gösterilecek çevirisi; çevirisi aslıyla aynıysa (ad, sayı, zaten Türkçe yazı) null.</summary>
    private static Item? Build(Group group, IReadOnlyList<string> translations)
    {
        var changed = false;
        var texts = new List<string>(group.Paragraphs.Count);
        for (var i = 0; i < group.Paragraphs.Count; i++)
        {
            var paragraph = group.Paragraphs[i];
            var text = translations[i].Trim();
            if (text.Length == 0) text = paragraph;
            changed |= !TextMatch.IsSimilar(TextMatch.Normalize(paragraph), TextMatch.Normalize(text), 0.90);
            texts.Add(text);
        }
        return changed ? new Item(string.Join('\n', group.Paragraphs), string.Join('\n', texts), group.Box, group.LineHeight) : null;
    }

    /// <summary>
    /// Satırları gruplara toplar. Kumanda ipuçları ve yazı tanıma çöpleri atılır; harfi olmayan ya da tek harfli
    /// satırlar ("23m", "9", "+") göstergedir, çevrilmez. Bir satır, üstündeki satırın hemen altındaysa, yatayda onunla
    /// üst üste biniyorsa ve yazı boyu benziyorsa o gruba katılır. Gruplar yukarıdan aşağı, en çok <see cref="MaxGroups"/>.
    /// </summary>
    public static IReadOnlyList<Group> Groups(Reading reading)
    {
        var lines = reading.WithoutButtonPrompts().WithoutOcrNoise().Lines
            .Where(line => line.Box is not null && IsWords(line.Text))
            .OrderBy(line => line.Box!.Value.Top)
            .ToList();
        var groups = new List<List<TextLine>>();
        foreach (var line in lines)
        {
            var index = groups.FindLastIndex(group => Belongs(line.Box!.Value, group[^1].Box!.Value));
            // İki bağımsız sütuna değen geniş başlık/alt satır, sütunlardan birinin parçası değildir.
            if (index >= 0 && (BridgesColumns(groups[index][^1].Box!.Value, line.Box!.Value, lines)
                || BridgesColumns(line.Box!.Value, groups[index][^1].Box!.Value, lines))) index = -1;
            if (index >= 0) groups[index].Add(line);
            else groups.Add([line]);
        }
        return [.. groups.Take(MaxGroups).Select(group =>
        {
            var heights = group.Select(line => line.Box!.Value.Bottom - line.Box!.Value.Top).OrderBy(value => value).ToList();
            var box = group.Select(line => line.Box!.Value).Aggregate((a, b) => a.Union(b));
            return new Group(Paragraphs(group), box, heights[heights.Count / 2]);
        })];
    }

    // Geniş kutu, yan yana duran iki ayrı satırı birbirine bağlamasın. Yalnız filtrelenmiş OCR satırları kullanılır.
    private static bool BridgesColumns(TextBox wide, TextBox column, IReadOnlyList<TextLine> lines) =>
        lines.Any(line =>
        {
            var peer = line.Box!.Value;
            if (Math.Min(column.Right, peer.Right) > Math.Max(column.Left, peer.Left)) return false;
            var rowOverlap = Math.Min(column.Bottom, peer.Bottom) - Math.Max(column.Top, peer.Top);
            if (rowOverlap <= 0 || rowOverlap < Math.Min(column.Bottom - column.Top, peer.Bottom - peer.Top) * 0.5) return false;
            return (Belongs(column, wide) && Belongs(peer, wide))
                || (Belongs(wide, column) && Belongs(wide, peer));
        });

    /// <summary>Alt satır üsttekinin hemen altında (arada satır yüksekliğinin %80'inden az), yatayda onunla üst üste ve yazı boyu benzer.</summary>
    private static bool Belongs(TextBox lower, TextBox upper)
    {
        double a = upper.Bottom - upper.Top, b = lower.Bottom - lower.Top;
        if (Math.Max(a, b) > Math.Min(a, b) * 1.6) return false;
        if (lower.Top - upper.Bottom >= Math.Max(a, b) * 0.8 || lower.Top < upper.Top) return false;
        var overlap = Math.Min(lower.Right, upper.Right) - Math.Max(lower.Left, upper.Left);
        var narrower = Math.Min(lower.Right - lower.Left, upper.Right - upper.Left);
        return overlap > 0 && overlap >= narrower * 0.5;
    }

    /// <summary>
    /// Grubun satırlarını ayrı çevrilecek parçalara böler. Önceki satır cümleyi bitirdiyse ya da kısa bir başlık/menü
    /// satırıysa (en çok üç sözcük, noktalamasız) ve yeni satır büyük harfle başlıyorsa yeni parça başlar; yoksa satır
    /// öncekinin devamıdır (cümle iki satıra sarılmış).
    /// </summary>
    internal static IReadOnlyList<string> Paragraphs(IReadOnlyList<TextLine> lines)
    {
        var result = new List<string>();
        foreach (var line in lines.Select(line => line.Text.Trim()))
        {
            if (result.Count > 0 && !StartsNew(result[^1], line)) result[^1] += " " + line;
            else result.Add(line);
        }
        return result;
    }

    private static bool StartsNew(string previous, string line) =>
        SubtitleStabilizer.EndsSentence(previous) ||
        (char.IsUpper(line[0]) && WordCount(previous) <= 3 && !previous.EndsWith(','));

    /// <summary>En az iki harfi ve iki harfli bir sözcüğü olan satır yazıdır; geri kalanı sayı ve simgedir.</summary>
    internal static bool IsWords(string text) =>
        text.Count(char.IsLetter) >= 2 &&
        text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Any(word => word.Count(char.IsLetter) >= 2);

    private static int WordCount(string text) => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;

    /// <summary>Çevirilerin TV'de kalma süresi (ms): yazı çoksa daha uzun; tuşa yeniden basınca hemen kalkar.</summary>
    public static int DisplayMilliseconds(IReadOnlyList<Item> items) =>
        Math.Clamp(8000 + (items.Sum(item => item.Translation.Length) * 50), 12000, 60000);
}
