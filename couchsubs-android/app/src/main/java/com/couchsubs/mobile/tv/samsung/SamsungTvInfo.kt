// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv.samsung

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Samsung TV'nin `http://TV:8001/api/v2/` yanıtı: adı, modeli ve geliştirici modu (açık mı, Host PC IP'si ne). Kurulum
 * ekranı buna bakarak TV'de neyin eksik olduğunu söyler; yanıt yoksa yine kurulum denenebilir.
 */
data class SamsungTvInfo(val name: String?, val model: String?, val developerMode: Boolean?, val developerIp: String?) {
    companion object {
        fun parse(json: String): SamsungTvInfo? = try {
            val device = JSONObject(json).optJSONObject("device") ?: throw IllegalArgumentException()
            fun text(name: String) = device.optString(name, "").replace("&quot;", "\"").trim().takeIf { it.isNotEmpty() }
            SamsungTvInfo(
                name = text("name"),
                model = text("modelName"),
                developerMode = text("developerMode")?.let { it == "1" || it.equals("true", ignoreCase = true) },
                developerIp = text("developerIP")?.takeIf { it != "0.0.0.0" },
            )
        } catch (error: Exception) {
            null
        }

        /** TV'ye sorar (bloklar, en çok iki kez [timeoutMs]); yanıt yoksa null. */
        fun fetch(host: String, timeoutMs: Int = 1500): SamsungTvInfo? = try {
            val connection = URL("http://$host:8001/api/v2/").openConnection() as HttpURLConnection
            connection.connectTimeout = timeoutMs
            connection.readTimeout = timeoutMs
            try {
                parse(connection.inputStream.use { String(it.readBytes(), Charsets.UTF_8) })
            } finally {
                connection.disconnect()
            }
        } catch (error: Exception) {
            null
        }
    }
}
