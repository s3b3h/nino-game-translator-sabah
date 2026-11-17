// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ocr

import com.couchsubs.mobile.core.CropRegion
import com.couchsubs.mobile.core.Reading
import com.couchsubs.mobile.core.TextBox
import com.couchsubs.mobile.core.TextLine
import com.couchsubs.mobile.remoteplay.VideoFrame
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.TimeUnit

/** Karenin altyazı bölgesinden kopyalanmış parlaklık (Y) düzlemi: yazı tanımaya bu gider, kare hemen bırakılır. */
class RegionPixels(val nv21: ByteArray, val width: Int, val height: Int, val signature: Long)

/**
 * Altyazı bölgesini Google ML Kit (cihaz üstü, Latin modeli uygulamayla gelir) ile okur. Renk gerekmez: yalnız parlaklık
 * düzlemi kopyalanır, renk düzlemleri nötr (128) bırakılır; bu hem hızlıdır hem beyaz/sarı altyazıyı aynı okur.
 */
class SubtitleReader : AutoCloseable {
    private val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    companion object {
        /** Karenin (Y düzlemi) bölgesini NV21 gri görüntüye kopyalar (en ve boy çift sayıya yuvarlanır). */
        fun copyRegion(frame: VideoFrame, region: CropRegion): RegionPixels? {
            val frameWidth = frame.width
            val frameHeight = frame.height
            if (frameWidth <= 0 || frameHeight <= 0 || frame.rowStride < frameWidth) return null
            val left = (region.left * frameWidth).toInt().coerceIn(0, frameWidth) and 1.inv()
            val top = (region.top * frameHeight).toInt().coerceIn(0, frameHeight) and 1.inv()
            val width = ((region.right - region.left) * frameWidth).toInt().coerceAtMost(frameWidth - left) and 1.inv()
            val height = ((region.bottom - region.top) * frameHeight).toInt().coerceAtMost(frameHeight - top) and 1.inv()
            if (width < 16 || height < 16) return null
            // Yerel taraf arabelleği her karede yeniden yazar: konum ve sınır başkasının işini bozmasın diye kopya.
            val buffer = frame.buffer.duplicate()
            val rowStride = frame.rowStride
            if ((top + height - 1).toLong() * rowStride + left + width > buffer.capacity()) return null
            val out = ByteArray(width * height * 3 / 2)
            var signature = 1125899906842597L
            for (y in 0 until height) {
                val base = y * width
                buffer.position((top + y) * rowStride + left)
                buffer.get(out, base, width)
                // Kare değişmediyse yeniden okunmasın diye kaba bir imza (her 8. piksel).
                if (y % 8 == 0) for (x in 0 until width step 8) signature = 31 * signature + (out[base + x].toInt() and 0xf0)
            }
            java.util.Arrays.fill(out, width * height, out.size, 128.toByte())
            return RegionPixels(out, width, height, signature)
        }
    }

    /** Bölgeyi okur (bloklar; okuma iş parçacığında çağrılır). Satır kutuları bölgeye oranladır. */
    fun read(pixels: RegionPixels): Reading {
        val input = InputImage.fromByteArray(pixels.nv21, pixels.width, pixels.height, 0, InputImage.IMAGE_FORMAT_NV21)
        val text = Tasks.await(recognizer.process(input), 5, TimeUnit.SECONDS)
        val lines = mutableListOf<TextLine>()
        for (block in text.textBlocks) {
            for (line in block.lines) {
                val box = line.boundingBox?.let {
                    TextBox(
                        it.left.toDouble() / pixels.width, it.top.toDouble() / pixels.height,
                        it.right.toDouble() / pixels.width, it.bottom.toDouble() / pixels.height,
                    )
                }
                lines.add(TextLine(line.text, box))
            }
        }
        // Yukarıdan aşağı (ML Kit blok sırası her zaman öyle değil).
        return Reading(lines.sortedBy { it.box?.top ?: 0.0 })
    }

    override fun close() = recognizer.close()
}
