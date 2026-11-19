// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import com.couchsubs.mobile.withInterfaceLanguage
import android.graphics.Color
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.setValue
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.account.Telemetry
import com.couchsubs.mobile.service.LiveState
import com.couchsubs.mobile.service.TranslationService
import com.couchsubs.mobile.settings.SubtitleTarget
import com.couchsubs.mobile.tv.TvAppUpdate

/** Gezinme yolları (Compose Navigation). */
object Routes {
    const val WELCOME = "welcome"
    const val PSN = "psn"
    const val PAIR = "pair"
    const val TARGET = "target"
    const val MAIN = "main"
    const val PACKS = "packs"
    const val PROFILE = "profile"
    const val SETTINGS = "settings"
    const val HEALTH = "health"
    const val SOURCE = "source"
    const val TV_INSTALL = "tvinstall"
    const val HISTORY = "history"
    /** Konsol türü sorusu (Nino'nun ConsoleScreen'i: PS5 / Xbox). */
    const val PLATFORM = "platform"
    const val XBOX_LOGIN = "xboxlogin"
    const val XBOX_CONSOLE = "xboxconsole"
    /** Nino: Sorun Bildir. */
    const val REPORT = "report"
    /** Nino: "Nino'ya Sor" kurulum yardımcısı. */
    const val ASSISTANT = "assistant"

    /** Yüzen robot düğmesinin göründüğü ekranlar (ana ekran ve kurulum adımları, takılınan yerler). */
    val ASSISTANT_BUTTON = setOf(MAIN, WELCOME, PLATFORM, PSN, PAIR, TARGET, XBOX_LOGIN, XBOX_CONSOLE, TV_INSTALL, SOURCE)

    /** Kurulumun eksik ilk adımı; hepsi tamamsa ana ekran. */
    fun next(): String {
        val settings = Services.settings
        return when {
            !settings.welcomeSeen -> WELCOME
            // Konsol türü bir kez sorulur; PS5'i önceden eşlenmiş kurulumlar PlayStation sayılır.
            // Nino: kurulumda önce konsol türü (PS5 / Xbox) sorulur; kurulumu bitmiş eski kurulumlara sorulmaz.
            settings.platformChoice == null && !settings.onboarded && settings.accountId == null && settings.console == null && !settings.setupSkipped -> PLATFORM
            // Xbox (Beta): Microsoft girişi ve Xbox seçimi; ikinci hesap (PSN) adımı yok. Yakalama kartında settings.xbox
            // false'tur (görüntü karttan gelir), bu adımlar atlanır.
            settings.xbox && !Services.xboxAuth.signedIn && !settings.setupSkipped -> XBOX_LOGIN
            settings.xbox && settings.xboxConsole == null && !settings.setupSkipped -> XBOX_CONSOLE
            settings.xbox -> if (!settings.onboarded) TARGET else MAIN
            // "Şimdilik geç" ile atlandıysa PS5'siz ana ekrana gidilir (ör. Play incelemesi); eşleme Ayarlar'dan.
            // Nino: yakalama kartıyla PSN girişi ve PS5 eşlemesi gerekmez.
            settings.accountId == null && !settings.setupSkipped && !settings.usesCaptureCard -> PSN
            settings.console == null && !settings.setupSkipped && !settings.usesCaptureCard -> PAIR
            !settings.onboarded -> TARGET
            else -> MAIN
        }
    }
}

class MainActivity : ComponentActivity() {
    override fun attachBaseContext(newBase: android.content.Context) = super.attachBaseContext(newBase.withInterfaceLanguage())

    /**
     * Nino: telefon uygulamasının yeni sürümüne uygulama her öne geldiğinde bakılır (ağa en çok 3 saatte bir çıkar).
     * Eskiden yalnız uygulama açılırken bakılıyordu; günlerce arka planda açık kalan uygulama yeni sürümü görmüyordu.
     */
    override fun onResume() {
        super.onResume()
        lifecycleScope.launch { com.couchsubs.mobile.update.AppUpdate.check(applicationContext) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Uygulama hep koyu; sistem açık temadayken de durum çubuğu simgeleri açık renk kalsın.
        enableEdgeToEdge(SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT), SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        val settings = Services.settings
        setContent {
            CouchSubsTheme {
                // Nino: her açılışta önce açılış animasyonu.
                var showSplash by androidx.compose.runtime.saveable.rememberSaveable { androidx.compose.runtime.mutableStateOf(true) }
                androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.fillMaxSize()) {
                val navigation = rememberNavController()
                val status by LiveState.status.collectAsState()
                LaunchedEffect(status.running) {
                    if (status.running && settings.keepScreenOn) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                // Masaüstündeki gibi: uygulama açılınca ve TV her bağlandığında TV'deki CouchSubs sürümüne bakılır;
                // eskiyse ana ekran "TV uygulamasını güncelle" önerir.
                val tvConnected = status.connectedTvs > 0
                LaunchedEffect(tvConnected) { TvAppUpdate.check(applicationContext) }
                DisposableEffect(navigation) {
                    val listener = androidx.navigation.NavController.OnDestinationChangedListener { _, destination, _ ->
                        destination.route?.let { Telemetry.screen(it.substringBefore('/')) }
                    }
                    navigation.addOnDestinationChangedListener(listener)
                    onDispose { navigation.removeOnDestinationChangedListener(listener) }
                }
                NavHost(navigation, startDestination = Routes.next()) {
                    composable(Routes.WELCOME) {
                        WelcomeScreen {
                            settings.welcomeSeen = true
                            Services.applyMeasurement()
                            advance(navigation)
                        }
                    }
                    composable(Routes.PSN) {
                        PsnLoginScreen(onBack = back(navigation), onSkip = skip(navigation)) {
                            // Ana ekrandan eşlemeye gelindiyse girişten sonra eşleme ekranı açılır.
                            if (settings.console == null && navigation.previousBackStackEntry != null)
                                navigation.navigate(Routes.PAIR) { popUpTo(Routes.PSN) { inclusive = true } }
                            else advance(navigation)
                        }
                    }
                    composable(Routes.PLATFORM) { ConsoleScreen(onBack = back(navigation)) { advance(navigation) } }
                    composable(Routes.XBOX_LOGIN) {
                        XboxLoginScreen(onBack = back(navigation), onSkip = skip(navigation)) {
                            if (settings.xboxConsole == null && navigation.previousBackStackEntry != null)
                                navigation.navigate(Routes.XBOX_CONSOLE) { popUpTo(Routes.XBOX_LOGIN) { inclusive = true } }
                            else advance(navigation)
                        }
                    }
                    composable(Routes.XBOX_CONSOLE) {
                        XboxConsoleScreen(onBack = back(navigation), onSkip = skip(navigation),
                            onSignIn = { navigation.navigate(Routes.XBOX_LOGIN) }) { advance(navigation) }
                    }
                    composable(Routes.PAIR) { PairScreen(onBack = back(navigation), onSkip = skip(navigation)) { advance(navigation) } }
                    composable(Routes.TARGET) {
                        val onboarding = navigation.previousBackStackEntry == null
                        TargetScreen(onBack = back(navigation), onTvInstall = { navigation.navigate(Routes.TV_INSTALL) }) {
                            if (onboarding) Telemetry.event(Telemetry.ONBOARDING_DONE, "target" to settings.target.name.lowercase())
                            advance(navigation)
                        }
                    }
                    composable(Routes.MAIN) {
                        MainScreen(
                            status = status,
                            onStart = ::startTranslation,
                            onStop = { if (com.couchsubs.mobile.service.DemoSession.active) com.couchsubs.mobile.service.DemoSession.stop() else TranslationService.stop(this@MainActivity) },
                            onPhoneView = { startActivity(Intent(this@MainActivity, PhoneSubtitleActivity::class.java)) },
                            onTarget = { navigation.navigate(Routes.TARGET) },
                            onPairing = { pairing(navigation) },
                            onSource = { navigation.navigate(Routes.SOURCE) },
                            onPacks = { navigation.navigate(Routes.PACKS) },
                            onProfile = { navigation.navigate(Routes.PROFILE) },
                            onSettings = { navigation.navigate(Routes.SETTINGS) },
                            onHistory = { navigation.navigate(Routes.HISTORY) },
                            onTvUpdate = { tv ->
                                TvAppUpdate.pending = tv
                                navigation.navigate(Routes.TV_INSTALL)
                            },
                        )
                    }
                    composable(Routes.PACKS) {
                        PacksScreen(onBack = { navigation.popBackStack() }, packInUse = status.packInUse)
                    }
                    composable(Routes.PROFILE) {
                        ProfileScreen(
                            onBack = { navigation.popBackStack() },
                            onSettings = { navigation.navigate(Routes.SETTINGS) },
                            onPairing = { pairing(navigation) },
                            onTarget = { navigation.navigate(Routes.TARGET) },
                            onPsn = { navigation.navigate(Routes.PSN) },
                            onInstallTv = { navigation.navigate(Routes.TV_INSTALL) },
                            onReport = { navigation.navigate(Routes.REPORT) },
                            onAssistant = { navigation.navigate(Routes.ASSISTANT) },
                        )
                    }
                    composable(Routes.SETTINGS) {
                        SettingsScreen(onBack = { navigation.popBackStack() }, onPacks = { navigation.navigate(Routes.PACKS) },
                            onTarget = { navigation.navigate(Routes.TARGET) }, onPairing = { pairing(navigation) },
                            onHealth = { navigation.navigate(Routes.HEALTH) }, onSource = { navigation.navigate(Routes.SOURCE) },
                            onTvInstall = { navigation.navigate(Routes.TV_INSTALL) }, onReport = { navigation.navigate(Routes.REPORT) },
                            onAssistant = { navigation.navigate(Routes.ASSISTANT) })
                    }
                    composable(Routes.REPORT) { ReportProblemScreen(onBack = { navigation.popBackStack() }) }
                    composable(Routes.ASSISTANT) {
                        AskNinoScreen(onBack = { navigation.popBackStack() }, onReport = { navigation.navigate(Routes.REPORT) })
                    }
                    composable(Routes.HISTORY) { HistoryScreen(onBack = { navigation.popBackStack() }) }
                    composable(Routes.TV_INSTALL) {
                        // Kurulum bitince "Ana ekrana geç": kurulumun 3. adımından gelindiyse kurulum biter (TvAppUpdate.installed).
                        TvInstallScreen(onBack = { navigation.popBackStack() }) {
                            if (Routes.next() == Routes.MAIN) navigation.navigate(Routes.MAIN) { popUpTo(0) { inclusive = true } }
                            else navigation.popBackStack()
                        }
                    }
                    composable(Routes.SOURCE) {
                        SourceScreen(onBack = back(navigation)) {
                            navigation.popBackStack()
                            // Nino: Xbox seçildiyse ve kurulmadıysa Microsoft girişi ya da konsol seçimi hemen açılır.
                            if (settings.xbox && !Services.xboxAuth.signedIn) navigation.navigate(Routes.XBOX_LOGIN)
                            else if (settings.xbox && settings.xboxConsole == null) navigation.navigate(Routes.XBOX_CONSOLE)
                        }
                    }
                    composable(Routes.HEALTH) { SystemHealthScreen(onBack = { navigation.popBackStack() }) }
                }
                // Nino: yüzen "Nino'ya Sor" düğmesi (ana ekran ve kurulum ekranları); altta birincil düğmenin üstünde durur.
                val entry by navigation.currentBackStackEntryAsState()
                val route = entry?.destination?.route
                if (!showSplash && route in Routes.ASSISTANT_BUTTON) {
                    AskNinoButton(androidx.compose.ui.Modifier.align(androidx.compose.ui.Alignment.BottomEnd)
                        .navigationBarsPadding()
                        .padding(end = 20.dp, bottom = if (route == Routes.MAIN) 96.dp else 92.dp)) {
                        navigation.navigate(Routes.ASSISTANT) { launchSingleTop = true }
                    }
                }
                // Nino: çeviri başlayınca 7 sn "Çeviri başladı" balonu: robot görünüyorsa yanında, yoksa ekranın üstünde.
                if (!showSplash && status.running && status.startedNoticeAt > 0) {
                    if (route in Routes.ASSISTANT_BUTTON) {
                        androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.align(androidx.compose.ui.Alignment.BottomEnd)
                            .navigationBarsPadding()
                            .padding(start = 20.dp, end = 20.dp + 60.dp + 10.dp, bottom = if (route == Routes.MAIN) 96.dp else 92.dp)
                            .heightIn(min = 60.dp),
                            contentAlignment = androidx.compose.ui.Alignment.CenterEnd) {
                            StartedNotice(status.startedNoticeAt, androidx.compose.ui.Modifier.widthIn(max = 250.dp))
                        }
                    } else {
                        StartedNotice(status.startedNoticeAt, androidx.compose.ui.Modifier.align(androidx.compose.ui.Alignment.TopCenter)
                            .statusBarsPadding().padding(top = 12.dp, start = 20.dp, end = 20.dp))
                    }
                }
                if (showSplash) NinoSplash { showSplash = false }
                }
            }
        }
    }

    /**
     * Kurulumda bir sonraki eksik adıma geçer. Ana ekrandan açılmış bir adım (ör. Profil › Eşlemeyi yenile) bitince
     * geri dönülür.
     */
    private fun advance(navigation: NavHostController) {
        val next = Routes.next()
        // Ayarlar'dan konsol türü değişince eksik adım (ör. Microsoft girişi) açılır.
        if (next != Routes.MAIN && navigation.previousBackStackEntry != null && next in setOf(Routes.XBOX_LOGIN, Routes.XBOX_CONSOLE, Routes.PSN, Routes.PAIR)) {
            navigation.navigate(next) { popUpTo(navigation.currentDestination?.route ?: next) { inclusive = true } }
            return
        }
        if (next == Routes.MAIN && navigation.previousBackStackEntry != null) {
            navigation.popBackStack()
            return
        }
        navigation.navigate(next) { popUpTo(0) { inclusive = true } }
    }

    /** Ana ekrandan açılmış adımda geri düğmesi; kurulumda (yığında önceki ekran yok) düğme görünmez. */
    private fun back(navigation: NavHostController): (() -> Unit)? =
        if (navigation.previousBackStackEntry != null) ({ navigation.popBackStack() }) else null

    /** Kurulumda (yığında önceki ekran yok) "Şimdilik geç": PSN ve PS5 adımları atlanır, PS5'siz ana ekrana geçilir. */
    private fun skip(navigation: NavHostController): (() -> Unit)? =
        if (navigation.previousBackStackEntry == null) ({
            Services.settings.setupSkipped = true
            advance(navigation)
        }) else null

    /** PS5 eşleme: PSN girişi yoksa (kurulum atlandıysa) önce giriş, ardından eşleme. */
    private fun pairing(navigation: NavHostController) {
        val settings = Services.settings
        if (settings.xbox) navigation.navigate(if (!Services.xboxAuth.signedIn) Routes.XBOX_LOGIN else Routes.XBOX_CONSOLE)
        else navigation.navigate(if (settings.accountId == null) Routes.PSN else Routes.PAIR)
    }

    /** Nino: yakalama kartında çeviri, kamera izni sorulduktan sonra başlar (izin verilmezse sorun ana ekranda yazılır). */
    private val cameraPermission = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) startTranslation()
        else LiveState.update { it.copy(error = getString(com.couchsubs.mobile.R.string.capture_no_permission)) }
    }

    private fun startTranslation() {
        if (Services.settings.usesCaptureCard && checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            cameraPermission.launch(Manifest.permission.CAMERA)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        TranslationService.start(this)
        if (Services.settings.target == SubtitleTarget.PHONE) startActivity(Intent(this, PhoneSubtitleActivity::class.java))
    }
}
