// SPDX-License-Identifier: AGPL-3.0-only
// Mobil tasarım sistemi (düz bento): design/tokens.json v3 ve TASARIM-MOBIL.md. Uygulama yalnız koyu temadır.
// Değerler yalnız buradan gelir; ekranlar bu dosyadaki bileşenleri kullanır. Parıltı, degrade ve renkli gölge yoktur.
package com.couchsubs.mobile.ui

import android.provider.Settings
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Shapes
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.draw.blur
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

object Tokens {
    /** design/tokens.json v3, koyu görünüm. Parıltı rengi yoktur. */
    object Color {
        // Nino: açık, beyaz cam görünüm; PS mavisi vurgu, lacivert derinlik (design/tokens.json "Nino").
        val bg = androidx.compose.ui.graphics.Color(0xFFEEF3FB)
        val surface = androidx.compose.ui.graphics.Color(0xD9FFFFFF)
        val surface2 = androidx.compose.ui.graphics.Color(0xFFE6EDF8)
        val raised = androidx.compose.ui.graphics.Color(0xFFFFFFFF)
        val border = androidx.compose.ui.graphics.Color(0xBFFFFFFF)
        val borderStrong = androidx.compose.ui.graphics.Color(0xFFD3DEEF)
        val text = androidx.compose.ui.graphics.Color(0xFF0A1430)
        val secondary = androidx.compose.ui.graphics.Color(0xFF55607A)
        val accent = androidx.compose.ui.graphics.Color(0xFF0070D1)
        val accentHi = androidx.compose.ui.graphics.Color(0xFF1A86E8)
        val accentText = androidx.compose.ui.graphics.Color(0xFF0058A8)
        val onAccent = androidx.compose.ui.graphics.Color(0xFFFFFFFF)
        val navy = androidx.compose.ui.graphics.Color(0xFF003085)
        val accentSoft = androidx.compose.ui.graphics.Color(0xFFDDEBFA)
        val pro = androidx.compose.ui.graphics.Color(0xFF00205B)
        val proSoft = androidx.compose.ui.graphics.Color(0xFFE2E8F5)
        val success = androidx.compose.ui.graphics.Color(0xFF1E6B45)
        val warning = androidx.compose.ui.graphics.Color(0xFF9A4A08)
        val danger = androidx.compose.ui.graphics.Color(0xFFB3261E)
        val dangerSoft = androidx.compose.ui.graphics.Color(0xFFFBE4E2)
    }

    /** Telefon ölçüleri (TASARIM-MOBIL.md): kenar 20, karolar arası 12, karo içi 16. */
    object Space {
        val screen = 20.dp
        val gap = 12.dp
        val tile = 16.dp
        val inline = 8.dp
        val hair = 4.dp
    }

    /** Tek köşe ölçeği: karo 16, denetim 12, karo içi kutu 8, etiket 6. */
    object Radius {
        val tile = 22.dp
        val control = 16.dp
        val inner = 8.dp
        val tag = 6.dp
    }

    object Control {
        val button = 52.dp
        val buttonSmall = 44.dp
        val icon = 44.dp
        val row = 52.dp
        val tag = 24.dp
        val tileIcon = 18.dp
        val statusDot = 8.dp
    }

    /** Beş boy (28/22/17/15/13), kalınlık 400–600; altyazı içeriği (subtitle*) dışında başka boy yok. */
    object Type {
        val display = TextStyle(fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp)
        val title = TextStyle(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.SemiBold)
        val headline = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold)
        /** Önceki altyazı satırları: headline boyu, normal kalınlık. */
        val line = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.Normal)
        val body = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Normal)
        val caption = TextStyle(fontSize = 13.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium)
        val subtitleCurrent = TextStyle(fontSize = 28.sp, lineHeight = 36.sp, fontWeight = FontWeight.SemiBold)
        val subtitleLandscape = TextStyle(fontSize = 36.sp, lineHeight = 44.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun CouchSubsTheme(content: @Composable () -> Unit) {
    val c = Tokens.Color
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = c.accent, onPrimary = c.onAccent, secondary = c.pro, onSecondary = c.onAccent,
            background = c.bg, onBackground = c.text, surface = c.surface, onSurface = c.text,
            surfaceVariant = c.surface2, onSurfaceVariant = c.secondary, outline = c.borderStrong,
            error = c.danger, onError = c.onAccent, secondaryContainer = c.surface2, onSecondaryContainer = c.text,
        ),
        typography = Typography(
            displaySmall = Tokens.Type.display, titleLarge = Tokens.Type.title, titleMedium = Tokens.Type.headline,
            bodyLarge = Tokens.Type.body, bodyMedium = Tokens.Type.body, bodySmall = Tokens.Type.caption,
            labelLarge = Tokens.Type.headline, labelMedium = Tokens.Type.caption,
        ),
        shapes = Shapes(
            extraSmall = RoundedCornerShape(Tokens.Radius.tag), small = RoundedCornerShape(Tokens.Radius.inner),
            medium = RoundedCornerShape(Tokens.Radius.control), large = RoundedCornerShape(Tokens.Radius.tile),
            extraLarge = RoundedCornerShape(Tokens.Radius.tile),
        ),
        content = content,
    )
}

/** Her ekranın zemini (Nino): beyazdan buz mavisine degrade ve camın arkasında iki yumuşak mavi ışık. */
@Composable
fun ScreenBackground(content: @Composable BoxScope.() -> Unit) {
    Box(
        Modifier.fillMaxSize().background(
            Brush.linearGradient(listOf(androidx.compose.ui.graphics.Color(0xFFF7FAFF), androidx.compose.ui.graphics.Color(0xFFE3ECFA))),
        ),
    ) {
        // Yumuşak ışıklar: radyal degrade (blur, kutunun kenarında kesik görünüyordu).
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(Brush.radialGradient(listOf(Tokens.Color.accent.copy(alpha = 0.22f), androidx.compose.ui.graphics.Color.Transparent),
                center = androidx.compose.ui.geometry.Offset(size.width * 0.1f, size.height * 0.08f), radius = size.width * 0.9f),
                radius = size.width * 0.9f, center = androidx.compose.ui.geometry.Offset(size.width * 0.1f, size.height * 0.08f))
            drawCircle(Brush.radialGradient(listOf(Tokens.Color.pro.copy(alpha = 0.16f), androidx.compose.ui.graphics.Color.Transparent),
                center = androidx.compose.ui.geometry.Offset(size.width * 0.95f, size.height * 0.95f), radius = size.width * 1.0f),
                radius = size.width * 1.0f, center = androidx.compose.ui.geometry.Offset(size.width * 0.95f, size.height * 0.95f))
        }
        content()
    }
}

/** Mavi-lacivert degrade (birincil düğme, simge kutuları). */
val NinoGradient: Brush get() = Brush.verticalGradient(listOf(Tokens.Color.accentHi, Tokens.Color.navy))

enum class TileStyle { NORMAL, ACTIVE }

/** Karo: düz yüzey ve 1 px çerçeve; etkin (seçili) karo 1 px sarı çerçeveyle belli olur, parlamaz. */
@Composable
fun Tile(modifier: Modifier = Modifier, style: TileStyle = TileStyle.NORMAL, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(Tokens.Radius.tile)
    val border = if (style == TileStyle.ACTIVE) Tokens.Color.accent else Tokens.Color.border
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Column(
        modifier.scale(if (pressed) 0.97f else 1f)
            .shadow(14.dp, shape, ambientColor = Tokens.Color.pro.copy(alpha = 0.10f), spotColor = Tokens.Color.pro.copy(alpha = 0.10f))
            .background(Tokens.Color.surface, shape)
            .border(if (style == TileStyle.ACTIVE) 1.5.dp else 1.dp, border, shape)
            .let { if (onClick != null) it.clickable(interactionSource = interaction, indication = null, onClick = onClick) else it }
            .padding(Tokens.Space.tile),
        verticalArrangement = Arrangement.spacedBy(Tokens.Space.inline),
        content = content,
    )
}

/** Karo başlığı (caption, ikincil renk). */
@Composable
fun TileLabel(text: String, color: Color = Tokens.Color.secondary) = Text(text, style = Tokens.Type.caption, color = color)

/** Birincil düğme (Nino): PS mavisinden laciverte degrade, beyaz yazı, mavi gölge; basılıyken %97 ölçek. */
@Composable
fun PrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    // Nino: ana ekrandaki kaydırma çubuğuyla aynı koyu lacivert hap; üstte ince ışık.
    val shape = RoundedCornerShape(50)
    val ink = androidx.compose.ui.graphics.Color(0xFF0A1430)
    Box(
        modifier.fillMaxWidth().height(58.dp).scale(if (pressed) 0.97f else 1f)
            .let { if (enabled) it.shadow(18.dp, shape, ambientColor = ink.copy(alpha = 0.5f), spotColor = ink.copy(alpha = 0.6f)) else it }
            .background(if (enabled) Brush.verticalGradient(listOf(androidx.compose.ui.graphics.Color(0xFF1B2747), ink)) else Brush.verticalGradient(listOf(Tokens.Color.surface2, Tokens.Color.surface2)), shape)
            .border(1.dp, if (enabled) androidx.compose.ui.graphics.Color.White.copy(alpha = 0.14f) else Tokens.Color.borderStrong, shape)
            .clickable(enabled = enabled, interactionSource = interaction, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Text(text, style = Tokens.Type.headline, color = if (enabled) Tokens.Color.onAccent else Tokens.Color.secondary) }
}

@Composable
fun SecondaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Button(onClick, enabled = enabled, shape = RoundedCornerShape(50), border = BorderStroke(1.dp, Tokens.Color.borderStrong),
        colors = ButtonDefaults.buttonColors(containerColor = Tokens.Color.raised, contentColor = Tokens.Color.text), elevation = null,
        modifier = modifier.fillMaxWidth().height(58.dp)) { Text(text, style = Tokens.Type.headline) }
}

@Composable
fun GhostButton(text: String, modifier: Modifier = Modifier, color: Color = Tokens.Color.accentText, onClick: () -> Unit) {
    TextButton(onClick, modifier = modifier.height(Tokens.Control.buttonSmall)) { Text(text, style = Tokens.Type.headline, color = color) }
}

/** Tehlikeli: kırmızı tonlu zemin, kırmızı yazı, çerçevesiz ("Çeviriyi durdur"). */
@Composable
fun DestructiveButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Button(onClick, shape = RoundedCornerShape(Tokens.Radius.control), elevation = null,
        colors = ButtonDefaults.buttonColors(containerColor = Tokens.Color.dangerSoft, contentColor = Tokens.Color.danger),
        modifier = modifier.fillMaxWidth().height(Tokens.Control.button)) { Text(text, style = Tokens.Type.headline) }
}

@Composable
fun IconSquare(label: String, modifier: Modifier = Modifier, onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        modifier.size(Tokens.Control.icon).background(Tokens.Color.raised, CircleShape)
            .border(1.dp, Tokens.Color.borderStrong, CircleShape)
            .clickable(onClickLabel = label, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}

/** Etiket: 24 yükseklik, 6 köşe, caption; nötr (surface2 + ikincil yazı) ya da oyun paketi için mor ([pro]). */
@Composable
fun Pill(text: String, modifier: Modifier = Modifier, pro: Boolean = false) {
    Box(
        modifier.height(Tokens.Control.tag)
            .background(if (pro) Tokens.Color.proSoft else Tokens.Color.surface2, RoundedCornerShape(Tokens.Radius.tag))
            .padding(horizontal = Tokens.Space.inline),
        contentAlignment = Alignment.Center,
    ) { Text(text, style = Tokens.Type.caption, color = if (pro) Tokens.Color.pro else Tokens.Color.secondary, maxLines = 1) }
}

/** Sistemde "animasyonları kapat" (azaltılmış hareket) açık mı. */
@Composable
fun reducedMotion(): Boolean {
    val context = LocalContext.current
    return remember { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}

/**
 * Durum noktası (8 dp). Yalnız [live] (çeviri canlı) iken 2 sn'de bir genişleyip sönen halka atar; "Bağlı", "Hazır"
 * gibi durumlarda ve azaltılmış harekette durur.
 */
@Composable
fun LiveDot(color: Color = Tokens.Color.success, live: Boolean = false) {
    val animate = live && !reducedMotion()
    Box(Modifier.size(Tokens.Control.statusDot * 2), contentAlignment = Alignment.Center) {
        if (animate) {
            val transition = rememberInfiniteTransition(label = "pulse")
            val ring by transition.animateFloat(0f, 1f, infiniteRepeatable(tween(2000), RepeatMode.Restart), label = "ring")
            Canvas(Modifier.fillMaxSize()) {
                drawCircle(color.copy(alpha = (1 - ring) * 0.7f), radius = size.minDimension / 2 * (0.5f + ring * 0.5f), style = Stroke(2.dp.toPx()))
            }
        }
        Box(Modifier.size(Tokens.Control.statusDot).background(color, CircleShape))
    }
}

/** Durum: nokta + kelime, zeminsiz ("Bağlı", "Çeviri sürüyor · 4:10"). Canlı durum etiket değildir. */
@Composable
fun StatusLabel(text: String, ok: Boolean = true, live: Boolean = false) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
        LiveDot(if (ok) Tokens.Color.success else Tokens.Color.secondary, live = live)
        Text(text, style = Tokens.Type.caption, color = Tokens.Color.text, maxLines = 1)
    }
}

@Composable
fun Field(
    value: String, onChange: (String) -> Unit, label: String, modifier: Modifier = Modifier,
    secret: Boolean = false, keyboard: androidx.compose.foundation.text.KeyboardOptions = androidx.compose.foundation.text.KeyboardOptions.Default,
    /** 1'den büyükse çok satırlı alan (ör. Sorun Bildir açıklaması); en az bu kadar satır yüksekliğinde. */
    lines: Int = 1,
) {
    OutlinedTextField(
        value, onChange, modifier.fillMaxWidth(), label = { Text(label, style = Tokens.Type.caption) }, singleLine = lines <= 1,
        minLines = lines, textStyle = if (lines > 1) Tokens.Type.body else Tokens.Type.headline, shape = RoundedCornerShape(Tokens.Radius.control), keyboardOptions = keyboard,
        visualTransformation = if (secret) androidx.compose.ui.text.input.PasswordVisualTransformation() else VisualTransformation.None,
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = Tokens.Color.raised, unfocusedContainerColor = Tokens.Color.raised,
            focusedBorderColor = Tokens.Color.accent, unfocusedBorderColor = Tokens.Color.borderStrong, cursorColor = Tokens.Color.accent,
            focusedLabelColor = Tokens.Color.secondary, unfocusedLabelColor = Tokens.Color.secondary,
        ),
    )
}

/**
 * Ekran iskeleti: güvenli alan + 20 kenar, isteğe bağlı başlık satırı, kaydırılan içerik ve altta sabit düğme bölgesi
 * (birincil en altta).
 */
@Composable
fun ScreenScaffold(
    top: (@Composable () -> Unit)? = null,
    bottom: (@Composable ColumnScope.() -> Unit)? = null,
    scroll: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    ScreenBackground {
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(Tokens.Space.screen)) {
            if (top != null) {
                top()
                Spacer(Modifier.height(Tokens.Space.gap))
            }
            val state = rememberScrollState()
            Column(
                Modifier.weight(1f).fillMaxWidth().let { if (scroll) it.verticalScroll(state) else it },
                verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap),
                content = content,
            )
            if (bottom != null) {
                Spacer(Modifier.height(Tokens.Space.gap))
                Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap), horizontalAlignment = Alignment.CenterHorizontally, content = bottom)
            }
        }
    }
}

@Composable
fun BodyText(text: String, color: Color = Tokens.Color.secondary, align: TextAlign? = null) =
    Text(text, style = Tokens.Type.body, color = color, textAlign = align)

/** Geniş karonun içindeki 52 yükseklikli satır (ayarlar, profil). */
@Composable
fun RowItem(title: String, value: String? = null, onClick: (() -> Unit)? = null, trailing: (@Composable () -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Tokens.Control.row).let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(vertical = Tokens.Space.hair),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
            Text(title, style = Tokens.Type.headline, color = Tokens.Color.text)
            value?.let { Text(it, style = Tokens.Type.caption, color = Tokens.Color.secondary) }
        }
        trailing?.invoke()
    }
}
