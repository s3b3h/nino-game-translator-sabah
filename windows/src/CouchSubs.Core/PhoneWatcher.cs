// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Text;

namespace CouchSubs.Core;

/// <summary>
/// Nino: telefonda bir sohbet açıksa mesajlarını okur, çevirir ve telefonun boş yanına mesajlaşma paneli olarak koyar;
/// sohbet olmayan uygulamada (BuckMe, Rydeme) her yazının Türkçesi uygulamanın renginde baloncuktur. Eskiden bu yazılar
/// altyazı sanılıp telefonun üstünde kocaman siyah kutuda çıkıyordu (Mac: AppModel.watchPhone ile aynı kurallar).
/// <list type="bullet">
/// <item>Ana okuma hattını beklemez: <see cref="Offer"/> hemen döner, okuma arka planda kendi okuyucusuyla yapılır.</item>
/// <item>Türkçeler yerleşmeden 0,6 sn'de, yerleştikten sonra 1,5 sn'de bir okunur.</item>
/// <item>Aynı okuma iki kez görülünce çevrilir (kaydırma sürerken yarım okunan satırlar çevrilmez).</item>
/// </list>
/// </summary>
public sealed class PhoneWatcher
{
    /// <summary>Telefon bu kadardan az kaydıysa (elde sallanma) panel yerinde kalır.</summary>
    internal const double Steady = 0.05;
    /// <summary>Telefondaki yazılar altyazı okumasında bu kadar süre altyazı sayılmaz.</summary>
    public const int RecentTextsMs = 30_000;

    private readonly ITextReader reader;
    private readonly ITextTranslator translator;
    private readonly Func<long> now;
    private readonly PhonePanel.Tracker tracker;
    private readonly object gate = new();
    private IReadOnlyList<ScreenTranslation.Item> items = [];
    private string key = "";
    private string pending = "";
    private long seen = long.MinValue / 2;
    private long lastCheck = long.MinValue / 2;
    private int busy;
    private int session;
    private (TextBox Panel, IReadOnlyList<ScreenTranslation.Item> Items)? placed;
    private Dictionary<string, double> anchors = [];
    private (IReadOnlyList<string> Texts, long At) recent = ([], long.MinValue / 2);
    /// <summary>Bu oturumda çevrilmiş mesajlar: sohbet kaydırılınca aynı mesaj yeniden çevrilmez.</summary>
    private readonly Dictionary<string, string> memory = [];

    public PhoneWatcher(ITextReader reader, ITextTranslator translator, Func<long>? clock = null)
    {
        this.reader = reader;
        this.translator = translator;
        now = clock ?? (() => Environment.TickCount64);
        tracker = new PhonePanel.Tracker(now);
    }

    /// <summary>Gösterilecek öğeler değişti (boşsa telefonun yanı temizlenir). Arka plan iş parçacığında çağrılır.</summary>
    public Action<IReadOnlyList<ScreenTranslation.Item>>? Changed { get; set; }
    /// <summary>Satırın hazır çevirisi (ortak havuz, paket); yoksa null.</summary>
    public Func<string, string?>? Known { get; set; }
    /// <summary>Telefon uygulamalarının sabit Türkçeleri (<see cref="PhoneThread.Glossary"/>) kullanılsın mı (hedef dil Türkçe).</summary>
    public bool UseGlossary { get; set; } = true;
    /// <summary>true döndüğü sürece (harita ya da menü açık) telefon aranmaz.</summary>
    public Func<bool>? Paused { get; set; }
    public Action<string>? Log { get; set; }
    /// <summary>Nino: oyunun telefonunda sohbet ya da uygulama okundu (bu telefon GTA 6'ya özgü; oyun buradan da tanınır).</summary>
    public Action? PhoneScreen { get; set; }

    public IReadOnlyList<ScreenTranslation.Item> Items { get { lock (gate) return items; } }

    /// <summary>Telefonda son okunan mesajlar (son <see cref="RecentTextsMs"/> içinde); altyazı okuması bunları atlar.</summary>
    public IReadOnlyList<string> RecentTexts
    {
        get { lock (gate) return now() - recent.At < RecentTextsMs ? recent.Texts : []; }
    }

    public bool IsBusy => Volatile.Read(ref busy) == 1;

    /// <summary>Telefon uygulamasının sözcükleri altyazı okumasında görüldü: telefon bu yazıların yerinden de bulunur.</summary>
    public void Adopt(IReadOnlyList<TextBox> boxes, Frame frame) => tracker.Adopt(boxes, frame);

    /// <summary>Her karede çağrılır; zamanı geldiyse ve önceki okuma bittiyse okumayı arka planda başlatır, hemen döner.</summary>
    public void Offer(Frame frame)
    {
        lock (gate)
            if (now() - lastCheck <= (items.Count == 0 ? 600 : 1500)) return;
        if (Interlocked.CompareExchange(ref busy, 1, 0) != 0) return;
        _ = Task.Run(async () =>
        {
            try { await CheckAsync(frame).ConfigureAwait(false); }
            catch (Exception error) { Log?.Invoke($"telefon: okunamadı ({error.GetType().Name})"); }
            finally { Volatile.Write(ref busy, 0); }
        });
    }

    /// <summary>Telefonun yanını temizler, takibi bırakır; süren okumanın sonucu gösterilmez.</summary>
    public void Reset()
    {
        bool had;
        lock (gate)
        {
            session++;
            had = items.Count > 0;
            items = [];
            placed = null;
            key = pending = "";
            recent = ([], long.MinValue / 2);
        }
        tracker.Reset();
        if (had) Changed?.Invoke([]);
    }

    private void Clear()
    {
        lock (gate)
        {
            if (items.Count == 0) return;
            items = [];
            placed = null;
            key = "";
        }
        Changed?.Invoke([]);
    }

    /// <summary>Bir okuma turu (sınamalar doğrudan çağırır).</summary>
    public async Task CheckAsync(Frame frame)
    {
        int started;
        lock (gate)
        {
            lastCheck = now();
            started = session;
        }
        // Harita/menü açıkken telefon aranmaz: haritanın aydınlık kısmı telefon sanılıp tuş listesi çevriliyordu.
        if (Paused?.Invoke() == true)
        {
            Clear();
            return;
        }
        if (tracker.Locate(frame) is not { } panel)
        {
            if (Items.Count > 0 && now() - Volatile.Read(ref seen) > 1200) Clear();
            return;
        }
        var box = panel.Box;
        var region = new CropRegion(box.Top, box.Bottom, box.Left, box.Right);
        var crop = RegionCropper.Crop(frame, region);
        // Küçük karede (720p) telefonun yazısı birkaç piksel boyundadır; büyütmek yazı tanımaya yardım eder.
        if (crop.Height < 900 && crop.Width * 2 <= 2600 && crop.Height * 2 <= 2600) crop = crop.Scaled(2);
        var reading = reader.ReadLines(crop, false).PlacedIn(box);
        await Process(frame, panel, reading, started).ConfigureAwait(false);
    }

    /// <summary>Okunmuş telefon ekranından öğeleri kurar (sınamalar için ayrı).</summary>
    internal async Task Process(Frame frame, PhonePanel.Panel panel, Reading reading, int started)
    {
        // Haritanın tuş listesi ("RECENTER", "2D VIEW") telefon sanılan bölgede okunduysa bu haritadır.
        if (reading.Lines.Any(line => MapCard.IsMapKey(line.Text)))
        {
            Clear();
            return;
        }
        // Sohbet: mesajlar balon olarak. Mesaj listesi çevrilmez. Başka uygulama (BuckMe bankası): satırları ayrı ayrı.
        // Başlığı ortalı uygulama ekranı ("Trip Details", Rydeme) sohbet sanılmasın: sohbette en az bir cümle olur.
        var threadMessages = PhoneThread.IsThread(reading, panel) ? PhoneThread.Messages(reading, panel) : [];
        var chat = threadMessages.Any(m => PhoneThread.IsSentence(m.Text));
        var messages = (chat ? threadMessages : PhoneThread.IsMessageList(reading) ? [] : PhoneThread.AppLines(reading, panel)).ToList();
        if (messages.Count == 0)
        {
            if (Items.Count > 0 && now() - Volatile.Read(ref seen) > 1200) Clear();
            return;
        }
        Volatile.Write(ref seen, now());
        PhoneScreen?.Invoke();
        // Kaydırınca mesajların yeri değişir: anahtar yeri de içerir (telefonun ekranına göre; el sallanınca değişmez).
        var readKey = string.Join('|', messages.Select(m => TextMatch.Normalize(m.Text) + "@" + (int)((m.Box.Top - panel.Box.Top) * 60)));
        Dictionary<string, string> known;
        var stale = false;
        try
        {
        lock (gate)
        {
            if (session != started || readKey == key) return;
            // Sohbet kaydırıldı ya da mesajlar değişti: eski Türkçeler hemen kalkar.
            if (placed is { } base_ && items.Count > 0)
            {
                var positions = new Dictionary<string, double>();
                foreach (var m in messages) positions.TryAdd(TextMatch.Normalize(m.Text), m.Box.Top - panel.Box.Top);
                var keys = base_.Items.Where(i => !i.Backdrop).Select(i => TextMatch.Normalize(i.Source)).ToList();
                var common = keys.Where(positions.ContainsKey).ToList();
                var moved = common.Any(k => anchors.TryGetValue(k, out var anchor) && Math.Abs(anchor - positions[k]) > 0.02);
                stale = moved || common.Count * 2 < keys.Count;
                if (stale)
                {
                    items = [];
                    placed = null;
                    key = "";
                }
            }
            if (readKey != pending)
            {
                pending = readKey;
                return;
            }
            known = new Dictionary<string, string>(memory);
        }
        }
        finally
        {
            // Kilidin dışında: dinleyici (uygulama) başka kilit alıp Items'ı okur; kilit sırası ters dönmesin.
            if (stale) Changed?.Invoke([]);
        }
        string? Remembered(string text)
        {
            var k = TextMatch.Normalize(text);
            if (k.Split(' ').Length < 5) return known.GetValueOrDefault(k);
            // Sondan ya da baştan kesik okunan mesaj tam halinin çevirisini alır.
            return known.Where(p => p.Key == k || p.Key.StartsWith(k + " ", StringComparison.Ordinal) || p.Key.EndsWith(" " + k, StringComparison.Ordinal))
                .OrderByDescending(p => p.Key.Length).Select(p => p.Value).FirstOrDefault();
        }
        // Ekranın dibinde cümlesi bitmemiş çok satırlı son mesaj, tamamı görünene kadar yarım çevrilmez.
        if (chat && messages[^1] is var last && Remembered(last.Text) is null
            && last.Box.Bottom > panel.Box.Bottom - 0.06 && last.Box.Bottom - last.Box.Top > last.LineHeight * 1.8
            && !(last.Text.TrimEnd(' ') is { Length: > 0 } t && ".!?…\")".Contains(t[^1])))
        {
            messages.RemoveAt(messages.Count - 1);
            if (messages.Count == 0) return;
        }
        // Ekranın üstünde baştan kesik (küçük harfle başlayan) ilk mesaj, tamamı görülmediyse yarım çevrilmez.
        if (chat && messages.Count > 1 && Remembered(messages[0].Text) is null && messages[0].Text.Length > 0 && char.IsLower(messages[0].Text[0]))
            messages.RemoveAt(0);
        var texts = messages.Select(m => (UseGlossary ? PhoneThread.Glossary(m.Text) : null) ?? Known?.Invoke(m.Text) ?? Remembered(m.Text) ?? "").ToList();
        var missing = Enumerable.Range(0, messages.Count).Where(i => texts[i].Length == 0).ToList();
        // Aynı anda en çok iki çeviri.
        using (var slots = new SemaphoreSlim(2))
        {
            var work = missing.Select(async index =>
            {
                await slots.WaitAsync().ConfigureAwait(false);
                try { return (index, await translator.TranslateAsync(messages[index].Text).ConfigureAwait(false)); }
                catch { return (index, ""); }
                finally { slots.Release(); }
            });
            foreach (var (index, turkish) in await Task.WhenAll(work).ConfigureAwait(false))
                texts[index] = WithoutIcons(turkish).Trim();
        }
        var color = PhonePanel.LiftedSampler(frame, panel);
        IReadOnlyList<ScreenTranslation.Item> built = chat
            ? PhoneThread.SideBubbles(messages, texts, panel, color, (text, width, line) =>
            {
                var wrapped = PhoneThread.Wrap(text, width, line);
                return (wrapped.Count, wrapped.Max(l => l.Length));
            }, chat: true, title: PhoneThread.TitleText(reading, panel))
            : PhoneThread.AppBubbles(messages, texts, panel, color);
        IReadOnlyList<ScreenTranslation.Item> shown;
        lock (gate)
        {
            if (session != started) return;
            foreach (var index in missing)
                if (texts[index].Length > 0) memory[TextMatch.Normalize(messages[index].Text)] = texts[index];
            if (memory.Count > 600) memory.Clear();
            recent = ([.. messages.Select(m => m.Text)], now());
            anchors = [];
            foreach (var m in messages) anchors.TryAdd(TextMatch.Normalize(m.Text), m.Box.Top - panel.Box.Top);
            // Kullanıcı isteği: panel telefonun yanında ayrı durur; telefon elde az oynadıysa yeni yerleşim eski telefon
            // yerine göre kurulur (panel yerinde kalır).
            var anchorPanel = panel.Box;
            if (placed is { } old)
            {
                var dx = (panel.Box.Left + panel.Box.Right - old.Panel.Left - old.Panel.Right) / 2;
                var dy = (panel.Box.Top + panel.Box.Bottom - old.Panel.Top - old.Panel.Bottom) / 2;
                if (Math.Abs(dx) < Steady && Math.Abs(dy) < Steady)
                {
                    built = PhoneThread.Shifted(built, -dx, -dy);
                    anchorPanel = old.Panel;
                }
                // Aynı mesaj yeniden okunduysa ve yeri az oynadıysa eski kutusu korunur (yazı boyu ve yeri zıplamasın).
                var current = old.Items;
                var sameScreen = !chat && current.Count == built.Count
                                 && current.Zip(built).All(p => p.First.Translation == p.Second.Translation && Math.Abs(p.First.Box.Top - p.Second.Box.Top) < 0.06);
                var reach = chat ? (X: 0.012, Y: 0.015) : (X: 0.04, Y: 0.06);
                built = sameScreen ? current : [.. built.Select(item =>
                    current.FirstOrDefault(same => same.Source == item.Source && same.Translation == item.Translation
                                                   && Math.Abs(same.Box.Left - item.Box.Left) < reach.X
                                                   && Math.Abs(same.Box.Top - item.Box.Top) < reach.Y) ?? item)];
            }
            placed = (anchorPanel, built);
            items = built;
            key = readKey;
            pending = "";
            shown = built;
        }
        var visible = shown.Where(i => !i.Backdrop).ToList();
        Log?.Invoke($"telefon: {visible.Count} yazı"
                    + (visible.Count > 0 ? $" ({SubtitleLog.Excerpt(visible[0].Source)} → {visible[0].Translation})" : "")
                    + (chat ? "" : " · uygulama"));
        Changed?.Invoke(shown);
    }

    /// <summary>HTML varlıkları ("&amp;amp;", "&amp;#39;") düz yazıya çevrilir (Mac: AppModel.withoutEntities).</summary>
    public static string WithoutEntities(string text) =>
        !text.Contains('&') ? text
            : text.Replace("&amp;", "&").Replace("&#39;", "'").Replace("&quot;", "\"").Replace("&lt;", "<").Replace("&gt;", ">").Replace("&apos;", "'");

    /// <summary>Çeviriye karışan simgeler (emoji, düğme simgeleri) atılır, boşluklar sadeleşir (Mac: AppModel.withoutIcons).</summary>
    public static string WithoutIcons(string text)
    {
        var builder = new StringBuilder(text.Length);
        foreach (var rune in WithoutEntities(text).EnumerateRunes())
        {
            var category = Rune.GetUnicodeCategory(rune);
            if (category is UnicodeCategory.OtherSymbol or UnicodeCategory.MathSymbol or UnicodeCategory.PrivateUse) continue;
            builder.Append(rune.ToString());
        }
        return string.Join(' ', builder.ToString().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
    }
}
