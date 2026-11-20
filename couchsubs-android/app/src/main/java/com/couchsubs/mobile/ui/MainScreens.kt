// SPDX-License-Identifier: AGPL-3.0-only
// Ana ekran (tuval: Telefon-Ana, -Calisiyor, -Tur) ve oyun paketleri (-Paketler). Uygulama ve paketler ücretsiz.
package com.couchsubs.mobile.ui

import androidx.compose.foundation.layout.size
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Icon
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.runtime.CompositionLocalProvider
import com.couchsubs.mobile.core.TargetLanguage
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.service.LiveStatus
import com.couchsubs.mobile.settings.SubtitleTarget
import com.couchsubs.mobile.settings.HomeStyle
import androidx.compose.ui.draw.clip
import com.couchsubs.mobile.tv.InstalledTv
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** Turda vurgulanan öğeler (TASARIM-MOBIL.md §10, tuval Telefon-Tur). */
private enum class TourStep(val title: Int, val body: Int) {
    START(R.string.tour1_title, R.string.tour1_body),
    TARGET(R.string.tour2_title, R.string.tour2_body),
    PACKS(R.string.tour3_title, R.string.tour3_body),
    PROFILE(R.string.tour4_title, R.string.tour4_body),
}

/** Paket kimliğinden kısa ad ve kod (tuvaldeki karolar). */
fun packShort(id: String, title: String): Pair<String, String> = when (id) {
    "gta-v" -> "GTA" to "GTA V"
    "red-dead-redemption-2" -> "RDR" to "Red Dead 2"
    "mafia-the-old-country" -> "MAF" to "Mafia: TOC"
    "assassins-creed-shadows" -> "ACS" to "AC Shadows"
    "death-stranding-2" -> "DS2" to "Death Str. 2"
    "call-of-duty-modern-warfare-2019" -> "MW" to "CoD MW 2019"
    else -> title.filter { it.isLetterOrDigit() }.take(3).uppercase() to title
}

/** "190 bin satır" */
fun linesText(context: Context, entries: Int): String =
    if (entries >= 1000) context.getString(R.string.lines_thousands, (entries + 500) / 1000) else context.getString(R.string.lines_count, entries)

fun durationText(context: Context, millis: Long): String {
    val minutes = millis / 60_000
    return if (minutes >= 60) context.getString(R.string.duration_hours, minutes / 60, minutes % 60) else context.getString(R.string.duration_minutes, minutes)
}

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun MainScreen(
    status: LiveStatus,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onPhoneView: () -> Unit,
    onTarget: () -> Unit,
    onPairing: () -> Unit,
    onPacks: () -> Unit,
    onProfile: () -> Unit,
    onSettings: () -> Unit,
    onSource: () -> Unit = onSettings,
    onHistory: () -> Unit = {},
    onTvUpdate: (InstalledTv) -> Unit = {},
) {
    val context = LocalContext.current
    val settings = Services.settings
    val bounds = remember { mutableStateMapOf<TourStep, Rect>() }
    var tour by remember { mutableStateOf(if (settings.tourShown) null else TourStep.START) }
    // Nino: yakalama kartıyla PS5 eşlemesi gerekmez; kart modu "hazır" sayılır, PS5 kısa yolu kaynak ekranını açar.
    val captureCard = settings.usesCaptureCard
    // Nino: Xbox'ta "eşli" = Microsoft girişi yapılmış ve konsol seçilmiş; kısa yol Xbox ekranını açar.
    val xbox = settings.xbox
    val paired = captureCard || if (xbox) settings.xboxReady else settings.console != null
    val sourceName = if (captureCard) stringResource(R.string.capture_card) else if (xbox) settings.xboxConsole?.name else settings.console?.name
    val onSourceTap = if (captureCard) onSource else onPairing
    val consoleLabel = if (xbox) "Xbox" else "PS5"
    // Nino: ana ekran hep dikeydir (manifest); yalnız tam ekran altyazı yataydır. Çeviri açıkken telefon yan çevrilince
    // (yön algılayıcısı, ekran dönmeden) tam ekran açılır. Tam ekrandan dönünce, telefon önce dikeye gelmeden yeniden açılmaz;
    // masadaki telefonun titremesi için yan durum en az 0,7 sn sürmelidir.
    val phoneOutput = settings.target != SubtitleTarget.TV || status.demo
    val armed = remember { java.util.concurrent.atomic.AtomicBoolean(false) }
    val openPhoneView = {
        armed.set(false)
        onPhoneView()
    }
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    val sensorContext = LocalContext.current
    androidx.compose.runtime.DisposableEffect(status.running, phoneOutput) {
        if (!status.running || !phoneOutput) return@DisposableEffect onDispose { }
        var sidewaysSince = 0L
        val listener = object : android.view.OrientationEventListener(sensorContext) {
            override fun onOrientationChanged(degrees: Int) {
                if (degrees == ORIENTATION_UNKNOWN) return
                val upright = degrees <= 25 || degrees >= 335
                val sideways = degrees in 65..115 || degrees in 245..295
                if (upright) { armed.set(true); sidewaysSince = 0L; return }
                if (!sideways || !armed.get() || !lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) { sidewaysSince = 0L; return }
                val now = android.os.SystemClock.uptimeMillis()
                if (sidewaysSince == 0L) sidewaysSince = now
                else if (now - sidewaysSince >= 700) { sidewaysSince = 0L; openPhoneView() }
            }
        }
        if (listener.canDetectOrientation()) listener.enable()
        onDispose { listener.disable() }
    }
    fun mark(step: TourStep) = Modifier.onGloballyPositioned { bounds[step] = it.boundsInRoot() }
    val topBar: @Composable () -> Unit = {
        TopBar {
            // iPhone'daki gibi: geçmiş, ayarlar, profil.
            IconAction(Icons.Filled.History, stringResource(R.string.history), onHistory)
            SettingsAction(onSettings)
            Box(mark(TourStep.PROFILE)) { ProfileAction(onProfile) }
        }
    }

    Box(Modifier.fillMaxSize()) {
        // Nino: Mac ile aynı iki arayüz (Ayarlar › Arayüz). Salon: fişi prize takın. Cam düğme: sağa kaydırın, canlı TV insin.
        ScreenScaffold(top = topBar) {
            val onTv = settings.target == SubtitleTarget.TV
            // TV'deki uygulama eskiyse güncelleme önerisi (telefondan kurulur).
            if (!status.running) TvAppUpdateCard(onTvUpdate)
            // Nino: GitHub'da telefon uygulamasının yeni sürümü varsa sakin bir öneri (Play kopyasında gösterilmez).
            if (!status.running) AppUpdateCard()
            if (settings.homeStyle == HomeStyle.LIVING_ROOM) {
                // Nino V4 (iPhone'daki HomeScreen ile aynı düzen): durum + başlık, salon, ipucu satırı (canlıyken sağında
                // Tam Ekran), eşlenmemişken "PS5'siz Deneyin", altta üç büyük kısa yol. Aralıklar elle verilir.
                Column(Modifier.fillMaxWidth()) {
                    LivingRoomHeader(status, paired, sourceName, onTv, consoleLabel)
                    Spacer(Modifier.height(14.dp))
                    // Nino: sahne Arapça arayüzde aynalanmaz (sürükleme ve görsel soldan sağa).
                    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                        LivingRoomScene(status, paired, mark(TourStep.START), onStart = onStart, onStop = onStop, onLocked = onSourceTap)
                    }
                    Spacer(Modifier.height(10.dp))
                    Row(Modifier.fillMaxWidth().heightIn(min = 36.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        LivingRoomHint(status.running, paired, Modifier.weight(1f))
                        // Nino: altyazı TV'ye gitse de telefonda tam ekran açılabilsin.
                        androidx.compose.animation.AnimatedVisibility(status.running,
                            enter = androidx.compose.animation.fadeIn(), exit = androidx.compose.animation.fadeOut()) {
                            FullScreenPill(openPhoneView)
                        }
                    }
                    // PS5'i olmayanlar ve mağaza incelemesi için örnek altyazılarla deneme.
                    if (!paired && !status.running) TryWithoutConsole({ com.couchsubs.mobile.service.DemoSession.start() }, Modifier.padding(top = 14.dp))
                    if (status.running && phoneOutput) Box(Modifier.padding(top = 14.dp)) { RotateHint() }
                    Spacer(Modifier.height(if (!paired && !status.running) 18.dp else 22.dp))
                    HomeShortcuts(consoleLabel, sourceName, onTv,
                        if (onTv) (if (status.connectedTvs > 0) stringResource(R.string.nino_tv_connected) else "TV") else stringResource(R.string.nino_phone),
                        settings.packsEnabled, mark(TourStep.TARGET), mark(TourStep.PACKS), onSourceTap, onTarget, onPacks)
                }
            } else {
                // Nino: telefonun sade ana ekranı (durum, başlık, sahne, kaydırma, üç kısa yol).
                PremiumHome(status, paired, sourceName, onTv, settings.packsEnabled,
                    startMarker = mark(TourStep.START), targetMarker = mark(TourStep.TARGET), packsMarker = mark(TourStep.PACKS),
                    onStart = onStart, onStop = onStop, onPairing = onSourceTap, onTarget = onTarget, onPacks = onPacks,
                    onFullScreen = openPhoneView, onDemo = { com.couchsubs.mobile.service.DemoSession.start() }, consoleLabel = consoleLabel)
            }
            status.error?.let { NoteTile(it) }
        }
        tour?.let { step ->
            TourOverlay(step, bounds[step], onSkip = {
                settings.tourShown = true
                tour = null
            }, onNext = {
                val next = TourStep.entries.getOrNull(step.ordinal + 1)
                if (next == null) settings.tourShown = true
                tour = next
            })
        }
    }
}

/** Son satırın ölçümleri tek satırda; bilinmeyen değer yazılmaz, hiç ölçüm yoksa null. */
fun metricsText(context: Context, pair: com.couchsubs.mobile.core.ShownPair): String? {
    val total = pair.totalMs ?: return null
    val parts = mutableListOf<String>()
    pair.ocrMs?.let { parts.add(context.getString(R.string.metrics_ocr, it)) }
    if (pair.origin == "paket") parts.add(context.getString(R.string.metrics_pack))
    else pair.translationMs?.let { parts.add(context.getString(R.string.metrics_translation, it)) }
    parts.add(context.getString(R.string.metrics_delay, total))
    return parts.joinToString(" · ")
}

fun engineName(context: Context): String = when (Services.settings.engine) {
    com.couchsubs.mobile.settings.EngineChoice.FREE -> context.getString(R.string.engine_free_short)
    com.couchsubs.mobile.settings.EngineChoice.DEEPL -> "DeepL"
    com.couchsubs.mobile.settings.EngineChoice.GEMINI -> "Gemini"
    com.couchsubs.mobile.settings.EngineChoice.OPENAI -> "OpenAI"
    com.couchsubs.mobile.settings.EngineChoice.CLAUDE -> "Claude"
}

/** Çeviri sürerken (tuval Telefon-Calisiyor): süre, paket, canlı satır ve önceki satırlar, sayılar. */
@Composable
private fun RunningScreen(status: LiveStatus, topBar: @Composable () -> Unit, onStop: () -> Unit, onPhoneView: () -> Unit) {
    val context = LocalContext.current
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1000)
            now = System.currentTimeMillis()
        }
    }
    ScreenScaffold(top = topBar, bottom = {
        SecondaryButton(stringResource(R.string.main_phone_view), onClick = onPhoneView)
        if (status.phase == stringResource(R.string.phase_streaming)) ScreenTranslateButton(status)
        DestructiveButton(stringResource(R.string.stop), onClick = onStop)
    }) {
        Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap), verticalAlignment = Alignment.CenterVertically) {
            val elapsed = ((now - status.startedAt).coerceAtLeast(0) / 1000)
            StatusLabel(stringResource(R.string.running_pill, "%d:%02d".format(elapsed / 60, elapsed % 60)), live = true)
            Spacer(Modifier.weight(1f))
            status.packInUse?.let { Pill(stringResource(R.string.running_pack, it), pro = true) }
        }
        Text(status.phase, style = Tokens.Type.caption, color = Tokens.Color.secondary)
        status.error?.let { NoteTile(it) }
        val current = status.recent.firstOrNull()
        // İlk altyazı gelene kadar: kolu açınca PS5'te ana hesap seçilmeli (GitHub #231).
        if (current == null && !Services.settings.xbox) NoteTile(stringResource(R.string.psn_main_account), Tokens.Color.secondary)
        GameSection(status)
        Tile(Modifier.fillMaxWidth()) {
            TileLabel(stringResource(R.string.running_now))
            // Son çeviri altyazı sarısında (içerik), altında özgün metin.
            // Nino: Arapça çeviri sağdan sola, satırın sağına yaslı.
            Text(current?.translation?.let(TargetLanguage::displayText) ?: stringResource(R.string.running_waiting),
                style = Tokens.Type.subtitleCurrent.copy(fontFamily = rememberSubtitleFontFamily(Services.settings.subtitleFont)), modifier = Modifier.fillMaxWidth(),
                color = if (current != null) Tokens.Color.accentText else Tokens.Color.secondary)
            current?.let {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                    Text(it.source, style = Tokens.Type.caption, color = Tokens.Color.secondary, modifier = Modifier.weight(1f))
                    if (it.origin == "paket") Text(stringResource(R.string.running_ready_translation), style = Tokens.Type.caption, color = Tokens.Color.pro)
                }
                // Ölçüm satırı (iPhone ile aynı): "OCR 42 ms · Çeviri 310 ms · Gecikme 520 ms".
                metricsText(context, it)?.let { line -> Text(line, style = Tokens.Type.caption, color = Tokens.Color.secondary) }
            }
        }
        val previous = status.recent.drop(1).take(4)
        if (previous.isNotEmpty()) RowList(previous.map { pair ->
            {
                Row(Modifier.padding(vertical = Tokens.Space.inline), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
                        Text(TargetLanguage.displayText(pair.translation), style = Tokens.Type.line, color = Tokens.Color.secondary,
                            modifier = Modifier.fillMaxWidth())
                        Text(pair.source, style = Tokens.Type.caption, color = Tokens.Color.secondary)
                    }
                    if (pair.origin == "paket") Text(stringResource(R.string.running_ready), style = Tokens.Type.caption, color = Tokens.Color.pro)
                    else Text(status.engineLabel, style = Tokens.Type.caption, color = Tokens.Color.secondary)
                }
            }
        })
        TwoColumns(
            { Tile(it) {
                TileLabel(stringResource(R.string.running_from_pack))
                Text("${status.packLines} / ${status.shownLines}", style = Tokens.Type.title, color = Tokens.Color.text)
            } },
            { Tile(it) {
                TileLabel(stringResource(R.string.main_tvs_label))
                Text(if (Services.settings.target == SubtitleTarget.TV) status.connectedTvs.toString() else stringResource(R.string.main_target_phone),
                    style = Tokens.Type.title, color = Tokens.Color.text)
            } },
        )
    }
}

/** Karartma %70, vurgulanan öğe çevresinde amber çerçeveli 16 yarıçaplı delik; kart surface2. */
@Composable
private fun TourOverlay(step: TourStep, target: Rect?, onSkip: () -> Unit, onNext: () -> Unit) {
    Box(Modifier.fillMaxSize()) {
        Canvas(Modifier.fillMaxSize().graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }) {
            drawRect(Color.Black.copy(alpha = 0.7f))
            target?.let { rect ->
                val pad = 6.dp.toPx()
                val topLeft = Offset(rect.left - pad, rect.top - pad)
                val size = Size(rect.width + 2 * pad, rect.height + 2 * pad)
                val corner = CornerRadius(16.dp.toPx())
                drawRoundRect(Color.Transparent, topLeft, size, corner, blendMode = BlendMode.Clear)
                drawRoundRect(Tokens.Color.accent, topLeft, size, corner, style = Stroke(2.dp.toPx()))
            }
        }
        val above = (target?.top ?: 0f) > 900f
        Column(Modifier.align(if (above) Alignment.TopCenter else Alignment.BottomCenter).safeDrawingPadding().padding(Tokens.Space.screen)
            .background(Tokens.Color.surface2, RoundedCornerShape(Tokens.Radius.tile)).padding(Tokens.Space.tile),
            verticalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("${step.ordinal + 1} / ${TourStep.entries.size}", style = Tokens.Type.caption, color = Tokens.Color.secondary)
                Spacer(Modifier.weight(1f))
                GhostButton(stringResource(R.string.skip), onClick = onSkip)
            }
            Text(stringResource(step.title), style = Tokens.Type.headline, color = Tokens.Color.text)
            Text(stringResource(step.body), style = Tokens.Type.body, color = Tokens.Color.secondary)
            PrimaryButton(stringResource(if (step == TourStep.PROFILE) R.string.tour_done else R.string.next), onClick = onNext)
        }
    }
}

/** Oyun paketleri (ücretsiz): anahtarla toptan, karoya dokunarak paket başına açılıp kapatılır. */
@Composable
fun PacksScreen(onBack: () -> Unit, packInUse: String?) {
    val context = LocalContext.current
    val settings = Services.settings
    val version by Services.packsVersion.collectAsState()
    var catalog by remember { mutableStateOf<List<Services.CatalogEntry>?>(null) }
    var disabled by remember { mutableStateOf(settings.disabledPacks) }
    var packsOn by remember { mutableStateOf(settings.packsEnabled) }
    LaunchedEffect(version) { catalog = withContext(Dispatchers.IO) { Services.catalog(context) } }
    val unlocked = packsOn
    val list = catalog.orEmpty()
    ScreenScaffold(top = {
        TopBar(stringResource(R.string.packs_title), onBack = onBack) {
            Pill(if (list.isEmpty()) stringResource(R.string.packs_free) else stringResource(R.string.packs_free_count, list.size))
        }
    }, bottom = {
        SecondaryButton(stringResource(R.string.packs_refresh)) { Services.refreshPacks(force = true) }
    }) {
        Text(stringResource(R.string.packs_auto), style = Tokens.Type.body, color = Tokens.Color.secondary)
        RowList(listOf({
            RowItem(stringResource(R.string.settings_packs), stringResource(R.string.packs_switch_note)) {
                androidx.compose.material3.Switch(packsOn, { packsOn = it; settings.packsEnabled = it })
            }
        }))
        if (catalog == null) Text(stringResource(R.string.packs_loading), style = Tokens.Type.body, color = Tokens.Color.secondary)
        else if (list.isEmpty()) NoteTile(stringResource(R.string.packs_none_yet), Tokens.Color.secondary)
        list.chunked(2).forEach { row ->
            Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                row.forEach { entry ->
                    val (code, short) = packShort(entry.id, entry.title)
                    val on = entry.id !in disabled
                    val playing = packInUse != null && packInUse == entry.title
                    PackTile(code, short, linesText(context, entry.entries), Modifier.weight(1f).fillMaxHeight(),
                        style = if (playing) TileStyle.ACTIVE else TileStyle.NORMAL, dim = !unlocked || !on,
                        corner = { if (playing) StatusLabel(stringResource(R.string.packs_now)) else if (unlocked && !on) Pill(stringResource(R.string.packs_off)) },
                        onClick = {
                            disabled = if (on) disabled + entry.id else disabled - entry.id
                            settings.disabledPacks = disabled
                        })
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
        ImportedPacksSection()
        Tile(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                TileIcon(Icons.Filled.Refresh)
                Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
                    Text(stringResource(R.string.packs_next), style = Tokens.Type.headline, color = Tokens.Color.text)
                    Text(stringResource(R.string.packs_next_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                }
            }
        }
    }
}

fun open(context: Context, url: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (error: Exception) {
    }
}

/** "Ekranı çevir": oyun ekranının tamamını çevirir; çeviri sürerken ya da sonuçlar ekrandayken dokununca kaldırır (iPhone ile aynı). */
@Composable
fun ScreenTranslateButton(status: LiveStatus, modifier: Modifier = Modifier) {
    val label = when (status.screenState) {
        LiveStatus.ScreenState.IDLE -> R.string.screen_translate
        LiveStatus.ScreenState.WORKING -> R.string.screen_working
        LiveStatus.ScreenState.SHOWN -> R.string.screen_remove
    }
    SecondaryButton(stringResource(label), modifier) { com.couchsubs.mobile.service.TranslationService.translateScreen() }
}
