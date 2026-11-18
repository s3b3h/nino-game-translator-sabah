// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

/** Havuz öncelikli oyunlarda kullanıcının motoru hiç çağrılmaz (Windows: PoolFirstTranslatorTests). */
class PoolFirstTranslatorTest {
    private class Counting(private val answer: String, private val together: Boolean = false) : TextTranslator {
        val translated = mutableListOf<String>()
        val translatedAll = mutableListOf<List<String>>()
        override fun translate(text: String): String = synchronized(translated) { translated += text; answer }
        override fun translateAll(texts: List<String>): List<String> { translatedAll += texts; return texts.map { answer } }
        override val translatesTogether: Boolean get() = together
    }

    @Test fun poolFirstGameUsesPoolAndNeverTheEngine() {
        val engine = Counting("gemini", together = true)
        val free = Counting("ücretsiz")
        val asked = mutableListOf<String>()
        val translator = PoolFirstTranslator(engine, free, { true }, { line -> asked += line; "havuz" })
        assertEquals("havuz", translator.translate("Get in the car!"))
        assertFalse(translator.translatesTogether)
        assertEquals(listOf("havuz", "havuz"), translator.translateAll(listOf("a line", "another line")))
        assertTrue(engine.translated.isEmpty())
        assertTrue(engine.translatedAll.isEmpty())
        assertTrue(free.translated.isEmpty())
        assertEquals(3, asked.size)
        assertEquals("havuz", translator.lastSource)
    }

    @Test fun poolSilenceFallsBackToFreeTranslationOnly() {
        val engine = Counting("gemini")
        val free = Counting("ücretsiz")
        val translator = PoolFirstTranslator(engine, free, { true }, { null })
        assertEquals("ücretsiz", translator.translate("Get in the car!"))
        val blank = PoolFirstTranslator(engine, free, { true }, { "  " })
        assertEquals("ücretsiz", blank.translate("Get in the car!"))
        val failing = PoolFirstTranslator(engine, free, { true }, { throw IOException("kapalı") })
        assertEquals("ücretsiz", failing.translate("Get in the car!"))
        assertTrue(engine.translated.isEmpty())
        assertEquals(3, free.translated.size)
        assertEquals("ücretsiz", failing.lastSource)
    }

    @Test(expected = InterruptedException::class)
    fun cancelledLineIsNotTranslatedAtAll() {
        val free = Counting("ücretsiz")
        try {
            PoolFirstTranslator(Counting("gemini"), free, { true }, { throw InterruptedException() }).translate("Get in the car!")
        } finally {
            assertTrue(free.translated.isEmpty())
        }
    }

    @Test fun otherGamesUseTheEngineAsBefore() {
        val engine = Counting("gemini", together = true)
        val free = Counting("ücretsiz")
        var asked = 0
        val translator = PoolFirstTranslator(engine, free, { false }, { asked++; "havuz" })
        assertEquals("gemini", translator.translate("Hello there."))
        assertTrue(translator.translatesTogether)
        assertEquals(listOf("gemini"), translator.translateAll(listOf("Menu")))
        assertEquals(0, asked)
        assertEquals(1, engine.translated.size)
        assertEquals(1, engine.translatedAll.size)
        assertTrue(free.translated.isEmpty())
        assertEquals("motor", translator.lastSource)
    }

    @Test fun gameChangeIsFollowedLineByLine() {
        val engine = Counting("gemini")
        val free = Counting("ücretsiz")
        var poolFirst = false
        val translator = PoolFirstTranslator(engine, free, { poolFirst }, { "havuz" })
        assertEquals("gemini", translator.translate("one"))
        poolFirst = true
        assertEquals("havuz", translator.translate("two"))
        assertEquals(1, engine.translated.size)
    }
}
