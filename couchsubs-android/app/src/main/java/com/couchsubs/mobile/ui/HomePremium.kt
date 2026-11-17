// SPDX-License-Identifier: AGPL-3.0-only
// Nino: telefonun ana ekranı (sade, tek odak). Durum satırı, büyük başlık, sahne kartı, kaydırarak başlatma çubuğu ve
// altta üç kısa yol. Arapça arayüzde her şey sağdan sola; kaydırma da sağdan sola yapılır.
package com.couchsubs.mobile.ui

import androidx.compose.animation.AnimatedContent
import com.couchsubs.mobile.core.TargetLanguage
import com.couchsubs.mobile.Services
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
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
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.service.LiveStatus
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

private val Ink = Color(0xFF0A1430)
private val InkSoft = Color(0xFF55607A)
private val StageTop = Color(0xFF151E36)
private val StageBottom = Color(0xFF06080F)
private val LiveGreen = Color(0xFF30C578)

/** Ana ekranın durumu (tek yerde hesaplanır). */
private enum class HomeState { NOT_PAIRED, READY, CONNECTING, LIVE }

private fun homeState(status: LiveStatus, paired: Boolean) = when {
    status.running && status.streaming -> HomeState.LIVE
    status.running -> HomeState.CONNECTING
    paired -> HomeState.READY
    else -> HomeState.NOT_PAIRED
}

@Composable
fun PremiumHome(
    status: LiveStatus,
    paired: Boolean,
    consoleName: String?,
    onTv: Boolean,
    packsEnabled: Boolean,
    startMarker: Modifier,
    targetMarker: Modifier,
    packsMarker: Modifier,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onPairing: () -> Unit,
    onTarget: () -> Unit,
    onPacks: () -> Unit,
    onFullScreen: () -> Unit,
    onDemo: () -> Unit = {},
    consoleLabel: String = "PS5",
) {
    val state = homeState(status, paired)
    val name = consoleName ?: consoleLabel
    Column(Modifier.fillMaxWidth().padding(top = 8.dp)) {
        // Durum satırı: renkli nokta + PS5 adı + durum.
        StatusLine(state, if (status.demo) stringResource(R.string.demo_name) else name, onTv)
        Spacer(Modifier.height(6.dp))
        // Başlık: büyük, sıkı aralıklı.
        AnimatedContent(state, Modifier.fillMaxWidth(), transitionSpec = { fadeIn(tween(300)) togetherWith fadeOut(tween(200)) }, label = "title") { s ->
            Text(
                when (s) {
                    HomeState.NOT_PAIRED -> stringResource(if (consoleLabel == "Xbox") R.string.xbox_home_title_pair else R.string.home_title_pair)
                    HomeState.LIVE -> stringResource(R.string.home_title_live)
                    else -> stringResource(R.string.home_title_ready, targetLanguageName())
                },
                style = TextStyle(fontSize = 34.sp, lineHeight = 40.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.6).sp),
                color = Ink,
            )
        }
        Spacer(Modifier.height(20.dp))
        Stage(status, state, onFullScreen.takeIf { !onTv })
        Spacer(Modifier.height(22.dp))
        SlideControl(state, startMarker, onStart, onStop, onPairing)
        // PS5'i olmayanlar ve mağaza incelemesi için: örnek altyazılarla deneme.
        if (state == HomeState.NOT_PAIRED) Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.Center) {
            Text(stringResource(R.string.demo_try), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Tokens.Color.accentText,
                modifier = Modifier.clip(RoundedCornerShape(50)).clickable(onClick = onDemo).padding(horizontal = 14.dp, vertical = 8.dp))
        }
        // Altta yalnız ipucu: yan çevirince tam ekran açılır (düğme sahnenin üstünde).
        AnimatedVisibility(state == HomeState.LIVE && !onTv) {
            Row(Modifier.fillMaxWidth().padding(top = 14.dp), horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.ScreenRotation, null, tint = InkSoft, modifier = Modifier.size(18.dp))
                Text(stringResource(R.string.home_rotate_hint), fontSize = 14.sp, color = InkSoft, modifier = Modifier.padding(start = 8.dp))
            }
        }
        Spacer(Modifier.height(28.dp))
        // Üç kısa yol; çeviri motoru Ayarlar'da.
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Shortcut(Icons.Filled.SportsEsports, consoleLabel, consoleName ?: stringResource(R.string.profile_not_paired), Modifier.weight(1f), onPairing)
            Shortcut(if (onTv) Icons.Filled.Tv else Icons.Filled.Smartphone, stringResource(R.string.nino_output),
                if (onTv) "TV" else stringResource(R.string.nino_phone), Modifier.weight(1f).then(targetMarker), onTarget)
            Shortcut(Icons.Filled.Inventory2, stringResource(R.string.nino_packs),
                if (packsEnabled) stringResource(R.string.packs_free) else "—", Modifier.weight(1f).then(packsMarker), onPacks)
        }
    }
}

@Composable
private fun StatusLine(state: HomeState, name: String, onTv: Boolean) {
    val (color, text) = when (state) {
        HomeState.NOT_PAIRED -> InkSoft to stringResource(R.string.home_not_paired)
        HomeState.READY -> Tokens.Color.accent to stringResource(R.string.home_ready)
        HomeState.CONNECTING -> Tokens.Color.accent to stringResource(R.string.home_connecting)
        HomeState.LIVE -> LiveGreen to stringResource(if (onTv) R.string.home_status_tv else R.string.home_live)
    }
    val pulse = rememberInfiniteTransition(label = "dot")
    val alpha by pulse.animateFloat(1f, if (state == HomeState.LIVE || state == HomeState.CONNECTING) 0.3f else 1f,
        infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "alpha")
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).alpha(alpha).background(color, CircleShape))
        Text(if (state == HomeState.NOT_PAIRED) text else "$name  ·  $text", fontSize = 14.sp, fontWeight = FontWeight.Medium,
            color = InkSoft, modifier = Modifier.padding(start = 8.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Sahne: koyu ekran. Canlıyken altyazı akar (dokununca tam ekran); değilken tek satırlık sakin bir yazı. */
@Composable
private fun Stage(status: LiveStatus, state: HomeState, onFullScreen: (() -> Unit)?) {
    val shape = RoundedCornerShape(28.dp)
    Box(Modifier.fillMaxWidth().height(196.dp)
        .shadow(28.dp, shape, ambientColor = Ink.copy(alpha = 0.5f), spotColor = Ink.copy(alpha = 0.5f))
        .clip(shape)
        .background(Brush.verticalGradient(listOf(StageTop, StageBottom)))
        .border(1.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.22f), Color.White.copy(alpha = 0.03f))), shape)
        .then(if (state == HomeState.LIVE && onFullScreen != null) Modifier.clickable(onClick = onFullScreen) else Modifier)) {
        AnimatedContent(state == HomeState.LIVE, transitionSpec = { fadeIn(tween(400)) togetherWith fadeOut(tween(250)) }, label = "stage") { live ->
            if (live) CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) { LiveTvScreen(status, Modifier.fillMaxSize()) }
            else Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Text(stringResource(if (state == HomeState.CONNECTING) R.string.home_connecting else R.string.home_stage_idle),
                    fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.42f), textAlign = TextAlign.Center)
            }
        }
        // Canlıyken sağ üstte buzlu cam "Tam Ekran" düğmesi (CANLI işaretinin karşısında).
        AnimatedVisibility(state == HomeState.LIVE && onFullScreen != null, Modifier.align(Alignment.TopEnd),
            enter = fadeIn(tween(300)), exit = fadeOut(tween(200))) {
            Row(Modifier.padding(12.dp)
                .shadow(12.dp, RoundedCornerShape(50), ambientColor = Color.Black, spotColor = Color.Black)
                .clip(RoundedCornerShape(50))
                .background(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.26f), Color.White.copy(alpha = 0.10f))))
                .border(1.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.55f), Color.White.copy(alpha = 0.12f))), RoundedCornerShape(50))
                .clickable { onFullScreen?.invoke() }
                .padding(start = 12.dp, end = 14.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Fullscreen, null, tint = Color.White, modifier = Modifier.size(20.dp))
                Text(stringResource(R.string.home_full_screen), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color.White,
                    modifier = Modifier.padding(start = 6.dp))
            }
        }
    }
}

/**
 * Kaydırarak başlatma: ince koyu iz, beyaz yuvarlak tutamaç, üzerinde soldan sağa parlayan yazı. Sona kadar kaydırınca
 * başlar; açıkken tutamaç sondadır, iz mavi olur, geri kaydırınca durur. Eşlenmemişse dokununca kurulum açılır. Arapça
 * arayüzde (sağdan sola) tutamaç sağda başlar ve sola kaydırılır.
 */
@Composable
private fun SlideControl(state: HomeState, marker: Modifier, onStart: () -> Unit, onStop: () -> Unit, onPairing: () -> Unit) {
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val on = state == HomeState.LIVE || state == HomeState.CONNECTING
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val drag = remember { Animatable(0f) }
    val label = stringResource(when (state) {
        HomeState.NOT_PAIRED -> R.string.slide_pair
        HomeState.READY -> R.string.slide_start
        else -> R.string.slide_stop
    })
    fun act() = when (state) {
        HomeState.NOT_PAIRED -> onPairing()
        HomeState.READY -> onStart()
        else -> onStop()
    }
    BoxWithConstraints(marker.fillMaxWidth().height(68.dp).semantics {
        role = Role.Button
        contentDescription = label
        onClick { act(); true }
    }) {
        val height = 68.dp
        val knob = 56.dp
        val inset = 6.dp
        val travel = with(density) { (maxWidth - knob - inset * 2).toPx() }.coerceAtLeast(1f)
        val base by animateFloatAsState(if (on) travel else 0f, spring(dampingRatio = 0.82f, stiffness = 320f), label = "base")
        val x = (base + drag.value).coerceIn(0f, travel)
        val progress = x / travel
        val shape = RoundedCornerShape(50)
        val (onTop, onBottom) = onColors()
        // İz
        Box(Modifier.fillMaxSize()
            .shadow(16.dp, shape, ambientColor = onTop.copy(alpha = 0.3f * progress), spotColor = onTop.copy(alpha = 0.45f * progress))
            .background(Ink, shape)
            .background(Brush.verticalGradient(listOf(onTop.copy(alpha = progress), onBottom.copy(alpha = progress))), shape)
            .background(Brush.verticalGradient(0f to Color.White.copy(alpha = 0.22f * progress), 0.5f to Color.Transparent), shape)
            .border(1.dp, Color.White.copy(alpha = 0.10f), shape))
        // Parlayan yazı (iPhone'un eski "kaydırarak aç" ışıltısı gibi).
        val shine = rememberInfiniteTransition(label = "shine")
        val sweep by shine.animateFloat(-0.3f, 1.3f, infiniteRepeatable(tween(2200, easing = LinearEasing)), label = "sweep")
        val widthPx = with(density) { maxWidth.toPx() }
        val center = (if (rtl) 1f - sweep else sweep) * widthPx
        val brush = Brush.linearGradient(
            listOf(Color.White.copy(alpha = 0.55f + 0.25f * progress), Color.White, Color.White.copy(alpha = 0.55f + 0.25f * progress)),
            start = Offset(center - widthPx * 0.18f, 0f), end = Offset(center + widthPx * 0.18f, 0f))
        Box(Modifier.fillMaxSize().padding(start = knob + inset * 2, end = inset * 2), contentAlignment = Alignment.Center) {
            Text(label, style = TextStyle(brush = brush, fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
                modifier = Modifier.alpha(if (on) 1f else (1f - progress * 1.4f).coerceAtLeast(0f)), maxLines = 1)
        }
        // Tutamaç (sağdan sola arayüzde ayna).
        val shown = if (rtl) travel - x else x
        Box(Modifier.align(androidx.compose.ui.AbsoluteAlignment.TopLeft).absoluteOffset { IntOffset((shown + with(density) { inset.toPx() }).roundToInt(), with(density) { ((height - knob) / 2).toPx() }.roundToInt()) }
            .size(knob).shadow(10.dp, CircleShape).background(Color.White, CircleShape).clip(CircleShape)
            .pointerInput(state) {
                detectHorizontalDragGestures(onDragEnd = {
                    val end = (base + drag.value) / travel
                    scope.launch { drag.animateTo(0f, spring(dampingRatio = 0.8f)) }
                    when {
                        state == HomeState.NOT_PAIRED -> if (end > 0.5f) onPairing()
                        !on && end > 0.85f -> onStart()
                        on && end < 0.15f -> onStop()
                    }
                }, onDragCancel = { scope.launch { drag.animateTo(0f) } }) { change, amount ->
                    change.consume()
                    scope.launch { drag.snapTo(drag.value + if (rtl) -amount else amount) }
                }
            }
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { act() },
            contentAlignment = Alignment.Center) {
            when {
                state == HomeState.CONNECTING -> CircularProgressIndicator(Modifier.size(22.dp), color = Tokens.Color.accent, strokeWidth = 2.5.dp)
                else -> Icon(Icons.AutoMirrored.Filled.ArrowForward, null, tint = Ink, modifier = Modifier.size(24.dp).alpha(1f - progress))
            }
            // Açıldıkça tutamaç camlı bir bayrak küresine döner (Türkçe: ay yıldız; Arapça: Suudi bayrağı).
            if (state != HomeState.CONNECTING) FlagGlass(Modifier.fillMaxSize().alpha(progress))
        }
    }
}

@Composable
private fun Shortcut(icon: ImageVector, title: String, value: String, modifier: Modifier, onClick: () -> Unit) {
    Column(modifier.clip(RoundedCornerShape(20.dp)).background(Color.White.copy(alpha = 0.72f))
        .border(1.dp, Color.White, RoundedCornerShape(20.dp)).clickable(onClick = onClick)
        .padding(horizontal = 12.dp, vertical = 14.dp)) {
        Icon(icon, null, tint = Tokens.Color.accent, modifier = Modifier.size(22.dp))
        Spacer(Modifier.height(10.dp))
        Text(title, fontSize = 12.sp, color = InkSoft, maxLines = 1)
        Text(value, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Camlı bayrak küresi: bayrak dairenin içinde, üstünde buzlu parlama ve ince ışıklı kenar. */
@Composable
private fun FlagGlass(modifier: Modifier) {
    Box(modifier.clip(CircleShape), contentAlignment = Alignment.Center) {
        if (!targetIsTurkish()) {
            // Bayrak emojisi dikdörtgendir; daireyi doldursun diye büyütülüp kırpılır.
            Text(TargetLanguage.flag(Services.settings.targetLanguage), fontSize = 64.sp, modifier = Modifier.wrapContentSize(unbounded = true))
        } else {
            Box(Modifier.fillMaxSize().background(FlagRed))
            androidx.compose.foundation.Canvas(Modifier.size(34.dp)) { drawCrescentStar(FlagRed) }
        }
        androidx.compose.foundation.Canvas(Modifier.fillMaxSize()) {
            val r = size.minDimension / 2
            drawCircle(Brush.linearGradient(listOf(Color.White.copy(alpha = 0.9f), Color.White.copy(alpha = 0.1f), Color.White.copy(alpha = 0.5f)),
                Offset.Zero, Offset(size.width, size.height)), r - 1.dp.toPx(), style = androidx.compose.ui.graphics.drawscope.Stroke(2.dp.toPx()))
            drawOval(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.6f), Color.Transparent), size.height * 0.06f, size.height * 0.4f),
                Offset(size.width * 0.16f, size.height * 0.07f), androidx.compose.ui.geometry.Size(size.width * 0.6f, size.height * 0.3f))
        }
    }
}
