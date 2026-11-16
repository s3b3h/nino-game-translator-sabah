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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.account.Telemetry
import com.couchsubs.mobile.service.LiveState
import com.couchsubs.mobile.service.TranslationService
import com.couchsubs.mobile.settings.SubtitleTarget

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

    /** Kurulumun eksik ilk adımı; hepsi tamamsa ana ekran. */
    fun next(): String {
        val settings = Services.settings
        return when {
            !settings.welcomeSeen -> WELCOME
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
                    composable(Routes.PAIR) { PairScreen(onBack = back(navigation), onSkip = skip(navigation)) { advance(navigation) } }
                    composable(Routes.TARGET) {
                        val onboarding = navigation.previousBackStackEntry == null
                        TargetScreen(onBack = back(navigation)) {
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
                        )
                    }
                    composable(Routes.SETTINGS) {
                        SettingsScreen(onBack = { navigation.popBackStack() }, onPacks = { navigation.navigate(Routes.PACKS) },
                            onTarget = { navigation.navigate(Routes.TARGET) }, onPairing = { pairing(navigation) },
                            onHealth = { navigation.navigate(Routes.HEALTH) }, onSource = { navigation.navigate(Routes.SOURCE) })
                    }
                    composable(Routes.SOURCE) { SourceScreen(onBack = back(navigation)) { navigation.popBackStack() } }
                    composable(Routes.HEALTH) { SystemHealthScreen(onBack = { navigation.popBackStack() }) }
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
        navigation.navigate(if (Services.settings.accountId == null) Routes.PSN else Routes.PAIR)
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
