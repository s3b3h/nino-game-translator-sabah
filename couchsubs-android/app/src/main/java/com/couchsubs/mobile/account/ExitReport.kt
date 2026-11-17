// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.account

/**
 * Uygulamanın önceki kapanışlarından biri (Android 11+ ApplicationExitInfo'dan; Android'e bağlı değil, JVM testi:
 * ExitReportTest).
 */
data class ExitRecord(
    val reason: Int,
    val timestamp: Long,
    val description: String?,
    /** Kapanış anında süreç ön planda mıydı (ActivityManager.RunningAppProcessInfo.IMPORTANCE_*). */
    val importance: Int,
    val pssKb: Long,
    val rssKb: Long,
)

/**
 * Crashlytics yalnız Java çökmelerini görür: yerel kütüphanedeki (libchiaki, MediaCodec) çökme, sistemin belleği
 * yetmediği için süreci öldürmesi ve ANR hiç raporlanmaz. "Çeviriyi başlatınca uygulama kapanıyor" bildirimlerinde
 * Crashlytics boştu. Bir sonraki açılışta Android'in kaydettiği kapanış nedeni okunup raporlanır.
 */
object ExitReport {
    // ApplicationExitInfo.REASON_* (API 30); JVM testinde android.jar olmadan da okunabilsin diye burada.
    const val REASON_SIGNALED = 2
    const val REASON_LOW_MEMORY = 3
    const val REASON_CRASH = 4
    const val REASON_CRASH_NATIVE = 5
    const val REASON_ANR = 6
    const val REASON_INITIALIZATION_FAILURE = 7
    const val REASON_EXCESSIVE_RESOURCE_USAGE = 9

    /**
     * Raporlanan nedenler. Java çökmesi (REASON_CRASH) Crashlytics'te zaten var; kullanıcının kapatması, güncelleme
     * ve izin değişikliği hata değildir.
     */
    private val reported = setOf(
        REASON_SIGNALED, REASON_LOW_MEMORY, REASON_CRASH_NATIVE, REASON_ANR, REASON_INITIALIZATION_FAILURE,
        REASON_EXCESSIVE_RESOURCE_USAGE,
    )

    /** [lastSeen]'den sonraki raporlanacak kapanışlar, eskiden yeniye. */
    fun reportable(records: List<ExitRecord>, lastSeen: Long): List<ExitRecord> =
        records.filter { it.timestamp > lastSeen && it.reason in reported }.sortedBy { it.timestamp }

    /** Kayıtların en yenisinin anı (hiç yoksa [lastSeen]); bir dahaki açılışta aynı kapanış yeniden raporlanmaz. */
    fun newestTimestamp(records: List<ExitRecord>, lastSeen: Long): Long = maxOf(lastSeen, records.maxOfOrNull { it.timestamp } ?: lastSeen)

    fun reasonName(reason: Int): String = when (reason) {
        REASON_SIGNALED -> "signaled"
        REASON_LOW_MEMORY -> "low_memory"
        REASON_CRASH -> "crash"
        REASON_CRASH_NATIVE -> "crash_native"
        REASON_ANR -> "anr"
        REASON_INITIALIZATION_FAILURE -> "initialization_failure"
        REASON_EXCESSIVE_RESOURCE_USAGE -> "excessive_resource_usage"
        else -> "reason_$reason"
    }

    /** Crashlytics'te kümelenecek hata satırı: neden başlıkta, ayrıntı iletide. */
    fun message(record: ExitRecord, duringTranslation: Boolean): String =
        "${reasonName(record.reason)}${if (duringTranslation) " (çeviri sürerken)" else ""}: ${record.description ?: "-"}" +
            " importance=${record.importance} pss=${record.pssKb / 1024}MB rss=${record.rssKb / 1024}MB"
}

/** Önceki kapanış; Crashlytics'te ölümcül olmayan hata olarak görünür (yığın izi yok, neden iletide). */
class PreviousExitException(message: String) : Exception(message)
