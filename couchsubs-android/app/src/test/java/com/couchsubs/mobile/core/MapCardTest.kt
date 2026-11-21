// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Nino: harita kartı (Windows: MapCardTests, Mac: MapCardParagraphTests, MapCardIconJunkTests). */
class MapCardTest {
    @Test
    fun wholeCardIsRead() {
        val reading = NinoFixtures.lines("gta6-harita-buckme")
        assertTrue(MapCard.isMapScreen(reading))
        val card = MapCard.find(reading)
        assertNotNull(card)
        assertEquals("DEPOSIT CASH INTO BUCKME", card!!.title)
        assertEquals(2, card.sentences.size)
        assertTrue(card.sentences[0], card.sentences[0].endsWith("nearby ATMs"))
        assertTrue(card.sentences[0], card.sentences[0].startsWith("Use the index"))
        assertTrue(card.sentences.last(), card.sentences.last().contains("checking account at an ATM"))
        assertTrue(card.box.bottom > 0.58)
    }

    @Test
    fun iconAndDistanceDoNotBreakTheCard() {
        val reading = NinoFixtures.lines("gta6-harita-balik")
        assertTrue(MapCard.isMapScreen(reading))
        val card = MapCard.find(reading)!!
        assertEquals("CATCH A BIGGER FISH", card.title)
        assertEquals(listOf("Cal challenged you to catch a stoplight parrotfish larger than 0.9 kg."), card.sentences)
    }

    @Test
    fun phoneIsNotAMapScreen() = assertFalse(MapCard.isMapScreen(NinoFixtures.lines("gta6-telefon-brian-parlama")))

    @Test
    fun mapKeysAreCleanedOfIcons() {
        assertTrue(MapCard.isMapKey("⊕ RECENTER"))
        assertTrue(MapCard.isMapKey("ii Close Menu"))
        assertFalse(MapCard.isMapKey("Get to the car"))
        assertEquals("Settings", MapCard.cleanMenuText("i Settings"))
    }

    @Test
    fun cardFrameFollowsTheDarkCard() {
        // Aydınlık harita, üstünde koyu kart (x 0.40–0.70, y 0.30–0.60); yazıların kutusu kartın içinde.
        val w = 960
        val h = 540
        val rgb = ByteArray(w * h * 3)
        for (y in 0 until h) for (x in 0 until w) {
            val fx = x.toDouble() / w
            val fy = y.toDouble() / h
            val dark = fx >= 0.40 && fx < 0.70 && fy >= 0.30 && fy < 0.60
            val o = (y * w + x) * 3
            val v = (if (dark) 30 else 200).toByte()
            rgb[o] = v; rgb[o + 1] = v; rgb[o + 2] = v
        }
        val frame = MapCard.frame(TextBox(0.42, 0.33, 0.62, 0.55), RgbImage(w, h, rgb))!!
        assertEquals(0.40, frame.left, 0.01)
        assertEquals(0.70, frame.right, 0.01)
        assertEquals(0.30, frame.top, 0.01)
        assertEquals(0.60, frame.bottom, 0.01)
        assertNull(MapCard.frame(TextBox(0.42, 0.33, 0.42, 0.55), RgbImage(w, h, rgb)))
    }
}
