// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.util.Collections
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/** Nino: çeviri havuzundan sonradan gelen çeviri ekrandaki satırın yerine konur (TV'ye `replaces = true`). */
class PoolUpgradeTest {
    private class Sender : SubtitleSender {
        val sent: MutableList<Pair<String, Boolean>> = Collections.synchronizedList(mutableListOf())
        override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) { sent += text to replaces }
        override fun clear() {}
    }

    private var time = 0L

    private fun pipeline(sender: Sender, translator: TextTranslator = TextTranslator { "Cihaz: $it" }) =
        SubtitlePipeline(translator, sender, { time }, Executors.newSingleThreadExecutor()).apply {
            holdReadings = true; packWait = 0; cleanWait = 0
        }

    private fun SubtitlePipeline.feed(vararg frames: String) {
        for (text in frames) {
            process(Reading.fromText(text), CropRegion().box)
            time += 100
        }
    }

    /** Çeviri iş parçacığındaki işler bitsin. */
    private fun settle(pipeline: SubtitlePipeline) {
        val field = SubtitlePipeline::class.java.getDeclaredField("executor").apply { isAccessible = true }
        (field.get(pipeline) as java.util.concurrent.ExecutorService).submit {}.get(5, TimeUnit.SECONDS)
    }

    @Test fun poolTranslationReplacesLineStillOnScreen() {
        val line = "Who the fuck are you?"
        val sender = Sender()
        val missed = mutableListOf<String>()
        val upgraded = mutableListOf<ShownPair>()
        val pipeline = pipeline(sender).apply {
            onPackMissed = { missed += it }
            onPairUpgraded = { upgraded += it }
        }
        repeat(4) { pipeline.feed(line); settle(pipeline) }
        assertEquals(listOf(line), missed)
        assertEquals(listOf("Cihaz: $line" to false), sender.sent.toList())
        pipeline.upgrade(line, "Sen de kimsin lan?")
        assertEquals("Sen de kimsin lan?" to true, sender.sent.last())
        assertEquals("havuz", upgraded.single().origin)
        // Aynı çeviri ikinci kez gelirse yeniden gönderilmez.
        pipeline.upgrade(line, "Sen de kimsin lan?")
        assertEquals(2, sender.sent.size)
        pipeline.shutdown()
    }

    @Test fun upgradeForOldLineDoesNotTouchScreen() {
        val first = "Get in the car!"
        val second = "Drive, drive, drive!"
        val sender = Sender()
        val pipeline = pipeline(sender)
        repeat(3) { pipeline.feed(first); settle(pipeline) }
        repeat(3) { pipeline.feed(second); settle(pipeline) }
        val before = sender.sent.size
        assertEquals("Cihaz: $second", sender.sent.last().first)
        pipeline.upgrade(first, "Bin arabaya!")
        // Ekrandan kalkmış satır yeniden gösterilmez; geri gelirse havuzun çevirisi gösterilir.
        assertEquals(before, sender.sent.size)
        pipeline.feed(first); settle(pipeline)
        assertEquals("Bin arabaya!", sender.sent.last().first)
        pipeline.shutdown()
    }

    @Test fun packLineIsNeverUpgraded() {
        val line = "Hold the gate."
        val sender = Sender()
        val pipeline = pipeline(sender).apply { packLookup = { if (it == line) PackMatch("Kapıyı tut.", "gta-v") else null } }
        repeat(3) { pipeline.feed(line); settle(pipeline) }
        assertEquals(listOf("Kapıyı tut." to false), sender.sent.toList())
        pipeline.upgrade(line, "Kapıyı tutun.")
        assertEquals(1, sender.sent.size)
        pipeline.shutdown()
    }

    @Test fun engineResultYieldsToPoolTranslationThatArrivedFirst() {
        val line = "No more stupid shit."
        val sender = Sender()
        var pooled: String? = null
        val shown = mutableListOf<ShownPair>()
        // Havuz ilk bakışta boş; satır motordayken sunucunun çevirisi gelir.
        val pipeline = pipeline(sender, TextTranslator { pooled = "Artık saçma sapan bok yemek yok."; "Cihaz: $it" }).apply {
            packLookup = { text -> if (text == line) pooled?.let { PackMatch(it, pooled = true) } else null }
            onPairShown = { shown += it }
        }
        repeat(3) { pipeline.feed(line); settle(pipeline) }
        assertEquals("Artık saçma sapan bok yemek yok.", sender.sent.first().first)
        assertEquals("havuz", shown.first().origin)
        assertEquals(0, pipeline.packHits)
        pipeline.shutdown()
    }

    @Test fun pooledLookupShowsAsPoolNotPack() {
        val line = "Move it!"
        val sender = Sender()
        val shown = mutableListOf<ShownPair>()
        val pipeline = pipeline(sender).apply {
            packLookup = { if (it == line) PackMatch("Kıpırda!", pooled = true) else null }
            onPairShown = { shown += it }
        }
        repeat(3) { pipeline.feed(line); settle(pipeline) }
        assertEquals("Kıpırda!", sender.sent.single().first)
        assertNotNull(shown.firstOrNull())
        assertEquals("havuz", shown.first().origin)
        assertEquals(0, pipeline.packHits)
        pipeline.shutdown()
    }
}
