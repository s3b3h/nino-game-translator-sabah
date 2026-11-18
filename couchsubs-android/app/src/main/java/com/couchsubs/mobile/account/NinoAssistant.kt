// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.account

import com.couchsubs.mobile.translation.Http
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URL
import java.util.Base64

/**
 * Nino: "Nino'ya Sor" kurulum yardımcısı. Sohbet Nino havuz sunucusuna (POST /v1/assistant, nino-pool/src/assistant.js)
 * gönderilir. Kurulum kimliği, fotoğraf küçültme ve ağ işi Sorun Bildir'inkilerle aynıdır (ProblemReport,
 * ReportAttachments). Bu dosya Android'e bağlı değildir (JVM testi: NinoAssistantTest).
 */
object NinoAssistant {
    const val MAX_MESSAGES = 24
    const val MAX_TEXT = 2000
    const val MAX_IMAGES = 3

    /** Yalnız son bu kadar fotoğraflı kullanıcı mesajı fotoğraflarıyla gider; eskiler "[screenshot]" yazısı olur. */
    const val IMAGE_MESSAGES = 2

    /**
     * Sohbette fotoğraf başına üst sınır. Gövde en çok 6 MB'tır: 2 mesaj × 3 fotoğraf × 600 KB ≈ 3,6 MB, base64 ile
     * ≈ 4,8 MB. Sorun Bildir'in 900 KB'ı burada sığmazdı.
     */
    const val MAX_IMAGE_BYTES = 600 * 1024
    const val MAX_BODY_BYTES = 6 * 1024 * 1024
    const val SCREENSHOT = "[screenshot]"

    /** Model yanıtı resimlerle birlikte sürebilir. */
    const val TIMEOUT_MS = 90_000

    /** Sunucuya giden bir sohbet mesajı. Fotoğraflar yalnız kullanıcı mesajlarında (JPEG baytları). */
    class Turn(val user: Boolean, val text: String, val images: List<ByteArray> = emptyList())

    sealed class Result {
        /** [report]: Nino ekibe bildirim gönderdiyse bildirimin kimliği. */
        data class Reply(val text: String, val report: String?) : Result()
        /** Sunucuda henüz model yok (503 assistant_disabled). */
        data object Disabled : Result()
        /** Bu kurulumun günlük sınırı doldu (429 rate_limited). */
        data object RateLimited : Result()
        /** Sunucunun günlük bütçesi doldu (429 busy). */
        data object Busy : Result()
        /** 413 ya da gövde 6 MB'ı aşıyor. */
        data object TooLarge : Result()
        /** 400: istek kabul edilmedi. */
        data object Invalid : Result()
        /** Ağ hatası, 502 (model_failed, refused) ve diğerleri: yeniden denenebilir. */
        data object Failed : Result()
    }

    /**
     * Sunucuya giden JSON gövdesi. Son [MAX_MESSAGES] mesaj gider; metin [MAX_TEXT]'te kırpılır; fotoğraf yalnız son
     * [keepImages] fotoğraflı kullanıcı mesajında (her birinde en çok [MAX_IMAGES]) gider, öncekilerde "[screenshot]"
     * yazısı kalır. Metni ve fotoğrafı olmayan mesaj atlanır.
     */
    fun body(install: String, app: String, language: String, turns: List<Turn>, keepImages: Int = IMAGE_MESSAGES): String {
        val recent = turns.filter { it.text.isNotBlank() || (it.user && it.images.isNotEmpty()) }.takeLast(MAX_MESSAGES)
        val withImages = recent.indices.filter { recent[it].user && recent[it].images.isNotEmpty() }.takeLast(keepImages).toSet()
        val messages = JSONArray()
        recent.forEachIndexed { index, turn ->
            val text = turn.text.trim()
            val message = JSONObject().put("role", if (turn.user) "user" else "assistant")
            if (index in withImages) {
                message.put("text", text.take(MAX_TEXT))
                val images = JSONArray()
                turn.images.take(MAX_IMAGES).forEach { bytes ->
                    images.put(JSONObject().put("mime", "image/jpeg").put("data", Base64.getEncoder().encodeToString(bytes)))
                }
                message.put("images", images)
            } else if (turn.user && turn.images.isNotEmpty()) {
                message.put("text", (if (text.isEmpty()) SCREENSHOT else "$text\n$SCREENSHOT").take(MAX_TEXT))
            } else {
                message.put("text", text.take(MAX_TEXT))
            }
            messages.put(message)
        }
        return JSONObject()
            .put("v", 1)
            .put("install", install)
            .put("app", app)
            .put("platform", "android")
            .put("language", language)
            .put("messages", messages)
            .toString()
    }

    /**
     * [body] gibi, ama gövde [maxBytes]'ı aşarsa önce eski fotoğraflı mesaj, sonra hepsi "[screenshot]" yazısına
     * indirilir. Yine de sığmazsa null.
     */
    fun fittedBody(install: String, app: String, language: String, turns: List<Turn>, maxBytes: Int = MAX_BODY_BYTES): String? {
        for (keep in IMAGE_MESSAGES downTo 0) {
            val body = body(install, app, language, turns, keep)
            if (body.toByteArray(Charsets.UTF_8).size <= maxBytes) return body
        }
        return null
    }

    /** Sunucu yanıtı → sonuç. */
    fun result(code: Int, response: String): Result {
        val json = try { JSONObject(response) } catch (error: Exception) { null }
        val error = json?.optString("error").orEmpty()
        return when {
            code in 200..299 -> {
                val reply = json?.optString("reply")?.trim().orEmpty()
                if (json?.optBoolean("ok") != true || reply.isEmpty()) Result.Failed
                else Result.Reply(reply, json.optString("report").takeIf { !json.isNull("report") && it.isNotBlank() })
            }
            code == 503 && error == "assistant_disabled" -> Result.Disabled
            code == 429 && error == "busy" -> Result.Busy
            code == 429 -> Result.RateLimited
            code == 413 -> Result.TooLarge
            code == 400 -> Result.Invalid
            else -> Result.Failed
        }
    }

    /** Gönderir (ağ işi: arka planda çağrılmalı). Gövde 6 MB'ı aşıyorsa hiç gönderilmez. */
    fun send(endpoint: URL, body: String, http: Http = Http.Default): Result {
        if (body.toByteArray(Charsets.UTF_8).size > MAX_BODY_BYTES) return Result.TooLarge
        return try {
            val (code, response) = http.send("POST", URL(endpoint, "/v1/assistant").toString(),
                mapOf("Content-Type" to "application/json"), body, TIMEOUT_MS)
            result(code, response)
        } catch (error: IOException) {
            Result.Failed
        } catch (error: RuntimeException) {
            Result.Failed
        }
    }

    private val url = Regex("https?://[^\\s<>\"']+")

    /** Nino'nun yanıtındaki http(s) bağlantıları (sondaki noktalama bağlantıya katılmaz). */
    fun links(text: String): List<IntRange> = url.findAll(text).mapNotNull { match ->
        var end = match.range.last
        while (end > match.range.first && text[end] in ".,;:!?)]}…'\"") end--
        (match.range.first..end).takeIf { end - match.range.first >= 8 }
    }.toList()
}
