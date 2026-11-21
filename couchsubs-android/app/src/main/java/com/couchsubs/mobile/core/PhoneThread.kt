// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.abs
import kotlin.math.ceil

/**
 * Nino: telefondaki sohbet ekranının mesajları ve Türkçelerinin telefonun yanındaki yeri (Windows: PhoneThread.cs,
 * Mac: PhonePanel.swift içindeki PhoneThread ile aynı kurallar).
 */
object PhoneThread {
    data class Message(val text: String, val box: TextBox, val lineHeight: Double)

    /** Telefon ekranının en üstündeki başlık şeridi (ekran yüksekliğine oranla). */
    internal const val HEADER_SHARE = 0.07
    /** Başlık şeridinin hemen altında bu kadar (kare yüksekliğine oranla) içinde başlayan satır kesiktir. */
    internal const val CLIPPED_TOP = 0.012
    /** Yazının kenarından balonun içine doğru: rengin okunduğu yer. */
    internal const val BUBBLE_INSET = 0.0045
    /** Örtünün yazıdan taşması. */
    internal const val COVER_PAD_X = 0.0035
    const val COVER_PAD_Y = 0.004
    /** Panelin genişliği (kare genişliğine oranla), balonların ve zeminin saydamlığı. */
    const val SIDE_WIDTH = 0.27
    const val SIDE_ALPHA = 0.95
    const val BACKDROP_ALPHA = 0.6
    /** Panelin altında logoya bırakılan yer (kare yüksekliğine oranla). */
    internal const val BADGE_SPACE = 0.03

    private fun trim(text: String) = text.trim(' ')

    private fun words(text: String): List<String> = text.split(' ').filter { it.isNotEmpty() }

    /** "#rrggbb" → sayı; geçersizse null. */
    private fun hexValue(hex: String?): Int? {
        if (hex == null || hex.length != 7) return null
        val digits = hex.substring(1)
        if (!digits.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
        return digits.toInt(16)
    }

    /**
     * Telefon ekranındaki okuma (kareye göre yerleşmiş) bir sohbet mi: en üstte, ekranın ortasında kişinin adı durur.
     * Mesaj listesinde en üstteki yazı sola yaslıdır; liste çevrilmez.
     */
    fun isThread(reading: Reading, panel: PhonePanel.Panel): Boolean = title(reading, panel) != null

    /** Sohbetin başlığındaki ad ("Lucia", "Fleeca, Laguna Lane"): panelin en üstünde ortada gösterilir. */
    fun titleText(reading: Reading, panel: PhonePanel.Panel): String? {
        val box = title(reading, panel) ?: return null
        return reading.lines.firstOrNull { it.box == box }?.let { trim(it.text) }
    }

    /** Sohbetin başlığı (kişinin adı) olan satırın kutusu: başlık şeridinde ya da ekrandaki en üst satırdır. */
    internal fun title(reading: Reading, panel: PhonePanel.Panel): TextBox? {
        val height = panel.box.bottom - panel.box.top
        val boxes = reading.lines.mapNotNull { it.box }
        val topmost = if (boxes.isNotEmpty()) boxes.minOf { it.top } else 0.0
        for (line in reading.lines) {
            val box = line.box ?: continue
            if (!(box.top < panel.box.top + height * HEADER_SHARE || box.top <= topmost + 0.002)) continue
            val text = trim(line.text)
            val middle = (box.top + box.bottom) / 2
            // Başlık kişi ya da yer adıdır; yer adında virgül, nokta, kesme ve & olabilir ("Fleeca, Laguna Lane").
            val nameLike = text.length >= 2 && words(text).size <= 5 &&
                text.all { it.isLetter() || it in " ,.'’&-" } && text.any { it.isLetter() }
            // Gezinme düğmesi ("Back", "< Back") kişi adı değildir.
            val bare = text.lowercase().trim { it == '<' || it == '‹' || it == ' ' }
            if (bare in setOf("back", "geri", "done", "close", "cancel", "edit")) continue
            if (!(MessageCards.isName(text) || nameLike) || abs((box.left + box.right) / 2 - panel.center(middle)) >= panel.width * 0.12) continue
            // Listede adın hemen altında, aynı hizada önizleme satırı durur; sohbet başlığının altında aynı hizada satır yoktur.
            val indent = box.left - panel.left(box.top)
            if (boxes.any { other -> other.top > box.top + 0.008 && other.top < box.top + 0.05 &&
                    abs(other.left - panel.left(other.top) - indent) < 0.015 }) continue
            return box
        }
        return null
    }

    private data class Piece(val text: String, val box: TextBox)

    /**
     * Sohbet ekranındaki mesajlar, yukarıdan aşağı. Başlık (kişinin adı), "New message", yer/eşya etiketleri ve harfsiz
     * satırlar mesaj değildir.
     */
    fun messages(reading: Reading, found: PhonePanel.Panel): List<Message> {
        val panel = found.box
        val panelHeight = panel.bottom - panel.top
        val header = maxOf(panel.top + panelHeight * HEADER_SHARE, title(reading, found)?.bottom ?: 0.0)
        // Satırın ortasındaki emoji satırı ikiye bölüyor; aynı satırdaki parçalar önce birleşir.
        val lines = joiningPieces(reading).lines
            .filter { it.box != null }
            .map { Piece(trim(it.text), it.box!!) }
            .filter { line ->
                line.text.count { it.isLetter() } >= 2 &&
                    // En üstteki başlık şeridi ve başlığın hemen altında yarısı kesik satır.
                    line.box.top > header + CLIPPED_TOP &&
                    // Ekranın alt kenarında yarısı görünen satır okunamaz.
                    line.box.bottom < panel.bottom - 0.01
            }
            .sortedBy { it.box.top }
        // Satır aralığı: art arda iki satırın üst kenarları arasındaki en küçük fark.
        val steps = lines.zipWithNext { a, b -> b.box.top - a.box.top }.filter { it >= 0.012 && it <= 0.04 }
        val pitch = if (steps.isNotEmpty()) steps.min()
        else (if (lines.isNotEmpty()) lines.minOf { it.box.bottom - it.box.top } else 0.025) * 1.2
        val groups = mutableListOf<MutableList<Piece>>()
        for (line in lines) {
            // Eğik telefonda paragrafın satırları aşağı indikçe yana kayar: sol kenar ekranın kenarına göre ölçülür.
            val indent = line.box.left - found.left(line.box.top)
            if (groups.isNotEmpty()) {
                val last = groups.last().last()
                val head = groups.last()[0]
                if (line.box.top - last.box.top < pitch * 1.6 && abs(indent - (head.box.left - found.left(head.box.top))) < 0.02) {
                    groups.last().add(line)
                    continue
                }
            }
            groups.add(mutableListOf(line))
        }
        val result = mutableListOf<Message>()
        for (group in groups) {
            val text = group.joinToString(" ") { it.text }
            if (isLabel(text)) continue
            val box = group.drop(1).fold(group[0].box) { a, b -> a.union(b.box) }
            result.add(Message(text, box, pitch * 0.85))
        }
        return result
    }

    /** Aynı satırda, aralarında küçük boşlukla (emoji) yan yana okunan parçalar tek satır olur. */
    internal fun joiningPieces(reading: Reading): Reading {
        val rows = mutableListOf<TextLine>()
        for (line in reading.lines.sortedBy { it.box?.left ?: 0.0 }) {
            val box = line.box
            if (box == null) { rows.add(line); continue }
            val index = rows.indexOfFirst { row ->
                val other = row.box ?: return@indexOfFirst false
                val overlap = minOf(box.bottom, other.bottom) - maxOf(box.top, other.top)
                val smaller = minOf(box.bottom - box.top, other.bottom - other.top)
                smaller > 0 && overlap >= smaller * 0.75 && box.left - other.right <= 0.03 && box.left > other.right - 0.005
            }
            val joined = if (index >= 0) rows[index].box else null
            if (joined != null) rows[index] = rows[index].copy(text = rows[index].text + " " + line.text, box = joined.union(box))
            else rows.add(line)
        }
        return Reading(rows)
    }

    private val LABEL_WORDS = setOf("new message", "new messages", "typing", "delivered", "read", "today", "yesterday", "messages encrypted")

    /**
     * Mesaj olmayan satır: "New message", "Typing...", ek olarak gönderilen yer ya da eşyanın adı (her sözcüğü büyük
     * harfle başlar, cümle noktalaması yoktur).
     */
    internal fun isLabel(text: String): Boolean {
        val lowered = text.lowercase().trim { it == '.' || it == '…' || it == '•' || it == ' ' }
        if (lowered in LABEL_WORDS) return true
        // Kilit simgesi harf sanılıyor ("A Messages encrypted").
        if (lowered.endsWith("messages encrypted") || lowered.endsWith("message encrypted")) return true
        // Mesaja eklenen uygulama bağlantısının kartı ("BuckMe") mesaj değildir.
        if (TextMatch.normalize(text) in PHONE_APP_NAMES) return true
        val words = words(text)
        if (words.size < 2 || text.any { it in ".,!?…" }) return false
        return words.all { word -> word[0].isUpperCase() || word.lowercase() in setOf("del", "de", "la", "of", "the", "&") }
    }

    /** Türkçelerin duracağı sütun (sol, sağ): telefonun boş kalan (geniş) yanında, en çok [maxWidth] genişliğinde. */
    fun column(found: PhonePanel.Panel, maxWidth: Double = 0.30): Pair<Double, Double> {
        val panel = found.box
        val gap = 0.035
        if ((panel.left + panel.right) / 2 > 0.5) {
            val right = panel.left - gap
            return Pair(maxOf(0.02, right - maxWidth), right)
        }
        val left = panel.right + gap
        return Pair(left, minOf(0.98, left + maxWidth))
    }

    /** Her çevirinin kutusu: mesajın hizasında, sütunun içinde; üst üste binmesinler diye gerekirse aşağı kayar. */
    fun boxes(messages: List<Message>, lineCounts: List<Int>, lineHeights: List<Double>, column: Pair<Double, Double>): List<TextBox> {
        val result = mutableListOf<TextBox>()
        var floor = 0.0
        for (index in messages.indices) {
            val height = lineHeights[index] * maxOf(1, lineCounts[index]) * 1.3
            val top = minOf(maxOf(messages[index].box.top, floor), maxOf(0.0, 0.98 - height))
            result.add(TextBox(column.first, top, column.second, top + height))
            floor = top + height + lineHeights[index] * 0.6
        }
        return result
    }

    /**
     * Mesajların Türkçesi her mesaj balonunun tam üstünde, balonun kendi rengiyle; balonun rengi yazının hemen solundan
     * (balonun iç payı) ve kutunun içinin aydınlık yarısından okunur.
     */
    fun covers(messages: List<Message>, translations: List<String>, color: ColorSampler, angle: Double = 0.0): List<ScreenTranslation.Item> {
        val result = mutableListOf<ScreenTranslation.Item>()
        for (i in 0 until minOf(messages.size, translations.size)) {
            val message = messages[i]
            val text = translations[i].trim()
            // Ek kartının adı ("BuckMe" bağlantısı) "BuckMe mi?" diye soruya çevrilip mesaj gibi çıkıyordu.
            if (text.isEmpty() || !worthShowing(message.text, text)) continue
            val box = message.box
            val points = mutableListOf<Pair<Double, Double>>()
            for (share in doubleArrayOf(0.15, 0.35, 0.5, 0.65, 0.85))
                for (inset in doubleArrayOf(BUBBLE_INSET, BUBBLE_INSET * 0.6))
                    points.add(Pair(box.left - inset, box.top + (box.bottom - box.top) * share))
            // Eğik telefonda yazının solu balonun dışına düşüyor; balonun içinden de okunur (aydınlık yarının ortancası).
            var inside = mutableListOf<Rgb>()
            for (yi in 0..7) for (xi in 0..8) {
                val y = 0.15 + yi * 0.1
                val x = 0.1 + xi * 0.1
                color(box.left + (box.right - box.left) * x, box.top + (box.bottom - box.top) * y)?.let { inside.add(it) }
            }
            inside = inside.sortedBy { it.luminance }.toMutableList()
            val ground = if (inside.size >= 10) inside.drop(inside.size - inside.size * 4 / 10) else emptyList()
            val edges = points.mapNotNull { color(it.first, it.second) }
            val edge = if (edges.isNotEmpty()) edges.maxBy { it.luminance } else Rgb(233, 233, 236)
            // İçerisi harf kadar koyuysa (kutu yazıyı sıkı sarıyor) yazının solundaki pay kullanılır.
            val fill = if (ground.isEmpty() || ground[ground.size / 2].luminance * 4 < edge.luminance * 3) edge else ground[ground.size / 2]
            val light = fill.luminance / 1000 > 140
            result.add(ScreenTranslation.Item(
                source = message.text, translation = text,
                box = TextBox(box.left - COVER_PAD_X, box.top - COVER_PAD_Y, box.right + COVER_PAD_X, box.bottom + COVER_PAD_Y),
                lineHeight = message.lineHeight,
                fill = fill.hex, ink = if (light) "#2c2c2e" else "#f5f5f7", angle = angle,
            ))
        }
        return result
    }

    /** Telefon kaydıysa (el sallanıyor) örtüler de aynı kadar kaydırılır; yazı yeniden okunmaz. */
    fun shifted(items: List<ScreenTranslation.Item>, dx: Double, dy: Double): List<ScreenTranslation.Item> =
        items.map { it.copy(box = TextBox(it.box.left + dx, it.box.top + dy, it.box.right + dx, it.box.bottom + dy)) }

    /**
     * Türkçenin [width] genişlikte (kare genişliğine oranla) ve [line] satır yüksekliğinde sözcük sözcük satırlara
     * bölünmüşü (Mac: AppModel.wrap).
     */
    fun wrap(text: String, width: Double, line: Double): List<String> {
        val perLine = maxOf(12, (width / maxOf(0.004, line * 0.5 * 9 / 16)).toInt())
        val lines = mutableListOf<String>()
        var current = ""
        for (word in words(text)) {
            if (current.isNotEmpty() && current.length + 1 + word.length > perLine) {
                lines.add(current)
                current = ""
            }
            current += if (current.isEmpty()) word else " $word"
        }
        if (current.isNotEmpty()) lines.add(current)
        return if (lines.isEmpty()) listOf(text) else lines
    }

    /**
     * Nino (kullanıcı isteği, 20 Kasım 2026): mesajların Türkçesi telefonun yanında, telefon boyunda dikey bir mesajlaşma
     * paneli içinde: zemin telefondaki sohbetin zemini gibi ve biraz saydam; gelen mesajlar solda, giden mesajlar sağda,
     * her biri kendi balonunun renginde ve mesajın hizasında. İlk öğe panelin zeminidir.
     * [lines](metin, genişlik, satır) Türkçenin o genişlikte kaç satır tuttuğunu ve en uzun satırın harf sayısını verir.
     */
    fun sideBubbles(
        messages: List<Message>, translations: List<String>, panel: PhonePanel.Panel, color: ColorSampler,
        lines: (String, Double, Double) -> Pair<Int, Int>, chat: Boolean = true, title: String? = null,
    ): List<ScreenTranslation.Item> {
        val covers = covers(messages, translations, color)
        if (covers.isEmpty()) return emptyList()
        val kept = covers.map { cover -> messages.first { it.text == cover.source } }
        val column = column(panel, SIDE_WIDTH)
        val inset = 0.012
        val gap = 0.012
        val innerLeft = column.first + inset
        val innerRight = column.second - inset
        val bubbleMax = (innerRight - innerLeft) * 0.82
        val pad = 0.012
        val counts = mutableListOf<Int>()
        val longest = mutableListOf<Int>()
        val heights = mutableListOf<Double>()
        for (index in covers.indices) {
            // Kullanıcı isteği: Türkçe %4, sonra %6 daha büyütüldü (→ 0,97).
            val line = minOf(maxOf(kept[index].lineHeight, 0.018), 0.028) * 0.97
            val measured = lines(covers[index].translation, bubbleMax - pad, line)
            counts.add(measured.first)
            longest.add(measured.second)
            heights.add(line)
        }
        var boxes = boxes(kept, counts, heights, Pair(innerLeft, innerRight))
        // Panel telefonun boyundadır; balonlar sığmazsa yukarı doğru sıkışır. Panelin sağ altında Nino logosu durur.
        val bottom = panel.box.bottom - gap - BADGE_SPACE
        if (boxes.isNotEmpty() && boxes.last().bottom > bottom) {
            val shift = boxes.last().bottom - bottom
            boxes = boxes.map { it.copy(top = it.top - shift, bottom = it.bottom - shift) }
        }
        // Giden mesaj: telefonda sağa yaslı ya da aynı sohbetin en gri balonundan belirgin mavi.
        val blueness = covers.map { blueShift(it.fill) }
        val grayest = blueness.min()
        val indents = kept.map { it.box.left - panel.left(it.box.top) }
        val rights = kept.map { it.box.right - panel.left(it.box.top) }
        val leftmost = indents.min()
        val rightmost = rights.max()
        val outgoing = covers.indices.map { i ->
            val rightAligned = indents[i] - leftmost > panel.width * 0.1 && rightmost - rights[i] < panel.width * 0.08
            chat && (isOutgoing(kept[i], panel) || rightAligned || blueness[i] - grayest >= 14)
        }
        val items = mutableListOf<ScreenTranslation.Item>()
        // Zemin: sohbetin zemini balonların arasından (gelen balonların sağındaki boşluk) okunur.
        val samples = kept.filter { !isOutgoing(it, panel) }.mapNotNull { m ->
            val y = (m.box.top + m.box.bottom) / 2
            color(panel.left(y) + panel.width - 0.012, y)
        }
        val sorted = samples.sortedBy { it.r + it.g + it.b }.drop(samples.size / 2)
        val ground = if (sorted.isNotEmpty()) sorted[0] else Rgb(226, 228, 233)
        // Kullanıcı: balonlar zeminden ayrışsın; zemin beyaz ve şeffaf olsun (mesajlar uygulamasının açık zemini gibi).
        val lightChat = chat && ground.luminance / 1000 > 150
        val toWhite = if (lightChat) 0.6 else 0.0
        fun lift(v: Int) = (v + (255 - v) * toWhite).toInt()
        var backdrop = ScreenTranslation.Item(
            source = "", translation = "", box = TextBox(column.first, panel.box.top, column.second, panel.box.bottom), lineHeight = 0.02,
            fill = Rgb(lift(ground.r), lift(ground.g), lift(ground.b)).hex, alpha = BACKDROP_ALPHA, backdrop = true,
        )
        // Kullanıcı isteği: panelin en üstünde ortada gönderenin adı (TV başlık olarak çizer; ad çevrilmez).
        if (chat && !title.isNullOrEmpty())
            backdrop = backdrop.copy(translation = title, lineHeight = minOf(maxOf(kept.maxOf { it.lineHeight }, 0.02), 0.028))
        items.add(backdrop)
        for (index in covers.indices) {
            var box = boxes[index]
            val width = minOf(bubbleMax, longest[index] * heights[index] * 0.5 * 9 / 16 + pad + 0.012)
            if (!chat) {
                // Uygulama ekranı: her satır telefondaki yatay yerine ve genişliğine göre (ölçeklenerek) durur.
                val message = kept[index]
                val scale = (innerRight - innerLeft) / panel.width
                val left = message.box.left - panel.left(message.box.top)
                val boxLeft = innerLeft + maxOf(0.0, left) * scale - pad / 2
                box = box.copy(left = boxLeft,
                    right = minOf(innerRight, boxLeft + maxOf(width, (message.box.right - message.box.left) * scale + pad)))
            } else if (outgoing[index]) {
                box = box.copy(left = innerRight - width, right = innerRight)
            } else {
                box = box.copy(left = innerLeft, right = innerLeft + width)
            }
            box = box.copy(bottom = box.bottom + heights[index] * 0.3)
            var item = covers[index]
            val value = if (lightChat) hexValue(item.fill) else null
            if (value != null) {
                val r = ((value shr 16) and 0xff).toDouble()
                val g = ((value shr 8) and 0xff).toDouble()
                val b = (value and 0xff).toDouble()
                val tuned = if (outgoing[index]) doubleArrayOf(r * 0.86, g * 0.93, minOf(255.0, b * 1.04))
                else doubleArrayOf(r + (255 - r) * 0.7, g + (255 - g) * 0.7, b + (255 - b) * 0.7)
                item = item.copy(fill = Rgb(tuned[0].toInt(), tuned[1].toInt(), tuned[2].toInt()).hex)
            }
            items.add(item.copy(box = box, lineHeight = heights[index], angle = null, alpha = SIDE_ALPHA, side = true))
        }
        return items
    }

    /** Rengin maviliği: mavi kanalın kırmızı ve yeşilin ortalamasından farkı. */
    internal fun blueShift(hex: String?): Int {
        val value = hexValue(hex) ?: return 0
        val r = (value shr 16) and 0xff
        val g = (value shr 8) and 0xff
        val b = value and 0xff
        return b - (r + g) / 2
    }

    /** Giden mesaj: telefonda sağa yaslı balon (sol kenarı ekranın içinde epey içeride başlar). */
    internal fun isOutgoing(message: Message, panel: PhonePanel.Panel): Boolean =
        message.box.left - panel.left(message.box.top) > panel.width * 0.2

    /**
     * Nino: sohbet olmayan telefon uygulaması (BuckMe bankası): her yazı satırı ayrı çevrilir. Harfsiz satırlar, üstteki
     * başlık şeridi ve alt kenarda yarısı görünen satır alınmaz; alt alta devam eden satırlar tek cümledir.
     */
    fun appLines(reading: Reading, found: PhonePanel.Panel): List<Message> {
        val panel = found.box
        val panelHeight = panel.bottom - panel.top
        var lines = mutableListOf<Message>()
        for (line in reading.lines) {
            val box = line.box ?: continue
            // Satırın başındaki simge ("◆ Checking Account") çevrilmez.
            val trimmed = trim(line.text)
            var start = 0
            while (start < trimmed.length && !trimmed[start].isLetter() && !trimmed[start].isDigit() && trimmed[start] !in "$€£") start++
            val text = trim(trimmed.substring(start))
            // Boş sohbetin "Messages encrypted" yazısı uygulama yazısı değildir.
            val lowered = text.lowercase()
            if (lowered.endsWith("messages encrypted") || lowered.endsWith("message encrypted")) continue
            if (text.count { it.isLetter() } < 3 || box.top <= panel.top + panelHeight * HEADER_SHARE || box.bottom >= panel.bottom - 0.01) continue
            lines.add(Message(text, box, (box.bottom - box.top) * 0.85))
        }
        lines = lines.sortedBy { it.box.top }.toMutableList()
        val merged = mutableListOf<Message>()
        for (line in lines) {
            if (merged.isNotEmpty()) {
                val last = merged.last()
                val gap = line.box.top - last.box.bottom
                val height = line.box.bottom - line.box.top
                val words = words(last.text).count { w -> w.any { it.isLetter() } }
                val ended = last.text.isNotEmpty() && last.text.last() in ".!?:"
                // Yazar satırı ("By Rusty Travers") paragrafa katılmaz.
                val byline = last.text.lowercase().startsWith("by ") && words <= 4
                val continues = !byline && ((line.text.isNotEmpty() && line.text[0].isLowerCase()) || (!ended && words >= 3))
                if (gap < height * 0.6 && abs(line.box.left - last.box.left) < 0.02 && continues) {
                    merged[merged.size - 1] = last.copy(text = last.text + " " + line.text, box = last.box.union(line.box))
                    continue
                }
            }
            merged.add(line)
        }
        return merged
    }

    /**
     * Kutudaki yazı açık zeminde koyu yazı mı (telefon ekranı, mesaj balonu): zemin (ortanca parlaklık) yazının
     * noktalarından aydınlıktır. Altyazı ise koyu sahnede (ya da siyah kutuda) beyaz yazıdır.
     */
    fun isDarkOnLight(box: TextBox, color: ColorSampler): Boolean {
        val values = mutableListOf<Int>()
        val step = maxOf((box.bottom - box.top) / 6, 0.001)
        var y = box.top
        while (y <= box.bottom + 1e-12) {
            for (si in 0..32) {
                val share = 0.02 + si * 0.03
                color(box.left + (box.right - box.left) * share, y)?.let { values.add(it.luminance / 1000) }
            }
            y += step
        }
        if (values.size < 20) return false
        values.sort()
        val darkest = values[values.size / 20]
        val middle = values[values.size / 2]
        val brightest = values[values.size * 19 / 20]
        return middle - darkest >= 25 && middle - darkest > (brightest - middle) * 2
    }

    /**
     * Çevrilecek yazı mı: çevirisi boş değil, aslının aynısı değil ve tek sözcüklü aslını olduğu gibi içermiyor ("buckme"
     * → "BuckMe mi?": marka adı çevrilmez).
     */
    fun worthShowing(source: String, translation: String): Boolean {
        val a = TextMatch.normalize(source)
        val b = TextMatch.normalize(translation)
        return b.isNotEmpty() && a != b && !(b.contains(a) && !a.contains(' '))
    }

    /**
     * Nino: oyun telefonunun arayüz yazıları (GTA 6 BuckMe bankası, mesajlar) için sabit Türkçe. Kısa arayüz yazısı
     * bağlamsız çevrilince saçmalıyordu ("Checking Account" → "Borsa Hesabı").
     */
    fun glossary(text: String): String? {
        val key = TextMatch.normalize(text)
        GLOSSARY_TERMS[key]?.let { return it }
        // "Book Ryde ($82)" → "Ryde Çağır ($82)": parantez içindeki tutar korunur.
        val open = text.indexOf('(')
        if (open >= 0 && text.endsWith(')')) {
            GLOSSARY_TERMS[TextMatch.normalize(text.substring(0, open))]?.let { return it + " " + text.substring(open) }
        }
        // "Muscle - High" → "Kas - Yüksek"
        val parts = text.split(" - ")
        if (parts.size == 2) {
            val leftName = STAT_NAMES[TextMatch.normalize(parts[0])]
            val rightLevel = STAT_LEVELS[TextMatch.normalize(parts[1])]
            if (leftName != null && rightLevel != null) return "$leftName - $rightLevel"
        }
        // Tanıma tireyi düşürebiliyor ("Muscle High").
        val words = words(key)
        if (words.size >= 2) {
            val level = STAT_LEVELS[words.last()]
            val name = STAT_NAMES[words.dropLast(1).joinToString(" ")]
            if (level != null && name != null) return "$name - $level"
        }
        // "Level 3/4" → "Seviye 3/4"
        val raw = words(text)
        if (key.startsWith("level ") && raw.size >= 2 && raw[1].contains('/')) return "Seviye " + raw[1]
        // "$4,900 to next goal" → "Sonraki hedefe $4.900"
        if (key.endsWith(" to next goal") && raw.isNotEmpty() && raw[0].any { it.isDigit() })
            return "Sonraki hedefe " + raw[0].replace(',', '.')
        return null
    }

    /** Telefonun mesaj listesi mi: "…" ile kesilmiş önizlemeler var. */
    fun isMessageList(reading: Reading): Boolean =
        MessageCards.isList(reading) && reading.lines.any { line ->
            val text = trim(line.text)
            text.endsWith("...") || text.endsWith('…')
        }

    /**
     * Cümle mi (sohbet mesajı): cümle noktalaması ya da küçük harfle başlayan sözcüğü var. Her sözcüğü büyük harfle
     * başlayan arayüz yazısı ("Book Ryde ($82)") cümle değildir.
     */
    fun isSentence(text: String): Boolean {
        val words = words(text).filter { w -> w.any { it.isLetter() } }
        val trimmed = trim(text)
        if (words.size >= 2 && trimmed.isNotEmpty() && trimmed.last() in ".!?") return true
        if (text.any { it == '!' || it == '?' } && words.size >= 2) return true
        return words.size >= 3 && words.drop(1).any { it[0].isLowerCase() }
    }

    private val PARENTHESIS = Regex("""\(.*\)""")

    /**
     * Nino: oyun telefonunun uygulamalarına özgü sözcükler. Bu yazılar her zaman telefondadır: telefon o karede
     * bulunamasa da altyazı sayılmaz.
     */
    fun isPhoneUI(text: String): Boolean {
        // Kök olarak aranır: yazı tanıma bir harfi yanlış okusa da ("Destinatior") tanınsın.
        val key = " " + TextMatch.normalize(text)
        if (PHONE_UI_WORDS.any { key.contains(" $it") }) return true
        // Uygulama adları tam sözcük olarak ("Ryde", "Rydeme"; "Rydell" değil).
        if (words(key).any { it in PHONE_APP_NAMES }) return true
        val bare = TextMatch.normalize(PARENTHESIS.replace(text, ""))
        if (bare in GLOSSARY_TERMS) return true
        // Sözlüğün kalıplarıyla çevrilen yazı da telefondadır; tek sözcükler diyalogda da geçebilir, sayılmaz.
        return words(text).size >= 2 && glossary(text) != null
    }

    /** Uygulama adları ve uygulamaya özgü sözcükler (tek başına geçince yeter). */
    internal val PHONE_UI_WORDS = listOf(
        "trip detail", "change destinat", "destinatio", "messages encrypt", "map pin expir", "checking accoun", "family saving",
        // Fitness uygulaması (tek sözcük değil kalıp: diyalogdaki "workout" altyazı olarak kalsın)
        "workout window", "strength workout", "cardio workout", "calorie balanc", "maintain weight", "gain weight", "lose weight",
    )

    internal val PHONE_APP_NAMES = setOf("ryde", "rydeme", "buckme")

    internal val STAT_NAMES = mapOf(
        "muscle" to "Kas", "body fat" to "Vücut Yağı", "stamina" to "Dayanıklılık", "strength" to "Güç", "fat" to "Yağ",
    )

    internal val STAT_LEVELS = mapOf(
        "high" to "Yüksek", "low" to "Düşük", "medium" to "Orta", "average" to "Ortalama", "very high" to "Çok Yüksek",
        "very low" to "Çok Düşük",
    )

    internal val GLOSSARY_TERMS = mapOf(
        // Gazete adları çevrilmez (aynısı döner, baloncuk gösterilmez).
        "vice city horn" to "Vice City Horn", "the leonida journal" to "The Leonida Journal", "leonida journal" to "Leonida Journal",
        "ripped" to "Kaslı", "toned" to "Sıkı", "average" to "Ortalama", "body & nutrition" to "Vücut ve Beslenme",
        "body nutrition" to "Vücut ve Beslenme",
        "strength workout" to "Güç Antrenmanı", "cardio workout" to "Kardiyo Antrenmanı", "workout window" to "Antrenman zamanı",
        "focus" to "Odak", "fitness" to "Fitness", "calorie balance" to "Kalori Dengesi", "you will maintain weight" to "Kilonu koruyacaksın",
        "you will gain weight" to "Kilo alacaksın", "you will lose weight" to "Kilo vereceksin", "hungry" to "Aç", "full" to "Tok",
        "trip details" to "Yolculuk Bilgileri", "cost" to "Ücret", "choose ryde" to "Ryde Seç", "standard ryde" to "Standart Ryde",
        "change destination" to "Varış Noktasını Değiştir", "book ryde" to "Ryde Çağır", "cancel ryde" to "Ryde'ı İptal Et",
        "checking account" to "Vadesiz Hesap", "savings account" to "Birikim Hesabı", "family savings" to "Aile Birikimi",
        "family savings video" to "Aile Birikimi Videosu", "atm finder" to "ATM Bulucu", "faqs" to "SSS",
        "savings" to "Birikim", "balance" to "Bakiye", "deposit" to "Para Yatır", "withdraw" to "Para Çek", "transfer" to "Transfer",
        "transactions" to "Hesap Hareketleri", "recent transactions" to "Son Hareketler", "set a goal" to "Hedef Belirle",
        "messages encrypted" to "Mesajlar şifreli", "new message" to "Yeni mesaj", "all contacts" to "Tüm Kişiler",
        "suggested" to "Önerilenler", "messages" to "Mesajlar", "map pin expired" to "Konum süresi doldu",
    )

    /**
     * Nino (kullanıcı isteği, 20 Kasım 2026): sohbet olmayan uygulamada Türkçe, telefonun yanındaki boşlukta uygulamanın
     * kendi renginde (ekrandaki en canlı renk; BuckMe'de mor) baloncuklar olarak, her yazının hizasında ve telefona yakın
     * kenara yaslı durur. Zemin paneli yoktur.
     */
    fun appBubbles(lines: List<Message>, translations: List<String>, panel: PhonePanel.Panel, color: ColorSampler): List<ScreenTranslation.Item> {
        val kept = lines.zip(translations).filter { worthShowing(it.first.text, it.second) }
        if (kept.isEmpty()) return emptyList()
        var accent = Rgb(58, 58, 60)
        fun strongest(points: List<Pair<Double, Double>>): Rgb? {
            var best = 60
            var found: Rgb? = null
            for ((x, y) in points) {
                val c = color(x, y) ?: continue
                val saturation = c.max - c.min
                // Yeterince aydınlık olmalı (koyu ekrandaki koyu lacivert uygulamanın rengi değildir).
                if (saturation > best && c.max >= 120) { best = saturation; found = c }
            }
            return found
        }
        val header = mutableListOf<Pair<Double, Double>>()
        var yi = 0
        while (true) {
            val y = panel.box.top - 0.04 + yi * 0.01
            if (y >= panel.box.top + 0.06 - 1e-12) break
            for (si in 1..9) header.add(Pair(panel.left(y) + panel.width * si * 0.1, y))
            yi++
        }
        val around = kept.flatMap { p ->
            val b = p.first.box
            val middle = (b.top + b.bottom) / 2
            listOf(Pair(b.left - 0.006, middle), Pair(b.right + 0.006, middle),
                Pair((b.left + b.right) / 2, b.top - 0.006), Pair((b.left + b.right) / 2, b.bottom + 0.006))
        }
        // Nino (kullanıcı fikri): uygulamanın belirgin rengi yoksa baloncuk ekranın baskın arka planı ve yazı rengiyle çizilir.
        var ink = "#ffffff"
        val strong = strongest(header) ?: strongest(around)
        if (strong != null) {
            accent = strong
        } else {
            val bins = HashMap<Int, MutableList<Rgb>>()
            var y = panel.box.top + 0.02
            while (y < panel.box.bottom - 0.01) {
                for (si in 1..19) {
                    val c = color(panel.left(y) + panel.width * si * 0.05, y) ?: continue
                    val key = ((c.r / 16) shl 8) or ((c.g / 16) shl 4) or (c.b / 16)
                    bins.getOrPut(key) { mutableListOf() }.add(c)
                }
                y += 0.01
            }
            if (bins.isNotEmpty()) {
                val crowd = bins.entries.sortedWith(compareByDescending<Map.Entry<Int, MutableList<Rgb>>> { it.value.size }.thenBy { it.key })
                    .first().value
                val back = Rgb(crowd.sumOf { it.r } / crowd.size, crowd.sumOf { it.g } / crowd.size, crowd.sumOf { it.b } / crowd.size)
                fun distance(c: Rgb) = abs(c.r - back.r) + abs(c.g - back.g) + abs(c.b - back.b)
                val strokes = mutableListOf<Rgb>()
                for ((line, _) in kept) {
                    val b = line.box
                    val step = maxOf((b.bottom - b.top) / 8, 0.002)
                    var sy = b.top
                    while (sy <= b.bottom + 1e-12) {
                        for (si in 1..49) color(b.left + (b.right - b.left) * si * 0.02, sy)?.let { strokes.add(it) }
                        sy += step
                    }
                }
                accent = back
                val lightBack = back.luminance > 128_000
                val text = strokes.maxByOrNull { distance(it) }
                ink = if (text != null && distance(text) >= 90) {
                    if (lightBack) Rgb((text.r * 0.6).toInt(), (text.g * 0.6).toInt(), (text.b * 0.6).toInt()).hex
                    else Rgb(255 - (255 - text.r) / 2, 255 - (255 - text.g) / 2, 255 - (255 - text.b) / 2).hex
                } else {
                    if (lightBack) "#1c1c1e" else "#ffffff"
                }
            }
        }
        val column = column(panel, SIDE_WIDTH)
        val onLeft = column.second <= panel.box.left
        var floor = 0.0
        // Bütün baloncuklarda aynı yazı boyu (ortanca satır yüksekliği).
        val heights = kept.map { it.first.lineHeight / 0.85 }.sorted()
        val size = minOf(maxOf(heights[heights.size / 2], 0.018), 0.028) * 0.95
        val items = mutableListOf<ScreenTranslation.Item>()
        for ((line, turkish) in kept) {
            val text = turkish.trim()
            // Uzun yazı (haber paragrafı) sütun genişliğinde alt satırlara kaydırılır.
            val charWidth = size * 0.5 * 9 / 16
            val room = column.second - column.first
            val perLine = maxOf(8, ((room - 0.03) / (charWidth * 0.85)).toInt())
            val rows = maxOf(1, ceil(text.length.toDouble() / perLine).toInt())
            val width = if (rows > 1) room else minOf(room, text.length * charWidth + 0.03)
            val height = if (rows > 1) size * (1.22 * rows + 0.45) else size * 1.55
            val top = minOf(maxOf(if (rows > 1) line.box.top else (line.box.top + line.box.bottom) / 2 - height / 2, floor), maxOf(0.0, 0.98 - height))
            floor = top + height + size * 0.4
            val left = if (onLeft) column.second - width else column.first
            items.add(ScreenTranslation.Item(
                source = line.text, translation = text, box = TextBox(left, top, left + width, top + height), lineHeight = size,
                fill = accent.hex, ink = ink, alpha = SIDE_ALPHA, side = true,
            ))
        }
        return items
    }
}

/** Nino: telefona gelen mesaj kartının ve mesaj listesinin tanınması (Windows: MessageCards, Mac: MessageCard.swift'in gereken kısmı). */
object MessageCards {
    /** Telefonun mesaj listesi: en az üç satır; iki ad ya da iki "…" ile kesilmiş önizleme. */
    fun isList(reading: Reading): Boolean {
        val lines = reading.lines.map { it.text.trim(' ') }
        val names = lines.count(::isName)
        val truncated = lines.count { it.endsWith("...") || it.endsWith('…') }
        return lines.size >= 3 && (names >= 2 || truncated >= 2)
    }

    /** Kişi adı gibi: 1-4 sözcük, her biri büyük harfle başlar, noktalamasız. */
    fun isName(text: String): Boolean {
        val words = text.split(' ').filter { it.isNotEmpty() }
        return text.length in 2..30 && words.size in 1..4 &&
            words.all { it[0].isUpperCase() || it[0] == '&' } &&
            words.all { w -> w.drop(1).count { it.isUpperCase() } <= 1 } &&
            text.any { it.isLowerCase() } && text.none { it in ".,!?:;…\"" }
    }
}
