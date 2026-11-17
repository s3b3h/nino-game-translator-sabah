// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import com.couchsubs.mobile.core.SubtitleSegmenter
import com.couchsubs.mobile.core.TargetLanguage
import com.couchsubs.mobile.core.TextMatch
import com.couchsubs.mobile.core.TextTranslator
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale

/** Çevrimiçi anahtarın durumu (ayarlardaki "Dene" ve ana ekrandaki uyarı için). */
enum class OnlineKeyState { VALID, INVALID, QUOTA_EXCEEDED, MODEL_REJECTED, UNREACHABLE }

class OnlineException(val state: OnlineKeyState) : IOException("online translation failed: $state")

/**
 * Hizmetin bildirdiği dakikalık istek sınırı aşımı (429; Windows: AiRateLimit). [retryAfterMs]: hizmetin önerdiği
 * bekleme ("retryDelay"), [requestsPerMinute]: bildirdiği dakikalık istek sınırı ("quotaValue"); yoksa null.
 */
data class AiRateLimit(val retryAfterMs: Long? = null, val requestsPerMinute: Int? = null)

/** Dakikalık sınır aşıldı: gün sınırından farklı olarak kısa sürer, kullanıcıya hata gösterilmez. */
class AiRateLimitedException(val limit: AiRateLimit) : IOException("rate limited")

/** Yapay zekâ hizmetleri (Windows: AiProvider, Mac: AIProvider). */
enum class AiProvider(val id: String, val displayName: String) {
    GEMINI("gemini", "Gemini"), OPENAI("openai", "OpenAI"), CLAUDE("claude", "Claude");
}

/** Çevrimiçi motorun yapay zekâ hizmeti (DeepL ve ücretsiz motorda null). */
val com.couchsubs.mobile.settings.EngineChoice.aiProvider: AiProvider?
    get() = when (this) {
        com.couchsubs.mobile.settings.EngineChoice.GEMINI -> AiProvider.GEMINI
        com.couchsubs.mobile.settings.EngineChoice.OPENAI -> AiProvider.OPENAI
        com.couchsubs.mobile.settings.EngineChoice.CLAUDE -> AiProvider.CLAUDE
        else -> null
    }

/** Listedeki bir model ve onunla gönderilen ayarlar (ortak ai-models.json). */
data class AiModel(
    val id: String,
    val label: String,
    val effort: String? = null,
    val thinking: String? = null,
    val freeTier: Boolean = false,
    val requestsPerMinute: Int? = null,
) {
    companion object {
        /** Uygulamayla gelen ai-models.json; okunamazsa boş. */
        fun load(context: android.content.Context): Map<String, List<AiModel>> = try {
            parse(context.assets.open("ai-models.json").use { String(it.readBytes(), Charsets.UTF_8) })
        } catch (error: Exception) {
            emptyMap()
        }

        /** ai-models.json: hizmet adı → modeller; "_comment" gibi dizi olmayan alanlar atlanır. */
        fun parse(json: String): Map<String, List<AiModel>> {
            val root = JSONObject(json)
            val result = mutableMapOf<String, List<AiModel>>()
            for (name in root.keys()) {
                val array = root.optJSONArray(name) ?: continue
                val models = (0 until array.length()).mapNotNull { array.optJSONObject(it) }.map { item ->
                    AiModel(
                        item.getString("id"), item.getString("label"),
                        item.optString("effort").ifEmpty { null }, item.optString("thinking").ifEmpty { null },
                        item.optBoolean("freeTier", false),
                        if (item.has("requestsPerMinute")) item.optInt("requestsPerMinute") else null,
                    )
                }
                if (models.isNotEmpty()) result[name] = models
            }
            return result
        }
    }
}

/**
 * Anahtar kaydedilmeden önce denenir (Mac/iPhone: DeepLTranslator.check ve AITranslationCore.test ile aynı kural):
 * DeepL'de kullanım sorgulanır, yapay zekâ hizmetinde örnek bir satır çevrilir. Geçerli, kotası dolmuş ya da modeli
 * reddedilen anahtar kabul edilir (anahtar doğrudur); geçersiz ya da ulaşılamayan anahtar kaydedilmez.
 */
object KeyCheck {
    /** Denemede çevrilen örnek satır (iPhone ile aynı). */
    const val SAMPLE = "KRATOS: We go now. Stay close, boy."

    fun accepted(state: OnlineKeyState) =
        state == OnlineKeyState.VALID || state == OnlineKeyState.QUOTA_EXCEEDED || state == OnlineKeyState.MODEL_REJECTED

    /** DeepL: /usage; bu ay kota dolduysa QUOTA_EXCEEDED. Bloklar. */
    fun deepL(key: String, http: Http = Http.Default): OnlineKeyState {
        val trimmed = key.trim()
        if (trimmed.isEmpty()) return OnlineKeyState.INVALID
        return try {
            val (status, body) = http.send("GET", DeepLTranslator.baseUrl(trimmed) + "usage",
                mapOf("Authorization" to "DeepL-Auth-Key $trimmed"), null, 6000)
            if (status !in 200..299) return DeepLTranslator.failure(status)
            val usage = JSONObject(body)
            val count = usage.optLong("character_count", 0)
            val limit = usage.optLong("character_limit", 0)
            if (limit > 0 && count >= limit) OnlineKeyState.QUOTA_EXCEEDED else OnlineKeyState.VALID
        } catch (error: IOException) {
            OnlineKeyState.UNREACHABLE
        } catch (error: JSONException) {
            OnlineKeyState.UNREACHABLE
        }
    }

    /** Yapay zekâ hizmeti: örnek satır seçilen modelle çevrilir. Bloklar. */
    fun ai(provider: AiProvider, key: String, model: AiModel, http: Http = Http.Default): OnlineKeyState {
        if (key.isBlank()) return OnlineKeyState.INVALID
        return try {
            val request = AiRequest.build(provider, key, model, listOf(SAMPLE), emptyList())
            val (status, body) = http.send("POST", request.url, request.headers, request.body, 15000)
            if (status !in 200..299) return AiRequest.failure(status, body)
            AiRequest.translations(AiRequest.text(provider, body), 1)
            OnlineKeyState.VALID
        } catch (error: OnlineException) {
            error.state
        } catch (error: IOException) {
            OnlineKeyState.UNREACHABLE
        } catch (error: JSONException) {
            OnlineKeyState.UNREACHABLE
        }
    }
}

/** Basit HTTP: gövde gönderir, durum kodu ve yanıt gövdesi döner (testlerde sahtesi verilir). */
fun interface Http {
    fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutMs: Int): Pair<Int, String>

    companion object {
        val Default = Http { method, url, headers, body, timeoutMs ->
            val connection = URL(url).openConnection() as HttpURLConnection
            try {
                connection.requestMethod = method
                connection.connectTimeout = timeoutMs
                connection.readTimeout = timeoutMs
                headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
                if (body != null) {
                    connection.doOutput = true
                    connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                }
                val status = connection.responseCode
                val stream = if (status >= 400) connection.errorStream else connection.inputStream
                status to (stream?.use { String(it.readBytes(), Charsets.UTF_8) } ?: "")
            } finally {
                connection.disconnect()
            }
        }
    }
}

/**
 * Cümle cümle çeviren çevrimiçi motorların ortak düzeni (Windows: DeepLTranslator ve AiTranslator): konuşmacı
 * etiketleri çevrilmez, önbellekteki cümleler yeniden gönderilmez, hata olursa o satır yerel motorla çevrilir ve bir
 * dakika hizmet denenmez. Dakikalık istek sınırında ([budget] bitti ya da hizmet 429 ile dakikalık sınırı bildirdi) hata
 * gösterilmez: satır sessizce yerel motorla çevrilir, hizmet en çok 20 saniye dinlenir (Windows ve iPhone ile aynı).
 */
abstract class SentenceTranslator<C>(
    private val local: TextTranslator?,
    protected val cache: TranslationCache = TranslationCache(),
    private val clock: () -> Long = System::currentTimeMillis,
    private val budget: RequestBudget? = null,
) : TextTranslator {
    companion object {
        /** Hata sonrası bu süre hizmet denenmez. */
        const val RETRY_AFTER_MS = 60_000L
        /** Dakikalık sınır aşılınca en çok bu kadar beklenir (hizmet bekleme önermezse de bu kadar). */
        const val RATE_LIMIT_PAUSE_MS = 20_000L
    }

    private val names = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private var pausedUntil = 0L

    @Volatile var lastError: OnlineKeyState? = null
        private set
    @Volatile var onFailureChanged: ((OnlineKeyState?) -> Unit)? = null

    /** [sentences] cümlelerini aynı sırada çevirir ([game]: oynanan oyun, yapay zekâya bağlam); hata durumunda
     *  [OnlineException] ya da [IOException]. */
    protected abstract fun request(sentences: List<String>, context: C, game: String?): List<String>

    /** Bu satırdan önce gösterilenler (bağlam); satırı da sonrakilerin bağlamına ekler. */
    protected abstract fun context(text: String): C

    protected open fun remember(text: String, translation: String) {}

    /** Önbellek anahtarı (DeepL'de sözlük terimi içeren satıra sözlüğün izi girer; yapay zekâda oyun adı). */
    protected open fun cacheKey(text: String, game: String?): String = text

    /** Oynanan oyun (yalnız yapay zekâ kullanır); bilinmiyorsa null. */
    protected open fun game(): String? = null

    /** Büyük harfle kalacak ek sözcükler (sözlükteki adlar). */
    protected open val extraNames: Set<String> get() = emptySet()

    override fun translate(text: String): String {
        // Arama, istek ve kayıt aynı oyunla yapılır; oyun işlem sırasında değişse de sonuç başka oyuna yazılmaz.
        val game = game()
        val context = context(text)
        cache.get(cacheKey(text, game))?.let { return it.also { remember(text, it) } }
        val pieces = SubtitleSegmenter.split(text)
        for (name in pieces.mapNotNull(SubtitleSegmenter::labelName))
            name.split(' ').filter { it.length >= 2 }.forEach { names.add(it.lowercase(Locale.ROOT)) }
        val known = names.toSet() + extraNames
        val translations = pieces.map { if (it.translate) cache.get(cacheKey(it.text, game)) else null }.toMutableList()
        val missing = pieces.indices.filter { pieces[it].translate && translations[it] == null }
        val sources = missing.map { SubtitleSegmenter.normalizeCase(pieces[it].text, known) }
        // Hizmetin beklemesi yalnız eksik çeviriler içindir; önbellekteki parçalar yerel motor istemez.
        if (sources.isNotEmpty() && clock() < pausedUntil) return fallback(text)
        // Dakikalık hak bittiyse istek gönderilmez; satır sessizce yerel çeviriyle çevrilir (hata değildir).
        if (sources.isNotEmpty() && budget?.take() == false) return fallback(text)
        val translated = try {
            if (sources.isEmpty()) emptyList() else request(sources, context, game).also { report(null) }
        } catch (error: AiRateLimitedException) {
            rateLimited(error.limit)
            return fallback(text)
        } catch (error: IOException) {
            report((error as? OnlineException)?.state ?: OnlineKeyState.UNREACHABLE)
            pausedUntil = clock() + RETRY_AFTER_MS
            return fallback(text)
        } catch (error: JSONException) {
            report(OnlineKeyState.UNREACHABLE)
            pausedUntil = clock() + RETRY_AFTER_MS
            return fallback(text)
        }
        var local = false
        for ((i, index) in missing.withIndex()) {
            val piece = pieces[index].text
            if (retriesEcho && isEcho(piece, translated[i])) {
                val retried = retryEcho(piece)
                if (retried != null && !isEcho(piece, retried)) {
                    // Yerel çeviri bu motorun önbelleğine yazılmaz.
                    translations[index] = retried
                    local = true
                    continue
                }
            }
            translations[index] = translated[i]
            cache.store(cacheKey(piece, game), translated[i])
        }
        val result = pieces.indices.joinToString("") { translations[it] ?: pieces[it].text }
        if (!local) cache.store(cacheKey(text, game), result)
        remember(text, result)
        return result
    }

    /**
     * Çevirmeden geri verilen cümle yerel motorla yeniden denensin mi (yalnız yapay zekâ; Windows ve iPhone'da da
     * yalnız AiTranslator/AITranslationCore yapar).
     */
    protected open val retriesEcho: Boolean get() = false

    /**
     * Model cümleyi çevirmeden geri verdi mi (hattın "zaten hedef dilde" eşiğiyle aynı). Küçük yerel modeller İngilizce
     * cümleyi sık sık olduğu gibi döndürüyor ("You think I'm on the run?"); hat bunu Türkçe sanıp hiç göstermiyor,
     * önbellek de öyle saklıyordu (#245).
     */
    private fun isEcho(source: String, translation: String) =
        TextMatch.isSimilar(TextMatch.normalize(source), TextMatch.normalize(translation), 0.90)

    /**
     * Geri verilen cümle cihaz üstü çeviriyle bir kez daha denenir; o da aynı kalırsa (ad, konsolun Türkçe menüsü)
     * çevrilecek bir şey yoktur ve modelin yanıtı önbelleğe yazılır. Yerel çeviri yoksa ya da hata verirse null.
     */
    private fun retryEcho(text: String): String? =
        try {
            local?.translate(text)
        } catch (error: InterruptedException) {
            throw error
        } catch (error: Exception) {
            null
        }

    private fun fallback(text: String): String =
        (local ?: throw IOException("no local translator")).translate(text).also { remember(text, it) }

    /** Toplu çeviride ("ekranı çevir") hizmet şu an dinleniyor mu (son hatadan sonra bir dakika denenmez). */
    protected fun paused(): Boolean = clock() < pausedUntil

    /** Toplu çevirinin tek isteği kullanıcının tuşa basmasıyla gider: hak bitmiş olsa da gönderilir, ama sayılır. */
    protected fun countRequest() {
        budget?.take()
    }

    /** Toplu çeviri hizmetten döndü: hata durumu temizlenir. */
    protected fun succeeded() = report(null)

    /** Toplu çeviri hata verdi: hata bildirilir ve bir dakika hizmet denenmez (dakikalık sınırda uyarısız, kısa). */
    protected fun failed(error: Exception) {
        if (error is AiRateLimitedException) return rateLimited(error.limit)
        report((error as? OnlineException)?.state ?: OnlineKeyState.UNREACHABLE)
        pausedUntil = clock() + RETRY_AFTER_MS
    }

    /**
     * Dakikalık sınır: hizmetin önerdiği kadar (en az 1, en çok 20 saniye) beklenir, ana ekranda uyarı çıkmaz; hizmet
     * daha düşük sınır bildirdiyse ona inilir.
     */
    private fun rateLimited(limit: AiRateLimit) {
        limit.requestsPerMinute?.let { budget?.lower(it) }
        pausedUntil = clock() + (limit.retryAfterMs ?: RATE_LIMIT_PAUSE_MS).coerceIn(1_000L, RATE_LIMIT_PAUSE_MS)
    }

    /** Hizmet yanıt vermeyen parçalar yerel motorla çevrilir; yerel motor yoksa hata yukarı çıkar. */
    protected fun localTranslation(text: String): String =
        (local ?: throw IOException("no local translator")).translate(text)

    private fun report(state: OnlineKeyState?) {
        if (lastError == state) return
        lastError = state
        onFailureChanged?.invoke(state)
    }
}

/**
 * Kullanıcının DeepL anahtarıyla çeviri; son 3 satır `context` olarak gider (ücretlendirilmez). Sözlükteki adlar ve
 * terimler etiketle korunur ([DeepLMarkup], iPhone ile aynı).
 */
class DeepLTranslator(
    key: String,
    fallback: TextTranslator?,
    private val http: Http = Http.Default,
    cache: TranslationCache = TranslationCache(),
    private val glossary: Glossary = Glossary.Empty,
    /** Nino: çeviri dili ("tr", "ar", "id"…). Sözlük Türkçeye özgüdür; öbür dillerde boş verilir. */
    private val target: String = "tr",
) : SentenceTranslator<String>(fallback, cache) {
    private val key = key.trim()
    private val recent = ArrayDeque<String>()

    override fun cacheKey(text: String, game: String?) = DeepLMarkup.cacheKey(text, glossary)
    override val extraNames: Set<String> get() = glossary.capitalWords

    companion object {
        /** Kalıcı önbellek dosyasındaki motor adı (iPhone ile aynı). */
        const val ENGINE_ID = "deepl"

        /** Ücretsiz anahtarlar ":fx" ile biter ve ayrı adrese gider. */
        fun baseUrl(key: String) = if (key.trim().endsWith(":fx")) "https://api-free.deepl.com/v2/" else "https://api.deepl.com/v2/"

        fun body(sentences: List<String>, context: String?, tagged: Boolean = false, target: String = "tr"): String = JSONObject()
            .put("text", JSONArray(sentences))
            .put("source_lang", "EN")
            .put("target_lang", TargetLanguage.code(target).uppercase(Locale.ROOT))
            .apply { if (!context.isNullOrEmpty()) put("context", context) }
            // Oyun konuşması: "siz" değil "sen" (yalnız Türkçede).
            .apply { if (TargetLanguage.isTurkish(target)) put("formality", "prefer_less") }
            .put("preserve_formatting", true)
            .apply {
                // Etiketli terimler çevrilmez.
                if (tagged) put("tag_handling", "xml").put("ignore_tags", JSONArray().put(DeepLMarkup.TAG))
            }
            .toString()

        fun failure(status: Int) = when (status) {
            401, 403 -> OnlineKeyState.INVALID
            456 -> OnlineKeyState.QUOTA_EXCEEDED
            else -> OnlineKeyState.UNREACHABLE
        }
    }

    override fun context(text: String): String = synchronized(recent) {
        val context = recent.joinToString("\n")
        if (recent.lastOrNull() != text) {
            recent.addLast(text)
            if (recent.size > 3) recent.removeFirst()
        }
        context
    }

    override fun request(sentences: List<String>, context: String, game: String?): List<String> {
        // Sözlükteki adlar etiketle korunur; etiket varsa istek XML olarak gider, diğer cümleler de kaçırılır.
        val wrapped = sentences.map { DeepLMarkup.wrap(it, glossary) }
        val tagged = wrapped.any { it != null }
        val sources = if (tagged) sentences.indices.map { wrapped[it] ?: DeepLMarkup.escape(sentences[it]) } else sentences
        val (status, response) = http.send(
            "POST", baseUrl(key) + "translate",
            mapOf("Authorization" to "DeepL-Auth-Key $key", "Content-Type" to "application/json"), body(sources, context, tagged, target), 4000,
        )
        if (status !in 200..299) throw OnlineException(failure(status))
        val list = JSONObject(response).optJSONArray("translations") ?: throw OnlineException(OnlineKeyState.UNREACHABLE)
        if (list.length() != sentences.size) throw OnlineException(OnlineKeyState.UNREACHABLE)
        val reply = (0 until list.length()).map { list.getJSONObject(it).getString("text") }
        return if (tagged) reply.map(DeepLMarkup::unwrap) else reply
    }
}

/** Hizmete giden istek: adres, başlıklar ve gövde (Windows: AiRequest.Build, aynı biçim). */
data class AiHttpRequest(val url: String, val headers: Map<String, String>, val body: String)

object AiRequest {
    const val MAX_OUTPUT_TOKENS = 1024
    /** "Ekranı çevir"in tek isteğinde çıktı sınırı: ekrandaki bütün yazılar birlikte döner (Mac/iPhone ile aynı). */
    const val SCREEN_OUTPUT_TOKENS = 8192

    const val SYSTEM_PROMPT =
        "You translate English video game subtitles into natural, spoken Turkish, the way people really talk. " +
            "Characters address each other informally (use \"sen\", not \"siz\") unless the line is clearly formal. " +
            "Keep character names, place names and speaker labels such as \"ATREUS:\" exactly as they are. " +
            "Keep line breaks. Keep the meaning and tone; do not add or leave out anything. " +
            "Reply with only the translation, no explanations, notes or quotes."

    /** Nino: Arapça hedefin yönergesi (Mac: AIRequest.arabicSystemPrompt ile aynı). */
    const val ARABIC_SYSTEM_PROMPT =
        "You translate English video game subtitles into clear, natural Modern Standard Arabic, the way good Arabic " +
            "game subtitles read. Keep it short and easy to read on screen; use a natural spoken tone for dialogue. " +
            "Keep character names, place names and speaker labels such as \"ATREUS:\" exactly as they are, in Latin letters. " +
            "Keep line breaks. Keep the meaning and tone; do not add or leave out anything. " +
            "Use Arabic punctuation (، ؟ ؛) and Western digits. Keep controller button symbols (✕ ○ △ □, L1, R2) unchanged. " +
            "Reply with only the translation, no explanations, notes or quotes."

    /** Nino: öbür dillerin (Hintçe, Endonezce, Tayca…) yönergesi (Mac: AIRequest.genericSystemPrompt ile aynı). */
    fun genericSystemPrompt(language: String): String =
        "You translate English video game subtitles into clear, natural $language, the way good $language " +
            "game subtitles read. Keep it short and easy to read on screen; use a natural spoken tone for dialogue. " +
            "Keep character names, place names and speaker labels such as \"ATREUS:\" exactly as they are, in Latin letters. " +
            "Keep line breaks. Keep the meaning and tone; do not add or leave out anything. " +
            "Keep controller button symbols (✕ ○ △ □, L1, R2) unchanged. " +
            "Reply with only the translation, no explanations, notes or quotes."

    fun systemPrompt(target: String): String = when {
        TargetLanguage.isTurkish(target) -> SYSTEM_PROMPT
        TargetLanguage.isArabic(target) -> ARABIC_SYSTEM_PROMPT
        else -> genericSystemPrompt(TargetLanguage.englishName(target))
    }

    /** Bağlam satırı: daha önce gösterilmiş İngilizce ve (biliniyorsa) çevirisi. */
    data class ContextLine(val source: String, val translation: String? = null)

    fun userMessage(sentences: List<String>, context: List<ContextLine>, game: String? = null, target: String = "tr"): String {
        val language = TargetLanguage.englishName(target)
        val parts = mutableListOf<String>()
        if (!game.isNullOrEmpty()) parts.add("Game: $game")
        if (context.isNotEmpty()) {
            val lines = mutableListOf("Previous subtitles, for context only (do not translate them again):")
            for (line in context) {
                lines.add("English: ${line.source}")
                line.translation?.let { lines.add("$language: $it") }
            }
            parts.add(lines.joinToString("\n"))
        }
        val list = JSONArray(sentences).toString()
        parts.add("Translate each string in this JSON array into $language. Reply with only a JSON array of ${sentences.size} " +
            "$language strings in the same order.\n$list")
        return parts.joinToString("\n\n")
    }

    fun build(
        provider: AiProvider, key: String, model: AiModel, sentences: List<String>, context: List<ContextLine>,
        maxOutputTokens: Int = MAX_OUTPUT_TOKENS, game: String? = null, target: String = "tr",
    ): AiHttpRequest {
        val trimmed = key.trim()
        val user = userMessage(sentences, context, game, target)
        val SYSTEM_PROMPT = systemPrompt(target)
        return when (provider) {
            AiProvider.GEMINI -> {
                val config = JSONObject().put("maxOutputTokens", maxOutputTokens)
                model.thinking?.let { config.put("thinkingConfig", JSONObject().put("thinkingLevel", it)) }
                val body = JSONObject()
                    .put("systemInstruction", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", SYSTEM_PROMPT))))
                    .put("contents", JSONArray().put(JSONObject().put("role", "user").put("parts", JSONArray().put(JSONObject().put("text", user)))))
                    .put("generationConfig", config)
                AiHttpRequest(
                    "https://generativelanguage.googleapis.com/v1beta/models/${URLEncoder.encode(model.id, "UTF-8")}:generateContent",
                    mapOf("x-goog-api-key" to trimmed, "Content-Type" to "application/json"), body.toString(),
                )
            }
            AiProvider.OPENAI -> {
                val body = JSONObject()
                    .put("model", model.id)
                    .put("messages", JSONArray()
                        .put(JSONObject().put("role", "developer").put("content", SYSTEM_PROMPT))
                        .put(JSONObject().put("role", "user").put("content", user)))
                    .put("max_completion_tokens", maxOutputTokens)
                model.effort?.let { body.put("reasoning_effort", it) }
                AiHttpRequest("https://api.openai.com/v1/chat/completions",
                    mapOf("Authorization" to "Bearer $trimmed", "Content-Type" to "application/json"), body.toString())
            }
            AiProvider.CLAUDE -> {
                val body = JSONObject()
                    .put("model", model.id)
                    .put("max_tokens", maxOutputTokens)
                    .put("system", SYSTEM_PROMPT)
                    .put("messages", JSONArray().put(JSONObject().put("role", "user").put("content", user)))
                model.effort?.let { body.put("output_config", JSONObject().put("effort", it)) }
                model.thinking?.let { body.put("thinking", JSONObject().put("type", it)) }
                AiHttpRequest("https://api.anthropic.com/v1/messages",
                    mapOf("x-api-key" to trimmed, "anthropic-version" to "2023-06-01", "Content-Type" to "application/json"), body.toString())
            }
        }
    }

    /** Yanıttaki düz metin (düşünme bölümleri atlanır). */
    fun text(provider: AiProvider, json: String): String {
        val root = try {
            JSONObject(json)
        } catch (error: JSONException) {
            throw OnlineException(OnlineKeyState.UNREACHABLE)
        }
        val text = when (provider) {
            AiProvider.GEMINI -> root.optJSONArray("candidates")?.optJSONObject(0)?.optJSONObject("content")?.optJSONArray("parts")
                ?.let { parts -> (0 until parts.length()).mapNotNull { parts.optJSONObject(it) }.filter { !it.optBoolean("thought", false) }
                    .joinToString("") { it.optString("text") } }
            AiProvider.OPENAI -> root.optJSONArray("choices")?.optJSONObject(0)?.optJSONObject("message")?.optString("content")
            AiProvider.CLAUDE -> root.optJSONArray("content")?.let { blocks ->
                (0 until blocks.length()).mapNotNull { blocks.optJSONObject(it) }.filter { it.optString("type") == "text" }
                    .joinToString("") { it.optString("text") }
            }
        }
        if (text.isNullOrBlank()) throw OnlineException(OnlineKeyState.UNREACHABLE)
        return text
    }

    /** Yanıttaki JSON dizisi; tek cümlede model diziyi unutup düz metin dönerse o metin alınır. */
    fun translations(text: String, count: Int): List<String> {
        var trimmed = text.trim()
        // Düşünen modeller yanıtın başına <think>…</think> koyar; yalnız sonrası alınır.
        val thought = trimmed.lastIndexOf("</think>")
        if (thought >= 0) trimmed = trimmed.substring(thought + "</think>".length).trim()
        trimmed = stripControlTokens(trimmed)
        if (trimmed.startsWith("```")) trimmed = trimmed.split('\n').drop(1).filter { !it.startsWith("```") }.joinToString("\n").trim()
        val start = trimmed.indexOf('[')
        val end = trimmed.lastIndexOf(']')
        // org.json tırnaksız öğeleri de kabul eder ("[gülüyor]" → "gülüyor", "[Evet, efendim.]" → iki öğe); yalnız
        // ilk öğesi tırnaklı (ya da boş) dizi JSON sayılır, gerisi tırnaksız dizi kuralıyla okunur.
        val quoted = start >= 0 && trimmed.substring(start + 1).trimStart().let { it.startsWith('"') || it.startsWith(']') }
        if (quoted && end > start) {
            try {
                val array = JSONArray(withoutTrailingComma(trimmed.substring(start, end + 1)))
                if ((0 until array.length()).all { array.opt(it) is String }) {
                    if (array.length() != count) throw OnlineException(OnlineKeyState.UNREACHABLE)
                    return (0 until array.length()).map { array.getString(it).trim() }
                }
            } catch (error: JSONException) {
                // Dizi değil; düz metin olabilir.
            }
        }
        unquotedList(trimmed, count)?.let { return it }
        if (count != 1) throw OnlineException(OnlineKeyState.UNREACHABLE)
        return listOf(trimmed.trim('"', '“', '”'))
    }

    private val controlTokens = Regex("""</?s>|<\|[A-Za-z0-9_]{1,32}\|>|</?(?:start|end)_of_turn>|</?(?:eos|bos|pad)>""")
    private val trailingComma = Regex(""",\s*]$""")

    /**
     * Yerel modellerin metne sızan bitiş/rol işaretleri (`</s>`, `<|im_end|>`, `<|eot_id|>`, `<end_of_turn>` …) ekranda
     * görünmesin; yalnız bu kalıplar silinir, altyazıdaki başka yazılara dokunulmaz.
     */
    fun stripControlTokens(text: String): String = controlTokens.replace(text, "").trim()

    /** `["Bir.", "İki.",]` gibi sondaki fazla virgül JSON'u bozmasın. */
    fun withoutTrailingComma(text: String): String = trailingComma.replace(text, "]")

    /**
     * Tırnaksız dizi: bazı modeller JSON istense de `[Hareket etmemiz lazım.]` ya da `[Satır bir., Satır iki.]` döndürür.
     * Yalnız bütün yanıt köşeli parantez içindeyse ve öğe sayısı tam tutuyorsa alınır; tutmazsa null (her zamanki geri
     * dönüş). Cümle içi virgülde yanlış bölmemek için sıra: satır sonu, cümle sonu işaretinden (. ! ? … ") sonra gelen
     * virgül, en son düz virgül (Mac ve Windows ile aynı).
     */
    internal fun unquotedList(text: String, count: Int): List<String>? {
        if (count < 1 || text.length < 2 || !text.startsWith('[') || !text.endsWith(']')) return null
        val inner = text.substring(1, text.length - 1)
        fun clean(item: String): String = item.trim().removeSuffix(",").trim().trim('"', '“', '”').trim()
        val candidates = if (count == 1) listOf(listOf(inner)) else listOf(
            inner.split('\n').filter { it.isNotBlank() },
            sentenceSplit(inner),
            inner.split(','),
        )
        for (parts in candidates) {
            val items = parts.map(::clean)
            if (items.size == count && items.none { it.isEmpty() }) return items
        }
        return null
    }

    /** Cümle sonu işaretinden (. ! ? … " ”) hemen sonra gelen virgüllerden böler; işaret öğede kalır. */
    private fun sentenceSplit(text: String): List<String> {
        val parts = mutableListOf<String>()
        var start = 0
        var last: Char? = null
        for (i in text.indices) {
            val c = text[i]
            if (c == ',' && last != null && last in ".!?…\"”") {
                parts.add(text.substring(start, i))
                start = i + 1
            }
            if (!c.isWhitespace()) last = c
        }
        parts.add(text.substring(start))
        return parts
    }

    /**
     * 429 yalnız dakikalık sınırdan geldiyse onun ayrıntısı; gün sınırı, bakiye ya da tanınmayan 429 için null (bunlar
     * QUOTA_EXCEEDED olarak kullanıcıya gösterilir). Gemini'nin hata gövdesinde error.details[] içinde
     * google.rpc.QuotaFailure (violations[].quotaId, ör. "GenerateRequestsPerMinutePerProjectPerModel-FreeTier",
     * quotaValue "15") ve google.rpc.RetryInfo (retryDelay "37s") bulunur (Windows ve iPhone ile aynı).
     */
    fun rateLimit(status: Int, body: String): AiRateLimit? {
        if (status != 429) return null
        val details = try {
            JSONObject(body).optJSONObject("error")?.optJSONArray("details")
        } catch (error: JSONException) {
            null
        } ?: return null
        val items = (0 until details.length()).mapNotNull { details.optJSONObject(it) }
        val violations = items.flatMap { item ->
            item.optJSONArray("violations")?.let { array -> (0 until array.length()).mapNotNull { array.optJSONObject(it) } }
                ?: emptyList()
        }
        val ids = violations.mapNotNull { it.opt("quotaId") as? String }
        // Günlük sınır doldu: dakikalık beklemeyle geçmez, kullanıcı bilmeli.
        if (ids.any { "PerDay" in it } || ids.none { "PerMinute" in it }) return null
        val retry = items.firstNotNullOfOrNull { it.opt("retryDelay") as? String }
            ?.trimEnd('s')?.toDoubleOrNull()?.let { (it * 1000).toLong() }
        // İstek sınırı (token sınırı değil).
        val requests = violations.firstOrNull { (it.opt("quotaId") as? String)?.contains("Requests") == true }
        val perMinute = when (val value = requests?.opt("quotaValue")) {
            is String -> value.toIntOrNull()
            is Number -> value.toInt()
            else -> null
        }?.takeIf { it > 0 }
        return AiRateLimit(retry, perMinute)
    }

    /** Başarısız yanıtın hatası: dakikalık sınırsa [AiRateLimitedException], değilse [OnlineException]. */
    fun error(status: Int, body: String): IOException =
        rateLimit(status, body)?.let(::AiRateLimitedException) ?: OnlineException(failure(status, body))

    fun failure(status: Int, body: String): OnlineKeyState {
        val message = body.lowercase(Locale.ROOT)
        return when {
            status == 401 || status == 403 -> OnlineKeyState.INVALID
            status == 402 || status == 429 -> OnlineKeyState.QUOTA_EXCEEDED
            status == 400 && ("api_key_invalid" in message || "api key not valid" in message) -> OnlineKeyState.INVALID
            status == 400 && ("credit balance" in message || "insufficient_quota" in message) -> OnlineKeyState.QUOTA_EXCEEDED
            status == 400 || status == 404 -> OnlineKeyState.MODEL_REJECTED
            else -> OnlineKeyState.UNREACHABLE
        }
    }
}

/** Kullanıcının Gemini, OpenAI ya da Claude anahtarıyla çeviri; son 3 satır ve çevirileri bağlam olarak gider. */
class AiTranslator(
    private val provider: AiProvider,
    key: String,
    private val model: AiModel,
    fallback: TextTranslator?,
    private val http: Http = Http.Default,
    cache: TranslationCache = TranslationCache(),
    private val playedGame: (() -> String?)? = null,
    clock: () -> Long = System::currentTimeMillis,
    // Dakikalık istek hakkı; null ise modelin uygulama genelindeki ortak hakkı (Google sınırı proje ve model başına
    // sayar; çeviri hattı yeniden kurulsa da hak sıfırlanmaz). Modelin sınırı yoksa hak da yoktur.
    budget: RequestBudget? = null,
    /** Nino: çeviri dili ("tr", "ar", "hi"…); istem buna göre yazılır. */
    private val target: String = "tr",
) : SentenceTranslator<List<AiRequest.ContextLine>>(fallback, cache, clock, budget ?: RequestBudget.shared(provider, model)) {
    companion object {
        /** Kalıcı önbellek dosyasındaki motor adı (iPhone ile aynı: "gemini:<model>"). */
        fun engineId(provider: AiProvider, model: AiModel) = "${provider.id}:${model.id}"

        /** "Ekranı çevir"de bir istekte giden en çok parça; kalabalık ekran birkaç isteğe bölünür (iPhone ile aynı). */
        const val SCREEN_BATCH = 40
        /** "Ekranı çevir"de beklenen en uzun süre: bütün ekranın çevirisi tek yanıtta gelir. */
        const val SCREEN_TIMEOUT_MS = 30_000
    }

    override val translatesTogether: Boolean get() = true

    override val retriesEcho: Boolean get() = true

    /**
     * "Ekranı çevir": birbirinden bağımsız parçalar (menü satırı, görev yazısı...) tek istekte, aynı sırada çevrilir
     * (parça başına istek dakikalık hakkı bitirirdi; Mac/iPhone AITranslationCore.translateAll ile aynı). Önbellekteki
     * parçalar gönderilmez. Hata olursa kalan parçalar yerel motorla çevrilir; o da yoksa hata yukarı çıkar.
     */
    override fun translateAll(texts: List<String>): List<String> {
        val game = game()
        val results = texts.map { cache.get(cacheKey(it, game)) }.toMutableList()
        val missing = texts.indices.filter { results[it] == null }
        var stopped = paused()
        for (chunk in missing.chunked(SCREEN_BATCH)) {
            if (stopped) break
            if (Thread.currentThread().isInterrupted) throw InterruptedException()
            val sentences = chunk.map { texts[it] }
            countRequest()
            try {
                val request = AiRequest.build(provider, key, model, sentences, emptyList(), AiRequest.SCREEN_OUTPUT_TOKENS, game, target)
                val (status, body) = http.send("POST", request.url, request.headers, request.body, SCREEN_TIMEOUT_MS)
                if (status !in 200..299) throw AiRequest.error(status, body)
                val translated = AiRequest.translations(AiRequest.text(provider, body), sentences.size)
                succeeded()
                for ((index, translation) in chunk.zip(translated)) {
                    results[index] = translation
                    cache.store(cacheKey(texts[index], game), translation)
                }
            } catch (error: IOException) {
                failed(error)
                stopped = true
            } catch (error: org.json.JSONException) {
                failed(error)
                stopped = true
            }
        }
        return texts.indices.map { results[it] ?: localTranslation(texts[it]) }
    }

    private val key = key.trim()
    private val recent = ArrayDeque<AiRequest.ContextLine>()

    override fun context(text: String): List<AiRequest.ContextLine> = synchronized(recent) {
        val context = recent.toList()
        if (recent.lastOrNull()?.source != text) {
            recent.addLast(AiRequest.ContextLine(text))
            if (recent.size > 3) recent.removeFirst()
        }
        context
    }

    /** Gösterilen satırın çevirisi sonraki satırların bağlamına girer. */
    override fun remember(text: String, translation: String) {
        synchronized(recent) {
            val index = recent.indexOfLast { it.source == text }
            if (index >= 0) recent[index] = recent[index].copy(translation = translation)
        }
    }

    override fun game(): String? = playedGame?.invoke()?.trim()

    /** Oyun bilinmiyorsa eski kayıtlar geçerlidir; biliniyorsa yalnız o oyunun sonucu kullanılır (Windows ve Mac ile aynı). */
    override fun cacheKey(text: String, game: String?): String = if (game.isNullOrEmpty()) text else "$game\u001f$text"

    override fun request(sentences: List<String>, context: List<AiRequest.ContextLine>, game: String?): List<String> {
        val request = AiRequest.build(provider, key, model, sentences, context, game = game, target = target)
        val (status, body) = http.send("POST", request.url, request.headers, request.body, 5000)
        if (status !in 200..299) throw AiRequest.error(status, body)
        return AiRequest.translations(AiRequest.text(provider, body), sentences.size)
    }
}
