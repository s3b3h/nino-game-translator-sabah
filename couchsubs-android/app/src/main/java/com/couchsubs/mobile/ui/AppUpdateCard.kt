// SPDX-License-Identifier: AGPL-3.0-only
// Nino: ana ekrandaki sakin "Yeni sürüm hazır" kartı (GitHub'dan kurulan telefon uygulaması için).
// Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-18.
package com.couchsubs.mobile.ui

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.update.AppUpdate

/** Yeni sürüm varsa: başlık, kısa açıklama, "Güncelle" (APK'yı tarayıcıda indirir) ve bu sürümü gizleyen ✕. */
@Composable
internal fun AppUpdateCard() {
    val context = LocalContext.current
    val version by AppUpdate.available.collectAsState()
    val latest = version ?: return
    Tile(Modifier.fillMaxWidth(), style = TileStyle.ACTIVE) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.app_update_title, latest), style = Tokens.Type.headline, color = Tokens.Color.text,
                modifier = Modifier.weight(1f))
            IconButton(onClick = { AppUpdate.dismiss(context, latest) }, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close), tint = Tokens.Color.secondary,
                    modifier = Modifier.size(18.dp))
            }
        }
        Text(stringResource(R.string.app_update_body), style = Tokens.Type.body, color = Tokens.Color.secondary)
        PrimaryButton(stringResource(R.string.app_update_button), Modifier.fillMaxWidth()) { open(context, AppUpdate.DOWNLOAD_URL) }
    }
}
