// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CouchSubs.Core;

/// <summary>
/// Bellekteki havuz çevirileri (anahtar → çeviri). Altyazı hattı eşzamanlı sorduğu için kilitli; diske dil başına yazılır.
/// Mac'teki CouchSubsCore/NinoPool/TranslationPool.swift (PoolTranslations) ile aynı.
/// </summary>
public sealed class PoolTranslations
{
    private readonly object gate = new();
    private Dictionary<string, string> texts = [];
    private string language = "";

    /// <summary>Satırın havuzdaki çevirisi (yoksa null). Anahtar oyun paketleriyle ve sunucuyla aynı (<see cref="PackKey"/>).</summary>
    public string? Match(string source)
    {
        if (PackKey.Key(source) is not { } key) return null;
        lock (gate) return texts.TryGetValue(key, out var text) ? text : null;
    }

    public int Count
    {
        get { lock (gate) return texts.Count; }
    }

    internal void Replace(string language, Dictionary<string, string> texts)
    {
        lock (gate)
        {
            this.language = language;
            this.texts = texts;
        }
    }

    /// <summary>Yalnız aynı dilin çevirileri eklenir (dil değişirken gelen eski cevap karışmasın).</summary>
    internal void Merge(string language, IReadOnlyDictionary<string, string> items)
    {
        lock (gate)
        {
            if (language != this.language) return;
            foreach (var (key, value) in items) texts[key] = value;
        }
    }

    internal (string Language, Dictionary<string, string> Texts) Snapshot()
    {
        lock (gate) return (language, new Dictionary<string, string>(texts));
    }
}

/// <summary>
/// Nino çeviri havuzu (sunucu: nino-pool/src/translate.js). Oyun satırlarının sunucuda Claude ile yapılmış çevirileri:
/// <list type="bullet">
/// <item>oyun başlarken o oyunun bütün çevirileri tek seferde, sonra birkaç dakikada bir yalnız değişenler iner;</item>
/// <item>pakette ve havuzda olmayan satır sunucuya sorulur; sunucu o an çevirir, herkes için saklar.</item>
/// </list>
/// Havuzdaki çeviri, hazır paketten sonra ve cihazın kendi çevirisinden önce kullanılır (11 dilin hepsinde). Ayarlar'daki
/// ortak havuz kapalıysa hiçbir şey gönderilmez ve indirilmez. Mac'teki TranslationPool.swift ile birebir aynı davranış.
/// </summary>
public sealed class TranslationPool : IDisposable
{
    /// <summary>Sunucudan gelen ayar (<c>GET /v1/config</c>); sunucuya ulaşılamazsa bu varsayılanlar.</summary>
    public sealed record Config
    {
        [JsonPropertyName("enabled")] public bool Enabled { get; init; } = true;
        [JsonPropertyName("deadlineMs")] public int DeadlineMs { get; init; } = 900;
        [JsonPropertyName("syncSeconds")] public int SyncSeconds { get; init; } = 180;
        [JsonPropertyName("contextLines")] public int ContextLines { get; init; } = 4;
        [JsonPropertyName("maxLines")] public int MaxLines { get; init; } = 12;
    }

    internal sealed class Cursor
    {
        [JsonPropertyName("since")] public long Since { get; set; }
        [JsonPropertyName("after")] public string After { get; set; } = "";
        [JsonPropertyName("checked")] public double Checked { get; set; }
    }

    internal sealed class Saved
    {
        [JsonPropertyName("language")] public string Language { get; set; } = "";
        [JsonPropertyName("texts")] public Dictionary<string, string> Texts { get; set; } = [];
        [JsonPropertyName("cursors")] public Dictionary<string, Cursor> Cursors { get; set; } = [];
    }

    private sealed class ConfigReply
    {
        [JsonPropertyName("translate")] public Config? Translate { get; set; }
    }

    private sealed class TranslateReply
    {
        [JsonPropertyName("translations")] public List<Line>? Translations { get; set; }

        public sealed class Line
        {
            [JsonPropertyName("text")] public string? Text { get; set; }
        }
    }

    /// <summary>Sunucudan en çok bu kadar çeviri tutulur (dil başına); fazlası diske yazılmaz.</summary>
    internal const int MaxStored = 400_000;

    private static readonly JsonSerializerOptions Json = new()
    {
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    /// <summary>Altyazı hattının eşzamanlı baktığı çeviriler.</summary>
    public PoolTranslations Store { get; } = new();

    private readonly object gate = new();
    private readonly string directory;
    private readonly string install;
    private readonly string app;
    private readonly string platform;
    private readonly HttpClient http;
    private readonly Func<DateTimeOffset> clock;
    private Uri? endpoint;
    private Config config = new();
    private bool enabled;
    private string language;
    private Dictionary<string, Cursor> cursors = [];
    private double configChecked;
    private double pinged = double.NegativeInfinity;
    private readonly Dictionary<string, Task<string?>> inFlight = [];
    private bool dirty;

    /// <param name="directory">Çevirilerin klasörü (%LOCALAPPDATA%\CouchSubs\pool-translations).</param>
    /// <param name="endpoint">Sunucu (<see cref="NinoPool.ConfiguredEndpoint"/>); null ise hiçbir şey sorulmaz.</param>
    /// <param name="install">Kuruluma özgü rastgele kimlik (sunucuda yalnız tuzlanmış özetiyle, kaba hız sınırı için);
    /// verilmezse klasördeki <c>install</c> dosyasından okunur ya da üretilir.</param>
    /// <param name="handler">HTTP katmanı; testlerde sahtesi verilir.</param>
    public TranslationPool(string directory, Uri? endpoint, string app, string platform, string language, bool enabled = true,
        string? install = null, HttpMessageHandler? handler = null, Func<DateTimeOffset>? clock = null)
    {
        this.directory = directory;
        this.endpoint = endpoint;
        try { Directory.CreateDirectory(directory); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        this.install = install ?? InstallId(directory);
        this.app = app;
        this.platform = platform;
        this.clock = clock ?? (() => DateTimeOffset.UtcNow);
        http = handler is null ? new HttpClient() : new HttpClient(handler, disposeHandler: false);
        // Süre her istekte ayrı verilir (çeviri 20 sn, indirme 30 sn).
        http.Timeout = Timeout.InfiniteTimeSpan;
        this.language = Code(language);
        this.enabled = enabled;
        var saved = Load(directory, this.language);
        cursors = saved?.Cursors ?? [];
        Store.Replace(this.language, enabled ? saved?.Texts ?? [] : []);
    }

    public Config CurrentConfig
    {
        get { lock (gate) return config; }
    }

    public bool IsEnabled
    {
        get { lock (gate) return enabled; }
    }

    public string InstallIdentifier => install;

    /// <summary>Havuz şu an kullanılabilir mi (ayar açık, sunucu açık, adres var).</summary>
    public bool IsActive
    {
        get { lock (gate) return enabled && config.Enabled && endpoint is not null; }
    }

    private double Now() => clock().ToUnixTimeMilliseconds() / 1000.0;

    private static string InstallId(string directory)
    {
        var file = Path.Combine(directory, "install");
        try
        {
            if (File.Exists(file) && Guid.TryParse(File.ReadAllText(file).Trim(), out var saved)) return saved.ToString("D");
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        var made = Guid.NewGuid().ToString("D");
        try { File.WriteAllText(file, made); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        return made;
    }

    /// <summary>"pt-BR" → "pt": sunucunun beklediği kısa dil kodu.</summary>
    internal static string Code(string language) =>
        language.ToLowerInvariant().Split(['-', '_'], StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";

    private static string FileFor(string directory, string language) => Path.Combine(directory, $"translations-{language}.json");

    private static Saved? Load(string directory, string language)
    {
        try
        {
            var file = FileFor(directory, language);
            return File.Exists(file) ? JsonSerializer.Deserialize<Saved>(File.ReadAllText(file), Json) : null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return null; }
    }

    // --- Ayar ---

    /// <summary>Hedef dil değişince o dilin çevirileri yüklenir.</summary>
    public void SetLanguage(string value)
    {
        var code = Code(value);
        lock (gate)
        {
            if (code == language) return;
            SaveLocked();
            language = code;
            var saved = Load(directory, code);
            cursors = saved?.Cursors ?? [];
            Store.Replace(code, enabled ? saved?.Texts ?? [] : []);
        }
    }

    /// <summary>Kullanıcı ortak havuzu kapatınca hiçbir şey sorulmaz ve indirilen çeviriler kullanılmaz.</summary>
    public void SetEnabled(bool value)
    {
        lock (gate)
        {
            if (value == enabled) return;
            enabled = value;
            var saved = value ? Load(directory, language) : null;
            Store.Replace(language, saved?.Texts ?? []);
        }
    }

    public void SetEndpoint(Uri? url)
    {
        lock (gate) endpoint = url;
    }

    /// <summary>Sunucunun ayarını en çok 10 dakikada bir sorar.</summary>
    public async Task RefreshConfigAsync(bool force = false, CancellationToken token = default)
    {
        Uri target;
        lock (gate)
        {
            if (endpoint is null) return;
            var now = Now();
            if (!force && now - configChecked <= 600) return;
            configChecked = now;
            target = endpoint;
        }
        if (await GetAsync(new Uri(target, "v1/config"), token).ConfigureAwait(false) is not { } body) return;
        Config? translate;
        try { translate = JsonSerializer.Deserialize<ConfigReply>(body, Json)?.Translate; }
        catch (JsonException) { return; }
        if (translate is null) return;
        lock (gate) config = translate;
    }

    // --- Toplu indirme ---

    /// <summary>
    /// Oyunun yeni çevirilerini indirir (oyun başlarken hemen, sonra <see cref="Config.SyncSeconds"/> aralıkla).
    /// <paramref name="rawGame"/> yoksa bütün oyunlar. Kaç çeviri geldiğini döner.
    /// </summary>
    public async Task<int> SyncAsync(string? rawGame, bool force = false, CancellationToken token = default)
    {
        await RefreshConfigAsync(token: token).ConfigureAwait(false);
        var game = NinoPool.GameId(rawGame) ?? "";
        Uri target;
        string lang;
        Cursor cursor;
        lock (gate)
        {
            if (!(enabled && config.Enabled && endpoint is not null)) return 0;
            target = endpoint;
            lang = language;
            var known = cursors.TryGetValue(game, out var saved) ? saved : new Cursor();
            cursor = new Cursor { Since = known.Since, After = known.After, Checked = known.Checked };
            var now = Now();
            if (!force && now - cursor.Checked < Math.Max(30, config.SyncSeconds)) return 0;
            cursor.Checked = now;
            cursors[game] = cursor;
        }
        var added = 0;
        for (var page = 0; page < 50; page++)
        {
            var query = new StringBuilder($"v1/translations?lang={Uri.EscapeDataString(lang)}&since={cursor.Since.ToString(CultureInfo.InvariantCulture)}");
            if (game.Length > 0) query.Append("&game=").Append(Uri.EscapeDataString(game));
            if (cursor.After.Length > 0) query.Append("&after=").Append(Uri.EscapeDataString(cursor.After));
            if (await GetAsync(new Uri(target, query.ToString()), token).ConfigureAwait(false) is not { } body) break;
            JsonDocument document;
            try { document = JsonDocument.Parse(body); }
            catch (JsonException) { break; }
            using (document)
            {
                var root = document.RootElement;
                lock (gate)
                    if (lang != language) break;
                if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("items", out var rows) || rows.ValueKind != JsonValueKind.Array) break;
                var items = new Dictionary<string, string>();
                var newest = cursor.Since;
                foreach (var row in rows.EnumerateArray())
                {
                    // [anahtar, çeviri, zaman, aşama]
                    if (row.ValueKind != JsonValueKind.Array || row.GetArrayLength() < 3) continue;
                    if (row[0].ValueKind != JsonValueKind.String || row[1].ValueKind != JsonValueKind.String
                        || row[2].ValueKind != JsonValueKind.Number || !row[2].TryGetInt64(out var updated)) continue;
                    items[row[0].GetString()!] = row[1].GetString()!;
                    newest = Math.Max(newest, updated);
                }
                Store.Merge(lang, items);
                added += items.Count;
                if (items.Count > 0) lock (gate) dirty = true;
                if (root.TryGetProperty("next", out var next) && next.ValueKind == JsonValueKind.Object
                    && next.TryGetProperty("since", out var since) && since.TryGetInt64(out var sinceValue))
                {
                    cursor.Since = sinceValue;
                    cursor.After = next.TryGetProperty("after", out var after) && after.ValueKind == JsonValueKind.String ? after.GetString() ?? "" : "";
                }
                else
                {
                    cursor.Since = newest;
                    cursor.After = "";
                    break;
                }
            }
        }
        lock (gate)
        {
            // Bu arada dil değiştiyse imleç yeni dilin imleçlerine yazılmaz.
            if (lang == language) cursors[game] = cursor;
            if (dirty) SaveLocked();
        }
        return added;
    }

    // --- Buradayım ---

    /// <summary>
    /// Çeviri sürerken sunucuya "buradayım" der (<c>GET /v1/ping</c>), en çok dakikada bir. Cevap önemsizdir, hata sessizce
    /// yutulur. Ortak havuz kapalıysa gönderilmez.
    /// </summary>
    public async Task PingAsync(string? rawGame, CancellationToken token = default)
    {
        Uri target;
        string lang;
        lock (gate)
        {
            if (!enabled || endpoint is null) return;
            var now = Now();
            if (now - pinged < 55) return;
            pinged = now;
            target = endpoint;
            lang = language;
        }
        var query = $"v1/ping?install={Uri.EscapeDataString(install)}&platform={Uri.EscapeDataString(platform)}"
            + $"&app={Uri.EscapeDataString(app)}&game={Uri.EscapeDataString(NinoPool.GameId(rawGame) ?? "")}&lang={Uri.EscapeDataString(lang)}";
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(target, query));
            request.Headers.UserAgent.ParseAdd(UserAgent);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
            timeout.CancelAfter(TimeSpan.FromSeconds(15));
            using var response = await http.SendAsync(request, timeout.Token).ConfigureAwait(false);
        }
        catch (Exception e) when (e is HttpRequestException or OperationCanceledException or IOException or ObjectDisposedException or InvalidOperationException) { }
    }

    // --- Anında çeviri ---

    /// <summary>
    /// Satırı sunucuya sorar; sunucu biliyorsa ya da o an çevirirse çeviri döner ve havuza eklenir. Aynı satır aynı anda
    /// iki kez sorulmaz. Ulaşılamazsa, sınır dolduysa ya da havuz kapalıysa null.
    /// </summary>
    public async Task<string?> TranslateAsync(string line, IReadOnlyList<string>? context = null, string? rawGame = null)
    {
        await RefreshConfigAsync().ConfigureAwait(false);
        if (!NinoPool.Accepts(NinoPool.Clean(line)) || PackKey.Key(line) is not { } key) return null;
        Task<string?> task;
        string lang;
        lock (gate)
        {
            if (!(enabled && config.Enabled && endpoint is not null)) return null;
            if (Store.Match(line) is { } known) return known;
            lang = language;
            var flightKey = lang + "\u001F" + key;
            if (!inFlight.TryGetValue(flightKey, out var running))
            {
                var keep = Math.Max(0, config.ContextLines);
                var recent = context ?? [];
                var body = new Dictionary<string, object>
                {
                    ["v"] = 1,
                    ["install"] = install,
                    ["app"] = app,
                    ["platform"] = platform,
                    ["lang"] = lang,
                    ["game"] = NinoPool.GameId(rawGame) ?? "",
                    ["lines"] = new[] { line },
                    ["context"] = recent.Skip(Math.Max(0, recent.Count - keep)).ToArray(),
                };
                running = PostAsync(new Uri(endpoint, "v1/translate"), JsonSerializer.Serialize(body, Json));
                inFlight[flightKey] = running;
                _ = running.ContinueWith(_ => { lock (gate) inFlight.Remove(flightKey); }, TaskScheduler.Default);
            }
            task = running;
        }
        var result = await task.ConfigureAwait(false);
        if (!string.IsNullOrEmpty(result))
        {
            Store.Merge(lang, new Dictionary<string, string> { [key] = result });
            lock (gate) dirty = true;
        }
        return result;
    }

    private async Task<string?> PostAsync(Uri url, string json)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, url) { Content = new StringContent(json, Encoding.UTF8, "application/json") };
            request.Headers.UserAgent.ParseAdd(UserAgent);
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
            using var response = await http.SendAsync(request, timeout.Token).ConfigureAwait(false);
            if ((int)response.StatusCode != 200) return null;
            var body = await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
            return JsonSerializer.Deserialize<TranslateReply>(body, Json)?.Translations?.FirstOrDefault()?.Text;
        }
        catch (Exception e) when (e is HttpRequestException or OperationCanceledException or IOException or JsonException
                                      or ObjectDisposedException or InvalidOperationException)
        {
            return null;
        }
    }

    // --- Oyunu ekrandan tanıma ---

    /// <summary>Tanıma isteğine gönderilebilecek en büyük JPEG (sunucu sınırının altında).</summary>
    public const int MaxIdentifyBytes = 450 * 1024;

    private sealed class IdentifyReply
    {
        [JsonPropertyName("game")] public string? Game { get; set; }
    }

    /// <summary>
    /// Nino: Remote Play karesinden oyunu tanır (<c>POST /v1/identify</c>; sunucuda Claude). <paramref name="jpeg"/>:
    /// küçültülmüş kare (≤ 450 KB). Havuz kapalıysa, ulaşılamazsa ya da tanınamazsa null (Mac: identify(jpeg:)).
    /// </summary>
    public async Task<string?> IdentifyAsync(byte[] jpeg, CancellationToken token = default)
    {
        Uri target;
        lock (gate)
        {
            if (!enabled || endpoint is null) return null;
            target = endpoint;
        }
        if (jpeg.Length == 0 || jpeg.Length > MaxIdentifyBytes) return null;
        var body = new Dictionary<string, object>
        {
            ["v"] = 1,
            ["install"] = install,
            ["app"] = app,
            ["platform"] = platform,
            ["image"] = Convert.ToBase64String(jpeg),
        };
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(target, "v1/identify"))
            {
                Content = new StringContent(JsonSerializer.Serialize(body, Json), Encoding.UTF8, "application/json"),
            };
            request.Headers.UserAgent.ParseAdd(UserAgent);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
            timeout.CancelAfter(TimeSpan.FromSeconds(30));
            using var response = await http.SendAsync(request, timeout.Token).ConfigureAwait(false);
            if ((int)response.StatusCode != 200) return null;
            var text = await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
            var game = JsonSerializer.Deserialize<IdentifyReply>(text, Json)?.Game?.Trim();
            return string.IsNullOrEmpty(game) ? null : game;
        }
        catch (Exception e) when (e is HttpRequestException or OperationCanceledException or IOException or JsonException
                                      or ObjectDisposedException or InvalidOperationException)
        {
            return null;
        }
    }

    // --- Disk ---

    /// <summary>Çevirileri diske yazar (indirmeden sonra ve kapanırken).</summary>
    public void Save()
    {
        lock (gate) SaveLocked();
    }

    private void SaveLocked()
    {
        if (!dirty) return;
        dirty = false;
        var snapshot = Store.Snapshot();
        if (snapshot.Language != language) return;
        var texts = snapshot.Texts.Count > MaxStored ? snapshot.Texts.Take(MaxStored).ToDictionary() : snapshot.Texts;
        var saved = new Saved { Language = language, Texts = texts, Cursors = cursors };
        var file = FileFor(directory, language);
        try
        {
            Directory.CreateDirectory(directory);
            var temporary = file + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(saved, Json));
            File.Move(temporary, file, overwrite: true);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    private string UserAgent => $"nino-pool/1 ({platform}; {app})";

    private async Task<string?> GetAsync(Uri url, CancellationToken token)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.UserAgent.ParseAdd(UserAgent);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
            timeout.CancelAfter(TimeSpan.FromSeconds(30));
            using var response = await http.SendAsync(request, timeout.Token).ConfigureAwait(false);
            if ((int)response.StatusCode != 200) return null;
            return await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
        }
        catch (Exception e) when (e is HttpRequestException or OperationCanceledException or IOException
                                      or ObjectDisposedException or InvalidOperationException)
        {
            return null;
        }
    }

    public void Dispose()
    {
        Save();
        http.Dispose();
    }
}

/// <summary>
/// Havuza sorulan satırların bağlamı: son birkaç satır (çok eskiyse atılır). Sunucu kısa satırı ("Do it.") bununla doğru
/// hitap ve anlamla çevirir.
/// </summary>
public sealed class PoolContext(Func<DateTimeOffset>? clock = null)
{
    public static readonly TimeSpan MaxAge = TimeSpan.FromSeconds(30);
    private readonly object gate = new();
    private readonly List<(string Text, DateTimeOffset At)> lines = [];
    private readonly Func<DateTimeOffset> clock = clock ?? (() => DateTimeOffset.UtcNow);

    /// <summary>Satırı ekler; ondan önceki (taze) satırları döner.</summary>
    public IReadOnlyList<string> Add(string text, int keep = 4)
    {
        lock (gate)
        {
            var now = clock();
            lines.RemoveAll(line => now - line.At > MaxAge || line.Text == text);
            var context = lines.Skip(Math.Max(0, lines.Count - keep)).Select(line => line.Text).ToList();
            lines.Add((text, now));
            if (lines.Count > keep) lines.RemoveRange(0, lines.Count - keep);
            return context;
        }
    }
}
