// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.atan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Nino: telefonun yanındaki mesajlaşma paneli ve uygulama baloncukları (Windows: PhoneBubbleTests). */
class PhoneBubbleTest {
    private val panel = PhonePanel.Panel(TextBox(0.59, 0.2, 0.79, 0.81), 0.59, 0.0, 0.2)
    private val measure: (String, Double, Double) -> Pair<Int, Int> = { text, _, _ -> Pair(1, text.length) }

    @Test
    fun translationCoversTheBubbleInItsColour() {
        val messages = listOf(
            PhoneThread.Message("On my way", TextBox(0.61, 0.5, 0.7, 0.53), 0.02),
            PhoneThread.Message("Casa De Donnie", TextBox(0.61, 0.6, 0.7, 0.63), 0.02),
        )
        val items = PhoneThread.covers(messages, listOf("Geliyorum", "Casa De Donnie"),
            { x, _ -> if (x < 0.6075) Rgb(233, 233, 236) else Rgb(40, 40, 40) })
        assertEquals(1, items.size)
        val item = items[0]
        assertEquals("#e9e9ec", item.fill)
        assertEquals("#2c2c2e", item.ink)
        assertTrue(item.box.left < 0.61 && item.box.right > 0.7 && item.box.top < 0.5 && item.box.bottom > 0.53)
    }

    @Test
    fun tiltedPhoneHasAnAngle() {
        val tilted = PhonePanel.Panel(panel.box, 0.6, -0.1, 0.2)
        assertEquals(atan(0.1 * 16 / 9) * 180 / Math.PI, tilted.angle, 1e-9)
        assertTrue(tilted.angle > 9)
        assertEquals(0.0, panel.angle, 1e-9)
    }

    @Test
    fun sideBubblesFormAChatPanelBesideThePhone() {
        val messages = listOf(
            PhoneThread.Message("On my way", TextBox(0.61, 0.5, 0.7, 0.53), 0.02),
            PhoneThread.Message("Where at?", TextBox(0.72, 0.6, 0.77, 0.62), 0.02),
        )
        val items = PhoneThread.sideBubbles(messages, listOf("Geliyorum", "Nerede?"), panel,
            { x, _ -> if (x < 0.7) Rgb(233, 233, 236) else Rgb(200, 220, 245) }, measure)
        assertEquals(3, items.size)
        val backdrop = items[0]
        assertTrue(backdrop.backdrop)
        assertEquals(panel.box.top, backdrop.box.top, 1e-9)
        assertEquals(panel.box.bottom, backdrop.box.bottom, 1e-9)
        assertTrue("telefonun solundaki boşlukta", backdrop.box.right <= panel.box.left)
        assertEquals(PhoneThread.BACKDROP_ALPHA, backdrop.alpha)
        val incoming = items[1]
        val outgoing = items[2]
        for (item in listOf(incoming, outgoing)) {
            assertTrue(item.side)
            assertTrue(item.box.left >= backdrop.box.left && item.box.right <= backdrop.box.right)
            assertNull(item.angle)
        }
        assertEquals(0.5, incoming.box.top, 0.001)
        assertTrue("gelen solda, giden sağda", incoming.box.left < outgoing.box.left)
        assertEquals("#f8f8f9", incoming.fill)
        assertEquals("#acccfe", outgoing.fill)
        // Işık bütün balonları mavimsi gösterse de en gri balon gelen sayılır; belirgin mavi balon sağa yaslı.
        val gray = PhoneThread.Message("Honestly if they didn't let us", TextBox(0.61, 0.4, 0.77, 0.43), 0.02)
        val longOne = PhoneThread.Message("No go. Cal's tryin to avoid that chick", TextBox(0.61, 0.5, 0.77, 0.53), 0.02)
        val tinted = PhoneThread.sideBubbles(listOf(gray, longOne), listOf("Dürüst olmak gerekirse", "Yok, olmaz."), panel,
            { _, y -> if (y < 0.45) Rgb(137, 154, 183) else Rgb(120, 150, 215) }, measure)
        assertEquals(tinted[0].box.left + 0.012, tinted[1].box.left, 1e-9)
        assertEquals(tinted[0].box.right - 0.012, tinted[2].box.right, 1e-9)
    }

    @Test
    fun chatTitleIsShownOnThePanel() {
        val messages = listOf(PhoneThread.Message("On my way", TextBox(0.61, 0.5, 0.7, 0.53), 0.02))
        val items = PhoneThread.sideBubbles(messages, listOf("Geliyorum"), panel, { _, _ -> Rgb(233, 233, 236) }, measure, title = "Lucia")
        assertEquals("Lucia", items[0].translation)
        assertTrue(items[0].backdrop)
    }

    @Test
    fun coversFollowThePhone() {
        val item = ScreenTranslation.Item("a", "b", TextBox(0.6, 0.5, 0.7, 0.52), 0.02, fill = "#ffffff")
        val moved = PhoneThread.shifted(listOf(item), 0.01, -0.02)[0]
        assertEquals(0.61, moved.box.left, 1e-9)
        assertEquals(0.48, moved.box.top, 1e-9)
        assertEquals("#ffffff", moved.fill)
    }

    @Test
    fun appLinesSkipNumbersAndIcons() {
        val reading = Reading(listOf(
            TextLine("$500", TextBox(0.70, 0.33, 0.77, 0.36)),
            TextLine("◆ Checking Account", TextBox(0.61, 0.38, 0.72, 0.40)),
            TextLine("$4,900 to next goal", TextBox(0.64, 0.65, 0.74, 0.67)),
        ))
        val lines = PhoneThread.appLines(reading, panel)
        assertEquals(listOf("Checking Account", "$4,900 to next goal"), lines.map { it.text })
        val items = PhoneThread.sideBubbles(lines, listOf("Vadesiz Hesap", "Sonraki hedefe $4.900"), panel,
            { _, y -> if (y < 0.5) Rgb(155, 80, 187) else Rgb(233, 233, 236) }, measure, chat = false)
        assertEquals(3, items.size)
        assertTrue("telefondaki gibi: içeride başlayan satır panelde de içeride", items[1].box.left < items[2].box.left)
        assertEquals("#f5f5f7", items[1].ink)
    }

    @Test
    fun appBubblesUseTheAppColourBesideThePhone() {
        val lines = listOf(
            PhoneThread.Message("Checking Account", TextBox(0.61, 0.38, 0.72, 0.40), 0.02),
            PhoneThread.Message("buckme", TextBox(0.61, 0.28, 0.66, 0.30), 0.02),
        )
        val items = PhoneThread.appBubbles(lines, listOf("Vadesiz Hesap", "BuckMe mi?"), panel,
            { _, y -> if (y < 0.45) Rgb(155, 80, 187) else Rgb(233, 233, 236) })
        assertEquals(1, items.size)
        val item = items[0]
        assertEquals("Vadesiz Hesap", item.translation)
        assertEquals("#9b50bb", item.fill)
        assertEquals("#ffffff", item.ink)
        assertTrue("telefonun solunda", item.box.right < panel.box.left)
        assertEquals(0.39, (item.box.top + item.box.bottom) / 2, 0.002)
    }

    @Test
    fun smallImageIsSampledProportionally() {
        // 64×36 kare (örnekleyicinin 960×540'ından küçük): Windows gibi büyütülerek örneklenir, null dönmez.
        val rgb = ByteArray(64 * 36 * 3)
        for (y in 0 until 36) for (x in 0 until 64) {
            val o = (y * 64 + x) * 3
            rgb[o] = (if (x < 32) 200 else 10).toByte()
            rgb[o + 1] = 20
            rgb[o + 2] = 30
        }
        val sample = PhonePanel.sampler(RgbImage(64, 36, rgb))
        assertEquals(Rgb(200, 20, 30), sample(0.25, 0.5))
        assertEquals(Rgb(10, 20, 30), sample(0.75, 0.5))
        assertNull(sample(0.0, 0.5))
    }
}
