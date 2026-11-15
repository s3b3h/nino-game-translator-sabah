// SPDX-License-Identifier: AGPL-3.0-only
// Nino: Ayarlar › Sistem sağlığı (Mac'teki SystemHealthView.swift'in telefon karşılığı).
// Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-15.
package com.couchsubs.mobile.ui

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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.BuildConfig
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.core.HealthLevel
import com.couchsubs.mobile.core.HealthReport
import com.couchsubs.mobile.core.HealthSnapshot
import com.couchsubs.mobile.core.NetworkKind
import com.couchsubs.mobile.service.LiveState
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
    val rows = rows(snapshot, network, status.connectedTvs, status.running)
    val worst = rows.maxOf { it.level.ordinal }.let { HealthLevel.entries[it] }

    ScreenScaffold(top = { TopBar("Sistem sağlığı", onBack = onBack) }) {
        Tile(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                Box(Modifier.size(14.dp).background(worst.color(), CircleShape))
                Text(when {
                    snapshot.isEmpty -> "Çeviriyi başlatınca ölçülür"
                    worst == HealthLevel.PROBLEM -> "Bir sorun var"
                    worst == HealthLevel.WARNING -> "Dikkat edilecek bir şey var"
                    worst == HealthLevel.GOOD -> "Her şey yolunda"
                    else -> "Ölçülüyor…"
                }, style = Tokens.Type.headline, color = Tokens.Color.text)
            }
            Text("Telefonun ağı, PS5 bağlantısı, görüntünün akıcılığı ve çeviri hızı. Sorun olursa ne yapılacağı yazar.",
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
                Text("Ayrıntılar", style = Tokens.Type.headline, color = Tokens.Color.text, modifier = Modifier.weight(1f))
                Text(if (details) "Gizle" else "Göster", style = Tokens.Type.caption, color = Tokens.Color.accentText)
            }
            Text("Sorun yaşarsanız bunu yardım eden kişiye gönderin.", style = Tokens.Type.caption, color = Tokens.Color.secondary)
            if (details) {
                val text = detailsText(snapshot, network, status.connectedTvs)
                Text(text, fontFamily = FontFamily.Monospace, fontSize = 12.sp, color = Tokens.Color.text)
                SecondaryButton("Ayrıntıları paylaş") {
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
                    context.startActivity(Intent.createChooser(send, "Ayrıntıları paylaş").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }
        }
    }
}

private fun rows(s: HealthSnapshot, network: NetworkKind, tvs: Int, running: Boolean): List<HealthRow> {
    val stream = HealthReport.stream(s)
    val net = HealthReport.network(network, stream)
    val list = mutableListOf(
        HealthRow("Ağ", when (network) {
            NetworkKind.WIFI -> "Wi-Fi"
            NetworkKind.WIRED -> "Kablo"
            NetworkKind.CELLULAR -> "Mobil veri"
            NetworkKind.OFFLINE -> "Bağlı değil"
            NetworkKind.OTHER -> "Diğer"
        }, net, when {
            network == NetworkKind.OFFLINE -> "Telefon internete ya da ev ağına bağlı değil."
            network == NetworkKind.CELLULAR -> "PS5 ile aynı Wi-Fi ağına bağlanın; mobil veride PS5 bulunamaz."
            net == HealthLevel.PROBLEM || net == HealthLevel.WARNING -> "Wi-Fi zayıf görünüyor. Modeme yaklaşın, 5 GHz ağı kullanın, PS5'i kabloyla bağlayın."
            else -> null
        }),
    )
    val connection = HealthReport.connection(s)
    list += HealthRow("PS5 bağlantısı", when {
        s.everStreamed && s.drops == 0 -> "Bağlı"
        s.everStreamed -> "${s.drops} kez koptu"
        s.failedConnects > 0 -> "Bağlanamadı"
        else -> "—"
    }, connection, when (connection) {
        HealthLevel.PROBLEM -> "PS5 açık mı, aynı ağda mı? Dinlenme modundaysa Ayarlar › Güç Tasarrufu'nda \"İnternete bağlı kal\" ve \"Ağdan açmaya izin ver\" açık olmalı."
        HealthLevel.WARNING -> "Bağlantı sık kopuyor; ağ zayıf olabilir."
        else -> null
    })
    list += HealthRow("Görüntü", s.framesPerSecond?.let { "%.0f kare/sn".format(it) } ?: "—", stream, when (stream) {
        HealthLevel.PROBLEM, HealthLevel.WARNING -> "PS5 görüntüsü kesik geliyor; altyazılar geç ya da eksik okunabilir. Çoğu zaman sebep Wi-Fi'dir."
        else -> null
    })
    val translation = HealthReport.translation(s)
    list += HealthRow("Çeviri hızı", s.translationMedianMs?.let { "%.1f sn".format(it / 1000.0) } ?: "—", translation, when (translation) {
        HealthLevel.PROBLEM, HealthLevel.WARNING -> "Çeviri yavaş. İnternet yavaş olabilir; Ayarlar'dan başka bir çeviri motoru deneyin."
        else -> null
    })
    if (Services.settings.target == SubtitleTarget.TV) {
        list += HealthRow("TV", if (tvs > 0) "Bağlı" else if (running) "Bekleniyor" else "—",
            if (tvs > 0) HealthLevel.GOOD else if (running && s.everStreamed) HealthLevel.WARNING else HealthLevel.UNKNOWN,
            if (tvs == 0 && running && s.everStreamed) "TV'de Nino uygulamasını açın; telefonla TV aynı ağda olmalı." else null)
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
