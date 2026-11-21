// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.abs

/**
 * Nino: harita ekranında seçilen görevin bilgi kartı (GTA 6): büyük harfli başlık ("BUY FLOWERS"), altında bir iki
 * cümle. Menü çevrilmez ama bu kartın Türkçesi kartın hemen altına yazılır (Windows: MapCard.cs, Mac: MapCard.swift ile
 * aynı kurallar).
 */
object MapCard {
    /**
     * [title]: başlık (yoksa boş); [sentences]: cümleler, yukarıdan aşağı, her cümle ayrı çevrilir; [box]: kartın
     * yazılarını çevreleyen kutu (0–1, kareye göre).
     */
    data class Found(val title: String, val sentences: List<String>, val box: TextBox, val lineHeight: Double)

    private val MAP_KEYS =
        setOf("recenter", "2d view", "3d view", "add marker", "remove marker", "set destination", "remove destination", "close menu")

    /** Harita ekranı mı: sağ alttaki tuş listesi ("RECENTER", "2D VIEW", "ADD MARKER", "SET DESTINATION", "CLOSE MENU"). */
    fun isMapScreen(reading: Reading): Boolean =
        reading.lines.map { cleanMenuText(it.text).lowercase() }.filter { it in MAP_KEYS }.distinct().size >= 2

    /** Bu satır haritanın tuş listesinden mi ("RECENTER", "2D VIEW"). */
    fun isMapKey(text: String): Boolean = cleanMenuText(text).lowercase() in MAP_KEYS

    /**
     * Menü satırının yazısı simgelerden arınmış hâliyle: baştaki ve sondaki harfsiz parçalar atılır (Mac: MenuBlock.clean).
     */
    internal fun cleanMenuText(text: String): String {
        val words = text.split(WHITESPACE).filter { it.isNotEmpty() }.toMutableList()
        while (words.isNotEmpty() && (!words[0].any { it.isLetter() } || (words[0].length <= 2 && !words[0].all { it.isLetter() })))
            words.removeAt(0)
        // Simge çoğu zaman küçük harf sanılır ("i Settings", "ii Map", "Il Game").
        while (words.size >= 2 && words[0].length <= 2 &&
            (!words[0].any { it.isUpperCase() } || words[0] == "Il" || words[0] == "II") &&
            words[1][0].isUpperCase())
            words.removeAt(0)
        while (words.isNotEmpty() && !words.last().any { it.isLetterOrDigit() }) words.removeAt(words.size - 1)
        return words.joinToString(" ")
    }

    private val WHITESPACE = Regex("""\s+""")
    private val DISTANCE = Regex("""\s*\b\d+(?:[.,]\d+)?\s?(?:km|mi|ft|m)\b\s*""")
    private val LEADING_ICONS = Regex("""^(?:[^A-Za-z\s]+\s+)+(?=[A-Z])""")
    private val ICON_CRUMBS = Regex("""^([iI•●◆△▲]|\S*\d\S*|ml)(\s+([iI•●◆△▲]|\S*\d\S*|ml))*\s+(?=[A-Z])""")
    private val TRAILING_SYMBOLS = Regex("""(\s+[^A-Za-z\s]{1,3})+$""")

    private fun endsSentence(text: String) = text.isNotEmpty() && text.last() in ".!?"

    /** Cümle satırı: küçük harfli, en az üç sözcük (yer adları ve uzaklıklar değil). */
    private fun isSentence(text: String) =
        text.split(' ').count { it.isNotEmpty() } >= 3 && text.count { it.isLowerCase() } >= 6

    private data class CardLine(val text: String, val box: TextBox)

    /**
     * Haritadaki kart: ekranın sol menüsü ve sağ alttaki tuş listesi dışında kalan, alt alta duran cümle satırları ve
     * hemen üstlerindeki büyük harfli başlık.
     */
    fun find(reading: Reading): Found? {
        var lines = mutableListOf<CardLine>()
        for (line in reading.lines) {
            val read = line.box ?: continue
            if (read.right <= 0.30) continue
            var place = read
            var text = line.text.trim(' ')
            // Haritadaki uzaklık etiketi ("1.53 km") kartın satırıyla birlikte okunabiliyor; atılır.
            if (DISTANCE.containsMatchIn(text)) {
                text = DISTANCE.replace(text, " ").trim(' ')
                if (place.left < 0.5) place = place.copy(left = maxOf(place.left, 0.5))
            }
            // Haritadaki simge harf/sayı okunup satırın başına eklenebiliyor ("(43) Cal challenged…").
            val lead = LEADING_ICONS.find(text)
            if (lead != null) {
                val length = lead.value.length
                val share = length.toDouble() / maxOf(1, text.length)
                place = place.copy(left = place.left + (place.right - place.left) * share)
                text = text.substring(length)
            }
            if (place.left <= 0.30 || text.count { it.isLetter() } < 3) continue
            lines.add(CardLine(text, place))
        }
        lines = lines.sortedBy { it.box.top }.toMutableList()
        val body = lines.filter { isSentence(it.text) }
        if (body.isEmpty()) return null
        val first = body[0]
        // İlk cümleyle aynı kartta olanlar: alt alta ve yatayda üst üste. Cümlenin kısa son satırı ve paragraf boşluğundan
        // sonraki ikinci paragraf da karttadır.
        val card = mutableListOf(first)
        for (line in lines.filter { it.box.top > first.box.top }) {
            val last = card.last()
            val height = last.box.bottom - last.box.top
            val gap = line.box.top - last.box.bottom
            val overlaps = line.box.left < last.box.right && last.box.left < line.box.right
            if (isSentence(line.text) && gap < height * 2.6 && overlaps && abs(line.box.left - first.box.left) < 0.06)
                card.add(line)
            else if (gap < height * 1.2 && abs(line.box.left - last.box.left) < 0.03 && line.text.any { it.isLowerCase() } && !endsSentence(last.text))
                card.add(line)
        }
        // Cümleler: sol kenarı aynı olan art arda satırlar tek cümledir; erken biten satırdan sonra büyük harfle başlayan
        // satır yeni cümledir. Küçük harfle başlayan satır her zaman önceki cümlenin devamıdır.
        val reach = card.maxOf { it.box.right }
        val sentences = mutableListOf<MutableList<CardLine>>()
        for (line in card) {
            val continues = line.text.isNotEmpty() && line.text[0].isLowerCase() &&
                !(sentences.isEmpty() || endsSentence(sentences.last().last().text))
            if (sentences.isNotEmpty()) {
                val head = sentences.last()[0]
                val last = sentences.last().last()
                if (continues || (abs(line.box.left - head.box.left) < 0.03 &&
                        line.box.top - last.box.bottom < (last.box.bottom - last.box.top) * 1.0 &&
                        !(last.box.right < reach - 0.04 && line.text.isNotEmpty() && line.text[0].isUpperCase()))) {
                    sentences.last().add(line)
                    continue
                }
            }
            sentences.add(mutableListOf(line))
        }
        val top = first.box
        var title: CardLine? = null
        for (line in lines)
            if (line.box.bottom <= top.top + 0.01 && top.top - line.box.bottom < 0.06 &&
                line.box.left < top.right && top.left < line.box.right + 0.05 &&
                line.text == line.text.uppercase() && line.text.count { it.isLetter() } >= 3)
                title = line
        var box = card.drop(1).fold(first.box) { a, b -> a.union(b.box) }
        title?.let { box = box.union(it.box) }
        // Kartın altındaki hedef satırı ("GOAL  $100 / $5,000") cümle değildir ama karttadır.
        for (line in lines.filter { it.box.top >= box.bottom - 0.005 }) {
            if (line.box.top - box.bottom >= 0.05 || line.box.left <= box.left - 0.03 || line.box.right >= box.right + 0.08) continue
            box = box.union(line.box)
        }
        val heights = card.map { it.box.bottom - it.box.top }.sorted()
        // Simge kırıntıları ("4 ml", "△", "00") baştan atılır; satır sonunda tireyle bölünen kelime birleşik kalır.
        val texts = sentences.map { s -> ICON_CRUMBS.replace(s.joinToString(" ") { it.text }.replace("- ", "-"), "") }
        val name = TRAILING_SYMBOLS.replace(title?.text ?: "", "")
        return Found(name, texts, box, heights[heights.size / 2])
    }

    /**
     * Nino (kullanıcı: "karenin köşelerini sınır almalı, metni değil"): kartın koyu çerçevesi, haritanın aydınlık
     * zemininden ayrılarak görüntüden bulunur. Yazıların kutusundan dışa doğru koyu kısım bitene kadar gidilir.
     */
    fun frame(box: TextBox, image: RgbImage): TextBox? {
        val color = PhonePanel.sampler(image, 640, 360)
        fun dark(x: Double, y: Double): Boolean = color(x, y)?.let { it.luminance / 1000 < 130 } ?: false
        val rows = mutableListOf<Double>()
        run { var y = box.top + 0.01; while (y < box.bottom) { rows.add(y); y += 0.02 } }
        val columns = mutableListOf<Double>()
        run { var x = box.left + 0.01; while (x < box.right) { columns.add(x); x += 0.03 } }
        if (rows.isEmpty() || columns.isEmpty()) return null
        // Bir yönde koyu satır/sütunların çoğu bitene kadar ilerlenir.
        fun edge(start: Double, step: Double, limit: Double, darkAt: (Double) -> Int, total: Int): Double {
            var position = start
            while (abs(position - start) < limit && darkAt(position + step) * 2 >= total) position += step
            return position
        }
        // Kenar sınıra kadar bulunamadıysa (gece haritası da koyu) o yanda yazıların kutusu biraz paylı kullanılır.
        fun bounded(found: Double, start: Double, limit: Double, fallback: Double): Double =
            if (abs(found - start) >= limit - 0.004) fallback else found
        val darkRows = { x: Double -> rows.count { dark(x, it) } }
        val darkColumns = { y: Double -> columns.count { dark(it, y) } }
        val left = bounded(edge(box.left, -0.003, 0.04, darkRows, rows.size), box.left, 0.04, box.left - 0.015)
        val right = bounded(edge(box.right, 0.003, 0.09, darkRows, rows.size), box.right, 0.09, box.right + 0.02)
        val bottom = bounded(edge(box.bottom, 0.004, 0.08, darkColumns, columns.size), box.bottom, 0.08, box.bottom + 0.02)
        val top = bounded(edge(box.top, -0.004, 0.06, darkColumns, columns.size), box.top, 0.06, box.top - 0.02)
        // Kart en az yazıların kutusu kadardır.
        if (right - left <= box.right - box.left) return null
        return TextBox(left, top, right, bottom)
    }
}
