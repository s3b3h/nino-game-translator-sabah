// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>Bir noktanın rengi (0–255).</summary>
public readonly record struct Rgb(int R, int G, int B)
{
    /// <summary>Parlaklık ×1000 (r·299 + g·587 + b·114).</summary>
    public int Luminance => (R * 299) + (G * 587) + (B * 114);
    public int Max => Math.Max(R, Math.Max(G, B));
    public int Min => Math.Min(R, Math.Min(G, B));
    public string Hex => $"#{Math.Clamp(R, 0, 255):x2}{Math.Clamp(G, 0, 255):x2}{Math.Clamp(B, 0, 255):x2}";
}

/// <summary>
/// Nino: oyundaki telefonun ekranı (GTA 6: dikey, beyaz, büyük dikdörtgen). Telefon açıkken içindeki yazılar altyazı
/// değildir: siyah altyazı kutusunda değil, telefonun yanında yarı saydam yazıyla gösterilir (Mac: PhonePanel.swift ile
/// aynı kurallar ve eşikler).
/// </summary>
public static class PhonePanel
{
    /// <summary>Bulunan ekran. Yaya hâlde telefon eğik tutulur: ekran bir paralelkenardır, aşağı indikçe sola ya da sağa kayar.</summary>
    /// <param name="Box">Ekranı çevreleyen dikdörtgen (0–1, kareye göre).</param>
    /// <param name="TopLeft">Üst kenarda ekranın sol kenarı (x).</param>
    /// <param name="Lean">Eğim: bir kare yüksekliği aşağı inince sol kenarın x olarak kayması (dik telefonda 0).</param>
    /// <param name="Width">Ekranın genişliği (her satırda aynı).</param>
    public readonly record struct Panel(TextBox Box, double TopLeft, double Lean, double Width)
    {
        /// <summary>Telefonun dönme açısı (derece, saat yönü artı; kare 16:9).</summary>
        public double Angle => Math.Atan(-Lean * 16 / 9) * 180 / Math.PI;

        /// <summary><paramref name="y"/> yüksekliğinde ekranın sol kenarı.</summary>
        public double Left(double y) => TopLeft + (Lean * (y - Box.Top));

        public double Center(double y) => Left(y) + (Width / 2);
    }

    /// <summary>Koyu ekranın satırlarının en az bu kadarında beyaz yazı noktası olmalı.</summary>
    internal const double DarkTextShare = 0.15;
    /// <summary>Küçültülmüş karede koyu ekrandaki yazının noktası (bulanıklaşmış beyaz): en parlak kanalı en az bu kadar.</summary>
    internal const int DarkTextFloor = 110;
    /// <summary>Koyu temalı ekran: en parlak kanal bundan koyu.</summary>
    internal const int DarkScreenCeiling = 75;
    /// <summary>Koyu ekranın çevresindeki gövde ekrandan belirgin açıktır: en parlak kanalı en az bu kadar.</summary>
    internal const int BezelFloor = 85;
    /// <summary>Telefon ekranında uyan iki satır arasındaki en uzun boşluk (küçültülmüş karede satır).</summary>
    internal const int MaxRowGap = 10;
    /// <summary>Bir renk kanalı en az bu kadar parlaksa (ve üçü birbirine yakınsa) nokta beyaz sayılır.</summary>
    internal const int WhiteFloor = 118;
    /// <summary>Telefonun siyah çerçevesi: ekranın hemen solu ve sağı bundan koyu olmalı.</summary>
    internal const int DarkCeiling = 90;
    /// <summary>Telefon ekranının genişliği (kare genişliğine oranla).</summary>
    internal const double MinWidth = 0.12, MaxWidth = 0.30;
    /// <summary>Telefon ekranının ortasının durabileceği yer (x).</summary>
    internal const double MinCenter = 0.30, MaxCenter = 0.80;
    /// <summary>Telefon ekranının yüksekliği (kare yüksekliğine oranla).</summary>
    internal const double MinHeight = 0.38, MaxHeight = 0.86;

    /// <summary>
    /// Karede telefonun beyaz ekranı; yoksa null. Kare küçültülür ve her satırda en uzun beyaz şerit aranır. Telefonun
    /// ekranı çok sayıda satırda aynı genişlikte, kenarları bir doğru üzerinde duran şerit verir; hemen iki yanında
    /// telefonun siyah çerçevesi vardır.
    /// </summary>
    public static Panel? Find(Frame frame)
    {
        const int width = 240, height = 135;
        var pixels = Downscaled(frame, width, height);
        if (pixels is null) return null;
        (int Low, int Spread) Low(int x, int y)
        {
            var i = ((y * width) + x) * 3;
            int r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
            var low = Math.Min(r, Math.Min(g, b));
            return (low, Math.Max(r, Math.Max(g, b)) - low);
        }
        if (Find(width, height,
                 (x, y) => { var p = Low(x, y); return p.Low >= WhiteFloor && p.Spread <= 45; },
                 (x, y) => Low(x, y).Low < DarkCeiling) is { } light)
            return light;
        // Nino: telefon elde bir süre dokunulmadan durunca ekranı kararıyor (gece sahnesinde beyaz ekran ≈70). Kare
        // karanlıksa ortasındaki en aydınlık kısım beyaza çekilip beyaz ekran yeniden aranır.
        var middle = new List<int>();
        for (var y = height / 10; y < height * 9 / 10; y += 2)
            for (var x = width * 15 / 100; x < width * 85 / 100; x += 2) middle.Add(Low(x, y).Low);
        middle.Sort();
        var bright = middle.Count == 0 ? 0 : middle[middle.Count * 95 / 100];
        if (bright >= 40 && bright < WhiteFloor)
        {
            var gain = 225.0 / bright;
            (int Low, int Spread) Lifted(int x, int y)
            {
                var p = Low(x, y);
                return ((int)(p.Low * gain), (int)(p.Spread * gain));
            }
            if (Find(width, height,
                     (x, y) => { var p = Lifted(x, y); return p.Low >= WhiteFloor && p.Spread <= 45; },
                     (x, y) => Lifted(x, y).Low < DarkCeiling) is { } dim)
                return dim;
        }
        // Nino: koyu temalı uygulama (GTA 6 Rydeme): ekran koyu, çevresindeki gövde açık. Aynı şekil sınamaları tersine
        // çevrilmiş renklerle.
        if (Find(width, height,
                 (x, y) => { var p = Low(x, y); return p.Low + p.Spread <= DarkScreenCeiling && p.Spread <= 40; },
                 (x, y) => { var p = Low(x, y); return p.Low + p.Spread >= BezelFloor; }) is not { } dark
            || dark.Box.Bottom > 0.96)
            return null;
        // Koyu kıyafet ya da gölge de koyu dikdörtgen verebiliyor: koyu ekranın satırlarının belirgin bir kısmında beyaz
        // yazı noktaları olmalı.
        int top = (int)(dark.Box.Top * height), bottom = (int)(dark.Box.Bottom * height);
        var texty = 0;
        for (var y = top; y < Math.Max(top + 1, bottom); y++)
        {
            var from = (int)(dark.Left((double)y / height) * width) + 2;
            var to = from + (int)(dark.Width * width) - 4;
            if (to <= from) continue;
            var lit = 0;
            for (var x = from; x <= to; x++)
            {
                var p = Low(Math.Min(width - 1, Math.Max(0, x)), y);
                if (p.Low + p.Spread >= DarkTextFloor) lit++;
            }
            if (lit >= 2 && lit <= (to - from + 1) * 0.6) texty++;
        }
        return texty >= Math.Max(1, bottom - top) * DarkTextShare ? dark : null;
    }

    /// <summary>Sınanan en çok aday (bkz. Find).</summary>
    internal const int MaxAttempts = 32;

    private static int Round(double value) => (int)Math.Round(value, MidpointRounding.AwayFromZero);

    /// <summary>Beyaz/koyu nokta haritasında telefonun ekranı (sınama için ayrı).</summary>
    internal static Panel? Find(int width, int height, Func<int, int, bool> isWhite, Func<int, int, bool> isDark)
    {
        // Her satırın telefon genişliğindeki beyaz şeritleri. Yazının ince çizgileri şeridi bölmez (≤3 nokta).
        var runs = new List<(int Start, int End)>[height];
        int minRun = (int)(width * MinWidth), maxRun = (int)(width * MaxWidth);
        for (var y = 0; y < height; y++)
        {
            runs[y] = [];
            var x = 0;
            while (x < width)
            {
                if (!isWhite(x, y)) { x++; continue; }
                int end = x, probe = x + 1;
                while (probe < width && probe - end <= 4)
                {
                    if (isWhite(probe, y)) end = probe;
                    probe++;
                }
                // Gümüş çerçevenin 1-2 noktalık parlak çizgisi ekranın şeridine eklenip sol kenarı kaydırıyordu; şeridin
                // başındaki ve sonundaki böyle kırıntılar atılır.
                int start = x, finish = end;
                int Crumb(int from, int step)
                {
                    int n = 0, p = from;
                    while (p >= start && p <= finish && isWhite(p, y)) { n++; p += step; }
                    return n;
                }
                while (finish - start > 6)
                {
                    var head = Crumb(start, 1);
                    if (!(head <= 2 && !isWhite(start + head, y) && !isWhite(start + head + 1, y))) break;
                    start += head;
                    while (start < finish && !isWhite(start, y)) start++;
                }
                while (finish - start > 6)
                {
                    var tail = Crumb(finish, -1);
                    if (!(tail <= 2 && !isWhite(finish - tail, y) && !isWhite(finish - tail - 1, y))) break;
                    finish -= tail;
                    while (finish > start && !isWhite(finish, y)) finish--;
                }
                var length = finish - start + 1;
                if (length >= minRun && length <= maxRun) runs[y].Add((start, finish));
                x = end + 1;
            }
        }
        // Sol kenar bir doğrudur: başlangıç = a + eğim·satır. Her eğimin en güçlü birkaç adayı; en çok oy alandan
        // başlanarak sınamaları geçen ilk aday telefondur.
        var candidates = new List<(int Votes, double Slope, int Key)>();
        var slopes = new List<double> { 0.0 };
        for (var i = 1; i <= 15; i++) { slopes.Add(i * 0.02); slopes.Add(i * -0.02); }
        foreach (var slope in slopes)
        {
            var votes = new Dictionary<int, int>();
            for (var y = 0; y < height; y++)
                foreach (var run in runs[y])
                {
                    var intercept = Round(run.Start - (slope * y));
                    var key = ((intercept + 400) / 2 * 1000) + ((run.End - run.Start) / 2);
                    votes[key] = votes.GetValueOrDefault(key) + 1;
                }
            foreach (var top in votes.OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key).Take(3))
                if (top.Value >= 8) candidates.Add((top.Value, slope, top.Key));
        }
        // Eşitlikte dik telefon (eğim 0, listede önce) öne geçer: sıralama kararlıdır.
        candidates = [.. candidates.Select((c, i) => (c, i)).OrderByDescending(p => p.c.Votes).ThenBy(p => p.i).Select(p => p.c)];

        Panel? Attempt((int Votes, double Slope, int Key) best)
        {
            double guess = (best.Key / 1000 * 2) - 400;
            var span = best.Key % 1000 * 2;
            double LeftEdge(int y, double intercept) => intercept + (best.Slope * y);
            var fit = new Dictionary<int, (int Start, int End)>();
            for (var y = 0; y < height; y++)
                foreach (var run in runs[y])
                    if (Math.Abs(run.Start - LeftEdge(y, guess)) <= 3.5 && Math.Abs(run.End - run.Start - span) <= 4)
                    {
                        fit[y] = run;
                        break;
                    }
            var rows = fit.Keys.OrderBy(y => y).ToList();
            // Telefonun üstündeki aydınlık pencere de aynı hizada ve genişlikte beyaz verebiliyor. Uyan satırlar uzun
            // boşluklarla parçalara ayrılır; başka parça varken karenin üst ya da alt kenarına değen parça atılır.
            var clusters = new List<List<int>>();
            foreach (var y in rows)
            {
                if (clusters.Count > 0 && y - clusters[^1][^1] <= MaxRowGap) clusters[^1].Add(y);
                else clusters.Add([y]);
            }
            var inner = clusters.Where(c => c[0] > 1 && c[^1] < height - 2).ToList();
            if (clusters.Count > 1 && inner.Count > 0) rows = [.. inner.SelectMany(c => c)];
            if (rows.Count < 8) return null;
            var intercepts = rows.Select(y => fit[y].Start - (best.Slope * y)).OrderBy(v => v).ToList();
            var intercept = intercepts[intercepts.Count / 2];
            var widths = rows.Select(y => fit[y].End - fit[y].Start).OrderBy(v => v).ToList();
            var runWidth = widths[widths.Count / 2];
            int Left(int y) => Round(LeftEdge(y, intercept));
            bool Near(int y, Func<int, int, bool> test, bool positive)
            {
                for (var d = 1; d <= 4; d++)
                {
                    var leftHit = test(Math.Max(0, Left(y) - d), y);
                    if (positive ? leftHit : !leftHit) return true;
                }
                return false;
            }
            bool NearRight(int y, Func<int, int, bool> test, bool positive)
            {
                for (var d = 1; d <= 4; d++)
                {
                    var hit = test(Math.Min(width - 1, Left(y) + runWidth + d), y);
                    if (positive ? hit : !hit) return true;
                }
                return false;
            }
            // Siyah çerçeve: bu satırların çoğunda ekranın hemen solu ve sağı koyu (kenarın 1-4 nokta yakınında).
            var framed = rows.Count(y => Near(y, isDark, true) && NearRight(y, isDark, true));
            // Gündüz telefonun bir yanı güneşli tahta olabiliyor: satırların çoğunda iki yanı beyaz olmayan ve en az üçte
            // birinde koyu çerçeveli beyaz şerit de telefondur.
            var edged = rows.Count(y => Near(y, isWhite, false) && NearRight(y, isWhite, false));
            if (!(framed >= rows.Count * 0.7 || (edged >= rows.Count * 0.85 && framed >= rows.Count * 0.35))) return null;
            // Üst ve alt kenar: şeridin yarıdan çoğu beyaz olduğu sürece ekrandır.
            bool Bright(int y)
            {
                int from = Math.Max(0, Left(y)), to = Math.Min(width - 1, Left(y) + runWidth);
                if (to <= from) return false;
                var white = 0;
                for (var x = from; x <= to; x++) if (isWhite(x, y)) white++;
                return white >= (to - from + 1) * 0.5;
            }
            int first = rows[0], last = rows[^1];
            while (first > 0 && Bright(first - 1)) first--;
            while (last < height - 1 && Bright(last + 1)) last++;
            rows = [.. rows.Where(y => y >= first && y <= last)];
            var tall = (double)(last - first + 1) / height;
            // Ekranın en az dörtte biri baştan sona beyaz olmalı.
            if (tall < MinHeight || tall > MaxHeight || rows.Count < (last - first + 1) * 0.25) return null;
            // Dikey dikdörtgen (nokta olarak yükseklik/genişlik; kare 16:9).
            var shape = tall * 9 / ((double)(runWidth + 1) / width * 16);
            if (shape < 1.2 || shape > 2.6) return null;
            double w = width, h = height;
            double topLeft = LeftEdge(first, intercept), bottomLeft = LeftEdge(last, intercept);
            var box = new TextBox(Math.Max(0, Math.Min(topLeft, bottomLeft)) / w, first / h,
                                  Math.Min(w, Math.Max(topLeft, bottomLeft) + runWidth + 1) / w, (last + 1) / h);
            // Telefon ekranın ortasında (yaya) ya da sağ yarısında (araçta) durur ve kenarlara değmez. Telefon eğilip aşağı
            // indirilince ekranın alt kenarından taşar; üstü ekranın ortalarındaysa telefondur.
            var center = (box.Left + box.Right) / 2;
            if (center < MinCenter || center > MaxCenter || box.Top < 0.04 || !(box.Bottom <= 0.96 || box.Top >= 0.2)) return null;
            return new Panel(box, topLeft / w, best.Slope * h / w, (runWidth + 1) / w);
        }
        // Aynı beyaz alan birkaç eğimde de aday çıkar; telefonun sırası gelsin diye yeterince aday sınanır. Mac 16 aday
        // sınar; buradaki küçültme CoreGraphics'inkinden bir nokta kaymış çıkabiliyor ve telefonun oyları komşu kutulara
        // bölünüp sırası düşüyordu (koyu Rydeme karesi bulunamıyordu). 32 aday sınanır; gerçek karelerdeki olumsuzlar
        // (kapüşonlu, harita, alt pencere) yine bulunmuyor.
        foreach (var best in candidates.Take(MaxAttempts))
            if (Attempt(best) is { } panel) return panel;
        return null;
    }

    /// <summary>
    /// Karenin <paramref name="width"/>×<paramref name="height"/> küçültülmüş RGB kopyası (alan ortalaması; Mac'teki
    /// CoreGraphics orta kaliteli küçültmeye yakın). Kare boşsa null.
    /// </summary>
    internal static byte[]? Downscaled(Frame frame, int width, int height)
    {
        if (frame.Width == 0 || frame.Height == 0 || width <= 0 || height <= 0) return null;
        var result = new byte[width * height * 3];
        for (var ty = 0; ty < height; ty++)
        {
            var y0 = (int)((long)ty * frame.Height / height);
            var y1 = Math.Max(y0 + 1, (int)((long)(ty + 1) * frame.Height / height));
            for (var tx = 0; tx < width; tx++)
            {
                var x0 = (int)((long)tx * frame.Width / width);
                var x1 = Math.Max(x0 + 1, (int)((long)(tx + 1) * frame.Width / width));
                long r = 0, g = 0, b = 0, n = 0;
                for (var y = y0; y < y1; y++)
                {
                    var row = y * frame.Stride;
                    for (var x = x0; x < x1; x++)
                    {
                        var i = row + (x * 4);
                        b += frame.Pixels[i];
                        g += frame.Pixels[i + 1];
                        r += frame.Pixels[i + 2];
                        n++;
                    }
                }
                var o = ((ty * width) + tx) * 3;
                result[o] = (byte)(r / n);
                result[o + 1] = (byte)(g / n);
                result[o + 2] = (byte)(b / n);
            }
        }
        return result;
    }

    /// <summary>
    /// Karedeki bir noktanın rengi (0–1 kesirlerle x, y; çevresindeki 3×3 noktanın ortalaması). Kare bir kez küçültülür.
    /// </summary>
    public static Func<double, double, Rgb?> Sampler(Frame frame, int width = 960, int height = 540)
    {
        var pixels = Downscaled(frame, width, height);
        if (pixels is null) return (_, _) => null;
        return (x, y) =>
        {
            int cx = Round(x * width), cy = Round(y * height);
            if (cx < 1 || cy < 1 || cx >= width - 1 || cy >= height - 1) return null;
            int r = 0, g = 0, b = 0;
            for (var dy = -1; dy <= 1; dy++)
                for (var dx = -1; dx <= 1; dx++)
                {
                    var i = (((cy + dy) * width) + cx + dx) * 3;
                    r += pixels[i]; g += pixels[i + 1]; b += pixels[i + 2];
                }
            return new Rgb(r / 9, g / 9, b / 9);
        };
    }

    /// <summary>
    /// Nino: telefonun ekranı kararmışsa (dokunulmadan duran telefon) renkler aydınlatılarak okunur: ekranın en aydınlık
    /// kısmı (zemin) beyaza çekilir. Koyu temalı uygulamanın ekranı olduğu gibi kalır.
    /// </summary>
    public static Func<double, double, Rgb?> LiftedSampler(Frame frame, Panel panel)
    {
        var base_ = Sampler(frame);
        var colors = new List<Rgb>();
        for (var y = panel.Box.Top + 0.03; y < panel.Box.Bottom - 0.02; y += 0.02)
            for (var share = 0.05; share <= 0.95 + 1e-9; share += 0.1)
                if (base_(panel.Left(y) + (panel.Width * share), y) is { } c) colors.Add(c);
        colors = [.. colors.OrderBy(c => c.Max)];
        var lights = colors.Select(c => c.Max).ToList();
        if (lights.Count == 0) return base_;
        var screen = lights[lights.Count * 8 / 10];
        var middle = lights[lights.Count / 2];
        var zone = colors[colors.Count * 8 / 10];
        var gray = (double)zone.Min / Math.Max(1, zone.Max);
        var brightest = lights[^1];
        if (!(screen >= 40 && screen < 232 && middle >= screen * 0.8 && gray >= 0.8 && brightest <= screen * 1.3)) return base_;
        var gain = 238.0 / screen;
        return (x, y) => base_(x, y) is { } c
            ? new Rgb(Math.Min(255, (int)(c.R * gain)), Math.Min(255, (int)(c.G * gain)), Math.Min(255, (int)(c.B * gain)))
            : null;
    }

    /// <summary>
    /// Telefon uygulamasının yazılarından telefon ekranının tahmini yeri: elde tutulan GTA 6 telefonu ≈ 0,21 genişlik,
    /// ekranın 0,20–0,82'si; yazılar bu tahminin dışına taşıyorsa kutu onları da içine alır.
    /// </summary>
    public static Panel Guess(IReadOnlyList<TextBox> boxes)
    {
        var minLeft = boxes.Count > 0 ? boxes.Min(b => b.Left) : 0.6;
        var maxRight = boxes.Count > 0 ? boxes.Max(b => b.Right) : 0.78;
        double left = Math.Max(0.02, minLeft - 0.015), right = Math.Min(0.98, Math.Max(maxRight + 0.015, left + 0.21));
        var top = Math.Min(0.2, (boxes.Count > 0 ? boxes.Min(b => b.Top) : 0.3) - 0.02);
        var bottom = Math.Min(0.95, Math.Max(0.82, (boxes.Count > 0 ? boxes.Max(b => b.Bottom) : 0.8) + 0.03));
        return new Panel(new TextBox(left, Math.Max(0.04, top), right, bottom), left, 0, right - left);
    }

    /// <summary>Ekranın içindeki noktaların ne kadarı koyu (<paramref name="dark"/>) ya da beyaz ekran rengi.</summary>
    internal static double ScreenShare(Panel panel, Frame frame, bool dark)
    {
        var sample = Sampler(frame, 480, 270);
        int hits = 0, total = 0;
        for (var row = 1; row <= 14; row++)
        {
            var y = panel.Box.Top + ((panel.Box.Bottom - panel.Box.Top) * row / 15);
            for (var column = 1; column <= 7; column++)
            {
                if (sample(panel.Left(y) + (panel.Width * column / 8), y) is not { } c) continue;
                total++;
                if (dark ? c.Max <= DarkScreenCeiling + 10 : c.Min >= WhiteFloor && c.Max - c.Min <= 45) hits++;
            }
        }
        return total == 0 ? 0 : (double)hits / total;
    }

    /// <summary>
    /// Nino: bir kez bulunan telefonu takip eder. Koyu temalı uygulamada (Rydeme) kartlar ve alt pencere ekranı böldüğünden
    /// telefon her karede baştan bulunamıyordu. Bulunamayan karede, son bulunan yerde hâlâ aynı tür ekran (koyu ya da
    /// beyaz) duruyorsa telefon orada sayılır. Takip en son gerçek bulunuştan <see cref="MaxAgeMs"/> sürer.
    /// </summary>
    public sealed class Tracker(Func<long>? clock = null)
    {
        private readonly object gate = new();
        private readonly Func<long> now = clock ?? (() => Environment.TickCount64);
        private Panel? last;
        private bool dark;
        private long lastSeen = long.MinValue / 2;
        public long MaxAgeMs { get; set; } = 20_000;

        /// <summary>
        /// Nino: telefon uygulamasının sözcükleri görüldü ama telefon bulunamadı (alt penceresi açık koyu uygulama).
        /// Telefonun yeri bu yazıların yerinden tahmin edilip takip oradan başlar.
        /// </summary>
        public void Adopt(IReadOnlyList<TextBox> boxes, Frame frame)
        {
            if (boxes.Count == 0) return;
            lock (gate)
                if (!(last is null || now() - lastSeen > 2000)) return;
            var guess = Guess(boxes);
            var isDark = ScreenShare(guess, frame, dark: true) >= 0.45;
            lock (gate) { last = guess; dark = isDark; lastSeen = now(); }
        }

        public Panel? Locate(Frame frame)
        {
            if (Find(frame) is { } found)
            {
                var isDark = ScreenShare(found, frame, dark: true) >= 0.5;
                lock (gate) { last = found; dark = isDark; lastSeen = now(); }
                return found;
            }
            Panel previous;
            bool wasDark;
            lock (gate)
            {
                if (now() - lastSeen >= MaxAgeMs || last is not { } kept) return null;
                previous = kept;
                wasDark = dark;
            }
            if (ScreenShare(previous, frame, wasDark) < 0.45)
            {
                lock (gate) last = null;
                return null;
            }
            return previous;
        }

        public void Reset()
        {
            lock (gate) last = null;
        }
    }
}
