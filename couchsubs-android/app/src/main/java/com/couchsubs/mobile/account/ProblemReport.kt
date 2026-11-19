// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.account

import com.couchsubs.mobile.core.DeviceInfo
import com.couchsubs.mobile.core.NinoPool
import com.couchsubs.mobile.translation.Http
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.URL
import java.util.Base64
import java.util.UUID

/**
 * Nino: "Sorun Bildir". Kullanıcının açıklaması, isteğe bağlı iletişim bilgisi, uygulama günlüğü ve en çok 3 fotoğraf
 * Nino havuz sunucusuna (POST /v1/reports, nino-pool/src/reports.js) gönderilir. Bu dosya Android'e bağlı değildir
 * (JVM testi: ProblemReportTest); fotoğraf çözme ve günlük okuma ReportAttachments.kt'de.
 */
object ProblemReport {
    const val MAX_TEXT = 4000
    const val MAX_CONTACT = 200
    const val MAX_LOG = 60_000
    const val MAX_IMAGES = 3
    const val MAX_SIDE = 1600
    const val QUALITY = 70

    /**
     * Fotoğraf başına üst sınır. Sunucu tek fotoğrafta 1,5 MB'a izin verir ama gövde en çok 4 MB'tır ve base64 boyu
     * 4/3 büyütür: 3 × 900 KB ≈ 3,6 MB (base64) + günlük ve metin, 4 MB'ın altında kalır.
     */
    const val MAX_IMAGE_BYTES = 900 * 1024
    const val MAX_BODY_BYTES = 4 * 1024 * 1024

    enum class Outcome { SENT, INVALID, TOO_LARGE, RATE_LIMITED, FAILED }

    /**
     * Sunucuya giden JSON gövdesi; alanlar sunucunun sınırlarına göre kırpılır, boş iletişim ve günlük gönderilmez.
     * [device]: cihaz bilgileri ([DeviceInfo.summary]: uygulama, cihaz modeli, sistem, TV, konsol; kişisel bilgi içermez);
     * boşsa alan hiç gönderilmez.
     */
    fun body(install: String, app: String, language: String, text: String, contact: String?, log: String?, images: List<ByteArray>,
             device: String? = null): String {
        val json = JSONObject()
            .put("v", 1)
            .put("install", install)
            .put("app", app)
            .put("platform", "android")
            .put("language", language)
            .put("text", text.trim().take(MAX_TEXT))
        contact?.trim()?.take(MAX_CONTACT)?.takeIf { it.isNotEmpty() }?.let { json.put("contact", it) }
        log?.takeIf { it.isNotBlank() }?.let { json.put("log", it.takeLast(MAX_LOG)) }
        device?.trim()?.take(DeviceInfo.MAX_LENGTH)?.takeIf { it.isNotEmpty() }?.let { json.put("device", it) }
        val list = JSONArray()
        images.take(MAX_IMAGES).forEach { bytes ->
            list.put(JSONObject().put("mime", "image/jpeg").put("data", Base64.getEncoder().encodeToString(bytes)))
        }
        json.put("images", list)
        return json.toString()
    }

    /** Sunucu yanıtı → sonuç (200 tamam, 400 geçersiz, 413 çok büyük, 429 günlük sınır). */
    fun outcome(code: Int): Outcome = when (code) {
        in 200..299 -> Outcome.SENT
        400 -> Outcome.INVALID
        413 -> Outcome.TOO_LARGE
        429 -> Outcome.RATE_LIMITED
        else -> Outcome.FAILED
    }

    /** Gönderir (ağ işi: arka planda çağrılmalı). Gövde 4 MB'ı aşıyorsa hiç gönderilmez. */
    fun send(endpoint: URL, body: String, http: Http = Http.Default): Outcome {
        if (body.toByteArray(Charsets.UTF_8).size > MAX_BODY_BYTES) return Outcome.TOO_LARGE
        return try {
            val (code, _) = http.send("POST", URL(endpoint, "/v1/reports").toString(),
                mapOf("Content-Type" to "application/json"), body, 30_000)
            outcome(code)
        } catch (error: IOException) {
            Outcome.FAILED
        } catch (error: RuntimeException) {
            Outcome.FAILED
        }
    }

    /** Havuz adresi: havuz klasöründeki endpoint.txt (deneme için), yoksa canlı sunucu. */
    fun endpoint(filesDir: File): URL? = NinoPool.configuredEndpoint(File(filesDir, "pool"))

    /**
     * Kurulum kimliği: Nino havuzunun kimliği (pool/state.json); havuz hiç çalışmadıysa bir kez üretilip [store]
     * edilen rastgele kimlik. Havuz nesnesi burada açılmaz: kuyruk dosyalarını düzenler, çeviri servisininkiyle çakışır.
     */
    fun installId(filesDir: File, stored: () -> String?, store: (String) -> Unit): String {
        val pool = try {
            File(filesDir, "pool/state.json").takeIf { it.exists() }?.let { JSONObject(it.readText()).optString("install") }
        } catch (error: Exception) {
            null
        }
        if (!pool.isNullOrBlank() && pool.length in 8..64) return pool
        stored()?.takeIf { it.length in 8..64 }?.let { return it }
        return UUID.randomUUID().toString().also(store)
    }

    // Günlükte anahtar ya da jeton gibi görünenler gizlenir (sıra önemli: önce adlandırılmış alanlar).
    private const val HIDDEN = "[gizlendi]"
    private val scrubbers = listOf(
        Regex("(?i)(bearer\\s+)[A-Za-z0-9._~+/=-]+") to "$1$HIDDEN",
        Regex("(?i)\\b([A-Za-z_-]*(?:key|token|secret|password|passcode|auth|authorization|cookie))(\"?\\s*[=:]\\s*\"?)[^\\s\"',;&]+") to "$1$2$HIDDEN",
        Regex("AIza[0-9A-Za-z_-]{20,}") to HIDDEN,
        Regex("\\bsk-[A-Za-z0-9_-]{16,}") to HIDDEN,
        Regex("\\b[0-9a-fA-F]{32,}\\b") to HIDDEN,
        Regex("[A-Za-z0-9+/_-]{40,}={0,2}") to HIDDEN,
    )

    /** Anahtar ve jeton gibi görünen her şeyi gizler, son [MAX_LOG] karakteri bırakır (sunucu baştan kırpar). */
    fun scrubLog(log: String): String =
        scrubbers.fold(log) { text, (pattern, replacement) -> pattern.replace(text, replacement) }.takeLast(MAX_LOG)

    /** BitmapFactory için 2'nin kuvveti örnekleme: çözülen görüntü uzun kenarda [maxSide]'ın altına inmeden küçülür. */
    fun sampleSize(width: Int, height: Int, maxSide: Int = MAX_SIDE): Int {
        var sample = 1
        val longest = maxOf(width, height)
        while (longest / (sample * 2) >= maxSide) sample *= 2
        return sample
    }

    /** Uzun kenarı en çok [maxSide] olacak boy (oran korunur, büyütülmez). */
    fun scaledSize(width: Int, height: Int, maxSide: Int = MAX_SIDE): Pair<Int, Int> {
        val longest = maxOf(width, height)
        if (longest <= maxSide || longest <= 0) return width to height
        val ratio = maxSide.toDouble() / longest
        return maxOf(1, Math.round(width * ratio).toInt()) to maxOf(1, Math.round(height * ratio).toInt())
    }

    /**
     * JPEG'i [maxBytes] altına sığdırır: önce kalite (70 → 55 → 40), sonra boy (×0,75) düşürülür. [encode] (genişlik,
     * yükseklik, kalite) için JPEG baytlarını verir. Sığmazsa null.
     */
    fun fitJpeg(width: Int, height: Int, maxBytes: Int = MAX_IMAGE_BYTES, maxSide: Int = MAX_SIDE,
                encode: (Int, Int, Int) -> ByteArray?): ByteArray? {
        var side = minOf(maxSide, maxOf(width, height))
        while (side >= 320) {
            val (w, h) = scaledSize(width, height, side)
            for (quality in intArrayOf(QUALITY, 55, 40)) {
                val bytes = encode(w, h, quality) ?: return null
                if (bytes.size <= maxBytes) return bytes
            }
            side = (side * 0.75).toInt()
        }
        return null
    }
}
