// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Nino: gerçek GTA 6 karelerinde telefon ve sohbet (Windows: RealPhoneFrameTests ve PhoneWatcherTests'in kare/satır
 * sınamaları; Mac: RealPhoneFrameTests, DarkPhoneTests, DimPhoneTests…). Kareler en çok 960×540 renkli kopya olarak okunur.
 */
class PhoneRealFrameTest {
    private fun frame(name: String, fullSize: Boolean = false) = NinoFixtures.frame(name, fullSize)

    @Test
    fun silverPhoneIsFoundInEveryFrame() {
        for (name in listOf("gta6-telefon-donnie.jpg", "gta6-telefon-kenton.jpg", "gta6-telefon-shirley.jpg", "gta6-telefon-liste.jpg")) {
            val panel = PhonePanel.find(frame(name))
            assertNotNull(name, panel)
            assertEquals(name, 0.59, panel!!.box.left, 0.02)
            assertEquals(name, 0.79, panel.box.right, 0.02)
            assertEquals(name, 0.20, panel.box.top, 0.03)
            assertEquals(name, 0.82, panel.box.bottom, 0.03)
        }
    }

    @Test
    fun tiltedPhoneCutByTheBottomEdgeIsFound() {
        val panel = PhonePanel.find(frame("gta6-telefon-egik-alt.jpg"))!!
        assertEquals(0.58, panel.box.top, 0.03)
        assertTrue(panel.box.bottom > 0.96)
        assertEquals(0.52, (panel.box.left + panel.box.right) / 2, 0.03)
    }

    @Test
    fun darkThemedAppIsFoundButDarkClothesAreNot() {
        val panel = PhonePanel.find(frame("gta6-telefon-koyu-rydeme.jpg"))!!
        assertEquals(0.69, (panel.box.left + panel.box.right) / 2, 0.03)
        assertNull(PhonePanel.find(frame("gta6-menu-kapusonlu.jpg")))
    }

    @Test
    fun trackerKeepsThePhoneWhileItsBodyIsThere() {
        // Android'in gördüğü 960×540 kopya. Bu boyda kapüşonlu menüde koyu pay 0,469 ölçülür; koyu telefonu tutma eşiği
        // 0,50 olduğundan (PhonePanel.Tracker.KEEP_DARK_SHARE) hayalet telefon kalmaz, gerçek alt pencere (0,59) tutulur.
        val first = frame("gta6-telefon-koyu-rydeme.jpg")
        val sheet = frame("gta6-telefon-koyu-altpencere.jpg")
        val menu = frame("gta6-menu-kapusonlu.jpg")
        assertNull(PhonePanel.find(sheet))
        val tracker = PhonePanel.Tracker()
        val found = tracker.locate(first)
        assertNotNull(found)
        assertEquals(found!!.box, tracker.locate(sheet)?.box)
        assertNull(tracker.locate(menu))
        assertNull(tracker.locate(sheet))
    }

    @Test
    fun dimmedPhoneIsFoundAndItsColoursLifted() {
        val image = frame("gta6-telefon-karanlik.jpg")
        val panel = PhonePanel.find(image)!!
        assertEquals(0.36, panel.box.left, 0.03)
        assertEquals(0.60, panel.box.right, 0.03)
        // "Dropped that stuff off for you" balonu (mavi): renk kanalları karışırsa kırmızı çıkar.
        val blue = PhonePanel.liftedSampler(image, panel)(0.44, 0.46)!!
        assertTrue(blue.toString(), blue.b > blue.r + 15)
        assertTrue(blue.toString(), blue.b > 150)
    }

    @Test
    fun rydemeDarkThemeIsNotLifted() {
        val image = frame("gta6-telefon-koyu-rydeme.jpg")
        val panel = PhonePanel.find(image)!!
        val lifted = PhonePanel.liftedSampler(image, panel)
        val plain = PhonePanel.sampler(image)
        val y = (panel.box.top + panel.box.bottom) / 2
        val x = panel.left(y) + panel.width * 0.5
        assertEquals(plain(x, y)?.r, lifted(x, y)?.r)
    }

    @Test
    fun otherPhoneFramesAreFound() {
        for ((name, center) in listOf("gta6-telefon-lucia-foto.jpg" to 0.47, "gta6-telefon-brian-parlama.jpg" to -1.0, "gta6-telefon-egik-mavi.jpg" to -1.0)) {
            val panel = PhonePanel.find(frame(name))
            assertNotNull(name, panel)
            if (center > 0) assertEquals(name, center, (panel!!.box.left + panel.box.right) / 2, 0.04)
        }
    }

    @Test
    fun daylightPhoneWithPhotoIsAThreadWithTitle() {
        val panel = PhonePanel.find(frame("gta6-telefon-lucia-foto.jpg"))!!
        val reading = NinoFixtures.lines("gta6-telefon-lucia-foto")
        assertTrue(PhoneThread.isThread(reading, panel))
        assertEquals("Lucia", PhoneThread.titleText(reading, panel))
    }

    @Test
    fun chatWithGlareIsStillAThread() {
        val panel = PhonePanel.find(frame("gta6-telefon-brian-parlama.jpg"))!!
        val reading = NinoFixtures.lines("gta6-telefon-brian-parlama")
        assertTrue(PhoneThread.isThread(reading, panel))
        val messages = PhoneThread.messages(reading, panel)
        assertFalse(messages.any { it.text == "Brian" })
        assertTrue(messages.any { it.text.startsWith("Remember, you get your hands") })
    }

    @Test
    fun blueMessagesGoRightOnTiltedPhone() {
        val image = frame("gta6-telefon-egik-mavi.jpg")
        val panel = PhonePanel.find(image)!!
        val reading = NinoFixtures.lines("gta6-telefon-egik-mavi")
        val messages = PhoneThread.messages(reading, panel)
        val items = PhoneThread.sideBubbles(messages, messages.map { "TR " + it.text }, panel,
            PhonePanel.liftedSampler(image, panel), { t, _, _ -> Pair(1, t.length) }).filter { !it.backdrop }
        val left = items.minOf { it.box.left }
        fun right(start: String) = items.first { it.source.startsWith(start, ignoreCase = true) }.box.left > left + 0.02
        assertTrue(right("Shit went sideways"))
        assertTrue(right("Will do"))
        assertFalse(right("Ah crap"))
        assertFalse(right("Remember"))
    }

    /**
     * Nino (kullanıcı): GTA'da altyazı koyu sahnede beyaz yazıdır; telefondaki mesaj açık zeminde koyu yazıdır ve altyazı
     * bölgesine girse de altyazı sayılmaz (Mac: DarkOnLightTests). Bölge, uygulamadaki gibi kırpılıp örneklenir.
     */
    private fun subtitleArea(name: String): Pair<List<TextLine>, ColorSampler> {
        val region = CropRegion(top = 0.66, bottom = 0.97, left = 0.14, right = 0.86)
        val color = PhonePanel.sampler(NinoFixtures.crop(frame("$name.jpg"), region))
        // Satırlar kareye göre yazılı; bölgeye göre yerleşir.
        val lines = NinoFixtures.lines(name).lines.filter { l -> l.text.count { it.isLetter() } >= 4 }.map { l ->
            val b = l.box!!
            l.copy(box = TextBox((b.left - 0.14) / 0.72, (b.top - 0.66) / 0.31, (b.right - 0.14) / 0.72, (b.bottom - 0.66) / 0.31))
        }
        return Pair(lines, color)
    }

    @Test
    fun whiteSubtitleIsNotDarkOnLight() {
        val (lines, color) = subtitleArea("gta6-altyazi-beyaz")
        val subtitle = lines.first { it.text.contains("gonna love it") }
        assertFalse(subtitle.text, PhoneThread.isDarkOnLight(subtitle.box!!, color))
        val phone = lines.filter { it.text.contains("finder") || it.text.contains("lockups") }
        assertTrue(phone.isNotEmpty())
        for (line in phone) assertTrue(line.text, PhoneThread.isDarkOnLight(line.box!!, color))
    }

    @Test
    fun phoneMessageIsDarkOnLight() {
        val (lines, color) = subtitleArea("gta6-telefon-yakin-alt")
        val message = lines.filter { it.text.contains("plane") || it.text.contains("good to her") }
        assertTrue(message.isNotEmpty())
        for (line in message) assertTrue(line.text, PhoneThread.isDarkOnLight(line.box!!, color))
    }
}
