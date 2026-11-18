// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "Nino'ya Sor" kurulum yardımcısı. Yüzen robot düğmesi (ana ekran ve kurulum ekranları), sohbet ekranı ve
// uygulama açık kaldıkça süren sohbet (AssistantSession). Sunucu: NinoAssistant (POST /v1/assistant).
package com.couchsubs.mobile.ui

import android.content.Context
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AddPhotoAlternate
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.BuildConfig
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.account.NinoAssistant
import com.couchsubs.mobile.account.ProblemReport
import com.couchsubs.mobile.account.ReportAttachments
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Sohbete eklenmiş fotoğraf: küçültülmüş JPEG ve küçük resmi. */
class ChatPhoto(val jpeg: ByteArray, val thumbnail: ImageBitmap)

/** Nino'nun yerel (sunucuya gitmeyen) uyarı balonları. */
enum class ChatNotice { DISABLED, RATE_LIMITED, BUSY, NETWORK, TOO_LARGE, INVALID }

/** Kullanıcı mesajının durumu: gönderildi, gönderiliyor, yeniden denenebilir hata, gönderilmedi (yeniden denenmez). */
enum class SendState { SENT, SENDING, FAILED, UNSENT }

@Stable
class ChatMessage(
    val user: Boolean,
    val text: String,
    val photos: List<ChatPhoto> = emptyList(),
    val notice: ChatNotice? = null,
    val report: String? = null,
) {
    var state by mutableStateOf(SendState.SENT)
}

/**
 * Uygulama açık kaldıkça süren sohbet: ekran kapanınca kaybolmaz, uygulama yeniden açılınca sıfırlanır. İstek
 * uygulama düzeyindeki kapsamda sürer; ekrandan çıkılsa da yanıt gelir.
 */
object AssistantSession {
    val messages = mutableStateListOf<ChatMessage>()
    var waiting by mutableStateOf(false)
        private set
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun clear() {
        if (waiting) return
        messages.clear()
    }

    fun send(context: Context, text: String, photos: List<ChatPhoto>) {
        if (waiting || (text.isBlank() && photos.isEmpty())) return
        val message = ChatMessage(true, text.trim().take(NinoAssistant.MAX_TEXT), photos.take(NinoAssistant.MAX_IMAGES))
        messages.add(message)
        request(context.applicationContext, message)
    }

    fun retry(context: Context, message: ChatMessage) {
        if (waiting || message.state != SendState.FAILED) return
        // Hatanın yerel balonu kaldırılır; mesaj sohbetin sonuna taşınır.
        val index = messages.indexOf(message)
        if (index >= 0 && index + 1 < messages.size && messages[index + 1].notice != null) messages.removeAt(index + 1)
        messages.remove(message)
        messages.add(message)
        request(context.applicationContext, message)
    }

    private fun request(context: Context, message: ChatMessage) {
        message.state = SendState.SENDING
        waiting = true
        // Sunucuya yalnız gönderilmiş kullanıcı mesajları, Nino'nun gerçek yanıtları ve şimdi gönderilen mesaj gider.
        val turns = messages.filter { if (it.user) it.state == SendState.SENT || it === message else it.notice == null }
            .map { NinoAssistant.Turn(it.user, it.text, it.photos.map(ChatPhoto::jpeg)) }
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                val filesDir = context.filesDir
                val prefs = context.getSharedPreferences("report", Context.MODE_PRIVATE)
                val install = ProblemReport.installId(filesDir, { prefs.getString("install", null) },
                    { prefs.edit().putString("install", it).apply() })
                val body = NinoAssistant.fittedBody(install, BuildConfig.VERSION_NAME, Services.settings.targetLanguage, turns)
                val endpoint = ProblemReport.endpoint(filesDir)
                when {
                    body == null -> NinoAssistant.Result.TooLarge
                    endpoint == null -> NinoAssistant.Result.Failed
                    else -> NinoAssistant.send(endpoint, body)
                }
            }
            waiting = false
            when (result) {
                is NinoAssistant.Result.Reply -> {
                    message.state = SendState.SENT
                    messages.add(ChatMessage(false, result.text, report = result.report))
                }
                NinoAssistant.Result.Disabled -> fail(message, SendState.UNSENT, ChatNotice.DISABLED)
                NinoAssistant.Result.RateLimited -> fail(message, SendState.UNSENT, ChatNotice.RATE_LIMITED)
                NinoAssistant.Result.Busy -> fail(message, SendState.FAILED, ChatNotice.BUSY)
                NinoAssistant.Result.TooLarge -> fail(message, SendState.UNSENT, ChatNotice.TOO_LARGE)
                NinoAssistant.Result.Invalid -> fail(message, SendState.UNSENT, ChatNotice.INVALID)
                NinoAssistant.Result.Failed -> fail(message, SendState.FAILED, ChatNotice.NETWORK)
            }
        }
    }

    private fun fail(message: ChatMessage, state: SendState, notice: ChatNotice) {
        message.state = state
        messages.add(ChatMessage(false, "", notice = notice))
    }
}

/**
 * Nino robotu. [animate]: yavaşça yukarı aşağı süzülür; göz kırpma her ~4,5 sn'de 150 ms. Azaltılmış harekette
 * durur.
 */
@Composable
fun NinoBot(size: Dp, modifier: Modifier = Modifier, animate: Boolean = true, bob: Boolean = false) {
    val moving = animate && !reducedMotion()
    var blink by remember { mutableStateOf(false) }
    if (moving) LaunchedEffect(Unit) {
        while (true) {
            delay(4500)
            blink = true
            delay(150)
            blink = false
        }
    }
    val lift = if (moving && bob) {
        val transition = rememberInfiniteTransition(label = "bob")
        transition.animateFloat(0f, 1f, infiniteRepeatable(tween(1600), RepeatMode.Reverse), label = "lift").value
    } else 0f
    Image(painterResource(if (blink) R.drawable.nino_bot_blink else R.drawable.nino_bot), null,
        modifier.size(size).offset(y = (-3 * lift).dp))
}

/** Yüzen "Nino'ya Sor" düğmesi: beyaz cam daire üstünde robot, hafif gölge. */
@Composable
fun AskNinoButton(modifier: Modifier = Modifier, onClick: () -> Unit) {
    val label = stringResource(R.string.assistant_title)
    Box(
        modifier.size(60.dp)
            .shadow(14.dp, CircleShape, ambientColor = Tokens.Color.pro.copy(alpha = 0.25f), spotColor = Tokens.Color.pro.copy(alpha = 0.3f))
            .background(Tokens.Color.raised.copy(alpha = 0.94f), CircleShape)
            .border(1.dp, Tokens.Color.borderStrong, CircleShape)
            .clickable(role = Role.Button, onClickLabel = label, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { NinoBot(46.dp, bob = true) }
}

/** Metin ve tıklanabilir http(s) bağlantıları. */
private fun linkified(text: String): AnnotatedString = buildAnnotatedString {
    append(text)
    val style = TextLinkStyles(SpanStyle(color = Tokens.Color.accentText, textDecoration = TextDecoration.Underline))
    NinoAssistant.links(text).forEach { range ->
        addLink(LinkAnnotation.Url(text.substring(range.first, range.last + 1), style), range.first, range.last + 1)
    }
}

/**
 * Nino'nun yanıtı: paragraflar, mavi yuvarlak rozetli numaralı adımlar ve noktalı maddeler. Kayan satırlar rozetin
 * altına değil yazının hizasına gelir (asılı girinti); sağdan sola dillerde rozet kendiliğinden sağa geçer. Bloklara
 * ayırma NinoAssistant.blocks'ta (Mac, iPhone ve Windows'la aynı kurallar).
 */
@Composable
private fun NinoReply(text: String) {
    val blocks = remember(text) { NinoAssistant.blocks(text) }
    val style = Tokens.Type.body.copy(color = Tokens.Color.text)
    val line = with(LocalDensity.current) { style.lineHeight.toDp() }
    val cell = maxOf(line, 21.dp)
    val textTop = (cell - line) / 2
    Column {
        blocks.forEachIndexed { i, block ->
            val gap = if (i == 0) 0.dp else if (block.isListItem && blocks[i - 1].isListItem) 8.dp else 10.dp
            when (block.kind) {
                NinoAssistant.Block.Kind.PARAGRAPH -> Text(linkified(block.text), style = style, modifier = Modifier.padding(top = gap))
                else -> Row(Modifier.padding(top = gap), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    // Rozet ilk satırın ortasında dursun: hücre en az bir satır boyu (büyük yazı boyutunda da), yazı ise
                    // rozetten kısa satırlarda hücrenin ortasına gelecek kadar aşağıda.
                    Box(Modifier.heightIn(min = cell).widthIn(min = 21.dp), contentAlignment = Alignment.Center) {
                        if (block.kind == NinoAssistant.Block.Kind.STEP) {
                            val number = block.number.orEmpty()
                            Box(Modifier.heightIn(min = 21.dp).widthIn(min = 21.dp).background(Tokens.Color.accent, CircleShape)
                                .padding(horizontal = if (number.length > 1) 4.dp else 0.dp),
                                contentAlignment = Alignment.Center) {
                                Text(number, color = Tokens.Color.onAccent, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                                    lineHeight = 12.sp, modifier = Modifier.semantics { contentDescription = "$number." })
                            }
                        } else {
                            Box(Modifier.size(6.dp).background(Tokens.Color.accent, CircleShape))
                        }
                    }
                    Text(linkified(block.text), style = style, modifier = Modifier.weight(1f, fill = false).padding(top = textTop))
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AskNinoScreen(onBack: () -> Unit, onReport: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val messages = AssistantSession.messages
    val waiting = AssistantSession.waiting
    var text by remember { mutableStateOf("") }
    val photos = remember { mutableStateListOf<ChatPhoto>() }
    var loadingPhotos by remember { mutableStateOf(false) }
    var photoError by remember { mutableStateOf(false) }
    val list = rememberLazyListState()

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(NinoAssistant.MAX_IMAGES)) { uris ->
        val chosen = uris.take((NinoAssistant.MAX_IMAGES - photos.size).coerceAtLeast(0))
        if (chosen.isEmpty()) return@rememberLauncherForActivityResult
        loadingPhotos = true
        scope.launch {
            val loaded = withContext(Dispatchers.Default) {
                chosen.map { uri ->
                    ReportAttachments.loadImage(context, uri, NinoAssistant.MAX_IMAGE_BYTES)?.let { jpeg ->
                        val options = BitmapFactory.Options().apply { inSampleSize = 4 }
                        BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, options)?.let { ChatPhoto(jpeg, it.asImageBitmap()) }
                    }
                }
            }
            loaded.filterNotNull().forEach { if (photos.size < NinoAssistant.MAX_IMAGES) photos.add(it) }
            photoError = loaded.any { it == null }
            loadingPhotos = false
        }
    }

    fun send(value: String, attached: List<ChatPhoto>) {
        if (waiting || loadingPhotos) return
        AssistantSession.send(context, value, attached)
        text = ""
        photos.clear()
        photoError = false
    }

    // Satırlar: 0 karşılama (+ öneriler), sonra mesajlar, en sonda "yazıyor" balonu.
    val count = 1 + messages.size + if (waiting) 1 else 0
    LaunchedEffect(count) { list.animateScrollToItem(count - 1) }

    ScreenBackground {
        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            // Başlık: geri, göz kırpan robot, "Nino / Kurulum yardımcısı", yeni sohbet.
            Row(Modifier.fillMaxWidth().padding(horizontal = Tokens.Space.screen, vertical = Tokens.Space.inline),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                IconAction(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back), onBack)
                NinoBot(44.dp)
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.assistant_name), style = Tokens.Type.headline, color = Tokens.Color.text)
                    Text(stringResource(R.string.assistant_subtitle), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                }
                if (messages.isNotEmpty()) IconAction(Icons.Filled.EditNote, stringResource(R.string.assistant_new_chat)) {
                    AssistantSession.clear()
                }
            }
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = Tokens.Space.screen, vertical = Tokens.Space.inline),
                verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                item(key = "greeting") {
                    Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                        NinoBubble { Text(stringResource(R.string.assistant_greeting), style = Tokens.Type.body, color = Tokens.Color.text) }
                        if (messages.isEmpty()) {
                            val chips = listOf(R.string.assistant_chip_1, R.string.assistant_chip_2, R.string.assistant_chip_3, R.string.assistant_chip_4)
                                .map { stringResource(it) }
                            FlowRow(Modifier.padding(start = 36.dp), horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline),
                                verticalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
                                chips.forEach { chip ->
                                    Box(Modifier.clip(RoundedCornerShape(50)).background(Tokens.Color.raised)
                                        .border(1.dp, Tokens.Color.borderStrong, RoundedCornerShape(50))
                                        .clickable(role = Role.Button) { send(chip, emptyList()) }
                                        .padding(horizontal = 14.dp, vertical = 9.dp)) {
                                        Text(chip, style = Tokens.Type.caption, color = Tokens.Color.accentText)
                                    }
                                }
                            }
                        }
                    }
                }
                items(messages, key = { System.identityHashCode(it) }) { message ->
                    if (message.user) UserBubble(message, onRetry = { AssistantSession.retry(context, message) })
                    else if (message.notice != null) NoticeBubble(message.notice, onReport)
                    else NinoBubble {
                        NinoReply(message.text)
                        message.report?.let {
                            Text(stringResource(R.string.assistant_report_sent), style = Tokens.Type.caption, color = Tokens.Color.success,
                                modifier = Modifier.background(Tokens.Color.success.copy(alpha = 0.1f), RoundedCornerShape(50))
                                    .padding(horizontal = 10.dp, vertical = 4.dp))
                        }
                    }
                }
                if (waiting) item(key = "typing") { TypingBubble() }
            }
            Composer(text, { text = it.take(NinoAssistant.MAX_TEXT) }, photos, loadingPhotos, photoError, enabled = !waiting,
                onAttach = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                onSend = { send(text, photos.toList()) })
        }
    }
}

/** Nino'nun balonu: solda küçük robot, açık yüzey. */
@Composable
private fun NinoBubble(thinking: Boolean = false, content: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
        NinoBot(28.dp, animate = thinking, bob = thinking)
        Column(
            Modifier.widthIn(max = 300.dp)
                .background(Tokens.Color.raised, RoundedCornerShape(18.dp, 18.dp, 18.dp, 6.dp))
                .border(1.dp, Tokens.Color.borderStrong, RoundedCornerShape(18.dp, 18.dp, 18.dp, 6.dp))
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(Tokens.Space.inline),
        ) { content() }
    }
}

@Composable
private fun NoticeBubble(notice: ChatNotice, onReport: () -> Unit) {
    val text = stringResource(when (notice) {
        ChatNotice.DISABLED -> R.string.assistant_disabled
        ChatNotice.RATE_LIMITED -> R.string.assistant_rate_limited
        ChatNotice.BUSY -> R.string.assistant_busy
        ChatNotice.NETWORK -> R.string.assistant_network
        ChatNotice.TOO_LARGE -> R.string.assistant_too_large
        ChatNotice.INVALID -> R.string.assistant_invalid
    })
    NinoBubble {
        Text(text, style = Tokens.Type.body, color = Tokens.Color.text, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
        if (notice == ChatNotice.DISABLED) {
            Box(Modifier.clip(RoundedCornerShape(50)).background(Tokens.Color.accent).clickable(role = Role.Button, onClick = onReport)
                .padding(horizontal = 16.dp, vertical = 9.dp)) {
                Text(stringResource(R.string.report_title), style = Tokens.Type.caption, color = Tokens.Color.onAccent)
            }
        }
    }
}

@Composable
private fun UserBubble(message: ChatMessage, onRetry: () -> Unit) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
        if (message.photos.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
            message.photos.forEach { photo ->
                Image(photo.thumbnail, stringResource(R.string.assistant_screenshot), Modifier.size(84.dp).clip(RoundedCornerShape(14.dp)),
                    contentScale = ContentScale.Crop)
            }
        }
        if (message.text.isNotEmpty()) Box(
            Modifier.widthIn(max = 300.dp).background(Tokens.Color.accent, RoundedCornerShape(18.dp, 18.dp, 6.dp, 18.dp))
                .padding(horizontal = 14.dp, vertical = 10.dp),
        ) { Text(message.text, style = Tokens.Type.body, color = Tokens.Color.onAccent) }
        when (message.state) {
            SendState.FAILED -> Row(Modifier.clip(RoundedCornerShape(50)).clickable(role = Role.Button, onClick = onRetry)
                .padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
                Text(stringResource(R.string.assistant_not_sent), style = Tokens.Type.caption, color = Tokens.Color.danger)
                Icon(Icons.Filled.Refresh, null, Modifier.size(14.dp), tint = Tokens.Color.accentText)
                Text(stringResource(R.string.assistant_retry), style = Tokens.Type.caption, color = Tokens.Color.accentText)
            }
            SendState.UNSENT -> Text(stringResource(R.string.assistant_not_sent), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            else -> {}
        }
    }
}

/** "Nino yazıyor": üç nokta sırayla yükselir; robot düşünür (süzülür). */
@Composable
private fun TypingBubble() {
    val label = stringResource(R.string.assistant_typing)
    val still = reducedMotion()
    val transition = rememberInfiniteTransition(label = "typing")
    val phase by transition.animateFloat(0f, 3f, infiniteRepeatable(tween(1200)), label = "phase")
    Box(Modifier.semantics { contentDescription = label; liveRegion = LiveRegionMode.Polite }) {
        NinoBubble(thinking = true) {
            Row(Modifier.heightIn(min = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                repeat(3) { index ->
                    val up = if (still) 0f else (1f - kotlin.math.abs(phase - index - 0.5f).coerceAtMost(1f))
                    Box(Modifier.offset(y = (-4 * up).dp).size(7.dp)
                        .background(Tokens.Color.secondary.copy(alpha = 0.45f + 0.55f * up), CircleShape))
                }
            }
        }
    }
}

@Composable
private fun Composer(text: String, onText: (String) -> Unit, photos: MutableList<ChatPhoto>, loadingPhotos: Boolean, photoError: Boolean,
                     enabled: Boolean, onAttach: () -> Unit, onSend: () -> Unit) {
    val canSend = enabled && !loadingPhotos && (text.isNotBlank() || photos.isNotEmpty())
    Column(Modifier.fillMaxWidth().background(Tokens.Color.raised.copy(alpha = 0.7f))
        .padding(horizontal = Tokens.Space.screen, vertical = Tokens.Space.inline),
        verticalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
        if (photos.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
            photos.toList().forEach { photo ->
                Box(Modifier.size(64.dp)) {
                    Image(photo.thumbnail, null, Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)), contentScale = ContentScale.Crop)
                    val remove = stringResource(R.string.report_remove_photo)
                    Box(Modifier.align(Alignment.TopEnd).padding(3.dp).size(22.dp).background(Tokens.Color.raised, CircleShape)
                        .border(1.dp, Tokens.Color.borderStrong, CircleShape).clickable(onClickLabel = remove) { photos.remove(photo) },
                        contentAlignment = Alignment.Center) { Icon(Icons.Filled.Close, remove, Modifier.size(12.dp), tint = Tokens.Color.text) }
                }
            }
        }
        if (photoError) Text(stringResource(R.string.report_photo_failed), style = Tokens.Type.caption, color = Tokens.Color.warning)
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
            val attach = stringResource(R.string.assistant_attach)
            Box(Modifier.size(Tokens.Control.icon).clip(CircleShape)
                .clickable(enabled = photos.size < NinoAssistant.MAX_IMAGES && !loadingPhotos, role = Role.Button, onClickLabel = attach, onClick = onAttach),
                contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.AddPhotoAlternate, attach, tint = if (photos.size < NinoAssistant.MAX_IMAGES) Tokens.Color.accentText else Tokens.Color.secondary)
            }
            OutlinedTextField(text, onText, Modifier.weight(1f), placeholder = { Text(stringResource(R.string.assistant_hint), style = Tokens.Type.body) },
                textStyle = Tokens.Type.body, maxLines = 5, shape = RoundedCornerShape(22.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedContainerColor = Tokens.Color.raised, unfocusedContainerColor = Tokens.Color.raised,
                    focusedBorderColor = Tokens.Color.accent, unfocusedBorderColor = Tokens.Color.borderStrong, cursorColor = Tokens.Color.accent,
                ))
            val sendLabel = stringResource(R.string.assistant_send)
            Box(Modifier.size(Tokens.Control.icon).clip(CircleShape).background(if (canSend) Tokens.Color.accent else Tokens.Color.surface2)
                .clickable(enabled = canSend, role = Role.Button, onClickLabel = sendLabel, onClick = onSend)
                .semantics { contentDescription = sendLabel },
                contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Filled.Send, null, Modifier.size(20.dp), tint = if (canSend) Tokens.Color.onAccent else Tokens.Color.secondary)
            }
        }
    }
}
