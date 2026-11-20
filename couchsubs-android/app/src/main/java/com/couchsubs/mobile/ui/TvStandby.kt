// SPDX-License-Identifier: AGPL-3.0-only
// Nino: salondaki TV'nin bekleme ekranı ve toplam indirme göstergesi (Mac: TVStandbyScreen, DownloadHUD).
package com.couchsubs.mobile.ui

import android.graphics.Typeface
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.pow
import kotlin.math.roundToInt
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextGeometricTransform
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.core.DownloadCounter
import com.couchsubs.mobile.core.TargetLanguage

/**
 * Fiş takılı değilken TV ekranı. Ortada ne yapılacağı ("Çalıştırmak için fişi prize sürükleyiniz"; eskiden "SİNYAL
 * YOK"), sağ üstte toplam indirme ([downloads] yoksa gösterge görünmez). Yazı kaynakta büyük harfle durur (Türkçedeki
 * İ için).
 */
@Composable
internal fun TvStandbyScreen(downloads: Int?) {
    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        val hint = stringResource(R.string.nino_plug_drag_hint)
        // Harf aralığı Arap harflerinin birleşmesini bozar.
        // Nino: telefonda TV küçük çizilir; yazı iPhone'daki kadar okunaklı ve iki satır olsun (420 noktalık TV'de).
        Text(hint, fontSize = 16.sp, lineHeight = 23.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace,
            letterSpacing = if (TargetLanguage.containsArabic(hint)) 0.sp else 2.5.sp, color = Color.White.copy(alpha = 0.45f),
            textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 56.dp))
        if (downloads != null) DownloadHud(downloads, Modifier.align(Alignment.TopEnd).padding(18.dp))
    }
}

private val HudGreen = Color(0xFF7BE87B)

/**
 * Toplam indirme göstergesi. Oyunlardaki para göstergesi gibi: kalın, hafif eğik, siyah çerçeveli; üstte küçük beyaz
 * başlık, altında yeşil sayı. Yazı tipi sistemin dar ve en kalın yazısıdır (sans-serif-condensed); oyunun kendi logosu
 * ya da yazı tipi kullanılmaz. Sayı olduğu gibi yazılır (binlik ayırıcı arayüz dilinin biçiminde).
 * [countsUp] (Mac: DownloadHUD countsUp; kullanıcı isteği, 21 Kasım 2026): göründüğünde sayı 1, 2, 3 diye yavaş başlar
 * (280 ms arayla), sonra hızlanarak (1,55 sn, p^2,6) toplam sayıya fırlar; sonda oyunun "görev tamam" yazısı gibi büyüyüp
 * yeşil parlayarak yerine oturur. Sistemde animasyonlar kapalıysa sayı doğrudan yazılır.
 */
@Composable
internal fun DownloadHud(total: Int, modifier: Modifier = Modifier, countsUp: Boolean = false) {
    val title = stringResource(R.string.nino_total_downloads)
    // Arap harflerinde eğim ve harf aralığı harfleri bozar.
    val arabic = TargetLanguage.containsArabic(title)
    val locale = LocalConfiguration.current.locales[0]
    val reduced = reducedMotion()
    // Sayım sürerken sayaç yenilenirse (aralıklı istek) sayım baştan başlamaz; yeni toplama doğru sürer.
    val latestTotal by rememberUpdatedState(total)
    var shown by remember { mutableStateOf<Int?>(null) }
    val punch = remember { Animatable(0f) }
    LaunchedEffect(countsUp) {
        if (!countsUp || reduced || latestTotal <= 3) { shown = null; return@LaunchedEffect }
        shown = 0
        // İlk üç sayı tek tek görünür, sonra hız katlanarak artar (toplam ~2,4 sn).
        for (step in 1..3) {
            shown = step
            delay(280)
        }
        val startNanos = withFrameNanos { it }
        while (true) {
            val now = withFrameNanos { it }
            val p = ((now - startNanos) / 1_000_000_000.0 / 1.55).coerceAtMost(1.0)
            shown = maxOf(3, (p.pow(2.6) * latestTotal).roundToInt())
            if (p >= 1.0) break
        }
        shown = null
        // Mac: .spring(response: 0.22, dampingFraction: 0.45), 260 ms sonra .spring(response: 0.45, dampingFraction: 0.6).
        launch { punch.animateTo(1f, spring(dampingRatio = 0.45f, stiffness = 816f)) }
        delay(260)
        punch.animateTo(0f, spring(dampingRatio = 0.6f, stiffness = 195f))
    }
    val number = DownloadCounter.format(shown ?: total, locale)
    val finalNumber = DownloadCounter.format(total, locale)
    val family = remember { FontFamily(Typeface.create("sans-serif-condensed", Typeface.BOLD)) }
    val style = TextStyle(fontFamily = family, fontWeight = FontWeight.Black,
        textGeometricTransform = if (arabic) null else TextGeometricTransform(skewX = -0.12f),
        platformStyle = PlatformTextStyle(includeFontPadding = false))
    // Büyüme sayının arka kenarından (Mac: anchor .trailing; sağdan sola dillerde sol kenar).
    val trailingX = if (LocalLayoutDirection.current == LayoutDirection.Rtl) 0f else 1f
    Column(modifier.clearAndSetSemantics { contentDescription = "$title $finalNumber" },
        horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        OutlinedText(title, style.copy(fontSize = 11.sp, letterSpacing = if (arabic) 0.sp else 0.8.sp), Color.White, 1.dp)
        val grow = punch.value
        Box(Modifier.graphicsLayer {
            val k = 1f + 0.32f * grow
            scaleX = k; scaleY = k
            transformOrigin = TransformOrigin(trailingX, 0.5f)
        }) {
            OutlinedText(number, style.copy(fontSize = 27.sp, letterSpacing = TextUnit.Unspecified), HudGreen, 1.5.dp, glow = grow)
        }
    }
}

/** Siyah çerçeveli yazı: altta derinlik gölgesi, çevresinde [weight] kalınlığında siyah çerçeve, üstte renkli dolgu. */
@Composable
private fun OutlinedText(text: String, style: TextStyle, color: Color, weight: Dp, glow: Float = 0f) {
    val density = LocalDensity.current
    val outline = with(density) { Stroke(width = (weight * 2).toPx(), join = StrokeJoin.Round) }
    // [glow]: sayının çevresindeki yeşil ışık (0 yok, 1 en parlak; Mac: shadow radius 14, opaklık 0,95).
    val fill = if (glow <= 0f) style else style.copy(shadow = Shadow(color.copy(alpha = 0.95f * glow.coerceAtMost(1f)), Offset.Zero,
        with(density) { (14.dp * glow).toPx() }.coerceAtLeast(0.1f)))
    Box {
        Text(text, style = style.copy(drawStyle = outline), color = Color.Black.copy(alpha = 0.9f), maxLines = 1, softWrap = false,
            modifier = Modifier.offset(y = weight + 1.dp))
        Text(text, style = style.copy(drawStyle = outline), color = Color.Black, maxLines = 1, softWrap = false)
        Text(text, style = fill, color = color, maxLines = 1, softWrap = false)
    }
}
