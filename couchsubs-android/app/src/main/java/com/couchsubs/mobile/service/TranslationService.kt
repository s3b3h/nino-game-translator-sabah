// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import com.couchsubs.mobile.BuildConfig
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.account.Telemetry
import com.couchsubs.mobile.capture.CaptureCards
import com.couchsubs.mobile.core.CropRegion
import com.couchsubs.mobile.core.GamePackLibrary
import com.couchsubs.mobile.core.NinoPool
import com.couchsubs.mobile.core.PackLookup
import com.couchsubs.mobile.core.TargetAwareTranslator
import com.couchsubs.mobile.core.TargetLanguage
import com.couchsubs.mobile.core.SubtitleEvent
import com.couchsubs.mobile.core.SubtitleLayout
import com.couchsubs.mobile.core.SubtitlePipeline
import com.couchsubs.mobile.core.SubtitleServer
import com.couchsubs.mobile.core.TextTranslator
import com.couchsubs.mobile.ocr.RegionPixels
import com.couchsubs.mobile.ocr.SubtitleReader
import com.couchsubs.mobile.remoteplay.DisconnectKind
import com.couchsubs.mobile.remoteplay.FrameSource
import com.couchsubs.mobile.remoteplay.FrameSourceFactory
import com.couchsubs.mobile.remoteplay.RegisteredConsole
import com.couchsubs.mobile.remoteplay.FrameSources
import com.couchsubs.mobile.remoteplay.NativeBridge
import com.couchsubs.mobile.remoteplay.SessionState
import com.couchsubs.mobile.remoteplay.StreamSession
import com.couchsubs.mobile.settings.AppSettings
import com.couchsubs.mobile.settings.EngineChoice
import com.couchsubs.mobile.settings.SubtitleTarget
import com.couchsubs.mobile.translation.AiModel
import com.couchsubs.mobile.translation.AiProvider
import com.couchsubs.mobile.translation.AiTranslator
import com.couchsubs.mobile.translation.DeepLTranslator
import com.couchsubs.mobile.translation.MlKitTranslator
import com.couchsubs.mobile.ui.MainActivity
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Çeviri sürerken çalışan ön plan hizmeti (kalıcı bildirimle): PS5 oturumu → kare → yazı tanıma → paket/çeviri →
 * SSE sunucusu (TV) ve telefon ekranı. Ekran kapansa ya da uygulama arka plana geçse de okuma sürer.
 */
class TranslationService : Service() {
    /** Nino: telefon altyazı ekranındaki satır süresi dolunca kalkar (bkz. [PhoneLine]). */
    private val lineHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val lineExpiry = Any()

    private fun showOnPhone(event: SubtitleEvent) {
        lineHandler.removeCallbacksAndMessages(lineExpiry)
        if (event is SubtitleEvent.Subtitle) {
            LiveState.update { it.copy(current = event.text) }
            val wait = com.couchsubs.mobile.core.PhoneLine.visibleMs(event.text, event.durationMs)
            lineHandler.postAtTime({ LiveState.update { it.copy(current = "") } }, lineExpiry,
                android.os.SystemClock.uptimeMillis() + wait)
        } else {
            LiveState.update { it.copy(current = "") }
        }
    }

    companion object {
        private const val TAG = "CouchSubsService"
        /** Ücretsiz modelin indirilmesi kaç kez denenir (aralar 10, 20, 30… sn). */
        private const val MODEL_ATTEMPTS = 6
        private const val CHANNEL = "translation"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_STOP = "com.couchsubs.mobile.STOP"
        /** Yazı tanıma en çok saniyede bu kadar kare okur (telefon ısınmasın; altyazı için yeterli). */
        private const val MAX_READS_PER_SECOND = 5

        fun start(context: Context) {
            context.startForegroundService(Intent(context, TranslationService::class.java))
        }

        fun stop(context: Context) {
            context.startService(Intent(context, TranslationService::class.java).setAction(ACTION_STOP))
        }
    }

    private lateinit var settings: AppSettings
    @Volatile private var session: FrameSource? = null
    @Volatile private var server: SubtitleServer? = null
    @Volatile private var pipeline: SubtitlePipeline? = null
    @Volatile private var reader: SubtitleReader? = null
    @Volatile private var pool: NinoPool? = null
    private var poolNetwork: android.net.ConnectivityManager.NetworkCallback? = null
    @Volatile private var freeTranslator: MlKitTranslator? = null
    @Volatile private var packs: GamePackLibrary? = null
    private val ocr = Executors.newSingleThreadExecutor { Thread(it, "CouchSubs OCR").apply { isDaemon = true } }
    private val background = Executors.newSingleThreadScheduledExecutor { Thread(it, "CouchSubs background").apply { isDaemon = true } }
    private val reading = AtomicBoolean(false)
    private var lastRead = 0L
    private var lastSignature = 0L
    private var lastReading = com.couchsubs.mobile.core.Reading.Empty
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private val region = CropRegion()
    private val lifecycle = Any()
    @Volatile private var destroyed = false
    private var begun = false
    /**
     * Nino: bu oturumda görüntü yakalama kartından gelir (Ayarlar › Görüntü Kaynağı). Debug yapısının demo klibi
     * kuruluysa o önceliklidir. Oturum başında bir kez belirlenir.
     */
    private var captureCard = false
    /** Nino: bu oturumda görüntü Xbox ev yayınından gelir (Ayarlar › Görüntü Kaynağı › Xbox). */
    private var xbox = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        settings = AppSettings(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!begun) {
            captureCard = settings.usesCaptureCard && FrameSources.replacement == null
            xbox = settings.usesXbox && FrameSources.replacement == null
        }
        startInForeground()
        if (!begun) {
            begun = true
            begin()
        }
        return START_NOT_STICKY
    }

    private fun startInForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.channel_translation), NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, TranslationService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(getString(if (captureCard) R.string.capture_notification_text else if (xbox) R.string.xbox_notification_text else R.string.notification_text))
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, getString(R.string.stop), stop).build())
            .build()
        // Android 14+: ağdaki cihazlarla (PS5, TV) sürekli konuşan hizmet "connectedDevice" türündedir.
        // Nino: yakalama kartında kamera da kullanılır ("camera" türü). Tür yalnız izin verilmişse eklenir; izin yokken
        // Android 14+ hizmeti başlatmaz (SecurityException) ve PS5 yolu da etkilenmesin.
        val cameraType = captureCard && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            checkSelfPermission(android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (cameraType)
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
        else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        else startForeground(NOTIFICATION_ID, notification)
    }

    private fun begin() {
        val console = settings.console
        val accountId = settings.accountId
        // Yerine geçen kaynak: debug yapısında kayıtlı klip (Play görüntüleri için) ya da Nino'da yakalama kartı.
        // İkisinde de PSN hesabı, PS5 eşlemesi ve PS5 kitaplığı gerekmez.
        val replacement = FrameSources.replacement ?: if (captureCard) CaptureCards.factory else null
        // Nino: Xbox'ta PSN ve Remote Play kitaplığı gerekmez; Microsoft girişi ve seçili konsol gerekir.
        if (xbox && replacement == null && !settings.xboxReady) {
            LiveState.update { it.copy(running = false, error = getString(R.string.xbox_error_not_ready)) }
            stopSelf()
            return
        }
        if (replacement == null && !xbox && (console == null || accountId == null)) {
            LiveState.update { it.copy(running = false, error = getString(R.string.error_not_paired)) }
            stopSelf()
            return
        }
        if (replacement == null && !xbox && !NativeBridge.available) {
            LiveState.update { it.copy(running = false, error = getString(R.string.error_native)) }
            stopSelf()
            return
        }
        acquireLocks()
        startedAt = System.currentTimeMillis()
        LiveState.update { LiveStatus(running = true, phase = getString(R.string.phase_preparing), startedAt = startedAt, engineLabel = engineLabel()) }
        LiveState.health.sessionStarted()
        Telemetry.event(Telemetry.SESSION_START, "target" to settings.target.name.lowercase(), "engine" to settings.engine.name.lowercase(),
            "packs" to settings.packsEnabled, "source" to if (captureCard) "capture_card" else if (xbox) "xbox" else "remote_play")
        // Paketlerin açılması, çeviri modeli ve sunucu kurulumu ana iş parçacığında yapılırsa zayıf telefonda
        // "CouchSubs yanıt vermiyor" uyarısı çıkar; kurulum kendi iş parçacığında yapılır.
        Thread({
            try {
                setup(console, accountId, replacement)
            } catch (error: Exception) {
                // Kurulum sürerken durdurulduysa (zamanlayıcı kapanmış olur) yalnız kurulanlar kapatılır.
                if (destroyed) releaseParts()
                else {
                    Log.e(TAG, "setup", error)
                    LiveState.update { it.copy(error = getString(R.string.error_native)) }
                    stopSelf()
                }
            }
        }, "CouchSubs start").start()
    }

    private fun setup(console: RegisteredConsole?, accountId: ByteArray?, replacement: FrameSourceFactory?) {
        // Paketler ücretsiz: uygulamayla gelenler ve sunucudan inmiş güncel sürümler. Ayardan kapatılırsa aranmaz.
        val library = Services.packLibrary(this)
        packs = library
        // Nino: çeviri dili (Türkçe ya da Arapça). Zaten hedef dilde olan yazı (ör. Arapça menüler) çevirmene gitmez.
        val target = settings.targetLanguage
        val turkish = TargetLanguage.isTurkish(target)
        val free = MlKitTranslator(target).also { freeTranslator = it }
        val translator = TargetAwareTranslator(onlineTranslator(free, target) ?: free, target)
        val subtitleServer = SubtitleServer().also { server = it }
        subtitleServer.sendsToTv = settings.target == SubtitleTarget.TV
        subtitleServer.onClientsChanged = { count ->
            val before = LiveState.status.value.connectedTvs
            LiveState.update { it.copy(connectedTvs = count) }
            if (before == 0 && count > 0) Telemetry.event(Telemetry.TV_CONNECTED, "count" to count)
        }
        subtitleServer.onEvent = { event -> lineHandler.post { showOnPhone(event) } }
        try {
            subtitleServer.start()
            subtitleServer.sendStyle(settings.style)
        } catch (error: Exception) {
            Log.e(TAG, "SSE server", error)
            LiveState.update { it.copy(error = getString(R.string.error_port)) }
        }

        // Klipten okunan satırlar ortak havuza gönderilmez (oyun yazısı değildir). Yakalama kartı gerçek oyundur: gönderilir.
        // Nino'nun kendi havuzu: satırlar telefonda kuyrukta bekler, sunucu onaylayınca silinir. CouchSubs'tan kalan
        // line-pool.json kuyruğu bir kez aktarılır.
        val linePool = NinoPool(File(filesDir, "pool"), BuildConfig.VERSION_NAME,
            enabled = settings.sharePool && FrameSources.replacement == null, legacyFile = File(filesDir, "line-pool.json"))
        pool = linePool
        val packTitles = library.infos.associate { it.id to it.title }
        reader = SubtitleReader()
        // Nino: oyunların altyazı yeri öğrenilir (oyun, gösterilen satırın paketinden anlaşılır).
        val layout = SubtitleLayout(File(filesDir, "subtitle-layout.json"))
        var game = "genel"
        pipeline = SubtitlePipeline(translator, subtitleServer).apply {
            hudTop = layout.hudTop(game)
            // Oyun paketleri Türkçedir: yalnız Türkçe çeviride kullanılır.
            packLookup = { text -> if (turkish && settings.packsEnabled) PackLookup.match(library, text) else null }
            onPackMissed = { text -> linePool.offer(text, game.takeIf { it != "genel" }) }
            onPairShown = { pair ->
                pair.packId?.let { game = it }
                pair.box?.let { box ->
                    layout.record(box, game)
                    hudTop = layout.hudTop(game)
                }
                LiveState.shown(pair, pair.packId?.let { packTitles[it] ?: it })
                LiveState.health.line(pair.translationMs)
                // Paket başına oturumda bir kez (her satırda olay göndermeyelim); toplam sayı oturum sonunda gider.
                pair.packId?.let { id -> if (packsUsed.add(id)) Telemetry.event(Telemetry.PACK_HIT, "pack" to id) }
            }
            onTranslationResult = { error ->
                LiveState.update { it.copy(error = error?.let { getString(R.string.error_translation) }) }
            }
        }
        background.scheduleWithFixedDelay({ linePool.flush() }, 5_000L, NinoPool.TICK_INTERVAL_MS, TimeUnit.MILLISECONDS)
        // Ağ gelince bekleyen parçalar hemen denenir.
        poolNetwork = object : android.net.ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: android.net.Network) {
                try { background.execute { linePool.networkAvailable() } } catch (error: java.util.concurrent.RejectedExecutionException) { }
            }
        }.also { callback ->
            try { getSystemService(android.net.ConnectivityManager::class.java)?.registerDefaultNetworkCallback(callback) }
            catch (error: Exception) { Log.w(TAG, "havuz ağ izleme", error) }
        }
        // Ücretsiz modelin ilk indirilmesi (yaklaşık 30 MB); oyun paketleri beklemeden çalışır.
        // Nino: ilk deneme ağ henüz hazır değilken düşebilir; birkaç kez yeniden denenir, inince uyarı kalkar.
        val modelError = getString(R.string.error_model)
        fun prepareModel(attempt: Int) {
            if (freeTranslator !== free) return
            try {
                free.prepare()
                LiveState.update { if (it.error == modelError) it.copy(error = null) else it }
            } catch (error: Exception) {
                Log.w(TAG, "ML Kit model (deneme $attempt)", error)
                if (attempt >= 2) LiveState.update { it.copy(error = modelError) }
                if (attempt < MODEL_ATTEMPTS) try {
                    background.schedule({ prepareModel(attempt + 1) }, attempt * 10L, java.util.concurrent.TimeUnit.SECONDS)
                } catch (stopped: java.util.concurrent.RejectedExecutionException) { }
            }
        }
        background.execute { prepareModel(1) }

        val onFrame: (android.media.Image) -> Unit = { image ->
            val now = System.currentTimeMillis()
            if (BuildConfig.DEBUG && image.format != android.graphics.ImageFormat.PRIVATE) debugRawFrame(image, now)
            if (!reading.get() && now - lastRead >= 1000 / MAX_READS_PER_SECOND) {
                SubtitleReader.copyRegion(image, region)?.let { pixels ->
                    lastRead = now
                    reading.set(true)
                    ocr.execute { read(pixels) }
                }
            }
        }
        // Nino: Xbox kareleri android.media.Image değildir (WebRTC I420); yalnız parlaklık düzlemi gelir.
        val onLuma = com.couchsubs.mobile.xbox.LumaSink { buffer, rowStride, width, height ->
            val now = System.currentTimeMillis()
            if (!reading.get() && now - lastRead >= 1000 / MAX_READS_PER_SECOND) {
                SubtitleReader.copyLuma(buffer, rowStride, 1, 0, 0, width, height, region)?.let { pixels ->
                    lastRead = now
                    reading.set(true)
                    ocr.execute { read(pixels) }
                }
            }
        }
        val onState: (SessionState) -> Unit = { state ->
            when (state) {
                SessionState.Connecting -> LiveState.health.connecting()
                SessionState.Streaming -> LiveState.health.streaming()
                is SessionState.Disconnected -> LiveState.health.disconnected(if (state.kind == DisconnectKind.STOPPED) null else state.kind.name)
            }
            // Nino: yakalama kartının sorunları (kart yok, izin yok, görüntü siyah) ana ekranda uyarı olarak da görünür;
            // görüntü gelince uyarı kalkar.
            val cardProblem = (state as? SessionState.Disconnected)?.kind in CARD_PROBLEMS
            val phase = describe(state)
            LiveState.update {
                it.copy(phase = phase, streaming = state == SessionState.Streaming,
                    error = if (cardProblem) phase else if (it.error in cardMessages) null else it.error)
            }
        }
        val xboxConsole = settings.xboxConsole
        val source = replacement?.create(this, onFrame, onState)
            ?: if (xbox && xboxConsole != null) com.couchsubs.mobile.xbox.XboxStreamSession(this, com.couchsubs.mobile.xbox.XboxAccount(settings), xboxConsole, onLuma, onState)
            else StreamSession(console!!, accountId!!, onFrame, onState, onConsoleMoved = { moved -> settings.console = moved })
        synchronized(lifecycle) {
            // Kurulum sürerken durdurulduysa (onDestroy çalıştı) açılan bağlantı başlatılmaz.
            if (destroyed) {
                source.dispose()
                releaseParts()
                return
            }
            session = source
            source.start()
        }
        background.scheduleWithFixedDelay({
            session?.let { s ->
                LiveState.health.frameTotal(s.framesReceived)
                LiveState.update { it.copy(framesReceived = s.framesReceived) }
            }
        }, 2, 2, TimeUnit.SECONDS)
    }

    private fun read(pixels: RegionPixels) {
        try {
            // Bölge değişmediyse (aynı altyazı duruyor) yeniden okunmaz; son okuma hattı yine besler (kararlılık ve
            // silme saate bağlıdır, Windows'taki ReadScheduler gibi).
            val current = pipeline ?: return
            val result = if (pixels.signature == lastSignature) lastReading else reader?.read(pixels) ?: return
            if (BuildConfig.DEBUG) debugDump(pixels, result)
            lastSignature = pixels.signature
            lastReading = result
            current.process(result, region.box)
        } catch (error: Exception) {
            Log.w(TAG, "OCR", error)
        } finally {
            reading.set(false)
        }
    }

    private var lastDump = 0L
    private var lastRawDump = 0L

    /** Yalnız geliştirme sürümü: ham Y düzlemini ve biçim bilgisini cache/frame-y.bin, frame-meta.txt olarak saklar. */
    private fun debugRawFrame(image: android.media.Image, now: Long) {
        if (now - lastRawDump < 5000) return
        lastRawDump = now
        try {
            val planes = image.planes
            val y = planes[0].buffer.duplicate().apply { rewind() }
            val bytes = ByteArray(y.remaining()).also { y.get(it) }
            File(cacheDir, "frame-y.bin").writeBytes(bytes)
            val meta = buildString {
                append("format=${image.format} size=${image.width}x${image.height} crop=${image.cropRect}\n")
                planes.forEachIndexed { i, plane -> append("plane$i rowStride=${plane.rowStride} pixelStride=${plane.pixelStride} bytes=${plane.buffer.capacity()}\n") }
            }
            File(cacheDir, "frame-meta.txt").writeText(meta)
            Log.d(TAG, "raw frame: " + meta.replace('\n', ' '))
        } catch (error: Exception) {
            Log.w(TAG, "raw dump", error)
        }
    }

    /** Yalnız geliştirme sürümü: okunan bölgeyi birkaç saniyede bir cache/last-region.jpg olarak saklar, okunanı yazar. */
    private fun debugDump(pixels: RegionPixels, result: com.couchsubs.mobile.core.Reading) {
        val now = System.currentTimeMillis()
        if (now - lastDump < 3000) return
        lastDump = now
        try {
            val image = android.graphics.YuvImage(pixels.nv21, android.graphics.ImageFormat.NV21, pixels.width, pixels.height, null)
            File(cacheDir, "last-region.jpg").outputStream().use { image.compressToJpeg(android.graphics.Rect(0, 0, pixels.width, pixels.height), 80, it) }
            Log.d(TAG, "OCR ${pixels.width}x${pixels.height}: " + result.lines.joinToString(" | ") { it.text })
        } catch (error: Exception) {
            Log.w(TAG, "debug dump", error)
        }
    }

    /** Çevrimiçi motor seçilip anahtarı girildiyse o, hatada yerel motor; yoksa null. */
    private fun onlineTranslator(free: TextTranslator, target: String): TextTranslator? {
        val engine = settings.engine
        val key = settings.apiKey(engine)?.takeIf { it.isNotBlank() } ?: return null
        return when (engine) {
            EngineChoice.FREE -> null
            EngineChoice.DEEPL -> DeepLTranslator(key, free, target = target)
            else -> {
                val provider = when (engine) {
                    EngineChoice.GEMINI -> AiProvider.GEMINI
                    EngineChoice.OPENAI -> AiProvider.OPENAI
                    else -> AiProvider.CLAUDE
                }
                val models = aiModels()[provider.id].orEmpty()
                val model = models.firstOrNull { it.id == settings.aiModel } ?: models.firstOrNull() ?: return null
                AiTranslator(provider, key, model, free, target = target)
            }
        }
    }

    private fun aiModels(): Map<String, List<AiModel>> = try {
        AiModel.parse(assets.open("ai-models.json").use { String(it.readBytes(), Charsets.UTF_8) })
    } catch (error: Exception) {
        emptyMap()
    }

    private val CARD_PROBLEMS = setOf(DisconnectKind.NO_CAPTURE_CARD, DisconnectKind.NO_CAMERA_PERMISSION, DisconnectKind.BLACK_PICTURE,
        DisconnectKind.XBOX_SIGNED_OUT)
    private val cardMessages by lazy {
        setOf(getString(R.string.capture_not_found), getString(R.string.capture_no_permission), getString(R.string.capture_black),
            getString(R.string.xbox_phase_signed_out))
    }

    private fun describe(state: SessionState): String = when (state) {
        SessionState.Connecting -> getString(if (captureCard) R.string.capture_phase_opening else if (xbox) R.string.xbox_phase_connecting else R.string.phase_connecting)
        SessionState.Streaming -> getString(R.string.phase_streaming)
        is SessionState.Disconnected -> when (state.kind) {
            DisconnectKind.NO_CAPTURE_CARD -> getString(R.string.capture_not_found)
            DisconnectKind.NO_CAMERA_PERMISSION -> getString(R.string.capture_no_permission)
            DisconnectKind.BLACK_PICTURE -> getString(R.string.capture_black)
            DisconnectKind.IN_USE -> getString(R.string.phase_in_use)
            DisconnectKind.NOT_FOUND -> getString(R.string.phase_not_found)
            DisconnectKind.CONSOLE_ASLEEP -> getString(R.string.phase_asleep)
            DisconnectKind.LOGIN_PASSCODE -> getString(R.string.phase_passcode)
            DisconnectKind.REFUSED -> getString(R.string.phase_refused)
            DisconnectKind.XBOX_SIGNED_OUT -> getString(R.string.xbox_phase_signed_out)
            DisconnectKind.XBOX_UNREACHABLE -> getString(R.string.xbox_phase_unreachable)
            else -> getString(R.string.phase_reconnecting)
        }
    }

    private fun acquireLocks() {
        // Ekran kapalıyken de Wi-Fi uyumasın ve işlemci kareleri işlemeye devam etsin.
        wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "CouchSubs:translate").apply { acquire() }
        @Suppress("DEPRECATION")
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
        wifiLock = (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager).createWifiLock(mode, "CouchSubs").apply { acquire() }
    }

    private val packsUsed = java.util.Collections.synchronizedSet(mutableSetOf<String>())
    private var startedAt = 0L

    /** Ana ekrandaki "Çeviri · DeepL" karosu ve satırlardaki motor hapı için. */
    private fun engineLabel(): String = when (settings.engine) {
        EngineChoice.FREE -> getString(R.string.engine_free_short)
        EngineChoice.DEEPL -> "DeepL"
        EngineChoice.GEMINI -> "Gemini"
        EngineChoice.OPENAI -> "OpenAI"
        EngineChoice.CLAUDE -> "Claude"
    }

    /** Kurulan parçaları kapatır; onDestroy'dan ve hizmet kurulum bitmeden durdurulduysa kurulum iş parçacığından çağrılır. */
    private fun releaseParts() = synchronized(lifecycle) {
        session?.dispose()
        session = null
        pipeline?.reset()
        pipeline?.shutdown()
        pipeline = null
        server?.stop()
        server = null
        reader?.close()
        reader = null
        freeTranslator?.close()
        freeTranslator = null
        poolNetwork?.let { callback ->
            try { getSystemService(android.net.ConnectivityManager::class.java)?.unregisterNetworkCallback(callback) } catch (error: Exception) { }
        }
        poolNetwork = null
        // Satırlar zaten diskte; burada yalnız gönderme zamanı gelmiş olanlar denenir.
        pool?.let { linePool -> Thread { linePool.flush() }.start() }
        pool = null
    }

    override fun onDestroy() {
        synchronized(lifecycle) { destroyed = true }
        if (startedAt > 0) settings.lastSessionMs = System.currentTimeMillis() - startedAt
        if (startedAt > 0) Telemetry.event(Telemetry.SESSION_STOP, "seconds" to (System.currentTimeMillis() - startedAt) / 1000,
            "pack_lines" to (pipeline?.packHits ?: 0), "lines" to LiveState.status.value.recent.size)
        releaseParts()
        LiveState.health.sessionEnded()
        background.shutdownNow()
        ocr.shutdownNow()
        wakeLock?.takeIf { it.isHeld }?.release()
        wifiLock?.takeIf { it.isHeld }?.release()
        lineHandler.removeCallbacksAndMessages(lineExpiry)
        // Nino: yakalama kartı uyarısı oturumla birlikte kalkar (kaynak değişince eski uyarı kalmasın).
        LiveState.update { it.copy(running = false, phase = "", current = "", streaming = false,
            error = if (it.error in cardMessages) null else it.error) }
        super.onDestroy()
    }
}
