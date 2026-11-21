// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Nino: GTA 6 ekrandaki kendine özgü yazılarından tanınır (Mac/iPhone: GameMarkersTests). */
class GameMarkersTest {
    private fun line(text: String, top: Double = 0.1) = TextLine(text, TextBox(0.4, top, 0.6, top + 0.03))

    @Test
    fun mapScreenIsGTA6() = assertEquals("GTA 6", GameMarkers.game(NinoFixtures.lines("gta6-harita-buckme")))

    @Test
    fun pauseMenuTabsAndPhoneAreGTA6() {
        assertEquals("GTA 6", GameMarkers.game(Reading(listOf(line("JASON & LUCIA"), line("MAP"), line("BRIEF"), line("PROGRESS")))))
        assertEquals("GTA 6", GameMarkers.game(Reading(listOf(line("MAP"), line("BRIEF"), line("PROGRESS")))))
        assertEquals("GTA 6", GameMarkers.game(Reading(listOf(line("Reminders"), line("WhatUp", 0.8)))))
    }

    @Test
    fun otherScreensAreNotRecognised() {
        assertNull(GameMarkers.game(Reading(listOf(line("Options"), line("Map"), line("Progress"), line("Quit Game")))))
        assertNull(GameMarkers.game(Reading(listOf(line("Jason, wait for me!", 0.85)))))
        assertNull(GameMarkers.game(NinoFixtures.lines("gta6-altyazi-beyaz")))
        assertNull(GameMarkers.game(NinoFixtures.lines("gta6-telefon-brian-parlama")))
    }

    @Test
    fun catalogShowsTheShortNameAndStillMatchesTheLongOne() {
        assertEquals(GameName.key("GTA 6"), GameName.key("Grand Theft Auto VI"))
        assertTrue(GameCatalog.suggestions("grand theft", emptyList(), null).contains("GTA 6"))
        assertEquals("GTA 6", GameCatalog.suggestions("", emptyList(), null).first())
    }
}
