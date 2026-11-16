// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import com.couchsubs.mobile.withInterfaceLanguage
import com.couchsubs.mobile.core.TargetLanguage
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.heightIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.core.SubtitleTextColor
import com.couchsubs.mobile.service.LiveState
import kotlinx.coroutines.delay

/**
 * Altyazı bu telefonun ekranında (tuval Telefon-Altyazi): yatay, siyah zeminde büyük yazı; üstte durum hapı ve kapat.
 * Ekran açık kalır; bir süre sonra parlaklık kısılır (oyun çoğunlukla karanlık odada oynanır).
 */
private const val DIMMED = 0.35f
private val SUBTITLE_WHITE = Color(0xFFFFFFFF)
private val SUBTITLE_YELLOW = Color(0xFFFFD54A) // iPhone ile aynı

/** Satır ekrana sığmazsa (uzun cümle, büyük yazı boyu) yazı sığana kadar küçülür; en çok yarıya iner. */
@Composable
private fun FittingText(text: String, style: TextStyle, color: Color, modifier: Modifier) {
    var factor by remember(text, style) { mutableFloatStateOf(1f) }
    Text(text, modifier = modifier, color = color, textAlign = TextAlign.Center,
        style = style.copy(fontSize = style.fontSize * factor, lineHeight = style.lineHeight * factor),
        onTextLayout = { layout ->
            if (layout.hasVisualOverflow && factor > 0.5f) factor = (factor * 0.9f).coerceAtLeast(0.5f)
        })
}

class PhoneSubtitleActivity : ComponentActivity() {
    override fun attachBaseContext(newBase: android.content.Context) = super.attachBaseContext(newBase.withInterfaceLanguage())

    /** Sistemin parlaklığı (0–1); okunamazsa kısılacak değerin kendisi. */
    private fun systemBrightness(): Float = try {
        android.provider.Settings.System.getInt(contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS) / 255f
    } catch (_: Exception) {
        DIMMED
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Uygulama hep koyu; sistem açık temadayken de durum çubuğu simgeleri açık renk kalsın.
        enableEdgeToEdge(SystemBarStyle.dark(android.graphics.Color.TRANSPARENT), SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        val settings = Services.settings
        // Yalnız geliştirici derlemesinde: ekran görüntüsü ve deneme için örnek satır (adb ile "nino.demoLine").
        if (com.couchsubs.mobile.BuildConfig.DEBUG) intent.getStringExtra("nino.demoLine")?.let { line ->
            LiveState.update { it.copy(current = line, running = true) }
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // Nino: saat ve bildirim simgeleri gizlenir (iPhone'daki gibi); kenardan kaydırınca bir an görünür.
        androidx.core.view.WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(androidx.core.view.WindowInsetsCompat.Type.systemBars())
        }
        // Nino: zemin her zaman siyah; uygulamanın (açık temalı) yazı renkleri burada okunmaz, altyazı renkleri sabittir.
        val color = if (settings.textColor == SubtitleTextColor.YELLOW) SUBTITLE_YELLOW else SUBTITLE_WHITE
        val scale = settings.subtitleScale / 100f
        val streaming = getString(R.string.phase_streaming)
        setContent {
            CouchSubsTheme {
                val status by LiveState.status.collectAsState()
                LaunchedEffect(Unit) {
                    delay(10_000)
                    // Nino: yalnız kısılır; parlaklığı zaten düşük olanınki yükseltilmez.
                    window.attributes = window.attributes.apply { screenBrightness = minOf(DIMMED, systemBrightness()) }
                }
                Box(Modifier.fillMaxSize().background(Color.Black).safeDrawingPadding().padding(Tokens.Space.screen)) {
                    Row(Modifier.fillMaxWidth().align(Alignment.TopCenter), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                        val connected = status.running && status.phase == streaming
                        // Nino: bu ekran kullanıcının tek ekranı; bağlı değilse nedeni yazılır ("PS5 kapalı" gibi).
                        val label = when {
                            connected -> stringResource(R.string.subtitle_connected)
                            status.error != null -> status.error!!
                            status.running && status.phase.isNotEmpty() -> status.phase
                            else -> stringResource(R.string.subtitle_waiting)
                        }
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
                            LiveDot(if (connected) Tokens.Color.success else Color.White.copy(alpha = 0.4f), live = connected)
                            Text(label, style = Tokens.Type.caption, color = Color.White.copy(alpha = 0.75f), maxLines = 1,
                                overflow = TextOverflow.Ellipsis)
                        }
                        status.packInUse?.let { Pill(stringResource(R.string.running_pack, it), pro = true) }
                        Spacer(Modifier.weight(1f))
                        IconAction(Icons.Filled.Close, stringResource(R.string.close)) { finish() }
                    }
                    BoxWithConstraints(Modifier.fillMaxSize().padding(vertical = Tokens.Space.screen * 2)) {
                        val room = maxHeight
                        Column(Modifier.align(Alignment.Center).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                            val style = Tokens.Type.subtitleLandscape
                            val previous = status.recent.getOrNull(1)?.translation
                            val current = status.current.ifEmpty { if (status.running) "" else "Nino" }
                            // Önceki satır yalnız yer varsa ve kısa bir satırken gösterilir; asıl satıra yer açılır.
                            if (previous != null && status.current.isNotEmpty() && previous != status.current && current.length < 90) Text(TargetLanguage.displayText(previous),
                                style = style.copy(fontSize = style.fontSize * scale * 0.8f, lineHeight = style.lineHeight * scale * 0.8f),
                                color = color.copy(alpha = 0.4f), textAlign = TextAlign.Center, maxLines = 2,
                                overflow = TextOverflow.Ellipsis)
                            FittingText(TargetLanguage.displayText(current), style.copy(fontSize = style.fontSize * scale, lineHeight = style.lineHeight * scale),
                                color, Modifier.fillMaxWidth().heightIn(max = room))
                        }
                    }
                    Text(stringResource(R.string.subtitle_screen_note), style = Tokens.Type.caption, color = Color.White.copy(alpha = 0.45f),
                        modifier = Modifier.align(Alignment.BottomCenter))
                }
            }
        }
    }
}
