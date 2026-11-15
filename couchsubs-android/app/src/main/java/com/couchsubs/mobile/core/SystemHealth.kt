// SPDX-License-Identifier: AGPL-3.0-only
// Nino: Sistem sağlığı (Mac'teki SystemHealth.swift'in telefon karşılığı). Telefonda libchiaki'nin ayrıntılı kayıtları
// (paket yeniden gönderme, tampon taşması) Kotlin'e gelmez; bu yüzden görüntü, gelen kare hızından ölçülür.
package com.couchsubs.mobile.core

enum class HealthLevel { UNKNOWN, GOOD, WARNING, PROBLEM }

enum class NetworkKind { WIFI, WIRED, CELLULAR, OFFLINE, OTHER }

/** Bir çeviri oturumunun ölçümleri (oturum bitince de son değerler kalır). */
data class HealthSnapshot(
    val active: Boolean = false,
    /** Görüntünün geldiği toplam süre (bağlanırken ve koptuğunda sayılmaz). */
    val streamingSeconds: Double = 0.0,
    val everStreamed: Boolean = false,
    /** Görüntü gelirken kopma sayısı (kullanıcının durdurması sayılmaz). */
    val drops: Int = 0,
    /** Hiç görüntü gelmeden biten bağlanma denemeleri. */
    val failedConnects: Int = 0,
    val lastDisconnect: String? = null,
    val frames: Long = 0,
    val lines: Int = 0,
    val translations: Int = 0,
    val translationMedianMs: Long? = null,
    val translationMaxMs: Long? = null,
) {
    val isEmpty: Boolean get() = !everStreamed && failedConnects == 0 && lines == 0

    /** Saniyedeki kare; yeterince uzun (20 sn) görüntü gelmeden hesaplanmaz. */
    val framesPerSecond: Double? get() = if (streamingSeconds >= 20) frames / streamingSeconds else null
}

class HealthRecorder(private val clock: () -> Long = System::currentTimeMillis) {
    private val lock = Any()
    private var active = false
    private var streamingSince: Long? = null
    private var streamedMs = 0L
    private var everStreamed = false
    private var streamedThisAttempt = false
    private var drops = 0
    private var failedConnects = 0
    private var lastDisconnect: String? = null
    private var frames = 0L
    private var lastFrameTotal = 0L
    private var lines = 0
    private val times = ArrayDeque<Long>()
    private var maxMs: Long? = null

    fun sessionStarted() = synchronized(lock) {
        active = true
        streamingSince = null
        streamedMs = 0
        everStreamed = false
        streamedThisAttempt = false
        drops = 0
        failedConnects = 0
        lastDisconnect = null
        frames = 0
        lastFrameTotal = 0
        lines = 0
        times.clear()
        maxMs = null
    }

    fun sessionEnded() = synchronized(lock) {
        closeStreaming()
        active = false
    }

    fun connecting() = synchronized(lock) {
        closeStreaming()
        streamedThisAttempt = false
    }

    fun streaming() = synchronized(lock) {
        if (streamingSince == null) streamingSince = clock()
        everStreamed = true
        streamedThisAttempt = true
    }

    /** [reason] null: kullanıcı durdurdu (kopma sayılmaz). */
    fun disconnected(reason: String?) = synchronized(lock) {
        val wasStreaming = streamingSince != null
        closeStreaming()
        if (reason == null) return@synchronized
        lastDisconnect = reason
        if (wasStreaming || streamedThisAttempt) drops++ else failedConnects++
        streamedThisAttempt = false
    }

    /** Oturumun o ana kadar aldığı toplam kare (artarak gelir; küçülürse yeni bir kaynak başlamıştır). */
    fun frameTotal(total: Long) = synchronized(lock) {
        val delta = if (total >= lastFrameTotal) total - lastFrameTotal else total
        lastFrameTotal = total
        if (streamingSince != null) frames += delta
    }

    /** Gösterilen bir satır; [translationMs] null: oyun paketinden geldi (çeviri süresi yok). */
    fun line(translationMs: Long?) = synchronized(lock) {
        lines++
        if (translationMs == null) return@synchronized
        times.addLast(translationMs)
        while (times.size > 50) times.removeFirst()
        maxMs = maxOf(maxMs ?: 0, translationMs)
    }

    fun snapshot(): HealthSnapshot = synchronized(lock) {
        val open = streamingSince?.let { clock() - it } ?: 0
        val sorted = times.sorted()
        HealthSnapshot(
            active = active,
            streamingSeconds = (streamedMs + open) / 1000.0,
            everStreamed = everStreamed,
            drops = drops,
            failedConnects = failedConnects,
            lastDisconnect = lastDisconnect,
            frames = frames,
            lines = lines,
            translations = times.size,
            translationMedianMs = if (sorted.isEmpty()) null else sorted[sorted.size / 2],
            translationMaxMs = maxMs,
        )
    }

    private fun closeStreaming() {
        streamingSince?.let { streamedMs += clock() - it }
        streamingSince = null
    }
}

/** Ölçümlerden iyi / dikkat / sorun kararı (Mac ile aynı eşikler; görüntü kare hızından). */
object HealthReport {
    const val FPS_WARNING = 24.0
    const val FPS_PROBLEM = 12.0
    const val TRANSLATION_WARNING_MS = 1500L
    const val TRANSLATION_PROBLEM_MS = 3000L
    const val DROP_WARNING = 3

    fun connection(s: HealthSnapshot): HealthLevel = when {
        !s.everStreamed && s.failedConnects >= 2 -> HealthLevel.PROBLEM
        s.drops >= DROP_WARNING -> HealthLevel.WARNING
        s.everStreamed -> HealthLevel.GOOD
        else -> HealthLevel.UNKNOWN
    }

    fun stream(s: HealthSnapshot): HealthLevel {
        val fps = s.framesPerSecond ?: return HealthLevel.UNKNOWN
        return when {
            fps < FPS_PROBLEM -> HealthLevel.PROBLEM
            fps < FPS_WARNING -> HealthLevel.WARNING
            else -> HealthLevel.GOOD
        }
    }

    fun translation(s: HealthSnapshot): HealthLevel {
        val median = s.translationMedianMs ?: return HealthLevel.UNKNOWN
        return when {
            median > TRANSLATION_PROBLEM_MS -> HealthLevel.PROBLEM
            median > TRANSLATION_WARNING_MS -> HealthLevel.WARNING
            else -> HealthLevel.GOOD
        }
    }

    /** Kablolu ağ her zaman iyi; Wi-Fi ve mobil veri, görüntünün durumuna göre (ölçülmeden yeşil gösterilmez). */
    fun network(kind: NetworkKind, stream: HealthLevel): HealthLevel = when (kind) {
        NetworkKind.WIRED -> HealthLevel.GOOD
        NetworkKind.OFFLINE -> HealthLevel.PROBLEM
        else -> stream
    }

    fun summary(s: HealthSnapshot, kind: NetworkKind): String = buildString {
        append("ağ: ").append(kind.name.lowercase())
        append(", görüntü ").append("%.0f".format(s.streamingSeconds)).append(" sn")
        s.framesPerSecond?.let { append(", ").append("%.1f".format(it)).append(" kare/sn") }
        append(", kopma ").append(s.drops)
        append(", bağlanamama ").append(s.failedConnects)
        s.lastDisconnect?.let { append(", son kopma ").append(it) }
        append(", satır ").append(s.lines)
        s.translationMedianMs?.let { append(", çeviri ortanca ").append(it).append(" ms") }
        s.translationMaxMs?.let { append(", en uzun ").append(it).append(" ms") }
    }
}
