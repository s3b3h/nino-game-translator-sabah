// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.RegularExpressions;

namespace CouchSubs.Core;

/// <summary>
/// Nino: harita ekranında seçilen görevin bilgi kartı (GTA 6): büyük harfli başlık ("BUY FLOWERS"), altında bir iki
/// cümle. Menü çevrilmez ama bu kartın Türkçesi kartın hemen altına yazılır (Mac: MapCard.swift ile aynı kurallar).
/// </summary>
public static class MapCard
{
    /// <param name="Title">Başlık (yoksa boş).</param>
    /// <param name="Sentences">Cümleler, yukarıdan aşağı; her cümle ayrı çevrilir.</param>
    /// <param name="Box">Kartın yazılarını çevreleyen kutu (0–1, kareye göre).</param>
    public sealed record Found(string Title, IReadOnlyList<string> Sentences, TextBox Box, double LineHeight)
    {
        public bool Equals(Found? other) =>
            other is not null && Title == other.Title && Sentences.SequenceEqual(other.Sentences) && Box == other.Box && LineHeight == other.LineHeight;

        public override int GetHashCode() => HashCode.Combine(Title, Box, LineHeight);
    }

    private static readonly HashSet<string> MapKeys =
        ["recenter", "2d view", "3d view", "add marker", "remove marker", "set destination", "remove destination", "close menu"];

    /// <summary>Harita ekranı mı: sağ alttaki tuş listesi ("RECENTER", "2D VIEW", "ADD MARKER", "SET DESTINATION", "CLOSE MENU").</summary>
    public static bool IsMapScreen(Reading reading) =>
        reading.Lines.Select(l => CleanMenuText(l.Text).ToLowerInvariant()).Where(MapKeys.Contains).Distinct().Count() >= 2;

    /// <summary>Bu satır haritanın tuş listesinden mi ("RECENTER", "2D VIEW").</summary>
    public static bool IsMapKey(string text) => MapKeys.Contains(CleanMenuText(text).ToLowerInvariant());

    /// <summary>
    /// Menü satırının yazısı simgelerden arınmış hâliyle: baştaki ve sondaki harfsiz parçalar atılır (Mac: MenuBlock.clean).
    /// </summary>
    internal static string CleanMenuText(string text)
    {
        var words = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).ToList();
        while (words.Count > 0 && (!words[0].Any(char.IsLetter) || (words[0].Length <= 2 && !words[0].All(char.IsLetter))))
            words.RemoveAt(0);
        // Simge çoğu zaman küçük harf sanılır ("i Settings", "ii Map", "Il Game").
        while (words.Count >= 2 && words[0].Length <= 2
               && (!words[0].Any(char.IsUpper) || words[0] == "Il" || words[0] == "II")
               && char.IsUpper(words[1][0]))
            words.RemoveAt(0);
        while (words.Count > 0 && !words[^1].Any(char.IsLetterOrDigit)) words.RemoveAt(words.Count - 1);
        return string.Join(' ', words);
    }

    private static readonly Regex Distance = new(@"\s*\b\d+(?:[.,]\d+)?\s?(?:km|mi|ft|m)\b\s*", RegexOptions.CultureInvariant);
    private static readonly Regex LeadingIcons = new(@"^(?:[^A-Za-z\s]+\s+)+(?=[A-Z])", RegexOptions.CultureInvariant);
    private static readonly Regex IconCrumbs = new(@"^([iI•●◆△▲]|\S*\d\S*|ml)(\s+([iI•●◆△▲]|\S*\d\S*|ml))*\s+(?=[A-Z])", RegexOptions.CultureInvariant);
    private static readonly Regex TrailingSymbols = new(@"(\s+[^A-Za-z\s]{1,3})+$", RegexOptions.CultureInvariant);

    private static bool EndsSentence(string text) => text.Length > 0 && ".!?".Contains(text[^1]);

    /// <summary>
    /// Haritadaki kart: ekranın sol menüsü ve sağ alttaki tuş listesi dışında kalan, alt alta duran cümle satırları ve
    /// hemen üstlerindeki büyük harfli başlık.
    /// </summary>
    public static Found? Find(Reading reading)
    {
        var lines = new List<(string Text, TextBox Box)>();
        foreach (var line in reading.Lines)
        {
            if (line.Box is not { } read || read.Right <= 0.30) continue;
            var place = read;
            var text = line.Text.Trim(' ');
            // Haritadaki uzaklık etiketi ("1.53 km") kartın satırıyla birlikte okunabiliyor; atılır.
            if (Distance.IsMatch(text))
            {
                text = Distance.Replace(text, " ").Trim(' ');
                if (place.Left < 0.5) place = place with { Left = Math.Max(place.Left, 0.5) };
            }
            // Haritadaki simge harf/sayı okunup satırın başına eklenebiliyor ("(43) Cal challenged…").
            if (LeadingIcons.Match(text) is { Success: true } lead)
            {
                var share = (double)lead.Length / Math.Max(1, text.Length);
                place = place with { Left = place.Left + ((place.Right - place.Left) * share) };
                text = text.Remove(0, lead.Length);
            }
            if (place.Left <= 0.30 || text.Count(char.IsLetter) < 3) continue;
            lines.Add((text, place));
        }
        lines = [.. lines.OrderBy(l => l.Box.Top)];
        // Cümle satırı: küçük harfli, en az üç sözcük (yer adları ve uzaklıklar değil).
        static bool IsSentence(string text) => text.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length >= 3 && text.Count(char.IsLower) >= 6;
        var body = lines.Where(l => IsSentence(l.Text)).ToList();
        if (body.Count == 0) return null;
        var first = body[0];
        // İlk cümleyle aynı kartta olanlar: alt alta ve yatayda üst üste. Cümlenin kısa son satırı ve paragraf boşluğundan
        // sonraki ikinci paragraf da karttadır.
        var card = new List<(string Text, TextBox Box)> { first };
        foreach (var line in lines.Where(l => l.Box.Top > first.Box.Top))
        {
            var last = card[^1];
            double height = last.Box.Bottom - last.Box.Top, gap = line.Box.Top - last.Box.Bottom;
            var overlaps = line.Box.Left < last.Box.Right && last.Box.Left < line.Box.Right;
            if (IsSentence(line.Text) && gap < height * 2.6 && overlaps && Math.Abs(line.Box.Left - first.Box.Left) < 0.06)
                card.Add(line);
            else if (gap < height * 1.2 && Math.Abs(line.Box.Left - last.Box.Left) < 0.03 && line.Text.Any(char.IsLower) && !EndsSentence(last.Text))
                card.Add(line);
        }
        // Cümleler: sol kenarı aynı olan art arda satırlar tek cümledir; erken biten satırdan sonra büyük harfle başlayan
        // satır yeni cümledir. Küçük harfle başlayan satır her zaman önceki cümlenin devamıdır.
        var reach = card.Max(l => l.Box.Right);
        var sentences = new List<List<(string Text, TextBox Box)>>();
        foreach (var line in card)
        {
            var continues = line.Text.Length > 0 && char.IsLower(line.Text[0]) && !(sentences.Count == 0 || EndsSentence(sentences[^1][^1].Text));
            if (sentences.Count > 0)
            {
                var head = sentences[^1][0];
                var last = sentences[^1][^1];
                if (continues || (Math.Abs(line.Box.Left - head.Box.Left) < 0.03
                                  && line.Box.Top - last.Box.Bottom < (last.Box.Bottom - last.Box.Top) * 1.0
                                  && !(last.Box.Right < reach - 0.04 && line.Text.Length > 0 && char.IsUpper(line.Text[0]))))
                {
                    sentences[^1].Add(line);
                    continue;
                }
            }
            sentences.Add([line]);
        }
        var top = first.Box;
        (string Text, TextBox Box)? title = null;
        foreach (var line in lines)
            if (line.Box.Bottom <= top.Top + 0.01 && top.Top - line.Box.Bottom < 0.06
                && line.Box.Left < top.Right && top.Left < line.Box.Right + 0.05
                && line.Text == line.Text.ToUpperInvariant() && line.Text.Count(char.IsLetter) >= 3)
                title = line;
        var box = card.Skip(1).Aggregate(first.Box, (a, b) => a.Union(b.Box));
        if (title is { } heading) box = box.Union(heading.Box);
        // Kartın altındaki hedef satırı ("GOAL  $100 / $5,000") cümle değildir ama karttadır.
        foreach (var line in lines.Where(l => l.Box.Top >= box.Bottom - 0.005))
        {
            if (line.Box.Top - box.Bottom >= 0.05 || line.Box.Left <= box.Left - 0.03 || line.Box.Right >= box.Right + 0.08) continue;
            box = box.Union(line.Box);
        }
        var heights = card.Select(l => l.Box.Bottom - l.Box.Top).OrderBy(v => v).ToList();
        // Simge kırıntıları ("4 ml", "△", "00") baştan atılır; satır sonunda tireyle bölünen kelime birleşik kalır.
        var texts = sentences.Select(s => IconCrumbs.Replace(string.Join(' ', s.Select(l => l.Text)).Replace("- ", "-"), "")).ToList();
        var name = TrailingSymbols.Replace(title?.Text ?? "", "");
        return new Found(name, texts, box, heights[heights.Count / 2]);
    }

    /// <summary>
    /// Nino (kullanıcı: "karenin köşelerini sınır almalı, metni değil"): kartın koyu çerçevesi, haritanın aydınlık
    /// zemininden ayrılarak görüntüden bulunur. Yazıların kutusundan dışa doğru koyu kısım bitene kadar gidilir.
    /// </summary>
    public static TextBox? Frame(TextBox box, Frame image)
    {
        var color = PhonePanel.Sampler(image, 640, 360);
        bool Dark(double x, double y) => color(x, y) is { } c && c.Luminance / 1000 < 130;
        var rows = new List<double>();
        for (var y = box.Top + 0.01; y < box.Bottom; y += 0.02) rows.Add(y);
        var columns = new List<double>();
        for (var x = box.Left + 0.01; x < box.Right; x += 0.03) columns.Add(x);
        if (rows.Count == 0 || columns.Count == 0) return null;
        // Bir yönde koyu satır/sütunların çoğu bitene kadar ilerlenir.
        static double Edge(double start, double step, double limit, Func<double, int> darkAt, int total)
        {
            var position = start;
            while (Math.Abs(position - start) < limit && darkAt(position + step) * 2 >= total) position += step;
            return position;
        }
        // Kenar sınıra kadar bulunamadıysa (gece haritası da koyu) o yanda yazıların kutusu biraz paylı kullanılır.
        static double Bounded(double found, double start, double limit, double fallback) =>
            Math.Abs(found - start) >= limit - 0.004 ? fallback : found;
        int DarkRows(double x) => rows.Count(y => Dark(x, y));
        int DarkColumns(double y) => columns.Count(x => Dark(x, y));
        var left = Bounded(Edge(box.Left, -0.003, 0.04, DarkRows, rows.Count), box.Left, 0.04, box.Left - 0.015);
        var right = Bounded(Edge(box.Right, 0.003, 0.09, DarkRows, rows.Count), box.Right, 0.09, box.Right + 0.02);
        var bottom = Bounded(Edge(box.Bottom, 0.004, 0.08, DarkColumns, columns.Count), box.Bottom, 0.08, box.Bottom + 0.02);
        var top = Bounded(Edge(box.Top, -0.004, 0.06, DarkColumns, columns.Count), box.Top, 0.06, box.Top - 0.02);
        // Kart en az yazıların kutusu kadardır.
        if (right - left <= box.Right - box.Left) return null;
        return new TextBox(left, top, right, bottom);
    }
}
