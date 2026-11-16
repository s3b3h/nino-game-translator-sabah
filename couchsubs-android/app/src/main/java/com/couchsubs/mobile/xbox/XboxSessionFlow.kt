// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı. Sıra ve kanal mesajları açık kaynak Greenlight / xbox-xcloud-player'dan
// (MIT, UnknownSKL) öğrenildi; bkz. THIRD-PARTY-NOTICES.md.
package com.couchsubs.mobile.xbox

import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

/** WebRTC bağlantısının oturum akışının ihtiyaç duyduğu kısmı; gerçeği org.webrtc, testte sahtesi. */
interface PeerLink {
    /** Teklif SDP'si üretir ve yerel tanım olarak kurar (bloklar). */
    fun createOffer(): String
    fun setAnswer(sdp: String)
    /** Yerel ICE adayları (toplama bitene ya da süre dolana kadar bekler). */
    fun localCandidates(): List<IceCandidate>
    fun addRemoteCandidates(candidates: List<IceCandidate>)
}

/**
 * Xbox ev yayını oturumunun kurulumu: oturumu aç → konsol hazırlanana kadar bekle (ReadyToConnect'te hesabı bağla) →
 * SDP teklif/yanıt → ICE aday değişimi. Ağ çağrıları bloklar; arka plan iş parçacığında çalışır.
 */
class XboxSessionFlow(
    private val api: XboxApi,
    private val transferToken: () -> String,
    private val sleep: (Long) -> Unit = Thread::sleep,
    private val stopped: () -> Boolean = { false },
    private val clock: () -> Long = System::currentTimeMillis,
) {
    companion object {
        const val PROVISION_TIMEOUT_MS = 120_000L
        const val EXCHANGE_TIMEOUT_MS = 30_000L
        const val POLL_MS = 1_000L
    }

    /** Oturum yolunu döndürür (keepalive ve kapatma için). Konsol yanıt vermezse ya da reddederse [XboxException]. */
    fun open(serverId: String, link: PeerLink, onSession: (String) -> Unit = {}): String {
        val session = api.startHome(serverId)
        onSession(session)
        waitProvisioned(session)
        api.postOffer(session, link.createOffer())
        link.setAnswer(poll("sdp") { api.answer(session) })
        api.postCandidates(session, link.localCandidates())
        link.addRemoteCandidates(Teredo.withIpv4(poll("ice") { api.remoteCandidates(session) }))
        return session
    }

    private fun waitProvisioned(session: String) {
        val deadline = clock() + PROVISION_TIMEOUT_MS
        var connected = false
        while (true) {
            check()
            val (state, detail) = api.state(session)
            when (state) {
                "Provisioned" -> return
                "ReadyToConnect" -> if (!connected) {
                    api.connect(session, transferToken())
                    connected = true
                }
                "Failed" -> throw XboxException(XboxStep.SESSION, null, detail ?: "Failed")
            }
            if (clock() > deadline) throw XboxException(XboxStep.SESSION, null, "timeout in $state")
            sleep(POLL_MS)
        }
    }

    private fun <T> poll(what: String, ask: () -> T?): T {
        val deadline = clock() + EXCHANGE_TIMEOUT_MS
        while (true) {
            check()
            ask()?.let { return it }
            if (clock() > deadline) throw XboxException(XboxStep.SESSION, null, "no $what answer")
            sleep(POLL_MS / 2)
        }
    }

    private fun check() {
        if (stopped()) throw InterruptedException("stopped")
    }
}

/**
 * Veri kanallarının mesajları. Nino yalnız izler: kol girişi göndermez (kol takıldı/çıktı çifti, Xbox'ın yayını
 * başlatması için gönderilir; ardından kol "yok" kalır, oyuncunun kendi kolu çalışmaya devam eder).
 */
object XboxChannels {
    const val MESSAGE = "message"
    const val CONTROL = "control"
    const val INPUT = "input"
    const val CHAT = "chat"

    /** (ad, protokol) — Greenlight'taki sırayla. */
    val all = listOf(CHAT to "chatV1", CONTROL to "controlV1", INPUT to "1.0", MESSAGE to "messageV1")

    fun handshake(): String = JSONObject().put("type", "Handshake").put("version", "messageV1")
        .put("id", UUID.randomUUID().toString()).put("cv", "0").toString()

    fun isHandshakeAck(text: String): Boolean = try { JSONObject(text).optString("type") == "HandshakeAck" } catch (error: Exception) { false }

    /** Xbox web istemcisinin sabit erişim anahtarı (Greenlight'taki değer). */
    fun authorization(): String = JSONObject().put("message", "authorizationRequest")
        .put("accessKey", "4BDB3609-C1F1-4195-9B37-FEFF45DA8B8E").toString()

    fun gamepadChanged(index: Int, added: Boolean): String =
        JSONObject().put("message", "gamepadChanged").put("gamepadIndex", index).put("wasAdded", added).toString()

    /** El sıkışmadan sonra gönderilen ayarlar: 1080p görüntü, dokunmatik kapalı. */
    fun configuration(width: Int = XboxApi.WIDTH, height: Int = XboxApi.HEIGHT): List<String> = listOf(
        message("/streaming/systemUi/configuration", JSONObject().put("version", org.json.JSONArray(listOf(0, 2, 0))).put("systemUis", org.json.JSONArray())),
        message("/streaming/properties/clientappinstallidchanged", JSONObject().put("clientAppInstallId", UUID.randomUUID().toString())),
        message("/streaming/characteristics/orientationchanged", JSONObject().put("orientation", 0)),
        message("/streaming/characteristics/touchinputenabledchanged", JSONObject().put("touchInputEnabled", false)),
        message("/streaming/characteristics/clientdevicecapabilities", JSONObject()),
        message("/streaming/characteristics/dimensionschanged", JSONObject()
            .put("horizontal", width).put("vertical", height).put("preferredWidth", width).put("preferredHeight", height)
            .put("safeAreaLeft", 0).put("safeAreaTop", 0).put("safeAreaRight", width).put("safeAreaBottom", height)
            .put("supportsCustomResolution", true)),
    )

    /** Giriş kanalının ilk paketi (istemci bilgisi): rapor türü 8, sıra 0, zaman, en çok dokunma noktası. 15 bayt. */
    fun clientMetadata(nowMs: Double, maxTouchPoints: Int = 1): ByteArray {
        val buffer = ByteBuffer.allocate(15).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putShort(8.toShort()).putInt(0).putDouble(nowMs).put(maxTouchPoints.toByte())
        return buffer.array()
    }

    private fun message(target: String, content: JSONObject) = JSONObject()
        .put("type", "Message").put("content", content.toString()).put("id", UUID.randomUUID().toString())
        .put("target", target).put("cv", "").toString()
}

/** H.264 profillerinin sırası: yüksek (4d), ana (42e), temel (420); Xbox yalnız H.264 gönderir. */
object XboxCodecs {
    fun rank(mimeType: String, profileLevelId: String?): Int {
        if (!mimeType.contains("H264", ignoreCase = true)) return if (mimeType.contains("fec", ignoreCase = true)) 4 else 5
        val profile = profileLevelId?.lowercase() ?: return 3
        return when {
            profile.startsWith("4d") -> 0
            profile.startsWith("42e") -> 1
            profile.startsWith("420") -> 2
            else -> 3
        }
    }
}
