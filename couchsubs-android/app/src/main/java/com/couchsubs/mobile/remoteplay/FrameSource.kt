// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.remoteplay

import android.content.Context
import java.nio.ByteBuffer

/**
 * Bir karenin parlaklık (Y) düzlemi, görünür alana kırpılmış: [width] x [height] piksel, satırlar [rowStride] bayt
 * arayla (piksel aralığı 1). [buffer] yalnız çağrı süresince geçerlidir; sonraki kare aynı arabelleğe yazılır, yani
 * saklanacaksa kopyalanmalıdır. [colorFormat] çözücünün kare biçimi (tanı için; MediaCodecInfo renk biçimi).
 */
class VideoFrame(
    val buffer: ByteBuffer, val width: Int, val height: Int, val rowStride: Int, val colorFormat: Int = 0,
    /** Nino: yarım çözünürlüklü renk düzlemleri (oyundaki telefonu ve balon renklerini bulmak için); yoksa null. */
    val chroma: Chroma? = null,
)

/**
 * Nino: karenin renk (U, V) düzlemleri, yarım çözünürlükte: (x, y) noktasının U değeri [u] arabelleğinde
 * `y * rowStride + x * pixelStride` konumundadır ([v] de öyle). [width] × [height] renk noktası. Kareyle aynı süre geçerlidir.
 */
class Chroma(val u: ByteBuffer, val v: ByteBuffer, val width: Int, val height: Int, val rowStride: Int, val pixelStride: Int) {
    fun at(x: Int, y: Int): Pair<Int, Int> {
        val cx = x.coerceIn(0, width - 1)
        val cy = y.coerceIn(0, height - 1)
        val i = cy * rowStride + cx * pixelStride
        return (u.get(i).toInt() and 0xff) to (v.get(i).toInt() and 0xff)
    }
}

/** Okuma hattına kare veren kaynak: PS5 Remote Play oturumu ([StreamSession]) ya da Nino'da yakalama kartı (CaptureCardSource). */
interface FrameSource {
    fun start()

    /** Bloklamaz: kaynak arka planda kapatılır. */
    fun dispose()

    /** Gelen kare sayısı (tanı: görüntü geliyor mu). */
    val framesReceived: Long
}

/** PS5 oturumunun yerine kare kaynağı kuran üretici (geliştirme yapısının demo klibi ya da yakalama kartı). */
fun interface FrameSourceFactory {
    fun create(context: Context, onFrame: (VideoFrame) -> Unit, onState: (SessionState) -> Unit): FrameSource
}

/**
 * Çeviri hizmeti kare kaynağını buradan seçer. Sürüm yapısında [replacement] hep null'dır ve PS5 oturumu açılır;
 * debug yapısı (app/src/debug) Play ekran görüntüleri için PS5 yerine kayıtlı bir klip oynatan kaynak kurabilir.
 */
object FrameSources {
    @Volatile var replacement: FrameSourceFactory? = null
}

/**
 * Nino: karenin en çok [maxWidth]×[maxHeight] boyutunda renkli kopyası (oyundaki telefonu ve balon renklerini bulmak
 * için). Renk düzlemi yoksa gri olur. Kare iş parçacığında, kare geçerliyken çağrılır.
 */
fun VideoFrame.rgb(
    maxWidth: Int = com.couchsubs.mobile.core.RgbImage.MAX_WIDTH, maxHeight: Int = com.couchsubs.mobile.core.RgbImage.MAX_HEIGHT,
): com.couchsubs.mobile.core.RgbImage? {
    if (width <= 0 || height <= 0 || rowStride < width) return null
    if ((height - 1).toLong() * rowStride + width > buffer.capacity()) return null
    // Oranlı küçültme (1280×720 → 960×540): her hedef noktaya kaynakta en yakın nokta.
    val ratio = minOf(1.0, minOf(maxWidth.toDouble() / width, maxHeight.toDouble() / height))
    val w = maxOf(1, (width * ratio).toInt())
    val h = maxOf(1, (height * ratio).toInt())
    val out = ByteArray(w * h * 3)
    val luma = buffer
    val color = chroma
    for (ty in 0 until h) {
        val sy = minOf(height - 1, ((ty + 0.5) * height / h).toInt())
        val row = sy * rowStride
        for (tx in 0 until w) {
            val sx = minOf(width - 1, ((tx + 0.5) * width / w).toInt())
            // Sınırlı aralık (16–235), BT.601: PS5 akışı böyledir.
            val y = ((luma.get(row + sx).toInt() and 0xff) - 16) * 1.164
            var du = 0.0
            var dv = 0.0
            if (color != null) {
                // Nesne üretmeden (karede yarım milyon nokta): Chroma.at ile aynı konum.
                val i = (sy / 2).coerceAtMost(color.height - 1) * color.rowStride + (sx / 2).coerceAtMost(color.width - 1) * color.pixelStride
                du = (color.u.get(i).toInt() and 0xff) - 128.0
                dv = (color.v.get(i).toInt() and 0xff) - 128.0
            }
            val o = (ty * w + tx) * 3
            out[o] = (y + 1.596 * dv).toInt().coerceIn(0, 255).toByte()
            out[o + 1] = (y - 0.392 * du - 0.813 * dv).toInt().coerceIn(0, 255).toByte()
            out[o + 2] = (y + 2.017 * du).toInt().coerceIn(0, 255).toByte()
        }
    }
    return com.couchsubs.mobile.core.RgbImage(w, h, out)
}
