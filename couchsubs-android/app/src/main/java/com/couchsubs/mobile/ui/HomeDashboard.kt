// SPDX-License-Identifier: AGPL-3.0-only
// Nino: telefona özel ana ekran parçaları (cam düğme arayüzü). Mac'teki ekranın kopyası değildir.
package com.couchsubs.mobile.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.StayCurrentPortrait
import androidx.compose.ui.draw.rotate
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.core.TargetLanguage
import com.couchsubs.mobile.service.LiveStatus
import kotlinx.coroutines.delay

private val StageTop = Color(0xFF14213F)
private val StageBottom = Color(0xFF05070D)
private val LiveGreen = Color(0xFF34C77B)
private val ReadyBlue = Color(0xFF5AA9FF)
private val Muted = Color(0xFF8A94AB)

/**
 * Sahne: koyu, yuvarlak köşeli bir ekran kartı. Çeviri açıkken canlı altyazılar burada akar; kapalıyken PS5'in adı ve
 * durumu görünür. Sol üstte durum rozeti (Canlı / Bağlanıyor / Hazır / Eşlenmedi), sağ üstte çeviri motoru.
 */
@Composable
fun HomeStage(status: LiveStatus, paired: Boolean, consoleName: String?, modifier: Modifier = Modifier, onFullScreen: (() -> Unit)? = null) {
    val shape = RoundedCornerShape(28.dp)
    val (dot, label) = when {
        status.running && status.streaming -> LiveGreen to stringResource(R.string.home_live)
        status.running -> ReadyBlue to stringResource(R.string.home_connecting)
        paired -> ReadyBlue to stringResource(R.string.home_ready)
        else -> Muted to stringResource(R.string.home_not_paired)
    }
    Box(modifier.fillMaxWidth().height(212.dp)
        .shadow(24.dp, shape, ambientColor = Color(0xFF0A1430), spotColor = Color(0xFF0A1430))
        .clip(shape)
        .background(Brush.verticalGradient(listOf(StageTop, StageBottom)))
        .border(1.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.28f), Color.White.copy(alpha = 0.04f))), shape)
        .then(if (status.running && onFullScreen != null) Modifier.clickable(onClick = onFullScreen) else Modifier)) {
        AnimatedContent(status.running, transitionSpec = { fadeIn(tween(400)) togetherWith fadeOut(tween(250)) }, label = "stage") { running ->
            if (running) {
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) { LiveTvScreen(status, Modifier.fillMaxSize()) }
            } else {
                Column(Modifier.fillMaxSize().padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center) {
                    Box(Modifier.size(56.dp).background(Color.White.copy(alpha = 0.08f), CircleShape)
                        .border(1.dp, Color.White.copy(alpha = 0.18f), CircleShape), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.SportsEsports, null, tint = Color.White, modifier = Modifier.size(28.dp))
                    }
                    Text(consoleName ?: "PS5", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Color.White,
                        modifier = Modifier.padding(top = 12.dp))
                    Text(stringResource(if (paired) R.string.home_idle_hint else R.string.home_pair_hint), fontSize = 13.sp,
                        color = Color.White.copy(alpha = 0.6f), textAlign = TextAlign.Center, modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
        // Durum rozeti (çeviri açıkken canlı ekranın kendi CANLI işareti var). Açıkken sağ üstte tam ekran düğmesi.
        if (!status.running) Row(Modifier.align(Alignment.TopStart).padding(14.dp)
            .background(Color.Black.copy(alpha = 0.35f), RoundedCornerShape(50))
            .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
            val pulse = rememberInfiniteTransition(label = "pulse")
            val alpha by pulse.animateFloat(1f, if (status.running) 0.35f else 1f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "dot")
            Box(Modifier.size(7.dp).alpha(alpha).background(dot, CircleShape))
            Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White, modifier = Modifier.padding(start = 6.dp))
        }
    }
}

/**
 * Çeviri açıkken tam ekrana yönlendirme: dönen telefon simgesi, kısa başlık ve açıklama; dokununca tam ekran açılır.
 * Telefonu yan çevirmek de aynı işi yapar (MainScreen).
 */
@Composable
fun FullScreenHint(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val turn = rememberInfiniteTransition(label = "turn")
    val angle by turn.animateFloat(0f, -90f, infiniteRepeatable(androidx.compose.animation.core.keyframes {
        durationMillis = 2600
        0f at 0
        0f at 700
        -90f at 1300
        -90f at 2000
        0f at 2600
    }), label = "angle")
    Row(modifier.fillMaxWidth()
        .shadow(10.dp, RoundedCornerShape(22.dp), ambientColor = Tokens.Color.accent.copy(alpha = 0.3f), spotColor = Tokens.Color.accent.copy(alpha = 0.3f))
        .background(Brush.horizontalGradient(listOf(Tokens.Color.accentHi, Tokens.Color.navy)), RoundedCornerShape(22.dp))
        .clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(44.dp).background(Color.White.copy(alpha = 0.16f), CircleShape), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.StayCurrentPortrait, null, tint = Color.White, modifier = Modifier.size(24.dp).rotate(angle))
        }
        Column(Modifier.weight(1f).padding(horizontal = 14.dp)) {
            Text(stringResource(R.string.home_rotate_title), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            Text(stringResource(R.string.home_rotate_body), fontSize = 13.sp, color = Color.White.copy(alpha = 0.8f))
        }
        Icon(Icons.Filled.Fullscreen, null, tint = Color.White, modifier = Modifier.size(26.dp))
    }
}
