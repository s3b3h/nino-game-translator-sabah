// SPDX-License-Identifier: AGPL-3.0-only
// Nino: Ayarlar › Görüntü Kaynağı: PS5 (Remote Play) ya da Yakalama Kartı (USB-C ile takılı HDMI kartı).
package com.couchsubs.mobile.ui

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Gamepad
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.capture.CameraInfo
import com.couchsubs.mobile.capture.CaptureCardPicker
import com.couchsubs.mobile.capture.CaptureCards
import com.couchsubs.mobile.settings.VideoSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** Ayarlar satırında görünen kısa ad. */
@Composable
fun videoSourceName(source: VideoSource = Services.settings.videoSource): String =
    stringResource(when (source) {
        VideoSource.CAPTURE_CARD -> R.string.capture_card
        VideoSource.XBOX -> R.string.source_xbox
        VideoSource.REMOTE_PLAY -> R.string.source_remote_play
    })

/**
 * Görüntü kaynağı seçimi (Altyazı hedefi ekranıyla aynı kimlik: koyu sahnede iki cam kutu). Yakalama kartı seçiliyken
 * takılı kart canlı aranır (kart sonradan takılınca kendiliğinden görünür); kaydederken kamera izni istenir.
 */
@Composable
fun SourceScreen(onBack: (() -> Unit)?, onDone: () -> Unit) {
    val context = LocalContext.current
    val settings = Services.settings
    var source by remember { mutableStateOf(settings.videoSource) }
    var card by remember { mutableStateOf<CameraInfo?>(null) }
    var checked by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        while (true) {
            card = withContext(Dispatchers.IO) { CaptureCards.find(context) }
            checked = true
            delay(1500)
        }
    }
    val permissionMessage = stringResource(R.string.capture_no_permission)
    fun save() {
        settings.videoSource = source
        // Önceki "kamera izni yok" uyarısı kaynak değişince ya da izin verilince kalmasın.
        if (source != VideoSource.CAPTURE_CARD || CaptureCards.hasPermission(context))
            com.couchsubs.mobile.service.LiveState.update { if (it.error == permissionMessage) it.copy(error = null) else it }
        onDone()
    }
    // İzin verilmese de seçim kaydedilir; çeviri başlarken izin yeniden istenir ve sorun ana ekranda yazılır.
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { save() }
    val cardMode = source == VideoSource.CAPTURE_CARD
    ScreenScaffold(top = { TopBar(onBack = onBack) }, bottom = {
        PrimaryButton(stringResource(R.string.save)) {
            if (cardMode && !CaptureCards.hasPermission(context)) permission.launch(Manifest.permission.CAMERA) else save()
        }
    }) {
        Heading(stringResource(R.string.settings_video_source), stringResource(R.string.source_body))
        OnboardingStage(height = if (cardMode) 316.dp else 250.dp) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SelectableGlass(Icons.Filled.SportsEsports, "PS5", stringResource(R.string.source_ps5_detail), source == VideoSource.REMOTE_PLAY, Modifier.weight(1f)) {
                    source = VideoSource.REMOTE_PLAY
                }
                // Nino: Xbox ev yayını (Microsoft hesabı).
                SelectableGlass(Icons.Filled.Gamepad, "Xbox", stringResource(R.string.source_xbox_detail), source == VideoSource.XBOX, Modifier.weight(1f)) {
                    source = VideoSource.XBOX
                }
                SelectableGlass(Icons.Filled.Usb, stringResource(R.string.capture_card), stringResource(R.string.source_card_detail), cardMode, Modifier.weight(1f)) {
                    source = VideoSource.CAPTURE_CARD
                }
            }
            if (cardMode) {
                val found = card
                if (found != null) GlassRow("USB", stringResource(R.string.capture_found_title),
                    stringResource(R.string.capture_found_detail, CaptureCardPicker.size(found.yuvSizes)?.toString() ?: "—"), stringResource(R.string.capture_ready))
                else GlassRow("USB", stringResource(R.string.capture_missing_title), stringResource(R.string.capture_missing_detail), null)
            }
        }
        Text(stringResource(if (cardMode) R.string.source_card_body else if (source == VideoSource.XBOX) R.string.source_xbox_body else R.string.source_ps5_body), fontSize = 15.sp, lineHeight = 21.sp, color = Tokens.Color.secondary)
        if (cardMode) {
            if (checked && card == null) NoteTile(stringResource(R.string.capture_not_found))
            Text(stringResource(R.string.source_hdcp), fontSize = 13.sp, lineHeight = 18.sp, color = Tokens.Color.secondary)
        }
    }
}
