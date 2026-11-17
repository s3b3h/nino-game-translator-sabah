// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import android.content.res.AssetManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import com.couchsubs.mobile.R
import com.couchsubs.mobile.core.SubtitleFont

/**
 * Altyazı yazı tipleri (TV sayfasıyla aynı OFL dosyaları; build.gradle assets/fonts'a kopyalar): Aksiyon = Barlow
 * Condensed, Modern = Barlow, Yuvarlak = Nunito, Sade = cihazın yazı tipi. Bu yazı tiplerinde olmayan harfler (Arapça,
 * Tayca, Hintçe) Android'in kendi yedek yazı tiplerinden çizilir.
 */
object SubtitleFonts {
    @OptIn(ExperimentalTextApi::class)
    fun family(font: SubtitleFont, assets: AssetManager): FontFamily = when (font) {
        SubtitleFont.SYSTEM -> FontFamily.Default
        SubtitleFont.CONDENSED -> FontFamily(
            Font("fonts/BarlowCondensed-SemiBold.ttf", assets, FontWeight.SemiBold),
            Font("fonts/BarlowCondensed-Bold.ttf", assets, FontWeight.Bold),
        )
        SubtitleFont.MODERN -> FontFamily(
            Font("fonts/Barlow-SemiBold.ttf", assets, FontWeight.SemiBold),
            Font("fonts/Barlow-Bold.ttf", assets, FontWeight.Bold),
        )
        // Değişken yazı tipi tek kalınlıkla: Compose aynı dosyadan yüklenen yazı tipini yola göre önbelleğe aldığından
        // birden çok kalınlık hepsi ilk yüklenenle (400) çiziliyordu. Altyazı kalınlığı (SemiBold) sabit.
        SubtitleFont.ROUNDED -> FontFamily(
            Font("fonts/Nunito-Variable.ttf", assets, FontWeight.SemiBold, variationSettings = FontVariation.Settings(FontVariation.weight(650))),
        )
    }

    /** Ayarlar'daki sıra: varsayılan Aksiyon en başta. */
    val choices = listOf(SubtitleFont.CONDENSED, SubtitleFont.MODERN, SubtitleFont.ROUNDED, SubtitleFont.SYSTEM)

    fun nameRes(font: SubtitleFont): Int = when (font) {
        SubtitleFont.CONDENSED -> R.string.settings_font_condensed
        SubtitleFont.MODERN -> R.string.settings_font_modern
        SubtitleFont.ROUNDED -> R.string.settings_font_rounded
        SubtitleFont.SYSTEM -> R.string.settings_font_system
    }
}

@Composable
fun rememberSubtitleFontFamily(font: SubtitleFont): FontFamily {
    val assets = LocalContext.current.assets
    return remember(font) { SubtitleFonts.family(font, assets) }
}
