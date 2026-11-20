// SPDX-License-Identifier: AGPL-3.0-only
// Nino: açılış animasyonu ve ana ekrandaki büyük Başlat düğmesi (Mac uygulamasıyla aynı dil).
// Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-14.
package com.couchsubs.mobile.ui

import com.couchsubs.mobile.core.TargetLanguage
import com.couchsubs.mobile.Services
import androidx.compose.ui.res.stringResource
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.material.icons.filled.ClosedCaption
import androidx.compose.material.icons.filled.KeyboardDoubleArrowRight
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.R
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Açılış: logo bulanıktan netleşerek büyür, arkasında mavi halka döner, logodaki bayrak kırmızı ışıkla parlar,
 * ardından "Nino" ve "Oyunlarınız artık Türkçe." belirir. Yaklaşık 2,3 sn sonra [onFinish].
 */
@Composable
fun NinoSplash(onFinish: () -> Unit) {
    val reduced = reducedMotion()
    val logo = remember { Animatable(0f) }
    val text = remember { Animatable(0f) }
    val flag = remember { Animatable(0f) }
    val leave = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        if (reduced) { logo.snapTo(1f); text.snapTo(1f); delay(900); onFinish(); return@LaunchedEffect }
        launch { logo.animateTo(1f, spring(dampingRatio = 0.62f, stiffness = 120f)) }
        delay(650)
        launch { text.animateTo(1f, tween(600, easing = FastOutSlowInEasing)) }
        repeat(2) {
            flag.animateTo(1f, tween(500))
            flag.animateTo(0.15f, tween(500))
        }
        delay(250)
        leave.animateTo(1f, tween(420))
        onFinish()
    }
    val spin = rememberInfiniteTransition(label = "spin")
    val angle by spin.animateFloat(0f, 360f, infiniteRepeatable(tween(2400, easing = LinearEasing), RepeatMode.Restart), label = "angle")

    ScreenBackground {
        Column(
            Modifier.fillMaxSize().alpha(1f - leave.value).scale(1f + leave.value * 0.06f),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(contentAlignment = Alignment.Center) {
                // Dönen ışık halkası
                Canvas(Modifier.size(270.dp).rotate(angle).alpha(logo.value)) {
                    drawCircle(
                        Brush.sweepGradient(listOf(Color.Transparent, Tokens.Color.accent, Tokens.Color.accentHi, Color.Transparent, Color.Transparent)),
                        style = Stroke(3.dp.toPx()),
                    )
                }
                Box(Modifier.size(300.dp).alpha(logo.value).background(Brush.radialGradient(listOf(Tokens.Color.accent.copy(alpha = 0.35f), Color.Transparent)), CircleShape))
                Box(contentAlignment = Alignment.Center) {
                    Image(
                        painterResource(R.drawable.nino_logo), contentDescription = null,
                        modifier = Modifier.size(230.dp).scale(0.72f + logo.value * 0.28f).alpha(logo.value)
                            .then(if (logo.value < 0.95f) Modifier.blur((14 * (1 - logo.value)).coerceAtLeast(0f).dp, androidx.compose.ui.draw.BlurredEdgeTreatment.Unbounded) else Modifier),
                    )
                    // Bayrağın üstündeki kırmızı parıltı (logoda bayrak üst ortada)
                    Box(
                        Modifier.offset(y = (-62).dp).size(width = 120.dp, height = 70.dp)
                            .alpha(flag.value * 0.85f).background(Brush.radialGradient(listOf(Color(0xFFF21F29).copy(alpha = 0.75f), Color.Transparent))),
                    )
                }
            }
            Spacer(Modifier.height(28.dp))
            Column(
                Modifier.alpha(text.value).offset(y = (12 * (1 - text.value)).dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("Nino", fontSize = 34.sp, fontWeight = FontWeight.Bold, color = Tokens.Color.text)
                Spacer(Modifier.height(6.dp))
                Text(stringResource(R.string.nino_games_now_in, targetLanguageName()), style = Tokens.Type.body, color = Tokens.Color.secondary)
            }
        }
    }
}

/** Önizleme ekranının köşesindeki küçük koyu etiket (PS5 · Eşlendi gibi). */
@Composable
fun ScreenChip(text: String, ok: Boolean?, onClick: (() -> Unit)? = null) {
    androidx.compose.foundation.layout.Row(
        Modifier.background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(50)).border(1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(50))
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }.padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(7.dp).background(when (ok) { true -> Color(0xFF5FD39A); false -> Color(0xFFFFA24A); null -> Color.White.copy(alpha = 0.6f) }, CircleShape))
        Text(text, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1)
    }
}

/**
 * Kaydırarak açılan çeviri anahtarı: düğmeyi sağa sürükleyince çeviri başlar, sola sürükleyince durur; düğmeye
 * dokunmak da aynı işi yapar. Kullanılamıyorken ([locked]) dokunmak [onLocked]'u çağırır (ör. PS5 eşleme).
 */
@Composable
fun SlideToTranslate(
    running: Boolean, label: String, locked: Boolean, modifier: Modifier = Modifier,
    onStart: () -> Unit, onStop: () -> Unit, onLocked: () -> Unit,
) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val drag = remember { Animatable(0f) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    androidx.compose.foundation.layout.BoxWithConstraints(modifier.fillMaxWidth().height(60.dp)) {
        val knob = 52.dp
        val travelPx = with(density) { (maxWidth - knob - 8.dp).toPx() }
        val base = if (running) travelPx else 0f
        val x = (base + drag.value).coerceIn(0f, travelPx)
        val progress = if (travelPx > 0) x / travelPx else 0f
        val shape = RoundedCornerShape(50)
        Box(
            Modifier.fillMaxSize().alpha(if (locked) 0.6f else 1f)
                .background(Color.White.copy(alpha = 0.85f), shape)
                .background(Brush.horizontalGradient(listOf(Tokens.Color.accent.copy(alpha = 0.12f + 0.88f * progress), Tokens.Color.navy.copy(alpha = progress))), shape)
                .border(1.dp, if (running) Color.White.copy(alpha = 0.4f) else Tokens.Color.borderStrong, shape)
                .clickable(enabled = locked, onClick = onLocked),
            contentAlignment = Alignment.CenterStart,
        ) {
            Text(label, style = Tokens.Type.headline, color = if (progress > 0.5f) Color.White else Tokens.Color.secondary,
                textAlign = TextAlign.Center, maxLines = 1,
                modifier = Modifier.fillMaxWidth().padding(start = if (running) 16.dp else knob + 8.dp, end = if (running) knob + 8.dp else 16.dp))
            Box(
                Modifier.offset { androidx.compose.ui.unit.IntOffset((with(density) { 4.dp.toPx() } + x).toInt(), 0) }
                    .size(knob)
                    .shadow(10.dp, CircleShape, ambientColor = Tokens.Color.accent, spotColor = Tokens.Color.accent)
                    .background(if (running) Brush.verticalGradient(listOf(Color.White, Color.White)) else NinoGradient, CircleShape)
                    .let {
                        if (locked) it else it.pointerInput(running) {
                            detectHorizontalDragGestures(
                                onDragEnd = {
                                    val end = base + drag.value
                                    if (!running && end > travelPx * 0.7f) onStart()
                                    if (running && end < travelPx * 0.3f) onStop()
                                    scope.launch { drag.animateTo(0f, spring(dampingRatio = 0.75f)) }
                                },
                            ) { change: androidx.compose.ui.input.pointer.PointerInputChange, amount: Float -> change.consume(); scope.launch { drag.snapTo(drag.value + amount) } }
                        }
                    }
                    .clickable(enabled = !locked) { if (running) onStop() else onStart() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(if (running) Icons.Filled.ClosedCaption else Icons.Filled.KeyboardDoubleArrowRight,
                    contentDescription = label, tint = if (running) Tokens.Color.accent else Color.White, modifier = Modifier.size(26.dp))
            }
        }
    }
}

/** Oyun sahnesi gibi koyu bir kart; içinde TV demosundaki gibi önce İngilizce, sonra üstüne Türkçe altyazı akar. */
@Composable
fun DemoScene(
    modifier: Modifier = Modifier,
    height: androidx.compose.ui.unit.Dp = 210.dp,
    live: String? = null,
    chips: @Composable (() -> Unit)? = null,
    badge: String = stringResource(R.string.nino_sample),
) {
    // Nino: örnek çeviriler seçili çeviri dilinde (Türkçe, Arapça ya da öbür dillerin üç satırı).
    val target = TargetLanguage.code(Services.settings.targetLanguage)
    val arabic = target == "ar"
    val lines = remember(target) {
        TargetLanguage.sampleLines(target).takeIf { it.isNotEmpty() } ?: if (arabic) listOf(
            "This city needs someone to watch over it." to "هذه المدينة تحتاج إلى من يحرسها.",
            "They're coming. Stay out of sight." to "إنهم قادمون. ابقَ بعيدًا عن الأنظار.",
            "Who's there?" to "من هناك؟",
            "The rain hides everything." to "المطر يخفي كل شيء.",
            "Get to the rooftop. Now!" to "اصعد إلى السطح. الآن!",
        ) else listOf(
            "This city needs someone to watch over it." to "Bu şehrin onu kollayacak birine ihtiyacı var.",
            "They're coming. Stay out of sight." to "Geliyorlar. Gözden uzak dur.",
            "Who's there?" to "Kim var orada?",
            "The rain hides everything." to "Yağmur her şeyi saklıyor.",
            "Get to the rooftop. Now!" to "Çatıya çık. Hemen!",
        )
    }
    val index = remember { androidx.compose.runtime.mutableIntStateOf(0) }
    val english = remember { Animatable(0f) }
    val turkish = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        while (true) {
            english.animateTo(1f, tween(300))
            delay(900)
            turkish.animateTo(1f, spring(dampingRatio = 0.8f, stiffness = 300f))
            delay(2600)
            launch { english.animateTo(0f, tween(250)) }
            turkish.animateTo(0f, tween(250))
            delay(450)
            index.intValue += 1
        }
    }
    // Dil değişince satır sayısı değişebilir (5 → 3): sıra okunurken listenin boyuyla alınır.
    val (en, tr) = lines[index.intValue % lines.size]
    // Nino: ana ekrandaki sahne kartıyla aynı: lacivert→siyah, ince ışıklı kenar, yumuşak gölge.
    val shape = RoundedCornerShape(28.dp)
    val ink = Color(0xFF0A1430)
    Box(
        modifier.fillMaxWidth().height(height)
            .shadow(28.dp, shape, ambientColor = ink.copy(alpha = 0.5f), spotColor = ink.copy(alpha = 0.5f))
            .background(Brush.verticalGradient(listOf(Color(0xFF151E36), Color(0xFF06080F))), shape)
            .border(1.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.22f), Color.White.copy(alpha = 0.03f))), shape),
        contentAlignment = Alignment.BottomCenter,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(Brush.radialGradient(listOf(Color(0xFFFF9A4A).copy(alpha = 0.16f), Color.Transparent),
                center = androidx.compose.ui.geometry.Offset(size.width * 0.75f, size.height * 0.3f), radius = size.width * 0.35f),
                radius = size.width * 0.35f, center = androidx.compose.ui.geometry.Offset(size.width * 0.75f, size.height * 0.3f))
            drawCircle(Brush.radialGradient(listOf(Tokens.Color.accent.copy(alpha = 0.22f), Color.Transparent),
                center = androidx.compose.ui.geometry.Offset(size.width * 0.2f, size.height * 0.45f), radius = size.width * 0.4f),
                radius = size.width * 0.4f, center = androidx.compose.ui.geometry.Offset(size.width * 0.2f, size.height * 0.45f))
        }
        if (chips != null) androidx.compose.foundation.layout.Row(Modifier.align(Alignment.TopStart).offset(12.dp, 12.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp)) { chips() }
        Box(Modifier.align(if (chips != null) Alignment.TopEnd else Alignment.TopStart).offset(if (chips != null) (-12).dp else 12.dp, 12.dp)
            .background(Color.Black.copy(alpha = 0.4f), RoundedCornerShape(50)).border(1.dp, Color.White.copy(alpha = 0.2f), RoundedCornerShape(50))) {
            // Harf aralığı Arapça harflerin birleşmesini bozar.
            Text(badge, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White,
                letterSpacing = if (TargetLanguage.containsArabic(badge)) 0.sp else 1.5.sp,
                modifier = Modifier.padding8())
        }
        if (live != null) {
            if (live.isNotEmpty()) Text(TargetLanguage.displayText(live), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White, textAlign = TextAlign.Center,
                modifier = Modifier.offset(y = (-20).dp).padding(horizontal = 16.dp)
                    .background(Color.Black.copy(alpha = 0.72f), RoundedCornerShape(10.dp)).padding14x6())
        } else Box(Modifier.offset(y = (-20).dp), contentAlignment = Alignment.Center) {
            Text(en, fontSize = 15.sp, color = Color(0xFFF4F1E8), textAlign = TextAlign.Center,
                modifier = Modifier.alpha(english.value * (1f - turkish.value)))
            Text(TargetLanguage.displayText(tr), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White, textAlign = TextAlign.Center,
                modifier = Modifier.alpha(turkish.value).scale(0.96f + turkish.value * 0.04f)
                    .background(Color.Black.copy(alpha = 0.72f), RoundedCornerShape(10.dp)).padding14x6())
        }
    }
}

private fun Modifier.padding8(): Modifier = this.padding(horizontal = 10.dp, vertical = 4.dp)
private fun Modifier.padding14x6(): Modifier = this.padding(horizontal = 14.dp, vertical = 6.dp)
