// SPDX-License-Identifier: AGPL-3.0-only
// Profil (cihazlar ve tercihler; hesap yok) ve ayarlar (tuval: Telefon-Profil, -Ayarlar).
package com.couchsubs.mobile.ui

import com.couchsubs.mobile.core.TargetLanguage
import com.couchsubs.mobile.settings.HomeStyle

import androidx.compose.foundation.layout.height

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.heightIn
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.BuildConfig
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.core.SubtitleBackgroundShape
import com.couchsubs.mobile.core.SubtitlePlacement
import com.couchsubs.mobile.core.SubtitleStyle
import com.couchsubs.mobile.core.SubtitleTextColor
import com.couchsubs.mobile.core.TvDisplayMode
import com.couchsubs.mobile.remoteplay.LoginPasscode
import com.couchsubs.mobile.service.LiveState
import com.couchsubs.mobile.service.TranslationService
import com.couchsubs.mobile.update.AppUpdate
import com.couchsubs.mobile.settings.AppSettings
import com.couchsubs.mobile.settings.EngineChoice
import com.couchsubs.mobile.settings.SubtitleTarget
import com.couchsubs.mobile.translation.AiModel
import com.couchsubs.mobile.translation.KeyCheck
import com.couchsubs.mobile.translation.OnlineKeyState
import com.couchsubs.mobile.translation.aiProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.couchsubs.mobile.tv.FoundTv
import com.couchsubs.mobile.tv.TvDiscovery


/**
 * Profil (tuval Telefon-Profil, hesapsız): cihazlar (PS5, TV'ler), ikinci PSN hesabı, bildirimler, ortak havuz,
 * kullanım verisi ve gizlilik. Uygulamada hesap ya da giriş yoktur.
 */
@Composable
fun ProfileScreen(onBack: () -> Unit, onSettings: () -> Unit, onPairing: () -> Unit, onTarget: () -> Unit, onPsn: () -> Unit, onInstallTv: () -> Unit = {},
                  onReport: () -> Unit = {}, onAssistant: () -> Unit = {}) {
    val context = LocalContext.current
    val settings = Services.settings
    var tvs by remember { mutableStateOf<List<FoundTv>?>(null) }
    var notifyDisconnect by remember { mutableStateOf(settings.notifyDisconnect) }
    var notifyPacks by remember { mutableStateOf(settings.notifyNewPacks) }
    var pool by remember { mutableStateOf(settings.sharePool) }
    var askGame by remember { mutableStateOf(settings.askGame) }
    var speakerNames by remember { mutableStateOf(settings.showSpeakerNames) }
    var fastReading by remember { mutableStateOf(settings.fastSubtitleDetection) }
    var usage by remember { mutableStateOf(settings.usageData) }
    LaunchedEffect(Unit) { tvs = withContext(Dispatchers.IO) { runCatching { TvDiscovery.search() }.getOrDefault(emptyList()) } }
    ScreenScaffold(top = { TopBar(stringResource(R.string.profile), onBack = onBack) { SettingsAction(onSettings) } }) {
        TwoColumns(
            { StatusTile(Icons.Filled.Tv, "PS5", settings.console?.name ?: stringResource(R.string.profile_not_paired), it,
                corner = { if (settings.console != null) StatusLabel(stringResource(R.string.main_paired)) }, onClick = onPairing) },
            { StatusTile(Icons.Filled.Person, stringResource(R.string.profile_psn),
                stringResource(if (settings.accountId != null) R.string.profile_psn_linked_short else R.string.profile_psn_missing), it,
                onClick = onPsn) },
        )
        Tile(Modifier.fillMaxWidth(), onClick = onTarget) {
            TileLabel(stringResource(R.string.profile_tvs))
            Text(if (settings.target == SubtitleTarget.TV) settings.tvName ?: stringResource(R.string.main_target_tv) else stringResource(R.string.main_target_phone),
                style = Tokens.Type.title, color = Tokens.Color.text)
            when (val found = tvs) {
                null -> Text(stringResource(R.string.target_searching), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                else -> Text(if (found.isEmpty()) stringResource(R.string.target_tvs_none) else found.joinToString { "${it.name} (${brandName(it.brand)})" },
                    style = Tokens.Type.caption, color = Tokens.Color.secondary)
            }
        }
        // Nino: Android TV'ye TV uygulamasını telefondan kurma (güncelleme de buradan).
        RowList(listOf({ RowItem(stringResource(R.string.tv_install_button), stringResource(R.string.tv_install_row_note), onClick = onInstallTv) }))
        RowList(listOf(
            { RowItem(stringResource(R.string.notify_disconnect)) { Switch(notifyDisconnect, { notifyDisconnect = it; settings.notifyDisconnect = it }) } },
            { RowItem(stringResource(R.string.notify_packs)) { Switch(notifyPacks, { notifyPacks = it; settings.notifyNewPacks = it }) } },
        ))
        RowList(listOf(
            { RowItem(stringResource(R.string.settings_pool), stringResource(R.string.settings_pool_short)) {
                Switch(pool, { pool = it; settings.sharePool = it })
            } },
            { RowItem(stringResource(R.string.settings_ask_game), stringResource(R.string.settings_ask_game_short)) {
                Switch(askGame, { askGame = it; settings.askGame = it })
            } },
            { RowItem(stringResource(R.string.settings_speaker_names), stringResource(R.string.settings_speaker_names_short)) {
                Switch(speakerNames, { speakerNames = it; settings.showSpeakerNames = it })
            } },
            { RowItem(stringResource(R.string.settings_fast_reading), stringResource(R.string.settings_fast_reading_short)) {
                Switch(fastReading, { fastReading = it; settings.fastSubtitleDetection = it })
            } },
            { RowItem(stringResource(R.string.profile_usage), stringResource(R.string.profile_usage_note)) {
                Switch(usage, { usage = it; Services.setUsageData(it) })
            } },
            { RowItem(stringResource(R.string.profile_privacy), onClick = { open(context, context.getString(R.string.url_privacy)) }) },
            { RowItem(stringResource(R.string.profile_help), onClick = { open(context, context.getString(R.string.url_help)) }) },
            { RowItem(stringResource(R.string.assistant_title), onClick = onAssistant) },
            { RowItem(stringResource(R.string.report_title), onClick = onReport) },
        ))
        Text(stringResource(R.string.profile_no_account), style = Tokens.Type.caption, color = Tokens.Color.secondary)
    }
}

/** Ayarlar (tuval Telefon-Ayarlar): motor ve anahtar, altyazı görünümü, paketler, hedef, PS5, hakkında. */
@Composable
fun SettingsScreen(onBack: () -> Unit, onPacks: () -> Unit, onTarget: () -> Unit, onPairing: () -> Unit, onHealth: () -> Unit = {},
                   onSource: () -> Unit = {}, onTvInstall: () -> Unit = {}, onReport: () -> Unit = {},
                   onAssistant: () -> Unit = {}) {
    val context = LocalContext.current
    val settings = Services.settings
    val live by LiveState.status.collectAsState()
    var engine by remember { mutableStateOf(settings.engine) }
    // Anahtar kaydedilmeden önce denenir (iPhone gibi): yalnız kabul edilen anahtar gizli depoya yazılır.
    var key by remember(engine) { mutableStateOf("") }
    var saved by remember(engine) { mutableStateOf(!settings.apiKey(engine).isNullOrBlank()) }
    var checking by remember { mutableStateOf(false) }
    var keyRejected by remember(engine) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    var scale by remember { mutableStateOf(settings.subtitleScale.toFloat()) }
    var autoSize by remember { mutableStateOf(settings.tvAutoSize) }
    var color by remember { mutableStateOf(settings.textColor) }
    var font by remember { mutableStateOf(settings.subtitleFont) }
    var background by remember { mutableStateOf(settings.tvBackground.toFloat()) }
    var shape by remember { mutableStateOf(settings.tvBackgroundShape) }
    var screenOn by remember { mutableStateOf(settings.keepScreenOn) }
    var homeStyle by remember { mutableStateOf(settings.homeStyle) }
    var targetLanguage by remember { mutableStateOf(settings.targetLanguage) }
    var stackPrevious by remember { mutableStateOf(settings.stackPrevious) }
    var watermark by remember { mutableStateOf(settings.tvWatermark) }
    var displayMode by remember { mutableStateOf(settings.tvDisplayMode) }
    var placement by remember { mutableStateOf(settings.tvPlacement) }
    var bottomPercent by remember { mutableStateOf(settings.tvBottomPercent.toFloat()) }
    var passcode by remember { mutableStateOf(settings.loginPasscode ?: "") }
    // Tuvaldeki dört seçenek: Ücretsiz, DeepL, Gemini, Diğer (OpenAI / Claude).
    val segment = when (engine) {
        EngineChoice.FREE -> 0
        EngineChoice.DEEPL -> 1
        EngineChoice.GEMINI -> 2
        else -> 3
    }
    fun choose(choice: EngineChoice) {
        engine = choice
        settings.engine = choice
    }
    ScreenScaffold(top = { TopBar(stringResource(R.string.settings), onBack = onBack) }) {
        // Nino: görüntü kaynağı en üstte (Mac'teki "Bağlantı" gibi): PS5 (Remote Play) ya da Yakalama Kartı.
        RowList(listOf({ RowItem(stringResource(R.string.settings_video_source), videoSourceName(), onClick = onSource) }))
        // Nino: Arayüz (Mac ile aynı iki ana ekran).
        Tile(Modifier.fillMaxWidth()) {
            TileLabel(stringResource(R.string.nino_interface))
            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                listOf(HomeStyle.LIVING_ROOM to stringResource(R.string.nino_home_living_room), HomeStyle.TOGGLE to stringResource(R.string.nino_home_toggle)).forEach { (style, name) ->
                    val selected = homeStyle == style
                    Column(Modifier.weight(1f).border(if (selected) 2.dp else 1.dp, if (selected) Tokens.Color.accent else Tokens.Color.borderStrong,
                        RoundedCornerShape(Tokens.Radius.control)).clickable { homeStyle = style; settings.homeStyle = style }.padding(10.dp),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Box(Modifier.fillMaxWidth().height(64.dp), contentAlignment = Alignment.Center) {
                            if (style == HomeStyle.LIVING_ROOM) LivingRoomThumbnail(Modifier.fillMaxWidth()) else GlassToggleThumbnail(Modifier.fillMaxWidth())
                        }
                        Text(name, style = Tokens.Type.body, color = if (selected) Tokens.Color.accentText else Tokens.Color.text)
                    }
                }
            }
            Text(stringResource(if (homeStyle == HomeStyle.LIVING_ROOM) R.string.nino_home_living_room_hint else R.string.nino_home_toggle_hint),
                style = Tokens.Type.caption, color = Tokens.Color.secondary)
        }
        // Nino: çeviri dili (bayraklı menü, Türkçe en üstte); bir sonraki çeviri oturumunda kullanılır.
        Tile(Modifier.fillMaxWidth()) {
            TileLabel(stringResource(R.string.nino_translation_language))
            TargetLanguageMenu(targetLanguage) { choice ->
                targetLanguage = choice
                settings.targetLanguage = choice
            }
            Text(stringResource(R.string.nino_translation_language_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        }
        RowList(listOf({ RowItem(stringResource(R.string.nino_system_health), stringResource(R.string.nino_system_health_detail), onClick = onHealth) }))
        // Nino: GTA 6'da (Türkçe) çeviri Nino'nun havuzundan gelir, seçilecek bir şey yoktur; motor kartının hemen
        // üstünde açıkça yazar (Mac'teki "GTA 6" kartı ve alt şeritteki "Nino · GTA 6 Aktif"). Çevirinin kendisi değişmez.
        val ninoActive = live.ninoPoolActive(targetLanguage)
        if (ninoActive) Tile(Modifier.fillMaxWidth()) {
            TileLabel("GTA 6")
            Row(Modifier.background(Tokens.Color.surface2, RoundedCornerShape(50)).padding(start = 6.dp, end = 12.dp, top = 4.dp, bottom = 4.dp)) {
                StatusLabel(stringResource(R.string.nino_gta6_active))
            }
            Text(stringResource(R.string.nino_gta6_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        }
        Tile(Modifier.fillMaxWidth()) {
            // GTA 6 kartı görünürken bu kart yalnız diğer oyunlar içindir.
            TileLabel(stringResource(if (ninoActive) R.string.settings_engine_other_games else R.string.settings_engine))
            Segmented(listOf(stringResource(R.string.engine_free_short), "DeepL", "Gemini", stringResource(R.string.engine_other)), segment) { index ->
                choose(when (index) {
                    0 -> EngineChoice.FREE
                    1 -> EngineChoice.DEEPL
                    2 -> EngineChoice.GEMINI
                    else -> if (engine == EngineChoice.CLAUDE) EngineChoice.CLAUDE else EngineChoice.OPENAI
                })
            }
            if (segment == 3) Segmented(listOf("OpenAI", "Claude"), if (engine == EngineChoice.CLAUDE) 1 else 0) {
                choose(if (it == 1) EngineChoice.CLAUDE else EngineChoice.OPENAI)
            }
            if (engine != EngineChoice.FREE) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TileLabel(stringResource(R.string.settings_key_for, engineName(context)))
                    Spacer(Modifier.weight(1f))
                    if (saved) StatusLabel(stringResource(R.string.settings_key_saved))
                }
                if (saved) {
                    GhostButton(stringResource(R.string.settings_key_remove)) {
                        settings.setApiKey(engine, null)
                        saved = false
                    }
                } else {
                    Field(key, { key = it; keyRejected = false }, stringResource(R.string.settings_key), secret = true)
                    SecondaryButton(stringResource(if (checking) R.string.settings_key_checking else R.string.settings_key_save),
                        enabled = !checking && key.isNotBlank()) {
                        val choice = engine
                        val typed = key.trim()
                        checking = true
                        keyRejected = false
                        scope.launch {
                            val state = withContext(Dispatchers.IO) {
                                val provider = choice.aiProvider
                                if (provider == null) KeyCheck.deepL(typed)
                                else {
                                    val models = AiModel.load(context)[provider.id].orEmpty()
                                    val model = models.firstOrNull { it.id == settings.aiModel } ?: models.firstOrNull()
                                    if (model == null) OnlineKeyState.UNREACHABLE else KeyCheck.ai(provider, typed, model)
                                }
                            }
                            checking = false
                            if (KeyCheck.accepted(state)) {
                                settings.setApiKey(choice, typed)
                                if (engine == choice) {
                                    saved = true
                                    key = ""
                                }
                            } else if (engine == choice) keyRejected = true
                        }
                    }
                    if (keyRejected) NoteTile(stringResource(R.string.settings_key_rejected))
                }
            }
            Text(stringResource(R.string.settings_engine_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        }
        Tile(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TileLabel(stringResource(R.string.settings_text_size))
                Spacer(Modifier.weight(1f))
                Text("%${Math.round(scale)}", style = Tokens.Type.headline, color = Tokens.Color.text)
            }
            // %10 adımlarla %40–160 (iPhone ile aynı): 13 değer, aradaki 11 durak.
            // Nino: TV yazı boyunu oyunun İngilizce satırına uydurur (Mac ile aynı, varsayılan açık). Açıkken TV ölçeği yok
            // sayar; LG'de "boyu değiştiriyorum, TV'de değişmiyor" şikâyeti buydu. Ölçeği değiştirmek otomatik boyu kapatır.
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.settings_auto_size), style = Tokens.Type.body, color = Tokens.Color.text, modifier = Modifier.weight(1f))
                Switch(autoSize, { autoSize = it; settings.tvAutoSize = it })
            }
            if (autoSize) Text(stringResource(R.string.settings_auto_size_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            Slider(scale, {
                scale = it
                if (autoSize) { autoSize = false; settings.tvAutoSize = false }
                settings.subtitleScale = Math.round(it)
            },
                valueRange = AppSettings.MIN_SUBTITLE_SCALE.toFloat()..AppSettings.MAX_SUBTITLE_SCALE.toFloat(),
                steps = (AppSettings.MAX_SUBTITLE_SCALE - AppSettings.MIN_SUBTITLE_SCALE) / 10 - 1,
                colors = SliderDefaults.colors(thumbColor = Tokens.Color.text, activeTrackColor = Tokens.Color.accent,
                    inactiveTrackColor = Tokens.Color.borderStrong, activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent))
            // Önizleme altyazı içeriğidir: boyu ölçeğe göre değişir.
            Text(stringResource(R.string.settings_preview), style = Tokens.Type.subtitleCurrent.copy(fontSize = Tokens.Type.subtitleCurrent.fontSize * (scale / 100f),
                fontFamily = rememberSubtitleFontFamily(font)),
                color = if (color == SubtitleTextColor.YELLOW) Tokens.Color.accentText else Tokens.Color.text)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                TileLabel(stringResource(R.string.settings_color))
                Spacer(Modifier.weight(1f))
                SubtitleTextColor.entries.forEach { option ->
                    val swatch = if (option == SubtitleTextColor.YELLOW) Tokens.Color.accent else Tokens.Color.text
                    Box(Modifier.size(32.dp).background(swatch, CircleShape)
                        .border(2.dp, if (color == option) Tokens.Color.accent else Tokens.Color.borderStrong, CircleShape)
                        .clickable { color = option; settings.textColor = option })
                }
            }
            // Yazı tipi (TV, OBS ve telefon ekranı; Mac, Windows ve iPhone ile aynı dört seçenek): her ad kendi yazı tipiyle.
            TileLabel(stringResource(R.string.settings_font))
            SubtitleFonts.choices.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                    pair.forEach { option ->
                        val selected = font == option
                        Box(Modifier.weight(1f).heightIn(min = 48.dp)
                            .border(if (selected) 2.dp else 1.dp, if (selected) Tokens.Color.accent else Tokens.Color.borderStrong, RoundedCornerShape(Tokens.Radius.control))
                            .clickable { font = option; settings.subtitleFont = option }.padding(horizontal = 8.dp, vertical = 10.dp),
                            contentAlignment = Alignment.Center) {
                            Text(stringResource(SubtitleFonts.nameRes(option)), maxLines = 1, overflow = TextOverflow.Ellipsis,
                                style = Tokens.Type.headline.copy(fontFamily = rememberSubtitleFontFamily(option), fontWeight = FontWeight.SemiBold),
                                color = if (selected) Tokens.Color.accentText else Tokens.Color.text)
                        }
                    }
                }
            }
            // TV'deki kutu: %100 tamamen opak olur ve oyundaki İngilizce yazıyı kapatır; bant ekranın iki kenarına uzanır.
            // Nino: örtme kipinde TV'ye %60 altı gitmez (SubtitleStyle.effectiveBackground). Kaydırıcı o kipte %60'tan başlar
            // ve TV'ye gideni gösterir; eskiden %0-55 seçilebiliyor, yazan yüzde yerine kutu simsiyah (%100) oluyordu.
            // Yuvarlama: adım değeri 54,99… gelirse toInt bir alt yüzdeye (eşiğin altına) düşürürdü.
            val backgroundFloor = if (placement == SubtitlePlacement.COVER) SubtitleStyle.COVER_MIN_BACKGROUND else 0
            val shownBackground = SubtitleStyle.effectiveBackground(placement, Math.round(background))
            Row(verticalAlignment = Alignment.CenterVertically) {
                TileLabel(stringResource(R.string.settings_background))
                Spacer(Modifier.weight(1f))
                Text("%$shownBackground", style = Tokens.Type.headline, color = Tokens.Color.text)
            }
            Slider(shownBackground.toFloat(), { background = it; settings.tvBackground = Math.round(it) },
                valueRange = backgroundFloor.toFloat()..100f, steps = (100 - backgroundFloor) / 5 - 1,
                colors = SliderDefaults.colors(thumbColor = Tokens.Color.text, activeTrackColor = Tokens.Color.accent,
                    inactiveTrackColor = Tokens.Color.borderStrong, activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent))
            TileLabel(stringResource(R.string.settings_background_area))
            Segmented(listOf(stringResource(R.string.settings_background_fit), stringResource(R.string.settings_background_band)),
                if (shape == SubtitleBackgroundShape.BAND) 1 else 0) {
                shape = if (it == 1) SubtitleBackgroundShape.BAND else SubtitleBackgroundShape.FIT
                settings.tvBackgroundShape = shape
            }
            Text(stringResource(R.string.settings_background_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            // TV'de çevirinin yeri (Mac ve Windows'taki Yeri seçimi, iPhone ile aynı): üstünde/altında seçilince oyundaki
            // İngilizce altyazı da görünür; sabit yerde yükseklik kaydırıcıyla ayarlanır, bırakınca TV'de örnek altyazı çıkar.
            if (settings.target == SubtitleTarget.TV) {
                val placements = listOf(SubtitlePlacement.COVER, SubtitlePlacement.ABOVE, SubtitlePlacement.BELOW, SubtitlePlacement.FIXED)
                TileLabel(stringResource(R.string.settings_placement))
                Segmented(listOf(stringResource(R.string.settings_placement_cover), stringResource(R.string.settings_placement_above),
                    stringResource(R.string.settings_placement_below), stringResource(R.string.settings_placement_fixed)),
                    placements.indexOf(placement).coerceAtLeast(0)) {
                    placement = placements[it]
                    settings.tvPlacement = placement
                }
                if (placement == SubtitlePlacement.FIXED) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TileLabel(stringResource(R.string.settings_position_height))
                        Spacer(Modifier.weight(1f))
                        Text("%${bottomPercent.toInt()}", style = Tokens.Type.headline, color = Tokens.Color.text)
                    }
                    Slider(bottomPercent, { bottomPercent = it; settings.tvBottomPercent = it.toInt() }, valueRange = 0f..85f,
                        onValueChangeFinished = { TranslationService.sendTestSubtitle(context.getString(R.string.test_subtitle_text)) },
                        colors = SliderDefaults.colors(thumbColor = Tokens.Color.text, activeTrackColor = Tokens.Color.accent,
                            inactiveTrackColor = Tokens.Color.borderStrong, activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent))
                    Text(stringResource(R.string.settings_placement_fixed_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                } else {
                    Text(stringResource(R.string.settings_placement_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                }
            }
            RowItem(stringResource(R.string.settings_stack_previous)) { Switch(stackPrevious, { stackPrevious = it; settings.stackPrevious = it }) }
            Text(stringResource(R.string.settings_stack_previous_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            // Yalnız Android TV uygulaması kullanır: bazı TV'lerde (ör. TCL) uygulama içindeki PS5 görüntüsü siyah kalıyor.
            // Katman'da TV, PS5'i kendi HDMI girişinde gösterir (Mac ve Windows'taki Görüntü modu seçimi, iPhone ile aynı).
            if (settings.target == SubtitleTarget.TV) {
                TileLabel(stringResource(R.string.settings_display_mode))
                Segmented(listOf(stringResource(R.string.settings_display_mode_in_app), stringResource(R.string.settings_display_mode_overlay)),
                    if (displayMode == TvDisplayMode.OVERLAY) 1 else 0) {
                    displayMode = if (it == 1) TvDisplayMode.OVERLAY else TvDisplayMode.IN_APP
                    settings.tvDisplayMode = displayMode
                }
                Text(stringResource(R.string.settings_display_mode_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            }
            // Nino: TV'nin sol altındaki küçük Nino işareti (Mac'teki "TV'de Nino filigranını göster" ile aynı). Kapalıyken yalnız o gizlenir.
            RowItem(stringResource(R.string.settings_tv_watermark)) { Switch(watermark, { watermark = it; settings.tvWatermark = it }) }
            Text(stringResource(R.string.settings_tv_watermark_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            RowItem(stringResource(R.string.settings_screen_on)) { Switch(screenOn, { screenOn = it; settings.keepScreenOn = it }) }
        }
        // Altyazı alanı ve ek alanlar (iPhone ile aynı sırada: görünümden sonra).
        AreaTile()
        ExtraAreasTile()
        // İkinci hesabın PS5 giriş şifresi: yalnız 4 hane gizli depoya (Keystore) yazılır; silinince kaldırılır.
        Tile(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TileLabel(stringResource(R.string.settings_passcode))
                Spacer(Modifier.weight(1f))
                if (LoginPasscode.normalized(passcode) != null) StatusLabel(stringResource(R.string.settings_key_saved))
            }
            Field(passcode, { value ->
                passcode = value.filter { it in '0'..'9' }.take(LoginPasscode.LENGTH)
                settings.loginPasscode = passcode
            }, stringResource(R.string.settings_passcode_field), secret = true,
                keyboard = KeyboardOptions(keyboardType = KeyboardType.NumberPassword))
            Text(stringResource(R.string.settings_passcode_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        }
        var xboxAudio by remember { mutableStateOf(settings.xboxAudioOnDevice) }
        val showUpdateRow = remember { !AppUpdate.managedByPlay(context) }
        RowList(listOfNotNull<@Composable () -> Unit>(
            { RowItem(stringResource(R.string.settings_packs), onClick = onPacks) { Pill(stringResource(if (settings.packsEnabled) R.string.main_packs_on else R.string.main_packs_off)) } },
            { RowItem(stringResource(R.string.settings_target), if (settings.target == SubtitleTarget.TV) settings.tvName ?: stringResource(R.string.main_target_tv)
                else stringResource(R.string.main_target_phone), onClick = onTarget) },
            // Nino: konsol türü (PS5 / Xbox / Capture Card) en üstteki Görüntü Kaynağı satırından seçilir.
            if (settings.xbox) ({ RowItem("Xbox", settings.xboxConsole?.name ?: stringResource(R.string.profile_not_paired), onClick = onPairing) })
            else ({ RowItem(stringResource(R.string.settings_ps5), settings.console?.name ?: stringResource(R.string.profile_not_paired), onClick = onPairing) }),
            // Yalnız Xbox: uzaktan oynatmada Xbox sesi istemciye verip TV'yi susturabilir (PS5'te ses TV'de kalır).
            if (settings.xbox) ({ RowItem(stringResource(R.string.settings_xbox_audio), stringResource(R.string.settings_xbox_audio_short)) {
                Switch(xboxAudio, { xboxAudio = it; settings.xboxAudioOnDevice = it })
            } }) else null,
            // Nino: Nino'ya Sor ve Sorun Bildir, Hakkında'nın hemen üstünde.
            { RowItem(stringResource(R.string.assistant_title), stringResource(R.string.assistant_row_note), onClick = onAssistant) },
            { RowItem(stringResource(R.string.report_title), stringResource(R.string.report_row_note), onClick = onReport) },
            // Nino: Güncelleme. Yeni sürüm biliniyorsa (ana ekrandaki kart ✕ ile kapatılmış olsa da) indirme düğmesi;
            // yoksa "Güncel" ve süreyi beklemeden bakan "Şimdi denetle". Play kopyasında gösterilmez (Play günceller).
            if (showUpdateRow) ({ UpdateRow() }) else null,
            { RowItem(stringResource(R.string.settings_about), BuildConfig.VERSION_NAME, onClick = { open(context, context.getString(R.string.url_source)) }) },
        ))
        XboxSignOutRow()
        // TV uygulamasını bu telefondan kurmak ve güncellemek (bilgisayardaki gibi; Samsung, LG, Android TV).
        Tile(Modifier.fillMaxWidth()) {
            TileLabel(stringResource(R.string.settings_tv_app))
            RowItem(stringResource(R.string.tvinstall_entry), tvAppSummary(), onClick = onTvInstall)
        }
        // Deneme altyazısı: TV'de (ya da telefon ekranında) yazının nasıl göründüğü; iPhone ile aynı.
        var testNote by remember { mutableStateOf<String?>(null) }
        SecondaryButton(stringResource(R.string.settings_test_subtitle)) {
            testNote = if (TranslationService.sendTestSubtitle(context.getString(R.string.test_subtitle_text))) null
                else context.getString(R.string.settings_test_needs_start)
        }
        testNote?.let { NoteTile(it, Tokens.Color.secondary) }
        Text(stringResource(R.string.settings_copyright), style = Tokens.Type.caption, color = Tokens.Color.secondary,
            modifier = Modifier.padding(top = Tokens.Space.inline))
    }
}


/**
 * Ayarlar'daki "Güncelleme" satırı (GitHub'dan kurulan kopya). Yeni sürüm biliniyorsa "Yeni sürüm var: 3.5.0" ve APK'yı
 * indiren "İndir"; yoksa "Güncel" ve "Şimdi denetle" (3 saatlik aralığı beklemeden GitHub'a bakar). GitHub'a
 * ulaşılamadıysa "Güncel" denmez, bağlantı uyarısı yazılır.
 */
@Composable
private fun UpdateRow() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val newer by AppUpdate.newer.collectAsState()
    var checking by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    val latest = newer
    if (latest != null) {
        RowItem(stringResource(R.string.update_row_title), stringResource(R.string.update_row_newer, latest)) {
            GhostButton(stringResource(R.string.update_row_download)) { open(context, AppUpdate.DOWNLOAD_URL) }
        }
    } else {
        RowItem(stringResource(R.string.update_row_title), stringResource(when {
            checking -> R.string.update_row_checking
            failed -> R.string.xbox_error_offline
            else -> R.string.update_row_current
        })) {
            if (!checking) GhostButton(stringResource(R.string.update_row_check)) {
                checking = true
                failed = false
                scope.launch {
                    failed = !AppUpdate.check(context.applicationContext, force = true)
                    checking = false
                }
            }
        }
    }
}

/** Xbox seçiliyken ve giriş yapılmışken Microsoft hesabından çıkış (jeton Keystore'dan silinir). */
@Composable
private fun XboxSignOutRow() {
    val settings = Services.settings
    var signedIn by remember { mutableStateOf(Services.xboxAuth.signedIn) }
    if (!settings.xbox || !signedIn) return
    Tile(Modifier.fillMaxWidth()) {
        RowItem(stringResource(R.string.xbox_sign_out), onClick = {
            Services.xboxAuth.signOut()
            signedIn = false
        })
    }
}
