// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Mac'teki SubtitleLayoutTests ile aynı kurallar. */
class SubtitleLayoutTest {
    private fun box(top: Double, bottom: Double) = TextBox(0.3, top, 0.7, bottom)

    @Test
    fun usesFallbackUntilLearned() {
        val layout = SubtitleLayout(null)
        repeat(SubtitleLayout.MINIMUM_SAMPLES - 1) { layout.record(box(0.80, 0.86), "rdr2") }
        assertEquals(SubtitleLayout.FALLBACK_HUD_TOP, layout.hudTop("rdr2")!!, 0.0)
        assertNull(layout.band("rdr2"))
    }

    @Test
    fun learnsBandAboveTutorialLine() {
        val layout = SubtitleLayout(null)
        repeat(12) { i -> layout.record(box(0.79 + (i % 3) * 0.01, 0.85 + (i % 3) * 0.01), "rdr2") }
        val hud = layout.hudTop("rdr2")!!
        assertTrue(hud > 0.89 && hud < 0.93)
    }

    @Test
    fun gameWithLowSubtitlesIsNotCut() {
        val layout = SubtitleLayout(null)
        repeat(10) { layout.record(box(0.90, 0.95), "low") }
        val hud = layout.hudTop("low")
        assertTrue(hud == null || hud > 0.95)
    }

    @Test
    fun savesAndLoads() {
        val file = File.createTempFile("layout", ".json")
        val layout = SubtitleLayout(file)
        repeat(9) { layout.record(box(0.8, 0.86), "g") }
        assertNotNull(SubtitleLayout(file).band("g"))
    }

    @Test
    fun longLivedTutorialLineIsSkippedWhileDialogueChanges() {
        val sender = object : SubtitleSender {
            override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) {}
            override fun clear() {}
        }
        val pipeline = SubtitlePipeline({ it }, sender)
        val tip = TextLine("Approach your horse and hold L1 to view stored weapons", TextBox(0.3, 0.9, 0.7, 0.95))
        pipeline.withoutStaleLines(Reading(listOf(tip)), 0)
        val later = pipeline.withoutStaleLines(Reading(listOf(TextLine("You two, get up there.", TextBox(0.3, 0.8, 0.7, 0.85)), tip)), 10_000)
        assertEquals(listOf("You two, get up there."), later.lines.map { it.text })
    }
}
