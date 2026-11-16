// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.xbox

import com.couchsubs.mobile.core.CropRegion
import com.couchsubs.mobile.ocr.SubtitleReader
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.nio.ByteBuffer

/** Sahte sunucu: (yöntem, adresin parçası) → yanıt sırası; gelen istekler kaydedilir. */
private class FakeHttp(private val routes: List<Pair<String, MutableList<HttpReply>>>) : XboxHttp {
    val calls = mutableListOf<Triple<String, String, String?>>()
    val headers = mutableListOf<Map<String, String>>()

    override fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpReply {
        calls.add(Triple(method, url, body))
        this.headers.add(headers)
        val key = "$method $url"
        val replies = routes.firstOrNull { key.contains(it.first) }?.second ?: throw AssertionError("beklenmeyen istek: $key")
        return if (replies.size > 1) replies.removeAt(0) else replies.first()
    }

    fun bodies(part: String) = calls.filter { "${it.first} ${it.second}".contains(part) }.mapNotNull { it.third }
}

private fun ok(json: String) = HttpReply(200, json)

class XboxProtocolTest {
    @Test
    fun deviceCodeAndPolling() {
        val http = FakeHttp(listOf(
            "devicecode" to mutableListOf(ok("""{"user_code":"ABCD1234","device_code":"dev","verification_uri":"https://www.microsoft.com/link","expires_in":900,"interval":5}""")),
            "/token" to mutableListOf(
                HttpReply(400, """{"error":"authorization_pending"}"""),
                HttpReply(400, """{"error":"slow_down"}"""),
                ok("""{"access_token":"acc","refresh_token":"ref","expires_in":3600}"""),
            ),
        ))
        val auth = XboxAuth(http) { 1000L }
        val code = auth.requestDeviceCode()
        assertEquals("ABCD1234", code.userCode)
        assertEquals(5, code.intervalSeconds)
        assertTrue(http.calls[0].third!!.contains("client_id=${XboxAuth.CLIENT_ID}"))
        assertTrue(http.calls[0].third!!.contains("scope=xboxlive.signin+openid+profile+offline_access"))
        assertEquals(DeviceCodePoll.Pending, auth.pollDeviceCode(code))
        assertEquals(DeviceCodePoll.SlowDown, auth.pollDeviceCode(code))
        val done = auth.pollDeviceCode(code) as DeviceCodePoll.Done
        assertEquals("ref", done.tokens.refreshToken)
        assertEquals(1000L + 3_600_000L, done.tokens.expiresAt)
        assertTrue(http.calls.last().third!!.contains("device_code=dev"))
    }

    @Test
    fun expiredCodeFails() {
        val http = FakeHttp(listOf("/token" to mutableListOf(HttpReply(400, """{"error":"expired_token"}"""))))
        val result = XboxAuth(http).pollDeviceCode(DeviceCode("A", "d", "u", 1, 1))
        assertEquals(DeviceCodePoll.Failed("expired_token"), result)
    }

    @Test
    fun streamHostChain() {
        val http = FakeHttp(listOf(
            "user.auth.xboxlive.com" to mutableListOf(ok("""{"Token":"xbl-user"}""")),
            "xsts.auth.xboxlive.com" to mutableListOf(ok("""{"Token":"gssv-xsts"}""")),
            "xhome.gssv-play-prod.xboxlive.com/v2/login/user" to mutableListOf(ok("""{"gsToken":"gs","durationInSeconds":14400,
                "offeringSettings":{"regions":[{"name":"WestEurope","baseUri":"https://weu.core.gssv-play-prodxhome.xboxlive.com","isDefault":false},
                {"name":"UKSouth","baseUri":"https://uks.core.gssv-play-prodxhome.xboxlive.com/","isDefault":true}]}}""")),
        ))
        val host = XboxAuth(http) { 0L }.streamHost("msa-access")
        assertEquals("https://uks.core.gssv-play-prodxhome.xboxlive.com", host.baseUri)
        assertEquals("gs", host.token)
        assertEquals(14_400_000L, host.expiresAt)
        val user = JSONObject(http.bodies("user/authenticate").single())
        assertEquals("d=msa-access", user.getJSONObject("Properties").getString("RpsTicket"))
        val xsts = JSONObject(http.bodies("xsts/authorize").single())
        assertEquals(XboxAuth.GSSV_RELYING_PARTY, xsts.getString("RelyingParty"))
        assertEquals("xbl-user", xsts.getJSONObject("Properties").getJSONArray("UserTokens").getString(0))
        val login = JSONObject(http.bodies("login/user").single())
        assertEquals("xhome", login.getString("offeringId"))
        assertEquals("gssv-xsts", login.getString("token"))
    }

    @Test
    fun noXboxProfileIsReported() {
        val http = FakeHttp(listOf(
            "user.auth.xboxlive.com" to mutableListOf(ok("""{"Token":"u"}""")),
            "xsts.auth.xboxlive.com" to mutableListOf(HttpReply(401, """{"XErr":2148916233}""")),
        ))
        try {
            XboxAuth(http).streamHost("a")
            fail()
        } catch (error: XboxException) {
            assertEquals(XboxStep.XBOX_LIVE, error.step)
            assertEquals(401, error.status)
        }
    }

    @Test
    fun revokedRefreshTokenSignsOut() {
        val store = MemoryStore("old", XboxConsole("F1", "Salon", "XboxSeriesX", "On"))
        val http = FakeHttp(listOf("/token" to mutableListOf(HttpReply(400, """{"error":"invalid_grant"}"""))))
        try {
            XboxAccount(store, XboxAuth(http)).streamHost()
            fail()
        } catch (error: XboxException) {
            assertEquals(XboxStep.SIGNED_OUT, error.step)
        }
        assertNull(store.xboxRefreshToken)
    }

    @Test
    fun rotatedRefreshTokenIsSaved() {
        val store = MemoryStore("old", null)
        val http = FakeHttp(listOf(
            "/token" to mutableListOf(ok("""{"access_token":"a","refresh_token":"new"}""")),
            "user.auth.xboxlive.com" to mutableListOf(ok("""{"Token":"u"}""")),
            "xsts.auth.xboxlive.com" to mutableListOf(ok("""{"Token":"x"}""")),
            "login/user" to mutableListOf(ok("""{"gsToken":"g","offeringSettings":{"regions":[{"baseUri":"https://h"}]}}""")),
        ))
        XboxAccount(store, XboxAuth(http)).streamHost()
        assertEquals("new", store.xboxRefreshToken)
    }

    @Test
    fun consolesAreParsed() {
        val list = XboxApi.parseConsoles("""{"totalItems":2,"results":[
            {"deviceName":"Salon","serverId":"F4001","powerState":"ConnectedStandby","consoleType":"XboxSeriesX"},
            {"deviceName":"","serverId":"F4002","powerState":"Off","consoleType":"XboxSeriesS"},
            {"deviceName":"Bozuk"}]}""")
        assertEquals(2, list.size)
        assertEquals("Salon", list[0].name)
        assertTrue(list[0].reachable)
        assertEquals("Xbox", list[1].name)
        assertFalse(list[1].reachable)
        assertEquals("Xbox Series S", XboxConsole.typeName(list[1].type))
        assertEquals(list[0], XboxConsole.fromJson(list[0].toJson()))
        assertNull(XboxConsole.fromJson("bozuk"))
    }

    @Test
    fun teredoDecodesRfcExample() {
        // RFC 4380 örneği: sunucu 65.54.227.120, istemci 192.0.2.45:40000.
        assertEquals("192.0.2.45" to 40000, Teredo.decode("2001:0000:4136:e378:8000:63bf:3fff:fdd2"))
        assertEquals("192.0.2.45" to 40000, Teredo.decode("2001:0:4136:e378:8000:63bf:3fff:fdd2"))
        assertNull(Teredo.decode("fe80::1"))
        assertNull(Teredo.decode("192.168.0.5"))
        val remote = listOf(
            IceCandidate("a=candidate:1 1 UDP 100 2001:0:4136:e378:8000:63bf:3fff:fdd2 1234 typ host ", "0", 0),
            IceCandidate("a=candidate:2 1 UDP 50 192.168.0.20 9002 typ host ", "0", 0),
            IceCandidate("a=end-of-candidates", "0", 0),
        )
        val all = Teredo.withIpv4(remote).map { it.candidate }
        assertEquals(4, all.size)
        assertTrue(all[0].contains("192.0.2.45 9002 typ host"))
        assertTrue(all[1].contains("192.0.2.45 40000 typ host"))
    }

    @Test
    fun sessionFlowRunsInOrder() {
        val session = "/v5/sessions/home/ABC"
        val http = FakeHttp(listOf(
            "POST https://h/v5/sessions/home/play" to mutableListOf(ok("""{"sessionPath":"v5/sessions/home/ABC","sessionId":"ABC","state":"Provisioning"}""")),
            "$session/state" to mutableListOf(ok("""{"state":"Provisioning"}"""), ok("""{"state":"ReadyToConnect"}"""),
                ok("""{"state":"ReadyToConnect"}"""), ok("""{"state":"Provisioned"}""")),
            "$session/connect" to mutableListOf(ok("")),
            "POST https://h$session/sdp" to mutableListOf(HttpReply(202, "")),
            "GET https://h$session/sdp" to mutableListOf(HttpReply(204, ""),
                ok(JSONObject().put("exchangeResponse", JSONObject().put("sdp", "v=0 answer").toString()).toString())),
            "POST https://h$session/ice" to mutableListOf(HttpReply(202, "")),
            "GET https://h$session/ice" to mutableListOf(ok(JSONObject().put("exchangeResponse",
                JSONArray().put(JSONObject().put("candidate", "a=candidate:2 1 UDP 50 192.168.0.20 9002 typ host ").put("sdpMid", "0").put("sdpMLineIndex", "0")).toString()).toString())),
        ))
        val api = XboxApi(StreamHost("https://h", "gs", 0), http)
        val link = FakeLink()
        var transfers = 0
        val path = XboxSessionFlow(api, { transfers++; "lpt" }, sleep = {}).open("F4001", link)
        assertEquals(session, path)
        assertEquals(1, transfers)
        assertEquals("v=0 answer", link.received)
        assertEquals(listOf("a=candidate:2 1 UDP 50 192.168.0.20 9002 typ host "), link.remote.map { it.candidate })
        val play = JSONObject(http.bodies("/play").single())
        assertEquals("F4001", play.getString("serverId"))
        assertEquals("V3;WebrtcTransport.dll", play.getJSONObject("settings").getString("nanoVersion"))
        assertEquals("lpt", JSONObject(http.bodies("/connect").single()).getString("userToken"))
        val offer = JSONObject(http.bodies("POST https://h$session/sdp").single())
        assertEquals("offer", offer.getString("messageType"))
        assertEquals("v=0 offer", offer.getString("sdp"))
        val ice = JSONObject(http.bodies("POST https://h$session/ice").single())
        assertEquals("a=candidate:9 1 UDP 1 10.0.0.2 5000 typ host", ice.getJSONArray("candidate").getJSONObject(0).getString("candidate"))
        assertEquals("Bearer gs", http.headers.first()["Authorization"])
    }

    @Test
    fun failedSessionStops() {
        val session = "/v5/sessions/home/X"
        val http = FakeHttp(listOf(
            "/play" to mutableListOf(ok("""{"sessionPath":"v5/sessions/home/X"}""")),
            "$session/state" to mutableListOf(ok("""{"state":"Failed","errorDetails":{"code":"ConsoleOffline","message":"off"}}""")),
        ))
        try {
            XboxSessionFlow(XboxApi(StreamHost("https://h", "g", 0), http), { "t" }, sleep = {}).open("F", FakeLink())
            fail()
        } catch (error: XboxException) {
            assertEquals(XboxStep.SESSION, error.step)
            assertEquals("ConsoleOffline: off", error.detail)
        }
    }

    @Test
    fun channelMessages() {
        val meta = XboxChannels.clientMetadata(12.5)
        assertEquals(15, meta.size)
        assertEquals(8, meta[0].toInt())
        assertEquals(1, meta[14].toInt())
        assertTrue(XboxChannels.isHandshakeAck("""{"type":"HandshakeAck"}"""))
        assertFalse(XboxChannels.isHandshakeAck("bozuk"))
        val dims = JSONObject(XboxChannels.configuration().last())
        assertEquals("/streaming/characteristics/dimensionschanged", dims.getString("target"))
        assertEquals(1080, JSONObject(dims.getString("content")).getInt("vertical"))
        assertEquals(listOf("chat", "control", "input", "message"), XboxChannels.all.map { it.first })
        assertTrue(XboxCodecs.rank("video/H264", "4d0033") < XboxCodecs.rank("video/H264", "42e01f"))
        assertTrue(XboxCodecs.rank("video/H264", "42001f") < XboxCodecs.rank("video/VP8", null))
    }

    @Test
    fun lumaRegionCopy() {
        // 64x40 kare, 80 bayt satır aralığı; parlaklık = satır numarası.
        val width = 64
        val height = 40
        val stride = 80
        val buffer = ByteBuffer.allocateDirect(stride * height)
        for (y in 0 until height) for (x in 0 until stride) buffer.put(y * stride + x, y.toByte())
        val region = CropRegion(top = 0.5, bottom = 1.0, left = 0.0, right = 1.0)
        val pixels = SubtitleReader.copyLuma(buffer, stride, 1, 0, 0, width, height, region)!!
        assertEquals(64, pixels.width)
        assertEquals(20, pixels.height)
        assertEquals(20, pixels.nv21[0].toInt())
        assertEquals(39, pixels.nv21[19 * 64 + 63].toInt())
        assertEquals(128.toByte(), pixels.nv21[pixels.nv21.size - 1])
        assertNull(SubtitleReader.copyLuma(buffer, stride, 1, 0, 0, 10, 10, region))
    }
}

private class MemoryStore(override var xboxRefreshToken: String?, override var xboxConsole: XboxConsole?) : XboxStore

private class FakeLink : PeerLink {
    var received: String? = null
    val remote = mutableListOf<IceCandidate>()
    override fun createOffer() = "v=0 offer"
    override fun setAnswer(sdp: String) { received = sdp }
    override fun localCandidates() = listOf(IceCandidate("a=candidate:9 1 UDP 1 10.0.0.2 5000 typ host", "0", 0))
    override fun addRemoteCandidates(candidates: List<IceCandidate>) { remote.addAll(candidates) }
}
