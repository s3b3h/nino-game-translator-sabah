// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "Sorun Bildir" (Ayarlar ve Profil'den). Açıklama, en çok 3 fotoğraf, isteğe bağlı iletişim ve uygulama günlüğü.
package com.couchsubs.mobile.ui

import android.graphics.BitmapFactory
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.BuildConfig
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.account.ProblemReport
import com.couchsubs.mobile.account.ReportAttachments
import com.couchsubs.mobile.account.ThisDevice
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Seçilmiş, gönderime hazır fotoğraf: küçültülmüş JPEG ve küçük resmi. */
private class ReportPhoto(val jpeg: ByteArray, val thumbnail: ImageBitmap)

@Composable
fun ReportProblemScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf("") }
    var contact by remember { mutableStateOf("") }
    var includeLog by remember { mutableStateOf(true) }
    val photos = remember { mutableStateListOf<ReportPhoto>() }
    var loadingPhotos by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    // Android'in fotoğraf seçicisi: izin istemez; yalnız görüntüler, kalan yer kadarı alınır.
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(ProblemReport.MAX_IMAGES)) { uris ->
        val room = ProblemReport.MAX_IMAGES - photos.size
        val chosen = uris.take(room.coerceAtLeast(0))
        if (chosen.isEmpty()) return@rememberLauncherForActivityResult
        loadingPhotos = true
        scope.launch {
            val loaded = withContext(Dispatchers.Default) {
                chosen.map { uri ->
                    ReportAttachments.loadImage(context, uri)?.let { jpeg ->
                        // Küçük resim için 1/4 boy yeter (1600 px → 400 px).
                        val options = BitmapFactory.Options().apply { inSampleSize = 4 }
                        BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, options)?.let { ReportPhoto(jpeg, it.asImageBitmap()) }
                    }
                }
            }
            loaded.filterNotNull().forEach { if (photos.size < ProblemReport.MAX_IMAGES) photos.add(it) }
            error = if (loaded.any { it == null }) context.getString(R.string.report_photo_failed) else null
            loadingPhotos = false
        }
    }

    fun send() {
        val description = text.trim()
        if (description.isEmpty() || sending) return
        sending = true
        error = null
        val jpegs = photos.map { it.jpeg }
        scope.launch {
            val outcome = withContext(Dispatchers.IO) {
                val filesDir = context.filesDir
                val prefs = context.getSharedPreferences("report", android.content.Context.MODE_PRIVATE)
                val install = ProblemReport.installId(filesDir, { prefs.getString("install", null) },
                    { prefs.edit().putString("install", it).apply() })
                val log = if (includeLog) ReportAttachments.recentLog() else null
                // Nino: cihaz bilgileri (model, Android sürümü, TV, konsol) gönderim anında okunur; ad ya da adres içermez.
                val body = ProblemReport.body(install, BuildConfig.VERSION_NAME, Services.settings.targetLanguage,
                    description, contact, log, jpegs, device = ThisDevice.summary())
                val endpoint = ProblemReport.endpoint(filesDir)
                if (endpoint == null) ProblemReport.Outcome.FAILED else ProblemReport.send(endpoint, body)
            }
            sending = false
            when (outcome) {
                ProblemReport.Outcome.SENT -> {
                    Toast.makeText(context, R.string.report_thanks, Toast.LENGTH_LONG).show()
                    onBack()
                }
                ProblemReport.Outcome.RATE_LIMITED -> error = context.getString(R.string.report_rate_limited)
                ProblemReport.Outcome.TOO_LARGE -> error = context.getString(R.string.report_too_large)
                ProblemReport.Outcome.INVALID -> error = context.getString(R.string.report_invalid)
                ProblemReport.Outcome.FAILED -> error = context.getString(R.string.report_failed)
            }
        }
    }

    ScreenScaffold(
        top = { TopBar(stringResource(R.string.report_title), onBack = onBack) },
        bottom = {
            PrimaryButton(stringResource(if (sending) R.string.report_sending else R.string.report_send), Modifier.fillMaxWidth(),
                enabled = text.isNotBlank() && !sending && !loadingPhotos) { send() }
        },
    ) {
        Field(text, { text = it.take(ProblemReport.MAX_TEXT) }, stringResource(R.string.report_description), lines = 5)
        Tile(Modifier.fillMaxWidth()) {
            TileLabel(stringResource(R.string.report_photos))
            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                photos.forEach { photo ->
                    Box(Modifier.size(84.dp)) {
                        Image(photo.thumbnail, null, Modifier.fillMaxSize().clip(RoundedCornerShape(Tokens.Radius.control)),
                            contentScale = ContentScale.Crop)
                        val remove = stringResource(R.string.report_remove_photo)
                        Box(Modifier.align(Alignment.TopEnd).padding(4.dp).size(24.dp).background(Tokens.Color.raised, CircleShape)
                            .border(1.dp, Tokens.Color.borderStrong, CircleShape).clickable(onClickLabel = remove) { photos.remove(photo) },
                            contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.Close, remove, Modifier.size(14.dp), tint = Tokens.Color.text)
                        }
                    }
                }
                if (photos.size < ProblemReport.MAX_IMAGES) {
                    val add = stringResource(R.string.report_add_photo)
                    Box(Modifier.size(84.dp).border(1.dp, Tokens.Color.borderStrong, RoundedCornerShape(Tokens.Radius.control))
                        .clickable(enabled = !loadingPhotos && !sending, onClickLabel = add) {
                            picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        }, contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.Add, add, tint = Tokens.Color.secondary)
                    }
                }
            }
        }
        Field(contact, { contact = it.take(ProblemReport.MAX_CONTACT) }, stringResource(R.string.report_contact))
        RowList(listOf({
            RowItem(stringResource(R.string.report_include_log), stringResource(R.string.report_include_log_note)) {
                Switch(includeLog, { includeLog = it })
            }
        }))
        error?.let { NoteTile(it) }
        Text(stringResource(R.string.report_privacy), style = Tokens.Type.caption, color = Tokens.Color.secondary)
    }
}
