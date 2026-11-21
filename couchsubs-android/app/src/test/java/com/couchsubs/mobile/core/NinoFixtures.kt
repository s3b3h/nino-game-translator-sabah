// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.ceil
import kotlin.math.floor

/**
 * Nino: gerçek GTA 6 kareleri (test/resources/nino içindeki .jpg dosyaları; Mac'in deneme verisi) ve yazı tanıma
 * satırları (.lines.txt: "sol üst sağ alt[TAB]metin", kareye göre 0–1; Windows: GameFrames, GameLines).
 */
object NinoFixtures {
    /**
     * Kare, gerçek karelerdeki gibi en çok 960×540 renkli kopya olarak (büyükse nokta seçilerek küçültülür).
     * [fullSize]: küçültülmeden (Windows sınamalarının gördüğü kare).
     */
    fun frame(name: String, fullSize: Boolean = false): RgbImage {
        val stream = NinoFixtures::class.java.classLoader!!.getResourceAsStream("nino/$name") ?: error("yok: $name")
        // JPEG, JVM'nin javax.imageio'suyla çözülür; Android derleme sınıf yolunda yok, yansımayla çağrılır.
        val image = stream.use {
            Class.forName("javax.imageio.ImageIO").getMethod("read", java.io.InputStream::class.java).invoke(null, it)
        } ?: error("okunamadı: $name")
        val type = image.javaClass
        val width = type.getMethod("getWidth").invoke(image) as Int
        val height = type.getMethod("getHeight").invoke(image) as Int
        val argb = IntArray(width * height)
        type.getMethod("getRGB", Int::class.java, Int::class.java, Int::class.java, Int::class.java, IntArray::class.java,
            Int::class.java, Int::class.java).invoke(image, 0, 0, width, height, argb, 0, width)
        val rgb = ByteArray(width * height * 3)
        for (i in argb.indices) {
            val p = argb[i]
            rgb[i * 3] = (p shr 16).toByte()
            rgb[i * 3 + 1] = (p shr 8).toByte()
            rgb[i * 3 + 2] = p.toByte()
        }
        if (fullSize || (width <= RgbImage.MAX_WIDTH && height <= RgbImage.MAX_HEIGHT)) return RgbImage(width, height, rgb)
        // Gerçek karelerdeki gibi (VideoFrame.rgb): her "scale" noktadan ortadaki alınır. İki kez alan ortalaması
        // (1920→960→240, her adımda aşağı yuvarlayarak) koyu Rydeme ekranını eşiğin altına itiyordu.
        val scale = maxOf(1, maxOf((width + RgbImage.MAX_WIDTH - 1) / RgbImage.MAX_WIDTH, (height + RgbImage.MAX_HEIGHT - 1) / RgbImage.MAX_HEIGHT))
        val w = width / scale
        val h = height / scale
        val out = ByteArray(w * h * 3)
        for (ty in 0 until h) {
            val sy = minOf(height - 1, ty * scale + scale / 2)
            for (tx in 0 until w) {
                val sx = minOf(width - 1, tx * scale + scale / 2)
                System.arraycopy(rgb, (sy * width + sx) * 3, out, (ty * w + tx) * 3, 3)
            }
        }
        return RgbImage(w, h, out)
    }

    fun lines(name: String): Reading {
        val stream = NinoFixtures::class.java.classLoader!!.getResourceAsStream("nino/$name.lines.txt") ?: error("yok: $name")
        val text = stream.use { it.readBytes().toString(Charsets.UTF_8) }
        return Reading(text.split('\n').map { it.trimEnd('\r') }.filter { it.contains('\t') }.map { line ->
            val (numbers, words) = line.split('\t', limit = 2)
            val n = numbers.split(' ').map { it.toDouble() }
            TextLine(words, TextBox(n[0], n[1], n[2], n[3]))
        })
    }

    /** Karenin bölgesi (kenarlar dışa yuvarlanır; Windows: RegionCropper.Crop). */
    fun crop(image: RgbImage, region: CropRegion): RgbImage {
        val left = floor(image.width * region.left).toInt()
        val top = floor(image.height * region.top).toInt()
        val right = minOf(image.width, ceil(image.width * region.right).toInt())
        val bottom = minOf(image.height, ceil(image.height * region.bottom).toInt())
        val w = right - left
        val h = bottom - top
        val out = ByteArray(w * h * 3)
        for (y in 0 until h) System.arraycopy(image.rgb, ((top + y) * image.width + left) * 3, out, y * w * 3, w * 3)
        return RgbImage(w, h, out)
    }
}
