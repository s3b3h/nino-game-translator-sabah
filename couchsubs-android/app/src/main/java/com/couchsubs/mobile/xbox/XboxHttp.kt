// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı (Xbox ev yayını; bkz. docs/nino/xbox-arastirma.md).
package com.couchsubs.mobile.xbox

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** Bir HTTP yanıtı: durum kodu ve gövde (boş olabilir). */
class HttpReply(val status: Int, val body: String) {
    val ok get() = status in 200..299
}

/** Xbox ve Microsoft sunucularıyla konuşan HTTP katmanı; testlerde sahtesi kullanılır. */
fun interface XboxHttp {
    /** Ağ hatasında [IOException] atar; 4xx/5xx yanıtlar hata değildir, [HttpReply.status] ile döner. */
    fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpReply

    companion object {
        /** Android'in kendi HttpURLConnection'ı (ek kitaplık yok). */
        val system = XboxHttp { method, url, headers, body ->
            val connection = URL(url).openConnection() as HttpURLConnection
            try {
                connection.requestMethod = method
                connection.connectTimeout = 15_000
                connection.readTimeout = 20_000
                connection.useCaches = false
                headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
                if (body != null) {
                    connection.doOutput = true
                    connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                } else if (method == "POST") {
                    connection.doOutput = true
                    connection.setFixedLengthStreamingMode(0)
                }
                val status = connection.responseCode
                val stream = if (status >= 400) connection.errorStream else connection.inputStream
                HttpReply(status, stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: "")
            } finally {
                connection.disconnect()
            }
        }
    }
}

/** Xbox tarafında bir adım başarısız oldu; [step] kullanıcıya hangi aşamada kaldığını anlatmak için. */
class XboxException(val step: XboxStep, val status: Int? = null, val detail: String? = null) :
    IOException("Xbox $step failed${status?.let { " (HTTP $it)" } ?: ""}${detail?.let { ": $it" } ?: ""}")

enum class XboxStep {
    /** Microsoft giriş kodu alınamadı ya da süresi doldu. */
    SIGN_IN,
    /** Microsoft girişi geçersiz (çıkış yapılmış, şifre değişmiş); yeniden giriş gerekir. */
    SIGNED_OUT,
    /** Xbox Live jetonu alınamadı (hesapta Xbox profili yok olabilir). */
    XBOX_LIVE,
    /** Ev yayını (xHome) izni alınamadı. */
    STREAMING,
    /** Konsol listesi alınamadı. */
    CONSOLES,
    /** Konsolla yayın oturumu kurulamadı. */
    SESSION,
}
