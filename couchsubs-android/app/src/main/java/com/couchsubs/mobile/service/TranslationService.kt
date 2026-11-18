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
import com.couchsubs.mobile.account.Backend
import com.couchsubs.mobile.account.Telemetry
import com.couchsubs.mobile.capture.CaptureCards
import com.couchsubs.mobile.core.CropRegion
import com.couchsubs.mobile.core.active
import com.couchsubs.mobile.core.GamePackLibrary
import com.couchsubs.mobile.core.GameSense
import com.couchsubs.mobile.core.NinoPool
import com.couchsubs.mobile.core.PackMatch
import com.couchsubs.mobile.core.PoolContext
import com.couchsubs.mobile.core.TranslationPool
import com.couchsubs.mobile.packs.PackStore
import com.couchsubs.mobile.core.PackLookup
import com.couchsubs.mobile.core.ScreenTranslation
import com.couchsubs.mobile.core.SubtitleLayout
import com.couchsubs.mobile.core.TargetAwareTranslator
import com.couchsubs.mobile.core.TargetLanguage
import com.couchsubs.mobile.core.SubtitleEvent
import com.couchsubs.mobile.core.SubtitlePipeline
import com.couchsubs.mobile.core.SubtitleServer
import com.couchsubs.mobile.core.TextTranslator
import com.couchsubs.mobile.ocr.RegionPixels
import com.couchsubs.mobile.ocr.SubtitleReader
import com.couchsubs.mobile.remoteplay.ConsoleDiscovery
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
import com.couchsubs.mobile.translation.Glossary
import com.couchsubs.mobile.translation.MlKitTranslator
import com.couchsubs.mobile.translation.TranslationCache
import com.couchsubs.mobile.ui.MainActivity
import com.couchsubs.mobile.xbox.XboxError
import com.couchsubs.mobile.xbox.XboxStreamSession
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Çeviri sürerken çalışan ön plan hizmeti (kalıcı bildirimle): PS5 oturumu → kare → yazı tanıma → paket/çeviri →
 * SSE sunucusu (TV) ve telefon ekranı. Ekran kapansa ya da uygulama arka plana geçse de okuma sürer.
 */
class TranslationService : Service() {
    /** Nino: telefon altyazı ekranındaki satır süresi dolunca kalkar (bkz. [com.couchsubs.mobile.core.PhoneLine]). */
    private val lineHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val lineExpiry = Any()

    private fun showOnPhone(event: SubtitleEvent) {
        // Ek alan ve "ekranı çevir" olayları altyazı satırının süresine dokunmaz.
        val line = event is SubtitleEvent.Subtitle || event == SubtitleEvent.Cleared
        if (line) lineHandler.removeCallbacksAndMessages(lineExpiry)
        LiveState.update { it.phoneEvent(event) }
        if (event is SubtitleEvent.Subtitle) {
            val wait = com.couchsubs.mobile.core.PhoneLine.visibleMs(event.text, event.durationMs)
            lineHandler.postAtTime({ LiveState.update { it.copy(current = "") } }, lineExpiry,
                android.os.SystemClock.uptimeMillis() + wait)
        }
    }

    companion object {
        private const val TAG = "CouchSubsService"
        /** Değişmeyen bölgenin son okuması kaç kare yeniden kullanılır (Mac/iPhone/Windows ReadScheduler ile aynı). */
        private const val DEFAULT_MAX_REUSE = 20
        private const val FAST_MAX_REUSE = 2
        /** Ücretsiz modelin indirilmesi kaç kez denenir (aralar 10, 20, 30… sn). */
        private const val MODEL_ATTEMPTS = 6
        private const val CHANNEL = "translation"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_STOP = "com.couchsubs.mobile.STOP"
        /** Yazı tanıma en çok saniyede bu kadar kare okur (telefon ısınmasın; altyazı için yeterli). */
        private const val MAX_READS_PER_SECOND = 5
        /** PS5'e çalışan oyunun sorulma aralığı (ortak havuz). */
        private const val GAME_PROBE_MS = 2 * 60 * 1000L

        fun start(context: Context) {
            context.startForegroundService(Intent(context, TranslationService::class.java))
        }

        fun stop(context: Context) {
            context.startService(Intent(context, TranslationService::class.java).setAction(ACTION_STOP))
        }

        /** Çalışan hizmet ("ekranı çevir" düğmesi buraya gelir). */
        @Volatile private var current: TranslationService? = null

        /**
         * "Ekranı çevir": PS5'in şu anki karesinin tamamı bir kez okunur, yazı grupları tek istekte çevrilir; sonuçlar
         * telefonda ve TV'de yazının yerinde görünür. Çeviri sürerken ya da sonuçlar ekrandayken yeniden çağrılmak onları
         * kaldırır (Mac ⌥⌘T ve iPhone ile aynı). Çeviri çalışmıyorsa false.
         */
        fun translateScreen(): Boolean {
            val service = current ?: return false
            service.toggleScreen()
            return true
        }

        /** Çeviri sürerken açık altyazı sunucusu ("TV'de test et" için). */
        @Volatile private var liveServer: SubtitleServer? = null

        /**
         * Deneme altyazısı (iPhone'daki "Deneme altyazısı gönder"): TV'de ya da telefon ekranında yazının nasıl
         * göründüğü. Çeviri çalışmıyorsa (TV bağlı değil) false.
         */
        fun sendTestSubtitle(text: String): Boolean {
            val server = liveServer ?: return false
            server.sendSubtitle(text, 8000)
            return true
        }
    }

    private lateinit var settings: AppSettings
    @Volatile private var session: FrameSource? = null
    @Volatile private var server: SubtitleServer? = null
    @Volatile private var pipeline: SubtitlePipeline? = null
    @Volatile private var reader: SubtitleReader? = null
    @Volatile private var pool: NinoPool? = null
    private var poolNetwork: android.net.ConnectivityManager.NetworkCallback? = null
    /** Nino: sunucunun çeviri havuzu (bütün dillerde; ortak havuz açıkken). */
    @Volatile private var translations: TranslationPool? = null
    /** Havuza sorulan satırlar (sunucu o an çevirir); okuma iş parçacığını bekletmesin diye ayrı. */
    private val poolWork = Executors.newFixedThreadPool(2) { Thread(it, "Nino pool translate").apply { isDaemon = true } }
    /** Havuzun toplu indirmesi ve "buradayım" isteği (dakikada bir). */
    private val poolSync = Executors.newSingleThreadScheduledExecutor { Thread(it, "Nino pool sync").apply { isDaemon = true } }
    private val syncLock = Any()
    @Volatile private var syncTask: java.util.concurrent.ScheduledFuture<*>? = null
    @Volatile private var poolListener: android.content.SharedPreferences.OnSharedPreferenceChangeListener? = null
    private val poolContext = PoolContext()
    /** Nino: oyunu ekrandan tanıma zamanlaması (bkz. [identifyGameIfNeeded]). */
    private val gameCheck = com.couchsubs.mobile.core.ScreenGameCheck()
    private val identifyWork = Executors.newSingleThreadExecutor { Thread(it, "Nino identify").apply { isDaemon = true; priority = Thread.MIN_PRIORITY } }
    @Volatile private var freeTranslator: MlKitTranslator? = null
    @Volatile private var packs: GamePackLibrary? = null
    private val ocr = Executors.newSingleThreadExecutor { Thread(it, "CouchSubs OCR").apply { isDaemon = true } }
    private val background = Executors.newSingleThreadScheduledExecutor { Thread(it, "CouchSubs background").apply { isDaemon = true } }
    private val reading = AtomicBoolean(false)
    private var lastRead = 0L
    private var lastSignature = 0L
    private var lastReading = com.couchsubs.mobile.core.Reading.Empty
    private var lastOcrMs: Int? = null
    private var reusedReads = 0
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    /** Altyazı bölgesi ve ek alanlar (Ayarlar › Altyazı alanı); çeviri sürerken değişirse hemen yenisi okunur. */
    @Volatile private var region = CropRegion()
    @Volatile private var extraAreas: List<com.couchsubs.mobile.core.ExtraArea> = emptyList()
    @Volatile private var areasListener: android.content.SharedPreferences.OnSharedPreferenceChangeListener? = null
    /** Ek alanları ana altyazıdan ayrı ve seyrek (saniyede bir) okuyan; kendi okuyucusu ve iş parçacığı var. */
    @Volatile private var regionWatcher: com.couchsubs.mobile.core.RegionWatcher? = null
    @Volatile private var regionReader: SubtitleReader? = null
    private val regionWork = Executors.newSingleThreadExecutor { Thread(it, "CouchSubs extra areas").apply { isDaemon = true; priority = Thread.MIN_PRIORITY } }
    private val lifecycle = Any()
    @Volatile private var destroyed = false
    @Volatile private var streaming = false
    private var begun = false
    @Volatile private var styleListener: android.content.SharedPreferences.OnSharedPreferenceChangeListener? = null
    @Volatile private var targetListener: android.content.SharedPreferences.OnSharedPreferenceChangeListener? = null
    /**
     * Nino: bu oturumda görüntü yakalama kartından gelir (Ayarlar › Görüntü Kaynağı). Debug yapısının demo klibi
     * kuruluysa o önceliklidir. Oturum başında bir kez belirlenir.
     */
    private var captureCard = false
    /** Bu oturumda görüntü Xbox ev yayınından gelir (Ayarlar › Görüntü Kaynağı › Xbox). */
    private var xbox = false
    /** Nino: çeviri dili (Türkçe, Arapça, Hintçe…); oturum başında bir kez okunur. */
    private var target = "tr"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        settings = AppSettings(this)
        current = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!begun) {
            captureCard = settings.usesCaptureCard && FrameSources.replacement == null
            xbox = settings.xbox && FrameSources.replacement == null
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
        // Xbox (Beta): Microsoft girişi ve seçili Xbox yeter; PSN ve PS5 eşlemesi gerekmez.
        if (xbox && (settings.xboxConsole == null || !Services.xboxAuth.signedIn)) {
            LiveState.update { it.copy(running = false, error = getString(R.string.error_xbox_not_ready)) }
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
        settings.translating = true
        Backend.breadcrumb("çeviri: başlıyor (${settings.target.name}, ${settings.engine.name}, paketler ${settings.packsEnabled})")
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
            } catch (error: Throwable) {
                // Exception değil Throwable: bu iş parçacığında yakalanmayan hata (ör. OutOfMemoryError) bütün uygulamayı
                // kapatır, PS5 bağlantısı da kopar. Kurulum sürerken durdurulduysa (zamanlayıcı kapanmış olur) yalnız
                // kurulanlar kapatılır.
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
        val xboxConsole = if (xbox && replacement == null) settings.xboxConsole else null
        // Gerçek oyun mu (debug klibi değil): yakalama kartı da gerçek oyundur.
        val realGame = FrameSources.replacement == null
        // Paketler ücretsiz: uygulamayla gelenler ve sunucudan inmiş güncel sürümler. Ayardan kapatılırsa aranmaz.
        val library = Services.packLibrary(this)
        packs = library
        // Nino: çeviri dili (Türkçe, Arapça, Hintçe…). Zaten hedef dilde olan yazı (ör. Arapça menüler) çevirmene gitmez.
        target = settings.targetLanguage
        val turkish = TargetLanguage.isTurkish(target)
        // Terim sözlüğü ve kalıcı önbellek (iPhone ile aynı biçim): önceki oturumlarda çevrilen cümleler hemen gelir.
        // Sözlük İngilizce→Türkçedir: öbür dillerde kullanılmaz.
        val glossary = if (turkish) Glossary.load(this) else Glossary.Empty
        glossaryInUse = glossary
        val free = MlKitTranslator(cache(MlKitTranslator.ENGINE_ID), glossary, target).also { freeTranslator = it }
        val translator = TargetAwareTranslator(onlineTranslator(free) ?: free, target)
        val subtitleServer = SubtitleServer().also { server = it }
        subtitleServer.sendsToTv = settings.target == SubtitleTarget.TV
        subtitleServer.onClientsChanged = { count ->
            val before = LiveState.status.value.connectedTvs
            LiveState.update { it.copy(connectedTvs = count) }
            if (before == 0 && count > 0) Telemetry.event(Telemetry.TV_CONNECTED, "count" to count)
        }
        subtitleServer.onEvent = { event -> lineHandler.post { showOnPhone(event) } }
        // Çeviri sürerken Ayarlar'da yazı boyu ya da rengi değişirse TV hemen yeni görünüme geçer (iPhone ile aynı).
        styleListener = settings.onStyleChanged { server?.sendStyle(settings.style) }
        // Çeviri sürerken hedef TV'ye (ya da telefona) çevrilirse altyazı hemen oraya gider (iPhone ile aynı).
        targetListener = settings.onTargetChanged { server?.sendsToTv = settings.target == SubtitleTarget.TV }
        region = settings.region
        extraAreas = settings.extraAreas.active()
        areasListener = settings.onAreasChanged {
            region = settings.region
            extraAreas = settings.extraAreas.active()
        }
        try {
            subtitleServer.start()
            subtitleServer.sendStyle(settings.style)
            liveServer = subtitleServer
        } catch (error: Exception) {
            Log.e(TAG, "SSE server", error)
            LiveState.update { it.copy(error = getString(R.string.error_port)) }
        }

        // Klipten okunan satırlar ortak havuza gönderilmez (oyun yazısı değildir). Yakalama kartı gerçek oyundur: gönderilir.
        // Nino'nun kendi havuzu: satırlar telefonda kuyrukta bekler, sunucu onaylayınca silinir. CouchSubs'tan kalan
        // line-pool.json kuyruğu bir kez aktarılır. Oyun paketleri ve havuz Türkçedir: öbür dillerde satır gönderilmez.
        val linePool = NinoPool(File(filesDir, "pool"), BuildConfig.VERSION_NAME,
            enabled = settings.sharePool && realGame, legacyFile = File(filesDir, "line-pool.json"))
        pool = linePool
        // Nino: sunucunun çeviri havuzu bütün çeviri dillerinde çalışır (paketlerden sonra, cihaz çevirisinden önce).
        // Klipte kullanılmaz (oyun yazısı değildir; satırlar sunucuya gitmesin).
        // Adres havuz klasöründeki endpoint.txt'den (deneme sunucusu) ya da canlı sunucudan, NinoPool ile aynı.
        val translationPool = TranslationPool(File(filesDir, "translation-pool"), NinoPool.configuredEndpoint(File(filesDir, "pool")),
            app = BuildConfig.VERSION_NAME, language = target, enabled = settings.sharePool && realGame)
        translations = translationPool
        // Havuza giden satırın oyunu: PS5'in bildirdiği / seçilen oyun (PlayedGame), yoksa son eşleşen paket.
        var playedGame: String? = null
        // Paketler burada açılır (ilk altyazı beklemesin); kapalıysa hiç açılmaz. Bellek yetmezse paketsiz sürülür:
        // çeviri motoru çalışır, uygulama kapanmaz ve PS5 bağlantısı kopmaz.
        var packTitles = if (!settings.packsEnabled) null else try {
            library.infos.associate { it.id to it.title }
        } catch (error: OutOfMemoryError) {
            Log.e(TAG, "packs", error)
            null
        }
        Backend.breadcrumb("çeviri: paketler ${packTitles?.size ?: "yok"}")
        // Ayarlardan paket içe aktarılınca ya da silinince bu oturumun paketleri hemen yeniden okunur.
        Services.onLocalPacksChanged = {
            try {
                library.reload()
                if (packTitles != null) packTitles = library.infos.associate { it.id to it.title }
            } catch (error: OutOfMemoryError) {
                Log.e(TAG, "packs reload", error)
            }
        }
        reader = SubtitleReader()
        // Nino: oyunların altyazı yeri öğrenilir (oyun, gösterilen satırın paketinden anlaşılır).
        val layout = SubtitleLayout(File(filesDir, "subtitle-layout.json"))
        var game = "genel"
        pipeline = SubtitlePipeline(translator, subtitleServer).apply {
            hudTop = layout.hudTop(game)
            // Yarım ya da bozuk okuma hemen çevrilmez; aynı satırın en iyi okuması çevrilir (Windows ve iPhone ile aynı).
            holdReadings = true
            // Oyun paketleri Türkçedir: yalnız Türkçe çeviride kullanılır.
            // Önce paket (yalnız Türkçe), sonra havuz (bütün diller; havuz kapalıysa boştur), en son motor.
            packLookup = { text ->
                (if (turkish && packTitles != null && settings.packsEnabled) PackLookup.match(library, text) else null)
                    ?: translationPool.store.match(text)?.let { PackMatch(it, pooled = true) }
            }
            showSpeakerNames = { settings.showSpeakerNames }
            onPackMissed = { text ->
                val played = playedGame ?: game.takeIf { it != "genel" }
                if (turkish) linePool.offer(text, played)
                if (translationPool.isEnabled) {
                    val context = poolContext.add(text)
                    // Sunucu o an çevirir (Claude); satır hâlâ ekrandaysa cihazın çevirisinin yerine konur.
                    try {
                        poolWork.execute {
                            translationPool.translate(text, context, played)?.let { better -> pipeline?.upgrade(text, better) }
                        }
                    } catch (stopped: java.util.concurrent.RejectedExecutionException) { }
                }
            }
            onPairUpgraded = { pair -> LiveState.upgraded(pair) }
            onPairShown = { pair ->
                pair.packId?.let { game = it }
                pair.box?.let { box ->
                    layout.record(box, game)
                    hudTop = layout.hudTop(game)
                }
                LiveState.shown(pair, pair.packId?.let { packTitles?.get(it) ?: it })
                LiveState.health.line(pair.translationMs?.toLong())
                if (realGame) PlayedGame.noteLine(pair.origin == "paket", library)
                Services.addToHistory(pair.source, pair.translation,
                    if (pair.origin == "paket") com.couchsubs.mobile.core.SubtitleHistory.PACK else com.couchsubs.mobile.core.SubtitleHistory.ENGINE)
                // Paket başına oturumda bir kez (her satırda olay göndermeyelim); toplam sayı oturum sonunda gider.
                pair.packId?.let { id -> if (packsUsed.add(id)) Telemetry.event(Telemetry.PACK_HIT, "pack" to id) }
            }
            onTranslationResult = { error ->
                LiveState.update { it.copy(error = error?.let { getString(R.string.error_translation) }) }
            }
        }
        // Ek alanlar aynı paketlerle ve aynı motorla (ayrı bir örnekle; altyazının bağlamına karışmasın) çevrilir; satırları
        // ortak havuza önerilmez (arayüz yazıları havuzu kirletmesin). Mac ve iPhone ile aynı.
        val areaReader = SubtitleReader().also { regionReader = it }
        regionWatcher = com.couchsubs.mobile.core.RegionWatcher({ crop -> areaReader.read(crop.pixels as RegionPixels) },
            TargetAwareTranslator(onlineTranslator(free.separate()) ?: free.separate(), target), subtitleServer).apply {
            packLookup = { text -> if (turkish && packTitles != null && settings.packsEnabled) PackLookup.match(library, text) else null }
        }
        // Nino: oyunun havuzdaki çevirileri oturum başında ve oyun değişince hemen, sonra dakikada bir iner (sunucunun
        // syncSeconds aralığıyla kendini sınırlar); aynı döngüde sunucuya "buradayım" denir.
        fun restartSync() = synchronized(syncLock) {
            syncTask?.cancel(false)
            syncTask = null
            if (!translationPool.isEnabled) return@synchronized
            var first = true
            syncTask = try {
                poolSync.scheduleWithFixedDelay({
                    val force = first
                    first = false
                    val played = playedGame ?: game.takeIf { it != "genel" }
                    try {
                        translationPool.sync(played, force)
                        translationPool.ping(played)
                    } catch (error: Exception) {
                        Log.w(TAG, "çeviri havuzu", error)
                    }
                }, 0, 60, TimeUnit.SECONDS)
            } catch (stopped: java.util.concurrent.RejectedExecutionException) { null }
        }
        restartSync()
        // Çeviri sürerken ortak havuz kapatılırsa hemen hiçbir şey sorulmaz, gönderilmez; açılırsa yeniden başlar.
        poolListener = settings.onSharePoolChanged {
            val on = settings.sharePool && realGame
            try {
                poolSync.execute {
                    // Satır kuyruğu yalnız kullanıcı havuzu kapatınca silinir; klipte kuyruğa dokunulmaz (bkz. NinoPool).
                    if (!settings.sharePool) linePool.setEnabled(false) else if (realGame) linePool.setEnabled(true)
                    translationPool.setEnabled(on)
                    restartSync()
                }
            } catch (stopped: java.util.concurrent.RejectedExecutionException) { }
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

        val onFrame: (com.couchsubs.mobile.remoteplay.VideoFrame) -> Unit = { frame ->
            val now = System.currentTimeMillis()
            if (screenRequested.compareAndSet(true, false)) startScreen(frame)
            if (!reading.get() && now - lastRead >= 1000 / MAX_READS_PER_SECOND) {
                val area = region
                // Karenin geldiği an: gecikme buradan TV'ye gidene kadar ölçülür (hattın saatiyle).
                val capturedAt = com.couchsubs.mobile.core.monotonicClock()
                SubtitleReader.copyRegion(frame, area)?.let { pixels ->
                    lastRead = now
                    reading.set(true)
                    ocr.execute { read(pixels, area, capturedAt) }
                }
            }
            // Ek alanlar saniyede bir, kendi iş parçacığında okunur; altyazı okumasını beklemez, onu bekletmez.
            regionWatcher?.offer(extraAreas, { r ->
                SubtitleReader.copyRegion(frame, r)?.let {
                    com.couchsubs.mobile.core.RegionWatcher.Crop(it, com.couchsubs.mobile.core.RegionSignature.of(it.nv21, it.width, it.height))
                }
            }) { task -> runCatching { regionWork.execute(task) } }
            FramePreview.offer(frame, now)
            if (realGame) identifyGameIfNeeded(frame, translationPool, library)
        }
        val onState: (SessionState) -> Unit = { state ->
            streaming = state == SessionState.Streaming
            if (!streaming) {
                PlayedGame.consoleReported(null)
                regionWatcher?.reset()
            }
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
        // Oynanan oyun (PS5'in bildirdiği, kullanıcının seçtiği ya da paketten tanınan; bkz. PlayedGame): havuza giden
        // satırlar bu oyunla gider. Klipte oyun aranmaz, sorulmaz.
        if (realGame) {
            PlayedGame.packTitles = { packTitles?.filterKeys { it != GameSense.GENERAL_PACK }?.values?.toList() ?: emptyList() }
            // Elle seçilen oyunda satırlar yalnız o oyunun paketinde aranır, paketi yoksa hiç aranmaz (#218).
            PlayedGame.packs = library
            PlayedGame.onChange = { game ->
                val changed = playedGame != game?.name
                playedGame = game?.name
                // Nino: yeni oyunun havuzdaki çevirileri hemen iner.
                if (changed) restartSync()
                // Yeni oyun: o oyunun (havuzdan otomatik) paketi sunucuda yeni çıkmış olabilir; inerse bu oturumun
                // paketleri hemen yeniden okunur (iPhone'daki gibi).
                if (game != null) Services.refreshPacks(force = false, maxAgeMs = PackStore.GAME_CHECK_MS) {
                    try {
                        library.reload()
                        if (packTitles != null) packTitles = library.infos.associate { it.id to it.title }
                    } catch (error: OutOfMemoryError) {
                        Log.e(TAG, "packs reload", error)
                    }
                }
            }
            PlayedGame.start(xboxConsole?.name?.ifEmpty { "Xbox" } ?: console?.takeIf { !captureCard }?.let { it.name.ifEmpty { it.host } }
                ?: getString(R.string.capture_card), settings, startedAt)
            gameCheck.reset()
            // Oyun iki dakikada tanınmazsa kart açılır (ayar ve ortak havuz açıksa, oturumda bir kez).
            background.scheduleWithFixedDelay({ PlayedGame.checkAsk(System.currentTimeMillis()) }, 15, 15, TimeUnit.SECONDS)
            // Bağlıyken iki dakikada bir PS5'e çalışan oyun sorulur (Xbox'ta bu soru yok; oyun paketten tanınır).
            if (xboxConsole == null && !captureCard && console != null) background.scheduleWithFixedDelay({
                try {
                    val host = settings.console?.host ?: console.host
                    if (streaming) PlayedGame.consoleReported(ConsoleDiscovery.runningGame(host))
                } catch (error: Exception) {
                    Log.w(TAG, "running game", error)
                }
            }, GAME_PROBE_MS / 4, GAME_PROBE_MS, TimeUnit.MILLISECONDS)
        } else {
            // Klipte oyun seçimi geçmez: önceki oturumun seçimi paket aramasını sınırlamasın.
            PlayedGame.packs = null
            library.limitToGame(null)
        }
        val source = replacement?.create(this, onFrame, onState)
            ?: xboxConsole?.let { XboxStreamSession(this, Services.xboxAuth, it, onFrame, onState, ::describeXbox,
                playAudio = settings.xboxAudioOnDevice) }
            ?: StreamSession(console!!, accountId!!, onFrame, onState, onConsoleMoved = { moved -> settings.console = moved },
                loginPasscode = settings.loginPasscode)
        synchronized(lifecycle) {
            // Kurulum sürerken durdurulduysa (onDestroy çalıştı) açılan bağlantı başlatılmaz.
            if (destroyed) {
                source.dispose()
                releaseParts()
                return
            }
            session = source
            Backend.breadcrumb(if (xboxConsole != null) "çeviri: Xbox oturumu açılıyor" else "çeviri: PS5 oturumu açılıyor")
            source.start()
        }
        // Nino: çeviri başladı; TV kısa bir "Çeviri başladı" balonu gösterir (sonradan bağlanan TV de 20 sn içinde görür),
        // telefonda da robotun yanında 7 sn balon çıkar (Mac ile aynı).
        subtitleServer.sendStarted()
        LiveState.update { it.copy(startedNoticeAt = System.currentTimeMillis()) }
        background.scheduleWithFixedDelay({
            session?.let { s ->
                LiveState.health.frameTotal(s.framesReceived)
                LiveState.update { it.copy(framesReceived = s.framesReceived) }
            }
        }, 2, 2, TimeUnit.SECONDS)
    }

    // --- Oyunu ekrandan tanıma ---

    /**
     * Nino: oyun bilinmiyorsa (PS5 bildirmiyor, hazır paketten de tanınmadı) Remote Play karesinden tanınır: sunucu kareye
     * bakıp oyunun adını söyler. Zamanlama [com.couchsubs.mobile.core.ScreenGameCheck]'te (8 sn sonra, olmazsa dakikada bir,
     * en çok 6 kez; tanıdıktan sonra 5 dk sonra bir kez, sonra 20 dakikada bir doğrular). Yalnız ortak havuz açıkken ve
     * hazır paket oyunu söylemiyorken. Kare iş parçacığında çağrılır: kare burada küçültülerek kopyalanır, JPEG ve istek
     * ayrı iş parçacığında. Mac: AppModel.identifyGameIfNeeded.
     */
    private fun identifyGameIfNeeded(frame: com.couchsubs.mobile.remoteplay.VideoFrame, pool: TranslationPool, library: GamePackLibrary) {
        if (!gameCheck.mayBeDue() || !pool.isEnabled || !settings.sharePool || library.searchScope != null) return
        val known = PlayedGame.sense.current
        if (!gameCheck.due(PlayedGame.sense.source)) return
        val gray = try {
            com.couchsubs.mobile.core.ScreenGameCheck.grayNv21(frame.buffer.duplicate(), frame.width, frame.height, frame.rowStride)
        } catch (error: RuntimeException) { null }
        if (gray == null) {
            gameCheck.finish()
            return
        }
        try {
            identifyWork.execute {
                try {
                    val jpeg = java.io.ByteArrayOutputStream().use { out ->
                        android.graphics.YuvImage(gray.nv21, android.graphics.ImageFormat.NV21, gray.width, gray.height, null)
                            .compressToJpeg(android.graphics.Rect(0, 0, gray.width, gray.height), 60, out)
                        out.toByteArray()
                    }
                    val name = pool.identify(jpeg)
                    if (destroyed) return@execute
                    when {
                        name == null -> Log.i(TAG, if (known == null) "oyun ekrandan tanınamadı (deneme ${gameCheck.attempts})"
                            else "oyun yeniden bakışta seçilemedi; ${known.name} olarak kalıyor")
                        known != null && NinoPool.gameId(known.name) == NinoPool.gameId(name) -> Log.i(TAG, "oyun doğrulandı: $name")
                        else -> {
                            Log.i(TAG, if (known == null) "oyun ekrandan tanındı: $name" else "oyun değişmiş: ${known.name} → $name")
                            Backend.breadcrumb("oyun ekrandan tanındı")
                            PlayedGame.seen(name)
                        }
                    }
                } catch (error: Exception) {
                    Log.w(TAG, "oyun tanıma", error)
                } finally {
                    gameCheck.finish()
                }
            }
        } catch (stopped: java.util.concurrent.RejectedExecutionException) {
            gameCheck.finish()
        }
    }

    // --- Ekranı çevir ---

    /** Düğmeye basıldı: sıradaki PS5 karesi tam okunsun. */
    private val screenRequested = AtomicBoolean(false)
    private val screenWork = Executors.newSingleThreadExecutor { Thread(it, "CouchSubs screen").apply { isDaemon = true } }
    private val screenExpiry = Executors.newSingleThreadScheduledExecutor { Thread(it, "CouchSubs screen expiry").apply { isDaemon = true } }
    /** Her istek ve kaldırma bir üst numara alır; eski işin sonuçları yok sayılır. */
    private val screenGeneration = java.util.concurrent.atomic.AtomicInteger()
    @Volatile private var screenTask: java.util.concurrent.Future<*>? = null
    @Volatile private var screenReader: SubtitleReader? = null

    private fun toggleScreen() {
        val server = server ?: return
        val state = LiveState.status.value.screenState
        if (state != LiveStatus.ScreenState.IDLE) {
            hideScreen()
            return
        }
        if (!streaming) {
            server.sendSubtitle(getString(R.string.screen_no_picture), 4000)
            return
        }
        screenGeneration.incrementAndGet()
        LiveState.update { it.copy(screenState = LiveStatus.ScreenState.WORKING) }
        server.sendStyle(settings.style)
        server.sendSubtitle(getString(R.string.screen_translating), 2500)
        screenRequested.set(true)
    }

    /** Çeviriyi durdurur, sonuçları telefondan ve TV'den kaldırır. */
    private fun hideScreen() {
        screenGeneration.incrementAndGet()
        screenRequested.set(false)
        screenTask?.cancel(true)
        screenTask = null
        server?.clearScreen()
        server?.clear()
        LiveState.update { it.copy(screen = emptyList(), screenState = LiveStatus.ScreenState.IDLE) }
    }

    /** Sıradaki kare geldi: bütün kare kopyalanır, okuma ve çeviri kendi iş parçacığında sürer. */
    private fun startScreen(frame: com.couchsubs.mobile.remoteplay.VideoFrame) {
        val pixels = SubtitleReader.copyRegion(frame, CropRegion(0.0, 1.0, 0.0, 1.0))
        val generation = screenGeneration.get()
        if (pixels == null) {
            failScreen(generation, getString(R.string.screen_no_picture))
            return
        }
        val free = freeTranslator
        val server = server
        if (free == null || server == null) {
            failScreen(generation, getString(R.string.error_translation))
            return
        }
        screenTask = screenWork.submit(Runnable {
            try {
                val reader = screenReader ?: SubtitleReader().also { screenReader = it }
                val reading = reader.read(pixels)
                // Yapay zekâda ekranın bütün yazıları tek istekte gider (bkz. AiTranslator.translateAll).
                val translator = TargetAwareTranslator(onlineTranslator(free.separate()) ?: free.separate(), target)
                val items = ScreenTranslation.translate(reading, translator, { screenGeneration.get() != generation }) { shown ->
                    if (screenGeneration.get() != generation) return@translate
                    val milliseconds = ScreenTranslation.displayMilliseconds(shown)
                    server.sendScreen(shown, milliseconds)
                    screenExpiry.schedule({ if (screenGeneration.get() == generation) hideScreen() }, milliseconds.toLong(), TimeUnit.MILLISECONDS)
                }
                if (screenGeneration.get() != generation) return@Runnable
                server.clear()
                if (items.isEmpty()) {
                    LiveState.update { it.copy(screenState = LiveStatus.ScreenState.IDLE) }
                    server.sendSubtitle(getString(R.string.screen_none), 2500)
                }
            } catch (error: InterruptedException) {
                return@Runnable
            } catch (error: Exception) {
                Log.w(TAG, "screen", error)
                failScreen(generation, getString(R.string.screen_failed, getString(R.string.error_translation)))
            }
        })
    }

    private fun failScreen(generation: Int, message: String) {
        if (screenGeneration.get() != generation) return
        LiveState.update { it.copy(screenState = LiveStatus.ScreenState.IDLE) }
        server?.clear()
        server?.sendSubtitle(message, 6000)
    }

    private fun read(pixels: RegionPixels, area: CropRegion, capturedAt: Long) {
        try {
            // Bölge değişmediyse (aynı altyazı duruyor) yeniden okunmaz; son okuma hattı yine besler (kararlılık ve
            // silme saate bağlıdır, Windows'taki ReadScheduler gibi). Aynı okuma en çok 20 kare (hızlı okumada 2) kullanılır.
            val current = pipeline ?: return
            val maxReuse = if (settings.fastSubtitleDetection) FAST_MAX_REUSE else DEFAULT_MAX_REUSE
            val reused = pixels.signature == lastSignature && reusedReads < maxReuse
            reusedReads = if (reused) reusedReads + 1 else 0
            val started = com.couchsubs.mobile.core.monotonicClock()
            val result = if (reused) lastReading else reader?.read(pixels) ?: return
            if (BuildConfig.DEBUG && !reused) debugDump(pixels, result)
            val ocrMs = if (reused) lastOcrMs else (com.couchsubs.mobile.core.monotonicClock() - started).toInt()
            lastSignature = pixels.signature
            lastReading = result
            lastOcrMs = ocrMs
            current.process(result, area.box, com.couchsubs.mobile.core.RegionSignature.of(pixels.nv21, pixels.width, pixels.height),
                capturedAt, ocrMs)
        } catch (error: Exception) {
            Log.w(TAG, "OCR", error)
        } finally {
            reading.set(false)
        }
    }

    private var lastDump = 0L

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
    private fun onlineTranslator(free: TextTranslator): TextTranslator? {
        val engine = settings.engine
        val key = settings.apiKey(engine)?.takeIf { it.isNotBlank() } ?: return null
        return when (engine) {
            EngineChoice.FREE -> null
            // Nino: DeepL'in çeviremediği dilde (Hintçe, Urduca…) ücretsiz ML Kit çevirir.
            EngineChoice.DEEPL -> if (TargetLanguage.deepLSupports(target))
                DeepLTranslator(key, free, cache = cache(DeepLTranslator.ENGINE_ID), glossary = glossaryInUse, target = target) else null
            else -> {
                val provider = when (engine) {
                    EngineChoice.GEMINI -> AiProvider.GEMINI
                    EngineChoice.OPENAI -> AiProvider.OPENAI
                    else -> AiProvider.CLAUDE
                }
                val models = aiModels()[provider.id].orEmpty()
                val model = models.firstOrNull { it.id == settings.aiModel } ?: models.firstOrNull() ?: return null
                AiTranslator(provider, key, model, free, cache = cache(AiTranslator.engineId(provider, model)),
                    // Kararlı oyun (GameSense.current), son eşleşen paket değil: tek satır adı başka oyuna geçirmez (#27).
                    playedGame = { PlayedGame.sense.current?.name }, target = target)
            }
        }
    }

    private fun aiModels(): Map<String, List<AiModel>> = AiModel.load(this)

    /**
     * Motorun kalıcı önbelleği: files/Translations/v1-<motor>-en-<dil>.jsonl (iPhone'daki Translations klasörüyle aynı
     * biçim). Nino: her çeviri dilinin önbelleği ayrıdır.
     */
    private fun cache(engine: String) = TranslationCache.shared(File(filesDir, "Translations"), engine, target = TargetLanguage.code(target))

    @Volatile private var glossaryInUse = Glossary.Empty

    /** Xbox hatasının ekrandaki anlatımı. */
    private fun describeXbox(kind: XboxError): String = getString(when (kind) {
        XboxError.SIGN_IN_REQUIRED, XboxError.CODE_EXPIRED, XboxError.SIGN_IN_DECLINED -> R.string.xbox_error_sign_in
        XboxError.NO_XBOX_ACCOUNT -> R.string.xbox_error_no_account
        XboxError.CONSOLE_UNAVAILABLE -> R.string.xbox_error_console
        XboxError.BUSY -> R.string.xbox_error_busy
        XboxError.TIMEOUT -> R.string.xbox_error_timeout
        XboxError.NETWORK -> R.string.xbox_error_network
        XboxError.SERVICE -> R.string.xbox_error_service
    })

    private fun describe(state: SessionState): String =
        // Xbox oturumu nedeni kullanıcının dilinde verir.
        if (state is SessionState.Disconnected && state.kind == DisconnectKind.OTHER && xbox && state.detail != null) state.detail
        else describePs(state)

    private val CARD_PROBLEMS = setOf(DisconnectKind.NO_CAPTURE_CARD, DisconnectKind.NO_CAMERA_PERMISSION, DisconnectKind.BLACK_PICTURE)
    private val cardMessages by lazy {
        setOf(getString(R.string.capture_not_found), getString(R.string.capture_no_permission), getString(R.string.capture_black))
    }

    private fun describePs(state: SessionState): String = when (state) {
        SessionState.Connecting -> getString(if (captureCard) R.string.capture_phase_opening else if (xbox) R.string.xbox_phase_connecting else R.string.phase_connecting)
        SessionState.Streaming -> getString(R.string.phase_streaming)
        is SessionState.Disconnected -> when (state.kind) {
            DisconnectKind.NO_CAPTURE_CARD -> getString(R.string.capture_not_found)
            DisconnectKind.NO_CAMERA_PERMISSION -> getString(R.string.capture_no_permission)
            DisconnectKind.BLACK_PICTURE -> getString(R.string.capture_black)
            DisconnectKind.IN_USE -> getString(R.string.phase_in_use)
            DisconnectKind.NOT_FOUND -> state.detail?.let { getString(R.string.phase_not_found_host, it) } ?: getString(R.string.phase_not_found)
            DisconnectKind.NETWORK -> getString(R.string.phase_network)
            DisconnectKind.REGISTRATION_INVALID -> getString(R.string.phase_registration_invalid)
            // Eskiden "Bağlantı koptu, yeniden bağlanılıyor…" görünüyordu, neden anlaşılmıyordu (GitHub #33, #202).
            DisconnectKind.REJECTED -> state.detail?.let { getString(R.string.phase_rejected_code, it) } ?: getString(R.string.phase_rejected)
            DisconnectKind.NO_PICTURE -> getString(R.string.phase_no_picture)
            DisconnectKind.CONSOLE_ASLEEP -> getString(R.string.phase_asleep)
            DisconnectKind.LOGIN_PASSCODE -> getString(R.string.phase_passcode)
            DisconnectKind.LOGIN_PASSCODE_INCORRECT -> getString(R.string.phase_passcode_incorrect)
            DisconnectKind.REFUSED -> getString(R.string.phase_refused)
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
        PlayedGame.stop()
        styleListener?.let(settings::removeListener)
        styleListener = null
        targetListener?.let(settings::removeListener)
        targetListener = null
        poolListener?.let(settings::removeListener)
        poolListener = null
        synchronized(syncLock) {
            syncTask?.cancel(false)
            syncTask = null
        }
        translations?.let { pool -> Thread { pool.save() }.start() }
        translations = null
        areasListener?.let(settings::removeListener)
        areasListener = null
        regionWatcher?.reset()
        regionWatcher = null
        regionReader?.close()
        regionReader = null
        session?.dispose()
        session = null
        pipeline?.reset()
        pipeline?.shutdown()
        pipeline = null
        liveServer = null
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
        Services.onLocalPacksChanged = null
        settings.translating = false
        if (startedAt > 0) settings.lastSessionMs = System.currentTimeMillis() - startedAt
        if (startedAt > 0) Telemetry.event(Telemetry.SESSION_STOP, "seconds" to (System.currentTimeMillis() - startedAt) / 1000,
            "pack_lines" to (pipeline?.packHits ?: 0), "lines" to LiveState.status.value.recent.size)
        releaseParts()
        LiveState.health.sessionEnded()
        background.shutdownNow()
        ocr.shutdownNow()
        regionWork.shutdownNow()
        poolWork.shutdownNow()
        identifyWork.shutdownNow()
        poolSync.shutdownNow()
        screenGeneration.incrementAndGet()
        screenTask?.cancel(true)
        screenWork.shutdownNow()
        screenExpiry.shutdownNow()
        screenReader?.close()
        screenReader = null
        if (current === this) current = null
        wakeLock?.takeIf { it.isHeld }?.release()
        wifiLock?.takeIf { it.isHeld }?.release()
        lineHandler.removeCallbacksAndMessages(lineExpiry)
        // Nino: yakalama kartı uyarısı oturumla birlikte kalkar (kaynak değişince eski uyarı kalmasın).
        LiveState.update { it.copy(running = false, phase = "", current = "", previous = "", regions = emptyList(), screen = emptyList(),
            screenState = LiveStatus.ScreenState.IDLE, streaming = false, error = if (it.error in cardMessages) null else it.error) }
        super.onDestroy()
    }
}
