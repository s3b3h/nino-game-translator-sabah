// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.text.Normalizer
import java.util.UUID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * Nino'nun ortak altyazı havuzu istemcisi (Mac'teki NinoPool ile aynı tasarım ve biçim). Pakette bulunmayan İngilizce
 * satırlar telefonda kalıcı bir kuyruğa yazılır ve sunucu "aldım" diyene kadar orada kalır:
 * 1. Her satır görüldüğü anda `pending.jsonl` dosyasının sonuna eklenir (uygulama kapansa da diskte kalır).
 * 2. Gönderim zamanı gelince bekleyenler (oyun, oturum, metin) başına sayılarak birleşir ve kimlikli parçalar hâlinde
 *    `outbox/` klasörüne yazılır. Parça, sunucu kimliğini geri söyleyene kadar silinmez; yanıt kaybolursa aynı kimlikle
 *    yeniden gider, sunucu onu ikinci kez saymaz.
 * 3. Ağ yoksa ya da sunucu hata verirse artan aralıklarla (30 sn → 1 sa) yeniden denenir; ağ gelince hemen denenir.
 * 4. Sunucunun kabul etmediği parça (400) `parked/` klasörüne alınır, uygulama güncellenince yeniden denenir; çok büyük
 *    parça (413) ikiye bölünür.
 * 5. Canlı sunucu adresi yoksa satırlar kuyrukta bekler.
 * Bloklayan çağrılar (`flush`) arka plan iş parçacığında yapılmalı.
 */
class NinoPool(
    private val directory: File,
    private val app: String,
    private val platform: String = "android",
    enabled: Boolean = true,
    endpoint: URL? = configuredEndpoint(directory),
    legacyFile: File? = null,
    private val limits: Limits = Limits(),
    private val post: ((URL, String) -> Response)? = null,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    companion object {
        /** Canlı havuz sunucusu (Cloudflare Workers, nino-pool/); denemede havuz klasöründeki endpoint.txt ile değişir. */
        val LIVE_ENDPOINT: URL? = URL("https://nino-pool.y-demirbag2506.workers.dev")
        const val TICK_INTERVAL_MS = 60_000L

        /** Adres: havuz klasöründeki `endpoint.txt` (deneme için), yoksa [LIVE_ENDPOINT]. */
        fun configuredEndpoint(directory: File): URL? {
            val text = try { File(directory, "endpoint.txt").takeIf { it.exists() }?.readText()?.trim() } catch (error: IOException) { null }
            if (!text.isNullOrEmpty() && (text.startsWith("http://") || text.startsWith("https://"))) {
                return try { URL(text) } catch (error: Exception) { LIVE_ENDPOINT }
            }
            return LIVE_ENDPOINT
        }
        /** Gönderim en erken bu kadar biriktirince yapılır (ya da en eski satır bu kadar bekleyince). */
        const val SEND_EVERY_MS = 120_000L

        /** Havuza uygun satır: harf var, en çok 500 karakter, yazı tanıma çöpü değil, Türkçe ya da PS5 sistem yazısı değil. */
        fun accepts(text: String, maxLength: Int = 500): Boolean {
            if (text.isEmpty() || text.codePointCount(0, text.length) > maxLength) return false
            if (!text.codePoints().anyMatch { Character.isLetter(it) }) return false
            return !LinePool.looksLikeNoise(text) && !looksTurkish(text) && !looksLikeSystemText(text)
        }

        private val turkishOnly = setOf('ğ', 'Ğ', 'ş', 'Ş', 'ı', 'İ')
        private val turkishShared = setOf('ü', 'Ü', 'ö', 'Ö', 'ç', 'Ç')

        /** Türkçe satır (PS5'in Türkçe arayüzü): Türkçeye özgü harf ya da iki ve daha çok ü/ö/ç. */
        fun looksTurkish(text: String): Boolean =
            text.any { it in turkishOnly } || text.count { it in turkishShared } >= 2

        /** PS5'in kendi bildirimleri; bazıları PSN adı taşır ("X signed in"), bu yüzden hiç gönderilmez. */
        private val systemPhrases = listOf(
            "signed in", "signed out", "earned a trophy", "trophy unlocked", "screenshot saved", "video clip saved",
            "joined the party", "left the party", "is now online", "remote play", "controller disconnected",
            "press the ps button", "playstation network", "download complete", "update available",
            "oturum acti", "oturum kapatti", "lutfen bekleyin", "yeniden baslat",
        )

        fun looksLikeSystemText(text: String): Boolean {
            val folded = " " + Normalizer.normalize(text.lowercase().replace('ı', 'i'), Normalizer.Form.NFD)
                .replace(Regex("\\p{M}+"), "").replace(Regex("[^\\p{L}\\p{N}]+"), " ").trim() + " "
            return systemPhrases.any { folded.contains(" $it ") }
        }

        fun clean(raw: String): String {
            val builder = StringBuilder(raw.length)
            raw.codePoints().forEach { cp ->
                val control = cp <= 0x1F || cp in 0x7F..0x9F || cp in 0x200B..0x200F || cp == 0x2028 || cp == 0x2029 || cp == 0xFEFF
                if (control) builder.append(' ') else builder.appendCodePoint(cp)
            }
            return builder.toString().trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        }

        /** Paket kimliği sunucunun beklediği biçimde: küçük harf, harf/rakam/.-_ dışı tire, en çok 64 karakter. */
        fun gameId(game: String?): String? {
            if (game == null) return null
            val mapped = game.lowercase().map { c ->
                if ((c in 'a'..'z') || (c in '0'..'9') || c == '.' || c == '_' || c == '-') c else '-'
            }.joinToString("").replace(Regex("-{2,}"), "-").trim('-', '.', '_')
            return mapped.takeIf { it.isNotEmpty() }?.take(64)
        }

        private fun newId() = UUID.randomUUID().toString()
    }

    data class Limits(
        val batchSize: Int = 200,
        val maxPendingBytes: Long = 32L * 1024 * 1024,
        val maxOutbox: Int = 1000,
        val maxTextLength: Int = 500,
        val backoffBaseMs: Long = 30_000,
        val backoffMaxMs: Long = 3_600_000,
    )

    data class Response(val code: Int, val body: String, val retryAfterSeconds: Long?)

    data class Status(val pendingLines: Int, val outboxBatches: Int, val parkedBatches: Int, val dropped: Int, val hasEndpoint: Boolean)

    private val lock = Any()
    private val sendLock = Any()
    private val session = newId()
    private val stateFile = File(directory, "state.json")
    private val pendingFile = File(directory, "pending.jsonl")
    private val outboxDir = File(directory, "outbox")
    private val parkedDir = File(directory, "parked")
    @Volatile private var endpoint: URL? = endpoint
    @Volatile private var enabled = enabled

    private var install = newId()
    private var frozenThrough = 0L
    private var failures = 0
    private var nextAttempt = 0L
    private var serverRetryAt = 0L
    private var lastApp = ""
    private var dropped = 0
    private var nextSeq = 1L
    private var pendingBytes = 0L
    private var pendingCount = 0
    private var oldestPending: Double? = null

    val installId: String get() = install
    val sessionId: String get() = session

    init {
        outboxDir.mkdirs()
        parkedDir.mkdirs()
        loadState()
        // Parça yazılıp durum yazılamadan kapanmışsa: parçaların kapsadığı sıra numarası esastır.
        batchFiles(outboxDir).forEach { file -> readBatch(file)?.let { frozenThrough = max(frozenThrough, it.optLong("upTo")) } }
        if (lastApp != app) {
            batchFiles(parkedDir).forEach { it.renameTo(File(outboxDir, it.name)) }
            lastApp = app
        }
        failures = 0
        nextAttempt = 0
        // enabled = false yalnız bu çalışmada etkisiz olmak demek (klip): kuyruk silinmez. Kullanıcı havuzu kapatınca
        // silme setEnabled(false) ile yapılır.
        repairPending()
        var scan = scanPending()
        if (enabled && legacyFile != null) {
            importLegacy(legacyFile, max(scan.maxSeq, frozenThrough) + 1)
            scan = scanPending()
        }
        nextSeq = max(scan.maxSeq, frozenThrough) + 1
        pendingBytes = pendingFile.length()
        pendingCount = scan.list.size
        oldestPending = scan.list.minOfOrNull { it.at }
        writeState()
    }

    fun status(): Status = synchronized(lock) {
        Status(pendingCount, batchFiles(outboxDir).size, batchFiles(parkedDir).size, dropped, endpoint != null)
    }

    fun setEndpoint(url: URL?) = synchronized(lock) {
        endpoint = url
        failures = 0
        nextAttempt = 0
        writeState()
    }

    /** Kapatılınca bekleyen her şey silinir: kullanıcı vazgeçtiyse hiçbir şey gitmez. */
    fun setEnabled(value: Boolean) = synchronized(lock) {
        enabled = value
        if (value) return@synchronized
        removeQueued()
        pendingBytes = 0
        pendingCount = 0
        oldestPending = null
        failures = 0
        nextAttempt = 0
        serverRetryAt = 0
        writeState()
    }

    /** Okunan (pakette bulunmayan) satırı kuyruğa yazar. [game]: varsa oyun ipucu (paket kimliği). */
    fun offer(raw: String, game: String? = null): Boolean {
        val text = clean(raw)
        if (!accepts(text, limits.maxTextLength)) return false
        return synchronized(lock) {
            if (!enabled) return@synchronized false
            append(text, gameId(game), session, clock() / 1000.0)
        }
    }

    /** Zamanı geldiyse bekleyenleri parçalara aktarır ve gönderir (bloklar). */
    fun flush(force: Boolean = false) = synchronized(sendLock) {
        val target = synchronized(lock) {
            val url = endpoint
            val now = clock()
            if (!enabled || url == null || now < nextAttempt || now < serverRetryAt) return@synchronized null
            val due = force || pendingCount >= limits.batchSize || (oldestPending?.let { now - (it * 1000).toLong() >= SEND_EVERY_MS } ?: false)
            if (due) freeze()
            url
        } ?: return@synchronized
        sendOutbox(target)
    }

    /** Ağ yeniden geldi: artan bekleme sıfırlanır ve hemen denenir (bloklar). */
    fun networkAvailable() {
        synchronized(lock) {
            failures = 0
            nextAttempt = 0
            writeState()
        }
        flush()
    }

    // --- Bekleyenler ---

    private class Sighting(val seq: Long, val text: String, val game: String?, val session: String?, val at: Double)

    private class Scan(val list: List<Sighting>, val maxSeq: Long)

    private fun append(text: String, game: String?, session: String?, at: Double): Boolean {
        if (pendingBytes >= limits.maxPendingBytes) {
            dropped++
            writeState()
            return false
        }
        val line = JSONObject().put("s", nextSeq).put("t", text).put("g", game ?: JSONObject.NULL)
            .put("e", session ?: JSONObject.NULL).put("a", at).toString() + "\n"
        val bytes = line.toByteArray(Charsets.UTF_8)
        try {
            FileOutputStream(pendingFile, true).use { it.write(bytes) }
        } catch (error: IOException) {
            return false
        }
        nextSeq++
        pendingBytes += bytes.size
        pendingCount++
        if (oldestPending == null) oldestPending = at
        return true
    }

    private fun repairPending() {
        if (!pendingFile.exists()) return
        val data = try { pendingFile.readBytes() } catch (error: IOException) { return }
        if (data.isEmpty() || data.last() == '\n'.code.toByte()) return
        val keep = data.lastIndexOf('\n'.code.toByte()) + 1
        try {
            java.io.RandomAccessFile(pendingFile, "rw").use { it.setLength(keep.toLong()) }
        } catch (error: IOException) {
        }
    }

    private fun scanPending(): Scan {
        val list = mutableListOf<Sighting>()
        var maxSeq = 0L
        if (!pendingFile.exists()) return Scan(list, 0)
        try {
            pendingFile.forEachLine(Charsets.UTF_8) { line ->
                if (line.isEmpty()) return@forEachLine
                val json = try { JSONObject(line) } catch (error: Exception) { return@forEachLine } // yarım satır
                val seq = json.optLong("s", -1)
                val text = json.optString("t", "")
                if (seq < 0 || text.isEmpty()) return@forEachLine
                maxSeq = max(maxSeq, seq)
                if (seq > frozenThrough) {
                    list += Sighting(seq, text, json.optString("g").takeIf { !json.isNull("g") && it.isNotEmpty() },
                        json.optString("e").takeIf { !json.isNull("e") && it.isNotEmpty() }, json.optDouble("a", 0.0))
                }
            }
        } catch (error: IOException) {
        }
        return Scan(list, maxSeq)
    }

    private fun freeze() {
        if (pendingCount == 0 || batchFiles(outboxDir).size >= limits.maxOutbox) return
        val scan = scanPending()
        if (scan.list.isEmpty()) {
            compactPending()
            return
        }
        // Parçalar sıra numarasına göre ardışık dilimlerdir: her parçanın upTo'su yalnız kendi kapsadığı son satırdır,
        // birleştirme parça sınırını aşmaz; yarıda kapanılsa da yazılmamış parçaların satırları bekleyenlerde kalır.
        val chunks = mutableListOf<Pair<List<JSONObject>, Long>>()
        var merged = LinkedHashMap<String, JSONObject>()
        var last = frozenThrough
        for (s in scan.list.sortedBy { it.seq }) {
            val id = "${s.game}\u0000${s.session}\u0000${s.text}"
            val at = s.at.toLong()
            val line = merged[id]
            if (line != null) {
                line.put("count", line.getInt("count") + 1)
                line.put("first", min(line.getLong("first"), at))
                line.put("last", max(line.getLong("last"), at))
            } else {
                if (merged.size == limits.batchSize) {
                    chunks += merged.values.toList() to last
                    merged = LinkedHashMap()
                }
                merged[id] = JSONObject().put("text", s.text).put("game", s.game ?: JSONObject.NULL)
                    .put("session", s.session ?: JSONObject.NULL).put("count", 1).put("first", at).put("last", at)
            }
            last = s.seq
        }
        if (merged.isNotEmpty()) chunks += merged.values.toList() to last
        val stamp = clock()
        for ((index, chunk) in chunks.withIndex()) {
            val batch = JSONObject().put("v", 1).put("batch", newId()).put("install", install).put("app", app)
                .put("platform", platform).put("lines", JSONArray(chunk.first)).put("upTo", chunk.second)
            val file = File(outboxDir, "%015d-%04d-%s.json".format(stamp, index, batch.getString("batch")))
            // Yazılamadıysa (disk dolu): yazılan parçalar kalır, gerisi bekleyenlerde sürer.
            if (!writeAtomic(file, batch.toString())) break
            frozenThrough = chunk.second
        }
        writeState()
        compactPending()
    }

    private fun compactPending() {
        val scan = scanPending()
        val text = buildString {
            for (s in scan.list) {
                append(JSONObject().put("s", s.seq).put("t", s.text).put("g", s.game ?: JSONObject.NULL)
                    .put("e", s.session ?: JSONObject.NULL).put("a", s.at).toString()).append('\n')
            }
        }
        if (writeAtomic(pendingFile, text)) pendingBytes = pendingFile.length()
        pendingCount = scan.list.size
        oldestPending = scan.list.minOfOrNull { it.at }
    }

    // --- Gönderim ---

    private fun sendOutbox(target: URL) {
        val tried = mutableSetOf<String>()
        while (true) {
            val (file, batch) = synchronized(lock) {
                if (!enabled) return
                val next = batchFiles(outboxDir).firstOrNull { it.name !in tried } ?: return
                tried += next.name
                val parsed = readBatch(next)
                if (parsed == null) {
                    park(next)
                    null
                } else next to parsed
            } ?: continue
            val response = try {
                (post ?: ::httpPost)(URL(target, "/v1/batches"), batch.toString())
            } catch (error: Exception) {
                synchronized(lock) { failed() }
                return
            }
            synchronized(lock) {
                when (response.code) {
                    in 200..299 -> {
                        val reply = try { JSONObject(response.body) } catch (error: Exception) { null }
                        if (reply == null || !reply.optBoolean("ok") || !reply.optString("batch").equals(batch.getString("batch"), true)) {
                            // "Tamam" dese de bizim sunucumuz değilse (yanlış adres) parça silinmez.
                            failed()
                            return
                        }
                        file.delete()
                        failures = 0
                        nextAttempt = 0
                        writeState()
                    }
                    413 -> if (batch.getJSONArray("lines").length() > 1) split(file, batch) else park(file)
                    429, 503 -> {
                        serverRetryAt = clock() + (response.retryAfterSeconds ?: 60L).coerceIn(1L, 86400L) * 1000
                        writeState()
                        return
                    }
                    400, 422 -> park(file)
                    else -> {
                        failed()
                        return
                    }
                }
            }
        }
    }

    private fun failed() {
        failures++
        val delay = min(limits.backoffBaseMs * 2.0.pow(min(failures - 1, 16)), limits.backoffMaxMs.toDouble())
        val jitter = delay * (Math.random() * 0.4 - 0.2)
        nextAttempt = clock() + (delay + jitter).toLong()
        writeState()
    }

    private fun split(file: File, batch: JSONObject) {
        val lines = batch.getJSONArray("lines")
        val half = lines.length() / 2
        val prefix = file.nameWithoutExtension.take(20)
        listOf(0 until half, half until lines.length()).forEachIndexed { index, range ->
            val piece = JSONObject(batch.toString()).put("batch", newId()).put("lines", JSONArray(range.map { lines.get(it) }))
            if (!writeAtomic(File(outboxDir, "$prefix-$index-${piece.getString("batch")}.json"), piece.toString())) return
        }
        file.delete()
    }

    private fun park(file: File) {
        val target = File(parkedDir, file.name)
        target.delete()
        if (!file.renameTo(target)) file.copyTo(target, overwrite = true).also { file.delete() }
    }

    private fun httpPost(url: URL, body: String): Response {
        val connection = url.openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("User-Agent", "nino-pool/1 ($platform; $app)")
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = connection.responseCode
            val stream = if (code < 400) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() } ?: ""
            return Response(code, text, connection.getHeaderField("Retry-After")?.trim()?.toLongOrNull())
        } finally {
            connection.disconnect()
        }
    }

    // --- Eski CouchSubs kuyruğu ---

    /** CouchSubs'tan kalan `line-pool.json` kuyruğundaki satırlar bir kez bekleyenlere eklenir, dosya kenara konur. */
    private fun importLegacy(file: File, firstSeq: Long) {
        if (!file.exists()) return
        try {
            val queue = JSONObject(file.readText()).optJSONArray("queue")
            if (queue != null) {
                var seq = firstSeq
                val out = StringBuilder()
                val parser = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.ROOT)
                    .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
                for (i in 0 until queue.length()) {
                    val line = queue.optJSONObject(i) ?: continue
                    val text = clean(line.optString("text"))
                    if (!accepts(text, limits.maxTextLength)) continue
                    val at = try { parser.parse(line.optString("firstSeen"))!!.time / 1000.0 } catch (error: Exception) { clock() / 1000.0 }
                    out.append(JSONObject().put("s", seq++).put("t", text).put("g", JSONObject.NULL).put("e", JSONObject.NULL)
                        .put("a", at).toString()).append('\n')
                }
                FileOutputStream(pendingFile, true).use { it.write(out.toString().toByteArray(Charsets.UTF_8)) }
            }
        } catch (error: Exception) {
        }
        val moved = File(file.parentFile, file.name + ".imported")
        moved.delete()
        file.renameTo(moved)
    }

    // --- Dosyalar ---

    private fun batchFiles(dir: File): List<File> =
        (dir.listFiles { f -> f.isFile && f.name.endsWith(".json") } ?: emptyArray()).sortedBy { it.name }

    private fun readBatch(file: File): JSONObject? =
        try { JSONObject(file.readText()).takeIf { it.has("batch") && it.has("lines") } } catch (error: Exception) { null }

    private fun writeAtomic(file: File, text: String): Boolean {
        val temp = File(file.parentFile, file.name + ".tmp")
        return try {
            FileOutputStream(temp).use {
                it.write(text.toByteArray(Charsets.UTF_8))
                it.fd.sync()
            }
            temp.renameTo(file) || run { file.delete(); temp.renameTo(file) }
        } catch (error: IOException) {
            temp.delete()
            false
        }
    }

    private fun loadState() {
        if (!stateFile.exists()) return
        try {
            val json = JSONObject(stateFile.readText())
            install = json.optString("install").ifEmpty { install }
            frozenThrough = json.optLong("frozenThrough")
            serverRetryAt = json.optLong("serverRetryAt")
            lastApp = json.optString("app")
            dropped = json.optInt("dropped")
        } catch (error: Exception) {
            // Okunamayan durum dosyası kenara alınır; satırlar ayrı dosyalarda olduğundan kaybolmaz.
            stateFile.renameTo(File(directory, "state.broken-${clock() / 1000}.json"))
        }
    }

    private fun writeState() {
        writeAtomic(stateFile, JSONObject().put("install", install).put("frozenThrough", frozenThrough)
            .put("failures", failures).put("nextAttempt", nextAttempt).put("serverRetryAt", serverRetryAt)
            .put("app", app).put("dropped", dropped).toString())
    }

    private fun removeQueued() {
        pendingFile.delete()
        listOf(outboxDir, parkedDir).forEach { dir -> dir.listFiles()?.forEach { it.delete() } }
    }
}
