// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Yol tarifi satırları ("Turn Right 405 ft") altyazı değildir: çevrilmez, gösterilmez (iPhone/Mac ile aynı kural). */
class NavigationHintTest {
    @Test fun turnByTurnLinesAreNotSubtitles() {
        listOf("Turn Right 405 ft 432 ft", "Keep Left O ft 2 ft", "U-Turn Left 5 ft 24 ft", "Turn Left 366 ft—",
            "-turn Right 67 ft 82 ft", "Turn Right i 100 ft 103 ft", "Keep Right 3.9 km")
            .forEach { assertTrue(it, Reading.isNavigationHint(it)) }
        listOf("Turn right at the lights, okay?", "Keep left and you'll be fine, 20 ft or so",
            "Keep it down!", "I said turn left, 50 ft back there you idiot.")
            .forEach { assertFalse(it, Reading.isNavigationHint(it)) }
    }

    /** Nino (@GreatRival, 20 Kasım 2026): mesafesiz tek komut da tariftir; eskiden "Turn Right" altyazı sayılıyordu (bilerek değişti). */
    @Test fun bareDirectionsAreHints() {
        listOf("Turn left", "Turn Right", "Keep left", "Make a U-turn", "U-Turn Left", "Keep Right.")
            .forEach { assertTrue(it, Reading.isNavigationHint(it)) }
        listOf("Turn left at the lights, okay?", "Keep going, we're almost there.", "Turn it down!")
            .forEach { assertFalse(it, Reading.isNavigationHint(it)) }
    }
}
