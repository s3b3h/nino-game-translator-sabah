// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.remoteplay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer

/**
 * Nino: yerel çözücünün Y düzleminin arkasına koyduğu yarım çözünürlüklü renk (NV12: U, V) doğru okunur. U ile V yer
 * değiştirse mavi (giden) mesaj balonu kırmızı/turuncu görünür ve sağa değil sola konurdu.
 */
class FrameColorTest {
    /** Sol yarısı saf mavi, sağ yarısı saf kırmızı kare (sınırlı aralık BT.601), yerel çözücünün verdiği düzende. */
    private fun frame(width: Int, height: Int, chroma: Boolean = true): VideoFrame {
        // Saf mavi: Y 41, U 240, V 110. Saf kırmızı: Y 81, U 90, V 240.
        val buffer = ByteBuffer.allocateDirect(width * height + (width / 2) * (height / 2) * 2)
        for (y in 0 until height) for (x in 0 until width) buffer.put(y * width + x, (if (x < width / 2) 41 else 81).toByte())
        val cw = width / 2
        for (y in 0 until height / 2) for (x in 0 until cw) {
            val i = width * height + y * cw * 2 + x * 2
            val blue = x < cw / 2
            buffer.put(i, (if (blue) 240 else 90).toByte())
            buffer.put(i + 1, (if (blue) 110 else 240).toByte())
        }
        return VideoFrame(buffer, width, height, width, 21, nativeChroma(buffer, width, height, chroma))
    }

    @Test
    fun blueAndRedComeOutRight() {
        val image = frame(64, 36).rgb() ?: error("renk yok")
        val (w, h) = image.width to image.height
        assertEquals(64, w)
        // Sol: mavi baskın; sağ: kırmızı baskın.
        val left = Triple(image.r(4, h / 2), image.g(4, h / 2), image.b(4, h / 2))
        val right = Triple(image.r(w - 4, h / 2), image.g(w - 4, h / 2), image.b(w - 4, h / 2))
        assertTrue("$left", left.third > 230 && left.first < 30 && left.second < 30)
        assertTrue("$right", right.first > 230 && right.second < 30 && right.third < 30)
    }

    @Test
    fun bigFramesAreShrunkProportionally() {
        assertEquals(960 to 540, frame(1920, 1080).rgb()!!.let { it.width to it.height })
        // Xbox (1280×720) da 960×540'a iner (eskiden tam sayı oranıyla 640×360 oluyordu).
        assertEquals(960 to 540, frame(1280, 720).rgb()!!.let { it.width to it.height })
    }

    @Test
    fun missingOrShortChromaIsNull() {
        assertNull(frame(64, 36, chroma = false).chroma)
        val short = ByteBuffer.allocateDirect(64 * 36)
        assertNull("arabellek rengi taşımıyor", nativeChroma(short, 64, 36, true))
        assertNotNull(frame(64, 36).chroma)
    }
}
