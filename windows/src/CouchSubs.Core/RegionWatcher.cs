// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>Ek alanların çevirisini TV'ye ileten taraf (gerçekte <see cref="SubtitleServer"/>).</summary>
public interface IRegionSender
{
    /// <summary><paramref name="text"/> boşsa alanın kutusu kalkar.</summary>
    void SendRegion(string id, string text, TextBox? box, double? lineHeight = null);
    void ClearRegions();
}

/// <summary>Sürekli okunan ek alan (görev yazısı, telefon mesajı, bildirim).</summary>
/// <param name="Id">TV'deki kutunun kimliği.</param>
/// <param name="Name">Günlükte görünen ad.</param>
public sealed record WatchedArea(string Id, string Name, CropRegion Region);

/// <summary>
/// Ek alanları ana altyazıdan ayrı ve seyrek okur, çevirip TV'ye kendi yerleriyle gönderir (Mac: RegionWatcher.swift ile
/// aynı kurallar).
/// <list type="bullet">
/// <item>Ana okuma hattını beklemez, onu bekletmez: <see cref="Offer"/> hemen döner, tur arka planda sürer.</item>
/// <item>En çok <see cref="DefaultIntervalMs"/>'de bir tur atılır; önceki tur bitmediyse kare atlanır.</item>
/// <item>Bölge izi değişmeyen alan yeniden okunmaz.</item>
/// <item>Yazı ancak kararlıysa çevrilir: iz bir tur değişmediyse ya da iki okuma aynı yazıyı verdiyse.</item>
/// <item>Yazı değişmedikçe yeniden çevrilmez; boşalan alanın kutusu kalkar.</item>
/// <item>Paket ve çeviri motoru altyazıyla aynıdır; ama ek alan satırları ortak havuza önerilmez.</item>
/// </list>
/// </summary>
public sealed class RegionWatcher
{
    public const int DefaultIntervalMs = 1000;

    private sealed class State
    {
        public byte[]? Signature;
        public string? LastRead;
        public Candidate? Candidate;
        public string Shown = "";
        public string? RenderedKey;
        public string? RenderedText;
        public TextBox? RenderedBox;
        public double? RenderedLineHeight;
    }

    internal sealed record Candidate(IReadOnlyList<string> Paragraphs, TextBox? Box, double? LineHeight, string Key);

    private readonly ITextReader reader;
    private readonly ITextTranslator translator;
    private readonly IRegionSender server;
    private readonly int intervalMs;
    private readonly Func<long> now;
    private Dictionary<string, State> states = [];
    private long? lastPass;
    private int busy;
    private int session;
    private int passes;
    private int reads;

    /// <summary>Oyun paketi: satırın hazır Türkçesi (ana altyazıyla aynı arama).</summary>
    public Func<string, PackMatch?>? PackLookup { get; set; }
    public Action<string>? Log { get; set; }
    /// <summary>Her okumanın süresi (ms; ölçüm için).</summary>
    public Action<long>? ReadMeasured { get; set; }
    public int Passes => Volatile.Read(ref passes);
    public int Reads => Volatile.Read(ref reads);
    public bool IsBusy => Volatile.Read(ref busy) == 1;

    public RegionWatcher(ITextReader reader, ITextTranslator translator, IRegionSender server, int intervalMs = DefaultIntervalMs,
                         Func<long>? clock = null)
    {
        this.reader = reader;
        this.translator = translator;
        this.server = server;
        this.intervalMs = intervalMs;
        now = clock ?? (() => Environment.TickCount64);
    }

    /// <summary>Her karede çağrılır; tur zamanı geldiyse ve önceki tur bittiyse turu arka planda başlatır, hemen döner.</summary>
    public void Offer(Frame frame, IReadOnlyList<WatchedArea> areas)
    {
        if (areas.Count == 0 && !AnyShown()) return;
        var time = now();
        if (lastPass is { } last && time - last < intervalMs) return;
        if (Interlocked.Exchange(ref busy, 1) == 1) return;
        lastPass = time;
        _ = Task.Run(async () =>
        {
            try { await PassAsync(frame, areas).ConfigureAwait(false); }
            catch (Exception error) { Log?.Invoke($"ek alan turu hata verdi: {error.Message}"); }
            finally { Volatile.Write(ref busy, 0); }
        });
    }

    private bool AnyShown()
    {
        var map = states;
        lock (map) return map.Values.Any(state => state.Shown.Length > 0);
    }

    /// <summary>Bir tur: kaldırılan alanların kutusu kalkar, her alan gerekirse okunur ve kararlı yazısı çevrilir. Testler doğrudan çağırır.</summary>
    public async Task PassAsync(Frame frame, IReadOnlyList<WatchedArea> areas)
    {
        var started = Volatile.Read(ref session);
        var map = states;
        Interlocked.Increment(ref passes);
        var ids = areas.Select(area => area.Id).ToHashSet();
        List<string> removed;
        lock (map)
        {
            removed = [.. map.Where(pair => !ids.Contains(pair.Key) && pair.Value.Shown.Length > 0).Select(pair => pair.Key)];
            foreach (var id in map.Keys.Where(id => !ids.Contains(id)).ToList()) map.Remove(id);
        }
        foreach (var id in removed) server.SendRegion(id, "", null);
        foreach (var area in areas)
        {
            await VisitAsync(area, frame, map, started).ConfigureAwait(false);
            if (Volatile.Read(ref session) != started) return;
        }
    }

    private async Task VisitAsync(WatchedArea area, Frame frame, Dictionary<string, State> map, int started)
    {
        var crop = RegionCropper.Crop(frame, area.Region);
        var signature = RegionCropper.Signature(crop);
        State state;
        lock (map)
        {
            if (!map.TryGetValue(area.Id, out state!)) map[area.Id] = state = new State();
        }
        var changed = state.Signature is not { } previous || ReadScheduler.Changed(previous, signature, ReadScheduler.ChangeThreshold);
        state.Signature = signature;
        if (!changed)
        {
            // İz bir tur değişmedi: okunan yazı kararlıdır.
            if (state.Candidate is { } stable)
            {
                state.Candidate = null;
                await CommitAsync(stable, area, state, started).ConfigureAwait(false);
            }
            return;
        }
        var clock = now();
        Reading reading;
        try { reading = reader.ReadLines(crop, false); }
        catch
        {
            // OCR hatası boş alan değildir. Eski kutuyu koru; aynı kareyi sonraki normal turda yeniden oku.
            // Başarısız kare, önceki adayın kararlılığını da doğrulayamaz.
            state.Signature = null;
            state.LastRead = null;
            state.Candidate = null;
            return;
        }
        if (Volatile.Read(ref session) != started) return;
        Interlocked.Increment(ref reads);
        ReadMeasured?.Invoke(now() - clock);
        var candidate = MakeCandidate(reading, area.Region);
        if (state.LastRead == candidate.Key)
        {
            state.Candidate = null;
            await CommitAsync(candidate, area, state, started).ConfigureAwait(false);
        }
        else
        {
            state.LastRead = candidate.Key;
            state.Candidate = candidate;
        }
    }

    /// <summary>
    /// Okumadan çevrilecek parçalar: kumanda ipuçları, yazı tanıma çöpleri ve harfsiz göstergeler atılır; satırlar
    /// yukarıdan aşağı parçalara toplanır.
    /// </summary>
    internal static Candidate MakeCandidate(Reading reading, CropRegion region)
    {
        var lines = reading.WithoutButtonPrompts().WithoutOcrNoise().Lines
            .Where(line => ScreenTranslation.IsWords(line.Text))
            .OrderBy(line => line.Box?.Top ?? 0)
            .ToList();
        var paragraphs = ScreenTranslation.Paragraphs(lines);
        var place = new TextBox(region.Left, region.Top, region.Right, region.Bottom);
        var boxes = lines.Where(line => line.Box is not null).Select(line => line.Box!.Value).ToList();
        TextBox? box = boxes.Count == 0 ? null : boxes.Skip(1).Aggregate(boxes[0], (a, b) => a.Union(b)).PlacedIn(place);
        var heights = boxes.Select(b => (b.Bottom - b.Top) * (region.Bottom - region.Top)).Order().ToList();
        double? lineHeight = heights.Count == 0 ? null : heights[heights.Count / 2];
        return new Candidate(paragraphs, box, lineHeight, TextMatch.Normalize(string.Join(' ', paragraphs)));
    }

    private async Task CommitAsync(Candidate candidate, WatchedArea area, State state, int started)
    {
        if (state.Shown == candidate.Key)
        {
            if (state.RenderedKey != candidate.Key || string.IsNullOrEmpty(state.RenderedText)) return;
            if (state.RenderedBox == candidate.Box && state.RenderedLineHeight == candidate.LineHeight) return;
            server.SendRegion(area.Id, state.RenderedText, candidate.Box, candidate.LineHeight);
            state.RenderedBox = candidate.Box;
            state.RenderedLineHeight = candidate.LineHeight;
            return;
        }
        var previousShown = state.Shown;
        state.Shown = candidate.Key;
        if (candidate.Key.Length == 0)
        {
            server.SendRegion(area.Id, "", null);
            state.RenderedKey = candidate.Key;
            state.RenderedText = "";
            state.RenderedBox = null;
            state.RenderedLineHeight = null;
            Log?.Invoke($"ek alan {area.Name}: boşaldı");
            return;
        }
        string?[] result = [.. candidate.Paragraphs.Select(paragraph => PackLookup?.Invoke(paragraph)?.Text)];
        var fromPack = result.Count(text => text is not null);
        try
        {
            var missing = Enumerable.Range(0, result.Length).Where(i => result[i] is null).ToList();
            if (missing.Count > 0)
            {
                var texts = missing.Select(i => candidate.Paragraphs[i]).ToList();
                var translations = await translator.TranslateAllAsync(texts).ConfigureAwait(false);
                for (var i = 0; i < missing.Count && i < translations.Count; i++) result[missing[i]] = translations[i];
            }
        }
        catch (Exception error)
        {
            if (Volatile.Read(ref session) == started)
            {
                if (state.Shown == candidate.Key)
                {
                    state.Shown = previousShown;
                    state.Candidate = candidate;
                }
                Log?.Invoke($"ek alan {area.Name}: {SubtitleLog.Excerpt(string.Join(' ', candidate.Paragraphs))} çevrilemedi ({error.Message})");
            }
            return;
        }
        if (Volatile.Read(ref session) != started || state.Shown != candidate.Key) return;
        var text = candidate.Paragraphs.Select((source, i) => result[i]?.Trim() is { Length: > 0 } translated ? translated : source).ToList();
        // Çevirisi aslıyla aynı (ad, sayı, zaten hedef dilde): kutu gösterilmez.
        var same = candidate.Paragraphs.Select((source, i) => TextMatch.IsSimilar(TextMatch.Normalize(source), TextMatch.Normalize(text[i]), 0.90))
            .All(similar => similar);
        if (same)
        {
            server.SendRegion(area.Id, "", null);
            state.RenderedKey = candidate.Key;
            state.RenderedText = "";
            state.RenderedBox = null;
            state.RenderedLineHeight = null;
            return;
        }
        var origin = fromPack == candidate.Paragraphs.Count ? "paket" : fromPack > 0 ? "paket+motor" : "motor";
        Log?.Invoke($"ek alan {area.Name}: {SubtitleLog.Excerpt(string.Join(' ', candidate.Paragraphs))} → {origin}");
        server.SendRegion(area.Id, string.Join('\n', text), candidate.Box, candidate.LineHeight);
        state.RenderedKey = candidate.Key;
        state.RenderedText = string.Join('\n', text);
        state.RenderedBox = candidate.Box;
        state.RenderedLineHeight = candidate.LineHeight;
    }

    /// <summary>Çeviri durdu ya da hat yeniden kuruldu: süren tur bırakılır, TV'deki ek alan kutuları kalkar.</summary>
    public void Reset()
    {
        Interlocked.Increment(ref session);
        var anyShown = AnyShown();
        states = [];
        lastPass = null;
        if (anyShown) server.ClearRegions();
    }
}
