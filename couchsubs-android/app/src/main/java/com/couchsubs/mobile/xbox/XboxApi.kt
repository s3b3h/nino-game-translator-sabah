// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı. Uç noktalar (/v6/servers/home, /v5/sessions/home/...) açık kaynak
// Greenlight ve xbox-xcloud-player'dan (MIT, UnknownSKL) öğrenildi; bkz. THIRD-PARTY-NOTICES.md.
package com.couchsubs.mobile.xbox

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/** Hesaba bağlı bir Xbox. [serverId] ev yayını oturumunu açarken kullanılır. */
data class XboxConsole(val serverId: String, val name: String, val type: String, val powerState: String) {
    /** "On" ya da "ConnectedStandby" (Anında Açılma) dışında konsol uzaktan uyandırılamaz. */
    val reachable get() = powerState == "On" || powerState == "ConnectedStandby"

    fun toJson(): String = JSONObject().put("serverId", serverId).put("name", name).put("type", type).put("powerState", powerState).toString()

    companion object {
        fun fromJson(text: String?): XboxConsole? = try {
            text?.let { JSONObject(it) }?.let { XboxConsole(it.getString("serverId"), it.optString("name"), it.optString("type"), it.optString("powerState")) }
        } catch (error: JSONException) {
            null
        }

        /** "XboxSeriesX" → "Xbox Series X" (ekranda). */
        fun typeName(type: String) = when (type) {
            "XboxSeriesX" -> "Xbox Series X"
            "XboxSeriesS" -> "Xbox Series S"
            "XboxOne" -> "Xbox One"
            "XboxOneS" -> "Xbox One S"
            "XboxOneX" -> "Xbox One X"
            else -> type.ifEmpty { "Xbox" }
        }
    }
}

/** Uzak tarafın ICE adayı (SDP satırı). */
data class IceCandidate(val candidate: String, val sdpMid: String?, val sdpMLineIndex: Int)

/** Xbox ev yayını sunucusu (bölge sunucusu + yayın jetonu). Bütün çağrılar bloklar. */
class XboxApi(private val host: StreamHost, private val http: XboxHttp = XboxHttp.system, private val locale: String = "en-US") {
    companion object {
        /** Konsolun altyazıyı göstereceği çözünürlük: okuma 1080p karede en iyisini verir. */
        const val WIDTH = 1920
        const val HEIGHT = 1080

        val deviceInfo: String = JSONObject()
            // Greenlight'ın gönderdiği cihaz bilgisi (Windows Xbox uygulaması gibi); sunucu bilinmeyen istemciyi reddedebilir.
            .put("appInfo", JSONObject().put("env", JSONObject().put("clientAppId", "Microsoft.GamingApp").put("clientAppType", "native")
                .put("clientAppVersion", "2203.1001.4.0").put("clientSdkVersion", "8.5.2").put("httpEnvironment", "prod").put("sdkInstallId", "")))
            .put("dev", JSONObject()
                .put("hw", JSONObject().put("make", "Microsoft").put("model", "Surface Pro").put("sdktype", "native"))
                .put("os", JSONObject().put("name", "Windows 11").put("ver", "22631.2715").put("platform", "desktop"))
                .put("displayInfo", JSONObject()
                    .put("dimensions", JSONObject().put("widthInPixels", WIDTH).put("heightInPixels", HEIGHT))
                    .put("pixelDensity", JSONObject().put("dpiX", 1).put("dpiY", 1))))
            .toString()

        fun parseConsoles(body: String): List<XboxConsole> {
            val results = try { JSONObject(body).optJSONArray("results") } catch (error: JSONException) { null } ?: return emptyList()
            return (0 until results.length()).mapNotNull { i ->
                val item = results.optJSONObject(i) ?: return@mapNotNull null
                val id = item.optString("serverId").ifEmpty { return@mapNotNull null }
                XboxConsole(id, item.optString("deviceName").ifEmpty { "Xbox" }, item.optString("consoleType"), item.optString("powerState"))
            }
        }

        /** /sdp ve /ice yanıtlarındaki "exchangeResponse" metin olarak gömülü JSON'dur. */
        fun exchange(body: String): String? = try {
            JSONObject(body).optString("exchangeResponse").ifEmpty { null }
        } catch (error: JSONException) {
            null
        }

        fun parseAnswerSdp(body: String): String? = exchange(body)?.let {
            try { JSONObject(it).optString("sdp").ifEmpty { null } } catch (error: JSONException) { null }
        }

        fun parseRemoteCandidates(body: String): List<IceCandidate> {
            val text = exchange(body) ?: return emptyList()
            val array = try { JSONArray(text) } catch (error: JSONException) { return emptyList() }
            return (0 until array.length()).mapNotNull { i ->
                val item = array.optJSONObject(i) ?: return@mapNotNull null
                val line = item.optString("candidate").ifEmpty { return@mapNotNull null }
                IceCandidate(line, item.optString("sdpMid").ifEmpty { null }, item.optString("sdpMLineIndex").toIntOrNull() ?: 0)
            }
        }

        fun offerBody(sdp: String): String = JSONObject()
            .put("messageType", "offer").put("sdp", sdp).put("requestId", "1")
            .put("configuration", JSONObject()
                .put("chatConfiguration", JSONObject().put("bytesPerSample", 2).put("expectedClipDurationMs", 20)
                    .put("format", JSONObject().put("codec", "opus").put("container", "webm")).put("numChannels", 1).put("sampleFrequencyHz", 24000))
                .put("chat", version(1, 1)).put("control", version(1, 3)).put("input", version(1, 8)).put("message", version(1, 1)))
            .toString()

        fun iceBody(candidates: List<IceCandidate>): String = JSONObject()
            .put("messageType", "iceCandidate")
            .put("candidate", JSONArray().apply {
                candidates.forEach { put(JSONObject().put("candidate", it.candidate).put("sdpMid", it.sdpMid ?: "0").put("sdpMLineIndex", it.sdpMLineIndex)) }
            })
            .toString()

        private fun version(min: Int, max: Int) = JSONObject().put("minVersion", min).put("maxVersion", max)
    }

    private val headers get() = mapOf(
        "Authorization" to "Bearer ${host.token}", "Content-Type" to "application/json", "Accept" to "application/json",
        "X-Gssv-Client" to "XboxComBrowser", "X-MS-Device-Info" to deviceInfo,
    )

    private fun call(method: String, path: String, body: String? = null, step: XboxStep = XboxStep.SESSION): HttpReply {
        val reply = http.send(method, host.baseUri + path, headers, body)
        if (!reply.ok) throw XboxException(step, reply.status, reply.body.take(160).ifEmpty { null })
        return reply
    }

    fun consoles(): List<XboxConsole> = parseConsoles(call("GET", "/v6/servers/home", step = XboxStep.CONSOLES).body)

    /** Oturumu açar; dönen yol ("v5/sessions/home/<kimlik>") sonraki çağrılarda kullanılır. */
    fun startHome(serverId: String): String {
        val body = JSONObject()
            .put("clientSessionId", "").put("titleId", "").put("systemUpdateGroup", "").put("serverId", serverId)
            .put("fallbackRegionNames", JSONArray())
            .put("settings", JSONObject().put("nanoVersion", "V3;WebrtcTransport.dll").put("enableOptionalDataCollection", false)
                .put("enableTextToSpeech", false).put("highContrast", 0).put("locale", locale).put("useIceConnection", false)
                .put("timezoneOffsetMinutes", java.util.TimeZone.getDefault().rawOffset / 60_000).put("sdkType", "web").put("osName", "windows"))
            .toString()
        val reply = call("POST", "/v5/sessions/home/play", body)
        return try {
            "/" + JSONObject(reply.body).getString("sessionPath").trimStart('/')
        } catch (error: JSONException) {
            throw XboxException(XboxStep.SESSION, reply.status, "no sessionPath")
        }
    }

    /** "Provisioning", "ReadyToConnect", "Provisioned", "Failed"… Hata ayrıntısı varsa ikinci değer. */
    fun state(session: String): Pair<String, String?> {
        val json = try { JSONObject(call("GET", "$session/state").body) } catch (error: JSONException) { JSONObject() }
        val details = json.optJSONObject("errorDetails")?.let { listOf(it.optString("code"), it.optString("message")).filter(String::isNotEmpty).joinToString(": ") }
        return json.optString("state") to details?.ifEmpty { null }
    }

    fun connect(session: String, transferToken: String) {
        call("POST", "$session/connect", JSONObject().put("userToken", transferToken).toString())
    }

    fun postOffer(session: String, sdp: String) { call("POST", "$session/sdp", offerBody(sdp)) }

    /** Yanıt hazır değilse (204) null; çağıran bekleyip yeniden sorar. */
    fun answer(session: String): String? = call("GET", "$session/sdp").takeIf { it.status != 204 }?.let { parseAnswerSdp(it.body) }

    fun postCandidates(session: String, candidates: List<IceCandidate>) { call("POST", "$session/ice", iceBody(candidates)) }

    fun remoteCandidates(session: String): List<IceCandidate>? =
        call("GET", "$session/ice").takeIf { it.status != 204 }?.let { parseRemoteCandidates(it.body) }

    fun keepalive(session: String) { call("POST", "$session/keepalive") }

    fun stop(session: String) {
        try { call("DELETE", session) } catch (error: Exception) { }
    }
}

/**
 * Konsolun ICE adayları arasında Teredo (2001::/32) IPv6 adresleri olabilir; Xbox'ın gerçek IPv4 adresi ve portu
 * bunun içinde gömülüdür (RFC 4380: istemci adresi ve portu ters çevrilmiş). Ev ağında IPv6 yoksa bağlantı bu IPv4
 * adaylarıyla kurulur.
 */
object Teredo {
    /** "2001:0:...:pppp:aaaa:bbbb" → ("a.b.c.d", port); Teredo değilse null. */
    fun decode(address: String): Pair<String, Int>? {
        val groups = expand(address) ?: return null
        if (groups[0] != 0x2001 || groups[1] != 0) return null
        val port = groups[5].inv() and 0xffff
        val high = groups[6].inv() and 0xffff
        val low = groups[7].inv() and 0xffff
        return "${high shr 8}.${high and 0xff}.${low shr 8}.${low and 0xff}" to port
    }

    /** Uzak adaylara Teredo'dan çıkarılan IPv4 adayları eklenir (9002, Xbox'ın sabit yayın portu, ve gömülü port). */
    fun withIpv4(candidates: List<IceCandidate>): List<IceCandidate> = candidates.flatMap { candidate ->
        if (candidate.candidate.contains("end-of-candidates")) return@flatMap emptyList()
        val parts = candidate.candidate.split(' ')
        val decoded = parts.getOrNull(4)?.let(::decode)
        if (decoded == null) listOf(candidate)
        else listOf(
            candidate.copy(candidate = "a=candidate:10 1 UDP 1 ${decoded.first} 9002 typ host "),
            candidate.copy(candidate = "a=candidate:11 1 UDP 1 ${decoded.first} ${decoded.second} typ host "),
            candidate,
        )
    }

    private fun expand(address: String): IntArray? {
        val text = address.substringBefore('%')
        if (!text.contains(':')) return null
        val halves = text.split("::")
        if (halves.size > 2) return null
        val head = halves[0].split(':').filter { it.isNotEmpty() }
        val tail = if (halves.size == 2) halves[1].split(':').filter { it.isNotEmpty() } else emptyList()
        val missing = 8 - head.size - tail.size
        if (missing < 0 || (halves.size == 1 && missing != 0)) return null
        val all = head + List(missing) { "0" } + tail
        return try { IntArray(8) { all[it].toInt(16).also { v -> if (v !in 0..0xffff) return null } } } catch (error: NumberFormatException) { null }
    }
}
