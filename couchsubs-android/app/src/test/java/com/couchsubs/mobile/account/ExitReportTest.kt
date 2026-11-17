// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.account

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * "Çeviriyi başlatınca uygulama kapanıyor" bildirimlerinde Crashlytics boştu: yerel çökme, bellek yetmemesi ve ANR
 * Crashlytics'e hiç düşmüyordu. Önceki kapanışlar bir sonraki açılışta raporlanır.
 */
class ExitReportTest {
    private fun record(reason: Int, at: Long, description: String? = null) =
        ExitRecord(reason, at, description, importance = 125, pssKb = 300 * 1024L, rssKb = 400 * 1024L)

    @Test
    fun nativeCrashLowMemoryAndAnrAreReportedJavaCrashAndUserExitAreNot() {
        val records = listOf(
            record(ExitReport.REASON_CRASH_NATIVE, 50, "crash"),
            record(ExitReport.REASON_CRASH, 40),
            record(ExitReport.REASON_LOW_MEMORY, 30),
            record(10, 20), // USER_REQUESTED
            record(ExitReport.REASON_ANR, 10),
            record(1, 5), // EXIT_SELF
        )
        val reported = ExitReport.reportable(records, lastSeen = 0)
        assertEquals(listOf(ExitReport.REASON_ANR, ExitReport.REASON_LOW_MEMORY, ExitReport.REASON_CRASH_NATIVE), reported.map { it.reason })
    }

    @Test
    fun sameExitIsNotReportedTwice() {
        val records = listOf(record(ExitReport.REASON_CRASH_NATIVE, 50), record(ExitReport.REASON_LOW_MEMORY, 30))
        val seen = ExitReport.newestTimestamp(records, lastSeen = 0)
        assertEquals(50, seen)
        assertTrue(ExitReport.reportable(records, seen).isEmpty())
        // Yeni kapanış geldiğinde yalnız o raporlanır.
        val later = listOf(record(ExitReport.REASON_SIGNALED, 70)) + records
        assertEquals(listOf(70L), ExitReport.reportable(later, seen).map { it.timestamp })
        // Kayıt yoksa son görülen değişmez.
        assertEquals(50, ExitReport.newestTimestamp(emptyList(), 50))
    }

    @Test
    fun messageNamesReasonTranslationAndMemory() {
        val message = ExitReport.message(record(ExitReport.REASON_LOW_MEMORY, 1, "lmk"), duringTranslation = true)
        assertEquals("low_memory (çeviri sürerken): lmk importance=125 pss=300MB rss=400MB", message)
        assertEquals("crash_native: - importance=125 pss=300MB rss=400MB", ExitReport.message(record(ExitReport.REASON_CRASH_NATIVE, 1), false))
    }
}
