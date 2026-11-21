// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.Collections

/** Nino: oyundaki telefonun sohbeti ve haritanın görev kartı Android'de de çevrilir (Mac, iPhone, Windows ile aynı). */
class PhoneWatcherTest {
    private val name = "gta6-telefon-brian-parlama"

    private fun watcher(calls: MutableList<String>, remember: Boolean = true, memory: File? = null) =
        PhoneWatcher({ Reading.Empty }, { text, _ ->
            calls.add(text)
            PhoneWatcher.Translation("TR $text", remember)
        }, memoryFile = memory, run = { it.run() }).apply { useGlossary = false }

    private fun panel(image: RgbImage) = PhonePanel.find(image) ?: error("telefon bulunamadı")

    @Test
    fun chatIsTranslatedBesideThePhoneAfterTwoSameReadings() {
        val image = NinoFixtures.frame("$name.jpg")
        val reading = NinoFixtures.lines(name)
        val calls = Collections.synchronizedList(mutableListOf<String>())
        val unknown = mutableListOf<String>()
        val watcher = watcher(calls)
        var last: List<ScreenTranslation.Item>? = null
        watcher.onChange = { last = it }
        watcher.onUnknown = { unknown += it }
        // İlk okuma yalnız bekletir (kaydırma sürerken yarım okunan satır çevrilmez).
        watcher.process(image, panel(image), reading)
        assertTrue(watcher.shown.isEmpty())
        assertTrue(calls.isEmpty())
        watcher.process(image, panel(image), reading)
        assertTrue(watcher.shown.isNotEmpty())
        assertTrue(watcher.shown.any { it.backdrop })
        assertTrue(watcher.shown.any { it.translation.startsWith("TR ") })
        assertEquals(calls.toSet(), unknown.toSet())
        assertEquals(watcher.shown, last)
        assertTrue("telefon yazıları altyazı sayılmasın", watcher.recentTexts.isNotEmpty())
        // Aynı ekran yeniden okununca çevirmene gidilmez.
        val before = calls.size
        watcher.process(image, panel(image), reading)
        assertEquals(before, calls.size)
        watcher.close()
    }

    @Test
    fun rememberedTranslationsComeBackFromTheFileButDeviceFallbackDoesNot() {
        val image = NinoFixtures.frame("$name.jpg")
        val reading = NinoFixtures.lines(name)
        val file = File.createTempFile("phone-memory", ".json").also { it.delete() }
        try {
            val device = watcher(mutableListOf(), remember = false, memory = file)
            repeat(2) { device.process(image, panel(image), reading) }
            assertTrue(device.shown.isNotEmpty())
            assertFalse("cihazın çevirisi hafızaya yazılmaz", file.exists())
            val first = watcher(mutableListOf(), memory = file)
            repeat(2) { first.process(image, panel(image), reading) }
            assertTrue(file.exists())
            // Nino yeniden açıldı: hafızadan gelir, çevirmene gidilmez.
            val calls = mutableListOf<String>()
            val second = watcher(calls, memory = file)
            repeat(2) { second.process(image, panel(image), reading) }
            assertTrue(second.shown.isNotEmpty())
            assertTrue(calls.toString(), calls.isEmpty())
        } finally {
            file.delete()
        }
    }

    @Test
    fun mapKeysOnThePhoneClearIt() {
        val image = NinoFixtures.frame("$name.jpg")
        val watcher = watcher(mutableListOf())
        repeat(2) { watcher.process(image, panel(image), NinoFixtures.lines(name)) }
        assertTrue(watcher.shown.isNotEmpty())
        val box = panel(image).box
        watcher.process(image, panel(image), Reading(listOf(TextLine("RECENTER", TextBox(box.left, 0.8, box.left + 0.05, 0.82)))))
        assertTrue(watcher.shown.isEmpty())
    }

    @Test
    fun pausedWatcherDoesNotLookForThePhone() {
        var asked = false
        val watcher = watcher(mutableListOf())
        watcher.paused = { true }
        watcher.offer({ asked = true; NinoFixtures.frame("$name.jpg") }) { null }
        assertFalse("harita açıkken kare bile kopyalanmaz", asked)
    }

    @Test
    fun resetClearsAndDropsTheOldSession() {
        val image = NinoFixtures.frame("$name.jpg")
        val watcher = watcher(mutableListOf())
        repeat(2) { watcher.process(image, panel(image), NinoFixtures.lines(name)) }
        var cleared = false
        watcher.onChange = { cleared = it.isEmpty() }
        watcher.reset()
        assertTrue(cleared)
        assertTrue(watcher.shown.isEmpty())
        assertTrue(watcher.recentTexts.isEmpty())
        // Eski oturumun okuması (started = 0) yeni oturuma yazılmaz.
        repeat(2) { watcher.process(image, panel(image), NinoFixtures.lines(name), started = 0) }
        assertTrue(watcher.shown.isEmpty())
    }

    @Test
    fun iconsAndEntitiesAreStripped() {
        assertEquals("Tamam & geliyorum", PhoneWatcher.withoutIcons("Tamam &amp; ✕ geliyorum"))
        assertEquals("Don't", PhoneWatcher.withoutEntities("Don&#39;t"))
    }

    /** Siyah-beyaz okumada telefon sanılan altyazı sahnesi, renkli kopyada telefon değildir (Android'e renk bunun için). */
    @Test
    fun subtitleSceneIsNotAPhoneInColour() {
        assertNull(PhonePanel.find(NinoFixtures.frame("gta6-altyazi-beyaz.jpg")))
    }

    @Test
    fun phoneLinesAreDroppedFromTheSubtitleReading() {
        val place = TextBox(0.0, 0.6, 1.0, 1.0)
        // Alana göre kutular: telefonun ekranındaki satır, çizginin üstündeki satır ve gerçek altyazı.
        val raw = Reading(listOf(
            TextLine("Where are you right now", TextBox(0.62, 0.1, 0.78, 0.15)),
            TextLine("Some sign text up here", TextBox(0.2, 0.2, 0.4, 0.25)),
            TextLine("We need to go now, Jason.", TextBox(0.3, 0.8, 0.7, 0.86)),
        ))
        val phone = TextBox(0.6, 0.2, 0.8, 0.8)
        val kept = PhoneLines.without(raw, place, phone, wantsPhone = true, areaColor = null, phoneTexts = emptyList())
        assertEquals(listOf("We need to go now, Jason."), kept.lines.map { it.text })
        // Telefon bulunamasa da telefonda az önce görülen mesaj altyazı sayılmaz.
        val again = PhoneLines.without(Reading(listOf(TextLine("where are you right now", TextBox(0.3, 0.8, 0.7, 0.86)))),
            place, null, wantsPhone = true, areaColor = null, phoneTexts = listOf("Where are you right now?"))
        assertTrue(again.lines.isEmpty())
        assertEquals(0.65, PhoneLines.mask(TextBox(0.6, 0.2, 0.8, 0.5)).bottom, 1e-9)
        assertEquals("altyazının başladığı yere inmez", 0.84, PhoneLines.mask(TextBox(0.6, 0.2, 0.8, 0.75)).bottom, 1e-9)
    }
}

class MapCardWatcherTest {
    private fun watcher(calls: MutableList<String> = mutableListOf()) =
        MapCardWatcher({ Reading.Empty }, { calls.add(it); "Türkçe $it" }, run = { it.run() })

    @Test
    fun cardTranslationGoesUnderTheCard() {
        val reading = NinoFixtures.lines("gta6-harita-buckme")
        val card = MapCard.find(reading) ?: error("kart yok")
        val watcher = watcher()
        watcher.process(null, reading)
        val item = watcher.shown.single()
        assertTrue(item.card)
        assertTrue("kartın altında", item.box.top > card.box.bottom)
        assertTrue(item.translation, item.translation.startsWith("TÜRKÇE "))
        assertEquals(1 + card.sentences.size, item.translation.split('\n').size)
        assertTrue(watcher.mapOpen)
    }

    @Test
    fun sameCardIsNotTranslatedTwiceAndLeavesWithTheMap() {
        val reading = NinoFixtures.lines("gta6-harita-buckme")
        val calls = mutableListOf<String>()
        val watcher = watcher(calls)
        watcher.process(null, reading)
        val count = calls.size
        watcher.process(null, reading)
        assertEquals(count, calls.size)
        // Harita kapandı (tuş listesi yok): Türkçe kalkar.
        watcher.process(null, NinoFixtures.lines("gta6-telefon-brian-parlama"))
        assertTrue(watcher.shown.isEmpty())
        // Haritaya dönülünce hafızadan gelir.
        watcher.process(null, reading)
        assertEquals(count, calls.size)
        assertNotNull(watcher.shown.singleOrNull())
    }

    @Test
    fun placeNamesAndTermsAreKept() {
        assertTrue(MapCardWatcher.isPlaceName("RIDEOUT CUSTOMS"))
        assertFalse(MapCardWatcher.isPlaceName("JASON'S MAILBOX"))
        assertEquals("işaretli banknotlar", MapCardWatcher.withMapTerms("işaretli faturalar"))
    }
}
