// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı.
package com.couchsubs.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.core.TargetLanguage

/**
 * Çeviri dili seçici: seçili dilin bayrağı ve kendi dilindeki adı; basınca bütün diller bayraklarıyla açılır (Türkçe
 * en üstte). [compact]: karşılama ekranının sağ üstündeki küçük hap; değilse Ayarlar'daki tam genişlik satır.
 */
@Composable
fun TargetLanguageMenu(selected: String, compact: Boolean = false, onSelect: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val code = TargetLanguage.code(selected)
    Box {
        val shape = RoundedCornerShape(if (compact) 50 else 12)
        Row(
            (if (compact) Modifier.height(36.dp) else Modifier.fillMaxWidth().height(44.dp))
                .background(if (compact) Color.White.copy(alpha = 0.10f) else Tokens.Color.surface2, shape)
                .border(1.dp, if (compact) Color.White.copy(alpha = 0.18f) else Color.Transparent, shape)
                .clickable { open = true }
                .semantics { contentDescription = TargetLanguage.nativeName(code) }
                .padding(horizontal = if (compact) 12.dp else 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(TargetLanguage.flag(code), fontSize = if (compact) 18.sp else 20.sp)
            Text(TargetLanguage.nativeName(code), style = Tokens.Type.body.copy(fontWeight = FontWeight.SemiBold),
                color = Tokens.Color.text, maxLines = 1)
            if (!compact) Spacer(Modifier.weight(1f))
            Icon(Icons.Filled.KeyboardArrowDown, null, tint = Tokens.Color.secondary, modifier = Modifier.size(20.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            TargetLanguage.choices.forEach { (choice, name) ->
                DropdownMenuItem(
                    text = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(TargetLanguage.flag(choice), fontSize = 20.sp)
                            Spacer(Modifier.width(12.dp))
                            Text(name, style = Tokens.Type.body)
                        }
                    },
                    trailingIcon = { if (choice == code) Icon(Icons.Filled.Check, null, tint = Tokens.Color.accent) },
                    onClick = { open = false; onSelect(choice) },
                )
            }
        }
    }
}
