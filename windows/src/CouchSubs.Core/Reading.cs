// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>Yazının yeri, içinde bulunduğu alanın kenarlarına oranla (0–1, üstten ve soldan).</summary>
public readonly record struct TextBox(double Left, double Top, double Right, double Bottom)
{
    public TextBox Union(TextBox other) =>
        new(Math.Min(Left, other.Left), Math.Min(Top, other.Top), Math.Max(Right, other.Right), Math.Max(Bottom, other.Bottom));

    /// <summary>Bu kutu <paramref name="area"/> içindeki oranlarsa, aynı yerin <paramref name="area"/>'yı içeren çerçevedeki oranları.</summary>
    public TextBox PlacedIn(TextBox area)
    {
        var width = area.Right - area.Left;
        var height = area.Bottom - area.Top;
        return new(area.Left + (Left * width), area.Top + (Top * height), area.Left + (Right * width), area.Top + (Bottom * height));
    }

    /// <summary>
    /// Ekranın ortasındaki altyazının kutusu ortaya göre simetrik genişletilir. Açık zeminde ya da renkli yazıda yazı
    /// tanıma satırın bir ucunu okuyamayabilir; kutu yalnız okunan parçayı örterse İngilizcenin geri kalanı yanda görünür
    /// ve çeviri ortalanmamış durur. Ortadan uzak (köşedeki) yazıya dokunulmaz (Mac: TextBox.centeredOnScreen).
    /// </summary>
    public TextBox CenteredOnScreen()
    {
        var middle = (Left + Right) / 2;
        if (middle <= 0.3 || middle >= 0.7) return this;
        return this with { Left = Math.Max(0, Math.Min(Left, 1 - Right)), Right = Math.Min(1, Math.Max(Right, 1 - Left)) };
    }
}

/// <summary>
/// Yazı tanımanın bulduğu bir satır; kutu okunan alana göredir, bilinmiyorsa null. Güven 0–1'dir; okuyucu vermiyorsa
/// null (Windows'un yazı tanıması vermez).
/// </summary>
public sealed record TextLine(string Text, TextBox? Box = null, double? Confidence = null);

/// <summary>Bir karenin okunan satırları, yukarıdan aşağı (Mac: CouchSubsCore/Reading.swift).</summary>
public sealed class Reading
{
    public static readonly Reading Empty = new([]);

    public Reading(IEnumerable<TextLine> lines) =>
        Lines = [.. lines.Where(line => !string.IsNullOrWhiteSpace(line.Text))];

    public IReadOnlyList<TextLine> Lines { get; }

    /// <summary>Satırları ayrı ayrı bilinmeyen okuyucular için: her satır sonu bir satırdır.</summary>
    public static Reading FromText(string text) =>
        new(text.Replace("\r\n", "\n").Split('\n').Select(line => new TextLine(line.Trim())));

    public string Text => string.Join('\n', Lines.Select(line => line.Text));

    /// <summary>
    /// Aynı satırdaki iki sözcük arasındaki boşluk (piksel) ayrı yazılara mı işaret ediyor? Yalnız hem satır yüksekliğinin
    /// dört katından hem görüntü genişliğinin %12'sinden genişse: soldaki menü ile sağdaki gösterge böyle ayrılır.
    /// Daha dar boşluk çoğunlukla okunamayan sözcüklerdir (açık zemindeki ince altyazıda yazı tanıma bazı sözcükleri
    /// atlar); orada bölmek cümleyi parçalara ayırır, parçanın çevirisi anlamsızlaşır ve kutusu satırı örtmez (GTA V).
    /// </summary>
    public static bool IsSeparateText(double gap, double lineHeight, double imageWidth) =>
        gap > lineHeight * 4 && gap > imageWidth * 0.12;

    /// <summary>Bütün satırları içine alan kutu; hiçbir satırın yeri bilinmiyorsa null.</summary>
    public TextBox? Box
    {
        get
        {
            TextBox? total = null;
            foreach (var line in Lines)
                if (line.Box is { } box) total = total?.Union(box) ?? box;
            return total;
        }
    }

    /// <summary>Satırların ortalama tanıma güveni (0–1); okuyucu güven vermiyorsa null.</summary>
    public double? Confidence =>
        Lines.Where(line => line.Confidence is not null).Select(line => line.Confidence!.Value).ToList() is { Count: > 0 } values
            ? values.Average() : null;

    /// <summary>Oyunun düğme ipuçları ("R2 Swing", "△ Pick up") çıkarılmış hali; bunlar altyazı değildir.</summary>
    public Reading WithoutButtonPrompts() => new(Lines.Where(line => !ButtonPrompts.IsPrompt(line.Text)));

    /// <summary>
    /// Yazı tanımanın uydurduğu sözcük çöpleri ("ou$3e", "waters2aljd") ayıklanmış hali; çevirmen bunları olduğu
    /// gibi taşıyıp TV'de anlamsız harfler gösteriyordu.
    /// </summary>
    /// <summary>
    /// Nino: okunan alanın hem sol hem sağ kenarına değen satır kesiktir, altyazı değildir (oyunun açılıştaki yasal uyarısı,
    /// PS5 menüsündeki kayan yazı). Yalnız bir kenara değen satır kalır (Mac: Reading.withoutClippedLines).
    /// </summary>
    public Reading WithoutClippedLines(double margin = 0.015) =>
        new(Lines.Where(line => line.Box is not { } box || !(box.Left <= margin && box.Right >= 1 - margin)));

    /// <summary>
    /// Nino: dev yazı altyazı değildir. Oyunun içindeki tabela, reklam panosu, dükkân adı ya da ekranı kaplayan başlık
    /// altyazı sanılıp çevriliyor, TV'de de yazının kapladığı yer kadar kocaman siyah bir kutu çıkıyordu. Altyazı satırı
    /// ekran yüksekliğinin yaklaşık %2,5-5'i kadardır (en büyük erişilebilirlik ayarında %6); bundan belirgin biçimde
    /// büyük satır atılır (Mac: Reading.maxSubtitleLineHeight).
    /// </summary>
    public const double MaxSubtitleLineHeight = 0.075;

    /// <summary>
    /// Altyazı bloğunun karede kaplayabileceği en çok yükseklik ve satır sayısı; aşan blok altyazı değildir (afiş, not,
    /// belge, üst üste tabelalar).
    /// </summary>
    public const double MaxSubtitleBlockHeight = 0.26;
    public const int MaxSubtitleLines = 5;

    /// <summary>
    /// Dev satırlar (bkz. <see cref="MaxSubtitleLineHeight"/>) çıkarılmış hali. Ölçü karenin tamamına göredir
    /// (<paramref name="area"/>: okunan alanın karedeki yeri), dar seçilmiş alanda normal satır büyük görünmesin. Yeri
    /// bilinmeyen satıra dokunulmaz (Mac: Reading.withoutOversizedLines).
    /// </summary>
    /// <remarks>
    /// Temkinlidir (V3.4.1): <paramref name="limit"/>ten yüksek satır yalnız etiket gibiyse (tabela, pano) atılır. Cümle
    /// gibi satır, yanındaki gösterge ya da tabela harfiyle aynı sıraya düşüp yüksek ölçülmüş gerçek altyazı olabilir
    /// ("What happened? 0006"); o ancak <see cref="MaxSentenceLineHeight"/>i aşarsa atılır.
    /// </remarks>
    public Reading WithoutOversizedLines(TextBox area, double limit = MaxSubtitleLineHeight)
    {
        var scale = area.Bottom - area.Top;
        return new(Lines.Where(line =>
        {
            if (line.Box is not { } box) return true;
            var height = (box.Bottom - box.Top) * scale;
            if (height > Math.Max(limit, MaxSentenceLineHeight)) return false;
            return !(height > limit && IsLabelLike(line.Text));
        }));
    }

    /// <summary>Cümle gibi görünen satır bu kadar yüksekse de atılır (karenin %13'ü).</summary>
    public const double MaxSentenceLineHeight = 0.13;

    /// <summary>
    /// Etiket gibi satır: en çok 4 sözcük ve cümle noktalaması yok ("OHM BOY", "Boat Charters", "YARD SALE"). Altyazı
    /// satırı ya uzundur ya da noktalamalıdır ("What?", "We made it!"). Mac: Reading.isLabelLike.
    /// </summary>
    public static bool IsLabelLike(string raw)
    {
        var words = raw.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Count(word => word.Any(char.IsLetter));
        return words <= 4 && raw.IndexOfAny(['.', ',', '!', '?', '…']) < 0;
    }

    /// <summary>Blok bir altyazı için fazla mı yüksek ya da fazla mı satırlı (bkz. <see cref="MaxSubtitleBlockHeight"/>).</summary>
    public bool IsOversizedBlock(TextBox area)
    {
        if (Lines.Count > MaxSubtitleLines) return true;
        return Box is { } box && (box.Bottom - box.Top) * (area.Bottom - area.Top) > MaxSubtitleBlockHeight;
    }

    public Reading WithoutOcrNoise() => new(Lines.Select(line => line with { Text = OcrNoise.Clean(line.Text) }));

    /// <summary>
    /// Aynı satırda yan yana okunan parçalar soldan sağa tek satır olur. Renkli konuşan adını ("Arthur:", RDR2) yazı
    /// tanıma cümleden ayrı okuyabiliyor; parçalar yalnız üst kenarlarına göre dizilince ad cümlenin sonuna düşüyor ya da
    /// ayrı blok sayılıp atılıyordu. Yatayda aralarında en çok <see cref="RowGap"/> (alan genişliğine oranla) olan
    /// parçalar birleşir; uzaktaki köşe yazısı ayrı kalır (Mac: Reading.joiningRows, Android: Reading.joiningRows).
    /// </summary>
    public Reading JoiningRows()
    {
        if (Lines.Count < 2 || Lines.Any(line => line.Box is null)) return this;
        var rows = new List<TextLine>();
        foreach (var line in Lines.OrderBy(line => line.Box!.Value.Left))
        {
            var box = line.Box!.Value;
            var index = rows.FindIndex(row => SameRow(box, row.Box!.Value));
            if (index >= 0)
            {
                var row = rows[index];
                double? confidence = row.Confidence is { } a && line.Confidence is { } b ? Math.Min(a, b) : row.Confidence ?? line.Confidence;
                rows[index] = new TextLine(row.Text + " " + line.Text, row.Box!.Value.Union(box), confidence);
            }
            else
            {
                rows.Add(line);
            }
        }
        return new Reading(rows.OrderBy(row => row.Box!.Value.Top));
    }

    /// <summary><see cref="JoiningRows"/>: aynı satırdaki iki parça arasındaki en büyük boşluk (alan genişliğine oranla).</summary>
    public const double RowGap = 0.05;

    private static bool SameRow(TextBox next, TextBox row)
    {
        var overlap = Math.Min(next.Bottom, row.Bottom) - Math.Max(next.Top, row.Top);
        var smaller = Math.Min(next.Bottom - next.Top, row.Bottom - row.Top);
        if (smaller <= 0 || overlap < smaller * 0.6) return false;
        return next.Left - row.Right <= RowGap;
    }

    /// <summary>
    /// Alandaki altyazı bloğu. Seçilen alanda altyazının yanında menü ("MAP / HELP / SETTINGS" alt alta), köşedeki
    /// gösterge ("9", "PHOTO MODE") da okunuyordu; hepsi tek cümle gibi çevrilip TV'de bütün alanı kaplayan kutuyla
    /// gösteriliyordu. Satırlar yerlerine göre bloklara ayrılır; ortalanmış ve menü olmayan en alttaki blok altyazıdır.
    /// Ortalanmış blok yoksa en az üç sözcüklü, menü olmayan en alttaki blok alınır. Satırların yeri bilinmiyorsa
    /// okuma olduğu gibi kalır. <paramref name="area"/>, okunan alanın karedeki yeridir (Mac: Reading.subtitleBlock).
    /// </summary>
    public Reading SubtitleBlock(TextBox area)
    {
        if (Lines.Count == 0 || Lines.Any(line => line.Box is null)) return this;
        var blocks = new List<List<TextLine>>();
        foreach (var line in Lines.OrderBy(line => line.Box!.Value.Top))
        {
            var box = line.Box!.Value.PlacedIn(area);
            var index = blocks.FindLastIndex(block => Belongs(box, block, area));
            if (index >= 0) blocks[index].Add(line);
            else blocks.Add([line]);
        }
        var candidates = blocks.Select(block => new Reading(block)).Where(reading => !reading.IsMenu).ToList();
        var centered = candidates.Where(reading =>
        {
            var box = reading.Box!.Value.PlacedIn(area);
            return Math.Abs(((box.Left + box.Right) / 2) - 0.5) <= 0.12;
        }).ToList();
        if (centered.Count > 0) return centered.MaxBy(reading => reading.Box!.Value.Bottom)!;
        return candidates.Where(reading => WordCount(reading.Text) >= 3).MaxBy(reading => reading.Box!.Value.Bottom) ?? Empty;
    }

    /// <summary>Bloğun son satırının hemen altında ve yatayda onunla üst üste binen satır o bloğa aittir.</summary>
    private static bool Belongs(TextBox box, List<TextLine> block, TextBox area)
    {
        var last = block[^1].Box!.Value.PlacedIn(area);
        var height = Math.Max(box.Bottom - box.Top, last.Bottom - last.Top);
        if (box.Top - last.Bottom >= height * 0.8 || box.Top < last.Top) return false;
        var overlap = Math.Min(box.Right, last.Right) - Math.Max(box.Left, last.Left);
        var narrower = Math.Min(box.Right - box.Left, last.Right - last.Left);
        return overlap > 0 && overlap >= narrower * 0.5;
    }

    /// <summary>Alt alta kısa ve noktalamasız satırlar ("MAP", "HELP", "SOCIAL CLUB") menüdür, konuşma değil.</summary>
    internal bool IsMenu => Lines.Count >= 3 &&
        Lines.All(line => WordCount(line.Text) <= 3 && !SubtitleStabilizer.EndsSentence(line.Text));

    private static int WordCount(string text) => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;

    /// <summary>Satır kutularını <paramref name="area"/> içindeki oranlardan dış çerçevenin oranlarına taşır.</summary>
    public Reading PlacedIn(TextBox area) => new(Lines.Select(line => line with { Box = line.Box?.PlacedIn(area) }));
}

/// <summary>
/// Oyunların ekranda gösterdiği kumanda ipuçlarını tanır: "R2 Swing", "L1 + R1 Spartan Rage", "△ Pick up",
/// "Press ✕ to jump". Konuşma satırları dokunulmadan kalır (Mac'teki ButtonPrompts ile aynı kurallar).
/// </summary>
public static class ButtonPrompts
{
    /// <summary>Her zaman kumanda düğmesi olan simgeler ve adlar (yazı tanıma bazen köşeli parantezle okur).</summary>
    private static readonly HashSet<string> Buttons = new(StringComparer.OrdinalIgnoreCase)
    {
        "R1", "R2", "R3", "L1", "L2", "L3", "OPTIONS", "TOUCHPAD",
        "✕", "×", "⨯", "✖", "○", "◯", "●", "□", "▢", "◻", "■", "△", "▲", "⨂",
    };

    /// <summary>Simge yazı tanımada harfe dönüşebilir; yalnız ipucu kalıbında düğme sayılır.</summary>
    private static readonly HashSet<string> Lookalikes = new(StringComparer.Ordinal) { "X", "O" };

    private static readonly HashSet<string> Verbs = new(StringComparer.OrdinalIgnoreCase)
    {
        "press", "hold", "tap", "push", "use", "mash", "release",
    };

    private static readonly char[] Separators = [' ', '\t', '+', '/'];
    private static readonly char[] Brackets = ['(', ')', '[', ']', '{', '}', '<', '>', '「', '」'];

    public static bool IsPrompt(string line)
    {
        var tokens = line.Split(Separators, StringSplitOptions.RemoveEmptyEntries)
            .Select(token => token.Trim(Brackets))
            .Where(token => token.Length > 0)
            .ToList();
        if (tokens.Count == 0) return false;
        var first = tokens[0];
        var words = tokens.Count(token => !Buttons.Contains(token) && token.Any(char.IsLetter));

        // "R2 Swing", "△ Pick up", "L1 R1 Spartan Rage"
        if (Buttons.Contains(first)) return words <= 5;
        // "PHOTO MODE L1 + R1": düğme sonda, önünde kısa ve noktalamasız bir eylem adı.
        if (Buttons.Contains(tokens[^1]) && words <= 4 && !SubtitleStabilizer.EndsSentence(line)) return true;
        // "X Interact", "O Back": ardından kısa, büyük harfle başlayan, noktalamasız bir eylem gelir.
        if (Lookalikes.Contains(first) && tokens.Count is >= 2 and <= 4 && char.IsUpper(tokens[1][0]) &&
            !SubtitleStabilizer.EndsSentence(line))
            return true;
        // "Press ✕ to jump", "Hold R2 to aim"
        if (Verbs.Contains(first) && tokens.Count is >= 2 and <= 10)
            return Buttons.Contains(tokens[1]) || Lookalikes.Contains(tokens[1]);
        return false;
    }
}
