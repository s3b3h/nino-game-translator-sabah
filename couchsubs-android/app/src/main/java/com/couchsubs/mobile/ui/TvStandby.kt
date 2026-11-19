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
import androidx.compose.runtime.remember
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
        Text(hint, fontSize = 13.sp, lineHeight = 19.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace,
            letterSpacing = if (TargetLanguage.containsArabic(hint)) 0.sp else 2.sp, color = Color.White.copy(alpha = 0.4f),
            textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 40.dp))
        if (downloads != null) DownloadHud(downloads, Modifier.align(Alignment.TopEnd).padding(18.dp))
    }
}

private val HudGreen = Color(0xFF7BE87B)

/**
 * Toplam indirme göstergesi. Oyunlardaki para göstergesi gibi: kalın, hafif eğik, siyah çerçeveli; üstte küçük beyaz
 * başlık, altında yeşil sayı. Yazı tipi sistemin dar ve en kalın yazısıdır (sans-serif-condensed); oyunun kendi logosu
 * ya da yazı tipi kullanılmaz. Sayı olduğu gibi yazılır (binlik ayırıcı arayüz dilinin biçiminde).
 */
@Composable
internal fun DownloadHud(total: Int, modifier: Modifier = Modifier) {
    val title = stringResource(R.string.nino_total_downloads)
    // Arap harflerinde eğim ve harf aralığı harfleri bozar.
    val arabic = TargetLanguage.containsArabic(title)
    val number = DownloadCounter.format(total, LocalConfiguration.current.locales[0])
    val family = remember { FontFamily(Typeface.create("sans-serif-condensed", Typeface.BOLD)) }
    val style = TextStyle(fontFamily = family, fontWeight = FontWeight.Black,
        textGeometricTransform = if (arabic) null else TextGeometricTransform(skewX = -0.12f),
        platformStyle = PlatformTextStyle(includeFontPadding = false))
    Column(modifier.clearAndSetSemantics { contentDescription = "$title $number" },
        horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        OutlinedText(title, style.copy(fontSize = 11.sp, letterSpacing = if (arabic) 0.sp else 0.8.sp), Color.White, 1.dp)
        OutlinedText(number, style.copy(fontSize = 27.sp, letterSpacing = TextUnit.Unspecified), HudGreen, 1.5.dp)
    }
}

/** Siyah çerçeveli yazı: altta derinlik gölgesi, çevresinde [weight] kalınlığında siyah çerçeve, üstte renkli dolgu. */
@Composable
private fun OutlinedText(text: String, style: TextStyle, color: Color, weight: Dp) {
    val outline = with(LocalDensity.current) { Stroke(width = (weight * 2).toPx(), join = StrokeJoin.Round) }
    Box {
        Text(text, style = style.copy(drawStyle = outline), color = Color.Black.copy(alpha = 0.9f), maxLines = 1, softWrap = false,
            modifier = Modifier.offset(y = weight + 1.dp))
        Text(text, style = style.copy(drawStyle = outline), color = Color.Black, maxLines = 1, softWrap = false)
        Text(text, style = style, color = color, maxLines = 1, softWrap = false)
    }
}
