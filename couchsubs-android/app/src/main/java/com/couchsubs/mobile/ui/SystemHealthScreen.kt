// SPDX-License-Identifier: AGPL-3.0-only
// Nino: Ayarlar › Sistem sağlığı (Mac'teki SystemHealthView.swift'in telefon karşılığı).
// Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-15.
package com.couchsubs.mobile.ui

import com.couchsubs.mobile.R
import androidx.compose.ui.res.stringResource
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.BuildConfig
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.account.ThisDevice
import com.couchsubs.mobile.core.DeviceInfo
import com.couchsubs.mobile.core.HealthLevel
import com.couchsubs.mobile.core.HealthReport
import com.couchsubs.mobile.core.HealthSnapshot
import com.couchsubs.mobile.core.NetworkKind
import com.couchsubs.mobile.service.LiveState
import com.couchsubs.mobile.service.LiveStatus
import com.couchsubs.mobile.settings.SubtitleTarget
import kotlinx.coroutines.delay

/** Telefonun şu anki ağı. */
fun networkKind(context: Context): NetworkKind {
    val manager = context.getSystemService(ConnectivityManager::class.java) ?: return NetworkKind.OTHER
    val caps = manager.getNetworkCapabilities(manager.activeNetwork) ?: return NetworkKind.OFFLINE
    return when {
        caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> NetworkKind.WIRED
        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> NetworkKind.WIFI
        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> NetworkKind.CELLULAR
        else -> NetworkKind.OTHER
    }
}

private fun HealthLevel.color(): Color = when (this) {
    HealthLevel.GOOD -> Color(0xFF2EA043)
    HealthLevel.WARNING -> Color(0xFFE3A008)
    HealthLevel.PROBLEM -> Color(0xFFD93025)
    HealthLevel.UNKNOWN -> Color(0xFFB0B8C8)
}

private data class HealthRow(val title: String, val value: String, val level: HealthLevel, val advice: String? = null)

@Composable
fun SystemHealthScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val status by LiveState.status.collectAsState()
    var snapshot by remember { mutableStateOf(LiveState.health.snapshot()) }
    var network by remember { mutableStateOf(networkKind(context)) }
    var details by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        while (true) {
            snapshot = LiveState.health.snapshot()
            network = networkKind(context)
            delay(1000)
        }
    }
    val rows = rows(context, snapshot, network, status.connectedTvs, status.running)
    val worst = rows.maxOf { it.level.ordinal }.let { HealthLevel.entries[it] }

    ScreenScaffold(top = { TopBar(stringResource(R.string.nino_system_health), onBack = onBack) }) {
        Tile(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                Box(Modifier.size(14.dp).background(worst.color(), CircleShape))
                Text(stringResource(when {
                    snapshot.isEmpty -> R.string.nino_health_measured_on_start
                    worst == HealthLevel.PROBLEM -> R.string.nino_health_problem
                    worst == HealthLevel.WARNING -> R.string.nino_health_warning
                    worst == HealthLevel.GOOD -> R.string.nino_health_good
                    else -> R.string.nino_health_measuring
                }), style = Tokens.Type.headline, color = Tokens.Color.text)
            }
            Text(stringResource(R.string.nino_health_intro),
                style = Tokens.Type.caption, color = Tokens.Color.secondary)
        }
        RowList(rows.map { row ->
            {
                Row(Modifier.padding(vertical = Tokens.Space.inline), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                    Box(Modifier.padding(top = 5.dp).size(10.dp).background(row.level.color(), CircleShape))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
                        Row {
                            Text(row.title, style = Tokens.Type.body, color = Tokens.Color.text, modifier = Modifier.weight(1f))
                            Text(row.value, style = Tokens.Type.body, color = Tokens.Color.secondary)
                        }
                        row.advice?.let { Text(it, style = Tokens.Type.caption, color = Tokens.Color.secondary) }
                    }
                }
            }
        })
        Tile(Modifier.fillMaxWidth(), onClick = { details = !details }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.nino_health_details), style = Tokens.Type.headline, color = Tokens.Color.text, modifier = Modifier.weight(1f))
                Text(stringResource(if (details) R.string.nino_hide else R.string.nino_show), style = Tokens.Type.caption, color = Tokens.Color.accentText)
            }
            Text(stringResource(R.string.nino_health_send_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            if (details) {
                val text = detailsText(snapshot, network, status.connectedTvs)
                Text(text, fontFamily = FontFamily.Monospace, fontSize = 12.sp, color = Tokens.Color.text)
                val shareTitle = stringResource(R.string.nino_health_share)
                SecondaryButton(shareTitle) {
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
                    context.startActivity(Intent.createChooser(send, shareTitle).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }
        }
        DeviceInfoCard(status)
    }
}

/**
 * Nino: "Cihaz bilgileri". Sorun Bildir ve Nino'ya Sor'a eklenen özetin aynısı: uygulama sürümü, telefonun modeli,
 * Android sürümü, TV, konsol ve şu anki durum (bilinmeyen satır gösterilmez). Ad, seri numarası ya da adres içermez.
 * Düğme özeti panoya kopyalar (destek yazışmasına yapıştırmak için).
 */
@Composable
private fun DeviceInfoCard(status: LiveStatus) {
    val context = LocalContext.current
    // Durum değiştikçe (bağlanıyor, hata) satırlar yenilenir.
    val rows = remember(status.running, status.phase, status.error) { ThisDevice.rows(status = status) }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(2000)
            copied = false
        }
    }
    Tile(Modifier.fillMaxWidth()) {
        Text(stringResource(R.string.device_info_title), style = Tokens.Type.headline, color = Tokens.Color.text)
        Text(stringResource(R.string.device_info_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        rows.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                Text(stringResource(when (row.id) {
                    "app" -> R.string.device_info_app
                    "device" -> R.string.device_info_device
                    "system" -> R.string.device_info_system
                    "tv" -> R.string.device_info_tv
                    "console" -> R.string.device_info_console
                    else -> R.string.device_info_status
                }), style = Tokens.Type.body, color = Tokens.Color.secondary)
                Text(row.value, style = Tokens.Type.body, color = Tokens.Color.text, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
            }
        }
        SecondaryButton(stringResource(if (copied) R.string.history_copied else R.string.device_info_copy)) {
            context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("Nino", DeviceInfo.summary(rows)))
            copied = true
        }
    }
}

private fun rows(context: android.content.Context, s: HealthSnapshot, network: NetworkKind, tvs: Int, running: Boolean): List<HealthRow> {
    fun t(id: Int, vararg args: Any) = context.getString(id, *args)
    val stream = HealthReport.stream(s)
    val net = HealthReport.network(network, stream)
    val list = mutableListOf(
        HealthRow(t(R.string.nino_health_network), when (network) {
            NetworkKind.WIFI -> "Wi-Fi"
            NetworkKind.WIRED -> t(R.string.nino_net_wired)
            NetworkKind.CELLULAR -> t(R.string.nino_net_cellular)
            NetworkKind.OFFLINE -> t(R.string.nino_net_offline)
            NetworkKind.OTHER -> t(R.string.nino_net_other)
        }, net, when {
            network == NetworkKind.OFFLINE -> t(R.string.nino_net_offline_advice)
            network == NetworkKind.CELLULAR -> t(R.string.nino_net_cellular_advice)
            net == HealthLevel.PROBLEM || net == HealthLevel.WARNING -> t(R.string.nino_net_weak_advice)
            else -> null
        }),
    )
    val connection = HealthReport.connection(s)
    list += HealthRow(t(R.string.nino_health_ps5), when {
        s.everStreamed && s.drops == 0 -> t(R.string.nino_connected)
        s.everStreamed -> t(R.string.nino_dropped_times, s.drops)
        s.failedConnects > 0 -> t(R.string.nino_could_not_connect)
        else -> "—"
    }, connection, when (connection) {
        HealthLevel.PROBLEM -> t(R.string.nino_ps5_problem_advice)
        HealthLevel.WARNING -> t(R.string.nino_ps5_warning_advice)
        else -> null
    })
    list += HealthRow(t(R.string.nino_health_picture), s.framesPerSecond?.let { t(R.string.nino_fps, "%.0f".format(it)) } ?: "—", stream, when (stream) {
        HealthLevel.PROBLEM, HealthLevel.WARNING -> t(R.string.nino_picture_advice)
        else -> null
    })
    val translation = HealthReport.translation(s)
    list += HealthRow(t(R.string.nino_health_translation), s.translationMedianMs?.let { t(R.string.nino_seconds, "%.1f".format(it / 1000.0)) } ?: "—", translation, when (translation) {
        HealthLevel.PROBLEM, HealthLevel.WARNING -> t(R.string.nino_translation_advice)
        else -> null
    })
    if (Services.settings.target == SubtitleTarget.TV) {
        list += HealthRow("TV", if (tvs > 0) t(R.string.nino_connected) else if (running) t(R.string.nino_waiting) else "—",
            if (tvs > 0) HealthLevel.GOOD else if (running && s.everStreamed) HealthLevel.WARNING else HealthLevel.UNKNOWN,
            if (tvs == 0 && running && s.everStreamed) t(R.string.nino_tv_advice) else null)
    }
    return list
}

private fun detailsText(s: HealthSnapshot, network: NetworkKind, tvs: Int): String = buildString {
    appendLine("Nino Android ${BuildConfig.VERSION_NAME}")
    appendLine("cihaz: ${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE}")
    appendLine("çıkış: ${Services.settings.target.name.lowercase()}, bağlı TV: $tvs, motor: ${Services.settings.engine.name.lowercase()}")
    appendLine("oturum: ${if (s.active) "sürüyor" else "bitti"}")
    append(HealthReport.summary(s, network))
}
