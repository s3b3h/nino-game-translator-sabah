// SPDX-License-Identifier: AGPL-3.0-only

using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using CouchSubs.Core;
using CouchSubs.Core.Dubbing;

namespace CouchSubs.Translation;

/// <summary>Bağlam olarak giden, daha önce gösterilmiş satır ve (biliniyorsa) çevirisi.</summary>
public sealed record AiContextLine(string Source, string? Translation = null);

/// <summary>Yapay zekâ hizmeti çeviremedi; yalnız durum taşır, anahtar ve hizmetin yanıt metni hiçbir yere yazılmaz.</summary>
public sealed class AiException(OnlineKeyState state) : Exception($"AI translation failed: {state}")
{
    public OnlineKeyState State { get; } = state;
}

/// <summary>
/// Üç hizmet için istek kurma ve yanıt okuma (Mac'teki CouchSubsCore/AITranslation.swift ile aynı). Cümleler bir JSON
/// dizisi olarak gider, aynı sırada JSON dizisi beklenir; böylece cümle cümle önbelleğe yazılır ve dublaj konuşmacıyı
/// bilir (DeepL ile aynı düzen).
/// </summary>
public static class AiRequest
{
    /// <summary>Bir altyazı satırına yeten çıktı sınırı; düşünen modellere de pay bırakır.</summary>
    public const int MaxOutputTokens = 1024;
    /// <summary>"Ekranı çevir"in tek isteğinde çıktı sınırı: ekrandaki bütün yazılar birlikte döner.</summary>
    public const int ScreenOutputTokens = 8192;

    public const string SystemPrompt =
        "You translate English video game subtitles into natural, spoken Turkish, the way people really talk. " +
        "Characters address each other informally (use \"sen\", not \"siz\") unless the line is clearly formal. " +
        "Keep character names, place names and speaker labels such as \"ATREUS:\" exactly as they are. " +
        "Keep line breaks. Keep the meaning and tone; do not add or leave out anything. " +
        "Reply with only the translation, no explanations, notes or quotes.";

    /// <summary>Nino: Arapça hedefin yönergesi (Mac: AIRequest.arabicSystemPrompt ile aynı).</summary>
    public const string ArabicSystemPrompt =
        "You translate English video game subtitles into clear, natural Modern Standard Arabic, the way good Arabic " +
        "game subtitles read. Keep it short and easy to read on screen; use a natural spoken tone for dialogue. " +
        "Keep character names, place names and speaker labels such as \"ATREUS:\" exactly as they are, in Latin letters. " +
        "Keep line breaks. Keep the meaning and tone; do not add or leave out anything. " +
        "Use Arabic punctuation (، ؟ ؛) and Western digits. Keep controller button symbols (✕ ○ △ □, L1, R2) unchanged. " +
        "Reply with only the translation, no explanations, notes or quotes.";

    /// <summary>Hedef dile göre yönerge.</summary>
    /// <summary>Nino: öbür dillerin (Hintçe, Endonezce, Tayca…) yönergesi (Mac: AIRequest.genericSystemPrompt ile aynı).</summary>
    public static string GenericSystemPrompt(string language) =>
        $"You translate English video game subtitles into clear, natural {language}, the way good {language} " +
        "game subtitles read. Keep it short and easy to read on screen; use a natural spoken tone for dialogue. " +
        "Keep character names, place names and speaker labels such as \"ATREUS:\" exactly as they are, in Latin letters. " +
        "Keep line breaks. Keep the meaning and tone; do not add or leave out anything. " +
        "Keep controller button symbols (✕ ○ △ □, L1, R2) unchanged. " +
        "Reply with only the translation, no explanations, notes or quotes.";

    public static string SystemPromptFor(string target) =>
        TargetLanguage.IsTurkish(target) ? SystemPrompt
        : TargetLanguage.IsArabic(target) ? ArabicSystemPrompt
        : GenericSystemPrompt(TargetLanguage.EnglishName(target));

    private static readonly JsonSerializerOptions Compact = new() { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    /// <summary>Kullanıcı iletisi: önceki satırlar (yalnız bağlam) ve çevrilecek cümleler.</summary>
    public static string UserMessage(IReadOnlyList<string> sentences, IReadOnlyList<AiContextLine> context, string? game = null,
                                     string target = "tr")
    {
        var language = TargetLanguage.EnglishName(target);
        var parts = new List<string>();
        if (!string.IsNullOrEmpty(game)) parts.Add($"Game: {game}");
        if (context.Count > 0)
        {
            var lines = new List<string> { "Previous subtitles, for context only (do not translate them again):" };
            foreach (var line in context)
            {
                lines.Add($"English: {line.Source}");
                if (line.Translation is { } translation) lines.Add($"{language}: {translation}");
            }
            parts.Add(string.Join("\n", lines));
        }
        var list = new JsonArray([.. sentences.Select(s => (JsonNode?)JsonValue.Create(s))]).ToJsonString(Compact);
        parts.Add($"Translate each string in this JSON array into {language}. Reply with only a JSON array of {sentences.Count} " +
                  $"{language} strings in the same order.\n{list}");
        return string.Join("\n\n", parts);
    }

    /// <summary>Yerel modelin sıcaklığı: çeviri tutarlı olsun, yine de doğal kalsın.</summary>
    public const double LocalTemperature = 0.2;

    /// <summary>Hizmete giden HTTP isteği. <paramref name="server"/>: yerel modelin sunucusu (verilmezse Ollama'nın varsayılan adresi).</summary>
    public static HttpRequestMessage Build(AiProvider provider, string key, AiModel model, IReadOnlyList<string> sentences,
                                           IReadOnlyList<AiContextLine> context, string? game = null, LocalAiServer? server = null,
                                           int maxOutputTokens = MaxOutputTokens, string target = "tr")
    {
        key = key.Trim();
        var user = UserMessage(sentences, context, game, target);
        var systemPrompt = SystemPromptFor(target);
        HttpRequestMessage request;
        JsonObject body;
        switch (provider)
        {
            case AiProvider.Gemini:
                // https://ai.google.dev/api/generate-content (aistudio.google.com/api-reference/generate-content):
                // POST /v1beta/models/{model}:generateContent, anahtar "x-goog-api-key" başlığında.
                // Gemini 3.6 Flash ve sonrası temperature'ı yok sayıyor; düşünme düzeyi listedeki modelle gelir.
                request = new HttpRequestMessage(HttpMethod.Post,
                    $"https://generativelanguage.googleapis.com/v1beta/models/{Uri.EscapeDataString(model.Id)}:generateContent");
                request.Headers.Add("x-goog-api-key", key);
                body = new JsonObject
                {
                    ["systemInstruction"] = new JsonObject { ["parts"] = new JsonArray(new JsonObject { ["text"] = systemPrompt }) },
                    ["contents"] = new JsonArray(new JsonObject
                    {
                        ["role"] = "user",
                        ["parts"] = new JsonArray(new JsonObject { ["text"] = user }),
                    }),
                    ["generationConfig"] = new JsonObject { ["maxOutputTokens"] = maxOutputTokens },
                };
                if (model.Thinking is { } level) body["generationConfig"]!["thinkingConfig"] = new JsonObject { ["thinkingLevel"] = level };
                break;
            case AiProvider.OpenAi:
                // https://platform.openai.com/docs/api-reference/chat/create (developers.openai.com/api/reference):
                // POST /v1/chat/completions, "Authorization: Bearer"; "developer" iletisi yönergedir.
                request = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/chat/completions");
                request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {key}");
                body = new JsonObject
                {
                    ["model"] = model.Id,
                    ["messages"] = new JsonArray(
                        new JsonObject { ["role"] = "developer", ["content"] = systemPrompt },
                        new JsonObject { ["role"] = "user", ["content"] = user }),
                    ["max_completion_tokens"] = maxOutputTokens,
                };
                if (model.Effort is { } effort) body["reasoning_effort"] = effort;
                break;
            case AiProvider.Local:
                // Ollama ve LM Studio'nun OpenAI uyumlu Chat Completions'ı: POST {adres}/chat/completions. Yalnız iki
                // sunucunun da tanıdığı alanlar gider ("developer" rolü, reasoning_effort, max_completion_tokens gitmez).
                // Anahtar isteğe bağlıdır; boşsa Authorization başlığı hiç eklenmez.
                var local = server ?? LocalAiServer.Create(LocalAiServer.OllamaUrl, model.Id)!;
                request = new HttpRequestMessage(HttpMethod.Post, local.ChatUrl);
                if (key.Length > 0) request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {key}");
                body = new JsonObject
                {
                    ["model"] = model.Id,
                    ["messages"] = TranslationModelPrompt.Messages(model.Id, sentences, context, target) ?? new JsonArray(
                            new JsonObject { ["role"] = "system", ["content"] = systemPrompt },
                            new JsonObject { ["role"] = "user", ["content"] = user }),
                    ["temperature"] = LocalTemperature,
                    ["max_tokens"] = maxOutputTokens,
                    ["stream"] = false,
                };
                break;
            default:
                // https://docs.anthropic.com/en/api/messages (platform.claude.com/docs/en/api/messages): POST /v1/messages,
                // "x-api-key" ve "anthropic-version". Yeni modellerde temperature gönderilmez; effort ve düşünme listedeki
                // modelle gelir (platform.claude.com/docs/en/build-with-claude/effort).
                request = new HttpRequestMessage(HttpMethod.Post, "https://api.anthropic.com/v1/messages");
                request.Headers.Add("x-api-key", key);
                request.Headers.Add("anthropic-version", "2023-06-01");
                body = new JsonObject
                {
                    ["model"] = model.Id,
                    ["max_tokens"] = maxOutputTokens,
                    ["system"] = systemPrompt,
                    ["messages"] = new JsonArray(new JsonObject { ["role"] = "user", ["content"] = user }),
                };
                if (model.Effort is { } claudeEffort) body["output_config"] = new JsonObject { ["effort"] = claudeEffort };
                if (model.Thinking is { } thinking) body["thinking"] = new JsonObject { ["type"] = thinking };
                break;
        }
        request.Content = new StringContent(body.ToJsonString(Compact), Encoding.UTF8, "application/json");
        return request;
    }

    /// <summary>Yanıttaki düz metin (düşünme bölümleri atlanır).</summary>
    public static string Text(AiProvider provider, string json)
    {
        JsonNode? root;
        try { root = JsonNode.Parse(json); }
        catch (JsonException) { throw new AiException(OnlineKeyState.Unreachable); }
        string? text = null;
        try
        {
            switch (provider)
            {
                case AiProvider.Gemini:
                    // candidates[0].content.parts[].text; "thought": true olan parçalar düşünmedir.
                    var parts = root?["candidates"]?.AsArray().FirstOrDefault()?["content"]?["parts"]?.AsArray();
                    text = parts is null ? null : string.Concat(parts
                        .Where(p => p?["thought"]?.GetValueKind() is not JsonValueKind.True)
                        .Select(p => p?["text"]?.GetValue<string>() ?? ""));
                    break;
                case AiProvider.OpenAi or AiProvider.Local:
                    text = root?["choices"]?.AsArray().FirstOrDefault()?["message"]?["content"]?.GetValue<string>();
                    break;
                default:
                    var blocks = root?["content"]?.AsArray();
                    text = blocks is null ? null : string.Concat(blocks
                        .Where(b => b?["type"]?.GetValue<string>() == "text")
                        .Select(b => b?["text"]?.GetValue<string>() ?? ""));
                    break;
            }
        }
        catch (Exception error) when (error is InvalidOperationException or FormatException)
        {
            throw new AiException(OnlineKeyState.Unreachable);
        }
        if (string.IsNullOrWhiteSpace(text)) throw new AiException(OnlineKeyState.Unreachable);
        return text;
    }

    /// <summary>Yanıttaki JSON dizisi; tek cümlede model diziyi unutup düz metin dönerse o metin alınır.</summary>
    public static string[] Translations(string text, int count)
    {
        var trimmed = text.Trim();
        // Düşünen yerel modeller (ör. Qwen3, DeepSeek-R1) yanıtın başına <think>…</think> koyar; yalnız sonrası alınır.
        var thought = trimmed.LastIndexOf("</think>", StringComparison.Ordinal);
        if (thought >= 0) trimmed = trimmed[(thought + "</think>".Length)..].Trim();
        trimmed = StripControlTokens(trimmed);
        // ```json … ``` çitini at.
        if (trimmed.StartsWith("```", StringComparison.Ordinal))
            trimmed = string.Join("\n", trimmed.Split('\n').Skip(1).Where(l => !l.StartsWith("```", StringComparison.Ordinal))).Trim();
        int start = trimmed.IndexOf('['), end = trimmed.LastIndexOf(']');
        if (start >= 0 && end > start)
        {
            try
            {
                if (JsonNode.Parse(WithoutTrailingComma(trimmed[start..(end + 1)])) is JsonArray array && array.All(n => n?.GetValueKind() == JsonValueKind.String))
                {
                    if (array.Count != count) throw new AiException(OnlineKeyState.Unreachable);
                    return [.. array.Select(n => n!.GetValue<string>().Trim())];
                }
            }
            catch (JsonException) { /* dizi değil; düz metin olabilir */ }
        }
        if (UnquotedList(trimmed, count) is { } list) return list;
        // Nino: TranslateGemma düz metin döner: birden çok cümle satır satır gelir.
        if (count > 1)
        {
            var lines = trimmed.Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).ToArray();
            if (lines.Length != count) throw new AiException(OnlineKeyState.Unreachable);
            return lines;
        }
        return [trimmed.Trim('"', '“', '”')];
    }

    /// <summary>
    /// Yerel modellerin metne sızan bitiş/rol işaretleri (<c>&lt;/s&gt;</c>, <c>&lt;|im_end|&gt;</c>, <c>&lt;|eot_id|&gt;</c>,
    /// <c>&lt;end_of_turn&gt;</c> …) ekranda görünmesin; yalnız bu kalıplar silinir, altyazıdaki başka yazılara dokunulmaz.
    /// </summary>
    internal static string StripControlTokens(string text) =>
        System.Text.RegularExpressions.Regex.Replace(text,
            @"</?s>|<\|[A-Za-z0-9_]{1,32}\|>|</?(?:start|end)_of_turn>|</?(?:eos|bos|pad)>", "").Trim();

    /// <summary><c>["Bir.", "İki.",]</c> gibi sondaki fazla virgül JSON'u bozmasın.</summary>
    internal static string WithoutTrailingComma(string text) =>
        System.Text.RegularExpressions.Regex.Replace(text, @",\s*\]$", "]");

    /// <summary>
    /// Tırnaksız dizi: bazı yerel modeller JSON istense de <c>[Hareket etmemiz lazım.]</c> ya da
    /// <c>[Satır bir., Satır iki.]</c> döndürür. Yalnız bütün yanıt köşeli parantez içindeyse ve öğe sayısı tam tutuyorsa
    /// alınır; tutmazsa null (hat her zamanki geri dönüşe gider). Cümle içi virgülde yanlış bölmemek için sıra: satır sonu,
    /// cümle sonu işaretinden (. ! ? … ") sonra gelen virgül, en son düz virgül.
    /// </summary>
    internal static string[]? UnquotedList(string text, int count)
    {
        if (count < 1 || text.Length < 2 || !text.StartsWith('[') || !text.EndsWith(']')) return null;
        var inner = text[1..^1];
        IEnumerable<string[]> candidates = count == 1 ? [[inner]] :
        [
            [.. inner.Split('\n').Where(line => line.Trim().Length > 0)],
            SentenceSplit(inner),
            inner.Split(','),
        ];
        foreach (var parts in candidates)
        {
            var items = parts.Select(CleanItem).ToArray();
            if (items.Length == count && items.All(item => item.Length > 0)) return items;
        }
        return null;
    }

    private static string CleanItem(string item)
    {
        var value = item.Trim();
        if (value.EndsWith(',')) value = value[..^1];
        return value.Trim().Trim('"', '“', '”').Trim();
    }

    /// <summary>Cümle sonu işaretinden (. ! ? … " ”) hemen sonra gelen virgüllerden böler; işaret öğede kalır.</summary>
    private static string[] SentenceSplit(string text)
    {
        var parts = new List<string>();
        var start = 0;
        var last = '\0';
        for (var i = 0; i < text.Length; i++)
        {
            var c = text[i];
            if (c == ',' && last is '.' or '!' or '?' or '…' or '"' or '”')
            {
                parts.Add(text[start..i]);
                start = i + 1;
            }
            if (!char.IsWhiteSpace(c)) last = c;
        }
        parts.Add(text[start..]);
        return [.. parts];
    }

    /// <summary>Başarısız HTTP yanıtının anlamı. Gövde yalnız tanınan hata kodları için okunur, hiçbir yere yazılmaz.</summary>
    public static OnlineKeyState Failure(HttpStatusCode status, string body)
    {
        var message = body.ToLowerInvariant();
        return (int)status switch
        {
            401 or 403 => OnlineKeyState.Invalid,
            402 or 429 => OnlineKeyState.QuotaExceeded,
            400 when message.Contains("api_key_invalid") || message.Contains("api key not valid") => OnlineKeyState.Invalid,
            400 when message.Contains("credit balance") || message.Contains("insufficient_quota") => OnlineKeyState.QuotaExceeded,
            400 or 404 => OnlineKeyState.ModelRejected,
            _ => OnlineKeyState.Unreachable,
        };
    }

    /// <summary>
    /// 429 yalnız dakikalık sınırdan geldiyse onun ayrıntısı; gün sınırı, bakiye ya da tanınmayan 429 için null (bunlar
    /// <see cref="OnlineKeyState.QuotaExceeded"/> olarak kullanıcıya gösterilir). Gemini'nin hata gövdesinde error.details[]
    /// içinde google.rpc.QuotaFailure (violations[].quotaId, ör. "GenerateRequestsPerMinutePerProjectPerModel-FreeTier",
    /// quotaValue "15") ve google.rpc.RetryInfo (retryDelay "37s") bulunur.
    /// </summary>
    public static AiRateLimit? RateLimit(HttpStatusCode status, string body)
    {
        if ((int)status != 429) return null;
        JsonArray? details;
        try { details = JsonNode.Parse(body)?["error"]?["details"] as JsonArray; }
        catch (JsonException) { return null; }
        if (details is null) return null;
        try
        {
            var violations = details.SelectMany(d => d?["violations"] as IEnumerable<JsonNode?> ?? []).OfType<JsonNode>().ToList();
            var ids = violations.Select(v => v["quotaId"]?.GetValueKind() == JsonValueKind.String ? v["quotaId"]!.GetValue<string>() : null)
                .OfType<string>().ToList();
            // Günlük sınır doldu: dakikalık beklemeyle geçmez, kullanıcı bilmeli.
            if (ids.Any(id => id.Contains("PerDay", StringComparison.Ordinal)) || !ids.Any(id => id.Contains("PerMinute", StringComparison.Ordinal)))
                return null;
            TimeSpan? retry = null;
            var delay = details.Select(d => d?["retryDelay"]).FirstOrDefault(n => n?.GetValueKind() == JsonValueKind.String)?.GetValue<string>();
            if (delay is not null && double.TryParse(delay.TrimEnd('s'), System.Globalization.NumberStyles.Float,
                                                     System.Globalization.CultureInfo.InvariantCulture, out var seconds))
                retry = TimeSpan.FromSeconds(seconds);
            // İstek sınırı (token sınırı değil).
            int? perMinute = null;
            var requests = violations.FirstOrDefault(v => v["quotaId"]?.GetValueKind() == JsonValueKind.String
                                                          && v["quotaId"]!.GetValue<string>().Contains("Requests", StringComparison.Ordinal));
            var value = requests?["quotaValue"];
            if (value?.GetValueKind() == JsonValueKind.String && int.TryParse(value.GetValue<string>(), out var parsed) && parsed > 0) perMinute = parsed;
            else if (value?.GetValueKind() == JsonValueKind.Number && value.GetValue<int>() > 0) perMinute = value.GetValue<int>();
            return new AiRateLimit(retry, perMinute);
        }
        catch (Exception error) when (error is InvalidOperationException or FormatException)
        {
            return null;
        }
    }
}

/// <summary>
/// Hizmetin bildirdiği dakikalık istek sınırı aşımı (429). Gün sınırından farklı olarak kısa sürer; kullanıcıya hata
/// gösterilmez, birkaç saniye o satırlar yerel çeviriyle çevrilir.
/// </summary>
/// <param name="RetryAfter">Hizmetin önerdiği bekleme ("retryDelay"); yoksa null.</param>
/// <param name="RequestsPerMinute">Hizmetin bildirdiği dakikalık istek sınırı ("quotaValue"); yoksa null.</param>
public sealed record AiRateLimit(TimeSpan? RetryAfter = null, int? RequestsPerMinute = null);

/// <summary>Hizmet dakikalık sınırın aşıldığını bildirdi; kullanıcıya hata olarak gösterilmez.</summary>
internal sealed class AiRateLimitedException(AiRateLimit limit) : Exception("AI translation rate limited")
{
    public AiRateLimit Limit { get; } = limit;
}

/// <summary>
/// İsteğe bağlı yapay zekâ çevirisi: kullanıcının kendi Gemini, OpenAI ya da Claude anahtarıyla (Mac'teki
/// AITranslationCore ile aynı). Altyazı cümle cümle, konuşmacı adları çevrilmeden gönderilir; son gösterilen 3 satır ve
/// çevirileri bağlam olarak eklenir. Hizmete ulaşılamazsa, kota biterse ya da zaman aşımı olursa o satır cihaz üstü
/// modelle çevrilir ve bir dakika hizmet denenmez. Yerel çeviriler bu motorun önbelleğine yazılmaz.
/// Bir altyazının çevrilmemiş bütün cümleleri tek istekte gider. Ücretsiz katmanın dakikalık sınırı için model listesindeki
/// <c>requestsPerMinute</c> kadar istek hakkı vardır; hak bitince o satır sessizce (hata göstermeden) yerel çeviriyle çevrilir.
/// </summary>
public sealed class AiTranslator : ITextTranslator, IOnlineTranslator
{
    /// <summary>Bağlama giden önceki satır sayısı.</summary>
    internal const int ContextLines = 3;
    /// <summary>Hata sonrası bu süre hizmet denenmez.</summary>
    private static readonly TimeSpan RetryAfter = TimeSpan.FromMinutes(1);
    /// <summary>Dakikalık sınır aşılınca en çok bu kadar beklenir (hizmet bekleme önermezse de bu kadar).</summary>
    public static readonly TimeSpan RateLimitPause = TimeSpan.FromSeconds(20);
    /// <summary>Denemede çevrilen örnek satır.</summary>
    public const string Sample = "BATMAN: I'm Batman.";

    /// <summary>Bulut hizmetinde beklenen en uzun süre.</summary>
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(5);
    /// <summary>
    /// Yerel modelde beklenen en uzun süre: bilgisayardaki model buluttan yavaştır ve bir süre boşta kalınca belleğe
    /// yeniden yüklenir. Yine de sınırlıdır: çeviriler sırayla gider, bir satır bütün sırayı bekletmesin; ekrandan çoktan
    /// kalkmış satırın geç gelen çevirisini hat zaten göstermez.
    /// </summary>
    public static readonly TimeSpan LocalTimeout = TimeSpan.FromSeconds(15);
    /// <summary>"Bağlantıyı dene"de yerel model için beklenen süre: ilk istek modeli belleğe yükler, uzun sürebilir.</summary>
    public static readonly TimeSpan LocalTestTimeout = TimeSpan.FromSeconds(90);

    // Kısa zaman aşımı: altyazı birkaç saniye ekranda kalır, geç gelen çeviri işe yaramaz.
    private static readonly Lazy<HttpClient> SharedClient = new(() => new HttpClient { Timeout = AiTranslator.Timeout });
    private static readonly Lazy<HttpClient> LocalClient = new(() => new HttpClient { Timeout = LocalTimeout });
    private static readonly Lazy<HttpClient> LocalTestClient = new(() => new HttpClient { Timeout = LocalTestTimeout });

    /// <summary>Hizmete uygun zaman aşımıyla paylaşılan istemci.</summary>
    public static HttpClient ClientFor(AiProvider provider) => provider.IsLocal() ? LocalClient.Value : SharedClient.Value;

    /// <summary>"Ekranı çevir"de bulut hizmetinde beklenen en uzun süre: bütün ekranın çevirisi tek yanıtta gelir.</summary>
    public static readonly TimeSpan ScreenTimeout = TimeSpan.FromSeconds(30);
    /// <summary>Bir istekte giden en çok parça; kalabalık ekran birkaç isteğe bölünür.</summary>
    public const int ScreenBatch = 40;
    private static readonly Lazy<HttpClient> ScreenClient = new(() => new HttpClient { Timeout = ScreenTimeout });

    private readonly string _key;
    private readonly ITextTranslator? _fallback;
    private readonly HttpClient _http;
    /// <summary>"Ekranı çevir"in uzun yanıtlı tek isteği için daha uzun bekleyen istemci.</summary>
    private readonly HttpClient _screenHttp;
    private readonly TranslationCache _cache;
    private readonly RequestBudget? _budget;
    private readonly ConcurrentDictionary<string, IReadOnlyList<SpokenLine>> _speech = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, byte> _names = new(StringComparer.Ordinal);
    private readonly List<AiContextLine> _recent = [];
    private readonly Func<string?>? _game;
    private DateTimeOffset _pausedUntil = DateTimeOffset.MinValue;
    private OnlineKeyState? _failure;

    /// <param name="model">Kayıtlı model kimliği; listede yoksa varsayılan model.</param>
    /// <param name="cache">Kalıcı önbellek; verilmezse yalnız bellekte tutulur.</param>
    /// <param name="budget">
    /// Dakikalık istek hakkı; null ise modelin uygulama genelindeki ortak hakkı (Google sınırı proje ve model başına sayar;
    /// çeviri hattı yeniden kurulsa da hak sıfırlanmaz). Modelin sınırı yoksa hak da yoktur.
    /// </param>
    /// <param name="server">Yerel modelin sunucusu (yalnız <see cref="AiProvider.Local"/>; verilmezse Ollama'nın varsayılan adresi).</param>
    /// <param name="http">Verilmezse hizmete uygun zaman aşımıyla paylaşılan istemci (yerel model daha uzun bekler).</param>
    /// <param name="game">
    /// Oynanan oyunun adı (ör. eşleşen oyun paketinin başlığı); her istekte sorulur, null ya da boşsa istemde oyun satırı olmaz.
    /// </param>
    public AiTranslator(AiProvider provider, string key, string? model, ITextTranslator? fallback, HttpClient? http = null,
                        TranslationCache? cache = null, RequestBudget? budget = null, LocalAiServer? server = null,
                        Func<string?>? game = null, string target = "tr")
    {
        _game = game;
        Provider = provider;
        Target = target;
        Model = provider.Model(model);
        Server = provider.IsLocal() ? server ?? LocalAiServer.Create(LocalAiServer.OllamaUrl, Model.Id) : null;
        _key = key.Trim();
        _fallback = fallback;
        _http = http ?? ClientFor(provider);
        _screenHttp = http ?? (provider.IsLocal() ? LocalTestClient.Value : ScreenClient.Value);
        _cache = cache ?? new TranslationCache();
        _budget = budget ?? RequestBudget.Shared(provider, Model);
    }

    public AiProvider Provider { get; }
    public AiModel Model { get; }
    /// <summary>Nino: hedef dil ("tr", "ar"); istemler buna göre yazılır.</summary>
    public string Target { get; }
    /// <summary>Yerel modelin sunucusu; bulut hizmetlerinde null.</summary>
    public LocalAiServer? Server { get; }

    /// <summary>Son hata; çeviri düzgün gidiyorsa null.</summary>
    public OnlineKeyState? LastError => _failure;

    /// <summary>Son satır dakikalık sınır yüzünden yerel çeviriyle çevrildi (hata sayılmaz, bildirilmez).</summary>
    public bool LastLineWasRateLimited { get; private set; }

    public event Action<OnlineKeyState?>? FailureChanged;

    // Oyun bilinmiyorsa eski kayıtlar geçerlidir; biliniyorsa yalnız o oyunun sonucu kullanılır.
    private static string CacheKey(string text, string? game) =>
        string.IsNullOrEmpty(game) ? text : game + "\u001f" + text;

    public async Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(text);
        // Arama, HTTP isteği ve kayıt aynı oyunla yapılmalı; callback işlem sırasında değişebilir.
        var game = _game?.Invoke()?.Trim();
        // Bağlam, bu satırdan önce gösterilenlerdir; satırın kendisi bağlama girmez.
        var context = Context();
        Shown(text);
        if (_cache.TryGet(CacheKey(text, game), out var cached)) return Remember(cached, text);

        var pieces = SubtitleSegmenter.Split(text);
        foreach (var name in pieces.Select(SubtitleSegmenter.LabelName).OfType<string>())
            foreach (var word in name.Split(' ', StringSplitOptions.RemoveEmptyEntries).Where(w => w.Length >= 2))
                _names[word.ToLowerInvariant()] = 0;
        var names = _names.Keys.ToHashSet(StringComparer.Ordinal);
        // Önbellekte duran cümleler yeniden gönderilmez.
        var translations = pieces.Select(p => p.Translate && _cache.TryGet(CacheKey(p.Text, game), out var known) ? known : null).ToList();
        var missing = Enumerable.Range(0, pieces.Count).Where(i => pieces[i].Translate && translations[i] is null).ToList();
        var sources = missing.Select(i => SubtitleSegmenter.NormalizeCase(pieces[i].Text, names)).ToList();
        // Hizmetin beklemesi yalnız eksik çeviriler içindir; önbellekteki parçalar yerel motor istemez.
        if (sources.Count > 0 && DateTimeOffset.UtcNow < _pausedUntil)
            return Remember(await FallbackAsync(text, cancellationToken).ConfigureAwait(false), text);
        // Dakikalık hak bittiyse istek gönderilmez; satır sessizce yerel çeviriyle çevrilir (hata değildir).
        LastLineWasRateLimited = sources.Count > 0 && _budget is { } budget && !budget.TryTake();
        if (LastLineWasRateLimited) return Remember(await FallbackAsync(text, cancellationToken).ConfigureAwait(false), text);

        string[] translated;
        try
        {
            translated = sources.Count == 0 ? [] : await RequestAsync(sources, context, game, cancellationToken).ConfigureAwait(false);
            if (sources.Count > 0) Report(null);
        }
        catch (AiRateLimitedException limited) when (!cancellationToken.IsCancellationRequested)
        {
            // Dakikalık sınır: kısa beklenir, ana ekranda uyarı çıkmaz; hizmet daha düşük sınır bildirdiyse ona inilir.
            if (limited.Limit.RequestsPerMinute is { } perMinute) _budget?.Lower(perMinute);
            var pause = limited.Limit.RetryAfter is { } retry && retry < RateLimitPause ? retry : RateLimitPause;
            if (pause < TimeSpan.FromSeconds(1)) pause = TimeSpan.FromSeconds(1);
            LastLineWasRateLimited = true;
            _pausedUntil = DateTimeOffset.UtcNow + pause;
            return Remember(await FallbackAsync(text, cancellationToken).ConfigureAwait(false), text);
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or AiException
                                      && !cancellationToken.IsCancellationRequested)
        {
            Report(error is AiException ai ? ai.State : OnlineKeyState.Unreachable);
            _pausedUntil = DateTimeOffset.UtcNow + RetryAfter;
            return Remember(await FallbackAsync(text, cancellationToken).ConfigureAwait(false), text);
        }
        var local = false;
        for (var i = 0; i < missing.Count; i++)
        {
            var piece = pieces[missing[i]].Text;
            if (IsEcho(piece, translated[i]) && await RetryEchoAsync(piece, cancellationToken).ConfigureAwait(false) is { } retried
                && !IsEcho(piece, retried))
            {
                // Yerel çeviri bu motorun önbelleğine yazılmaz.
                translations[missing[i]] = retried;
                local = true;
                continue;
            }
            translations[missing[i]] = translated[i];
            _cache.Store(CacheKey(piece, game), translated[i]);
        }

        var builder = new StringBuilder();
        for (var i = 0; i < pieces.Count; i++) builder.Append(translations[i] ?? pieces[i].Text);
        if (_speech.Count >= 512) _speech.Clear();
        _speech[CacheKey(text, game)] = SpeechScript.Lines(pieces, translations);
        var result = builder.ToString();
        if (!local) _cache.Store(CacheKey(text, game), result);
        return Remember(result, text);
    }

    /// <summary>
    /// Model cümleyi çevirmeden geri verdi mi (hattın "zaten hedef dilde" eşiğiyle aynı). Küçük yerel modeller İngilizce
    /// cümleyi sık sık olduğu gibi döndürüyor ("You think I'm on the run?"); hat bunu Türkçe sanıp hiç göstermiyor,
    /// önbellek de öyle saklıyordu (#245).
    /// </summary>
    internal static bool IsEcho(string source, string translation) =>
        TextMatch.IsSimilar(TextMatch.Normalize(source), TextMatch.Normalize(translation), 0.90);

    /// <summary>
    /// Geri verilen cümle cihaz üstü çeviriyle bir kez daha denenir; o da aynı kalırsa (ad, konsolun Türkçe menüsü)
    /// çevrilecek bir şey yoktur ve modelin yanıtı önbelleğe yazılır. Yerel çeviri yoksa ya da hata verirse null.
    /// </summary>
    private async Task<string?> RetryEchoAsync(string text, CancellationToken cancellationToken)
    {
        if (_fallback is null) return null;
        try { return await _fallback.TranslateAsync(text, cancellationToken).ConfigureAwait(false); }
        catch (Exception error) when (error is not OperationCanceledException) { return null; }
    }

    public bool TranslatesTogether => true;

    /// <summary>
    /// "Ekranı çevir": birbirinden bağımsız parçalar (menü satırı, görev yazısı...) tek istekte, aynı sırada çevrilir.
    /// Parça başına istek gitseydi kalabalık bir ekran Gemini'nin dakikalık hakkını (15) ilk saniyelerde bitirir, kalan
    /// parçalar yerel çeviriye düşerdi; yerel model kurulu değilse ekranın hiçbir yazısı çevrilmezdi. Bu tek istek
    /// kullanıcının tuşa basmasıyla gider: ortak hak o an bitmiş olsa da gönderilir (hakkı sayılır). Hata ya da dakikalık
    /// sınırda parçalar yerel çeviriyle çevrilir; o da yoksa hata yukarı çıkar ve ekranda gösterilir (Mac ile aynı).
    /// </summary>
    public async Task<IReadOnlyList<string>> TranslateAllAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(texts);
        var game = _game?.Invoke()?.Trim();
        var results = texts.Select(text => _cache.TryGet(CacheKey(text, game), out var known) ? known : null).ToArray();
        var missing = Enumerable.Range(0, texts.Count).Where(i => results[i] is null).ToList();
        var failed = DateTimeOffset.UtcNow < _pausedUntil;
        for (var start = 0; start < missing.Count && !failed; start += ScreenBatch)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var chunk = missing.Skip(start).Take(ScreenBatch).ToList();
            _budget?.TryTake();
            LastLineWasRateLimited = false;
            try
            {
                var sentences = chunk.Select(i => texts[i]).ToList();
                using var request = AiRequest.Build(Provider, _key, Model, sentences, [], game, Server, maxOutputTokens: AiRequest.ScreenOutputTokens, target: Target);
                using var response = await _screenHttp.SendAsync(request, cancellationToken).ConfigureAwait(false);
                var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
                if (!response.IsSuccessStatusCode)
                {
                    if (AiRequest.RateLimit(response.StatusCode, body) is { } limit) throw new AiRateLimitedException(limit);
                    throw new AiException(AiRequest.Failure(response.StatusCode, body));
                }
                var translated = AiRequest.Translations(AiRequest.Text(Provider, body), sentences.Count);
                Report(null);
                for (var i = 0; i < chunk.Count; i++)
                {
                    results[chunk[i]] = translated[i];
                    _cache.Store(CacheKey(texts[chunk[i]], game), translated[i]);
                }
            }
            catch (AiRateLimitedException limited) when (!cancellationToken.IsCancellationRequested)
            {
                if (limited.Limit.RequestsPerMinute is { } perMinute) _budget?.Lower(perMinute);
                var pause = limited.Limit.RetryAfter is { } retry && retry < RateLimitPause ? retry : RateLimitPause;
                if (pause < TimeSpan.FromSeconds(1)) pause = TimeSpan.FromSeconds(1);
                LastLineWasRateLimited = true;
                _pausedUntil = DateTimeOffset.UtcNow + pause;
                failed = true;
            }
            catch (Exception error) when (error is HttpRequestException or TaskCanceledException or AiException
                                          && !cancellationToken.IsCancellationRequested)
            {
                Report(error is AiException ai ? ai.State : OnlineKeyState.Unreachable);
                _pausedUntil = DateTimeOffset.UtcNow + RetryAfter;
                failed = true;
            }
        }
        for (var i = 0; i < texts.Count; i++)
        {
            if (results[i] is not null) continue;
            cancellationToken.ThrowIfCancellationRequested();
            results[i] = await FallbackAsync(texts[i], cancellationToken).ConfigureAwait(false);
        }
        return [.. results.Select(result => result ?? "")];
    }

    public IReadOnlyList<SpokenLine> SpokenLines(string text)
    {
        var game = _game?.Invoke()?.Trim();
        return _speech.TryGetValue(CacheKey(text, game), out var lines) ? lines
            : SpeechScript.FromCache(text, _cache, part => CacheKey(part, game)) is { Count: > 0 } cached ? cached
            : _fallback?.SpokenLines(text) ?? [];
    }

    private List<AiContextLine> Context()
    {
        lock (_recent) return [.. _recent];
    }

    private void Shown(string text)
    {
        lock (_recent)
        {
            // Aynı satır yeniden okunduysa bağlam tekrarla dolmasın.
            if (_recent.Count > 0 && _recent[^1].Source == text) return;
            _recent.Add(new AiContextLine(text));
            if (_recent.Count > ContextLines) _recent.RemoveAt(0);
        }
    }

    /// <summary>Gösterilen satırın çevirisi sonraki satırların bağlamına girer.</summary>
    private string Remember(string translation, string text)
    {
        lock (_recent)
        {
            var index = _recent.FindLastIndex(line => line.Source == text);
            if (index >= 0) _recent[index] = _recent[index] with { Translation = translation };
        }
        return translation;
    }

    private void Report(OnlineKeyState? state)
    {
        if (_failure == state) return;
        _failure = state;
        FailureChanged?.Invoke(state);
    }

    private async Task<string> FallbackAsync(string text, CancellationToken cancellationToken) =>
        _fallback is null ? throw new TranslatorException(TranslatorStatus.NeedsDownload)
            : await _fallback.TranslateAsync(text, cancellationToken).ConfigureAwait(false);

    private async Task<string[]> RequestAsync(List<string> sentences, List<AiContextLine> context, string? game, CancellationToken cancellationToken)
    {
        using var request = AiRequest.Build(Provider, _key, Model, sentences, context, game, Server, target: Target);
        using var response = await _http.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            if (AiRequest.RateLimit(response.StatusCode, body) is { } limit) throw new AiRateLimitedException(limit);
            throw new AiException(AiRequest.Failure(response.StatusCode, body));
        }
        return AiRequest.Translations(AiRequest.Text(Provider, body), sentences.Count);
    }

    /// <summary>
    /// Ayarlardaki "Dene" ve "Bağlantıyı dene": örnek satırı çevirir; çeviri ya da hatanın türü döner. Yerel modelde
    /// anahtar isteğe bağlıdır ve model belleğe yüklenirken uzun beklenir.
    /// </summary>
    public static async Task<AiTestResult> TestAsync(AiProvider provider, string key, string? model, HttpClient? http = null,
                                                     CancellationToken cancellationToken = default, LocalAiServer? server = null)
    {
        key = key.Trim();
        if (key.Length == 0 && !provider.IsLocal()) return new(OnlineKeyState.Invalid);
        http ??= provider.IsLocal() ? LocalTestClient.Value : SharedClient.Value;
        // Deneme tek istektir; çeviri hattının dakikalık hakkından yemez.
        var translator = new AiTranslator(provider, key, model, new FailingTranslator(), http, budget: new RequestBudget(int.MaxValue),
                                          server: server);
        try
        {
            return new(OnlineKeyState.Valid, await translator.TranslateAsync(Sample, cancellationToken).ConfigureAwait(false));
        }
        catch (FailedException)
        {
            // Dakikalık sınıra takıldıysa anahtar geçerlidir ama şu an sınırdadır.
            return new(translator.LastError ?? (translator.LastLineWasRateLimited ? OnlineKeyState.QuotaExceeded : OnlineKeyState.Unreachable));
        }
    }

    /// <summary>Denemede yerel çeviriye düşülmez; hata olduğu gibi gösterilir.</summary>
    private sealed class FailingTranslator : ITextTranslator
    {
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default) => throw new FailedException();
    }

    private sealed class FailedException : Exception;
}

/// <summary>
/// Nino: çeviri için eğitilmiş yerel modeller (TranslateGemma, MiLMMT) Nino'nun JSON dizili isteğini değil, kendi kısa
/// kalıplarını ister. Önceki altyazılar aynı kalıpta soru-cevap çiftleri halinde gider; cümleler satır satır (Mac ile aynı).
/// </summary>
public static class TranslationModelPrompt
{
    public static JsonArray? Messages(string model, IReadOnlyList<string> sentences, IReadOnlyList<AiContextLine> context,
                                      string target = "tr")
    {
        Func<string, string> prompt;
        if (TranslateGemma.Matches(model)) prompt = text => TranslateGemma.Prompt(text, target);
        else if (MiLMMT.Matches(model)) prompt = text => MiLMMT.Prompt(text, target);
        else return null;
        var messages = new JsonArray();
        foreach (var line in context)
        {
            if (line.Translation is null) continue;
            messages.Add(new JsonObject { ["role"] = "user", ["content"] = prompt(line.Source) });
            messages.Add(new JsonObject { ["role"] = "assistant", ["content"] = line.Translation });
        }
        var text = string.Join("\n", sentences.Select(s => s.Replace("\n", " ")));
        messages.Add(new JsonObject { ["role"] = "user", ["content"] = prompt(text) });
        return messages;
    }
}

/// <summary>Xiaomi'nin çeviri modeli MiLMMT-46 (huggingface.co/xiaomi-research/MiLMMT-46-4B-v1.0); kalıp model kartındaki gibi.</summary>
public static class MiLMMT
{
    public static bool Matches(string model) => model.Contains("milmmt", StringComparison.OrdinalIgnoreCase);

    public static string Prompt(string text, string target = "tr")
    {
        var language = TargetLanguage.EnglishName(target);
        return $"Translate this from English to {language}:\nEnglish: {text}\n{language}:";
    }
}

/// <summary>
/// Google'ın çeviri modeli TranslateGemma (ollama.com/library/translategemma, "Prompt Format"; metinden önce iki boş satır).
/// </summary>
public static class TranslateGemma
{
    public static bool Matches(string model) => model.Contains("translategemma", StringComparison.OrdinalIgnoreCase);

    public static string Prompt(string text, string target = "tr")
    {
        var language = TargetLanguage.EnglishName(target);
        var code = TargetLanguage.Code(target);
        return $"You are a professional English (en) to {language} ({code}) translator. Your goal is to accurately convey the meaning " +
            $"and nuances of the original English text while adhering to {language} grammar, vocabulary, and cultural " +
            $"sensitivities. Produce only the {language} translation, without any additional explanations or commentary. " +
            $"Please translate the following English text into {language}:\n\n\n" + text;
    }
}
