// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.nio.ByteBuffer

/**
 * Nino: oyun bilinmiyorsa (PS5 bildirmiyor, hazır paketten de tanınmadı) Remote Play karesinden tanınır: sunucu kareye
 * bakıp oyunun adını söyler ([TranslationPool.identify]). Çeviri başladıktan ~8 sn sonra, olmazsa dakikada bir, en çok 6
 * kez. Ekrandan tanıdıktan sonra arka planda yedek olarak yeniden bakar: 5 dk sonra bir kez doğrular, sonra 20 dakikada bir
 * (en çok 12 kez; oyun değiştirilmiş olabilir). PS5, kullanıcı ya da hazır paket oyunu söylüyorsa bakılmaz.
 * Mac: AppModel.identifyGameIfNeeded ile aynı zamanlama. Kare iş parçacığından çağrılır.
 */
class ScreenGameCheck(private val clock: () -> Long = System::currentTimeMillis) {
    companion object {
        const val FIRST_TRY_MS = 8_000L
        const val RETRY_MS = 60_000L
        const val MAX_TRIES = 6
        const val FIRST_CHECK_MS = 5 * 60_000L
        const val RECHECK_MS = 20 * 60_000L
        const val MAX_CHECKS = 12
        /** Gönderilen karenin genişliği (yaklaşık 50 KB JPEG). */
        const val IMAGE_WIDTH = 768

        /**
         * Karenin parlaklık düzlemini en çok [maxWidth] genişliğe küçültüp NV21 olarak döner (renk düzlemleri nötr: gri).
         * Kare arabelleği yalnız parlaklık düzlemini kesin taşır (Xbox yalnız Y verir); oyunu tanımak için gri yeter.
         * Boyutlar çifttir. Kare okunamazsa null.
         */
        fun grayNv21(buffer: ByteBuffer, width: Int, height: Int, rowStride: Int, maxWidth: Int = IMAGE_WIDTH): Gray? {
            if (width < 16 || height < 16 || rowStride < width) return null
            if ((height - 1).toLong() * rowStride + width > buffer.capacity()) return null
            val outWidth = minOf(width, maxWidth) and 1.inv()
            val outHeight = ((outWidth.toLong() * height / width).toInt()) and 1.inv()
            if (outWidth < 16 || outHeight < 16) return null
            val out = ByteArray(outWidth * outHeight * 3 / 2)
            for (y in 0 until outHeight) {
                val row = (y.toLong() * height / outHeight).toInt() * rowStride
                for (x in 0 until outWidth) out[y * outWidth + x] = buffer.get(row + (x.toLong() * width / outWidth).toInt())
            }
            java.util.Arrays.fill(out, outWidth * outHeight, out.size, 128.toByte())
            return Gray(out, outWidth, outHeight)
        }
    }

    class Gray(val nv21: ByteArray, val width: Int, val height: Int)

    private val lock = Any()
    private var tries = 0
    private var checks = 0
    private var last = clock()
    private var busy = false

    /** Yeni çeviri oturumu: sayaçlar sıfırlanır, ilk bakış [FIRST_TRY_MS] sonra. */
    fun reset() = synchronized(lock) {
        tries = 0
        checks = 0
        last = clock()
        busy = false
    }

    /**
     * Şimdi bakılmalı mı. [source]: oyunun şu an nereden bilindiği (bilinmiyorsa null). true dönerse bakış başlamış
     * sayılır; sonucu gelince [finish] çağrılmalıdır (o zamana kadar yeni bakış başlamaz).
     */
    fun due(source: GameSense.Source?): Boolean = synchronized(lock) {
        if (busy) return false
        val wait = when (source) {
            null -> if (tries >= MAX_TRIES) return false else if (tries == 0) FIRST_TRY_MS else RETRY_MS
            GameSense.Source.SCREEN -> if (checks >= MAX_CHECKS) return false else if (checks == 0) FIRST_CHECK_MS else RECHECK_MS
            else -> return false  // PS5, kullanıcı ya da hazır paket söylüyor; bakmaya gerek yok
        }
        val now = clock()
        if (now - last <= wait) return false
        last = now
        if (source == null) tries++ else checks++
        busy = true
        true
    }

    /**
     * Ucuz ön denetim (her karede, kilitli işlerden önce): bakış sürmüyor ve son bakıştan en kısa bekleme süresi
     * ([FIRST_TRY_MS]) geçti. false ise [due] de false döner.
     */
    fun mayBeDue(): Boolean = synchronized(lock) { !busy && clock() - last > FIRST_TRY_MS }

    /** Bakış bitti (sonuç ne olursa olsun). */
    fun finish() = synchronized(lock) { busy = false }

    /** Bu oturumda yapılan tanıma denemesi sayısı (kayıt için). */
    val attempts: Int get() = synchronized(lock) { tries }
}
