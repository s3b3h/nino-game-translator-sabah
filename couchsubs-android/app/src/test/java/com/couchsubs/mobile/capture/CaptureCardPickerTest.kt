// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureCardPickerTest {
    private val hd = FrameSize(1920, 1080)
    private fun camera(id: String, facing: Int, vararg sizes: FrameSize) = CameraInfo(id, facing, sizes.toList())

    @Test fun phoneCamerasAreNeverPicked() {
        val cameras = listOf(camera("0", 1, hd), camera("1", 0, hd))
        assertNull(CaptureCardPicker.pick(cameras))
    }

    @Test fun externalCameraIsPicked() {
        val cameras = listOf(camera("0", 1, hd), camera("1", 0, hd), camera("5", CaptureCardPicker.LENS_FACING_EXTERNAL, hd))
        assertEquals("5", CaptureCardPicker.pick(cameras)?.id)
    }

    @Test fun externalWithoutYuvIsSkipped() {
        val cameras = listOf(camera("4", 2), camera("6", 2, hd))
        assertEquals("6", CaptureCardPicker.pick(cameras)?.id)
    }

    @Test fun preferredCardWins() {
        val cameras = listOf(camera("4", 2, hd), camera("6", 2, hd))
        assertEquals("6", CaptureCardPicker.pick(cameras, preferred = "6")?.id)
        assertEquals("4", CaptureCardPicker.pick(cameras, preferred = "9")?.id)
    }

    @Test fun noCamerasGivesNull() {
        assertNull(CaptureCardPicker.pick(emptyList()))
        assertNull(CaptureCardPicker.size(emptyList()))
    }

    @Test fun fullHdIsPreferred() {
        val sizes = listOf(FrameSize(3840, 2160), FrameSize(640, 480), hd, FrameSize(1280, 720))
        assertEquals(hd, CaptureCardPicker.size(sizes))
    }

    @Test fun nearestWideSizeWithoutFullHd() {
        // 4K ve 720p arasında 1080p'ye alanca yakın olan 720p; 4:3 boyutlar 16:9 varken seçilmez.
        val sizes = listOf(FrameSize(3840, 2160), FrameSize(1280, 720), FrameSize(1600, 1200), FrameSize(640, 480))
        assertEquals(FrameSize(1280, 720), CaptureCardPicker.size(sizes))
        assertEquals(FrameSize(2560, 1440), CaptureCardPicker.size(listOf(FrameSize(2560, 1440), FrameSize(640, 360))))
    }

    @Test fun anySizeWhenNoWideOne() {
        val sizes = listOf(FrameSize(640, 480), FrameSize(1600, 1200), FrameSize(1920, 1200))
        assertEquals(FrameSize(1600, 1200), CaptureCardPicker.size(sizes))
    }

    @Test fun blackFrameDetection() {
        assertTrue(BlackFrame.isBlack(1920, 1080) { _, _ -> 12 })
        assertFalse(BlackFrame.isBlack(1920, 1080) { x, y -> if (x > 900 && y > 900) 200 else 0 })
    }
}
