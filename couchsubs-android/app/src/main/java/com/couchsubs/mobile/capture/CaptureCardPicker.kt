// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı. Android türü kullanmaz; birim testleriyle sınanır.
package com.couchsubs.mobile.capture

/** Telefonun gördüğü bir kameranın özeti (Camera2'den doldurulur). */
data class CameraInfo(
    val id: String,
    /** Camera2 LENS_FACING değeri: 0 ön, 1 arka, 2 harici (USB/UVC). */
    val facing: Int,
    /** YUV_420_888 akışında verebildiği boyutlar. */
    val yuvSizes: List<FrameSize>,
)

data class FrameSize(val width: Int, val height: Int) {
    val area: Long get() = width.toLong() * height
    val isWide: Boolean get() = width * 9 == height * 16
    override fun toString() = "${width}x$height"
}

/**
 * Yakalama kartını ve okuma boyunu seçer. HDMI yakalama kartları USB-C OTG ile takılınca Android 14+'ta (her telefonda
 * değil) Camera2'de "harici" kamera olarak görünür. Telefonun kendi ön ve arka kameraları asla seçilmez: oyun yerine
 * odanın görüntüsü okunmasın.
 */
object CaptureCardPicker {
    const val LENS_FACING_EXTERNAL = 2

    /** Okuma hattının PS5 yolundaki boyu. */
    val PREFERRED = FrameSize(1920, 1080)

    /** Harici kameralar arasından YUV akışı verebilen ilki; [preferred] takılıysa o. */
    fun pick(cameras: List<CameraInfo>, preferred: String? = null): CameraInfo? {
        val usable = cameras.filter { it.facing == LENS_FACING_EXTERNAL && it.yuvSizes.isNotEmpty() }
        return usable.firstOrNull { it.id == preferred } ?: usable.firstOrNull()
    }

    /**
     * 1920x1080 varsa o; yoksa 16:9 boyutlar arasından 1080p'ye alanca en yakını (eşitse büyüğü); 16:9 yoksa herhangi
     * bir boyuttan en yakını. Liste boşsa null.
     */
    fun size(sizes: List<FrameSize>): FrameSize? {
        if (sizes.isEmpty()) return null
        if (PREFERRED in sizes) return PREFERRED
        val pool = sizes.filter { it.isWide }.ifEmpty { sizes }
        return pool.minWithOrNull(compareBy<FrameSize> { kotlin.math.abs(it.area - PREFERRED.area) }.thenByDescending { it.area })
    }
}

/**
 * Karenin neredeyse tamamen siyah olup olmadığı (PS5'te HDCP açıkken kart simsiyah görüntü verir). Y (parlaklık)
 * düzleminden seyrek örnek alınır; en parlak örnek bile çok karanlıksa kare siyah sayılır.
 */
object BlackFrame {
    const val THRESHOLD = 24

    /** [luma] (x, y) noktasının parlaklığını (0–255) verir; kare doğrudan kamera arabelleğinden örneklenir. */
    fun isBlack(width: Int, height: Int, step: Int = 32, luma: (x: Int, y: Int) -> Int): Boolean {
        var y = step / 2
        while (y < height) {
            var x = step / 2
            while (x < width) {
                if (luma(x, y) > THRESHOLD) return false
                x += step
            }
            y += step
        }
        return true
    }
}
