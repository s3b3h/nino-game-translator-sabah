// SPDX-License-Identifier: AGPL-3.0-only
// Nino: Mac'teki iki ana ekran arayüzünün telefon karşılığı (LivingRoomScene.swift, GlassTranslateToggle.swift).
// Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-15.
package com.couchsubs.mobile.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.service.LiveStatus
import kotlinx.coroutines.launch
import kotlin.math.hypot
import kotlin.math.roundToInt

private val FlagRed = Color(0xFFE30A17)
private val FlagDeep = Color(0xFFA80514)
private val LedBlue = Color(0xFF1F5CFF)
private val LedLight = Color(0xFF738CFF)

/** Telefonda ekranda gösterilecek Türkçe satır: şu an görünen, yoksa son çeviri. */
private fun LiveStatus.liveText(): String = current.ifEmpty { recent.firstOrNull()?.translation.orEmpty() }

/**
 * Salon (Mac'teki birinci arayüz). Saydam salon görseli sabit durur; üstüne TV ekranının içi, sehpanın ucundan
 * prize giden kablo ve fiş çizilir. Fiş prize takılınca (dokunarak ya da sürükleyerek) çeviri başlar, TV'de Nino'nun
 * açılış animasyonu oynar, ardından altyazılar akar; mavi LED'ler yalnız fiş takılıyken yanar. Koordinatlar görselin
 * piksel ölçüsündedir (1672×941). Not: konsolun biçimi Sony'nin tasarımına benzer; Play'e göndermeden önce
 * markasız bir çizimle değiştirilmeli (bkz. CLAUDE.md, Marka).
 */
@Composable
fun LivingRoomScene(status: LiveStatus, paired: Boolean, modifier: Modifier = Modifier, onStart: () -> Unit, onStop: () -> Unit, onLocked: () -> Unit) {
    val plugged = status.running
    val reduced = reducedMotion()
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val drag = remember { Animatable(Offset.Zero, Offset.VectorConverter) }
    var splashDone by remember { mutableStateOf(status.running) }
    LaunchedEffect(plugged) { if (plugged && !status.streaming) splashDone = false }
    val leds by animateFloatAsState(if (plugged) 1f else 0f, tween(if (reduced) 0 else 800), label = "leds")
    fun toggle() = if (plugged) onStop() else if (paired) onStart() else onLocked()

    BoxWithConstraints(modifier.fillMaxWidth()) {
        // Sağda fiş için pay bırakılır (fiş görselin sağ kenarına yakın sarkar).
        val canvasWidth = CANVAS_W + 40f
        val sceneWidthPx = with(density) { maxWidth.toPx() }
        val scale = sceneWidthPx / canvasWidth
        val heightDp = with(density) { (CANVAS_H * scale).toDp() } + 8.dp
        fun dp(value: Float) = with(density) { (value * scale).toDp() }
        val base = if (plugged) SOCKET else HANGING
        val plugAt = Offset(base.x + drag.value.x / scale, base.y + drag.value.y / scale)
        val dragging = drag.value != Offset.Zero

        Box(Modifier.fillMaxWidth().height(heightDp).semantics {
            role = Role.Button
            contentDescription = if (plugged) "Fişi çekin, çeviri dursun" else "Fişi takın, Türkçe altyazı açılsın"
            onClick { toggle(); true }
        }) {
            // Mavi LED'ler: görselin arkasında, saydam kenarlarından taşar (bulanıklık yerine katmanlı ışık; Android 8'de de çalışır).
            Canvas(Modifier.fillMaxSize().alpha(leds)) { drawLeds(scale) }
            Image(painterResource(R.drawable.living_room), contentDescription = null,
                modifier = Modifier.offset(0.dp, 0.dp).requiredSize(dp(CANVAS_W), dp(CANVAS_H)).align(Alignment.TopStart))
            // TV ekranı: altta siyah zemin (geçişlerde görseldeki ekran görünmesin), içerik 588 noktalık TV'ye göre çizilip büyütülür.
            Box(Modifier.offset(dp(SCREEN_X), dp(SCREEN_Y)).requiredSize(dp(SCREEN_W), dp(SCREEN_H)).align(Alignment.TopStart)
                .background(Color.Black).clipToBounds(), contentAlignment = Alignment.Center) {
                val virtualW = 588f
                val virtualH = virtualW * SCREEN_H / SCREEN_W
                val factor = with(density) { (SCREEN_W * scale) / virtualW.dp.toPx() }
                Box(Modifier.requiredSize(virtualW.dp, virtualH.dp).graphicsLayer { scaleX = factor; scaleY = factor }) {
                    when {
                        !plugged -> Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
                            Text("NO SIGNAL", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace,
                                letterSpacing = 3.sp, color = Color.White.copy(alpha = 0.28f))
                        }
                        !splashDone -> TvSplash(onFinish = { splashDone = true })
                        else -> LiveTvScreen(status)
                    }
                }
            }
            // Kablo: sehpanın ucundan fişe; çıkıkken aşağı sarkar, takılıyken prize kıvrılır.
            Canvas(Modifier.fillMaxSize()) {
                val s = scale
                val path = Path()
                path.moveTo(CABLE_START.x * s, CABLE_START.y * s)
                if (plugged && !dragging) {
                    val end = Offset(plugAt.x, plugAt.y + 30)
                    path.cubicTo(1620 * s, 720 * s, (end.x + 10) * s, (end.y + 170) * s, end.x * s, end.y * s)
                } else {
                    val end = Offset(plugAt.x, plugAt.y - 30)
                    path.cubicTo(1585 * s, 745 * s, (end.x - 8) * s, (end.y - 70) * s, end.x * s, end.y * s)
                }
                drawPath(path, Color(0xFF101010), style = Stroke(width = maxOf(10 * s, 2.dp.toPx()), cap = StrokeCap.Round))
                drawPlug(plugAt, s, plugged && !dragging, dragging)
            }
            // Dokunma alanları en az 48 dp (fiş görselde küçük kalsa da kolay yakalansın); sahnenin dışına taşmaz.
            val touch = 56.dp
            val touchPx = with(density) { touch.toPx() }
            val widthPx = sceneWidthPx
            val heightPx = with(density) { heightDp.toPx() }
            fun clampedOffset(point: Offset) = IntOffset(
                (point.x * scale - touchPx / 2).coerceIn(0f, widthPx - touchPx).roundToInt(),
                (point.y * scale - touchPx / 2).coerceIn(0f, heightPx - touchPx).roundToInt(),
            )
            // Prize dokunmak da fişi takar/çıkarır.
            Box(Modifier.offset { clampedOffset(SOCKET) }.size(touch).clickable(
                interactionSource = remember { MutableInteractionSource() }, indication = null) { toggle() })
            Box(Modifier.offset { clampedOffset(plugAt) }.size(touch)
                .pointerInput(plugged, paired) {
                    detectDragGestures(
                        onDragEnd = {
                            val end = Offset(base.x + drag.value.x / scale, base.y + drag.value.y / scale)
                            val near = hypot(end.x - SOCKET.x, end.y - SOCKET.y) < 160
                            scope.launch { drag.animateTo(Offset.Zero, spring(dampingRatio = 0.75f)) }
                            if (near != plugged) toggle()
                        },
                        onDragCancel = { scope.launch { drag.animateTo(Offset.Zero) } },
                    ) { change, amount ->
                        change.consume()
                        scope.launch { drag.snapTo(drag.value + amount) }
                    }
                }
                .pointerInput(plugged, paired) { detectTapGestures { toggle() } })
        }
    }
}

/** Sahnenin altındaki tek satırlık ipucu. */
@Composable
fun LivingRoomHint(running: Boolean, paired: Boolean) {
    Text(
        when {
            running -> "Fişi çekin, çeviri dursun"
            paired -> "Fişi prize takın, Türkçe altyazı açılsın"
            else -> "Önce PS5'inizi eşleyin"
        },
        style = Tokens.Type.caption, color = Tokens.Color.secondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
    )
}

/** TV'deki açılış: uygulamanın kendi açılış animasyonu, ekrana sığacak kadar küçültülmüş. */
@Composable
private fun TvSplash(onFinish: () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize().clipToBounds(), contentAlignment = Alignment.Center) {
        val virtualW = 820.dp
        val virtualH = 424.dp
        val factor = maxWidth / virtualW
        Box(Modifier.requiredSize(virtualW, virtualH).graphicsLayer { scaleX = factor; scaleY = factor }) { NinoSplash(onFinish) }
    }
}

/** Çeviri açık: oyun sahnesi gibi koyu ekran, sol üstte CANLI, altta Türkçe satır ya da PS5'in durumu. */
@Composable
fun LiveTvScreen(status: LiveStatus, modifier: Modifier = Modifier) {
    val text = status.liveText()
    Box(modifier.fillMaxSize().background(Brush.linearGradient(listOf(Color(0xFF171F3D), Color(0xFF26172E)))).padding(18.dp)) {
        Row(Modifier.align(Alignment.TopStart).background(Color.Black.copy(alpha = 0.4f), RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.size(8.dp).background(FlagRed, CircleShape))
            Text("CANLI", fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = Color.White)
        }
        Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp)) {
            when {
                // PS5 görüntüsü gelmiyorsa altyazı yerine bağlantının durumu yazılır.
                !status.streaming -> Text(status.phase.ifEmpty { "PS5'e bağlanılıyor…" }, fontSize = 15.sp, fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.7f), textAlign = TextAlign.Center)
                text.isEmpty() -> Text("Sıradaki altyazı bekleniyor…", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.55f))
                else -> Text(text, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, color = Color.White, textAlign = TextAlign.Center,
                    modifier = Modifier.background(Color.Black.copy(alpha = 0.72f), RoundedCornerShape(10.dp)).padding(horizontal = 16.dp, vertical = 8.dp))
            }
        }
    }
}

private fun DrawScope.drawLeds(s: Float) {
    // TV'nin arkasından duvara vuran ışık: içten dışa soluklaşan katmanlar.
    val tvX = 139f; val tvY = 27f; val tvW = 1171f; val tvH = 621f
    for (i in 6 downTo 0) {
        val grow = 10f + i * 12f
        drawRoundRect(LedBlue.copy(alpha = 0.06f + 0.05f * (6 - i) / 6f), Offset((tvX - grow) * s, (tvY - grow) * s),
            Size((tvW + 2 * grow) * s, (tvH + 2 * grow) * s), CornerRadius((30f + grow) * s))
    }
    drawRoundRect(LedLight.copy(alpha = 0.55f), Offset((tvX - 5) * s, (tvY - 5) * s), Size((tvW + 10) * s, (tvH + 10) * s), CornerRadius(12 * s))
    // Sehpanın altındaki şerit.
    val standX = 49f; val standW = 1502f; val standBottom = 873f
    for (i in 5 downTo 0) {
        val h = 10f + i * 8f
        drawRoundRect(LedBlue.copy(alpha = 0.08f + 0.06f * (5 - i) / 5f), Offset((standX + 30 - i * 4) * s, (standBottom - h / 2) * s),
            Size((standW - 60 + i * 8) * s, h * s), CornerRadius(h / 2 * s))
    }
    drawRoundRect(LedLight, Offset((standX + 45) * s, (standBottom - 4) * s), Size((standW - 90) * s, 6 * s), CornerRadius(3 * s))
}

/** Fiş: çıkıkken siyah gövde ve iki metal uç aşağı bakar; takılıyken prizin önünde yuvarlak siyah kapak. */
private fun DrawScope.drawPlug(at: Offset, s: Float, inSocket: Boolean, lifted: Boolean) {
    val c = Offset(at.x * s, at.y * s)
    if (inSocket) {
        val r = 29 * s
        drawCircle(Color.Black.copy(alpha = 0.35f), r * 1.08f, c + Offset(0f, 4 * s))
        drawCircle(Brush.linearGradient(listOf(Color(0xFF3D3D3D), Color(0xFF0A0A0A)), c - Offset(r, r), c + Offset(r, r)), r, c)
        drawCircle(Color.White.copy(alpha = 0.18f), r, c, style = Stroke(1.5f * s))
        return
    }
    val k = if (lifted) 1.08f else 1f
    val top = c.y - 44 * s * k
    drawRoundRect(Color(0xFF0F0F0F), Offset(c.x - 8 * s * k, top), Size(16 * s * k, 14 * s * k), CornerRadius(6 * s))
    drawRoundRect(Brush.horizontalGradient(listOf(Color(0xFF383838), Color(0xFF0A0A0A)), c.x - 18 * s, c.x + 18 * s),
        Offset(c.x - 18 * s * k, top + 14 * s * k), Size(36 * s * k, 50 * s * k), CornerRadius(9 * s))
    val prong = Brush.horizontalGradient(listOf(Color(0xFFEBEBEB), Color(0xFF999999)))
    listOf(-10f, 10f).forEach { dx ->
        drawRoundRect(prong, Offset(c.x + (dx - 3) * s * k, top + 64 * s * k), Size(6 * s * k, 24 * s * k), CornerRadius(3 * s))
    }
}

private const val CANVAS_W = 1672f
private const val CANVAS_H = 941f
private const val SCREEN_X = 149f
private const val SCREEN_Y = 40f
private const val SCREEN_W = 1151f
private const val SCREEN_H = 595f
private val SOCKET = Offset(1564f, 378f)
private val CABLE_START = Offset(1550f, 734f)
private val HANGING = Offset(1600f, 885f)

/**
 * Cam düğme (Mac'teki ikinci arayüz): hap biçimli iz ve üstünde kayan cam küre. Kapalıyken küre solda, iz mavi-gri;
 * sürükleyip ya da dokunup açınca küre sağa kayar, iz bayrak kırmızısına döner, kürede ay yıldız belirir.
 */
@Composable
fun GlassTranslateToggle(running: Boolean, starting: Boolean, paired: Boolean, modifier: Modifier = Modifier,
                         onStart: () -> Unit, onStop: () -> Unit, onLocked: () -> Unit) {
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val drag = remember { Animatable(0f) }
    fun toggle() = if (running) onStop() else if (paired) onStart() else onLocked()
    BoxWithConstraints(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        val width = minOf(maxWidth, 340.dp)
        val height = 76.dp
        val knob = 94.dp
        val travel = with(density) { (width - height).toPx() }
        val base = if (running) travel else 0f
        val animated by animateFloatAsState(base, spring(dampingRatio = 0.8f, stiffness = 300f), label = "knob")
        val x = (animated + drag.value).coerceIn(0f, travel)
        val progress = if (travel > 0) x / travel else 0f
        Box(Modifier.size(width, knob).semantics {
            role = Role.Switch
            contentDescription = if (running) "Çeviriyi durdur" else "Çeviriyi başlat"
            onClick { toggle(); true }
        }.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { toggle() },
            contentAlignment = Alignment.CenterStart) {
            // İz
            val shape = RoundedCornerShape(50)
            Box(Modifier.size(width, height)
                .shadow(18.dp, shape, ambientColor = if (progress > 0.5f) FlagRed else Color(0xFF4D5C85), spotColor = if (progress > 0.5f) FlagRed else Color(0xFF4D5C85))
                .background(Brush.verticalGradient(listOf(Color(0xFF788CB3), Color(0xFF4D5C85))), shape)
                .background(Brush.verticalGradient(listOf(FlagRed.copy(alpha = progress), FlagDeep.copy(alpha = progress))), shape)
                .background(Brush.verticalGradient(0f to Color.White.copy(alpha = 0.35f), 0.5f to Color.Transparent), shape)
                .border(1.dp, Color.White.copy(alpha = 0.45f), shape))
            // Yazılar
            Box(Modifier.size(width, height)) {
                Column(Modifier.align(Alignment.CenterEnd).padding(end = 26.dp).alpha(1 - progress), horizontalAlignment = Alignment.End) {
                    Text(if (starting) "Bağlanıyor…" else if (paired) "Açın" else "PS5'i eşleyin", fontSize = 21.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                    Text(if (paired) "Türkçe altyazı" else "Kuruluma başlamak için dokunun", fontSize = 12.sp, color = Color.White.copy(alpha = 0.8f))
                }
                Column(Modifier.align(Alignment.CenterStart).padding(start = 28.dp).alpha(progress)) {
                    Text("Türkçe", fontSize = 25.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    Text("Altyazılar açık", fontSize = 12.sp, color = Color.White.copy(alpha = 0.85f))
                }
            }
            // Küre: izden büyük, iki uçta dışarı taşar.
            val knobShift = with(density) { (x - (knob - height).toPx() / 2).roundToInt() }
            Box(Modifier.offset { IntOffset(knobShift, 0) }.size(knob)
                .pointerInput(running, paired) {
                    detectHorizontalDragGestures(onDragEnd = {
                        val end = base + drag.value
                        scope.launch { drag.animateTo(0f, spring(dampingRatio = 0.78f)) }
                        if (!running && end > travel * 0.6f) toggle() else if (running && end < travel * 0.4f) toggle()
                    }) { change, amount -> change.consume(); scope.launch { drag.snapTo(drag.value + amount) } }
                }, contentAlignment = Alignment.Center) {
                GlassKnob(progress, starting)
            }
        }
    }
}

@Composable
private fun GlassKnob(progress: Float, starting: Boolean) {
    Box(Modifier.fillMaxSize().shadow(14.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.3f)), contentAlignment = Alignment.Center) {
        // Kürenin arkasındaki renkli disk (iz rengini taşır).
        Box(Modifier.fillMaxSize(0.62f).background(Color(0xFF5C6E99), CircleShape).background(FlagRed.copy(alpha = progress), CircleShape))
        if (starting) CircularProgressIndicator(Modifier.size(26.dp), color = Color.White, strokeWidth = 3.dp)
        else {
            Icon(Icons.Filled.PowerSettingsNew, null, tint = Color.White, modifier = Modifier.size(26.dp).alpha(1 - progress))
            Canvas(Modifier.size(42.dp).alpha(progress).scale(0.7f + 0.3f * progress)) { drawCrescentStar(FlagRed) }
        }
        // Cam: buzlu dolgu, kenar ışığı ve sol üstte parlama.
        Canvas(Modifier.fillMaxSize()) {
            val r = size.minDimension / 2
            drawCircle(Color.White.copy(alpha = 0.16f), r)
            drawCircle(Brush.linearGradient(listOf(Color.White.copy(alpha = 0.95f), Color.White.copy(alpha = 0.15f), Color.White.copy(alpha = 0.6f)),
                Offset.Zero, Offset(size.width, size.height)), r - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
            drawOval(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.65f), Color.Transparent), size.height * 0.08f, size.height * 0.36f),
                Offset(size.width * 0.1f, size.height * 0.08f), Size(size.width * 0.55f, size.height * 0.28f))
        }
    }
}

/** Bayraktaki ay yıldız: beyaz ay (iç daire zemin rengiyle oyulur) ve ucu aya bakan beş köşeli yıldız. */
private fun DrawScope.drawCrescentStar(background: Color) {
    val s = size.minDimension
    val r = s * 0.42f
    drawCircle(Color.White, r, Offset(s * 0.42f, s / 2))
    drawCircle(background, r * 0.8f, Offset(s * 0.42f + r * 0.32f, s / 2))
    val center = Offset(s * 0.8f, s / 2)
    val outer = s * 0.17f
    val inner = outer * 0.382f
    val star = Path()
    for (i in 0 until 10) {
        val angle = Math.PI + i * Math.PI / 5
        val radius = if (i % 2 == 0) outer else inner
        val point = Offset(center.x + (kotlin.math.cos(angle) * radius).toFloat(), center.y + (kotlin.math.sin(angle) * radius).toFloat())
        if (i == 0) star.moveTo(point.x, point.y) else star.lineTo(point.x, point.y)
    }
    star.close()
    drawPath(star, Color.White)
}

/** Arayüz seçimindeki küçük önizleme kartları için: Salon görselinin küçük hali. */
@Composable
fun LivingRoomThumbnail(modifier: Modifier = Modifier) {
    Image(painterResource(R.drawable.living_room), contentDescription = null, modifier = modifier)
}

/** Cam düğmenin küçük, etkileşimsiz önizlemesi (açık hali). */
@Composable
fun GlassToggleThumbnail(modifier: Modifier = Modifier) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Box(Modifier.widthIn(max = 130.dp).fillMaxWidth().height(34.dp)
            .background(Brush.verticalGradient(listOf(FlagRed, FlagDeep)), RoundedCornerShape(50))
            .border(1.dp, Color.White.copy(alpha = 0.45f), RoundedCornerShape(50)), contentAlignment = Alignment.CenterEnd) {
            Text("Türkçe", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White,
                modifier = Modifier.align(Alignment.CenterStart).padding(start = 12.dp))
            Box(Modifier.padding(end = 2.dp).size(30.dp).background(Color.White.copy(alpha = 0.3f), CircleShape)
                .border(1.5.dp, Color.White.copy(alpha = 0.9f), CircleShape), contentAlignment = Alignment.Center) {
                Canvas(Modifier.size(16.dp)) { drawCrescentStar(FlagRed) }
            }
        }
    }
}
