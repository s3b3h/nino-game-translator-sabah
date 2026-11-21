// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.RegularExpressions;

namespace CouchSubs.Core;

/// <summary>
/// Nino: telefondaki sohbet ekranının mesajları ve Türkçelerinin telefonun yanındaki yeri (Mac: PhonePanel.swift
/// içindeki PhoneThread ile aynı kurallar).
/// </summary>
public static class PhoneThread
{
    public sealed record Message(string Text, TextBox Box, double LineHeight);

    /// <summary>Telefon ekranının en üstündeki başlık şeridi (ekran yüksekliğine oranla).</summary>
    internal const double HeaderShare = 0.07;
    /// <summary>Başlık şeridinin hemen altında bu kadar (kare yüksekliğine oranla) içinde başlayan satır kesiktir.</summary>
    internal const double ClippedTop = 0.012;
    /// <summary>Yazının kenarından balonun içine doğru: rengin okunduğu yer.</summary>
    internal const double BubbleInset = 0.0045;
    /// <summary>Örtünün yazıdan taşması.</summary>
    internal const double CoverPadX = 0.0035;
    public const double CoverPadY = 0.004;
    /// <summary>Panelin genişliği (kare genişliğine oranla), balonların ve zeminin saydamlığı.</summary>
    public const double SideWidth = 0.27;
    public const double SideAlpha = 0.95;
    public const double BackdropAlpha = 0.6;
    /// <summary>Panelin altında logoya bırakılan yer (kare yüksekliğine oranla).</summary>
    internal const double BadgeSpace = 0.03;

    private static string Trim(string text) => text.Trim(' ');

    private static string[] Words(string text) => text.Split(' ', StringSplitOptions.RemoveEmptyEntries);

    /// <summary>
    /// Telefon ekranındaki okuma (kareye göre yerleşmiş) bir sohbet mi: en üstte, ekranın ortasında kişinin adı durur.
    /// Mesaj listesinde en üstteki yazı sola yaslıdır; liste çevrilmez.
    /// </summary>
    public static bool IsThread(Reading reading, PhonePanel.Panel panel) => Title(reading, panel) is not null;

    /// <summary>Sohbetin başlığındaki ad ("Lucia", "Fleeca, Laguna Lane"): panelin en üstünde ortada gösterilir.</summary>
    public static string? TitleText(Reading reading, PhonePanel.Panel panel)
    {
        if (Title(reading, panel) is not { } box) return null;
        return reading.Lines.FirstOrDefault(line => line.Box == box) is { } line ? Trim(line.Text) : null;
    }

    /// <summary>Sohbetin başlığı (kişinin adı) olan satırın kutusu: başlık şeridinde ya da ekrandaki en üst satırdır.</summary>
    internal static TextBox? Title(Reading reading, PhonePanel.Panel panel)
    {
        var height = panel.Box.Bottom - panel.Box.Top;
        var boxes = reading.Lines.Where(l => l.Box is not null).Select(l => l.Box!.Value).ToList();
        var topmost = boxes.Count > 0 ? boxes.Min(b => b.Top) : 0;
        foreach (var line in reading.Lines)
        {
            if (line.Box is not { } box || !(box.Top < panel.Box.Top + (height * HeaderShare) || box.Top <= topmost + 0.002)) continue;
            var text = Trim(line.Text);
            var middle = (box.Top + box.Bottom) / 2;
            // Başlık kişi ya da yer adıdır; yer adında virgül, nokta, kesme ve & olabilir ("Fleeca, Laguna Lane").
            var nameLike = text.Length >= 2 && Words(text).Length <= 5
                           && text.All(c => char.IsLetter(c) || " ,.'’&-".Contains(c)) && text.Any(char.IsLetter);
            // Gezinme düğmesi ("Back", "< Back") kişi adı değildir.
            var bare = text.ToLowerInvariant().Trim('<', '‹', ' ');
            if (bare is "back" or "geri" or "done" or "close" or "cancel" or "edit") continue;
            if (!(MessageCards.IsName(text) || nameLike) || Math.Abs(((box.Left + box.Right) / 2) - panel.Center(middle)) >= panel.Width * 0.12) continue;
            // Listede adın hemen altında, aynı hizada önizleme satırı durur; sohbet başlığının altında aynı hizada satır yoktur.
            var indent = box.Left - panel.Left(box.Top);
            if (boxes.Any(other => other.Top > box.Top + 0.008 && other.Top < box.Top + 0.05
                                   && Math.Abs(other.Left - panel.Left(other.Top) - indent) < 0.015)) continue;
            return box;
        }
        return null;
    }

    /// <summary>
    /// Sohbet ekranındaki mesajlar, yukarıdan aşağı. Başlık (kişinin adı), "New message", yer/eşya etiketleri ve harfsiz
    /// satırlar mesaj değildir.
    /// </summary>
    public static IReadOnlyList<Message> Messages(Reading reading, PhonePanel.Panel found)
    {
        var panel = found.Box;
        var panelHeight = panel.Bottom - panel.Top;
        var header = Math.Max(panel.Top + (panelHeight * HeaderShare), Title(reading, found)?.Bottom ?? 0);
        // Satırın ortasındaki emoji satırı ikiye bölüyor; aynı satırdaki parçalar önce birleşir.
        var lines = JoiningPieces(reading).Lines
            .Where(line => line.Box is not null)
            .Select(line => (Text: Trim(line.Text), Box: line.Box!.Value))
            .Where(line => line.Text.Count(char.IsLetter) >= 2
                           // En üstteki başlık şeridi ve başlığın hemen altında yarısı kesik satır.
                           && line.Box.Top > header + ClippedTop
                           // Ekranın alt kenarında yarısı görünen satır okunamaz.
                           && line.Box.Bottom < panel.Bottom - 0.01)
            .OrderBy(line => line.Box.Top)
            .ToList();
        // Satır aralığı: art arda iki satırın üst kenarları arasındaki en küçük fark.
        var steps = lines.Zip(lines.Skip(1), (a, b) => b.Box.Top - a.Box.Top).Where(s => s >= 0.012 && s <= 0.04).ToList();
        var pitch = steps.Count > 0 ? steps.Min() : (lines.Count > 0 ? lines.Min(l => l.Box.Bottom - l.Box.Top) : 0.025) * 1.2;
        var groups = new List<List<(string Text, TextBox Box)>>();
        foreach (var line in lines)
        {
            // Eğik telefonda paragrafın satırları aşağı indikçe yana kayar: sol kenar ekranın kenarına göre ölçülür.
            var indent = line.Box.Left - found.Left(line.Box.Top);
            if (groups.Count > 0)
            {
                var last = groups[^1][^1];
                var head = groups[^1][0];
                if (line.Box.Top - last.Box.Top < pitch * 1.6
                    && Math.Abs(indent - (head.Box.Left - found.Left(head.Box.Top))) < 0.02)
                {
                    groups[^1].Add(line);
                    continue;
                }
            }
            groups.Add([line]);
        }
        var result = new List<Message>();
        foreach (var group in groups)
        {
            var text = string.Join(' ', group.Select(l => l.Text));
            if (IsLabel(text)) continue;
            var box = group.Skip(1).Aggregate(group[0].Box, (a, b) => a.Union(b.Box));
            result.Add(new Message(text, box, pitch * 0.85));
        }
        return result;
    }

    /// <summary>Aynı satırda, aralarında küçük boşlukla (emoji) yan yana okunan parçalar tek satır olur.</summary>
    internal static Reading JoiningPieces(Reading reading)
    {
        var rows = new List<TextLine>();
        foreach (var line in reading.Lines.OrderBy(l => l.Box?.Left ?? 0))
        {
            if (line.Box is not { } box) { rows.Add(line); continue; }
            var index = rows.FindIndex(row =>
            {
                if (row.Box is not { } other) return false;
                var overlap = Math.Min(box.Bottom, other.Bottom) - Math.Max(box.Top, other.Top);
                var smaller = Math.Min(box.Bottom - box.Top, other.Bottom - other.Top);
                return smaller > 0 && overlap >= smaller * 0.75 && box.Left - other.Right <= 0.03 && box.Left > other.Right - 0.005;
            });
            if (index >= 0 && rows[index].Box is { } joined)
                rows[index] = new TextLine(rows[index].Text + " " + line.Text, joined.Union(box), rows[index].Confidence);
            else
                rows.Add(line);
        }
        return new Reading(rows);
    }

    private static readonly HashSet<string> LabelWords =
        ["new message", "new messages", "typing", "delivered", "read", "today", "yesterday", "messages encrypted"];

    /// <summary>
    /// Mesaj olmayan satır: "New message", "Typing...", ek olarak gönderilen yer ya da eşyanın adı (her sözcüğü büyük
    /// harfle başlar, cümle noktalaması yoktur).
    /// </summary>
    internal static bool IsLabel(string text)
    {
        var lowered = text.ToLowerInvariant().Trim('.', '…', '•', ' ');
        if (LabelWords.Contains(lowered)) return true;
        // Kilit simgesi harf sanılıyor ("A Messages encrypted").
        if (lowered.EndsWith("messages encrypted", StringComparison.Ordinal) || lowered.EndsWith("message encrypted", StringComparison.Ordinal)) return true;
        // Mesaja eklenen uygulama bağlantısının kartı ("BuckMe") mesaj değildir.
        if (PhoneAppNames.Contains(TextMatch.Normalize(text))) return true;
        var words = Words(text);
        if (words.Length < 2 || text.Any(c => ".,!?…".Contains(c))) return false;
        return words.All(word => char.IsUpper(word[0]) || word.ToLowerInvariant() is "del" or "de" or "la" or "of" or "the" or "&");
    }

    /// <summary>Türkçelerin duracağı sütun: telefonun boş kalan (geniş) yanında, en çok <paramref name="maxWidth"/> genişliğinde.</summary>
    public static (double Left, double Right) Column(PhonePanel.Panel found, double maxWidth = 0.30)
    {
        var panel = found.Box;
        const double gap = 0.035;
        if ((panel.Left + panel.Right) / 2 > 0.5)
        {
            var right = panel.Left - gap;
            return (Math.Max(0.02, right - maxWidth), right);
        }
        var left = panel.Right + gap;
        return (left, Math.Min(0.98, left + maxWidth));
    }

    /// <summary>Her çevirinin kutusu: mesajın hizasında, sütunun içinde; üst üste binmesinler diye gerekirse aşağı kayar.</summary>
    public static IReadOnlyList<TextBox> Boxes(IReadOnlyList<Message> messages, IReadOnlyList<int> lineCounts,
                                               IReadOnlyList<double> lineHeights, (double Left, double Right) column)
    {
        var result = new List<TextBox>();
        var floor = 0.0;
        for (var index = 0; index < messages.Count; index++)
        {
            var height = lineHeights[index] * Math.Max(1, lineCounts[index]) * 1.3;
            var top = Math.Min(Math.Max(messages[index].Box.Top, floor), Math.Max(0, 0.98 - height));
            result.Add(new TextBox(column.Left, top, column.Right, top + height));
            floor = top + height + (lineHeights[index] * 0.6);
        }
        return result;
    }

    /// <summary>
    /// Mesajların Türkçesi her mesaj balonunun tam üstünde, balonun kendi rengiyle; balonun rengi yazının hemen solundan
    /// (balonun iç payı) ve kutunun içinin aydınlık yarısından okunur.
    /// </summary>
    public static IReadOnlyList<ScreenTranslation.Item> Covers(IReadOnlyList<Message> messages, IReadOnlyList<string> translations,
                                                               Func<double, double, Rgb?> color, double angle = 0)
    {
        var result = new List<ScreenTranslation.Item>();
        for (var i = 0; i < Math.Min(messages.Count, translations.Count); i++)
        {
            var message = messages[i];
            var text = translations[i].Trim();
            // Ek kartının adı ("BuckMe" bağlantısı) "BuckMe mi?" diye soruya çevrilip mesaj gibi çıkıyordu.
            if (text.Length == 0 || !WorthShowing(message.Text, text)) continue;
            var box = message.Box;
            var points = new List<(double X, double Y)>();
            foreach (var share in new[] { 0.15, 0.35, 0.5, 0.65, 0.85 })
                foreach (var inset in new[] { BubbleInset, BubbleInset * 0.6 })
                    points.Add((box.Left - inset, box.Top + ((box.Bottom - box.Top) * share)));
            // Eğik telefonda yazının solu balonun dışına düşüyor; balonun içinden de okunur (aydınlık yarının ortancası).
            var inside = new List<Rgb>();
            for (var yi = 0; yi <= 7; yi++)
                for (var xi = 0; xi <= 8; xi++)
                {
                    double y = 0.15 + (yi * 0.1), x = 0.1 + (xi * 0.1);
                    if (color(box.Left + ((box.Right - box.Left) * x), box.Top + ((box.Bottom - box.Top) * y)) is { } c) inside.Add(c);
                }
            inside = [.. inside.OrderBy(c => c.Luminance)];
            var ground = inside.Count >= 10 ? inside.Skip(inside.Count - (inside.Count * 4 / 10)).ToList() : [];
            var edges = points.Select(p => color(p.X, p.Y)).Where(c => c is not null).Select(c => c!.Value).ToList();
            var edge = edges.Count > 0 ? edges.MaxBy(c => c.Luminance) : new Rgb(233, 233, 236);
            // İçerisi harf kadar koyuysa (kutu yazıyı sıkı sarıyor) yazının solundaki pay kullanılır.
            var fill = ground.Count == 0 || ground[ground.Count / 2].Luminance * 4 < edge.Luminance * 3 ? edge : ground[ground.Count / 2];
            var light = fill.Luminance / 1000 > 140;
            result.Add(new ScreenTranslation.Item(message.Text, text,
                new TextBox(box.Left - CoverPadX, box.Top - CoverPadY, box.Right + CoverPadX, box.Bottom + CoverPadY), message.LineHeight)
            {
                Fill = fill.Hex,
                Ink = light ? "#2c2c2e" : "#f5f5f7",
                Angle = angle,
            });
        }
        return result;
    }

    /// <summary>Telefon kaydıysa (el sallanıyor) örtüler de aynı kadar kaydırılır; yazı yeniden okunmaz.</summary>
    public static IReadOnlyList<ScreenTranslation.Item> Shifted(IReadOnlyList<ScreenTranslation.Item> items, double dx, double dy) =>
        [.. items.Select(item => item with { Box = new TextBox(item.Box.Left + dx, item.Box.Top + dy, item.Box.Right + dx, item.Box.Bottom + dy) })];

    /// <summary>
    /// Türkçenin <paramref name="width"/> genişlikte (kare genişliğine oranla) ve <paramref name="line"/> satır
    /// yüksekliğinde sözcük sözcük satırlara bölünmüşü (Mac: AppModel.wrap).
    /// </summary>
    public static IReadOnlyList<string> Wrap(string text, double width, double line)
    {
        var perLine = Math.Max(12, (int)(width / Math.Max(0.004, line * 0.5 * 9 / 16)));
        var lines = new List<string>();
        var current = "";
        foreach (var word in Words(text))
        {
            if (current.Length > 0 && current.Length + 1 + word.Length > perLine)
            {
                lines.Add(current);
                current = "";
            }
            current += current.Length == 0 ? word : " " + word;
        }
        if (current.Length > 0) lines.Add(current);
        return lines.Count == 0 ? [text] : lines;
    }

    /// <summary>
    /// Nino (kullanıcı isteği, 20 Kasım 2026): mesajların Türkçesi telefonun yanında, telefon boyunda dikey bir mesajlaşma
    /// paneli içinde: zemin telefondaki sohbetin zemini gibi ve biraz saydam; gelen mesajlar solda, giden mesajlar sağda,
    /// her biri kendi balonunun renginde ve mesajın hizasında. İlk öğe panelin zeminidir.
    /// <paramref name="lines"/>(metin, genişlik, satır) Türkçenin o genişlikte kaç satır tuttuğunu ve en uzun satırın harf
    /// sayısını verir.
    /// </summary>
    public static IReadOnlyList<ScreenTranslation.Item> SideBubbles(
        IReadOnlyList<Message> messages, IReadOnlyList<string> translations, PhonePanel.Panel panel,
        Func<double, double, Rgb?> color, Func<string, double, double, (int Count, int Longest)> lines,
        bool chat = true, string? title = null)
    {
        var covers = Covers(messages, translations, color);
        if (covers.Count == 0) return [];
        var kept = covers.Select(cover => messages.First(m => m.Text == cover.Source)).ToList();
        var column = Column(panel, SideWidth);
        const double inset = 0.012, gap = 0.012;
        var inner = (Left: column.Left + inset, Right: column.Right - inset);
        var bubbleMax = (inner.Right - inner.Left) * 0.82;
        const double pad = 0.012;
        var counts = new List<int>();
        var longest = new List<int>();
        var heights = new List<double>();
        for (var index = 0; index < covers.Count; index++)
        {
            // Kullanıcı isteği: Türkçe %4, sonra %6 daha büyütüldü (→ 0,97).
            var line = Math.Min(Math.Max(kept[index].LineHeight, 0.018), 0.028) * 0.97;
            var measured = lines(covers[index].Translation, bubbleMax - pad, line);
            counts.Add(measured.Count);
            longest.Add(measured.Longest);
            heights.Add(line);
        }
        var boxes = Boxes(kept, counts, heights, (inner.Left, inner.Right)).ToList();
        // Panel telefonun boyundadır; balonlar sığmazsa yukarı doğru sıkışır. Panelin sağ altında Nino logosu durur.
        var bottom = panel.Box.Bottom - gap - BadgeSpace;
        if (boxes.Count > 0 && boxes[^1].Bottom > bottom)
        {
            var shift = boxes[^1].Bottom - bottom;
            boxes = [.. boxes.Select(b => b with { Top = b.Top - shift, Bottom = b.Bottom - shift })];
        }
        // Giden mesaj: telefonda sağa yaslı ya da aynı sohbetin en gri balonundan belirgin mavi.
        var blueness = covers.Select(c => BlueShift(c.Fill)).ToList();
        var grayest = blueness.Min();
        var indents = kept.Select(m => m.Box.Left - panel.Left(m.Box.Top)).ToList();
        var rights = kept.Select(m => m.Box.Right - panel.Left(m.Box.Top)).ToList();
        double leftmost = indents.Min(), rightmost = rights.Max();
        var outgoing = Enumerable.Range(0, covers.Count).Select(i =>
        {
            var rightAligned = indents[i] - leftmost > panel.Width * 0.1 && rightmost - rights[i] < panel.Width * 0.08;
            return chat && (IsOutgoing(kept[i], panel) || rightAligned || blueness[i] - grayest >= 14);
        }).ToList();
        var items = new List<ScreenTranslation.Item>();
        // Zemin: sohbetin zemini balonların arasından (gelen balonların sağındaki boşluk) okunur.
        var samples = kept.Where(m => !IsOutgoing(m, panel)).Select(m =>
        {
            var y = (m.Box.Top + m.Box.Bottom) / 2;
            return color(panel.Left(y) + panel.Width - 0.012, y);
        }).Where(c => c is not null).Select(c => c!.Value).ToList();
        var sorted = samples.OrderBy(c => c.R + c.G + c.B).Skip(samples.Count / 2).ToList();
        var ground = sorted.Count > 0 ? sorted[0] : new Rgb(226, 228, 233);
        // Kullanıcı: balonlar zeminden ayrışsın; zemin beyaz ve şeffaf olsun (mesajlar uygulamasının açık zemini gibi).
        var lightChat = chat && ground.Luminance / 1000 > 150;
        var toWhite = lightChat ? 0.6 : 0.0;
        int Lift(int v) => (int)(v + ((255 - v) * toWhite));
        var backdrop = new ScreenTranslation.Item("", "", new TextBox(column.Left, panel.Box.Top, column.Right, panel.Box.Bottom), 0.02)
        {
            Fill = new Rgb(Lift(ground.R), Lift(ground.G), Lift(ground.B)).Hex,
            Alpha = BackdropAlpha,
            Backdrop = true,
        };
        // Kullanıcı isteği: panelin en üstünde ortada gönderenin adı (TV başlık olarak çizer; ad çevrilmez).
        if (chat && !string.IsNullOrEmpty(title))
            backdrop = backdrop with
            {
                Translation = title,
                LineHeight = Math.Min(Math.Max(kept.Max(m => m.LineHeight), 0.02), 0.028),
            };
        items.Add(backdrop);
        for (var index = 0; index < covers.Count; index++)
        {
            var box = boxes[index];
            var width = Math.Min(bubbleMax, (longest[index] * heights[index] * 0.5 * 9 / 16) + pad + 0.012);
            if (!chat)
            {
                // Uygulama ekranı: her satır telefondaki yatay yerine ve genişliğine göre (ölçeklenerek) durur.
                var message = kept[index];
                var scale = (inner.Right - inner.Left) / panel.Width;
                var left = message.Box.Left - panel.Left(message.Box.Top);
                var boxLeft = inner.Left + (Math.Max(0, left) * scale) - (pad / 2);
                box = box with { Left = boxLeft, Right = Math.Min(inner.Right, boxLeft + Math.Max(width, ((message.Box.Right - message.Box.Left) * scale) + pad)) };
            }
            else if (outgoing[index]) box = box with { Left = inner.Right - width, Right = inner.Right };
            else box = box with { Left = inner.Left, Right = inner.Left + width };
            box = box with { Bottom = box.Bottom + (heights[index] * 0.3) };
            var item = covers[index];
            if (lightChat && item.Fill is { Length: 7 } fill && int.TryParse(fill.AsSpan(1), System.Globalization.NumberStyles.HexNumber, null, out var value))
            {
                double r = (value >> 16) & 0xff, g = (value >> 8) & 0xff, b = value & 0xff;
                var tuned = outgoing[index]
                    ? (r * 0.86, g * 0.93, Math.Min(255, b * 1.04))
                    : (r + ((255 - r) * 0.7), g + ((255 - g) * 0.7), b + ((255 - b) * 0.7));
                item = item with { Fill = new Rgb((int)tuned.Item1, (int)tuned.Item2, (int)tuned.Item3).Hex };
            }
            items.Add(item with { Box = box, LineHeight = heights[index], Angle = null, Alpha = SideAlpha, Side = true });
        }
        return items;
    }

    /// <summary>Rengin maviliği: mavi kanalın kırmızı ve yeşilin ortalamasından farkı.</summary>
    internal static int BlueShift(string? hex)
    {
        if (hex is not { Length: 7 } || !int.TryParse(hex.AsSpan(1), System.Globalization.NumberStyles.HexNumber, null, out var value)) return 0;
        int r = (value >> 16) & 0xff, g = (value >> 8) & 0xff, b = value & 0xff;
        return b - ((r + g) / 2);
    }

    /// <summary>Giden mesaj: telefonda sağa yaslı balon (sol kenarı ekranın içinde epey içeride başlar).</summary>
    internal static bool IsOutgoing(Message message, PhonePanel.Panel panel) =>
        message.Box.Left - panel.Left(message.Box.Top) > panel.Width * 0.2;

    /// <summary>
    /// Nino: sohbet olmayan telefon uygulaması (BuckMe bankası): her yazı satırı ayrı çevrilir. Harfsiz satırlar, üstteki
    /// başlık şeridi ve alt kenarda yarısı görünen satır alınmaz; alt alta devam eden satırlar tek cümledir.
    /// </summary>
    public static IReadOnlyList<Message> AppLines(Reading reading, PhonePanel.Panel found)
    {
        var panel = found.Box;
        var panelHeight = panel.Bottom - panel.Top;
        var lines = new List<Message>();
        foreach (var line in reading.Lines)
        {
            if (line.Box is not { } box) continue;
            // Satırın başındaki simge ("◆ Checking Account") çevrilmez.
            var trimmed = Trim(line.Text);
            var start = 0;
            while (start < trimmed.Length && !char.IsLetter(trimmed[start]) && !char.IsDigit(trimmed[start]) && trimmed[start] is not ('$' or '€' or '£')) start++;
            var text = Trim(trimmed[start..]);
            // Boş sohbetin "Messages encrypted" yazısı uygulama yazısı değildir.
            var lowered = text.ToLowerInvariant();
            if (lowered.EndsWith("messages encrypted", StringComparison.Ordinal) || lowered.EndsWith("message encrypted", StringComparison.Ordinal)) continue;
            if (text.Count(char.IsLetter) < 3 || box.Top <= panel.Top + (panelHeight * HeaderShare) || box.Bottom >= panel.Bottom - 0.01) continue;
            lines.Add(new Message(text, box, (box.Bottom - box.Top) * 0.85));
        }
        lines = [.. lines.OrderBy(l => l.Box.Top)];
        var merged = new List<Message>();
        foreach (var line in lines)
        {
            if (merged.Count > 0)
            {
                var last = merged[^1];
                double gap = line.Box.Top - last.Box.Bottom, height = line.Box.Bottom - line.Box.Top;
                var words = Words(last.Text).Count(w => w.Any(char.IsLetter));
                var ended = last.Text.Length > 0 && ".!?:".Contains(last.Text[^1]);
                // Yazar satırı ("By Rusty Travers") paragrafa katılmaz.
                var byline = last.Text.ToLowerInvariant().StartsWith("by ", StringComparison.Ordinal) && words <= 4;
                var continues = !byline && ((line.Text.Length > 0 && char.IsLower(line.Text[0])) || (!ended && words >= 3));
                if (gap < height * 0.6 && Math.Abs(line.Box.Left - last.Box.Left) < 0.02 && continues)
                {
                    merged[^1] = last with { Text = last.Text + " " + line.Text, Box = last.Box.Union(line.Box) };
                    continue;
                }
            }
            merged.Add(line);
        }
        return merged;
    }

    /// <summary>
    /// Kutudaki yazı açık zeminde koyu yazı mı (telefon ekranı, mesaj balonu): zemin (ortanca parlaklık) yazının
    /// noktalarından aydınlıktır. Altyazı ise koyu sahnede (ya da siyah kutuda) beyaz yazıdır.
    /// </summary>
    public static bool IsDarkOnLight(TextBox box, Func<double, double, Rgb?> color)
    {
        var values = new List<int>();
        var step = Math.Max((box.Bottom - box.Top) / 6, 0.001);
        for (var y = box.Top; y <= box.Bottom + 1e-12; y += step)
            for (var si = 0; si <= 32; si++)
            {
                var share = 0.02 + (si * 0.03);
                if (color(box.Left + ((box.Right - box.Left) * share), y) is { } c) values.Add(c.Luminance / 1000);
            }
        if (values.Count < 20) return false;
        values.Sort();
        int darkest = values[values.Count / 20], middle = values[values.Count / 2], brightest = values[values.Count * 19 / 20];
        return middle - darkest >= 25 && middle - darkest > (brightest - middle) * 2;
    }

    /// <summary>
    /// Çevrilecek yazı mı: çevirisi boş değil, aslının aynısı değil ve tek sözcüklü aslını olduğu gibi içermiyor ("buckme"
    /// → "BuckMe mi?": marka adı çevrilmez).
    /// </summary>
    public static bool WorthShowing(string source, string translation)
    {
        string a = TextMatch.Normalize(source), b = TextMatch.Normalize(translation);
        return b.Length > 0 && a != b && !(b.Contains(a, StringComparison.Ordinal) && !a.Contains(' '));
    }

    /// <summary>
    /// Nino: oyun telefonunun arayüz yazıları (GTA 6 BuckMe bankası, mesajlar) için sabit Türkçe. Kısa arayüz yazısı
    /// bağlamsız çevrilince saçmalıyordu ("Checking Account" → "Borsa Hesabı").
    /// </summary>
    public static string? Glossary(string text)
    {
        var key = TextMatch.Normalize(text);
        if (GlossaryTerms.TryGetValue(key, out var fixedText)) return fixedText;
        // "Book Ryde ($82)" → "Ryde Çağır ($82)": parantez içindeki tutar korunur.
        var open = text.IndexOf('(');
        if (open >= 0 && text.EndsWith(')') && GlossaryTerms.TryGetValue(TextMatch.Normalize(text[..open]), out var withAmount))
            return withAmount + " " + text[open..];
        // "Muscle - High" → "Kas - Yüksek"
        var parts = text.Split(" - ");
        if (parts.Length == 2 && StatNames.TryGetValue(TextMatch.Normalize(parts[0]), out var leftName)
            && StatLevels.TryGetValue(TextMatch.Normalize(parts[1]), out var rightLevel))
            return leftName + " - " + rightLevel;
        // Tanıma tireyi düşürebiliyor ("Muscle High").
        var words = Words(key);
        if (words.Length >= 2 && StatLevels.TryGetValue(words[^1], out var level)
            && StatNames.TryGetValue(string.Join(' ', words[..^1]), out var name))
            return name + " - " + level;
        // "Level 3/4" → "Seviye 3/4"
        var raw = Words(text);
        if (key.StartsWith("level ", StringComparison.Ordinal) && raw.Length >= 2 && raw[1].Contains('/'))
            return "Seviye " + raw[1];
        // "$4,900 to next goal" → "Sonraki hedefe $4.900"
        if (key.EndsWith(" to next goal", StringComparison.Ordinal) && raw.Length > 0 && raw[0].Any(char.IsDigit))
            return "Sonraki hedefe " + raw[0].Replace(',', '.');
        return null;
    }

    /// <summary>Telefonun mesaj listesi mi: "…" ile kesilmiş önizlemeler var.</summary>
    public static bool IsMessageList(Reading reading) =>
        MessageCards.IsList(reading) && reading.Lines.Any(line =>
        {
            var text = Trim(line.Text);
            return text.EndsWith("...", StringComparison.Ordinal) || text.EndsWith('…');
        });

    /// <summary>
    /// Cümle mi (sohbet mesajı): cümle noktalaması ya da küçük harfle başlayan sözcüğü var. Her sözcüğü büyük harfle
    /// başlayan arayüz yazısı ("Book Ryde ($82)") cümle değildir.
    /// </summary>
    public static bool IsSentence(string text)
    {
        var words = Words(text).Where(w => w.Any(char.IsLetter)).ToList();
        var trimmed = Trim(text);
        if (words.Count >= 2 && trimmed.Length > 0 && ".!?".Contains(trimmed[^1])) return true;
        if (text.Any(c => c is '!' or '?') && words.Count >= 2) return true;
        return words.Count >= 3 && words.Skip(1).Any(w => char.IsLower(w[0]));
    }

    private static readonly Regex Parenthesis = new(@"\(.*\)", RegexOptions.CultureInvariant);

    /// <summary>
    /// Nino: oyun telefonunun uygulamalarına özgü sözcükler. Bu yazılar her zaman telefondadır: telefon o karede
    /// bulunamasa da altyazı sayılmaz.
    /// </summary>
    public static bool IsPhoneUI(string text)
    {
        // Kök olarak aranır: yazı tanıma bir harfi yanlış okusa da ("Destinatior") tanınsın.
        var key = " " + TextMatch.Normalize(text);
        if (PhoneUIWords.Any(word => key.Contains(" " + word, StringComparison.Ordinal))) return true;
        // Uygulama adları tam sözcük olarak ("Ryde", "Rydeme"; "Rydell" değil).
        if (Words(key).Any(PhoneAppNames.Contains)) return true;
        var bare = TextMatch.Normalize(Parenthesis.Replace(text, ""));
        if (GlossaryTerms.ContainsKey(bare)) return true;
        // Sözlüğün kalıplarıyla çevrilen yazı da telefondadır; tek sözcükler diyalogda da geçebilir, sayılmaz.
        return Words(text).Length >= 2 && Glossary(text) is not null;
    }

    /// <summary>Uygulama adları ve uygulamaya özgü sözcükler (tek başına geçince yeter).</summary>
    internal static readonly string[] PhoneUIWords =
    [
        "trip detail", "change destinat", "destinatio", "messages encrypt", "map pin expir", "checking accoun", "family saving",
        // Fitness uygulaması (tek sözcük değil kalıp: diyalogdaki "workout" altyazı olarak kalsın)
        "workout window", "strength workout", "cardio workout", "calorie balanc", "maintain weight", "gain weight", "lose weight",
    ];

    internal static readonly HashSet<string> PhoneAppNames = ["ryde", "rydeme", "buckme"];

    internal static readonly Dictionary<string, string> StatNames = new()
    {
        ["muscle"] = "Kas", ["body fat"] = "Vücut Yağı", ["stamina"] = "Dayanıklılık", ["strength"] = "Güç", ["fat"] = "Yağ",
    };

    internal static readonly Dictionary<string, string> StatLevels = new()
    {
        ["high"] = "Yüksek", ["low"] = "Düşük", ["medium"] = "Orta", ["average"] = "Ortalama", ["very high"] = "Çok Yüksek",
        ["very low"] = "Çok Düşük",
    };

    internal static readonly Dictionary<string, string> GlossaryTerms = new()
    {
        // Gazete adları çevrilmez (aynısı döner, baloncuk gösterilmez).
        ["vice city horn"] = "Vice City Horn", ["the leonida journal"] = "The Leonida Journal", ["leonida journal"] = "Leonida Journal",
        ["ripped"] = "Kaslı", ["toned"] = "Sıkı", ["average"] = "Ortalama", ["body & nutrition"] = "Vücut ve Beslenme",
        ["body nutrition"] = "Vücut ve Beslenme",
        ["strength workout"] = "Güç Antrenmanı", ["cardio workout"] = "Kardiyo Antrenmanı", ["workout window"] = "Antrenman zamanı",
        ["focus"] = "Odak", ["fitness"] = "Fitness", ["calorie balance"] = "Kalori Dengesi", ["you will maintain weight"] = "Kilonu koruyacaksın",
        ["you will gain weight"] = "Kilo alacaksın", ["you will lose weight"] = "Kilo vereceksin", ["hungry"] = "Aç", ["full"] = "Tok",
        ["trip details"] = "Yolculuk Bilgileri", ["cost"] = "Ücret", ["choose ryde"] = "Ryde Seç", ["standard ryde"] = "Standart Ryde",
        ["change destination"] = "Varış Noktasını Değiştir", ["book ryde"] = "Ryde Çağır", ["cancel ryde"] = "Ryde'ı İptal Et",
        ["checking account"] = "Vadesiz Hesap", ["savings account"] = "Birikim Hesabı", ["family savings"] = "Aile Birikimi",
        ["family savings video"] = "Aile Birikimi Videosu", ["atm finder"] = "ATM Bulucu", ["faqs"] = "SSS",
        ["savings"] = "Birikim", ["balance"] = "Bakiye", ["deposit"] = "Para Yatır", ["withdraw"] = "Para Çek", ["transfer"] = "Transfer",
        ["transactions"] = "Hesap Hareketleri", ["recent transactions"] = "Son Hareketler", ["set a goal"] = "Hedef Belirle",
        ["messages encrypted"] = "Mesajlar şifreli", ["new message"] = "Yeni mesaj", ["all contacts"] = "Tüm Kişiler",
        ["suggested"] = "Önerilenler", ["messages"] = "Mesajlar", ["map pin expired"] = "Konum süresi doldu",
    };

    /// <summary>
    /// Nino (kullanıcı isteği, 20 Kasım 2026): sohbet olmayan uygulamada Türkçe, telefonun yanındaki boşlukta uygulamanın
    /// kendi renginde (ekrandaki en canlı renk; BuckMe'de mor) baloncuklar olarak, her yazının hizasında ve telefona yakın
    /// kenara yaslı durur. Zemin paneli yoktur.
    /// </summary>
    public static IReadOnlyList<ScreenTranslation.Item> AppBubbles(IReadOnlyList<Message> lines, IReadOnlyList<string> translations,
                                                                   PhonePanel.Panel panel, Func<double, double, Rgb?> color)
    {
        var kept = lines.Zip(translations).Where(p => WorthShowing(p.First.Text, p.Second)).ToList();
        if (kept.Count == 0) return [];
        var accent = new Rgb(58, 58, 60);
        Rgb? Strongest(IEnumerable<(double X, double Y)> points)
        {
            var best = 60;
            Rgb? found = null;
            foreach (var (x, y) in points)
            {
                if (color(x, y) is not { } c) continue;
                var saturation = c.Max - c.Min;
                // Yeterince aydınlık olmalı (koyu ekrandaki koyu lacivert uygulamanın rengi değildir).
                if (saturation > best && c.Max >= 120) { best = saturation; found = c; }
            }
            return found;
        }
        var header = new List<(double, double)>();
        for (var yi = 0; ; yi++)
        {
            var y = panel.Box.Top - 0.04 + (yi * 0.01);
            if (y >= panel.Box.Top + 0.06 - 1e-12) break;
            for (var si = 1; si <= 9; si++) header.Add((panel.Left(y) + (panel.Width * si * 0.1), y));
        }
        var around = kept.SelectMany(p =>
        {
            var b = p.First.Box;
            var middle = (b.Top + b.Bottom) / 2;
            return new[] { (b.Left - 0.006, middle), (b.Right + 0.006, middle), ((b.Left + b.Right) / 2, b.Top - 0.006), ((b.Left + b.Right) / 2, b.Bottom + 0.006) };
        }).ToList();
        // Nino (kullanıcı fikri): uygulamanın belirgin rengi yoksa baloncuk ekranın baskın arka planı ve yazı rengiyle çizilir.
        var ink = "#ffffff";
        if ((Strongest(header) ?? Strongest(around)) is { } strong)
        {
            accent = strong;
        }
        else
        {
            var bins = new Dictionary<int, List<Rgb>>();
            for (var y = panel.Box.Top + 0.02; y < panel.Box.Bottom - 0.01; y += 0.01)
                for (var si = 1; si <= 19; si++)
                {
                    if (color(panel.Left(y) + (panel.Width * si * 0.05), y) is not { } c) continue;
                    var key = ((c.R / 16) << 8) | ((c.G / 16) << 4) | (c.B / 16);
                    if (!bins.TryGetValue(key, out var list)) bins[key] = list = [];
                    list.Add(c);
                }
            if (bins.Count > 0)
            {
                var crowd = bins.OrderByDescending(p => p.Value.Count).ThenBy(p => p.Key).First().Value;
                var back = new Rgb(crowd.Sum(c => c.R) / crowd.Count, crowd.Sum(c => c.G) / crowd.Count, crowd.Sum(c => c.B) / crowd.Count);
                int Distance(Rgb c) => Math.Abs(c.R - back.R) + Math.Abs(c.G - back.G) + Math.Abs(c.B - back.B);
                var strokes = new List<Rgb>();
                foreach (var (line, _) in kept)
                {
                    var b = line.Box;
                    var step = Math.Max((b.Bottom - b.Top) / 8, 0.002);
                    for (var y = b.Top; y <= b.Bottom + 1e-12; y += step)
                        for (var si = 1; si <= 49; si++)
                            if (color(b.Left + ((b.Right - b.Left) * si * 0.02), y) is { } c) strokes.Add(c);
                }
                accent = back;
                var lightBack = back.Luminance > 128_000;
                if (strokes.Count > 0 && strokes.MaxBy(Distance) is var text && Distance(text) >= 90)
                {
                    ink = lightBack
                        ? new Rgb((int)(text.R * 0.6), (int)(text.G * 0.6), (int)(text.B * 0.6)).Hex
                        : new Rgb(255 - ((255 - text.R) / 2), 255 - ((255 - text.G) / 2), 255 - ((255 - text.B) / 2)).Hex;
                }
                else
                {
                    ink = lightBack ? "#1c1c1e" : "#ffffff";
                }
            }
        }
        var column = Column(panel, SideWidth);
        var onLeft = column.Right <= panel.Box.Left;
        var floor = 0.0;
        // Bütün baloncuklarda aynı yazı boyu (ortanca satır yüksekliği).
        var heights = kept.Select(p => p.First.LineHeight / 0.85).OrderBy(v => v).ToList();
        var size = Math.Min(Math.Max(heights[heights.Count / 2], 0.018), 0.028) * 0.95;
        var items = new List<ScreenTranslation.Item>();
        foreach (var (line, turkish) in kept)
        {
            var text = turkish.Trim();
            // Uzun yazı (haber paragrafı) sütun genişliğinde alt satırlara kaydırılır.
            double charWidth = size * 0.5 * 9 / 16, room = column.Right - column.Left;
            var perLine = Math.Max(8, (int)((room - 0.03) / (charWidth * 0.85)));
            var rows = Math.Max(1, (int)Math.Ceiling((double)text.Length / perLine));
            var width = rows > 1 ? room : Math.Min(room, (text.Length * charWidth) + 0.03);
            var height = rows > 1 ? size * ((1.22 * rows) + 0.45) : size * 1.55;
            var top = Math.Min(Math.Max(rows > 1 ? line.Box.Top : ((line.Box.Top + line.Box.Bottom) / 2) - (height / 2), floor), Math.Max(0, 0.98 - height));
            floor = top + height + (size * 0.4);
            var left = onLeft ? column.Right - width : column.Left;
            items.Add(new ScreenTranslation.Item(line.Text, text, new TextBox(left, top, left + width, top + height), size)
            {
                Fill = accent.Hex,
                Ink = ink,
                Alpha = SideAlpha,
                Side = true,
            });
        }
        return items;
    }
}

/// <summary>Nino: telefona gelen mesaj kartının ve mesaj listesinin tanınması (Mac: MessageCard.swift'in gereken kısmı).</summary>
public static class MessageCards
{
    /// <summary>Telefonun mesaj listesi: en az üç satır; iki ad ya da iki "…" ile kesilmiş önizleme.</summary>
    public static bool IsList(Reading reading)
    {
        var lines = reading.Lines.Select(l => l.Text.Trim(' ')).ToList();
        var names = lines.Count(IsName);
        var truncated = lines.Count(t => t.EndsWith("...", StringComparison.Ordinal) || t.EndsWith('…'));
        return lines.Count >= 3 && (names >= 2 || truncated >= 2);
    }

    /// <summary>Kişi adı gibi: 1-4 sözcük, her biri büyük harfle başlar, noktalamasız.</summary>
    public static bool IsName(string text)
    {
        var words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return text.Length is >= 2 and <= 30 && words.Length is >= 1 and <= 4
               && words.All(w => char.IsUpper(w[0]) || w[0] == '&')
               && words.All(w => w.Skip(1).Count(char.IsUpper) <= 1)
               && text.Any(char.IsLower) && !text.Any(c => ".,!?:;…\"".Contains(c));
    }
}
