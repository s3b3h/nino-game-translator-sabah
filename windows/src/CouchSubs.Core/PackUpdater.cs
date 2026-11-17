// SPDX-License-Identifier: AGPL-3.0-only

using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace CouchSubs.Core;

/// <summary>Paket sunucusundaki (server/packs: <c>GET /v1/packs</c> = R2'deki index.json) bir paket.</summary>
public sealed record RemotePack(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("version")] long Version,
    [property: JsonPropertyName("sha256")] string Sha256,
    [property: JsonPropertyName("size")] long? Size = null,
    [property: JsonPropertyName("entries")] int? Entries = null);

/// <summary>
/// Sunucudaki yeni ve güncellenen oyun paketleri (ücretsiz, hesapsız): Android'deki PackStore'un Windows karşılığı.
/// Liste alınır, değişen paket indirilir, SHA-256 ile doğrulanır ve paket klasörüne (<see cref="GamePackLibrary.UserDirectory"/>)
/// konur; uygulamayla gelen aynı kimlikli paketin yerine geçer. Açılışta, günde bir ve PS5'te yeni oyun başlayınca bakılır; sürümü değişmeyen paket yeniden inmez,
/// sunucudan kalkan paket silinir. Yarım ya da bozuk dosya hiç yüklenmez (önce geçici dosya, doğrulanınca yerine).
/// Klasöre kullanıcının kendi bıraktığı (sunucudan inmemiş ya da sonradan değiştirilmiş) dosyanın üstüne yazılmaz, o dosya
/// silinmez. Sunucu adresi yapılandırmadan gelir (<see cref="ConfiguredBaseUrl"/>); adres yoksa özellik kapalıdır.
/// Mac'teki CouchSubsCore/PackUpdater.swift ile aynı kurallar.
/// </summary>
public sealed partial class PackUpdater : IDisposable
{
    /// <summary>Açılışta ve günde bir bakılır (havuzdan her gece üretilen <c>pool-*</c> paketleri en geç bir gün sonra gelir).</summary>
    public static readonly TimeSpan RefreshInterval = TimeSpan.FromDays(1);
    /// <summary>PS5'te yeni bir oyun tanınınca son bakış bundan eskiyse hemen bakılır.</summary>
    public static readonly TimeSpan GameCheckInterval = TimeSpan.FromMinutes(10);
    internal const int MaxPackBytes = 64 * 1024 * 1024;

    [GeneratedRegex("^[a-z0-9][a-z0-9-]{0,63}$")]
    private static partial Regex PackId();

    [GeneratedRegex("^[0-9a-fA-F]{64}$")]
    private static partial Regex Hex64();

    /// <param name="Version">-1: son yenilemede inemedi (eski sürümü duruyor), sonraki açılışta yeniden denenir.</param>
    public sealed record Installed(
        [property: JsonPropertyName("id")] string Id,
        [property: JsonPropertyName("title")] string Title,
        [property: JsonPropertyName("version")] long Version,
        [property: JsonPropertyName("sha256")] string Sha256);

    /// <summary>Yenilemenin sonucu; <c>Skipped</c>: süresi gelmedi, <c>Failed</c>: liste alınamadı (elde olanlar kaldı).</summary>
    public sealed record Refresh(IReadOnlyList<string> Downloaded, IReadOnlyList<string> Removed, bool Skipped = false, bool Failed = false)
    {
        public bool Changed => Downloaded.Count > 0 || Removed.Count > 0;
    }

    private sealed class State
    {
        [JsonPropertyName("checked")] public double Checked { get; set; }
        [JsonPropertyName("packs")] public List<Installed> Packs { get; set; } = [];
    }

    private sealed record Listing([property: JsonPropertyName("packs")] List<RemotePack>? Packs);

    private readonly Uri baseUrl;
    private readonly string directory;
    private readonly string stateFile;
    private readonly HttpClient http;
    private readonly Func<DateTimeOffset> clock;
    private readonly SemaphoreSlim running = new(1, 1);

    /// <param name="directory">Paketlerin konacağı klasör (uygulamada <see cref="GamePackLibrary.UserDirectory"/>).</param>
    /// <param name="stateFile">Durum dosyası; paket klasörünün dışında durur ki paket gibi okunmasın.</param>
    /// <param name="handler">HTTP katmanı; testlerde sahtesi verilir.</param>
    public PackUpdater(Uri baseUrl, string directory, string stateFile, HttpMessageHandler? handler = null, Func<DateTimeOffset>? clock = null)
    {
        this.baseUrl = new Uri(baseUrl.AbsoluteUri.TrimEnd('/') + "/");
        this.directory = directory;
        this.stateFile = stateFile;
        http = handler is null ? new HttpClient() : new HttpClient(handler);
        http.Timeout = TimeSpan.FromSeconds(60);
        this.clock = clock ?? (() => DateTimeOffset.UtcNow);
    }

    /// <summary>
    /// Sunucu adresi: <c>COUCHSUBS_PACKS_URL</c> ortam değişkeni ya da derlemedeki <c>CouchSubsPacksUrl</c> bilgisi
    /// (App projesinde MSBuild özelliği <c>CouchSubsPacksUrl</c>). Hiçbiri yoksa (bugünkü durum) null: paket indirme kapalı.
    /// </summary>
    public static Uri? ConfiguredBaseUrl(string? environment = null, Assembly? assembly = null)
    {
        var fromBuild = (assembly ?? Assembly.GetEntryAssembly())?.GetCustomAttributes<AssemblyMetadataAttribute>()
            .FirstOrDefault(a => a.Key == "CouchSubsPacksUrl")?.Value;
        foreach (var candidate in new[] { environment ?? Environment.GetEnvironmentVariable("COUCHSUBS_PACKS_URL"), fromBuild })
        {
            var value = candidate?.Trim();
            if (string.IsNullOrEmpty(value) || !Uri.TryCreate(value, UriKind.Absolute, out var url)) continue;
            if (url.Scheme is "https" or "http" && url.Host.Length > 0) return url;
        }
        return null;
    }

    public IReadOnlyList<Installed> InstalledPacks => Load().Packs;

    /// <summary>
    /// Son bakış <paramref name="maxAge"/>'den (yoksa <see cref="RefreshInterval"/>) eskiyse ya da <paramref name="force"/> ise sunucuya bakar ve değişen paketleri indirir. Liste alınamazsa elde
    /// olanlar kalır; inemeyen paket sonraki açılışta yeniden denenir.
    /// </summary>
    public async Task<Refresh> RefreshAsync(bool force = false, CancellationToken cancellationToken = default, TimeSpan? maxAge = null)
    {
        await running.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var state = Load();
            var now = clock();
            var nowSeconds = now.ToUnixTimeMilliseconds() / 1000.0;
            if (!force && state.Checked > 0 && nowSeconds - state.Checked < (maxAge ?? RefreshInterval).TotalSeconds && state.Packs.All(p => p.Version != -1))
                return new Refresh([], [], Skipped: true);
            var remote = await ListAsync(cancellationToken).ConfigureAwait(false);
            if (remote is null) return new Refresh([], [], Failed: true);
            Directory.CreateDirectory(directory);

            var kept = new List<Installed>();
            var downloaded = new List<string>();
            var retry = false;
            foreach (var pack in remote)
            {
                if (!PackId().IsMatch(pack.Id) || !Hex64().IsMatch(pack.Sha256)) continue;
                var wanted = pack.Sha256.ToLowerInvariant();
                var existing = state.Packs.FirstOrDefault(p => p.Id == pack.Id);
                var file = PackFile(pack.Id);
                var onDisk = Sha256OfFile(file);
                if (existing is not null && existing.Version == pack.Version && existing.Sha256 == wanted && onDisk == wanted)
                {
                    kept.Add(existing);
                    continue;
                }
                // Bizim indirmediğimiz (ya da indirdikten sonra değiştirilmiş) dosyaya dokunulmaz.
                if (onDisk is not null && onDisk != existing?.Sha256 && onDisk != wanted) continue;
                var data = await GetAsync($"v1/packs/{pack.Id}", cancellationToken).ConfigureAwait(false);
                if (data is null || data.Length > MaxPackBytes || Sha256(data) != wanted)
                {
                    retry = true;
                    if (existing is not null && onDisk is not null) kept.Add(existing with { Version = -1 });
                    continue;
                }
                var temporary = Path.Combine(directory, $".{pack.Id}.download");
                try
                {
                    await File.WriteAllBytesAsync(temporary, data, cancellationToken).ConfigureAwait(false);
                    File.Move(temporary, file, overwrite: true);
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    try { File.Delete(temporary); } catch (IOException) { }
                    if (existing is not null && onDisk is not null) kept.Add(existing with { Version = -1 });
                    continue;
                }
                kept.Add(new Installed(pack.Id, pack.Title, pack.Version, wanted));
                downloaded.Add(pack.Id);
            }

            // Sunucudan kalkan paket silinir (yalnız bizim indirdiğimiz ve değişmemişse).
            var remoteIds = remote.Select(p => p.Id).ToHashSet();
            var removed = new List<string>();
            foreach (var old in state.Packs.Where(p => !remoteIds.Contains(p.Id)))
            {
                var file = PackFile(old.Id);
                if (Sha256OfFile(file) == old.Sha256) TryDelete(file);
                removed.Add(old.Id);
            }
            // Yeni bir paket inemediyse kontrol zamanı ilerletilmez: sonraki açılışta yeniden denenir.
            Save(new State { Checked = retry ? state.Checked : nowSeconds, Packs = kept });
            return new Refresh(downloaded, removed);
        }
        finally
        {
            running.Release();
        }
    }

    /// <summary>Ayarlardan "indirilen paketleri sil": yalnız sunucudan inmiş ve değişmemiş dosyalar.</summary>
    public void Clear()
    {
        foreach (var pack in Load().Packs)
        {
            var file = PackFile(pack.Id);
            if (Sha256OfFile(file) == pack.Sha256) TryDelete(file);
        }
        TryDelete(stateFile);
    }

    private async Task<List<RemotePack>?> ListAsync(CancellationToken cancellationToken)
    {
        var data = await GetAsync("v1/packs", cancellationToken).ConfigureAwait(false);
        if (data is null) return null;
        // Eksik/null liste başarısız yanıttır, boş liste değildir: aksi hâlde indirilmiş paketler silinir.
        try { return JsonSerializer.Deserialize<Listing>(data)?.Packs; }
        catch (JsonException) { return null; }
    }

    private async Task<byte[]?> GetAsync(string path, CancellationToken cancellationToken)
    {
        try
        {
            using var response = await http.GetAsync(new Uri(baseUrl, path), cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode) return null;
            return await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException)
        {
            return null;
        }
    }

    private string PackFile(string id) => Path.Combine(directory, $"{id}.json.gz");

    private State Load()
    {
        try { return JsonSerializer.Deserialize<State>(File.ReadAllText(stateFile)) ?? new State(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { return new State(); }
    }

    private void Save(State state)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(stateFile)!);
            var temporary = stateFile + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(state));
            File.Move(temporary, stateFile, overwrite: true);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static void TryDelete(string file)
    {
        try { File.Delete(file); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    internal static bool IsValidId(string id) => PackId().IsMatch(id);

    internal static string Sha256(byte[] data) => Convert.ToHexStringLower(SHA256.HashData(data));

    private static string? Sha256OfFile(string file)
    {
        try { return File.Exists(file) ? Sha256(File.ReadAllBytes(file)) : null; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return null; }
    }

    public void Dispose()
    {
        http.Dispose();
        running.Dispose();
    }
}
