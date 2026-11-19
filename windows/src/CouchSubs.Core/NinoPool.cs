// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Net;
using System.Net.NetworkInformation;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CouchSubs.Core;

/// <summary>
/// Nino'nun ortak altyazı havuzu istemcisi (Mac'teki CouchSubsCore/NinoPool ile aynı tasarım ve biçim). Pakette
/// bulunmayan İngilizce satırlar cihazda kalıcı bir kuyruğa yazılır ve sunucu "aldım" diyene kadar orada kalır:
/// <list type="number">
/// <item>Her satır görüldüğü anda <c>pending.jsonl</c> dosyasının sonuna eklenir (uygulama çökse de diskte kalır).</item>
/// <item>Gönderim zamanı gelince bekleyenler (oyun, oturum, metin) başına sayılarak birleşir ve kimlikli parçalar hâlinde
/// <c>outbox\</c> klasörüne yazılır. Parça, sunucu kimliğini geri söyleyene kadar silinmez; yanıt kaybolursa aynı
/// kimlikle yeniden gider, sunucu onu ikinci kez saymaz.</item>
/// <item>Ağ yoksa ya da sunucu hata verirse artan aralıklarla (30 sn → 1 sa) yeniden denenir; ağ gelince hemen denenir.
/// 429'da sunucunun istediği kadar beklenir.</item>
/// <item>Sunucunun kabul etmediği parça (400) silinmez, <c>parked\</c> klasörüne alınır ve uygulama güncellenince yeniden
/// denenir. Çok büyük parça (413) ikiye bölünür.</item>
/// <item>Canlı sunucu adresi yoksa satırlar kuyrukta bekler.</item>
/// </list>
/// Kişisel veri gitmez: satırın metni, varsa oyun ipucu, her açılışta yeni rastgele oturum kimliği, kaç kez/ne zaman
/// görüldüğü, kuruluma özgü rastgele kimlik, uygulama sürümü ve platform.
/// </summary>
public sealed class NinoPool : IDisposable
{
    /// <summary>Canlı havuz sunucusu (Cloudflare Workers, nino-pool/); denemede NINO_POOL_URL ya da endpoint.txt ile değişir.</summary>
    public static readonly Uri? LiveEndpoint = new("https://nino-pool.y-demirbag2506.workers.dev");
    public static readonly TimeSpan TickInterval = TimeSpan.FromMinutes(1);
    /// <summary>Gönderim en erken bu kadar biriktirince yapılır (ya da en eski satır bu kadar bekleyince).</summary>
    public static readonly TimeSpan SendEvery = TimeSpan.FromMinutes(2);

    public sealed class Limits
    {
        public int BatchSize { get; init; } = 200;
        public long MaxPendingBytes { get; init; } = 64L * 1024 * 1024;
        public int MaxOutbox { get; init; } = 2000;
        public int MaxTextLength { get; init; } = 500;
        public long MaxRejectedBytes { get; init; } = 1024 * 1024;
        public TimeSpan BackoffBase { get; init; } = TimeSpan.FromSeconds(30);
        public TimeSpan BackoffMax { get; init; } = TimeSpan.FromHours(1);
    }

    internal sealed class State
    {
        [JsonPropertyName("install")] public string Install { get; set; } = NewId();
        [JsonPropertyName("frozenThrough")] public long FrozenThrough { get; set; }
        [JsonPropertyName("failures")] public int Failures { get; set; }
        [JsonPropertyName("nextAttempt")] public double NextAttempt { get; set; }
        [JsonPropertyName("serverRetryAt")] public double ServerRetryAt { get; set; }
        [JsonPropertyName("app")] public string App { get; set; } = "";
        [JsonPropertyName("dropped")] public int Dropped { get; set; }
    }

    internal sealed record Sighting(
        [property: JsonPropertyName("s")] long S,
        [property: JsonPropertyName("t")] string T,
        [property: JsonPropertyName("g")] string? G,
        [property: JsonPropertyName("e")] string? E,
        [property: JsonPropertyName("a")] double A);

    public sealed class WireLine
    {
        [JsonPropertyName("text")] public string Text { get; set; } = "";
        [JsonPropertyName("game")] public string? Game { get; set; }
        [JsonPropertyName("session")] public string? Session { get; set; }
        [JsonPropertyName("count")] public int Count { get; set; }
        [JsonPropertyName("first")] public long First { get; set; }
        [JsonPropertyName("last")] public long Last { get; set; }
    }

    public sealed class Batch
    {
        [JsonPropertyName("v")] public int V { get; set; } = 1;
        [JsonPropertyName("batch")] public string Id { get; set; } = "";
        [JsonPropertyName("install")] public string Install { get; set; } = "";
        [JsonPropertyName("app")] public string App { get; set; } = "";
        [JsonPropertyName("platform")] public string Platform { get; set; } = "";
        [JsonPropertyName("lines")] public List<WireLine> Lines { get; set; } = [];
        [JsonPropertyName("upTo")] public long UpTo { get; set; }
    }

    private sealed class Reply
    {
        [JsonPropertyName("ok")] public bool Ok { get; set; }
        [JsonPropertyName("batch")] public string? Batch { get; set; }
        [JsonPropertyName("rejected")] public List<Rejected>? Rejected { get; set; }
    }

    private sealed class Rejected
    {
        [JsonPropertyName("i")] public int I { get; set; }
        [JsonPropertyName("reason")] public string Reason { get; set; } = "";
    }

    public sealed record Status(int PendingLines, int OutboxBatches, int ParkedBatches, int Dropped, bool HasEndpoint);

    private static readonly JsonSerializerOptions Json = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };
    private static readonly Random Jitter = new();

    private readonly object gate = new();
    private readonly SemaphoreSlim flushing = new(1, 1);
    private readonly string directory;
    private readonly string app;
    private readonly string platform;
    private readonly HttpClient http;
    private readonly Func<DateTimeOffset> clock;
    private readonly Limits limits;
    private readonly string session = NewId();
    private readonly State state;
    private Uri? endpoint;
    private long nextSeq;
    private long pendingBytes;
    private int pendingCount;
    private double? oldestPending;
    private bool enabled;
    private Timer? ticker;
    private bool disposed;

    private string StateFile => Path.Combine(directory, "state.json");
    private string PendingFile => Path.Combine(directory, "pending.jsonl");
    private string OutboxDir => Path.Combine(directory, "outbox");
    private string ParkedDir => Path.Combine(directory, "parked");
    private string RejectedFile => Path.Combine(directory, "rejected.jsonl");

    /// <summary>Adres: <c>NINO_POOL_URL</c> ortam değişkeni, sonra klasördeki <c>endpoint.txt</c>, sonra <see cref="LiveEndpoint"/>.</summary>
    public static Uri? ConfiguredEndpoint(string directory, Func<string, string?>? environment = null)
    {
        environment ??= Environment.GetEnvironmentVariable;
        string? fromFile = null;
        try { fromFile = File.Exists(Path.Combine(directory, "endpoint.txt")) ? File.ReadAllText(Path.Combine(directory, "endpoint.txt")) : null; }
        catch (IOException) { }
        foreach (var value in new[] { environment("NINO_POOL_URL"), fromFile })
        {
            if (value?.Trim() is { Length: > 0 } text && Uri.TryCreate(text, UriKind.Absolute, out var url)
                && (url.Scheme == Uri.UriSchemeHttp || url.Scheme == Uri.UriSchemeHttps))
                return url;
        }
        return LiveEndpoint;
    }

    /// <param name="directory">Havuz klasörü (%LOCALAPPDATA%\Nino\pool).</param>
    /// <param name="endpoint">Sunucu; verilmezse <see cref="ConfiguredEndpoint"/>.</param>
    /// <param name="legacyFile">CouchSubs'tan kalan pool.json; gönderilmemiş satırları bir kez kuyruğa alınır.</param>
    /// <param name="handler">HTTP katmanı; testlerde sahtesi verilir.</param>
    public NinoPool(string directory, string app, string platform = "windows", bool enabled = true, Uri? endpoint = null,
        bool useConfiguredEndpoint = true, string? legacyFile = null, Limits? limits = null, HttpMessageHandler? handler = null,
        Func<DateTimeOffset>? clock = null)
    {
        this.directory = directory;
        this.app = app;
        this.platform = platform;
        this.enabled = enabled;
        this.clock = clock ?? (() => DateTimeOffset.UtcNow);
        this.limits = limits ?? new Limits();
        http = handler is null ? new HttpClient() : new HttpClient(handler, disposeHandler: false);
        http.Timeout = TimeSpan.FromSeconds(30);
        Directory.CreateDirectory(OutboxDir);
        Directory.CreateDirectory(ParkedDir);
        this.endpoint = endpoint ?? (useConfiguredEndpoint ? ConfiguredEndpoint(directory) : null);

        state = LoadState();
        // Parça yazılıp durum yazılamadan kapanmışsa: parçaların kapsadığı sıra numarası esastır.
        foreach (var file in BatchFiles(OutboxDir))
            if (ReadBatch(file) is { } batch) state.FrozenThrough = Math.Max(state.FrozenThrough, batch.UpTo);
        // Uygulama güncellendiyse: kabul edilmemiş parçalar yeniden denenir.
        if (state.App != app)
        {
            foreach (var file in BatchFiles(ParkedDir))
                TryMove(file, Path.Combine(OutboxDir, Path.GetFileName(file)));
            state.App = app;
        }
        // Açılışta hemen denenir (sunucunun istediği bekleme korunur).
        state.Failures = 0;
        state.NextAttempt = 0;
        // enabled: false yalnız bu çalışmada etkisiz olmak demek (test, klip): kuyruk silinmez. Kullanıcı havuzu
        // kapatınca silme SetEnabled(false) ile yapılır.
        RepairPending(PendingFile);
        var scan = ScanPending(PendingFile, state.FrozenThrough);
        if (enabled && legacyFile is not null)
        {
            ImportLegacy(legacyFile, PendingFile, Math.Max(scan.MaxSeq, state.FrozenThrough) + 1, this.limits.MaxTextLength, Now());
            scan = ScanPending(PendingFile, state.FrozenThrough);
        }
        nextSeq = Math.Max(scan.MaxSeq, state.FrozenThrough) + 1;
        pendingBytes = scan.Bytes;
        pendingCount = scan.List.Count;
        oldestPending = scan.Oldest;
        WriteState();
    }

    public string InstallId => state.Install;
    public string SessionId => session;
    public bool IsEnabled { get { lock (gate) return enabled; } }

    public Status GetStatus()
    {
        lock (gate)
            return new Status(pendingCount, BatchFiles(OutboxDir).Count, BatchFiles(ParkedDir).Count, state.Dropped, endpoint is not null);
    }

    public void SetEndpoint(Uri? url)
    {
        lock (gate)
        {
            endpoint = url;
            state.Failures = 0;
            state.NextAttempt = 0;
            WriteState();
        }
    }

    /// <summary>Kapatılınca bekleyen her şey silinir: kullanıcı vazgeçtiyse hiçbir şey gitmez.</summary>
    public void SetEnabled(bool value)
    {
        lock (gate)
        {
            enabled = value;
            if (value) return;
            RemoveQueued();
            pendingBytes = 0;
            pendingCount = 0;
            oldestPending = null;
            state.Failures = 0;
            state.NextAttempt = 0;
            state.ServerRetryAt = 0;
            WriteState();
        }
    }

    /// <summary>Okunan (pakette bulunmayan) satırı kuyruğa yazar. <paramref name="game"/>: varsa oyun ipucu (paket kimliği).</summary>
    public bool Offer(string raw, string? game = null)
    {
        var text = Clean(raw);
        if (!Accepts(text, limits.MaxTextLength)) return false;
        lock (gate)
        {
            if (!enabled || disposed) return false;
            return AppendLocked(text, GameId(game), session, Now());
        }
    }

    /// <summary>Zamanı geldiyse bekleyenleri parçalara aktarır ve gönderir. Sık çağrılabilir.</summary>
    public async Task FlushAsync(bool force = false)
    {
        if (!await flushing.WaitAsync(0).ConfigureAwait(false)) return;
        try
        {
            Uri target;
            lock (gate)
            {
                if (!enabled || disposed || endpoint is null) return;
                var now = Now();
                if (now < state.NextAttempt || now < state.ServerRetryAt) return;
                target = endpoint;
                var due = force || pendingCount >= limits.BatchSize || (oldestPending is { } oldest && now - oldest >= SendEvery.TotalSeconds);
                if (due) FreezeLocked();
            }
            await SendOutboxAsync(target).ConfigureAwait(false);
        }
        finally
        {
            flushing.Release();
        }
    }

    /// <summary>Ağ yeniden geldi: artan bekleme sıfırlanır ve hemen denenir.</summary>
    public Task NetworkAvailableAsync()
    {
        lock (gate)
        {
            state.Failures = 0;
            state.NextAttempt = 0;
            WriteState();
        }
        return FlushAsync();
    }

    /// <summary>Dakikada bir dener ve ağ gelince hemen gönderir (uygulamada bir kez çağrılır).</summary>
    public void StartBackground()
    {
        ticker ??= new Timer(_ => _ = FlushAsync(), null, TimeSpan.FromSeconds(5), TickInterval);
        NetworkChange.NetworkAvailabilityChanged += OnNetworkChanged;
    }

    private void OnNetworkChanged(object? sender, NetworkAvailabilityEventArgs e)
    {
        if (e.IsAvailable) _ = NetworkAvailableAsync();
    }

    /// <summary>Kapanışta: satırlar zaten diskte, ağ beklenmez.</summary>
    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return;
            disposed = true;
            WriteState();
        }
        NetworkChange.NetworkAvailabilityChanged -= OnNetworkChanged;
        ticker?.Dispose();
        http.Dispose();
    }

    // --- Süzgeç ---

    /// <summary>Havuza uygun satır: harf içeriyor, en çok 500 karakter, yazı tanıma çöpü değil; Türkçe, PS5 sistem yazısı
    /// (ör. "X signed in": PSN adı taşıyabilir) ya da yarım okuma değil (<see cref="PoolFilter"/>).</summary>
    public static bool Accepts(string text, int maxLength = 500)
    {
        if (text.Length == 0 || text.EnumerateRunes().Count() > maxLength || !text.Any(char.IsLetter)) return false;
        return !LinePool.LooksLikeNoise(text) && PoolFilter.Accepts(text);
    }

    public static string Clean(string raw)
    {
        var builder = new StringBuilder(raw.Length);
        foreach (var rune in raw.EnumerateRunes())
        {
            var v = rune.Value;
            var control = v <= 0x1F || (v >= 0x7F && v <= 0x9F) || (v >= 0x200B && v <= 0x200F) || v == 0x2028 || v == 0x2029 || v == 0xFEFF;
            builder.Append(control ? " " : rune.ToString());
        }
        return string.Join(' ', builder.ToString().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
    }

    /// <summary>Paket kimliği sunucunun beklediği biçimde: küçük harf, harf/rakam/.-_ dışı tire, en çok 64 karakter.</summary>
    public static string? GameId(string? game)
    {
        if (game is null) return null;
        var mapped = new string(game.ToLowerInvariant().Select(c => (char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '-') ? c : '-').ToArray());
        // Art arda tireler teke iner (Mac ile aynı): "Mafia: The Old Country" → "mafia-the-old-country".
        mapped = System.Text.RegularExpressions.Regex.Replace(mapped, "-{2,}", "-").Trim('-', '.', '_');
        return mapped.Length == 0 ? null : mapped[..Math.Min(mapped.Length, 64)];
    }

    // --- Bekleyenler ---

    private bool AppendLocked(string text, string? game, string? sessionId, double at)
    {
        if (pendingBytes >= limits.MaxPendingBytes)
        {
            state.Dropped++;
            WriteState();
            return false;
        }
        var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new Sighting(nextSeq, text, game, sessionId, at), Json) + "\n");
        try
        {
            using var stream = new FileStream(PendingFile, FileMode.Append, FileAccess.Write, FileShare.Read);
            stream.Write(bytes);
        }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
        nextSeq++;
        pendingBytes += bytes.Length;
        pendingCount++;
        oldestPending ??= at;
        return true;
    }

    internal static void RepairPending(string file)
    {
        try
        {
            if (!File.Exists(file)) return;
            var data = File.ReadAllBytes(file);
            if (data.Length == 0 || data[^1] == (byte)'\n') return;
            var keep = Array.LastIndexOf(data, (byte)'\n') + 1;
            using var stream = new FileStream(file, FileMode.Open, FileAccess.Write);
            stream.SetLength(keep);
        }
        catch (IOException) { }
    }

    internal sealed record Scan(List<Sighting> List, long MaxSeq, long Bytes, double? Oldest);

    internal static Scan ScanPending(string file, long after)
    {
        var list = new List<Sighting>();
        long maxSeq = 0, bytes = 0;
        try
        {
            if (!File.Exists(file)) return new Scan(list, 0, 0, null);
            bytes = new FileInfo(file).Length;
            foreach (var line in File.ReadLines(file, Encoding.UTF8))
            {
                if (line.Length == 0) continue;
                Sighting? sighting;
                try { sighting = JsonSerializer.Deserialize<Sighting>(line, Json); }
                catch (JsonException) { continue; } // yarım yazılmış satır
                if (sighting is null || sighting.T is null) continue;
                maxSeq = Math.Max(maxSeq, sighting.S);
                if (sighting.S > after) list.Add(sighting);
            }
        }
        catch (IOException) { }
        return new Scan(list, maxSeq, bytes, list.Count == 0 ? null : list.Min(s => s.A));
    }

    /// <summary>Bekleyenleri birleştirip parçalara yazar; parçalar diske yazılmadan bekleyenler silinmez.</summary>
    private void FreezeLocked()
    {
        if (pendingCount == 0) return;
        if (BatchFiles(OutboxDir).Count >= limits.MaxOutbox) return;
        var scan = ScanPending(PendingFile, state.FrozenThrough);
        if (scan.List.Count == 0) { CompactPendingLocked(); return; }
        // Parçalar sıra numarasına göre ardışık dilimlerdir: her parçanın UpTo'su yalnız kendi kapsadığı son satırdır,
        // birleştirme parça sınırını aşmaz; yarıda çökülse de yazılmamış parçaların satırları bekleyenlerde kalır.
        var chunks = new List<(List<WireLine> Lines, long UpTo)>();
        var merged = new Dictionary<string, WireLine>();
        var lines = new List<WireLine>();
        var last = state.FrozenThrough;
        foreach (var s in scan.List.OrderBy(s => s.S))
        {
            var id = $"{s.G}\0{s.E}\0{s.T}";
            var at = (long)s.A;
            if (merged.TryGetValue(id, out var line))
            {
                line.Count++;
                line.First = Math.Min(line.First, at);
                line.Last = Math.Max(line.Last, at);
            }
            else
            {
                if (lines.Count == limits.BatchSize)
                {
                    chunks.Add((lines, last));
                    lines = [];
                    merged = [];
                }
                line = new WireLine { Text = s.T, Game = s.G, Session = s.E, Count = 1, First = at, Last = at };
                merged[id] = line;
                lines.Add(line);
            }
            last = s.S;
        }
        if (lines.Count > 0) chunks.Add((lines, last));
        var stamp = clock().ToUnixTimeMilliseconds();
        for (var index = 0; index < chunks.Count; index++)
        {
            var batch = new Batch { Id = NewId(), Install = state.Install, App = app, Platform = platform, UpTo = chunks[index].UpTo, Lines = chunks[index].Lines };
            // Yazılamadıysa (disk dolu): yazılan parçalar kalır, gerisi bekleyenlerde sürer.
            if (!WriteBatch(batch, Path.Combine(OutboxDir, $"{stamp:D15}-{index:D4}-{batch.Id}.json"))) break;
            state.FrozenThrough = batch.UpTo;
        }
        WriteState();
        CompactPendingLocked();
    }

    private void CompactPendingLocked()
    {
        var scan = ScanPending(PendingFile, state.FrozenThrough);
        var builder = new StringBuilder();
        foreach (var s in scan.List) builder.Append(JsonSerializer.Serialize(s, Json)).Append('\n');
        var bytes = Encoding.UTF8.GetBytes(builder.ToString());
        if (WriteAtomic(PendingFile, bytes)) pendingBytes = bytes.Length;
        pendingCount = scan.List.Count;
        oldestPending = scan.Oldest;
    }

    // --- Gönderim ---

    private async Task SendOutboxAsync(Uri target)
    {
        var tried = new HashSet<string>();
        while (true)
        {
            string? file;
            Batch? batch;
            lock (gate)
            {
                if (!enabled || disposed) return;
                file = BatchFiles(OutboxDir).FirstOrDefault(f => !tried.Contains(Path.GetFileName(f)));
                if (file is null) return;
                tried.Add(Path.GetFileName(file));
                batch = ReadBatch(file);
                if (batch is null) { Park(file); continue; }
            }

            HttpResponseMessage response;
            string body;
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(target, "v1/batches"))
                {
                    Content = new StringContent(JsonSerializer.Serialize(batch, Json), Encoding.UTF8, "application/json"),
                };
                request.Headers.UserAgent.ParseAdd($"nino-pool/1 ({platform}; {app})");
                response = await http.SendAsync(request).ConfigureAwait(false);
                body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
            }
            catch (Exception e) when (e is HttpRequestException or TaskCanceledException or IOException or ObjectDisposedException)
            {
                lock (gate) Failed();
                return;
            }

            using (response)
            lock (gate)
            {
                var status = (int)response.StatusCode;
                switch (status)
                {
                    case >= 200 and < 300:
                        Reply? reply = null;
                        try { reply = JsonSerializer.Deserialize<Reply>(body, Json); } catch (JsonException) { }
                        if (reply is not { Ok: true } || !string.Equals(reply.Batch, batch.Id, StringComparison.OrdinalIgnoreCase))
                        {
                            // "Tamam" dese de bizim sunucumuz değilse (yanlış adres) parça silinmez.
                            Failed();
                            return;
                        }
                        RecordRejected(reply.Rejected ?? [], batch);
                        TryDelete(file);
                        state.Failures = 0;
                        state.NextAttempt = 0;
                        WriteState();
                        break;
                    case 413:
                        if (batch.Lines.Count > 1) Split(file, batch); else Park(file);
                        break;
                    case 429 or 503:
                        state.ServerRetryAt = Now() + RetryDelay(response).TotalSeconds;
                        WriteState();
                        return;
                    case 400 or 422:
                        Park(file);
                        break;
                    default:
                        // Adres yanlış (404), yetki (401/403) ya da sunucu hatası: parça kalır, sonra yeniden denenir.
                        Failed();
                        return;
                }
            }
        }
    }

    private void Failed()
    {
        state.Failures++;
        var exponent = Math.Min(state.Failures - 1, 16);
        var delay = Math.Min(limits.BackoffBase.TotalSeconds * Math.Pow(2, exponent), limits.BackoffMax.TotalSeconds);
        double jitter;
        lock (Jitter) jitter = delay * (Jitter.NextDouble() * 0.4 - 0.2);
        state.NextAttempt = Now() + delay + jitter;
        WriteState();
    }

    private void Split(string file, Batch batch)
    {
        var half = batch.Lines.Count / 2;
        var name = Path.GetFileNameWithoutExtension(file);
        var prefix = name[..Math.Min(20, name.Length)];
        var parts = new[] { batch.Lines.GetRange(0, half), batch.Lines.GetRange(half, batch.Lines.Count - half) };
        for (var i = 0; i < parts.Length; i++)
        {
            var piece = new Batch { Id = NewId(), Install = batch.Install, App = batch.App, Platform = batch.Platform, UpTo = batch.UpTo, Lines = parts[i] };
            if (!WriteBatch(piece, Path.Combine(OutboxDir, $"{prefix}-{i}-{piece.Id}.json"))) return;
        }
        TryDelete(file);
    }

    private void Park(string file)
    {
        var target = Path.Combine(ParkedDir, Path.GetFileName(file));
        TryDelete(target);
        TryMove(file, target);
    }

    private void RecordRejected(List<Rejected> rejected, Batch batch)
    {
        if (rejected.Count == 0) return;
        try
        {
            if (File.Exists(RejectedFile) && new FileInfo(RejectedFile).Length >= limits.MaxRejectedBytes) return;
            var builder = new StringBuilder();
            foreach (var item in rejected.Where(r => r.I >= 0 && r.I < batch.Lines.Count))
                builder.Append(JsonSerializer.Serialize(new Dictionary<string, string> { ["reason"] = item.Reason, ["text"] = batch.Lines[item.I].Text }, Json)).Append('\n');
            File.AppendAllText(RejectedFile, builder.ToString(), Encoding.UTF8);
        }
        catch (IOException) { }
    }

    private static TimeSpan RetryDelay(HttpResponseMessage response)
    {
        var header = response.Headers.RetryAfter;
        TimeSpan delay = TimeSpan.FromMinutes(1);
        if (header?.Delta is { } delta) delay = delta;
        else if (header?.Date is { } date) delay = date - DateTimeOffset.UtcNow;
        return TimeSpan.FromSeconds(Math.Clamp(delay.TotalSeconds, 1, 86400));
    }

    // --- Eski CouchSubs kuyruğu ---

    private sealed class LegacyState
    {
        [JsonPropertyName("queue")] public List<LegacyLine>? Queue { get; set; }
    }

    private sealed class LegacyLine
    {
        [JsonPropertyName("text")] public string? Text { get; set; }
        [JsonPropertyName("firstSeen")] public string? FirstSeen { get; set; }
    }

    /// <summary>CouchSubs'tan kalan pool.json kuyruğundaki satırlar bir kez bekleyenlere eklenir, dosya kenara konur.</summary>
    internal static void ImportLegacy(string file, string pending, long firstSeq, int maxLength, double now)
    {
        if (!File.Exists(file)) return;
        try
        {
            LegacyState? legacy = null;
            try { legacy = JsonSerializer.Deserialize<LegacyState>(File.ReadAllText(file), Json); } catch (JsonException) { }
            if (legacy?.Queue is { } queue)
            {
                var builder = new StringBuilder();
                var seq = firstSeq;
                foreach (var line in queue)
                {
                    var text = Clean(line.Text ?? "");
                    if (!Accepts(text, maxLength)) continue;
                    var at = DateTimeOffset.TryParse(line.FirstSeen, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var seen)
                        ? seen.ToUnixTimeSeconds() : now;
                    builder.Append(JsonSerializer.Serialize(new Sighting(seq++, text, null, null, at), Json)).Append('\n');
                }
                File.AppendAllText(pending, builder.ToString(), new UTF8Encoding(false));
            }
            var moved = file + ".imported";
            TryDelete(moved);
            File.Move(file, moved);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    // --- Dosyalar ---

    private static string NewId() => Guid.NewGuid().ToString("D");

    private double Now() => clock().ToUnixTimeMilliseconds() / 1000.0;

    internal static List<string> BatchFiles(string dir)
    {
        try { return Directory.GetFiles(dir, "*.json").OrderBy(Path.GetFileName, StringComparer.Ordinal).ToList(); }
        catch (IOException) { return []; }
        catch (UnauthorizedAccessException) { return []; }
    }

    internal static Batch? ReadBatch(string file)
    {
        try { return JsonSerializer.Deserialize<Batch>(File.ReadAllText(file), Json); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return null; }
    }

    private static bool WriteBatch(Batch batch, string path) => WriteAtomic(path, JsonSerializer.SerializeToUtf8Bytes(batch, Json));

    private static bool WriteAtomic(string path, byte[] data)
    {
        var temp = path + ".tmp";
        try
        {
            using (var stream = new FileStream(temp, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                stream.Write(data);
                stream.Flush(true);
            }
            File.Move(temp, path, overwrite: true);
            return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            TryDelete(temp);
            return false;
        }
    }

    private State LoadState()
    {
        try
        {
            if (File.Exists(StateFile))
            {
                if (JsonSerializer.Deserialize<State>(File.ReadAllText(StateFile), Json) is { } saved && saved.Install.Length > 0) return saved;
            }
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { }
        // Okunamayan durum dosyası silinmez, kenara alınır; satırlar ayrı dosyalarda olduğundan kaybolmaz.
        if (File.Exists(StateFile)) TryMove(StateFile, Path.Combine(directory, $"state.broken-{clock().ToUnixTimeSeconds()}.json"));
        return new State();
    }

    private void WriteState() => WriteAtomic(StateFile, JsonSerializer.SerializeToUtf8Bytes(state, Json));

    private void RemoveQueued()
    {
        TryDelete(PendingFile);
        TryDelete(RejectedFile);
        foreach (var dir in new[] { OutboxDir, ParkedDir })
            foreach (var file in Directory.Exists(dir) ? Directory.GetFiles(dir) : []) TryDelete(file);
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static void TryMove(string from, string to)
    {
        try { File.Move(from, to, overwrite: true); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
