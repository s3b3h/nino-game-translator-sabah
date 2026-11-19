// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile

import com.couchsubs.mobile.core.TranslationPool
import com.couchsubs.mobile.service.LiveStatus
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ayarlar'daki "GTA 6" kartının koşulu (Mac: ninoPoolActive ile aynı kural). */
class NinoPoolActiveTest {
    @Test fun shownForTurkishWhileNoGameIsRecognised() {
        assertTrue(LiveStatus().ninoPoolActive("tr"))
        assertTrue(LiveStatus().ninoPoolActive("tr-TR"))
        assertTrue(LiveStatus(running = true).ninoPoolActive("tr"))
    }

    @Test fun hiddenForLanguagesThePoolDoesNotTranslate() {
        assertFalse(LiveStatus().ninoPoolActive("ar"))
        assertFalse(LiveStatus(running = true, game = "Grand Theft Auto VI", poolFirstGame = true).ninoPoolActive("en"))
        // Sunucu bütün dilleri açarsa (langs: "*") o dillerde de geçerlidir.
        assertTrue(LiveStatus().ninoPoolActive("ar", TranslationPool.PoolFirstConfig(langs = listOf("*"))))
    }

    @Test fun followsTheRecognisedGameWhileTranslating() {
        assertTrue(LiveStatus(running = true, game = "Grand Theft Auto VI", poolFirstGame = true).ninoPoolActive("tr"))
        assertFalse(LiveStatus(running = true, game = "Red Dead Redemption 2").ninoPoolActive("tr"))
    }

    @Test fun lastSessionsGameDoesNotHideItAfterStop() {
        // Oyun adı çeviri durunca silinmez; durmuşken kart yine görünür.
        assertTrue(LiveStatus(running = false, game = "Red Dead Redemption 2").ninoPoolActive("tr"))
    }
}
