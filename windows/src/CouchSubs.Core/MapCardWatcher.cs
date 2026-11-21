// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;

namespace CouchSubs.Core;

/// <summary>
/// Nino: haritada seçili görevin kartı ("BUY FLOWERS / Lucia will appreciate this / Have some flowers delivered…")
/// çevrilir ve kartın hemen altına (yer yoksa üstüne) oyunun kartı gibi yazılır; menünün kalanı çevrilmez. Harita
/// açıkken altyazı okunmaz ve telefon aranmaz (Mac: AppModel.showMapCard / placeMapCard ile aynı kurallar).
/// Karenin tamamı seyrek (<see cref="DefaultIntervalMs"/>'de bir) ve kendi okuyucusuyla okunur.
/// </summary>
public sealed class MapCardWatcher
{
    public const int DefaultIntervalMs = 2000;
    /// <summary>Harita görüldükten sonra bu kadar süre açık sayılır.</summary>
    public const int MapHoldMs = 5000;

    private readonly ITextReader reader;
    private readonly ITextTranslator translator;
    private readonly Func<long> now;
    private readonly int intervalMs;
    private readonly object gate = new();
    private IReadOnlyList<ScreenTranslation.Item> items = [];
    private string key = "";
    private MapCard.Found? waiting;
    private bool translating;
    private readonly Dictionary<string, IReadOnlyList<string>> memory = [];
    private (string Title, double Top) shownCard = ("", -1);
    private string shownText = "";
    private long mapUntil = long.MinValue / 2;
    private long lastPass = long.MinValue / 2;
    private int busy;
    private int session;
    private Frame? lastFrame;

    public MapCardWatcher(ITextReader reader, ITextTranslator translator, int intervalMs = DefaultIntervalMs, Func<long>? clock = null)
    {
        this.reader = reader;
        this.translator = translator;
        this.intervalMs = intervalMs;
        now = clock ?? (() => Environment.TickCount64);
    }

    /// <summary>Gösterilecek öğeler değişti (boşsa kart kalkar). Arka plan iş parçacığında çağrılır.</summary>
    public Action<IReadOnlyList<ScreenTranslation.Item>>? Changed { get; set; }
    /// <summary>Satırın hazır çevirisi (ortak havuz, paket); yoksa null.</summary>
    public Func<string, string?>? Known { get; set; }
    /// <summary>Kart başlığı Türkçe büyük harfe çevrilir ("İ"); başka dilde kültürden bağımsız.</summary>
    public string TargetLanguage { get; set; } = "tr";
    public Action<string>? Log { get; set; }
    /// <summary>Nino: her okumanın (karenin büyük kısmı) satırları; oyun buradan da tanınır (bkz. <see cref="GameMarkers"/>).</summary>
    public Action<Reading>? Screen { get; set; }

    public IReadOnlyList<ScreenTranslation.Item> Items { get { lock (gate) return items; } }

    /// <summary>Harita ekranı açık mı (son <see cref="MapHoldMs"/> içinde tuş listesi görüldü).</summary>
    public bool MapOpen { get { lock (gate) return now() < mapUntil; } }

    /// <summary>Harita az önce açıktı (telefon araması bu süre de bekler; harita kapanırken telefon sanılıyordu).</summary>
    public bool RecentlyOpen(int extraMs) { lock (gate) return now() < mapUntil + extraMs || items.Count > 0; }

    public void Offer(Frame frame)
    {
        lock (gate)
        {
            if (now() - lastPass < intervalMs) return;
            lastPass = now();
        }
        if (Interlocked.CompareExchange(ref busy, 1, 0) != 0) return;
        _ = Task.Run(async () =>
        {
            try { await CheckAsync(frame).ConfigureAwait(false); }
            catch (Exception error) { Log?.Invoke($"harita: okunamadı ({error.GetType().Name})"); }
            finally { Volatile.Write(ref busy, 0); }
        });
    }

    public void Reset()
    {
        bool had;
        lock (gate)
        {
            session++;
            had = items.Count > 0;
            items = [];
            key = "";
            waiting = null;
            mapUntil = long.MinValue / 2;
        }
        if (had) Changed?.Invoke([]);
    }

    /// <summary>Bir okuma turu: karenin üstten alta çoğu (sekme şeridi ve alt kenar hariç) okunur.</summary>
    public async Task CheckAsync(Frame frame)
    {
        var region = new CropRegion(Top: 0.03, Bottom: 0.95, Left: 0.0, Right: 1.0);
        var place = new TextBox(region.Left, region.Top, region.Right, region.Bottom);
        var area = RegionCropper.Crop(frame, region);
        // Windows'un yazı tanıması 2600 pikselden büyük görüntüyü okumaz (4K yakalama kartı): yarıya küçültülür.
        while (area.Width > 2600 || area.Height > 2600) area = Half(area);
        var reading = reader.ReadLines(area, false).WithoutOcrNoise().PlacedIn(place);
        await Process(frame, reading).ConfigureAwait(false);
    }

    /// <summary>Görüntünün yarı boyutlu kopyası (2×2 noktanın ortalaması).</summary>
    internal static Frame Half(Frame image)
    {
        var result = Frame.Blank(image.Width / 2, image.Height / 2);
        for (var y = 0; y < result.Height; y++)
            for (var x = 0; x < result.Width; x++)
                for (var c = 0; c < 4; c++)
                {
                    int P(int dx, int dy) => image.Pixels[((2 * y) + dy) * image.Stride + (((2 * x) + dx) * 4) + c];
                    result.Pixels[(y * result.Stride) + (x * 4) + c] = (byte)((P(0, 0) + P(1, 0) + P(0, 1) + P(1, 1) + 2) / 4);
                }
        return result;
    }

    /// <summary>Okunmuş kareden harita kartını bulur (sınamalar için ayrı).</summary>
    internal async Task Process(Frame frame, Reading reading)
    {
        Screen?.Invoke(reading);
        if (!MapCard.IsMapScreen(reading))
        {
            if (Items.Count > 0) Clear();
            return;
        }
        lock (gate)
        {
            mapUntil = now() + MapHoldMs;
            lastFrame = frame;
        }
        if (MapCard.Find(reading) is { } card)
        {
            // Çeviri okumayı bekletmez: çeviri sürerken de harita okunmaya devam eder (harita açık sayılır, seçilen yeni
            // kart beklemeye alınır).
            var showing = ShowSafely(card);
            lock (gate) lastShow = showing;
        }
        else if (Items.Count > 0) Clear();
        await Task.CompletedTask.ConfigureAwait(false);
    }

    private Task lastShow = Task.CompletedTask;

    /// <summary>Süren kart çevirisinin bitmesini bekler (sınamalar için).</summary>
    internal Task WhenShown() { lock (gate) return lastShow; }

    private async Task ShowSafely(MapCard.Found card)
    {
        try { await Show(card).ConfigureAwait(false); }
        catch (Exception error) { Log?.Invoke($"harita: kart çevrilemedi ({error.GetType().Name})"); }
    }

    private void Clear(bool forget = true)
    {
        lock (gate)
        {
            if (items.Count == 0) return;
            items = [];
            if (forget) key = "";
        }
        Changed?.Invoke([]);
    }

    private static string Normalize(string text) => TextMatch.Normalize(text);

    private async Task Show(MapCard.Found card)
    {
        // Nino: PS5'in kendi bildirimi zaten Türkçe; kart değildir.
        var all = string.Join(' ', new[] { card.Title }.Concat(card.Sentences));
        if (all.Any(c => "ğışĞİŞ".Contains(c)) || card.Sentences.Count == 0) return;
        // PS5'in sağ üstteki bildirimi ve ekranın en üstündeki sekme şeridi görev kartı değildir.
        if (card.Title.Length == 0 && card.Box.Left > 0.6 && card.Box.Top < 0.32) return;
        if (card.Box.Top < 0.1) return;
        var fullText = Normalize(all);
        var cardKey = fullText + "@" + (int)(card.Box.Top * 50);
        int started;
        lock (gate)
        {
            // Aynı kartın yarım okuması (alttaki satır okunamadı) ekrandaki tam okumanın yerine geçmez.
            if (card.Title.Length > 0 && Normalize(card.Title) == shownCard.Title && shownText.StartsWith(fullText, StringComparison.Ordinal) && shownText != fullText) return;
            if (cardKey == key) return;
            key = cardKey;
            started = session;
        }
        // İmleç başka yere geçti: eski kartın Türkçesi yeni kartın altında kalmasın. Aynı kart (aynı başlık, aynı yer) biraz
        // farklı okunduysa eski Türkçe yenisi gelene kadar kalır.
        var sameCard = card.Title.Length > 0 && Normalize(card.Title) == shownCard.Title && Math.Abs(card.Box.Top - shownCard.Top) < 0.04;
        if (!sameCard) Clear(forget: false);
        IReadOnlyList<string>? remembered;
        lock (gate)
        {
            memory.TryGetValue(cardKey, out remembered);
            if (remembered is null && translating)
            {
                // Çeviri sürüyorsa yeni kart beklemeye alınır (en son seçilen); süren bitince o çevrilir.
                waiting = card;
                return;
            }
            if (remembered is null) { translating = true; waiting = null; }
        }
        if (remembered is not null)
        {
            Place(card, remembered, cardKey);
            return;
        }
        var lines = new List<string>();
        try
        {
            var culture = TargetLanguage == "tr" ? CultureInfo.GetCultureInfo("tr-TR") : CultureInfo.InvariantCulture;
            if (card.Title.Length > 0)
            {
                var title = await Translate(CultureInfo.InvariantCulture.TextInfo.ToTitleCase(card.Title.ToLowerInvariant())).ConfigureAwait(false);
                if (title.Length > 0) lines.Add(title.ToUpper(culture));
            }
            foreach (var sentence in card.Sentences)
            {
                var text = await Translate(sentence).ConfigureAwait(false);
                // Satırlara bölünmez (TV kutunun genişliğine göre böler).
                if (text.Length > 0) lines.Add(WithMapTerms(PhoneWatcher.WithoutEntities(text)));
            }
        }
        finally
        {
            lock (gate) translating = false;
        }
        MapCard.Found? next;
        lock (gate)
        {
            if (session != started) return;
            if (lines.Count > 0) memory[cardKey] = lines;
            if (memory.Count > 200) memory.Clear();
            next = waiting;
            waiting = null;
            if (next is not null) key = "";
        }
        if (next is not null)
        {
            // Çeviri sürerken imleç başka karta geçti: bu sonuç gösterilmez, en son kart çevrilir.
            await Show(next).ConfigureAwait(false);
            return;
        }
        lock (gate)
        {
            if (key != cardKey || lines.Count == 0) return;
            if (now() >= mapUntil)
            {
                // Harita çeviri sürerken kapandı: kart gösterilmez; yeniden açılınca hafızadan hemen gelir.
                key = "";
                return;
            }
        }
        Place(card, lines, cardKey);
    }

    private async Task<string> Translate(string piece)
    {
        var result = Known?.Invoke(piece);
        if (result is null)
        {
            try { result = await translator.TranslateAsync(piece).ConfigureAwait(false); }
            catch { result = ""; }
        }
        return PhoneWatcher.WithoutIcons(result).Trim();
    }

    /// <summary>
    /// Nino: oyunun sık geçen terimlerinin yanlış çevirileri düzeltilir ("marked bills" → işaretli banknot, "lockup" → depo).
    /// </summary>
    public static string WithMapTerms(string text)
    {
        (string, string)[] fixes =
        [
            ("KAPALI TUTULMASI", "DEPOSU"), ("Kapalı Tutulması", "Deposu"), ("kapalı tutulması", "deposu"),
            ("işaretli faturaların", "işaretli banknotların"), ("işaretli faturalar", "işaretli banknotlar"),
            ("işaretli fatura", "işaretli banknot"), ("narkotik", "uyuşturucu"), ("NARKOTİK", "UYUŞTURUCU"),
            ("trafik ışığı papağan balığı", "stoplight papağan balığı"), ("kırmızı ışık papağan balığı", "stoplight papağan balığı"),
        ];
        return fixes.Aggregate(text, (current, fix) => current.Replace(fix.Item1, fix.Item2, StringComparison.Ordinal));
    }

    /// <summary>
    /// Nino: kartın başlığı bir dükkân ya da mekân adıysa ("RIDEOUT CUSTOMS", "ONE-EYED WILLIE'S AUTO SHOP") çevrilmez.
    /// </summary>
    public static bool IsPlaceName(string title, string description = "")
    {
        string[] business = ["distributor", "shop", "store", "dive bar", " bar", "restaurant", "dealer", "club", "diner", "garage",
                             "convenience", "wholesaler", "boutique", "salon", "motel", "hotel", "bodega"];
        var about = description.ToLowerInvariant();
        if (business.Any(word => about.Contains(word, StringComparison.Ordinal))) return true;
        var upper = title.ToUpperInvariant();
        var words = upper.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        HashSet<string> places = ["CUSTOMS", "AUTO", "SHOP", "BAR", "CLUB", "MOTORS", "GARAGE", "CARE", "SPEEDWAY", "DINER",
                                  "CAFE", "GRILL", "MOTEL", "HOTEL", "STORE", "MART", "LOUNGE", "SALOON", "TACKLE", "ANCHOR",
                                  "MARINA", "AMMU-NATION", "BARBER", "TATTOO", "PAWN"];
        return words.Any(places.Contains) || (upper.StartsWith("THE ", StringComparison.Ordinal) && words.Length <= 4);
    }

    /// <summary>
    /// Kartın Türkçesi oyunun kartı gibi; kartın çerçevesiyle aynı sol kenarda, hemen altında; yer yoksa üstünde; o da
    /// yetmezse yazı küçülür.
    /// </summary>
    internal static ScreenTranslation.Item Placement(MapCard.Found card, IReadOnlyList<string> translated, TextBox? frameBox)
    {
        var lines = translated.Select(l => WithMapTerms(PhoneWatcher.WithoutEntities(l))).ToList();
        if (card.Title.Length > 0 && lines.Count > 0 && IsPlaceName(card.Title, string.Join(' ', card.Sentences))) lines[0] = card.Title;
        var line = Math.Min(Math.Max(card.LineHeight, 0.02), 0.032) * 0.85;
        var frame = frameBox ?? new TextBox(card.Box.Left - 0.015, card.Box.Top - 0.02, card.Box.Right + 0.015, card.Box.Bottom + 0.02);
        // Dar yazı tipi: bir harf satır yüksekliğinin yaklaşık %42'si.
        var charWidth = line * 0.42 * 9 / 16;
        var longest = (double)(lines.Count > 0 ? lines.Max(l => l.Length) : 10);
        var width = Math.Min(frame.Right - frame.Left, (longest * charWidth) + 0.035);
        var rows = lines.Select((text, index) => index == 0 ? 1 : Math.Max(1, (int)Math.Ceiling(text.Length * charWidth / (width - 0.03)))).Sum();
        var height = (line * rows * 1.32) + 0.022;
        double below = 0.97 - (frame.Bottom + 0.012), above = frame.Top - 0.012 - 0.02;
        var top = frame.Bottom + 0.012;
        if (height > below)
        {
            if (height <= above || above > below)
            {
                if (height > above) { line *= (above - 0.022) / (height - 0.022); height = above; }
                top = frame.Top - 0.012 - height;
            }
            else
            {
                line *= (below - 0.022) / (height - 0.022);
                height = below;
            }
        }
        var left = Math.Max(frame.Left, card.Box.Left - 0.014);
        return new ScreenTranslation.Item(string.Join(' ', new[] { card.Title }.Concat(card.Sentences)), string.Join('\n', lines),
                                          new TextBox(left, top, left + width, top + height), line) { Card = true };
    }

    private void Place(MapCard.Found card, IReadOnlyList<string> lines, string cardKey)
    {
        Frame? frame;
        lock (gate) frame = lastFrame;
        var item = Placement(card, lines, frame is null ? null : MapCard.Frame(card.Box, frame));
        lock (gate)
        {
            if (key != cardKey) return;
            items = [item];
            shownCard = (Normalize(card.Title), card.Box.Top);
            shownText = Normalize(string.Join(' ', new[] { card.Title }.Concat(card.Sentences)));
        }
        Log?.Invoke($"harita kartı: {SubtitleLog.Excerpt(card.Title.Length > 0 ? card.Title : card.Sentences[0])} → {SubtitleLog.Excerpt(lines[0])}");
        Changed?.Invoke([item]);
    }
}
