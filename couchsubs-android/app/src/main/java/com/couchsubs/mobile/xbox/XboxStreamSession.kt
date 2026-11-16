// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı. Görüntü Google'ın libwebrtc'siyle (BSD-3) alınır.
package com.couchsubs.mobile.xbox

import android.content.Context
import android.util.Log
import com.couchsubs.mobile.remoteplay.DisconnectKind
import com.couchsubs.mobile.remoteplay.FrameSource
import com.couchsubs.mobile.remoteplay.ReconnectPolicy
import com.couchsubs.mobile.remoteplay.SessionState
import org.webrtc.DataChannel
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.MediaStreamTrack
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.RtpTransceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.VideoSink
import org.webrtc.VideoTrack
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Parlaklık (Y) düzlemi; yalnız çağrı süresince geçerlidir. */
fun interface LumaSink {
    fun onLuma(buffer: ByteBuffer, rowStride: Int, width: Int, height: Int)
}

/**
 * Xbox ev yayını (Xbox uygulamasındaki "Uzaktan oynat" ile aynı yol): Microsoft hesabıyla oturum açılır, konsol
 * görüntüsü WebRTC (H.264) ile telefona gelir, çözülen karelerin parlaklık düzlemi okuma hattına verilir. Ses çalınmaz,
 * mikrofon açılmaz, kol girişi gönderilmez. Bağlantı koparsa PS5 yolundaki gibi artan aralıklarla yeniden denenir.
 */
class XboxStreamSession(
    context: Context,
    private val account: XboxAccount,
    private val console: XboxConsole,
    private val onLuma: LumaSink,
    private val onState: (SessionState) -> Unit,
) : FrameSource {
    private companion object {
        const val TAG = "NinoXbox"
        /** Okuma saniyede birkaç kez yapılır; her kareyi çevirmek pili boşuna harcar. */
        const val FRAME_INTERVAL_MS = 100L
        const val KEEPALIVE_SECONDS = 30L
        const val GATHER_TIMEOUT_MS = 5_000L
        @Volatile var initialized = false
    }

    private val app = context.applicationContext
    private val worker = Executors.newSingleThreadScheduledExecutor { Thread(it, "Nino Xbox").apply { isDaemon = true } }
    private val stopped = AtomicBoolean(false)
    private val policy = ReconnectPolicy()

    // Aşağıdakiler yalnız [worker] iş parçacığında değişir.
    private var factory: PeerConnectionFactory? = null
    private var peer: PeerConnection? = null
    private var api: XboxApi? = null
    private var session: String? = null
    private var keepalive: ScheduledFuture<*>? = null
    private val channels = mutableMapOf<String, DataChannel>()
    @Volatile private var streaming = false
    @Volatile private var lastFrame = 0L
    @Volatile private var generation = 0

    @Volatile override var framesReceived = 0L
        private set

    override fun start() {
        worker.execute { connect() }
    }

    override fun dispose() {
        stopped.set(true)
        worker.execute {
            teardown()
            factory?.dispose()
            factory = null
            worker.shutdown()
        }
        onState(SessionState.Disconnected(DisconnectKind.STOPPED))
    }

    private fun connect() {
        if (stopped.get()) return
        onState(SessionState.Connecting)
        val attempt = ++generation
        try {
            val host = account.streamHost()
            val api = XboxApi(host).also { this.api = it }
            val link = createPeer(attempt)
            val flow = XboxSessionFlow(api, account::transferToken, stopped = { stopped.get() || attempt != generation })
            val path = flow.open(console.serverId, link) { session = it }
            session = path
            keepalive = worker.scheduleWithFixedDelay({
                try { api.keepalive(path) } catch (error: Exception) { Log.w(TAG, "keepalive", error) }
            }, KEEPALIVE_SECONDS, KEEPALIVE_SECONDS, TimeUnit.SECONDS)
        } catch (error: InterruptedException) {
            return
        } catch (error: XboxException) {
            Log.w(TAG, "oturum kurulamadı", error)
            val kind = when (error.step) {
                XboxStep.SIGNED_OUT -> DisconnectKind.XBOX_SIGNED_OUT
                XboxStep.SESSION -> DisconnectKind.XBOX_UNREACHABLE
                else -> DisconnectKind.NETWORK
            }
            fail(kind, error.detail, retry = kind != DisconnectKind.XBOX_SIGNED_OUT)
        } catch (error: Exception) {
            Log.w(TAG, "bağlantı", error)
            fail(DisconnectKind.NETWORK, error.message, retry = true)
        }
    }

    private fun fail(kind: DisconnectKind, detail: String?, retry: Boolean) {
        teardown()
        if (stopped.get()) return
        onState(SessionState.Disconnected(kind, detail))
        if (retry) try {
            worker.schedule({ connect() }, policy.nextDelaySeconds().toLong(), TimeUnit.SECONDS)
        } catch (error: java.util.concurrent.RejectedExecutionException) { }
    }

    private fun teardown() {
        keepalive?.cancel(false)
        keepalive = null
        streaming = false
        channels.values.forEach { try { it.unregisterObserver(); it.close(); it.dispose() } catch (error: Exception) { } }
        channels.clear()
        peer?.let { try { it.close(); it.dispose() } catch (error: Exception) { Log.w(TAG, "kapatma", error) } }
        peer = null
        val path = session
        val api = api
        session = null
        if (path != null && api != null) api.stop(path)
    }

    private fun factory(): PeerConnectionFactory {
        factory?.let { return it }
        if (!initialized) {
            PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(app).createInitializationOptions())
            initialized = true
        }
        // EGL bağlamı verilmez: donanım çözücü kareyi dokuya değil belleğe yazar (Y düzlemi doğrudan okunur).
        return PeerConnectionFactory.builder()
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(null))
            .createPeerConnectionFactory()
            .also { factory = it }
    }

    private fun createPeer(attempt: Int): PeerLink {
        val factory = factory()
        val candidates = mutableListOf<IceCandidate>()
        val gathered = CountDownLatch(1)
        val config = PeerConnection.RTCConfiguration(emptyList()).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
        }
        val observer = object : PeerConnection.Observer {
            override fun onSignalingChange(state: PeerConnection.SignalingState?) {}
            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState?) {}
            override fun onConnectionChange(state: PeerConnection.PeerConnectionState?) {
                Log.i(TAG, "bağlantı: $state")
                if (state == PeerConnection.PeerConnectionState.FAILED || state == PeerConnection.PeerConnectionState.DISCONNECTED)
                    post { if (attempt == generation && !stopped.get()) fail(DisconnectKind.NETWORK, state.name, retry = true) }
            }
            override fun onIceConnectionReceivingChange(receiving: Boolean) {}
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState?) {
                if (state == PeerConnection.IceGatheringState.COMPLETE) gathered.countDown()
            }
            override fun onIceCandidate(candidate: org.webrtc.IceCandidate) {
                synchronized(candidates) { candidates.add(IceCandidate("a=" + candidate.sdp.removePrefix("a="), candidate.sdpMid, candidate.sdpMLineIndex)) }
            }
            override fun onIceCandidatesRemoved(removed: Array<out org.webrtc.IceCandidate>?) {}
            override fun onAddStream(stream: MediaStream?) {}
            override fun onRemoveStream(stream: MediaStream?) {}
            override fun onDataChannel(channel: DataChannel?) {}
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(receiver: RtpReceiver?, streams: Array<out MediaStream>?) {}
            override fun onTrack(transceiver: RtpTransceiver) {
                when (val track = transceiver.receiver.track()) {
                    is VideoTrack -> track.addSink(sink(attempt))
                    // Oyun sesi telefondan çalmasın (ses TV'den gelir).
                    null -> {}
                    else -> if (track.kind() == MediaStreamTrack.AUDIO_TRACK_KIND) track.setEnabled(false)
                }
            }
        }
        val pc = factory.createPeerConnection(config, observer) ?: throw IllegalStateException("createPeerConnection null")
        peer = pc
        pc.addTransceiver(MediaStreamTrack.MediaType.MEDIA_TYPE_AUDIO, RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY))
        val video = pc.addTransceiver(MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO, RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY))
        try {
            val codecs = factory.getRtpReceiverCapabilities(MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO).codecs
            video.setCodecPreferences(codecs.sortedBy { XboxCodecs.rank(it.mimeType ?: it.name ?: "", it.parameters?.get("profile-level-id")) })
        } catch (error: Exception) {
            Log.w(TAG, "kodek sırası", error)
        }
        for ((name, protocol) in XboxChannels.all) {
            val channel = pc.createDataChannel(name, DataChannel.Init().apply { ordered = true; this.protocol = protocol }) ?: continue
            channels[name] = channel
            channel.registerObserver(channelObserver(name, channel))
        }

        return object : PeerLink {
            override fun createOffer(): String {
                val offer = await<SessionDescription> { done -> pc.createOffer(done, MediaConstraints()) }
                await<Unit> { done -> pc.setLocalDescription(done, offer) }
                return offer.description
            }

            override fun setAnswer(sdp: String) {
                await<Unit> { done -> pc.setRemoteDescription(done, SessionDescription(SessionDescription.Type.ANSWER, sdp)) }
            }

            override fun localCandidates(): List<IceCandidate> {
                gathered.await(GATHER_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                return synchronized(candidates) { candidates.toList() }
            }

            override fun addRemoteCandidates(candidates: List<IceCandidate>) {
                for (candidate in candidates) {
                    val line = candidate.candidate.removePrefix("a=").trim()
                    if (!pc.addIceCandidate(org.webrtc.IceCandidate(candidate.sdpMid ?: "0", candidate.sdpMLineIndex, line)))
                        Log.w(TAG, "aday eklenemedi: $line")
                }
            }
        }
    }

    private fun channelObserver(name: String, channel: DataChannel) = object : DataChannel.Observer {
        override fun onBufferedAmountChange(previous: Long) {}
        override fun onStateChange() {
            if (channel.state() == DataChannel.State.OPEN && name == XboxChannels.MESSAGE) send(XboxChannels.MESSAGE, XboxChannels.handshake())
        }
        override fun onMessage(buffer: DataChannel.Buffer) {
            if (name != XboxChannels.MESSAGE || buffer.binary) return
            val bytes = ByteArray(buffer.data.remaining()).also { buffer.data.get(it) }
            if (XboxChannels.isHandshakeAck(String(bytes, Charsets.UTF_8))) {
                send(XboxChannels.CONTROL, XboxChannels.authorization())
                send(XboxChannels.CONTROL, XboxChannels.gamepadChanged(0, true))
                send(XboxChannels.CONTROL, XboxChannels.gamepadChanged(0, false))
                channels[XboxChannels.INPUT]?.send(DataChannel.Buffer(ByteBuffer.wrap(XboxChannels.clientMetadata(System.nanoTime() / 1e6)), true))
                XboxChannels.configuration().forEach { send(XboxChannels.MESSAGE, it) }
            }
        }
    }

    /** Kapatıldıktan sonra gelen WebRTC geri çağrıları yok sayılır. */
    private fun post(task: () -> Unit) {
        try { worker.execute(task) } catch (error: java.util.concurrent.RejectedExecutionException) { }
    }

    private fun send(name: String, text: String) {
        channels[name]?.send(DataChannel.Buffer(ByteBuffer.wrap(text.toByteArray(Charsets.UTF_8)), false))
    }

    private fun sink(attempt: Int) = VideoSink { frame ->
        if (attempt != generation || stopped.get()) return@VideoSink
        framesReceived++
        if (!streaming) {
            streaming = true
            onState(SessionState.Streaming)
        }
        val now = System.currentTimeMillis()
        if (now - lastFrame < FRAME_INTERVAL_MS) return@VideoSink
        lastFrame = now
        val i420 = frame.buffer.toI420() ?: return@VideoSink
        try {
            onLuma.onLuma(i420.dataY, i420.strideY, i420.width, i420.height)
        } catch (error: Exception) {
            Log.w(TAG, "kare", error)
        } finally {
            i420.release()
        }
    }

    /** org.webrtc'nin geri çağrılı SDP işlemlerini bloklayan çağrıya çevirir. */
    private class Done<T> {
        val latch = CountDownLatch(1)
        @Volatile var value: T? = null
        @Volatile var error: String? = null
    }

    private fun <T> await(start: (SdpObserver) -> Unit): T {
        val done = Done<T>()
        start(object : SdpObserver {
            @Suppress("UNCHECKED_CAST")
            override fun onCreateSuccess(description: SessionDescription?) { done.value = description as T?; done.latch.countDown() }
            @Suppress("UNCHECKED_CAST")
            override fun onSetSuccess() { done.value = Unit as T; done.latch.countDown() }
            override fun onCreateFailure(error: String?) { done.error = error ?: "create"; done.latch.countDown() }
            override fun onSetFailure(error: String?) { done.error = error ?: "set"; done.latch.countDown() }
        })
        if (!done.latch.await(10, TimeUnit.SECONDS)) throw XboxException(XboxStep.SESSION, null, "sdp timeout")
        done.error?.let { throw XboxException(XboxStep.SESSION, null, it) }
        return done.value ?: throw XboxException(XboxStep.SESSION, null, "sdp empty")
    }

}
