// SPDX-License-Identifier: AGPL-3.0-only
// Nino çeviri havuzu (sunucu: nino-pool/src/translate.js; Mac/iPhone: TranslationPool.swift ile aynı davranış). Oyun
// satırlarının sunucuda Claude ile yapılmış çevirileri:
//   - oyun başlarken o oyunun bütün çevirileri tek seferde, sonra birkaç dakikada bir yalnız değişenler iner;
//   - pakette ve havuzda olmayan satır sunucuya sorulur; sunucu o an çevirir, herkes için saklar.
// Havuzdaki çeviri, hazır paketten sonra ve cihazın kendi çevirisinden önce kullanılır (11 dilin hepsinde).
// Ayarlar'daki ortak havuz kapalıysa hiçbir şey gönderilmez ve indirilmez; yalnız havuz öncelikli oyunlarda (sunucunun
// `poolFirst` listesi, varsayılan GTA 6) satır yine sunucuya sorulur (kullanıcı kararı; bkz. [PoolFirstTranslator]).
package com.couchsubs.mobile.core

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/** Bellekteki çeviriler (anahtar → çeviri). Altyazı hattı eşzamanlı sorduğu için kilitli; diske dil başına yazılır. */
class PoolTranslations {
    private val lock = Any()
    private var texts = HashMap<String, String>()
    private var language = ""

    /** Satırın havuzdaki çevirisi (yoksa null). Anahtar oyun paketleriyle ve sunucuyla aynı ([PackKey]). */
    fun match(source: String): String? {
        val key = PackKey.key(source) ?: return null
        return synchronized(lock) { texts[key] }
    }

    val count: Int get() = synchronized(lock) { texts.size }

    internal fun replace(language: String, new: Map<String, String>) = synchronized(lock) {
        this.language = language
        texts = HashMap(new)
    }

    /** Yalnız aynı dilin çevirileri eklenir (dil değişirken gelen eski cevap karışmasın). */
    internal fun merge(language: String, items: Map<String, String>) = synchronized(lock) {
        if (language == this.language) texts.putAll(items)
    }

    internal fun snapshot(): Pair<String, Map<String, String>> = synchronized(lock) { language to HashMap(texts) }
}

/**
 * Sunucunun çeviri havuzu istemcisi. Bloklayan çağrılar ([translate], [sync], [refreshConfig]) arka plan iş
 * parçacığında yapılmalı; ağ isteği sürerken kilit tutulmaz (uzun indirme anında çeviriyi bekletmez).
 * [install]: kuruluma özgü rastgele kimlik (sunucuda yalnız tuzlanmış özetiyle, kaba hız sınırı için); verilmezse
 * klasördeki `install` dosyasından okunur ya da üretilir.
 */
class TranslationPool(
    private val directory: File,
    endpoint: URL? = NinoPool.configuredEndpoint(directory),
    install: String? = null,
    private val app: String,
    private val platform: String = "android",
    language: String,
    enabled: Boolean = true,
    private val send: ((Request) -> NinoPool.Response)? = null,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    /** Sunucudan gelen ayar (`GET /v1/config`); sunucuya ulaşılamazsa bu varsayılanlar. */
    data class Config(
        val enabled: Boolean = true,
        val deadlineMs: Int = 900,
        val syncSeconds: Int = 180,
        val contextLines: Int = 4,
        val maxLines: Int = 12,
    )

    /**
     * Havuz öncelikli oyunlar (`GET /v1/config` → `poolFirst`): bu oyunlarda satır önce sunucuya sorulur, kullanıcının
     * kendi motoru (Gemini, DeepL, yapay zekâ) hiç çağrılmaz; sunucu [deadlineMs] içinde cevap vermezse yalnız cihazın
     * ücretsiz çevirisi kullanılır. Varsayılan GTA 6 (sunucuya ulaşılamasa da). Windows: PoolFirstConfig.
     */
    data class PoolFirstConfig(
        val games: List<String> = listOf("grand-theft-auto-vi", "gta-vi", "gta-6", "gta6"),
        val deadlineMs: Int = 1500,
    ) {
        /** Oyun listede mi: kimlik ([NinoPool.gameId]) parçalardan birini içeriyorsa (sunucudaki kural). */
        fun contains(rawGame: String?): Boolean {
            val id = NinoPool.gameId(rawGame) ?: return false
            return games.any { part -> part.trim().lowercase().let { it.isNotEmpty() && id.contains(it) } }
        }
    }

    /** Giden istek (testlerde sahte sunucuya gider). [body] yalnız POST'ta. */
    data class Request(val method: String, val url: URL, val body: String?)

    private data class Cursor(var since: Long = 0, var after: String = "", var checked: Double = 0.0)

    private class Saved(val language: String, val texts: Map<String, String>, val cursors: Map<String, Cursor>)

    companion object {
        /** Sunucunun tanıdığı oyun bu kadar süre geçerli sayılır (saniye). */
        const val SERVER_GAME_SECONDS = 600.0

        /** Sunucudan en çok bu kadar çeviri tutulur (dil başına); fazlası diske yazılmaz. */
        const val MAX_STORED = 400_000

        /** Oyun tanımaya gönderilen karenin üst sınırı (Mac ile aynı). */
        const val MAX_IDENTIFY_BYTES = 450 * 1024

        fun code(language: String): String = language.lowercase().split('-', '_').firstOrNull() ?: ""

        private fun installId(directory: File): String {
            val file = File(directory, "install")
            try {
                val saved = file.takeIf { it.exists() }?.readText()?.trim()
                if (saved != null && runCatching { UUID.fromString(saved) }.isSuccess && saved.length == 36) return saved.lowercase()
            } catch (error: IOException) {
            }
            val made = UUID.randomUUID().toString().lowercase()
            try { file.writeText(made) } catch (error: IOException) { }
            return made
        }

        private fun file(directory: File, language: String) = File(directory, "translations-$language.json")

        private fun load(directory: File, language: String): Saved? {
            val file = file(directory, language)
            if (!file.exists()) return null
            return try {
                val json = JSONObject(file.readText())
                val texts = HashMap<String, String>()
                json.optJSONObject("texts")?.let { obj -> obj.keys().forEach { key -> if (!obj.isNull(key)) texts[key] = obj.optString(key) } }
                val cursors = HashMap<String, Cursor>()
                json.optJSONObject("cursors")?.let { obj ->
                    obj.keys().forEach { game ->
                        val c = obj.optJSONObject(game) ?: return@forEach
                        cursors[game] = Cursor(c.optLong("since"), c.optString("after", ""), c.optDouble("checked", 0.0))
                    }
                }
                Saved(json.optString("language", language), texts, cursors)
            } catch (error: Exception) {
                null
            }
        }
    }

    /** Altyazı hattının eşzamanlı baktığı çeviriler. */
    val store = PoolTranslations()

    private val lock = Any()
    /** Aynı anda tek indirme (oyun değişince başlayan ile dakikalık olan çakışmasın). */
    private val syncLock = Any()
    @Volatile var config = Config()
        private set
    @Volatile var poolFirst = PoolFirstConfig()
        private set
    /** Havuz öncelikli oyunda süresinde gelmeyen cevap beklenmez; istek bu iş parçacıklarında sürer. */
    private val firstWork = Executors.newCachedThreadPool { Thread(it, "Nino pool first").apply { isDaemon = true } }
    @Volatile var isEnabled: Boolean = enabled
        private set
    @Volatile private var endpoint: URL? = endpoint
    private val install: String
    private var language: String
    private var cursors = HashMap<String, Cursor>()
    private var configChecked = 0.0
    private val inFlight = ConcurrentHashMap<String, CompletableFuture<String?>>()
    private var dirty = false

    init {
        directory.mkdirs()
        this.install = install ?: installId(directory)
        this.language = code(language)
        val saved = load(directory, this.language)
        cursors = HashMap(saved?.cursors ?: emptyMap())
        store.replace(this.language, if (enabled) saved?.texts ?: emptyMap() else emptyMap())
    }

    // --- Ayar ---

    /** Hedef dil değişince o dilin çevirileri yüklenir. */
    fun setLanguage(value: String) = synchronized(lock) {
        val code = code(value)
        if (code == language) return@synchronized
        saveLocked()
        language = code
        val saved = load(directory, code)
        cursors = HashMap(saved?.cursors ?: emptyMap())
        store.replace(code, if (isEnabled) saved?.texts ?: emptyMap() else emptyMap())
    }

    /** Kullanıcı ortak havuzu kapatınca hiçbir şey sorulmaz ve indirilen çeviriler kullanılmaz. */
    fun setEnabled(value: Boolean) = synchronized(lock) {
        if (value == isEnabled) return@synchronized
        // Kapatmadan önce henüz yazılmamış çeviriler diske yazılır; boşaltılan bellek sonra diskin üstüne yazılmasın.
        if (!value) saveLocked()
        isEnabled = value
        val saved = if (value) load(directory, language) else null
        store.replace(language, saved?.texts ?: emptyMap())
    }

    fun setEndpoint(url: URL?) { endpoint = url }

    /** Havuz şu an kullanılabilir mi (ayar açık, sunucu açık, adres var). */
    val isActive: Boolean get() = isEnabled && config.enabled && endpoint != null

    /**
     * Oyun havuz öncelikli mi ve sunucu kullanılabilir mi (sunucu açık, adres var). Ortak havuz ayarı kapalı olsa da
     * geçerlidir: kullanıcı kararıyla bu oyunlarda çeviri hep sunucudan gelir.
     */
    fun isPoolFirst(rawGame: String?): Boolean {
        if (!(config.enabled && endpoint != null)) return false
        if (poolFirst.contains(rawGame)) return true
        // Uygulama oyunu bilmiyor ya da yanlış biliyor (ör. benzer satırlı başka oyunun paketi): sunucu satırlardan havuz
        // öncelikli oyunu tanıdıysa o geçerli. Sunucu her cevapta oyunu yeniden söyler.
        val (game, at) = synchronized(lock) { serverGame }
        return clock() / 1000.0 - at <= SERVER_GAME_SECONDS && poolFirst.contains(game)
    }

    /** Sunucunun son çeviri cevabındaki oyun ve zamanı (saniye). */
    private var serverGame: Pair<String, Double> = "" to Double.NEGATIVE_INFINITY

    /** Sunucunun ayarını en çok 10 dakikada bir sorar (bloklar). */
    fun refreshConfig(force: Boolean = false) {
        val base = endpoint ?: return
        val now = clock() / 1000.0
        synchronized(lock) {
            if (!force && now - configChecked <= 600) return
            configChecked = now
        }
        val data = get(URL(base, "/v1/config")) ?: return
        val reply = try { JSONObject(data) } catch (error: Exception) { null } ?: return
        val translate = reply.optJSONObject("translate") ?: return
        val defaults = Config()
        config = Config(
            enabled = translate.optBoolean("enabled", defaults.enabled),
            deadlineMs = translate.optInt("deadlineMs", defaults.deadlineMs),
            syncSeconds = translate.optInt("syncSeconds", defaults.syncSeconds),
            contextLines = translate.optInt("contextLines", defaults.contextLines),
            maxLines = translate.optInt("maxLines", defaults.maxLines),
        )
        // Eski sunucu bu bölümü göndermez: varsayılan (GTA 6) kalır.
        reply.optJSONObject("poolFirst")?.let { first ->
            val current = PoolFirstConfig()
            val games = first.optJSONArray("games")?.let { list -> (0 until list.length()).mapNotNull { list.opt(it) as? String } }
            poolFirst = PoolFirstConfig(games ?: current.games, first.optInt("deadlineMs", current.deadlineMs))
        }
    }

    // --- Toplu indirme ---

    /**
     * Oyunun yeni çevirilerini indirir (oyun başlarken hemen, sonra `syncSeconds` aralıkla). [rawGame] yoksa bütün
     * oyunlar. Eklenen çeviri sayısını döner (bloklar).
     */
    fun sync(rawGame: String?, force: Boolean = false): Int = synchronized(syncLock) {
        refreshConfig()
        val base = endpoint
        if (!isActive || base == null) return 0
        val game = NinoPool.gameId(rawGame) ?: ""
        val now = clock() / 1000.0
        val (lang, cursor) = synchronized(lock) {
            val cursor = (cursors[game] ?: Cursor()).copy()
            if (!force && now - cursor.checked < maxOf(30, config.syncSeconds).toDouble()) return 0
            cursor.checked = now
            cursors[game] = cursor.copy()
            language to cursor
        }
        var added = 0
        for (page in 0 until 50) {
            val query = buildString {
                append("lang=").append(enc(lang)).append("&since=").append(cursor.since)
                if (game.isNotEmpty()) append("&game=").append(enc(game))
                if (cursor.after.isNotEmpty()) append("&after=").append(enc(cursor.after))
            }
            val data = get(URL(base, "/v1/translations?$query")) ?: break
            val json = try { JSONObject(data) } catch (error: Exception) { null } ?: break
            if (synchronized(lock) { lang != language }) break
            val rows = json.optJSONArray("items") ?: JSONArray()
            val items = HashMap<String, String>()
            var newest = cursor.since
            for (i in 0 until rows.length()) {
                val row = rows.optJSONArray(i) ?: continue
                if (row.length() < 3) continue
                val key = row.opt(0) as? String ?: continue
                val text = row.opt(1) as? String ?: continue
                val updated = (row.opt(2) as? Number)?.toLong() ?: continue
                items[key] = text
                newest = maxOf(newest, updated)
            }
            // İndirme sürerken havuz kapatıldıysa gelen çeviriler kullanılmaz.
            if (!synchronized(lock) { isEnabled }) break
            store.merge(lang, items)
            added += items.size
            if (items.isNotEmpty()) synchronized(lock) { dirty = true }
            val next = if (json.isNull("next")) null else json.optJSONObject("next")
            if (next != null) {
                cursor.since = next.optLong("since", cursor.since)
                cursor.after = next.optString("after", "")
            } else {
                cursor.since = newest
                cursor.after = ""
                break
            }
        }
        synchronized(lock) {
            if (lang == language) cursors[game] = cursor
            saveLocked()
        }
        added
    }

    private fun enc(value: String) = URLEncoder.encode(value, "UTF-8")

    /**
     * Çeviri sürerken dakikada bir "buradayım" (`GET /v1/ping`): sunucu kaç kişinin hangi oyunu oynadığını sayar.
     * Cevap önemsiz, hata sessizce yutulur; ortak havuz kapalıysa gönderilmez (bloklar).
     */
    fun ping(rawGame: String?) {
        val base = endpoint ?: return
        if (!isEnabled) return
        val lang = synchronized(lock) { language }
        val query = "install=${enc(install)}&platform=${enc(platform)}&app=${enc(app)}" +
            "&game=${enc(NinoPool.gameId(rawGame) ?: "")}&lang=${enc(lang)}"
        call(Request("GET", URL(base, "/v1/ping?$query"), null))
    }

    // --- Oyunu ekrandan tanıma ---

    /**
     * Nino: oyunun bir karesini (küçük JPEG) sunucuya gösterir (`POST /v1/identify`); sunucu oyunun adını söyler. Havuz
     * kapalıysa, kare çok büyükse, sunucu tanıyamazsa ya da ulaşılamazsa null (bloklar). Mac: TranslationPool.identify.
     */
    fun identify(jpeg: ByteArray): String? {
        val base = endpoint ?: return null
        if (!isEnabled || jpeg.isEmpty() || jpeg.size > MAX_IDENTIFY_BYTES) return null
        val body = JSONObject().put("v", 1).put("install", install).put("app", app).put("platform", platform)
            .put("image", java.util.Base64.getEncoder().encodeToString(jpeg))
        val response = call(Request("POST", URL(base, "/v1/identify"), body.toString()))
        if (response == null || response.code != 200 || !isEnabled) return null
        val json = try { JSONObject(response.body) } catch (error: Exception) { return null }
        // Tanınamadıysa "game": null (org.json'un optString'i bunu "null" yazısı yapar).
        if (!json.has("game") || json.isNull("game")) return null
        return json.optString("game").trim().takeIf { it.isNotEmpty() }
    }

    // --- Anında çeviri ---

    /**
     * Satırı sunucuya sorar; sunucu biliyorsa ya da o an çevirirse çeviri döner ve havuza eklenir. Aynı satır aynı anda
     * iki kez sorulmaz. Ulaşılamazsa, sınır dolduysa ya da havuz kapalıysa null (bloklar). Havuz öncelikli oyunda
     * ([isPoolFirst]) ortak havuz ayarı kapalı olsa da sorulur.
     */
    fun translate(line: String, context: List<String> = emptyList(), rawGame: String? = null): String? {
        refreshConfig()
        val base = endpoint
        val forced = isPoolFirst(rawGame)
        if (!((isEnabled || forced) && config.enabled) || base == null || !NinoPool.accepts(NinoPool.clean(line))) return null
        val key = PackKey.key(line) ?: return null
        store.match(line)?.let { return it }
        val lang = synchronized(lock) { language }
        val flightKey = lang + "\u001F" + key
        val mine = CompletableFuture<String?>()
        val running = inFlight.putIfAbsent(flightKey, mine)
        if (running != null) return try { running.get() } catch (error: Exception) { null }
        var result: String? = null
        try {
            val body = JSONObject().put("v", 1).put("install", install).put("app", app).put("platform", platform)
                .put("lang", lang).put("game", NinoPool.gameId(rawGame) ?: "").put("lines", JSONArray(listOf(line)))
                .put("context", JSONArray(context.takeLast(maxOf(0, config.contextLines))))
            val response = call(Request("POST", URL(base, "/v1/translate"), body.toString()))
            if (response != null && response.code == 200) {
                val reply = try { JSONObject(response.body) } catch (error: Exception) { null }
                val said = reply?.takeIf { it.has("game") && !it.isNull("game") }?.optString("game")
                synchronized(lock) { serverGame = (NinoPool.gameId(said) ?: "") to clock() / 1000.0 }
                val first = reply?.optJSONArray("translations")?.optJSONObject(0)
                // Sunucu çeviremediyse "text": null (org.json'un optString'i bunu "null" yazısı yapar).
                if (first != null && first.has("text") && !first.isNull("text")) result = first.optString("text").takeIf { it.isNotEmpty() }
            }
            // Cevap gelirken havuz kapatıldıysa çeviri ne saklanır ne gösterilir (havuz öncelikli oyun hariç).
            synchronized(lock) {
                if (!isEnabled && !forced) result = null
                result?.let { text ->
                    store.merge(lang, mapOf(key to text))
                    dirty = true
                }
            }
        } finally {
            inFlight.remove(flightKey, mine)
            mine.complete(result)
        }
        return result
    }

    /**
     * Havuz öncelikli oyunda satırı sunucuya sorar ve en çok [PoolFirstConfig.deadlineMs] bekler. Süre dolarsa, sunucu
     * hata verirse ya da günlük bütçe dolduysa null (çağıran ücretsiz yerel çeviriye düşer). Süre dolsa da istek sürer;
     * geç gelen çeviri havuza yazılır ve aynı satır için [translate] onu bekler. Bekleyen iş parçacığı kesilirse
     * (okuma hattı satırı bıraktı) [InterruptedException] (bloklar). Windows: TranslateFirstAsync.
     */
    fun translateFirst(line: String, context: List<String> = emptyList(), rawGame: String? = null): String? {
        val deadline = poolFirst.deadlineMs.coerceIn(100, 10_000).toLong()
        val asking = try {
            CompletableFuture.supplyAsync({ translate(line, context, rawGame) }, firstWork)
        } catch (stopped: RejectedExecutionException) {
            return null
        }
        return try {
            asking.get(deadline, TimeUnit.MILLISECONDS)
        } catch (late: TimeoutException) {
            null
        } catch (error: ExecutionException) {
            null
        }
    }

    // --- Disk ---

    /** Çevirileri diske yazar (indirmeden sonra ve kapanırken). */
    fun save() = synchronized(lock) { saveLocked() }

    private fun saveLocked() {
        // Kapalıyken bellek boştur; diske yazılırsa indirilmiş çeviriler silinirdi.
        if (!dirty || !isEnabled) return
        dirty = false
        val (storeLanguage, all) = store.snapshot()
        if (storeLanguage != language) return
        val texts = JSONObject()
        var count = 0
        for ((key, value) in all) {
            if (count++ >= MAX_STORED) break
            texts.put(key, value)
        }
        val cursorJson = JSONObject()
        for ((game, c) in cursors) cursorJson.put(game, JSONObject().put("since", c.since).put("after", c.after).put("checked", c.checked))
        val text = JSONObject().put("language", language).put("texts", texts).put("cursors", cursorJson).toString()
        val target = file(directory, language)
        val temp = File(directory, target.name + ".tmp")
        try {
            FileOutputStream(temp).use { it.write(text.toByteArray(Charsets.UTF_8)) }
            if (!temp.renameTo(target)) { target.delete(); temp.renameTo(target) }
        } catch (error: IOException) {
            temp.delete()
        }
    }

    // --- Ağ ---

    private fun get(url: URL): String? {
        val response = call(Request("GET", url, null)) ?: return null
        return response.body.takeIf { response.code == 200 }
    }

    private fun call(request: Request): NinoPool.Response? = try {
        (send ?: ::http)(request)
    } catch (error: Exception) {
        null
    }

    private fun http(request: Request): NinoPool.Response {
        val connection = request.url.openConnection() as HttpURLConnection
        try {
            connection.requestMethod = request.method
            connection.connectTimeout = 15_000
            // Oyun tanıma (kareye bakılır) çeviriden uzun sürebilir.
            connection.readTimeout = if (request.method == "POST" && !request.url.path.endsWith("/identify")) 20_000 else 30_000
            // Cloudflare tanımadığı Java istemcilerini bazen engelliyor; NinoPool ile aynı tanıtım.
            connection.setRequestProperty("User-Agent", "nino-pool/1 ($platform; $app)")
            if (request.body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(request.body.toByteArray(Charsets.UTF_8)) }
            }
            val code = connection.responseCode
            val stream = if (code < 400) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() } ?: ""
            return NinoPool.Response(code, text, connection.getHeaderField("Retry-After")?.trim()?.toLongOrNull())
        } finally {
            connection.disconnect()
        }
    }
}

/**
 * Havuza sorulan satırların bağlamı: son birkaç satır (çok eskiyse atılır). Sunucu kısa satırı ("Do it.") bununla
 * doğru hitap ve anlamla çevirir.
 */
class PoolContext(private val clock: () -> Long = System::currentTimeMillis) {
    companion object {
        const val MAX_AGE_MS = 30_000L
    }

    private val lock = Any()
    private val lines = ArrayList<Pair<String, Long>>()

    /** Satırdan önceki (taze) satırlar; satırı eklemez. */
    fun before(text: String, keep: Int = 4): List<String> = synchronized(lock) {
        val now = clock()
        lines.filter { now - it.second <= MAX_AGE_MS && it.first != text }.map { it.first }.takeLast(keep)
    }

    /** Satırı ekler; ondan önceki (taze) satırları döner. */
    fun add(text: String, keep: Int = 4): List<String> = synchronized(lock) {
        val now = clock()
        lines.removeAll { now - it.second > MAX_AGE_MS || it.first == text }
        val context = lines.takeLast(keep).map { it.first }
        lines.add(text to now)
        while (lines.size > keep) lines.removeAt(0)
        context
    }
}
