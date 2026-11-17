// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.remoteplay

import android.content.Context
import java.nio.ByteBuffer

/**
 * Bir karenin parlaklık (Y) düzlemi, görünür alana kırpılmış: [width] x [height] piksel, satırlar [rowStride] bayt
 * arayla (piksel aralığı 1). [buffer] yalnız çağrı süresince geçerlidir; sonraki kare aynı arabelleğe yazılır, yani
 * saklanacaksa kopyalanmalıdır. [colorFormat] çözücünün kare biçimi (tanı için; MediaCodecInfo renk biçimi).
 */
class VideoFrame(val buffer: ByteBuffer, val width: Int, val height: Int, val rowStride: Int, val colorFormat: Int = 0)

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
