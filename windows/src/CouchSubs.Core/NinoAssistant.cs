// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace CouchSubs.Core;

/// <summary>
/// Nino: "Nino'ya Sor" kurulum yardımcısı. Sohbet havuz sunucusuna (<c>POST /v1/assistant</c>,
/// nino-pool/src/assistant.js) tek bir JSON olarak gider, cevap ve (robot ekibe bildirim gönderdiyse) bildirim kimliği
/// döner. Bu sınıf arayüzsüzdür: isteği kurar (son 24 mesaj, metin 2000 karakter, fotoğraflar yalnız fotoğraflı son 2
/// kullanıcı mesajında), gövdeyi 6 MB'ın altında tutar, cevabı ve hataları <see cref="Outcome"/>'a çevirir. Kuruluş
/// kimliği, fotoğraf küçültme ve JSON ayarları Sorun Bildir'le (<see cref="ProblemReport"/>) aynıdır.
/// </summary>
public static class NinoAssistant
{
    public const int MaxMessages = 24;
    public const int MaxText = 2000;
    public const int MaxImagesPerMessage = 3;
    /// <summary>Fotoğraf taşıyan en çok kaç kullanıcı mesajı (en yenileri); eskilerin yerine "[screenshot]" yazılır.</summary>
    public const int ImageMessages = 2;
    public const long MaxBodyBytes = 6L * 1024 * 1024;
    /// <summary>
    /// Fotoğraf başına hedef: 6 fotoğraf × 600 KB ≈ 4,8 MB base64, metinle birlikte 6 MB'ın altında kalır (Sorun Bildir'in
    /// 900 KB'ı burada fazla gelir). Gövde yine de aşarsa en eski fotoğraflı mesaj metne indirilir.
    /// </summary>
    public const int TargetImageBytes = 600 * 1024;
    public const string ScreenshotMarker = "[screenshot]";

    public enum Role { User, Assistant }

    /// <summary>Sohbetteki gerçek bir mesaj (yerel karşılama ve hata baloncukları buraya girmez).</summary>
    public sealed record Turn(Role Role, string Text, IReadOnlyList<byte[]>? Jpegs = null)
    {
        public IReadOnlyList<byte[]> Images => Jpegs ?? [];
    }

    public sealed class Message
    {
        [JsonPropertyName("role")] public string Role { get; set; } = "user";
        [JsonPropertyName("text")] public string Text { get; set; } = "";
        [JsonPropertyName("images")] public List<ProblemReport.Image>? Images { get; set; }
    }

    public sealed class Payload
    {
        [JsonPropertyName("v")] public int V { get; set; } = 1;
        [JsonPropertyName("install")] public string Install { get; set; } = "";
        [JsonPropertyName("app")] public string App { get; set; } = "";
        [JsonPropertyName("platform")] public string Platform { get; set; } = ProblemReport.Platform;
        [JsonPropertyName("language")] public string Language { get; set; } = "";
        [JsonPropertyName("messages")] public List<Message> Messages { get; set; } = [];
    }

    public enum Outcome
    {
        /// <summary>Cevap geldi.</summary>
        Replied,
        /// <summary>503 assistant_disabled: sunucuda model henüz yok.</summary>
        Disabled,
        /// <summary>429 rate_limited: bu kuruluşun günlük sınırı doldu.</summary>
        RateLimited,
        /// <summary>429 busy: günlük toplam bütçe doldu.</summary>
        Busy,
        /// <summary>400/413: istek kabul edilmedi (yeniden denemek işe yaramaz).</summary>
        Rejected,
        /// <summary>Ağ hatası, zaman aşımı, 5xx, model hatası ya da bozuk cevap: yeniden denenebilir.</summary>
        Failed,
    }

    public sealed record Result(Outcome Outcome, string? Reply = null, string? Report = null, TimeSpan? RetryAfter = null);

    private static readonly JsonSerializerOptions Json = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    /// <summary>Yardımcının adresi: havuz adresi (<see cref="NinoPool.ConfiguredEndpoint"/>) + <c>/v1/assistant</c>.</summary>
    public static Uri? Endpoint(Uri? poolBase) => poolBase is null ? null : new Uri(poolBase, "/v1/assistant");

    /// <summary>Gönderilebilir mi: yazı ya da en az bir fotoğraf var.</summary>
    public static bool CanSend(string? text, int images) => !string.IsNullOrWhiteSpace(text) || images > 0;

    /// <summary>
    /// İsteği kurar. Son <see cref="MaxMessages"/> mesaj alınır, baştaki Nino mesajları ve boş mesajlar atılır, son mesaj
    /// kullanıcınınki olmalıdır (değilse <see cref="ArgumentException"/>). Fotoğraflar yalnız fotoğraflı en yeni
    /// <see cref="ImageMessages"/> kullanıcı mesajında (her birinde en çok 3) gider; eskilerin metnine "[screenshot]"
    /// eklenir. Gövde <paramref name="maxBodyBytes"/>'ı aşarsa en eski fotoğraflı mesaj da metne indirilir.
    /// </summary>
    public static Payload Build(string install, string app, string language, IReadOnlyList<Turn> turns, long maxBodyBytes = MaxBodyBytes)
    {
        var kept = turns.Where(turn => !string.IsNullOrWhiteSpace(turn.Text) || (turn.Role == Role.User && turn.Images.Count > 0)).ToList();
        if (kept.Count == 0 || kept[^1].Role != Role.User) throw new ArgumentException("Son mesaj kullanıcınınki olmalı.", nameof(turns));
        if (kept.Count > MaxMessages) kept = kept[^MaxMessages..];
        while (kept.Count > 0 && kept[0].Role == Role.Assistant) kept.RemoveAt(0);

        // Fotoğraf taşıyacak mesajlar: fotoğraflı en yeni iki kullanıcı mesajı.
        var withImages = kept.Select((turn, index) => (turn, index))
            .Where(item => item.turn.Role == Role.User && item.turn.Images.Any(bytes => bytes.Length > 0))
            .Select(item => item.index).TakeLast(ImageMessages).ToList();

        while (true)
        {
            var payload = new Payload
            {
                Install = install,
                App = app.Length > 40 ? app[..40] : app,
                Language = language,
            };
            for (var i = 0; i < kept.Count; i++)
            {
                var turn = kept[i];
                var message = new Message { Role = turn.Role == Role.User ? "user" : "assistant" };
                var text = turn.Text.Trim();
                var hasImages = turn.Role == Role.User && turn.Images.Any(bytes => bytes.Length > 0);
                if (hasImages && withImages.Contains(i))
                {
                    message.Images = [.. turn.Images.Where(bytes => bytes.Length > 0).Take(MaxImagesPerMessage)
                        .Select(bytes => new ProblemReport.Image { Mime = "image/jpeg", Data = Convert.ToBase64String(bytes) })];
                }
                else if (hasImages)
                {
                    text = text.Length == 0 ? ScreenshotMarker : text + " " + ScreenshotMarker;
                }
                message.Text = text.Length > MaxText ? text[..MaxText] : text;
                payload.Messages.Add(message);
            }
            if (withImages.Count == 0 || Encoding.UTF8.GetByteCount(ToJson(payload)) <= maxBodyBytes) return payload;
            withImages.RemoveAt(0);
        }
    }

    public static string ToJson(Payload payload) => JsonSerializer.Serialize(payload, Json);

    /// <summary>Sunucunun cevabını (durum kodu, gövde, Retry-After) sonuca çevirir.</summary>
    public static Result Map(HttpStatusCode status, string? body, TimeSpan? retryAfter = null)
    {
        string? error = null, reply = null, report = null;
        try
        {
            if (!string.IsNullOrWhiteSpace(body))
            {
                using var document = JsonDocument.Parse(body);
                var root = document.RootElement;
                if (root.ValueKind == JsonValueKind.Object)
                {
                    if (root.TryGetProperty("error", out var e) && e.ValueKind == JsonValueKind.String) error = e.GetString();
                    if (root.TryGetProperty("reply", out var r) && r.ValueKind == JsonValueKind.String) reply = r.GetString();
                    if (root.TryGetProperty("report", out var p) && p.ValueKind == JsonValueKind.String) report = p.GetString();
                }
            }
        }
        catch (JsonException) { }

        return (int)status switch
        {
            200 => string.IsNullOrWhiteSpace(reply) ? new Result(Outcome.Failed)
                : new Result(Outcome.Replied, reply.Trim(), string.IsNullOrWhiteSpace(report) ? null : report),
            503 when error == "assistant_disabled" => new Result(Outcome.Disabled),
            429 => new Result(error == "busy" ? Outcome.Busy : Outcome.RateLimited, RetryAfter: retryAfter),
            400 or 413 => new Result(Outcome.Rejected),
            _ => new Result(Outcome.Failed),
        };
    }

    /// <summary>Sohbeti gönderir; ağ hatası ve zaman aşımı da <see cref="Outcome.Failed"/> olarak döner.</summary>
    public static async Task<Result> SendAsync(HttpClient http, Uri? endpoint, Payload payload, CancellationToken cancel = default)
    {
        if (endpoint is null) return new Result(Outcome.Failed);
        try
        {
            using var content = new StringContent(ToJson(payload), Encoding.UTF8);
            content.Headers.ContentType = new MediaTypeHeaderValue("application/json") { CharSet = "utf-8" };
            using var response = await http.PostAsync(endpoint, content, cancel).ConfigureAwait(false);
            var body = await response.Content.ReadAsStringAsync(cancel).ConfigureAwait(false);
            var retry = response.Headers.RetryAfter is { } header
                ? header.Delta ?? (header.Date is { } date ? date - DateTimeOffset.UtcNow : null) : null;
            return Map(response.StatusCode, body, retry);
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or IOException)
        {
            if (cancel.IsCancellationRequested) throw;
            return new Result(Outcome.Failed);
        }
    }

    // --- Cevap metni ---

    /// <summary>Cevaptaki bir parça: düz yazı ya da tıklanabilir bağlantı.</summary>
    public sealed record Span(string Text, Uri? Link = null);

    /// <summary>Cevaptaki bir satır bloğu: paragraf ya da "1." gibi numaralı madde (numara ayrı).</summary>
    public sealed record Block(string? Number, IReadOnlyList<Span> Spans);

    private static readonly Regex Url = new(@"https?://[^\s<>""')\]]+", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex NumberedItem = new(@"^\s*(\d{1,2})[.)]\s+(.*)$", RegexOptions.Compiled);

    /// <summary>
    /// Nino'nun cevabını bloklara ayırır: boş satır paragrafları ayırır, "1." ile başlayan satır numaralı maddedir, paragraf
    /// içindeki tek satır sonları korunur. Yalnız http/https bağlantıları tıklanabilir olur (sondaki nokta, virgül bağlantıya
    /// girmez).
    /// </summary>
    public static IReadOnlyList<Block> Format(string reply)
    {
        var blocks = new List<Block>();
        var paragraph = new List<string>();
        void Flush()
        {
            if (paragraph.Count == 0) return;
            blocks.Add(new Block(null, Linkify(string.Join("\n", paragraph))));
            paragraph.Clear();
        }
        foreach (var raw in reply.Replace("\r\n", "\n").Split('\n'))
        {
            var line = raw.TrimEnd();
            if (line.Trim().Length == 0) { Flush(); continue; }
            if (NumberedItem.Match(line) is { Success: true } item)
            {
                Flush();
                blocks.Add(new Block(item.Groups[1].Value + ".", Linkify(item.Groups[2].Value.Trim())));
                continue;
            }
            paragraph.Add(line.Trim());
        }
        Flush();
        return blocks;
    }

    /// <summary>Metni düz yazı ve bağlantı parçalarına ayırır.</summary>
    public static IReadOnlyList<Span> Linkify(string text)
    {
        var spans = new List<Span>();
        var at = 0;
        foreach (Match match in Url.Matches(text))
        {
            var value = match.Value.TrimEnd('.', ',', ';', ':', '!', '?');
            if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps)) continue;
            if (match.Index > at) spans.Add(new Span(text[at..match.Index]));
            spans.Add(new Span(value, uri));
            at = match.Index + value.Length;
        }
        if (at < text.Length) spans.Add(new Span(text[at..]));
        return spans;
    }
}
