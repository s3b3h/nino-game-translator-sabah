// SPDX-License-Identifier: AGPL-3.0-only
// Nino: ana ekrandaki TV'nin sağ üst köşesinde görünen "Toplam indirme" sayısı (Mac: DownloadCounter.swift).
package com.couchsubs.mobile.core

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.NumberFormat
import java.util.Locale

/**
 * Toplam indirme sayısı (GitHub'daki uygulama dosyalarının indirme toplamı). Sunucunun `GET /v1/config` cevabındaki
 * `downloads` alanından okunur; sunucu onu yarım saatte bir GitHub'dan yeniler. İstek kullanıcıya ait hiçbir bilgi
 * taşımaz. Çeviri sürerken ayrı istek yapılmaz: [TranslationPool] aynı cevabı zaten okur ve buraya verir ([accept]).
 * Çeviri kapalıyken (fiş takılı değil; havuz o zaman çalışmaz) ana ekran açıkken en çok [INTERVAL_MS]de bir sorulur
 * ([refresh]). İnternet yoksa ya da sunucu sayıyı veremiyorsa son bilinen sayı gösterilmeye devam eder (kalıcı
 * saklanır); hiç alınamadıysa sayaç görünmez. Sayı olduğu gibi gösterilir, üstüne ekleme yapılmaz.
 */
class DownloadCounter(
    private val store: Store,
    private val endpoint: URL?,
    private val fetch: (URL) -> String?,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    /** Son bilinen sayının kalıcı yeri (uygulamada SharedPreferences); hiç alınmadıysa 0. */
    interface Store {
        var downloadTotal: Int
    }

    companion object {
        /** Sunucuya en çok bu aralıkla sorulur. */
        const val INTERVAL_MS = 600_000L

        /** `/v1/config` cevabındaki toplam indirme; alan yoksa ya da sayı geçersizse null. */
        fun parse(body: String): Int? {
            val value = try { JSONObject(body).opt("downloads") } catch (error: Exception) { null }
            // Yalnız tamsayı: "3439" yazısı ya da 12.5 sayılmaz.
            val number = (value as? Int) ?: (value as? Long)?.takeIf { it <= Int.MAX_VALUE }?.toInt()
            return number?.takeIf { it > 0 }
        }

        /** Sayı, binlik ayırıcısı yerel biçimde ("3.439" / "3,439"). */
        fun format(total: Int, locale: Locale): String = NumberFormat.getIntegerInstance(locale).format(total.toLong())

        /** Düz GET; 200 dışında ya da ağ hatasında null. [app]: sürüm (havuz istekleriyle aynı tanıtım). */
        fun get(url: URL, app: String): String? = try {
            val connection = url.openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 10_000
                connection.readTimeout = 10_000
                connection.useCaches = false
                // Cloudflare tanımadığı Java istemcilerini bazen engelliyor; NinoPool ile aynı tanıtım.
                connection.setRequestProperty("User-Agent", "nino-pool/1 (android; $app)")
                if (connection.responseCode == 200) connection.inputStream.bufferedReader().use { it.readText() } else null
            } finally {
                connection.disconnect()
            }
        } catch (error: Exception) {
            null
        }
    }

    private val state = MutableStateFlow(store.downloadTotal.takeIf { it > 0 })

    /** Gösterilecek sayı; hiç alınamadıysa null (gösterge görünmez). */
    val total: StateFlow<Int?> = state

    private val lock = Any()
    private var lastAsked = Long.MIN_VALUE

    /** Sayıyı yeniler (en çok [INTERVAL_MS]de bir; bloklar). Alınamazsa eldeki sayı kalır. */
    fun refresh() {
        val base = endpoint ?: return
        val now = clock()
        synchronized(lock) {
            if (lastAsked != Long.MIN_VALUE && now - lastAsked < INTERVAL_MS) return
            lastAsked = now
        }
        val body = try { fetch(URL(base, "/v1/config")) } catch (error: Exception) { null } ?: return
        parse(body)?.let(::publish)
    }

    /** Başka bir yerin (çeviri havuzu) az önce aldığı `/v1/config` cevabı: aynı şey yeniden sorulmaz. */
    fun accept(configReply: String) {
        synchronized(lock) { lastAsked = clock() }
        parse(configReply)?.let(::publish)
    }

    private fun publish(value: Int) {
        state.value = value
        store.downloadTotal = value
    }
}
