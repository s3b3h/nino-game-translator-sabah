// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Nino: oyundaki telefonun ekranı (Windows: PhonePanelTests.cs, Mac: PhonePanelTests.swift ile aynı beklentiler). */
class PhonePanelTest {
    /** 240×135 haritada telefonun ekranı: x 139–190, y 27–115 (gerçek karelerdeki yer). */
    private fun phone(x: Int, y: Int) = x in 139..190 && y in 27..115

    /** Beyaz olmayan her nokta koyu (karanlık sahne). */
    private fun find(isWhite: (Int, Int) -> Boolean): TextBox? =
        PhonePanel.find(240, 135, isWhite) { x, y -> !isWhite(x, y) }?.box

    private fun panel(left: Double, top: Double, right: Double, bottom: Double) =
        PhonePanel.Panel(TextBox(left, top, right, bottom), left, 0.0, right - left)

    private fun line(text: String, left: Double, top: Double, right: Double, bottom: Double) =
        TextLine(text, TextBox(left, top, right, bottom))

    @Test
    fun leaningPanelIsFound() {
        val found = PhonePanel.find(240, 135, { x, y ->
            if (y < 24 || y > 105) return@find false
            val left = 99 - PhonePanel.round((y - 24) * 0.16)
            x >= left && x <= left + 45
        }) { _, _ -> true }
        assertNotNull(found)
        val panel = found!!
        assertEquals(-0.16, panel.lean * 240 / 135, 0.03)
        assertEquals(24.0 / 135, panel.box.top, 0.01)
        assertEquals(106.0 / 135, panel.box.bottom, 0.01)
        assertEquals((99 + 23) / 240.0, panel.center(panel.box.top), 0.012)
        assertEquals((86 + 23) / 240.0, panel.center(panel.box.bottom), 0.012)
    }

    @Test
    fun findsWhitePortraitPanel() {
        val box = find(::phone)!!
        assertEquals(139.0 / 240, box.left, 0.01)
        assertEquals(191.0 / 240, box.right, 0.01)
        assertEquals(27.0 / 135, box.top, 0.01)
        assertEquals(116.0 / 135, box.bottom, 0.01)
    }

    @Test
    fun panelWithPhotoAndBubblesIsStillFound() {
        assertNotNull(find { x, y ->
            when {
                !phone(x, y) -> false
                y in 40..75 && x in 144..185 -> false
                y in 95..108 && x in 160..186 -> false
                else -> true
            }
        })
    }

    @Test
    fun notPhones() {
        // Çerçevesi koyu olmayan beyaz dikdörtgen, kenardaki duvar, üst kenara dayanan kapı, karanlık sahne, gökyüzü,
        // yatay kutu ve kenarları oynayan leke telefon değildir.
        assertNull(PhonePanel.find(240, 135, ::phone) { _, _ -> false })
        assertNull(find { x, y -> x in 12..65 && y in 7..88 })
        assertNull(find { x, y -> x in 100..150 && y in 0..68 })
        assertNull(find { _, _ -> false })
        assertNull(find { _, y -> y < 70 })
        assertNull(find { x, y -> x in 150..220 && y in 110..134 })
        assertNull(find { x, y -> y in 20..120 && x >= 100 + (y * 7) % 23 && x <= 150 + (y * 11) % 29 })
    }

    @Test
    fun threadMessagesAreGroupedAndLabelsSkipped() {
        val reading = Reading(listOf(
            line("Kenton", 0.66, 0.22, 0.70, 0.24),
            line("Nuestra Señora del Ocio", 0.63, 0.295, 0.755, 0.315),
            line("Dropped off scuba to yuh boat", 0.60, 0.372, 0.752, 0.394),
            line("man. Happy hunting!", 0.60, 0.398, 0.70, 0.42),
            line("New message", 0.648, 0.503, 0.718, 0.522),
            line("Still can't believe u found them", 0.60, 0.558, 0.753, 0.58),
            line("doubloons. U got that luck boy.", 0.60, 0.582, 0.754, 0.604),
            line("Need u out there on these", 0.60, 0.607, 0.731, 0.629),
            line("wrecks man.", 0.60, 0.632, 0.662, 0.652),
            line("Yeah, I'm on it man.", 0.667, 0.689, 0.766, 0.712),
        ))
        assertEquals(listOf(
            "Dropped off scuba to yuh boat man. Happy hunting!",
            "Still can't believe u found them doubloons. U got that luck boy. Need u out there on these wrecks man.",
            "Yeah, I'm on it man.",
        ), PhoneThread.messages(reading, panel(0.58, 0.197, 0.793, 0.854)).map { it.text })
    }

    @Test
    fun threadHasCenteredNameOnTopButListDoesNot() {
        val thread = Reading(listOf(line("Kenton", 0.653, 0.233, 0.690, 0.248), line("Hey Jason! Was good meeting u", 0.595, 0.351, 0.750, 0.377)))
        assertTrue(PhoneThread.isThread(thread, panel(0.575, 0.215, 0.783, 0.859)))
        val list = Reading(listOf(
            line("Suggested", 0.608, 0.230, 0.661, 0.249),
            line("Donnie", 0.635, 0.272, 0.669, 0.285), line("Go get em", 0.635, 0.297, 0.685, 0.313),
            line("Chuck's Gun Shop", 0.634, 0.347, 0.725, 0.367), line("Hey Jason. You good? I saw", 0.634, 0.371, 0.772, 0.391),
        ))
        assertFalse(PhoneThread.isThread(list, panel(0.583, 0.207, 0.792, 0.852)))
        // Başlığı virgüllü yer adı olan sohbet ("Fleeca, Laguna Lane") de sohbettir.
        val place = Reading(listOf(line("Fleeca, Laguna Lane", 0.64, 0.21, 0.74, 0.23), line("Hello Mr. Duval. Please see the", 0.61, 0.55, 0.76, 0.57)))
        assertTrue(PhoneThread.isThread(place, panel(0.59, 0.2, 0.79, 0.81)))
        assertEquals("Fleeca, Laguna Lane", PhoneThread.titleText(place, panel(0.59, 0.2, 0.79, 0.81)))
    }

    @Test
    fun attachmentLabelsAreNotMessages() {
        val reading = Reading(listOf(
            line("Kenton", 0.653, 0.233, 0.690, 0.248),
            line("Messages encrypted", 0.620, 0.296, 0.734, 0.322),
            line("Map Pin Expired", 0.624, 0.478, 0.707, 0.496),
            line("Here r the spots man. These", 0.595, 0.557, 0.736, 0.576),
            line("wrecks should be a good place", 0.595, 0.581, 0.747, 0.602),
            line("Nuestra Señora de la", 0.626, 0.646, 0.734, 0.665),
            line("Ética Laxa", 0.625, 0.668, 0.681, 0.694),
        ))
        assertEquals(listOf("Here r the spots man. These wrecks should be a good place"),
            PhoneThread.messages(reading, panel(0.575, 0.215, 0.783, 0.859)).map { it.text })
    }

    @Test
    fun columnGoesToTheRoomierSideAndBoxesDoNotOverlap() {
        val right = panel(0.58, 0.197, 0.793, 0.854)
        assertTrue(PhoneThread.column(right).second < right.box.left)
        val middle = PhoneThread.column(panel(0.39, 0.2, 0.61, 0.85))
        assertTrue(middle.first > 0.61)
        assertTrue(middle.second <= 0.98)
        val messages = listOf(
            PhoneThread.Message("a", TextBox(0.6, 0.40, 0.7, 0.42), 0.022),
            PhoneThread.Message("b", TextBox(0.6, 0.43, 0.7, 0.45), 0.022),
        )
        val boxes = PhoneThread.boxes(messages, listOf(3, 1), listOf(0.02, 0.02), Pair(0.2, 0.5))
        assertTrue(boxes[1].top >= boxes[0].bottom)
    }

    @Test
    fun glossaryAndPhoneWords() {
        assertEquals("Vadesiz Hesap", PhoneThread.glossary("Checking Account"))
        assertEquals("Aile Birikimi", PhoneThread.glossary("Family Savings"))
        assertEquals("Sonraki hedefe $4.900", PhoneThread.glossary("$4,900 to next goal"))
        assertNull(PhoneThread.glossary("Are you high right now?"))
        assertEquals("Ryde Çağır ($82)", PhoneThread.glossary("Book Ryde ($82)"))
        assertEquals("Yolculuk Bilgileri", PhoneThread.glossary("Trip Details"))
        assertEquals("Seviye 3/4", PhoneThread.glossary("Level 3/4"))
        assertEquals("Kardiyo Antrenmanı", PhoneThread.glossary("Cardio Workout"))
        assertEquals("Kas - Yüksek", PhoneThread.glossary("Muscle - High"))
        assertEquals("Vücut Yağı - Düşük", PhoneThread.glossary("Body Fat - Low"))
        assertEquals("Kaslı", PhoneThread.glossary("Ripped"))
        assertEquals("Kas - Yüksek", PhoneThread.glossary("Muscle High"))
        assertTrue(PhoneThread.isPhoneUI("Body Fat Low"))
        for (text in listOf("Cardio Workout", "Calorie Balance", "You will maintain weight", "I Change Destination",
            "I Change Destinatior", "Book Ryde ($82)", "Choose Ryde", "Trip Details", "buckme", "Checking Account"))
            assertTrue(text, PhoneThread.isPhoneUI(text))
        for (text in listOf("You got this!", "Get to the car", "Change of plans, meet me downtown", "Rydell's house is over there",
            "I skipped my workout today"))
            assertFalse(text, PhoneThread.isPhoneUI(text))
        assertFalse(PhoneThread.isSentence("Book Ryde ($82)"))
        assertFalse(PhoneThread.isSentence("Righto Cash & Carry"))
        assertFalse(PhoneThread.isSentence("1.74 mi"))
        assertTrue(PhoneThread.isSentence("Thx amigo! U find anything else"))
        assertTrue(PhoneThread.isSentence("Are you high right now?"))
        assertTrue(PhoneThread.isSentence("Dropped off scuba to yuh boat man"))
        assertFalse(PhoneThread.worthShowing("buckme", "BuckMe mi?"))
        assertTrue(PhoneThread.worthShowing("Checking Account", "Vadesiz Hesap"))
        assertFalse(PhoneThread.isMessageList(Reading(listOf("Righto Cash & Carry", "Standard Ryde", "Choose Ryde", "Change Destination").map { TextLine(it) })))
        assertTrue(PhoneThread.isMessageList(Reading(listOf("Donnie", "You got my plane?! You be...", "Brian", "Remember, you get your h...").map { TextLine(it) })))
    }

    @Test
    fun phoneWordsWorkInTurkishLocale() {
        // Türkçe sistemde "I" küçülünce "ı" olur; karşılaştırmalar dilden bağımsız olmalı.
        val locale = Locale.getDefault()
        try {
            Locale.setDefault(Locale.forLanguageTag("tr-TR"))
            assertTrue(PhoneThread.isPhoneUI("TRIP DETAILS"))
            assertTrue(MapCard.isMapScreen(Reading(listOf(TextLine("RECENTER"), TextLine("SET DESTINATION")))))
        } finally {
            Locale.setDefault(locale)
        }
    }

    @Test
    fun whiteSubtitleIsNotDarkOnLightButPhoneMessageIs() {
        // Koyu zeminde beyaz yazı ve açık zeminde koyu yazı (bölge örnekleyicisiyle aynı ölçüler).
        val whiteText: ColorSampler = { x, _ -> if ((x * 200).toInt() % 4 == 0) Rgb(250, 250, 250) else Rgb(30, 30, 30) }
        val darkText: ColorSampler = { x, _ -> if ((x * 200).toInt() % 4 == 0) Rgb(30, 30, 30) else Rgb(235, 235, 238) }
        val box = TextBox(0.2, 0.4, 0.6, 0.5)
        assertFalse(PhoneThread.isDarkOnLight(box, whiteText))
        assertTrue(PhoneThread.isDarkOnLight(box, darkText))
    }

    @Test
    fun wrapBreaksAtWords() {
        val lines = PhoneThread.wrap("Bir iki üç dört beş altı yedi sekiz dokuz on", 0.1, 0.02)
        assertTrue(lines.size > 1)
        assertTrue(lines.all { it.length <= maxOf(12, (0.1 / (0.02 * 0.5 * 9 / 16)).toInt()) })
        assertEquals("Bir iki üç dört beş altı yedi sekiz dokuz on", lines.joinToString(" "))
        assertEquals(listOf(""), PhoneThread.wrap("", 0.1, 0.02))
    }
}
