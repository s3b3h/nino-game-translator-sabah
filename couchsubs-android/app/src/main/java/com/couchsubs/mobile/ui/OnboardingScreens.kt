// SPDX-License-Identifier: AGPL-3.0-only
// Kurulum akışı (tuval: Telefon-Karsilama, -PSN, -PS5, -Hedef): izin → karşılama (3 sayfa) → PSN girişi (ikinci
// hesap; PsnLoginScreen.kt) → PS5 eşleme → altyazı nerede. Uygulamada hesap yoktur.
package com.couchsubs.mobile.ui

import com.couchsubs.mobile.core.TargetLanguage
import androidx.compose.ui.unit.sp
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.remoteplay.ConsoleDiscovery
import com.couchsubs.mobile.remoteplay.ConsoleInfo
import com.couchsubs.mobile.remoteplay.Registration
import com.couchsubs.mobile.remoteplay.RegistrationException
import com.couchsubs.mobile.remoteplay.RegistrationFailure
import com.couchsubs.mobile.settings.SubtitleTarget
import com.couchsubs.mobile.tv.FoundTv
import com.couchsubs.mobile.tv.TvBrand
import com.couchsubs.mobile.tv.TvDiscovery
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Nino: çeviri dili için yalnız bayraklar (🇹🇷 / 🇸🇦): seçili olan tam renkli ve ince mavi halkalı, öteki soluk. Ekran
 * okuyucu dilin adını okur. Sonra Ayarlar'dan da değişir.
 */
@Composable
fun TranslationLanguageFlags() {
    var selected by remember { mutableStateOf(Services.settings.targetLanguage) }
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        TargetLanguage.choices.forEach { (code, name) ->
            val on = selected == code
            Box(Modifier.size(36.dp).alpha(if (on) 1f else 0.45f)
                .background(Color.White.copy(alpha = if (on) 0.10f else 0f), CircleShape)
                .border(1.5.dp, if (on) Tokens.Color.accent else Color.Transparent, CircleShape)
                .clickable { selected = code; Services.settings.targetLanguage = code }
                .semantics { contentDescription = name; this.selected = on },
                contentAlignment = Alignment.Center) {
                Text(TargetLanguage.flags[code] ?: name, fontSize = 18.sp)
            }
        }
    }
}

/** Karşılama: üç sayfa, yatay kaydırma, nokta göstergesi; otomatik geçiş yok. */
@Composable
fun WelcomeScreen(onDone: () -> Unit) {
    val pager = rememberPagerState { 3 }
    val scope = rememberCoroutineScope()
    val last = pager.currentPage == 2
    ScreenScaffold(scroll = false, top = {
        // Nino: sağ üstte yalnız bayraklarla çeviri dili (Arapça arayüzde de sağda kalır).
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
            TopBar {
                TranslationLanguageFlags()
                if (!last) GhostButton(stringResource(R.string.skip), onClick = onDone)
            }
        }
    }, bottom = {
        Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
            repeat(3) { index ->
                val on = pager.currentPage == index
                Box(Modifier.size(width = if (on) 24.dp else 8.dp, height = 8.dp).background(if (on) Color(0xFF0A1430) else Color(0xFF0A1430).copy(alpha = 0.18f), CircleShape))
            }
        }
        PrimaryButton(stringResource(if (last) R.string.welcome_start else R.string.next)) {
            if (last) onDone() else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
        }
    }) {
        HorizontalPager(pager, Modifier.fillMaxWidth().weight(1f)) { page ->
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap, Alignment.Bottom)) {
                when (page) {
                    0 -> {
                        Spacer(Modifier.weight(1f))
                        DemoScene(height = 380.dp)
                        Heading(stringResource(R.string.welcome1_title), stringResource(R.string.welcome1_body))
                    }
                    1 -> {
                        Spacer(Modifier.weight(1f))
                        OnboardingStage {
                            GlassRow("GTA", "Grand Theft Auto V", stringResource(R.string.welcome2_gta), stringResource(R.string.packs_free))
                            GlassRow("RDR", "Red Dead Redemption 2", stringResource(R.string.welcome2_rdr_lines), stringResource(R.string.packs_free))
                            GlassRow("MAF", "Mafia", stringResource(R.string.welcome2_maf_lines), stringResource(R.string.packs_free))
                        }
                        Heading(stringResource(R.string.welcome2_title), stringResource(R.string.welcome2_body))
                    }
                    else -> {
                        Spacer(Modifier.weight(1f))
                        OnboardingStage {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                GlassChoice(Icons.Filled.Tv, stringResource(R.string.welcome3_tv), stringResource(R.string.welcome3_tv_label), Modifier.weight(1f))
                                GlassChoice(Icons.Filled.Smartphone, stringResource(R.string.welcome3_phone), stringResource(R.string.welcome3_phone_label), Modifier.weight(1f))
                            }
                            GlassRow(null, stringResource(R.string.welcome3_wifi), stringResource(R.string.welcome3_wifi_body), null)
                        }
                        Heading(stringResource(R.string.welcome3_title), stringResource(R.string.welcome3_body))
                    }
                }
            }
        }
    }
}

/** Kurulumda PSN ve PS5 adımlarının sağ üstünde "Şimdilik geç" (PS5'siz de uygulama gezilebilsin). */
@Composable
internal fun SkipAction(onSkip: (() -> Unit)?) {
    if (onSkip != null) GhostButton(stringResource(R.string.skip_for_now), onClick = onSkip)
}

@Composable
fun InfoDialog(title: String, body: String, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, containerColor = Tokens.Color.surface2,
        title = { Text(title, style = Tokens.Type.headline, color = Tokens.Color.text) },
        text = { Text(body, style = Tokens.Type.body, color = Tokens.Color.secondary) },
        confirmButton = { TextButton(onDismiss) { Text(stringResource(R.string.ok), style = Tokens.Type.headline, color = Tokens.Color.accentText) } })
}

@Composable
fun PairScreen(onBack: (() -> Unit)? = null, onSkip: (() -> Unit)? = null, onDone: () -> Unit) {
    val settings = Services.settings
    var consoles by remember { mutableStateOf<List<ConsoleInfo>?>(null) }
    var host by remember { mutableStateOf(settings.console?.host ?: "") }
    var code by remember { mutableStateOf("") }
    var manual by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val failures = registrationErrors()
    // Nino: arama ekran açık kaldıkça yinelenir; PS5 sonradan açılır ya da dinlenme modundan uyanırsa kendiliğinden
    // bulunur (eskiden yalnız açılışta bir kez, 3 sn aranıyordu).
    var searchRound by remember { mutableStateOf(0) }
    LaunchedEffect(searchRound) {
        if (searchRound > 0 && consoles.isNullOrEmpty()) consoles = null
        var autoHost = host.isEmpty()
        while (true) {
            val found = withContext(Dispatchers.IO) { ConsoleDiscovery.discover(null, 2500) }
            if (found.isNotEmpty() || consoles == null) consoles = found
            if (found.isNotEmpty()) {
                if (autoHost || host.isEmpty() || found.none { it.host == host }) {
                    if (autoHost || host.isEmpty()) { host = found.first().host; autoHost = true }
                }
                if (autoHost) manual = false
            } else if (consoles.isNullOrEmpty()) {
                manual = true
            }
            delay(if (found.isEmpty()) 1500 else 6000)
        }
    }
    val pin = Registration.parsePin(code)
    ScreenScaffold(top = { TopBar(onBack = onBack) { SkipAction(onSkip) } }, bottom = {
        if (!manual) GhostButton(stringResource(R.string.pair_not_found)) { manual = true }
        // Nino: PS5'i yanında olmayan (ya da mağaza incelemesi) kurulumu atlayıp örnek altyazılarla dener.
        if (onSkip != null) GhostButton(stringResource(R.string.demo_try)) { com.couchsubs.mobile.service.DemoSession.start(); onSkip() }
        PrimaryButton(stringResource(R.string.pair_button), enabled = !working && pin != null && host.isNotEmpty()) {
            val accountId = settings.accountId ?: return@PrimaryButton
            working = true
            problem = null
            scope.launch {
                try {
                    settings.console = withContext(Dispatchers.IO) { Registration.register(host, accountId, pin!!) }
                    onDone()
                } catch (error: RegistrationException) {
                    problem = failures(error.failure) + (error.detail?.let { " ($it)" } ?: "")
                } catch (error: Exception) {
                    problem = error.message
                } finally {
                    working = false
                }
            }
        }
    }) {
        Heading(stringResource(R.string.pair_title), stringResource(R.string.pair_body), stringResource(R.string.setup_step, 2))
        when (val list = consoles) {
            null -> Tile(Modifier.fillMaxWidth()) { Text(stringResource(R.string.pair_searching), style = Tokens.Type.body, color = Tokens.Color.secondary) }
            else -> if (list.isEmpty()) Tile(Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.pair_searching), style = Tokens.Type.headline, color = Tokens.Color.text)
                Text(stringResource(R.string.pair_still_searching), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                TextButton({ searchRound++ }) {
                    Text(stringResource(R.string.pair_search_again), style = Tokens.Type.headline, color = Tokens.Color.accentText)
                }
            } else list.forEach { console ->
                Tile(Modifier.fillMaxWidth(), style = if (host == console.host) TileStyle.ACTIVE else TileStyle.NORMAL, onClick = { host = console.host }) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                        TileIcon(Icons.Filled.Check, Tokens.Color.success)
                        Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
                            Text(stringResource(R.string.pair_found, console.name), style = Tokens.Type.headline, color = Tokens.Color.text)
                            Text(stringResource(R.string.pair_same_wifi, console.host), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                        }
                    }
                }
            }
        }
        if (manual) Field(host, { host = it.trim() }, stringResource(R.string.pair_address), keyboard = KeyboardOptions(keyboardType = KeyboardType.Uri))
        Tile(Modifier.fillMaxWidth()) {
            TileLabel(stringResource(R.string.pair_code))
            // Görünmez alan rakamları alır; kutular gösterir.
            Box {
                CodeCells(code.filter { it.isDigit() })
                BasicTextField(code, { code = it.filter { c -> c.isDigit() }.take(8) }, Modifier.matchParentSizeCompat().alpha(0.01f),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword))
            }
            Text(stringResource(R.string.pair_code_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        }
        problem?.let { NoteTile(stringResource(R.string.pair_failed, it)) }
        if (working) Text(stringResource(R.string.pair_working), style = Tokens.Type.body, color = Tokens.Color.secondary)
    }
}

private fun Modifier.matchParentSizeCompat() = this.fillMaxWidth().height(48.dp)

/** Kayıt hatalarının Türkçesi (Windows'taki iletilerle aynı anlam). */
@Composable
fun registrationErrors(): (RegistrationFailure) -> String {
    val context = LocalContext.current
    return { failure ->
        context.getString(when (failure) {
            RegistrationFailure.WRONG_ACCOUNT -> R.string.regist_wrong_account
            RegistrationFailure.WRONG_CODE -> R.string.regist_wrong_code
            RegistrationFailure.IN_USE -> R.string.regist_in_use
            RegistrationFailure.VERSION_MISMATCH -> R.string.regist_version
            RegistrationFailure.CONSOLE_CRASHED -> R.string.regist_crashed
            RegistrationFailure.BAD_ADDRESS -> R.string.regist_bad_address
            RegistrationFailure.NO_ANSWER -> R.string.regist_no_answer
            RegistrationFailure.NO_REPLY -> R.string.regist_no_reply
            RegistrationFailure.FAILED -> R.string.regist_failed
        })
    }
}

@Composable
fun TargetScreen(onBack: (() -> Unit)? = null, onDone: () -> Unit) {
    val context = LocalContext.current
    val settings = Services.settings
    var target by remember { mutableStateOf(settings.target) }
    var tvs by remember { mutableStateOf<List<FoundTv>?>(null) }
    LaunchedEffect(Unit) { tvs = withContext(Dispatchers.IO) { runCatching { TvDiscovery.search() }.getOrDefault(emptyList()) } }
    ScreenScaffold(top = { TopBar(onBack = onBack) }, bottom = {
        PrimaryButton(stringResource(R.string.next_continue)) {
            settings.target = target
            tvs?.firstOrNull()?.let { settings.tvName = it.name }
            settings.onboarded = true
            onDone()
        }
    }) {
        Heading(stringResource(R.string.target_title), stringResource(R.string.target_body), if (onBack == null) stringResource(R.string.setup_step, 3) else null)
        // Nino: iki seçenek koyu sahnede seçilebilir cam kutular; seçili olan parlak kenarlı ve işaretli.
        val tvDetail = when (val found = tvs) {
            null -> stringResource(R.string.target_searching)
            else -> if (found.isEmpty()) stringResource(R.string.target_tv_over_game) else found.joinToString { it.name }
        }
        OnboardingStage(height = androidx.compose.ui.unit.Dp(250f)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SelectableGlass(Icons.Filled.Tv, stringResource(R.string.target_tv_short), tvDetail, target == SubtitleTarget.TV, Modifier.weight(1f)) { target = SubtitleTarget.TV }
                SelectableGlass(Icons.Filled.Smartphone, stringResource(R.string.target_phone), stringResource(R.string.target_phone_note), target == SubtitleTarget.PHONE, Modifier.weight(1f)) { target = SubtitleTarget.PHONE }
            }
        }
        Text(stringResource(if (target == SubtitleTarget.TV) R.string.target_tv_body else R.string.target_phone_body), fontSize = 15.sp, lineHeight = 21.sp, color = Tokens.Color.secondary)
        GhostButton(stringResource(R.string.target_unlisted)) { open(context, context.getString(R.string.url_tvs)) }
    }
}

/** Koyu sahnede seçilebilir cam kutu (simge, büyük ad, açıklama; seçiliyken parlak kenar ve işaret). */
@Composable
internal fun SelectableGlass(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, detail: String, selected: Boolean,
                             modifier: Modifier, onClick: () -> Unit) {
    Box(modifier.height(190.dp).background(Color.White.copy(alpha = if (selected) 0.16f else 0.06f), RoundedCornerShape(20.dp))
        .border(if (selected) 2.dp else 1.dp, Color.White.copy(alpha = if (selected) 0.85f else 0.12f), RoundedCornerShape(20.dp))
        .clickable(onClick = onClick).padding(16.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(40.dp).background(Color.White.copy(alpha = 0.12f), CircleShape), contentAlignment = Alignment.Center) {
                Icon(icon, null, tint = Color.White, modifier = Modifier.size(22.dp))
            }
            Text(title, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Text(detail, fontSize = 12.sp, color = Color.White.copy(alpha = 0.65f), maxLines = 3)
        }
        if (selected) Box(Modifier.align(Alignment.TopEnd).size(24.dp).background(Color.White, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Check, null, tint = Color(0xFF0A1430), modifier = Modifier.size(16.dp))
        }
    }
}

fun brandName(brand: TvBrand) = when (brand) {
    TvBrand.LG -> "LG"
    TvBrand.SAMSUNG -> "Samsung"
    TvBrand.ANDROID_TV -> "Android TV"
}

/** Nino: karşılama sayfalarının ana görseli: ana ekrandaki koyu sahne kartı, içinde camsı satırlar. */
@Composable
internal fun OnboardingStage(height: androidx.compose.ui.unit.Dp = 380.dp, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(28.dp)
    val ink = Color(0xFF0A1430)
    Column(Modifier.fillMaxWidth().height(height)
        .shadow(28.dp, shape, ambientColor = ink.copy(alpha = 0.5f), spotColor = ink.copy(alpha = 0.5f))
        .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color(0xFF151E36), Color(0xFF06080F))), shape)
        .border(1.dp, androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.22f), Color.White.copy(alpha = 0.03f))), shape)
        .padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically), content = content)
}

/** Koyu sahne üstünde buzlu cam satır: isteğe bağlı kısa ad rozeti, başlık, açıklama, sağda isteğe bağlı etiket. */
@Composable
internal fun GlassRow(monogram: String?, title: String, detail: String, tag: String?) {
    Row(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(18.dp))
        .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(18.dp)).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (monogram != null) Box(Modifier.size(40.dp).background(Color.White.copy(alpha = 0.12f), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
            Text(monogram, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White)
        }
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1)
            Text(detail, fontSize = 12.sp, color = Color.White.copy(alpha = 0.6f), maxLines = 1)
        }
        if (tag != null) Text(tag, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White,
            modifier = Modifier.background(Color(0xFF30C578).copy(alpha = 0.25f), RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 4.dp))
    }
}

/** Koyu sahne üstünde buzlu cam seçenek kutusu (simge, büyük ad, kısa açıklama). */
@Composable
internal fun GlassChoice(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, detail: String, modifier: Modifier) {
    Column(modifier.background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(20.dp))
        .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(20.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(40.dp).background(Color.White.copy(alpha = 0.12f), CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(22.dp))
        }
        Text(title, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Text(detail, fontSize = 12.sp, color = Color.White.copy(alpha = 0.6f))
    }
}

/** Koyu sahne üstünde simgeli buzlu cam satır (PSN ekranındaki güvence satırları gibi). */
@Composable
internal fun GlassIconRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, detail: String) {
    Row(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(18.dp))
        .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(18.dp)).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(40.dp).background(Color.White.copy(alpha = 0.12f), CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            Text(detail, fontSize = 12.sp, color = Color.White.copy(alpha = 0.6f))
        }
    }
}
