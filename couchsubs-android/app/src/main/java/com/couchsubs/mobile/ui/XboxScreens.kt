// SPDX-License-Identifier: AGPL-3.0-only
// Nino: konsol seçimi (PS5 / Xbox) ve Xbox kurulumu (Microsoft girişi + konsol seçimi). Sıfırdan yazıldı.
package com.couchsubs.mobile.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Gamepad
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.settings.VideoSource
import com.couchsubs.mobile.xbox.DeviceCode
import com.couchsubs.mobile.xbox.DeviceCodePoll
import com.couchsubs.mobile.xbox.XboxAccount
import com.couchsubs.mobile.xbox.XboxAuth
import com.couchsubs.mobile.xbox.XboxConsole
import com.couchsubs.mobile.xbox.XboxException
import com.couchsubs.mobile.xbox.XboxStep
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Kurulumun ilk sorusu: hangi konsolda oynuyorsunuz? (Altyazı hedefi ekranıyla aynı kimlik: koyu sahnede iki cam kutu.)
 * Yakalama kartı Ayarlar › Görüntü Kaynağı'ndan seçilir.
 */
@Composable
fun ConsoleScreen(onBack: (() -> Unit)?, onDone: () -> Unit) {
    val settings = Services.settings
    var xbox by remember { mutableStateOf(settings.usesXbox) }
    ScreenScaffold(top = { TopBar(onBack = onBack) }, bottom = {
        PrimaryButton(stringResource(R.string.next)) {
            settings.videoSource = if (xbox) VideoSource.XBOX else VideoSource.REMOTE_PLAY
            settings.consoleAsked = true
            onDone()
        }
    }) {
        Heading(stringResource(R.string.console_title), stringResource(R.string.console_body))
        OnboardingStage(height = 250.dp) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SelectableGlass(Icons.Filled.SportsEsports, "PS5", stringResource(R.string.console_ps5_detail), !xbox, Modifier.weight(1f)) { xbox = false }
                SelectableGlass(Icons.Filled.Gamepad, "Xbox", stringResource(R.string.console_xbox_detail), xbox, Modifier.weight(1f)) { xbox = true }
            }
        }
        Text(stringResource(if (xbox) R.string.console_xbox_body else R.string.console_ps5_body), fontSize = 15.sp, lineHeight = 21.sp, color = Tokens.Color.secondary)
    }
}

/** Xbox kurulumunun adımları. */
private sealed class XboxPhase {
    data object SignIn : XboxPhase()
    data object Requesting : XboxPhase()
    data class Code(val code: DeviceCode) : XboxPhase()
    data object Loading : XboxPhase()
    data class Consoles(val list: List<XboxConsole>) : XboxPhase()
}

/**
 * Xbox kurulumu: Microsoft hesabıyla giriş (şifre Nino'ya yazılmaz; microsoft.com/link'te kod girilir), ardından
 * hesaptaki konsollardan biri seçilir. Konsolda Ayarlar › Cihazlar ve bağlantılar › Uzak özellikler açık olmalı.
 */
@Composable
fun XboxScreen(onBack: (() -> Unit)?, onSkip: (() -> Unit)? = null, onDone: () -> Unit) {
    val context = LocalContext.current
    val settings = Services.settings
    val account = remember { XboxAccount(settings) }
    val auth = remember { XboxAuth() }
    var phase by remember { mutableStateOf<XboxPhase>(if (account.signedIn) XboxPhase.Loading else XboxPhase.SignIn) }
    var error by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf(settings.xboxConsole?.serverId) }
    val messages = xboxErrors()

    // Kod gösterilirken Microsoft'a onaylandı mı diye sorulur (Microsoft'un istediği aralıkla).
    val current = phase
    LaunchedEffect(current) {
        when (current) {
            is XboxPhase.Requesting -> phase = try {
                XboxPhase.Code(withContext(Dispatchers.IO) { auth.requestDeviceCode() })
            } catch (failure: Exception) {
                error = messages(failure)
                XboxPhase.SignIn
            }
            is XboxPhase.Code -> {
                var interval = current.code.intervalSeconds * 1000L
                val deadline = System.currentTimeMillis() + current.code.expiresInSeconds * 1000L
                while (System.currentTimeMillis() < deadline) {
                    delay(interval)
                    val result = try { withContext(Dispatchers.IO) { auth.pollDeviceCode(current.code) } } catch (failure: Exception) { DeviceCodePoll.Pending }
                    when (result) {
                        DeviceCodePoll.Pending -> {}
                        DeviceCodePoll.SlowDown -> interval += 5000
                        is DeviceCodePoll.Done -> {
                            account.save(result.tokens)
                            phase = XboxPhase.Loading
                            return@LaunchedEffect
                        }
                        is DeviceCodePoll.Failed -> break
                    }
                }
                error = context.getString(R.string.xbox_code_expired)
                phase = XboxPhase.SignIn
            }
            is XboxPhase.Loading -> phase = try {
                val list = withContext(Dispatchers.IO) { account.consoles() }
                if (selected == null || list.none { it.serverId == selected }) selected = list.firstOrNull()?.serverId
                error = if (list.isEmpty()) context.getString(R.string.xbox_no_consoles) else null
                XboxPhase.Consoles(list)
            } catch (failure: Exception) {
                error = messages(failure)
                if (!account.signedIn) XboxPhase.SignIn else XboxPhase.Consoles(emptyList())
            }
            else -> {}
        }
    }

    ScreenScaffold(top = { TopBar(onBack = onBack, actions = { SkipAction(onSkip) }) }, bottom = {
        when (val p = phase) {
            XboxPhase.SignIn -> PrimaryButton(stringResource(R.string.xbox_sign_in)) { error = null; phase = XboxPhase.Requesting }
            is XboxPhase.Code -> PrimaryButton(stringResource(R.string.xbox_open_link)) {
                copy(context, p.code.userCode)
                open(context, p.code.verificationUri)
            }
            is XboxPhase.Consoles -> {
                val chosen = p.list.firstOrNull { it.serverId == selected }
                if (p.list.isEmpty()) PrimaryButton(stringResource(R.string.xbox_retry)) { phase = XboxPhase.Loading }
                else PrimaryButton(stringResource(R.string.save), enabled = chosen != null) {
                    settings.xboxConsole = chosen
                    settings.videoSource = VideoSource.XBOX
                    onDone()
                }
                GhostButton(stringResource(R.string.xbox_sign_out), color = Tokens.Color.secondary) {
                    account.signOut()
                    selected = null
                    error = null
                    phase = XboxPhase.SignIn
                }
            }
            else -> PrimaryButton(stringResource(R.string.xbox_working), enabled = false) {}
        }
    }) {
        Heading(stringResource(R.string.xbox_title), stringResource(
            if (phase is XboxPhase.Consoles) R.string.xbox_consoles_body else R.string.xbox_sign_in_body))
        OnboardingStage(height = 290.dp) {
            when (val p = phase) {
                is XboxPhase.Code -> CodeCard(p.code)
                is XboxPhase.Consoles -> if (p.list.isEmpty()) GlassRow("X", stringResource(R.string.xbox_no_consoles_title), stringResource(R.string.xbox_remote_hint), null)
                    else p.list.take(3).forEach { console ->
                        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).clickable { selected = console.serverId }) {
                            GlassRow("X", console.name, XboxConsole.typeName(console.type) + " · " + powerText(console),
                                if (console.serverId == selected) stringResource(R.string.selected) else null)
                        }
                    }
                else -> {
                    GlassRow("1", stringResource(R.string.xbox_step_remote), stringResource(R.string.xbox_remote_hint), null)
                    GlassRow("2", stringResource(R.string.xbox_step_account), stringResource(R.string.xbox_account_hint), null)
                    GlassRow("3", stringResource(R.string.xbox_step_code), stringResource(R.string.xbox_code_hint), null)
                }
            }
        }
        error?.let { NoteTile(it) }
        Text(stringResource(R.string.xbox_privacy), fontSize = 13.sp, lineHeight = 18.sp, color = Tokens.Color.secondary)
    }
}

@Composable
private fun CodeCard(code: DeviceCode) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(R.string.xbox_code_label), fontSize = 14.sp, color = Color.White.copy(alpha = 0.7f))
        Text(code.userCode, fontSize = 40.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, letterSpacing = 4.sp, color = Color.White)
        Text(code.verificationUri.removePrefix("https://").removePrefix("www."), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        Text(stringResource(R.string.xbox_code_waiting), fontSize = 13.sp, color = Color.White.copy(alpha = 0.6f))
    }
}

@Composable
private fun powerText(console: XboxConsole) = stringResource(when (console.powerState) {
    "On" -> R.string.xbox_power_on
    "ConnectedStandby" -> R.string.xbox_power_standby
    else -> R.string.xbox_power_off
})

private fun copy(context: Context, text: String) {
    try {
        context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("Microsoft", text))
    } catch (error: Exception) {
    }
}

/** Xbox hatalarının kullanıcıya anlatımı. */
@Composable
fun xboxErrors(): (Exception) -> String {
    val signIn = stringResource(R.string.xbox_error_sign_in)
    val signedOut = stringResource(R.string.xbox_phase_signed_out)
    val live = stringResource(R.string.xbox_error_live)
    val streaming = stringResource(R.string.xbox_error_streaming)
    val network = stringResource(R.string.xbox_error_network)
    return { error ->
        when ((error as? XboxException)?.step) {
            XboxStep.SIGN_IN -> signIn
            XboxStep.SIGNED_OUT -> signedOut
            XboxStep.XBOX_LIVE -> live
            XboxStep.STREAMING, XboxStep.CONSOLES, XboxStep.SESSION -> streaming
            null -> network
        }
    }
}
