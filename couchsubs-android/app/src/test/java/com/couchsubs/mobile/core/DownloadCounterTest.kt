// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.net.URL
import java.util.Locale

/** Toplam indirme sayacı (Mac: DownloadCounterTests.swift ile aynı durumlar). */
class DownloadCounterTest {
    private class MemoryStore(override var downloadTotal: Int = 0) : DownloadCounter.Store

    @Test fun parsesTheServerReply() {
        assertEquals(3439, DownloadCounter.parse("""{"ok":true,"downloads":3439}"""))
        assertNull(DownloadCounter.parse("""{"ok":true}"""))
        assertNull(DownloadCounter.parse("""{"downloads":0}"""))
        assertNull(DownloadCounter.parse("""{"downloads":null}"""))
        assertNull(DownloadCounter.parse("""{"downloads":"3439"}"""))
        assertNull(DownloadCounter.parse("bozuk"))
    }

    /** Sayı alınamazsa son bilinen sayı kalır; yeniden açılışta da oradan başlar. Üstüne ekleme yapılmaz. */
    @Test fun keepsTheLastKnownTotalWhenTheServerCannotBeReached() {
        val store = MemoryStore()
        var reply: String? = """{"downloads":3439}"""
        var now = 1_000_000L
        val asked = mutableListOf<URL>()
        val counter = DownloadCounter(store, URL("https://example.invalid"), { asked += it; reply }) { now }
        assertNull(counter.total.value)
        counter.refresh()
        assertEquals(3439, counter.total.value)
        assertEquals(3439, store.downloadTotal)
        assertEquals(listOf("https://example.invalid/v1/config"), asked.map { it.toString() })
        reply = null
        now += 5_000_000
        counter.refresh()
        assertEquals(2, asked.size)
        assertEquals(3439, counter.total.value)
        assertEquals(3439, DownloadCounter(store, null, { null }).total.value)
    }

    /** Sunucuya en çok 10 dakikada bir sorulur; havuzun aldığı cevap verilince de yeniden sorulmaz. */
    @Test fun asksAtMostOncePerInterval() {
        var now = 0L
        var asked = 0
        val counter = DownloadCounter(MemoryStore(), URL("https://example.invalid"), { asked++; """{"downloads":10}""" }) { now }
        counter.refresh()
        now += DownloadCounter.INTERVAL_MS - 1
        counter.refresh()
        assertEquals(1, asked)
        now += 1
        counter.refresh()
        assertEquals(2, asked)
        // Çeviri havuzu aynı cevabı az önce aldı: sayı güncellenir, ayrıca istek yapılmaz.
        now += DownloadCounter.INTERVAL_MS
        counter.accept("""{"ok":true,"translate":{"enabled":true},"downloads":25}""")
        assertEquals(25, counter.total.value)
        counter.refresh()
        assertEquals(2, asked)
        // Alanı olmayan cevap eldeki sayıyı silmez.
        counter.accept("""{"ok":true}""")
        assertEquals(25, counter.total.value)
    }

    /** Hiç alınamadıysa sayı yoktur (gösterge görünmez); adres yoksa sorulmaz. */
    @Test fun hasNoTotalUntilTheServerAnswers() {
        var asked = 0
        val counter = DownloadCounter(MemoryStore(), null, { asked++; """{"downloads":10}""" })
        counter.refresh()
        assertNull(counter.total.value)
        assertEquals(0, asked)
    }

    /** Sayı olduğu gibi, binlik ayırıcısı yerel biçimde yazılır. */
    @Test fun formatsWithTheLocalGroupingSeparator() {
        assertEquals("3.439", DownloadCounter.format(3439, Locale.forLanguageTag("tr")))
        assertEquals("3,439", DownloadCounter.format(3439, Locale.forLanguageTag("en")))
        assertEquals("999", DownloadCounter.format(999, Locale.forLanguageTag("tr")))
        assertEquals("1.234.567", DownloadCounter.format(1234567, Locale.forLanguageTag("tr")))
    }
}
