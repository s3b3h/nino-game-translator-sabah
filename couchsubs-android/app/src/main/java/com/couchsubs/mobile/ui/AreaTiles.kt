// SPDX-License-Identifier: AGPL-3.0-only
// Ayarlar › Altyazı alanı ve Ek alanlar (iPhone'daki AreaTile ve ExtraAreasTile ile aynı): hazır seçimler, son kareyle
// canlı önizleme (çerçeve sürüklenir, köşesinden büyütülür), Özel'de kaydırıcılar; en çok üç ek alan.
package com.couchsubs.mobile.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.core.AreaPreset
import com.couchsubs.mobile.core.CropRegion
import com.couchsubs.mobile.core.ExtraArea
import com.couchsubs.mobile.core.ExtraAreaPreset
import com.couchsubs.mobile.core.MINIMUM_REGION_SIZE
import com.couchsubs.mobile.core.moved
import com.couchsubs.mobile.core.resized
import com.couchsubs.mobile.core.withVertical
import com.couchsubs.mobile.service.FramePreview

/** Ayarlar › Altyazı alanı: Alt alan, Üst alan, Tam ekran, Özel; önizlemede çerçeve sürüklenir. */
@Composable
fun AreaTile() {
    val settings = Services.settings
    var region by remember { mutableStateOf(settings.region) }
    var preset by remember { mutableStateOf(settings.areaPreset) }
    fun custom(value: CropRegion) {
        region = value
        preset = AreaPreset.CUSTOM
        settings.setCustomRegion(value)
    }
    Tile(Modifier.fillMaxWidth()) {
        TileLabel(stringResource(R.string.area_title))
        val presets = listOf(AreaPreset.BOTTOM, AreaPreset.TOP, AreaPreset.FULL, AreaPreset.CUSTOM)
        Segmented(listOf(stringResource(R.string.area_bottom), stringResource(R.string.area_top), stringResource(R.string.area_full),
            stringResource(R.string.area_custom)), presets.indexOf(preset)) { index ->
            preset = presets[index]
            settings.selectAreaPreset(preset)
            region = settings.region
        }
        RegionPreview(region, onChange = ::custom)
        if (preset == AreaPreset.CUSTOM) {
            val position = region.top * 100
            val height = (region.bottom - region.top) * 100
            SliderRow(stringResource(R.string.area_position), position, 0f..maxOf(1.0, 100 - height).toFloat()) { custom(region.withVertical(it, height)) }
            SliderRow(stringResource(R.string.area_height), height, (MINIMUM_REGION_SIZE * 100).toFloat()..100f) { custom(region.withVertical(position, it)) }
        }
        Text(stringResource(R.string.area_drag_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
    }
}

@Composable
private fun SliderRow(title: String, value: Double, range: ClosedFloatingPointRange<Float>, onChange: (Double) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
        Row {
            TileLabel(title)
            Spacer(Modifier.weight(1f))
            TileLabel("%${value.toInt()}")
        }
        Slider(value.toFloat(), { onChange(it.toDouble()) }, valueRange = range,
            colors = SliderDefaults.colors(thumbColor = Tokens.Color.text, activeTrackColor = Tokens.Color.accent, inactiveTrackColor = Tokens.Color.borderStrong))
    }
}

/** Ayarlar › Ek alanlar: altyazının yanında sürekli okunan en çok üç küçük alan (görev, bildirim, telefon). */
@Composable
fun ExtraAreasTile() {
    val settings = Services.settings
    var areas by remember { mutableStateOf(settings.extraAreas) }
    var menu by remember { mutableStateOf(false) }
    fun save(value: List<ExtraArea>) {
        areas = value
        settings.extraAreas = value
    }
    fun update(id: String, change: (ExtraArea) -> ExtraArea) = save(areas.map { if (it.id == id) change(it) else it })
    Tile(Modifier.fillMaxWidth()) {
        TileLabel(stringResource(R.string.extra_title))
        Text(stringResource(R.string.extra_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        areas.forEach { area ->
            Column(Modifier.fillMaxWidth().background(Tokens.Color.surface2, RoundedCornerShape(Tokens.Radius.tile)).padding(Tokens.Space.gap),
                verticalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
                    Box(Modifier.weight(1f)) {
                        Field(area.name, { name -> update(area.id) { it.copy(name = name) } }, stringResource(R.string.extra_name))
                    }
                    Switch(area.enabled, { on -> update(area.id) { it.copy(enabled = on) } })
                    IconAction(Icons.Filled.Delete, stringResource(R.string.extra_remove)) { save(areas.filter { it.id != area.id }) }
                }
                val presets = ExtraAreaPreset.entries
                Segmented(listOf(stringResource(R.string.extra_quest), stringResource(R.string.extra_notification), stringResource(R.string.extra_phone)),
                    presets.indexOf(ExtraAreaPreset.matching(area.region))) { index -> update(area.id) { it.copy(region = presets[index].region) } }
                Box(Modifier.alpha(if (area.enabled) 1f else 0.5f)) {
                    RegionPreview(area.region) { region -> update(area.id) { it.copy(region = region) } }
                }
            }
        }
        if (areas.size < ExtraArea.MAX_COUNT) Box {
            SecondaryButton(stringResource(R.string.extra_add)) { menu = true }
            DropdownMenu(menu, { menu = false }) {
                ExtraAreaPreset.entries.forEach { preset ->
                    val name = presetName(preset)
                    DropdownMenuItem({ Text(presetTitle(preset)) }, {
                        menu = false
                        save(areas + ExtraArea(name = name, region = preset.region))
                    })
                }
            }
        }
    }
}

@Composable
private fun presetTitle(preset: ExtraAreaPreset) = stringResource(when (preset) {
    ExtraAreaPreset.QUEST -> R.string.extra_quest_title
    ExtraAreaPreset.NOTIFICATION -> R.string.extra_notification_title
    ExtraAreaPreset.PHONE -> R.string.extra_phone_title
})

@Composable
private fun presetName(preset: ExtraAreaPreset) = stringResource(when (preset) {
    ExtraAreaPreset.QUEST -> R.string.extra_quest
    ExtraAreaPreset.NOTIFICATION -> R.string.extra_notification
    ExtraAreaPreset.PHONE -> R.string.extra_phone
})

/**
 * Son PS5 karesi (çeviri sürerken) üstünde bölge çerçevesi: içinden sürüklenince kayar, sağ alt köşesinden sürüklenince
 * büyür. Kare yoksa düz zemin ve açıklama.
 */
@Composable
fun RegionPreview(region: CropRegion, onChange: (CropRegion) -> Unit) {
    DisposableEffect(Unit) {
        FramePreview.watch(true)
        onDispose { FramePreview.watch(false) }
    }
    val frame by FramePreview.frame.collectAsState()
    val current by rememberUpdatedState(region)
    val change by rememberUpdatedState(onChange)
    Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(Tokens.Radius.control)).background(Color.Black)) {
        frame?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds) }
            ?: Text(stringResource(R.string.area_preview_empty), style = Tokens.Type.caption, color = Tokens.Color.secondary,
                textAlign = TextAlign.Center, modifier = Modifier.align(Alignment.Center).padding(Tokens.Space.gap))
        Canvas(Modifier.fillMaxSize().pointerInput(Unit) {
            var resizing = false
            detectDragGestures(onDragStart = { start ->
                val r = current
                val corner = Offset((r.right * size.width).toFloat(), (r.bottom * size.height).toFloat())
                resizing = (start - corner).getDistance() < 32.dp.toPx()
            }) { change2, drag ->
                change2.consume()
                val r = current
                val next = if (resizing) {
                    val x = change2.position.x / size.width
                    val y = change2.position.y / size.height
                    r.resized(right = x.toDouble(), bottom = y.toDouble())
                } else r.moved(dx = drag.x.toDouble() / size.width, dy = drag.y.toDouble() / size.height)
                change(next)
            }
        }) {
            val topLeft = Offset((region.left * size.width).toFloat(), (region.top * size.height).toFloat())
            val box = Size(((region.right - region.left) * size.width).toFloat(), ((region.bottom - region.top) * size.height).toFloat())
            drawRect(Tokens.Color.accent.copy(alpha = 0.15f), topLeft, box)
            drawRect(Tokens.Color.accent, topLeft, box, style = Stroke(2.dp.toPx()))
            drawCircle(Tokens.Color.accent, 7.dp.toPx(), Offset(topLeft.x + box.width, topLeft.y + box.height))
        }
    }
}
