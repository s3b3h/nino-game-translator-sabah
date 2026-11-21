// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.remoteplay

import android.os.SystemClock
import android.util.Log
import com.couchsubs.mobile.account.Backend
import com.couchsubs.mobile.account.Telemetry
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Bağlantının neden koptuğu; kullanıcıya anlatılabilecek biçimde (Windows: DisconnectKind). */
enum class DisconnectKind {
    STOPPED, IN_USE, REFUSED, NETWORK, NOT_FOUND, CONSOLE_ASLEEP,
    /** PS5 bu hesap için giriş şifresi istiyor, Ayarlar'da kayıtlı şifre yok. */
    LOGIN_PASSCODE,
    /** PS5 Ayarlar'daki giriş şifresini kabul etmedi; yeniden gönderilmez. */
    LOGIN_PASSCODE_INCORRECT,
    /**
     * PS5 oturum isteğinde kaydı kabul etmedi (0x80108b09 kayıt geçersiz, 0x80108b02 hesap tanınmıyor). Yeniden denemek
     * aynı yere çıkar; PS5 ikinci hesapla yeniden eşlenmelidir.
     */
    REGISTRATION_INVALID,
    /**
     * PS5'te Uzaktan Oynama kapalı (0x80108b12): eşleme durur ama PS5 oturum açmaz; kullanıcı PS5'te Ayarlar › Sistem ›
     * Uzaktan Oynama'dan açmalıdır. Yeniden denemek aynı yere çıkar.
     */
    REMOTE_PLAY_DISABLED,
    /**
     * Bağlantı kuruluyor ama art arda [PictureWatchdog.MAX_NO_PICTURE_SESSIONS] oturumda PS5'ten hiç görüntü gelmedi
     * (iki çözücü türüyle de). Sonsuz "Bağlantı koptu, yeniden bağlanılıyor" döngüsü yerine durulur.
     */
    NO_PICTURE,
    /**
     * PS5 oturum isteğini kayıt dışı bir nedenle reddetti ya da yanıtı okunamadı; libchiaki bunu yalnız "Unknown Session
     * Request Error" diye verir (GitHub #33, #202). Ayrıntı: PS5'in "Reported Application Reason" kodu (ör. 0x80108bff;
     * günlükte kod yoksa null).
     */
    REJECTED,
    OTHER,
    // Nino: yakalama kartı kaynağı (capture/CaptureCardSource): kart takılı değil, kamera izni yok, görüntü simsiyah.
    NO_CAPTURE_CARD, NO_CAMERA_PERMISSION, BLACK_PICTURE;

    companion object {
        /**
         * CHIAKI_RP_APPLICATION_REASON_REGIST_FAILED ve _INVALID_PSN_ID; 0x80108b26: PS5 eşleme anahtarını kendi
         * kayıtlarında bulamadı (eşleme PS5'te silinmiş ya da başka hesapla yapılmış), PS5 yeniden eşlenmelidir.
         */
        val REGISTRATION_REJECTED_CODES = setOf(0x80108b09L, 0x80108b02L, 0x80108b26L)

        /** PS5'te Uzaktan Oynama kapalıyken dönen kod. */
        const val REMOTE_PLAY_DISABLED_CODE = 0x80108b12L
        private val unreachableLines = listOf(
            "Session request connect failed eventually",
            "Failed to send session request",
            "Failed to receive session request response",
        )

        /** libchiaki'nin CHIAKI_QUIT_REASON_SESSION_REQUEST_UNKNOWN metni. */
        const val UNKNOWN_SESSION_REQUEST = "Unknown Session Request Error"

        /**
         * libchiaki oturum isteği (TCP 9295) düşünce yalnız "Unknown Session Request Error" der; asıl neden günlük
         * satırındadır. Satırdan anlaşılan neden; anlaşılmıyorsa null (Mac/iPhone: DisconnectReason.sessionRequestHint).
         * PS5 kayıt dışı bir kodla reddettiyse [REJECTED], ayrıntıda kod.
         */
        fun sessionRequestHint(line: String): SessionState.Disconnected? {
            val marker = "Reported Application Reason:"
            val at = line.indexOf(marker)
            if (at >= 0) {
                val token = line.substring(at + marker.length).trimStart(' ').takeWhile { !it.isWhitespace() }.lowercase()
                val code = token.removePrefix("0x").toLongOrNull(16) ?: return null
                if (code == REMOTE_PLAY_DISABLED_CODE) return SessionState.Disconnected(REMOTE_PLAY_DISABLED)
                return if (code in REGISTRATION_REJECTED_CODES) SessionState.Disconnected(REGISTRATION_INVALID)
                    else SessionState.Disconnected(REJECTED, "0x%08x".format(code))
            }
            // PS5'e bağlanılamadı ya da yanıt gelmedi: PS5 dinlenmeden yeni uyandıysa ilk denemelerde olağandır.
            return if (unreachableLines.any { line.contains(it) }) SessionState.Disconnected(NETWORK) else null
        }

        /** Günlük satırlarından anlaşılan son neden (sonraki satır öncekinden daha yenidir). */
        fun sessionRequestHint(lines: List<String>): SessionState.Disconnected? =
            lines.mapNotNull(::sessionRequestHint).lastOrNull()
    }
}

/** Art arda oturumlarda PS5'ten hiç görüntü gelmedi (Crashlytics'e günlüğüyle birlikte gider). */
class NoPictureException(message: String) : RuntimeException(message)

/** PS5 oturum giriş şifresi (4 hane). PS5 ikinci hesapta şifre isterse Ayarlar'da kayıtlı şifre gönderilir. */
object LoginPasscode {
    const val LENGTH = 4

    /** Boşlukları atar; tam 4 rakam değilse null. */
    fun normalized(value: String?): String? {
        val trimmed = value?.trim() ?: return null
        return trimmed.takeIf { it.length == LENGTH && it.all { c -> c in '0'..'9' } }
    }

    sealed class Reply {
        /** libchiaki rakamları ASCII bekler (chiaki-ng'deki gibi). */
        class Send(val pin: ByteArray) : Reply()
        data class Stop(val kind: DisconnectKind) : Reply()
    }

    /** Şifre yoksa ya da PS5 önceki şifreyi kabul etmediyse oturum kapanır; yanlış şifreyle döngüye girilmez. */
    fun reply(saved: String?, incorrect: Boolean): Reply {
        if (incorrect) return Reply.Stop(DisconnectKind.LOGIN_PASSCODE_INCORRECT)
        val pin = normalized(saved) ?: return Reply.Stop(DisconnectKind.LOGIN_PASSCODE)
        return Reply.Send(pin.toByteArray(Charsets.US_ASCII))
    }
}

sealed class SessionState {
    data object Connecting : SessionState()
    data object Streaming : SessionState()
    data class Disconnected(val kind: DisconnectKind, val detail: String? = null) : SessionState()
}

/** Bağlantı koptuğunda yeniden deneme aralıkları: 2, 4, 8, 16, en çok 30 sn (Windows ile aynı). */
class ReconnectPolicy {
    private var attempt = 0
    fun nextDelaySeconds(): Int {
        val delay = minOf(30, 2 shl attempt)
        attempt = minOf(attempt + 1, 5)
        return delay
    }
    fun reset() {
        attempt = 0
    }
}

/**
 * Bağlı oturumda PS5'ten görüntü gelmiyor mu (Mac ve Windows'taki PictureWatchdog ile aynı kural).
 * libchiaki bir karenin FEC onarımı tutmayınca PS5'ten bir kez yeni anahtar kare (IDR) ister ve o gelene kadar bütün
 * kareleri atlar (enable_idr_on_fec_failure). İstenen IDR karesinin kendisi de bozuk gelirse yeniden istemez ("Video FEC
 * failure, already waiting for requested IDR"): bağlantı açık kalır, ama bir daha hiç kare gelmez; altyazı ancak
 * uygulamayı kapatıp açınca dönüyordu. Bağlıyken [STALL_AFTER_MS] boyunca hiç görüntü gelmezse oturum yeniden kurulur;
 * yeni oturum anahtar kareyle başlar.
 */
class PictureWatchdog {
    companion object {
        /** IDR ile olağan toparlanma bir saniyeden kısa sürer; bundan uzun boşluk takılmadır. */
        const val STALL_AFTER_MS = 8_000L
        /** Bağlandıktan sonra ilk kare bu sürede gelmezse çözücü türü değiştirilip yeniden denenir. */
        const val FIRST_PICTURE_MS = 5_000L
        /** Art arda bu kadar oturumda hiç görüntü gelmezse yeniden bağlanma bırakılır. */
        const val MAX_NO_PICTURE_SESSIONS = 3
        /** Yeniden bağlanırken görünen neden. */
        const val REASON = "no picture from the PS5"
    }

    /** Takılma sonrası ne yapılacak. */
    enum class Next {
        /** Oturumda görüntü gelmişti, sonra kesildi: aynı çözücüyle yeniden kur. */
        RECONNECT,
        /** Oturumda hiç görüntü gelmedi: çözücü türünü değiştirip ([swapDecoder]) yeniden kur. */
        RECONNECT_OTHER_DECODER,
        /** Art arda [MAX_NO_PICTURE_SESSIONS] oturumda görüntü yok: döngüyü bırak. */
        GIVE_UP,
    }

    /** Bağlıyken son görüntünün (ya da bağlanmanın) anı; bağlı değilken null. */
    private var since: Long? = null
    /** Bu oturumda görüntü geldi mi. */
    private var hasPicture = false
    /** Art arda hiç görüntü gelmeyen oturum sayısı; görüntü gelince sıfırlanır. */
    private var noPictureSessions = 0

    /** Bir sonraki oturum, üreticiye göre seçilen çözücü türünün (yazılım/donanım) tersiyle başlasın mı. */
    val swapDecoder: Boolean @Synchronized get() = noPictureSessions % 2 == 1

    /** Art arda görüntüsüz oturum sayısı (tanı). */
    val noPictureStreak: Int @Synchronized get() = noPictureSessions

    /** Kullanıcı başlattı ya da ağ değişti: sayaç sıfırdan. */
    @Synchronized fun reset() {
        since = null
        hasPicture = false
        noPictureSessions = 0
    }

    /** Oturum bağlandı: süre bağlanma anından sayılır (ilk kare hiç gelmezse de yakalanır). */
    @Synchronized fun connected(nowMs: Long) {
        since = nowMs
        hasPicture = false
    }

    /** Görüntü geldi (kare iş parçacığından). */
    @Synchronized fun picture(nowMs: Long) {
        if (since != null) {
            since = nowMs
            hasPicture = true
            noPictureSessions = 0
        }
    }

    /** [stalledMs] boşluk bildirdi; oturum kapatılırken ne yapılacağı. */
    @Synchronized fun stalled(): Next {
        if (hasPicture) return Next.RECONNECT
        noPictureSessions++
        return if (noPictureSessions >= MAX_NO_PICTURE_SESSIONS) Next.GIVE_UP else Next.RECONNECT_OTHER_DECODER
    }

    /** Oturum kapandı ya da yeniden kuruluyor. */
    @Synchronized fun ended() {
        since = null
    }

    /**
     * Bağlıyken [STALL_AFTER_MS]'den (oturumda henüz hiç görüntü gelmediyse [FIRST_PICTURE_MS]'den) uzun süredir
     * görüntü yoksa boşluğun süresi (ms); yoksa null.
     */
    @Synchronized fun stalledMs(nowMs: Long): Long? {
        val last = since ?: return null
        val gap = nowMs - last
        return if (gap >= (if (hasPicture) STALL_AFTER_MS else FIRST_PICTURE_MS)) gap else null
    }
}

/**
 * PS5'e (ikinci hesapla) Remote Play bağlantısı kurar; görüntü MediaCodec'le yüzeysiz çözülür, her karenin parlaklık
 * düzlemi yerel tarafta kopyalanıp [onFrame]'e verilir (kare yalnız çağrı süresince geçerlidir; çözücünün iş
 * parçacığında çağrılır, kısa sürmeli). Ses kapalıdır, kol girdisi gönderilmez. Bağlantı koparsa
 * kendiliğinden yeniden bağlanır; PS5 uyuyorsa uyandırılır, adresi değiştiyse ağda yeniden bulunur. Windows'taki
 * StreamSession.cs ile aynı akış.
 */
class StreamSession(
    console: RegisteredConsole,
    private val accountId: ByteArray,
    private val onFrame: (VideoFrame) -> Unit,
    private val onState: (SessionState) -> Unit,
    private val onConsoleMoved: (RegisteredConsole) -> Unit = {},
    private val width: Int = 1920,
    private val height: Int = 1080,
    /** PS5 bu hesap için giriş şifresi isterse gönderilecek 4 hane (Ayarlar'da kayıtlıysa). */
    private val loginPasscode: String? = null,
) : FrameSource {
    private companion object {
        const val TAG = "CouchSubsSession"
        const val RELOCATE_INTERVAL_MS = 30_000L
    }

    @Volatile private var console = console
    private val queue = Executors.newSingleThreadScheduledExecutor { Thread(it, "CouchSubs session").apply { isDaemon = true } }
    private val policy = ReconnectPolicy()
    /** Bağlıyken görüntü gelmezse oturum yeniden kurulur. */
    private val watchdog = PictureWatchdog()
    private val stateLock = Any()
    private var running = false
    private var generation = 0
    private var nextRelocate = 0L
    private var searchAnswered = true

    /** Yalnız kuyrukta okunur/yazılır. */
    private var native = 0L
    private var nativeGeneration = 0

    override fun start() {
        val current = bump(true)
        queue.execute {
            policy.reset()
            watchdog.reset()
            connect(current)
        }
    }

    /** Bloklamaz: oturum arka planda kapatılır. */
    fun stop() {
        bump(false)
        queue.execute(::closeNative)
    }

    override fun dispose() {
        stop()
        queue.execute { queue.shutdown() }
    }

    /** Ağ değiştiğinde uygulama çağırır. */
    fun reconnectNow() {
        if (!isRunning) return
        val current = bump(true)
        queue.execute {
            closeNative()
            policy.reset()
            watchdog.reset()
            connect(current)
        }
    }

    /** Çözücüden gelen kare sayısı (tanı: görüntü geliyor mu). */
    @Volatile override var framesReceived = 0L
        private set

    private val isRunning get() = synchronized(stateLock) { running }

    private fun bump(value: Boolean) = synchronized(stateLock) {
        running = value
        ++generation
    }

    private fun isCurrent(value: Int) = synchronized(stateLock) { running && generation == value }

    private fun connect(current: Int) {
        if (!isCurrent(current) || native != 0L) return
        emit(SessionState.Connecting)
        val info = ConsoleDiscovery.discover(console.host, 2000).firstOrNull() ?: relocate()
        searchAnswered = info != null
        Log.i(TAG, if (info == null) "PS5 ${console.host} aramaya yanıt vermedi, yine de bağlanılıyor"
            else "PS5 ${info.name} ${info.host} ${if (info.isAwake) "uyanık" else "dinlenmede, uyandırılıyor"}")
        if (info != null && !info.isAwake) {
            try {
                ConsoleDiscovery.wake(console)
            } catch (error: Exception) {
                Log.w(TAG, "wake: ${error.message}")
            }
            waitForWake(current, System.currentTimeMillis() + 20_000)
            return
        }
        openSession(current)
    }

    private fun relocate(): ConsoleInfo? {
        val now = System.currentTimeMillis()
        if (now < nextRelocate) return null
        nextRelocate = now + RELOCATE_INTERVAL_MS
        val moved = ConsoleDiscovery.pickMoved(ConsoleDiscovery.discover(null, 3000), console.name)
        if (moved == null || moved.host == console.host) return null
        Log.i(TAG, "PS5 yeni adreste: ${console.host} -> ${moved.host}")
        console = console.withHost(moved.host)
        onConsoleMoved(console)
        return moved
    }

    private fun waitForWake(current: Int, deadline: Long) {
        queue.schedule({
            if (!isCurrent(current)) return@schedule
            when {
                ConsoleDiscovery.discover(console.host, 2000).any { it.isAwake } -> openSession(current)
                System.currentTimeMillis() < deadline -> waitForWake(current, deadline)
                else -> scheduleReconnect(current, SessionState.Disconnected(DisconnectKind.CONSOLE_ASLEEP))
            }
        }, 2, TimeUnit.SECONDS)
    }

    private fun openSession(current: Int) {
        if (!isCurrent(current) || native != 0L) return
        var described = false
        // Çözücünün çıkış iş parçacığından gelir. Kare Java'nın arabelleğindedir (Image.getPlanes yok): okunamayan
        // kare yerel tarafta atlanır, burada JNI'yi durduracak bir çağrı kalmadı.
        val frames = NativeFrameListener { buffer, frameWidth, frameHeight, rowStride, colorFormat, hasChroma ->
            framesReceived++
            watchdog.picture(SystemClock.elapsedRealtime())
            if (!described) {
                described = true
                val text = "PS5: ilk kare ${frameWidth}x$frameHeight biçim 0x${Integer.toHexString(colorFormat)}"
                Log.i(TAG, text)
                Backend.breadcrumb(text)
            }
            try {
                onFrame(VideoFrame(buffer, frameWidth, frameHeight, rowStride, colorFormat, nativeChroma(buffer, frameWidth, frameHeight, hasChroma)))
            } catch (error: RuntimeException) {
                Log.e(TAG, "frame handler", error)
            }
        }
        val outcome = NativeOutcome()
        val listener = NativeSessionListener { type, reason, text -> handle(type, reason, text, current) }
        val c = console
        val swapDecoder = watchdog.swapDecoder
        if (swapDecoder) Backend.breadcrumb("PS5: önceki oturumda görüntü gelmedi; öbür çözücü türüyle deneniyor")
        val ptr = NativeBridge.sessionStart(c.host, c.registKey, c.morning, accountId, width, height, frames,
            swapDecoder, listener, outcome)
        if (ptr == 0L) {
            Log.w(TAG, "PS5 oturumu başlatılamadı (${c.host}): ${outcome.errors}")
            scheduleReconnect(current, SessionState.Disconnected(DisconnectKind.OTHER, outcome.errorLines.lastOrNull() ?: "session could not be started"))
            return
        }
        native = ptr
        nativeGeneration = current
    }

    /** Oturumu kapatır (join içerir; yalnız kuyrukta, asla yerel geri çağrıdan değil). */
    private fun closeNative() {
        val ptr = native
        if (ptr != 0L) {
            native = 0L
            // Çözücünün çıkış iş parçacığını da bekler: dönünce [onFrame] bir daha çağrılmaz.
            NativeBridge.sessionStop(ptr)
        }
        // Kapanırken gelen son kare bekçiyi yeniden kurmasın diye durdurmadan sonra.
        watchdog.ended()
    }

    /** libchiaki'nin iş parçacığından çağrılır. */
    private fun handle(type: Int, reason: Int, text: String?, eventGeneration: Int) {
        when (type) {
            NativeBridge.EVENT_CONNECTED -> queue.execute {
                if (nativeGeneration != eventGeneration || native == 0L) return@execute
                policy.reset()
                watchdog.connected(SystemClock.elapsedRealtime())
                emit(SessionState.Streaming)
                scheduleWatch(eventGeneration)
            }
            // libchiaki olayı kilit tutarken verir; şifre kuyrukta gönderilir.
            NativeBridge.EVENT_LOGIN_PIN -> {
                val reply = LoginPasscode.reply(loginPasscode, incorrect = reason == 1)
                queue.execute {
                    if (nativeGeneration != eventGeneration || native == 0L) return@execute
                    when (reply) {
                        is LoginPasscode.Reply.Send -> {
                            Log.i(TAG, "PS5 giriş şifresi istedi; Ayarlar'daki şifre gönderiliyor")
                            NativeBridge.sessionSetLoginPin(native, reply.pin)
                        }
                        // Şifre yok ya da yanlış: yeniden denemek aynı yere çıkar.
                        is LoginPasscode.Reply.Stop -> {
                            bump(false)
                            closeNative()
                            emit(SessionState.Disconnected(reply.kind))
                        }
                    }
                }
            }
            NativeBridge.EVENT_QUIT -> {
                val general = when (reason) {
                    NativeBridge.QUIT_STOPPED -> DisconnectKind.STOPPED
                    NativeBridge.QUIT_IN_USE -> DisconnectKind.IN_USE
                    NativeBridge.QUIT_REFUSED -> DisconnectKind.REFUSED
                    NativeBridge.QUIT_NETWORK -> DisconnectKind.NETWORK
                    else -> DisconnectKind.OTHER
                }
                queue.execute {
                    if (nativeGeneration != eventGeneration || native == 0L) return@execute
                    // "Unknown Session Request Error": asıl neden libchiaki'nin hata satırlarındadır (iPhone ve Mac ile aynı).
                    // Satırlarda neden yoksa PS5 oturumu başlatmamıştır: anlamsız İngilizce metin yerine REJECTED.
                    val hint = if (general == DisconnectKind.OTHER && text?.contains("Session Request", ignoreCase = true) == true)
                        DisconnectKind.sessionRequestHint(NativeBridge.sessionErrors(native)?.split('\n').orEmpty())
                        else null
                    val state = hint
                        ?: if (general == DisconnectKind.OTHER && text == DisconnectKind.UNKNOWN_SESSION_REQUEST)
                            SessionState.Disconnected(DisconnectKind.REJECTED)
                        else SessionState.Disconnected(general, text)
                    val kind = state.kind
                    Log.i(TAG, "Oturum kapandı: $kind ${state.detail.orEmpty()} $text")
                    closeNative()
                    if (kind == DisconnectKind.REGISTRATION_INVALID || kind == DisconnectKind.REMOTE_PLAY_DISABLED) {
                        // Kayıt geçersiz ya da Uzaktan Oynama kapalı: yeniden denemek aynı yere çıkar (eskiden sonsuza kadar "Yeniden bağlanılıyor…").
                        bump(false)
                        emit(SessionState.Disconnected(kind, text))
                        return@execute
                    }
                    scheduleReconnect(eventGeneration, state)
                }
            }
        }
    }

    /**
     * Bağlıyken saniyede bir bakılır: görüntü [PictureWatchdog.STALL_AFTER_MS]'den uzun süredir gelmiyorsa bağlantı açık
     * görünse de oturum kapatılıp yeniden kurulur (bkz. [PictureWatchdog]).
     */
    private fun scheduleWatch(sessionGeneration: Int) {
        try {
            queue.schedule({
                if (nativeGeneration != sessionGeneration || native == 0L || !isCurrent(sessionGeneration)) return@schedule
                val gap = watchdog.stalledMs(SystemClock.elapsedRealtime())
                if (gap == null) {
                    scheduleWatch(sessionGeneration)
                    return@schedule
                }
                val next = watchdog.stalled()
                val streak = watchdog.noPictureStreak
                val text = "PS5: ${gap / 1000} sn'dir görüntü yok (bağlantı açık, kare $framesReceived, " +
                    "art arda görüntüsüz oturum $streak): ${next.name}"
                Log.w(TAG, text)
                Backend.breadcrumb(text)
                Telemetry.event("no_picture", "next" to next.name.lowercase(), "streak" to streak, "frames" to framesReceived)
                closeNative()
                if (next == PictureWatchdog.Next.GIVE_UP) {
                    // İki çözücü türüyle de görüntü gelmedi: sonsuz "yeniden bağlanılıyor" döngüsü yerine dur ve söyle.
                    bump(false)
                    Backend.recordError(NoPictureException(text))
                    emit(SessionState.Disconnected(DisconnectKind.NO_PICTURE, PictureWatchdog.REASON))
                    return@schedule
                }
                scheduleReconnect(sessionGeneration, SessionState.Disconnected(DisconnectKind.OTHER, PictureWatchdog.REASON))
            }, 1, TimeUnit.SECONDS)
        } catch (error: java.util.concurrent.RejectedExecutionException) {
            // Oturum kapatıldı (dispose); bakacak bir şey yok.
        }
    }

    private fun scheduleReconnect(current: Int, state: SessionState.Disconnected) {
        // Ağ hatasıyla düştüyse ve PS5 aramaya da yanıt vermediyse neden "bulunamadı"dır.
        val classified = if (!searchAnswered && (state.kind == DisconnectKind.NETWORK || state.kind == DisconnectKind.OTHER))
            SessionState.Disconnected(DisconnectKind.NOT_FOUND, console.host) else state
        emit(classified)
        if (!isCurrent(current)) return
        queue.schedule({ connect(current) }, policy.nextDelaySeconds().toLong(), TimeUnit.SECONDS)
    }

    private fun emit(state: SessionState) {
        try {
            onState(state)
        } catch (error: RuntimeException) {
            Log.e(TAG, "state handler", error)
        }
    }
}

/** Nino: yerel çözücünün Y düzleminin arkasına koyduğu yarım çözünürlüklü renk (NV12); yoksa ya da sığmıyorsa null. */
internal fun nativeChroma(buffer: java.nio.ByteBuffer, width: Int, height: Int, present: Boolean): Chroma? {
    val cw = width / 2
    val ch = height / 2
    val offset = width * height
    if (!present || cw <= 0 || ch <= 0 || buffer.capacity() < offset + cw * ch * 2) return null
    val u = buffer.duplicate().apply { position(offset) }.slice()
    val v = buffer.duplicate().apply { position(offset + 1) }.slice()
    return Chroma(u, v, cw, ch, cw * 2, 2)
}
