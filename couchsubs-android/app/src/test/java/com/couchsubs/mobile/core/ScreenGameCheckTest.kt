// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer

/** Oyunu ekrandan tanıma zamanlaması (Mac: AppModel.identifyGameIfNeeded ile aynı kurallar). */
class ScreenGameCheckTest {
    private var now = 1_000_000L
    private val check = ScreenGameCheck { now }

    /** Saati [ms] ilerletir ve bakılmalı mı diye sorar; bakış başlarsa hemen bitirir. */
    private fun after(ms: Long, source: GameSense.Source?): Boolean {
        now += ms
        return check.due(source).also { if (it) check.finish() }
    }

    @Test fun unknownGameIsTriedAfterEightSecondsThenEveryMinuteSixTimes() {
        check.reset()
        assertFalse(check.mayBeDue())
        assertFalse(after(8_000, null))
        assertTrue(after(1, null))
        assertFalse(after(59_000, null))
        assertTrue(after(1_001, null))
        repeat(4) { assertTrue(after(60_001, null)) }
        // Altı deneme bitti.
        assertFalse(after(10 * 60_000, null))
        assertEquals(6, check.attempts)
    }

    @Test fun gameSeenOnScreenIsRecheckedAfterFiveMinutesThenEveryTwenty() {
        check.reset()
        assertTrue(after(8_001, null))
        // Ekrandan tanındı: 5 dk sonra bir kez, sonra 20 dakikada bir, en çok 12 kez.
        assertFalse(after(5 * 60_000, GameSense.Source.SCREEN))
        assertTrue(after(1, GameSense.Source.SCREEN))
        assertFalse(after(20 * 60_000, GameSense.Source.SCREEN))
        assertTrue(after(1, GameSense.Source.SCREEN))
        repeat(10) { assertTrue(after(20 * 60_000 + 1, GameSense.Source.SCREEN)) }
        assertFalse(after(20 * 60_000 + 1, GameSense.Source.SCREEN))
    }

    @Test fun consoleUserOrPackNeverAsk() {
        check.reset()
        for (source in listOf(GameSense.Source.CONSOLE, GameSense.Source.USER, GameSense.Source.PACK)) assertFalse(after(3_600_000, source))
    }

    @Test fun onlyOneLookAtATime() {
        check.reset()
        now += 8_001
        assertTrue(check.due(null))
        now += 120_000
        assertFalse(check.mayBeDue())
        assertFalse(check.due(null))
        check.finish()
        assertTrue(check.due(null))
    }

    @Test fun resetStartsANewSession() {
        check.reset()
        repeat(6) { after(60_001, null) }
        assertFalse(after(60_001, null))
        check.reset()
        assertFalse(after(1_000, null))
        assertTrue(after(7_001, null))
    }

    @Test fun seenIsTheLowestPrioritySource() {
        val sense = GameSense()
        sense.setSeen("Mafia: The Old Country")
        assertEquals(GameSense.Source.SCREEN, sense.source)
        assertEquals("Mafia: The Old Country", sense.current?.name)
        // Ekrandan tanınan oyun sorulacak kartı engellemez ama paket, kullanıcı ve PS5 onun önüne geçer.
        sense.choose("Elden Ring")
        assertEquals(GameSense.Source.USER, sense.source)
        sense.setConsole(RunningGame.named("Ghost of Yōtei"))
        assertEquals(GameSense.Source.CONSOLE, sense.source)
        sense.setConsole(null)
        sense.choose(null)
        assertEquals(GameSense.Source.SCREEN, sense.source)
        sense.setSeen(null)
        assertNull(sense.source)
    }

    @Test fun grayFrameIsDownscaledToEvenSize() {
        val width = 1920
        val height = 1080
        val stride = 2048
        val buffer = ByteBuffer.allocate(stride * height)
        for (y in 0 until height) for (x in 0 until width) buffer.put(y * stride + x, (x * 255 / width).toByte())
        val gray = ScreenGameCheck.grayNv21(buffer, width, height, stride)!!
        assertEquals(768, gray.width)
        assertEquals(432, gray.height)
        assertEquals(768 * 432 * 3 / 2, gray.nv21.size)
        // Soldan sağa açılan parlaklık korunur; renk düzlemleri nötr.
        assertTrue((gray.nv21[0].toInt() and 0xff) < (gray.nv21[767].toInt() and 0xff))
        assertEquals(128.toByte(), gray.nv21[gray.nv21.size - 1])
        // Küçük kare büyütülmez; bozuk boyut okunmaz.
        assertEquals(640, ScreenGameCheck.grayNv21(ByteBuffer.allocate(640 * 360), 640, 360, 640)!!.width)
        assertNull(ScreenGameCheck.grayNv21(ByteBuffer.allocate(100), 640, 360, 640))
    }
}
