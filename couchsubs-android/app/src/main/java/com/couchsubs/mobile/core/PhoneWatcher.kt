// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.io.File
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/**
 * Nino: oyundaki telefonda (GTA 6) bir sohbet açıksa mesajlarını okur, çevirir ve telefonun boş yanına mesajlaşma paneli
 * olarak koyar; sohbet olmayan uygulamada (BuckMe, Rydeme) her yazının Türkçesi uygulamanın renginde baloncuktur. Eskiden
 * bu yazılar altyazı sanılıp telefonun üstünde kocaman siyah kutuda çıkıyordu.
 *
 * Kurallar Mac'teki `AppModel.watchPhone` / `trackPhone`, iPhone'daki `PhoneWatcher.swift` ve Windows'taki
 * `PhoneWatcher.cs` ile aynıdır:
 * - Ana okuma hattını beklemez: [offer] kare iş parçacığında yalnız telefonun yerini bulup ekranını kopyalar, okuma ve
 *   çeviri [run] ile arka planda yapılır.
 * - Türkçeler yerleşmeden 0,6 sn'de, yerleştikten sonra 1,5 sn'de bir okunur.
 * - Aynı okuma iki kez görülünce çevrilir (kaydırma sürerken yarım okunan satırlar çevrilmez).
 * - Türkçeler yerleştikten sonra telefon elde sallanırsa yazı yeniden okunmadan yalnız yeri bulunur, balonlar kaydırılır.
 *
 * @param read telefonun ekranından kopyalanan görüntüyü okur (satırlar görüntüye göre, 0–1).
 * @param translate mesajı (sohbette önceki en çok üç mesajla) çevirir; sıra çağırana ait (havuz eşleşmesi, havuz, cihaz).
 * @param memoryFile çevrilen mesajların saklandığı dosya (çeviri diline özel); null ise yalnız bellekte.
 */
class PhoneWatcher(
    private val read: (Any) -> Reading,
    private val translate: (String, List<String>) -> Translation,
    private val memoryFile: File? = null,
    private val clock: () -> Long = { monotonicClock() },
    private val run: (Runnable) -> Unit,
    /** Telefonun yerinin takibi (yazı okunmadan); okuma ve çeviri sürerken de sürsün diye ayrı iş parçacığı olabilir. */
    private val runTrack: (Runnable) -> Unit = run,
) : AutoCloseable {
    /** Bir çeviri; [remember] false ise (cihazın yedek çevirisi) hafızaya yazılmaz, sonraki okumada havuz yeniden sorulur. */
    data class Translation(val text: String?, val remember: Boolean)

    /** Telefonu takip eder (koyu temalı uygulamada her karede bulunamıyor; bkz. [PhonePanel.Tracker]). */
    val tracker = PhonePanel.Tracker(clock)

    /** Satırın hazır çevirisi (ortak havuz); yoksa null. Hafızadakinden önce gelir. */
    @Volatile var known: ((String) -> String?)? = null
    /** Telefon uygulamalarının sabit Türkçeleri ([PhoneThread.glossary]) kullanılsın mı (hedef dil Türkçe). */
    @Volatile var useGlossary = true
    /** true döndüğü sürece (harita ya da menü açık) telefon aranmaz. */
    @Volatile var paused: (() -> Boolean)? = null
    /** Çevrilmemiş mesajlar (havuza bildirilmek üzere). */
    @Volatile var onUnknown: ((List<String>) -> Unit)? = null
    /** Gösterilecek öğeler değişti (boşsa telefonun yanı temizlenir). Arka plan iş parçacığında çağrılır. */
    @Volatile var onChange: ((List<ScreenTranslation.Item>) -> Unit)? = null
    @Volatile var log: ((String) -> Unit)? = null
    /** Nino: oyunun telefonunda sohbet ya da uygulama okundu (bu telefon GTA 6'ya özgü; oyun buradan da tanınır). */
    @Volatile var onPhoneScreen: (() -> Unit)? = null

    private val lock = Any()
    private var items: List<ScreenTranslation.Item> = emptyList()
    private var key = ""
    private var pending = ""
    private var seen = Long.MIN_VALUE / 2
    private var lastCheck = Long.MIN_VALUE / 2
    private var busy = false
    private var session = 0
    private var recent: Pair<List<String>, Long> = emptyList<String>() to Long.MIN_VALUE / 2
    private var placed: Pair<TextBox, List<ScreenTranslation.Item>>? = null
    private var anchors: Map<String, Double> = emptyMap()
    private var trackAt = Long.MIN_VALUE / 2
    private var trackBusy = false
    private var shift = 0.0 to 0.0
    private var shiftSeen: Pair<Double, Double>? = null
    private val memory: MutableMap<String, String> = loadMemory()
    /** Aynı anda en çok iki çeviri (cihaz üstü çeviri yazı okumayla işlemciyi paylaşır). */
    private val translations: ExecutorService = Executors.newFixedThreadPool(2)

    val shown: List<ScreenTranslation.Item> get() = synchronized(lock) { items }

    /** Telefonda son okunan mesajlar (son [RECENT_TEXTS_MS] içinde); altyazı okuması bunları atlar. */
    val recentTexts: List<String>
        get() = synchronized(lock) { if (clock() - recent.second < RECENT_TEXTS_MS) recent.first else emptyList() }

    /** Telefon uygulamasının sözcükleri altyazı okumasında görüldü: telefon bu yazıların yerinden de bulunur. */
    fun adopt(boxes: List<TextBox>, image: RgbImage) = tracker.adopt(boxes, image)

    /**
     * Her karede (kare iş parçacığında) çağrılır. [image] karenin renkli kopyasını, [crop] telefonun ekranının (0–1 kutu)
     * okunacak kopyasını verir; ikisi de yalnız gerektiğinde çağrılır. Hemen döner.
     */
    fun offer(image: () -> RgbImage?, crop: (TextBox) -> Any?) {
        val now = clock()
        val (due, tracking, started) = synchronized(lock) {
            val tracking = placed != null && items.isNotEmpty() && now - trackAt > TRACK_INTERVAL_MS
            if (tracking) trackAt = now
            val due = !busy && now - lastCheck > (if (items.isEmpty()) 600 else 1500)
            Triple(due, tracking, session)
        }
        if (!due && !tracking) return
        if (due && paused?.invoke() == true) {
            clear()
            return
        }
        val picture = image() ?: return
        // Takip ayrı iş parçacığında (kare iş parçacığı yalnız kopyalar); önceki takip bitmediyse bu kare atlanır.
        if (tracking && synchronized(lock) { if (trackBusy) false else { trackBusy = true; true } }) {
            try {
                runTrack(Runnable {
                    try { track(picture, started) } finally { synchronized(lock) { trackBusy = false } }
                })
            } catch (error: Exception) {
                synchronized(lock) { trackBusy = false }
            }
        }
        if (!due) return
        synchronized(lock) {
            if (busy || session != started) return
            busy = true
            lastCheck = now
        }
        try {
            val panel = tracker.locate(picture)
            if (panel == null) {
                finish(started)
                if (synchronized(lock) { items.isNotEmpty() && clock() - seen > 1200 }) clear()
                return
            }
            val pixels = crop(panel.box)
            if (pixels == null) {
                finish(started)
                return
            }
            run(Runnable {
                try {
                    val box = panel.box
                    val reading = Reading(read(pixels).lines.map { line -> line.copy(box = line.box?.placedIn(box)) })
                    process(picture, panel, reading, started)
                } catch (error: Exception) {
                    log?.invoke("telefon: okunamadı (${error.javaClass.simpleName})")
                } finally {
                    finish(started)
                }
            })
        } catch (error: Exception) {
            finish(started)
            log?.invoke("telefon: okunamadı (${error.javaClass.simpleName})")
        }
    }

    private fun finish(started: Int) = synchronized(lock) { if (session == started) busy = false }

    /** Telefonun yanını temizler, takibi bırakır; süren okumanın sonucu gösterilmez. */
    fun reset() {
        val had = synchronized(lock) {
            session++
            busy = false
            val had = items.isNotEmpty()
            items = emptyList()
            placed = null
            key = ""
            pending = ""
            recent = emptyList<String>() to Long.MIN_VALUE / 2
            shift = 0.0 to 0.0
            shiftSeen = null
            had
        }
        tracker.reset()
        if (had) onChange?.invoke(emptyList())
    }

    override fun close() {
        reset()
        translations.shutdownNow()
    }

    private fun clear() {
        synchronized(lock) {
            if (items.isEmpty()) return
            items = emptyList()
            placed = null
            key = ""
            pending = ""
        }
        onChange?.invoke(emptyList())
    }

    /** Okunmuş telefon ekranından öğeleri kurar (sınamalar doğrudan çağırır). */
    internal fun process(image: RgbImage, panel: PhonePanel.Panel, reading: Reading, started: Int = synchronized(lock) { session }) {
        // Haritanın tuş listesi ("RECENTER", "2D VIEW") telefon sanılan bölgede okunduysa bu haritadır.
        if (reading.lines.any { MapCard.isMapKey(it.text) }) {
            clear()
            return
        }
        // Sohbet: mesajlar balon olarak. Mesaj listesi çevrilmez. Başka uygulama (BuckMe bankası): satırları ayrı ayrı.
        // Başlığı ortalı uygulama ekranı ("Trip Details", Rydeme) sohbet sanılmasın: sohbette en az bir cümle olur.
        val threadMessages = if (PhoneThread.isThread(reading, panel)) PhoneThread.messages(reading, panel) else emptyList()
        val chat = threadMessages.any { PhoneThread.isSentence(it.text) }
        val messages = (if (chat) threadMessages else if (PhoneThread.isMessageList(reading)) emptyList() else PhoneThread.appLines(reading, panel))
            .toMutableList()
        if (messages.isEmpty()) {
            if (synchronized(lock) { items.isNotEmpty() && clock() - seen > 1200 }) clear()
            return
        }
        // Kaydırınca mesajların yeri değişir: anahtar yeri de içerir (telefonun ekranına göre; el sallanınca değişmez).
        val readKey = messages.joinToString("|") { TextMatch.normalize(it.text) + "@" + ((it.box.top - panel.box.top) * 60).toInt() }
        var stale = false
        var firstSight = false
        val known: Map<String, String>
        synchronized(lock) {
            if (session != started) return
            seen = clock()
            if (readKey == key) return
            // Sohbet kaydırıldı ya da mesajlar değişti: eski Türkçeler hemen kalkar.
            val base = placed
            if (base != null && items.isNotEmpty()) {
                val positions = HashMap<String, Double>()
                for (m in messages) positions.putIfAbsent(TextMatch.normalize(m.text), m.box.top - panel.box.top)
                // Okuyucu bir mesajı arada kaçırabiliyor (6 → 5 → 6); bu kaydırma değildir.
                val keys = base.second.filter { !it.backdrop }.map { TextMatch.normalize(it.source) }
                val common = keys.filter { positions.containsKey(it) }
                val moved = common.any { k -> anchors[k]?.let { abs(it - positions.getValue(k)) > 0.02 } == true }
                stale = moved || common.size * 2 < keys.size
                if (stale) {
                    items = emptyList()
                    placed = null
                    key = ""
                }
            }
            // Aynı okuma iki kez görülünce çevrilir.
            if (readKey != pending) {
                pending = readKey
                firstSight = true
            }
            known = HashMap(memory)
        }
        if (stale) onChange?.invoke(emptyList())
        // Oyunun telefonu okundu (kilidin dışında: dinleyici başka kilit alabilir).
        onPhoneScreen?.invoke()
        if (firstSight) return
        fun remembered(text: String): String? {
            val k = TextMatch.normalize(text)
            if (k.split(' ').size < 5) return known[k]
            // Sondan ya da baştan kesik okunan mesaj tam halinin çevirisini alır.
            return known.entries.filter { it.key == k || it.key.startsWith("$k ") || it.key.endsWith(" $k") }
                .maxByOrNull { it.key.length }?.value
        }
        // Ekranın dibinde cümlesi bitmemiş çok satırlı son mesaj, tamamı görünene kadar yarım çevrilmez.
        val last = messages.last()
        if (chat && remembered(last.text) == null && last.box.bottom > panel.box.bottom - 0.06 &&
            last.box.bottom - last.box.top > last.lineHeight * 1.8 && last.text.trimEnd().lastOrNull()?.let { it in ".!?…\")" } != true
        ) {
            messages.removeAt(messages.size - 1)
            if (messages.isEmpty()) return
        }
        // Ekranın üstünde baştan kesik (küçük harfle başlayan) ilk mesaj, tamamı görülmediyse yarım çevrilmez.
        if (chat && messages.size > 1 && remembered(messages[0].text) == null && messages[0].text.firstOrNull()?.isLowerCase() == true) {
            messages.removeAt(0)
        }
        // Havuzun (elden geçmiş) çevirisi cihazın hafızasındakinden önce gelir.
        val texts = messages.map { m ->
            (if (useGlossary) PhoneThread.glossary(m.text) else null) ?: this@PhoneWatcher.known?.invoke(m.text) ?: remembered(m.text) ?: ""
        }.toMutableList()
        val missing = messages.indices.filter { texts[it].isEmpty() }
        if (missing.isNotEmpty()) onUnknown?.invoke(missing.map { messages[it].text })
        // Sohbette her mesaj önceki (en çok üç) mesajla birlikte sorulur: kısaltma ve argo bağlamla doğru çevrilir.
        val work = missing.map { index ->
            val context = if (chat) messages.subList(maxOf(0, index - 3), index).map { it.text } else emptyList()
            translations.submit(Callable { runCatching { translate(messages[index].text, context) }.getOrElse { Translation(null, false) } })
        }
        val results = work.map { runCatching { it.get(60, TimeUnit.SECONDS) }.getOrElse { Translation(null, false) } }
        var wrote = false
        synchronized(lock) {
            if (session != started) return
            for ((slot, index) in missing.withIndex()) {
                val clean = withoutIcons(results[slot].text ?: "").trim()
                if (clean.isNotEmpty() && results[slot].remember) {
                    memory[TextMatch.normalize(messages[index].text)] = clean
                    wrote = true
                }
                texts[index] = clean
            }
            if (memory.size > 600) memory.clear()
        }
        if (wrote) saveMemory()
        // Sohbet: telefonun yanında dikey mesajlaşma paneli. Uygulama (BuckMe): her yazının hemen altında sade Türkçe.
        val color = PhonePanel.liftedSampler(image, panel)
        var built = if (chat) {
            PhoneThread.sideBubbles(messages, texts, panel, color, { text, width, line ->
                val wrapped = PhoneThread.wrap(text, width, line)
                wrapped.size to (wrapped.maxOfOrNull { it.length } ?: 0)
            }, chat = true, title = PhoneThread.titleText(reading, panel))
        } else {
            PhoneThread.appBubbles(messages, texts, panel, color)
        }
        val visible: List<ScreenTranslation.Item>
        synchronized(lock) {
            if (session != started) return
            recent = messages.map { it.text } to clock()
            anchors = messages.associate { TextMatch.normalize(it.text) to (it.box.top - panel.box.top) }
            // Kullanıcı isteği: panel telefonun yanında ayrı durur; telefon az oynadıysa yeni yerleşim eski telefon yerine
            // göre kurulur (panel yerinde kalır).
            var anchorPanel = panel.box
            val old = placed
            if (old != null) {
                val dx = (panel.box.left + panel.box.right - old.first.left - old.first.right) / 2
                val dy = (panel.box.top + panel.box.bottom - old.first.top - old.first.bottom) / 2
                if (abs(dx) < STEADY && abs(dy) < STEADY) {
                    built = PhoneThread.shifted(built, -dx, -dy)
                    anchorPanel = old.first
                }
                // Aynı mesaj yeniden okunduysa ve yeri az oynadıysa eski kutusu korunur (yazı boyu ve yeri zıplamasın).
                val current = PhoneThread.shifted(old.second, shift.first, shift.second)
                val sameScreen = !chat && current.size == built.size &&
                    current.zip(built).all { (a, b) -> a.translation == b.translation && abs(a.box.top - b.box.top) < 0.06 }
                val reach = if (chat) 0.012 to 0.015 else 0.04 to 0.06
                built = if (sameScreen) current else built.map { item ->
                    current.firstOrNull { same ->
                        same.source == item.source && same.translation == item.translation &&
                            abs(same.box.left - item.box.left) < reach.first && abs(same.box.top - item.box.top) < reach.second
                    } ?: item
                }
            }
            placed = anchorPanel to built
            items = built
            shift = 0.0 to 0.0
            shiftSeen = null
            key = readKey
            pending = ""
            visible = built.filter { !it.backdrop }
        }
        log?.invoke("telefon: ${visible.size} yazı" +
            (visible.firstOrNull()?.let { " (${it.source.take(40)} → ${it.translation})" } ?: "") + (if (chat) "" else " · uygulama"))
        onChange?.invoke(built)
    }

    /** Türkçeler yerleşikken telefon elde sallanır: yazı yeniden okunmadan yalnız yeri bulunur, örtüler kaydırılır. */
    private fun track(image: RgbImage, started: Int) {
        val found = PhonePanel.find(image)?.box ?: return
        val moved: List<ScreenTranslation.Item>
        synchronized(lock) {
            val base = placed ?: return
            if (session != started || items.isEmpty()) return
            // Telefonun ortası ne kadar kaydı (kenar okuması bir iki nokta oynar; ortalama daha sakin).
            val dx = (found.left + found.right - base.first.left - base.first.right) / 2
            val dy = (found.top + found.bottom - base.first.top - base.first.bottom) / 2
            if (!((abs(dx - shift.first) > 0.009 || abs(dy - shift.second) > 0.012) && abs(dx) < 0.08 && abs(dy) < 0.08)) {
                shiftSeen = null
                return
            }
            // Tek ölçümlük sıçrama gürültüdür; aynı yöndeki ikinci ölçümde kaydırılır (iki ölçümün ortalamasıyla).
            val previous = shiftSeen
            if (previous == null || abs(previous.first - dx) >= 0.008 || abs(previous.second - dy) >= 0.011) {
                shiftSeen = dx to dy
                return
            }
            shiftSeen = null
            shift = (previous.first + dx) / 2 to (previous.second + dy) / 2
            items = PhoneThread.shifted(base.second, shift.first, shift.second)
            moved = items
        }
        onChange?.invoke(moved)
    }

    private fun loadMemory(): MutableMap<String, String> {
        val file = memoryFile ?: return HashMap()
        return try {
            val parsed = org.json.JSONObject(file.readText())
            val out = HashMap<String, String>()
            for (k in parsed.keys()) out[k] = parsed.getString(k)
            out
        } catch (error: Exception) {
            HashMap()
        }
    }

    private fun saveMemory() {
        val file = memoryFile ?: return
        try {
            val copy = synchronized(lock) { HashMap(memory) }
            val json = org.json.JSONObject()
            for ((k, v) in copy) json.put(k, v)
            val temp = File(file.path + ".tmp")
            temp.writeText(json.toString())
            temp.renameTo(file)
        } catch (error: Exception) {
            log?.invoke("telefon: hafıza yazılamadı (${error.javaClass.simpleName})")
        }
    }

    companion object {
        /** Telefon bu kadardan az kaydıysa (elde sallanma) panel yerinde kalır. */
        const val STEADY = 0.05
        /** Telefondaki yazılar altyazı okumasında bu kadar süre altyazı sayılmaz. */
        const val RECENT_TEXTS_MS = 30_000L
        /** Telefonun yerinin (yazı okunmadan) en sık bulunma aralığı. */
        const val TRACK_INTERVAL_MS = 150L

        /** HTML varlıkları ("&amp;", "&#39;") düz yazıya çevrilir. */
        fun withoutEntities(text: String): String =
            if ('&' !in text) text
            else text.replace("&amp;", "&").replace("&#39;", "'").replace("&quot;", "\"").replace("&lt;", "<")
                .replace("&gt;", ">").replace("&apos;", "'")

        /** Çeviriye karışan simgeler (emoji, düğme simgeleri) atılır, boşluklar sadeleşir. */
        fun withoutIcons(text: String): String {
            val builder = StringBuilder(text.length)
            val source = withoutEntities(text)
            var i = 0
            while (i < source.length) {
                val code = source.codePointAt(i)
                val type = Character.getType(code)
                if (type != Character.OTHER_SYMBOL.toInt() && type != Character.MATH_SYMBOL.toInt() && type != Character.PRIVATE_USE.toInt()) {
                    builder.appendCodePoint(code)
                }
                i += Character.charCount(code)
            }
            return builder.toString().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        }
    }
}
