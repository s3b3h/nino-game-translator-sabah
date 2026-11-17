// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace CouchSubs.Core;

/// <summary>
/// Nino: "Sorun Bildir". Kullanıcının açıklaması, isteğe bağlı iletişim bilgisi, (açıksa) uygulama günlüğünün sonu ve en
/// çok 3 fotoğraf havuz sunucusuna (<c>POST /v1/reports</c>, nino-pool/src/reports.js) tek bir JSON olarak gider.
/// Bu sınıf arayüzsüzdür: isteği kurar, günlükteki anahtar ve belirteçleri siler, fotoğrafı sığdırma döngüsünü yürütür ve
/// gönderir. Fotoğrafın kendisini küçültüp JPEG yapan kodlayıcı uygulamadadır (WPF), buraya bir işlev olarak verilir.
/// </summary>
public static class ProblemReport
{
    public const int MaxText = 4000;
    public const int MaxContact = 200;
    public const int MaxLog = 60000;
    public const int MaxImages = 3;
    /// <summary>Sunucunun fotoğraf başına sınırı (çözülmüş bayt).</summary>
    public const int ServerMaxImageBytes = 1500 * 1024;
    /// <summary>
    /// Bizim hedefimiz daha düşük: gövde en çok 4 MB ve base64 boyutu üçte bir büyütür. 3 × 900 KB ≈ 3,6 MB base64, günlük
    /// ve metinle birlikte 4 MB'ın altında kalır.
    /// </summary>
    public const int TargetImageBytes = 900 * 1024;
    public const long MaxBodyBytes = 4L * 1024 * 1024;
    public const int MaxSide = 1600;
    public const string Platform = "windows";

    public sealed class Image
    {
        [JsonPropertyName("mime")] public string Mime { get; set; } = "image/jpeg";
        [JsonPropertyName("data")] public string Data { get; set; } = "";
    }

    public sealed class Payload
    {
        [JsonPropertyName("v")] public int V { get; set; } = 1;
        [JsonPropertyName("install")] public string Install { get; set; } = "";
        [JsonPropertyName("app")] public string App { get; set; } = "";
        [JsonPropertyName("platform")] public string Platform { get; set; } = ProblemReport.Platform;
        [JsonPropertyName("language")] public string Language { get; set; } = "";
        [JsonPropertyName("text")] public string Text { get; set; } = "";
        [JsonPropertyName("contact")] public string? Contact { get; set; }
        [JsonPropertyName("log")] public string? Log { get; set; }
        [JsonPropertyName("images")] public List<Image> Images { get; set; } = [];
    }

    public enum Outcome { Sent, RateLimited, TooLarge, Rejected, Failed }

    public sealed record Result(Outcome Outcome, string? Id = null, TimeSpan? RetryAfter = null);

    // Havuzla aynı: base64'teki '+' ve Türkçe harfler \uXXXX'e dönüşüp gövdeyi şişirmesin.
    private static readonly JsonSerializerOptions Json = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    /// <summary>Bildirimin adresi: havuz adresi (<see cref="NinoPool.ConfiguredEndpoint"/>) + <c>/v1/reports</c>.</summary>
    public static Uri? Endpoint(Uri? poolBase) => poolBase is null ? null : new Uri(poolBase, "/v1/reports");

    /// <summary>
    /// İsteği kurar: metin ve iletişim kırpılır, boş iletişim ve günlük gönderilmez, en çok 3 fotoğraf (JPEG baytları).
    /// </summary>
    public static Payload Build(string install, string app, string language, string text, string? contact, string? log,
                                IEnumerable<byte[]> jpegs)
    {
        var payload = new Payload
        {
            Install = install,
            App = app.Length > 40 ? app[..40] : app,
            Language = language,
            Text = Clip(text.Trim(), MaxText),
            Contact = string.IsNullOrWhiteSpace(contact) ? null : Clip(contact.Trim(), MaxContact),
            Log = string.IsNullOrWhiteSpace(log) ? null : log.Length > MaxLog ? log[^MaxLog..] : log,
        };
        foreach (var jpeg in jpegs.Where(bytes => bytes.Length > 0).Take(MaxImages))
            payload.Images.Add(new Image { Mime = "image/jpeg", Data = Convert.ToBase64String(jpeg) });
        return payload;
    }

    public static string ToJson(Payload payload) => JsonSerializer.Serialize(payload, Json);

    /// <summary>Açıklamada en az bir harf ya da işaret var mı (sunucu boşlukları kırpar; Gönder bu yüzden kapalı kalır).</summary>
    public static bool CanSend(string? text) => !string.IsNullOrWhiteSpace(text);

    private static string Clip(string value, int max) => value.Length > max ? value[..max] : value;

    // --- Kuruluş kimliği ---

    /// <summary>
    /// Havuzun kuruluşa özgü rastgele kimliği varsa o; yoksa bir kez üretilip <paramref name="fallbackFile"/>'a yazılan
    /// rastgele kimlik (sunucu 8–64 karakter ister).
    /// </summary>
    public static string InstallId(string? poolInstall, string fallbackFile)
    {
        if (poolInstall is { Length: >= 8 and <= 64 }) return poolInstall;
        try
        {
            if (File.Exists(fallbackFile) && File.ReadAllText(fallbackFile).Trim() is { Length: >= 8 and <= 64 } saved) return saved;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        var id = Guid.NewGuid().ToString("N");
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(fallbackFile)!);
            File.WriteAllText(fallbackFile, id);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        return id;
    }

    // --- Günlük ---

    private const string Hidden = "[gizlendi]";
    // Authorization: Bearer … / Basic …: sözcük kalır, değeri gizlenir.
    private static readonly Regex BearerToken = new(@"\b(?<scheme>Bearer|Basic)\s+[A-Za-z0-9._~+/=\-]{8,}", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex[] SecretPatterns =
    [
        // Google (AIza…), OpenAI/Anthropic (sk-…, sk-ant-…), GitHub (ghp_…) anahtarları.
        new(@"AIza[0-9A-Za-z_\-]{20,}", RegexOptions.Compiled),
        new(@"\bsk-[A-Za-z0-9_\-]{16,}", RegexOptions.Compiled),
        new(@"\bgh[pousr]_[A-Za-z0-9]{20,}", RegexOptions.Compiled),
        // DeepL anahtarı ve benzeri UUID'ler (":fx" ekiyle ya da eksiz).
        new(@"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(?::fx)?\b", RegexOptions.Compiled),
        // Uzun onaltılık diziler (PSN kayıt anahtarları, belirteçler).
        new(@"\b[0-9a-fA-F]{32,}\b", RegexOptions.Compiled),
    ];
    // key=…, token: …, "api_key":"…", id_token=… gibi atamalar: adı kalır, değeri gizlenir (önünde harf olmamalı: hotkey=F8 kalır).
    private static readonly Regex Assignment = new(
        @"(?<name>(?<![A-Za-z])(?:api[_\-]?key|apikey|key|token|access[_\-]?token|refresh[_\-]?token|secret|client[_\-]?secret|password|passwd|pwd|passcode|pin|auth|authorization|cookie|session[_\-]?key|npsso)""?\s*[=:]\s*""?)(?<value>[^\s""&,;]+)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);
    // Uzun base64 benzeri dizi: en az 40 karakter, içinde rakam ve harf (yol ve tür adları ayrıca '\' ya da '.' taşır).
    private static readonly Regex LongToken = new(@"(?<![A-Za-z0-9+/_\-])[A-Za-z0-9+/_\-]{40,}={0,2}", RegexOptions.Compiled);

    /// <summary>Günlükte API anahtarı ya da belirtece benzeyen her şeyi <c>[gizlendi]</c> ile değiştirir.</summary>
    public static string Scrub(string log)
    {
        var result = BearerToken.Replace(log, match => match.Groups["scheme"].Value + " " + Hidden);
        result = Assignment.Replace(result, match =>
        {
            var value = match.Groups["value"].Value;
            // "Authorization: Bearer [gizlendi]" ya da zaten gizlenmiş değer olduğu gibi kalır.
            return value.StartsWith(Hidden, StringComparison.Ordinal)
                || value.Equals("Bearer", StringComparison.OrdinalIgnoreCase) || value.Equals("Basic", StringComparison.OrdinalIgnoreCase)
                ? match.Value : match.Groups["name"].Value + Hidden;
        });
        foreach (var pattern in SecretPatterns) result = pattern.Replace(result, Hidden);
        result = LongToken.Replace(result, match => match.Value.Any(char.IsDigit) && match.Value.Any(char.IsLetter) ? Hidden : match.Value);
        return result;
    }

    /// <summary>
    /// Verilen günlük dosyalarının sonlarını (her biri kendi payıyla, başlığıyla) birleştirir, gizler ve en çok
    /// <paramref name="max"/> karakter olacak şekilde baştan satır sınırında keser. Hiçbiri yoksa null.
    /// </summary>
    public static string? CollectLogs(IEnumerable<(string Path, int Budget)> files, int max = MaxLog)
    {
        var parts = new List<string>();
        foreach (var (path, budget) in files)
        {
            if (Tail(path, budget) is not { Length: > 0 } tail) continue;
            parts.Add($"— {System.IO.Path.GetFileName(path)} —\n{tail.TrimEnd()}");
        }
        if (parts.Count == 0) return null;
        // Önce gizle, sonra kes: kesimin ortasında kalan bir anahtar uzunluk kalıplarından kaçmasın.
        var all = Scrub(string.Join("\n\n", parts));
        return CutToLastChars(all, max);
    }

    /// <summary>Metnin son <paramref name="max"/> karakteri; kesim bir satırın ortasına düşerse o yarım satır atılır.</summary>
    public static string CutToLastChars(string text, int max)
    {
        if (text.Length <= max) return text;
        var cut = text[^max..];
        var newline = cut.IndexOf('\n');
        return newline >= 0 && newline < cut.Length - 1 ? cut[(newline + 1)..] : cut;
    }

    /// <summary>Dosyanın son ~<paramref name="chars"/> karakteri (yazılırken de okunur); yoksa ya da okunamazsa null.</summary>
    public static string? Tail(string path, int chars)
    {
        try
        {
            if (!File.Exists(path)) return null;
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            // UTF-8'de karakter başına en çok 4 bayt; fazlası okunur, sonra karakterle kesilir.
            var bytes = Math.Min(stream.Length, (long)chars * 4);
            stream.Seek(stream.Length - bytes, SeekOrigin.Begin);
            using var reader = new StreamReader(stream, Encoding.UTF8);
            var text = reader.ReadToEnd();
            if (stream.Length > bytes)
            {
                // Dosyanın ortasından başladık: yarım kalan ilk satır atılır.
                var newline = text.IndexOf('\n');
                if (newline >= 0) text = text[(newline + 1)..];
            }
            return CutToLastChars(text, chars);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return null; }
    }

    // --- Fotoğraf ---

    /// <summary>En uzun kenarı <paramref name="maxSide"/>'ı aşmayacak boyut (oran korunur, büyütülmez).</summary>
    public static (int Width, int Height) FitSize(int width, int height, int maxSide = MaxSide)
    {
        if (width <= 0 || height <= 0) return (Math.Max(1, width), Math.Max(1, height));
        var longest = Math.Max(width, height);
        if (longest <= maxSide) return (width, height);
        var scale = (double)maxSide / longest;
        return (Math.Max(1, (int)Math.Round(width * scale)), Math.Max(1, (int)Math.Round(height * scale)));
    }

    /// <summary>Denenecek (en uzun kenar, JPEG kalitesi) çiftleri: önce kalite düşer, sonra boyut.</summary>
    public static IEnumerable<(int MaxSide, int Quality)> Attempts()
    {
        foreach (var side in new[] { MaxSide, 1280, 1024, 800, 640 })
            foreach (var quality in new[] { 70, 55, 40 })
                yield return (side, quality);
    }

    /// <summary>
    /// Fotoğrafı hedef boyuta sığdırır: <paramref name="encode"/> (en uzun kenar, kalite) → JPEG baytları. Sığan ilk sonuç
    /// döner; hiçbiri sığmazsa null.
    /// </summary>
    public static byte[]? FitJpeg(Func<int, int, byte[]> encode, int maxBytes = TargetImageBytes)
    {
        foreach (var (side, quality) in Attempts())
        {
            var bytes = encode(side, quality);
            if (bytes.Length > 0 && bytes.Length <= maxBytes) return bytes;
        }
        return null;
    }

    // --- Gönderim ---

    /// <summary>Bildirimi gönderir; ağ hatası da <see cref="Outcome.Failed"/> olarak döner (istisna fırlatmaz).</summary>
    public static async Task<Result> SendAsync(HttpClient http, Uri endpoint, Payload payload, CancellationToken cancel = default)
    {
        try
        {
            using var content = new StringContent(ToJson(payload), Encoding.UTF8);
            content.Headers.ContentType = new MediaTypeHeaderValue("application/json") { CharSet = "utf-8" };
            using var response = await http.PostAsync(endpoint, content, cancel).ConfigureAwait(false);
            switch (response.StatusCode)
            {
                case HttpStatusCode.OK:
                    string? id = null;
                    try
                    {
                        using var reply = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancel).ConfigureAwait(false));
                        if (reply.RootElement.TryGetProperty("id", out var value) && value.ValueKind == JsonValueKind.String) id = value.GetString();
                    }
                    catch (JsonException) { }
                    return new Result(Outcome.Sent, id);
                case HttpStatusCode.TooManyRequests:
                    return new Result(Outcome.RateLimited, RetryAfter: response.Headers.RetryAfter?.Delta);
                case HttpStatusCode.RequestEntityTooLarge:
                    return new Result(Outcome.TooLarge);
                case HttpStatusCode.BadRequest:
                    return new Result(Outcome.Rejected);
                default:
                    return new Result(Outcome.Failed);
            }
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or IOException)
        {
            if (cancel.IsCancellationRequested) throw;
            return new Result(Outcome.Failed);
        }
    }
}
