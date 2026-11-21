// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Nino: karenin küçültülmüş renkli kopyası (piksel başına 3 bayt: R, G, B; satırlar boşluksuz). Oyundaki telefonun
 * (GTA 6) ekranını bulmak, mesaj balonlarının ve harita kartının rengini örneklemek için (Mac/iPhone: CGImage,
 * Windows: Frame). Yazı tanıma bunu kullanmaz; o tam çözünürlüklü parlaklıkla okur.
 */
class RgbImage(val width: Int, val height: Int, val rgb: ByteArray) {
    init {
        require(width > 0 && height > 0 && rgb.size >= width * height * 3)
    }

    fun r(x: Int, y: Int): Int = rgb[(y * width + x) * 3].toInt() and 0xff
    fun g(x: Int, y: Int): Int = rgb[(y * width + x) * 3 + 1].toInt() and 0xff
    fun b(x: Int, y: Int): Int = rgb[(y * width + x) * 3 + 2].toInt() and 0xff

    /**
     * [targetWidth]×[targetHeight] boyutunda kopya (alan ortalaması), satır satır R, G, B. Görüntü bu boyuttan küçükse
     * noktalar orantılı tekrarlanarak büyütülür; boyut geçersizse null (Windows: PhonePanel.Downscaled ile aynı).
     */
    fun downscaled(targetWidth: Int, targetHeight: Int): ByteArray? {
        if (targetWidth <= 0 || targetHeight <= 0) return null
        val out = ByteArray(targetWidth * targetHeight * 3)
        for (ty in 0 until targetHeight) {
            val y0 = (ty.toLong() * height / targetHeight).toInt()
            val y1 = maxOf(y0 + 1, ((ty + 1).toLong() * height / targetHeight).toInt())
            for (tx in 0 until targetWidth) {
                val x0 = (tx.toLong() * width / targetWidth).toInt()
                val x1 = maxOf(x0 + 1, ((tx + 1).toLong() * width / targetWidth).toInt())
                var r = 0L; var g = 0L; var b = 0L; var n = 0L
                for (y in y0 until y1) for (x in x0 until x1) {
                    val i = (y * width + x) * 3
                    r += rgb[i].toInt() and 0xff
                    g += rgb[i + 1].toInt() and 0xff
                    b += rgb[i + 2].toInt() and 0xff
                    n++
                }
                val o = (ty * targetWidth + tx) * 3
                out[o] = (r / n).toInt().toByte()
                out[o + 1] = (g / n).toInt().toByte()
                out[o + 2] = (b / n).toInt().toByte()
            }
        }
        return out
    }

    companion object {
        /** Telefon ve harita için en çok bu boyutta renkli kopya yeter (en ayrıntılı örnekleyici 960×540). */
        const val MAX_WIDTH = 960
        const val MAX_HEIGHT = 540

        // Kareden renkli kopya: VideoFrame.rgb (remoteplay/FrameSource.kt).
    }
}
