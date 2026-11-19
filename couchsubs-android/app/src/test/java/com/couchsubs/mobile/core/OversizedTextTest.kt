// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.util.concurrent.Executors
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Nino: dev yazılar (tabela, reklam panosu) altyazı değildir (Mac/iPhone: SubtitleBlockTests.swift'in "Dev yazılar"
 * bölümüyle aynı senaryolar, Windows: ReadingTests). Sondaki testler hattın bunları çevirmediğini ve günlüğe bir kez
 * yazdığını sınar.
 */
class OversizedTextTest {
    private val lowerHalf = TextBox(0.06, 0.56, 0.98, 1.0)

    @Test fun normalSubtitleLinesAreKept() {
        // Alanın %9'u × alan yüksekliği 0.44 ≈ karenin %4'ü: sıradan altyazı satırı.
        val reading = Reading(listOf(
            TextLine("I told you not to come here.", TextBox(0.3, 0.60, 0.7, 0.69)),
            TextLine("You never listen.", TextBox(0.38, 0.70, 0.62, 0.79)),
        ))
        assertEquals(reading.lines, reading.withoutOversizedLines(lowerHalf).lines)
        assertFalse(reading.isOversizedBlock(lowerHalf))
    }

    @Test fun giantSignLineIsDroppedButSubtitleStays() {
        // Tabela satırı alanın %30'u ≈ karenin %13'ü; altyazı yanında kalır.
        val sign = TextLine("Welcome to Leonida", TextBox(0.1, 0.05, 0.9, 0.35))
        val subtitle = TextLine("Where are we going?", TextBox(0.35, 0.80, 0.65, 0.88))
        val reading = Reading(listOf(sign, subtitle)).withoutOversizedLines(lowerHalf)
        assertEquals(listOf(subtitle), reading.lines)
    }

    @Test fun lineHeightIsMeasuredAgainstTheWholeFrame() {
        // Aynı satır dar bir alanda alanın yarısını kaplar ama karede %5'tir: atılmaz.
        val narrow = TextBox(0.2, 0.85, 0.8, 0.95)
        val line = TextLine("Stay close to me.", TextBox(0.2, 0.2, 0.8, 0.7))
        assertEquals(listOf(line), Reading(listOf(line)).withoutOversizedLines(narrow).lines)
        // Aynı oran bütün karede okunursa karenin yarısıdır: atılır.
        val full = TextBox(0.0, 0.0, 1.0, 1.0)
        assertTrue(Reading(listOf(line)).withoutOversizedLines(full).lines.isEmpty())
    }

    @Test fun linesWithoutBoxesAreNeverDropped() {
        val reading = Reading(listOf(TextLine("No position known.")))
        assertEquals(reading.lines, reading.withoutOversizedLines(lowerHalf).lines)
        assertFalse(reading.isOversizedBlock(lowerHalf))
    }

    @Test fun tallBlockIsNotASubtitle() {
        // Normal boyda ama üst üste yedi satır (afiş, not): blok karenin %26'sından yüksek ve 5 satırdan çok.
        val lines = (0 until 7).map { index ->
            val top = 0.05 + index * 0.12
            TextLine("Line number $index of a poster.", TextBox(0.3, top, 0.7, top + 0.09))
        }
        assertTrue(Reading(lines).isOversizedBlock(lowerHalf))
        // Üç satırlık uzun altyazı kalır.
        assertFalse(Reading(lines.take(3)).isOversizedBlock(lowerHalf))
    }

    @Test fun fewLinesCoveringTooMuchHeightAreNotASubtitle() {
        // İki satır ama aralarında büyük boşluk: kutu karenin %30'u.
        val reading = Reading(listOf(
            TextLine("Top of a billboard", TextBox(0.3, 0.05, 0.7, 0.15)),
            TextLine("bottom of a billboard", TextBox(0.3, 0.65, 0.7, 0.75)),
        ))
        assertTrue(reading.isOversizedBlock(lowerHalf))
    }

    // --- Hat ---

    private class Recorder : SubtitleSender {
        val sent = java.util.Collections.synchronizedList(mutableListOf<String>())
        override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) { sent.add(text) }
        override fun clear() {}
    }

    private class Recording : TextTranslator {
        val requested = java.util.Collections.synchronizedList(mutableListOf<String>())
        override fun translate(text: String): String {
            requested.add(text)
            return "<$text>"
        }
    }

    private val executor = Executors.newSingleThreadExecutor { Thread(it, "test translate").apply { isDaemon = true } }
    private val sender = Recorder()
    private val translator = Recording()
    private var now = 0L
    private val logged = mutableListOf<String>()
    private val pipeline = SubtitlePipeline(translator, sender, { now }, executor).apply {
        hudTop = null
        log = { logged.add(it) }
    }

    @After fun tearDown() { executor.shutdownNow() }

    private fun frame(lines: List<TextLine>, at: Long) {
        now = at
        pipeline.process(Reading(lines), lowerHalf)
    }

    private fun settle() {
        executor.submit {}.get()
    }

    @Test fun signOnScreenIsNotTranslatedAndLoggedOnce() {
        val sign = TextLine("Welcome to Leonida.", TextBox(0.1, 0.05, 0.9, 0.35))
        for (at in 0L..800L step 100) frame(listOf(sign), at)
        settle()
        assertTrue(translator.requested.isEmpty())
        assertTrue(sender.sent.isEmpty())
        assertEquals(1, logged.size)
        assertTrue(logged[0].startsWith("dev yazı: \"Welcome to Leonida.\""))
    }

    @Test fun subtitleNextToASignIsStillTranslated() {
        val sign = TextLine("Welcome to Leonida.", TextBox(0.1, 0.05, 0.9, 0.35))
        val subtitle = TextLine("Where are we going?", TextBox(0.35, 0.80, 0.65, 0.88))
        for (at in 0L..800L step 100) frame(listOf(sign, subtitle), at)
        settle()
        assertEquals(listOf("Where are we going?"), translator.requested)
        assertEquals(1, logged.size)
    }

    @Test fun posterBlockIsNotTranslatedAndLoggedOnce() {
        // Yedi normal boy satır: satır süzgecinden geçer, blok olarak atılır.
        val poster = (0 until 7).map { index ->
            val top = 0.05 + index * 0.12
            TextLine("Line number $index of a long poster.", TextBox(0.3, top, 0.7, top + 0.09))
        }
        for (at in 0L..800L step 100) frame(poster, at)
        settle()
        assertTrue(translator.requested.isEmpty())
        assertEquals(1, logged.size)
        assertTrue(logged[0].startsWith("dev blok: "))
    }

    @Test fun billboardWithGiantTitleAndPosterBodyLogsEachOnce() {
        // Dev başlık (satır olarak atılır) ve altında yedi satırlık gövde (blok olarak atılır): aynı karede iki ayrı
        // günlük satırı; dokuz karede yine yalnız iki satır.
        val title = TextLine("LEONIDA LOTTERY.", TextBox(0.1, 0.0, 0.9, 0.3))
        val body = (0 until 7).map { index ->
            val top = 0.32 + index * 0.09
            TextLine("Line number $index of a long poster.", TextBox(0.3, top, 0.7, top + 0.07))
        }
        for (at in 0L..800L step 100) frame(listOf(title) + body, at)
        settle()
        assertTrue(translator.requested.isEmpty())
        assertEquals(2, logged.size)
        assertTrue(logged.any { it.startsWith("dev yazı: ") })
        assertTrue(logged.any { it.startsWith("dev blok: ") })
    }
}
