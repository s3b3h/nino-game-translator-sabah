// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.util.Locale
import kotlin.math.abs
import kotlin.math.atan

/** Bir noktanın rengi (bkz. [PhonePanel.Rgb]). */
typealias Rgb = PhonePanel.Rgb

/** Karedeki bir noktanın rengi (0–1 kesirlerle x, y); kare dışındaysa null. */
typealias ColorSampler = (Double, Double) -> Rgb?

/**
 * Nino: oyundaki telefonun ekranı (GTA 6: dikey, beyaz, büyük dikdörtgen). Telefon açıkken içindeki yazılar altyazı
 * değildir: siyah altyazı kutusunda değil, telefonun yanında yarı saydam yazıyla gösterilir (Windows: PhonePanel.cs,
 * Mac: PhonePanel.swift ile aynı kurallar ve eşikler).
 */
object PhonePanel {
    /** Bir noktanın rengi (0–255). */
    data class Rgb(val r: Int, val g: Int, val b: Int) {
        /** Parlaklık ×1000 (r·299 + g·587 + b·114). */
        val luminance: Int get() = r * 299 + g * 587 + b * 114
        val max: Int get() = maxOf(r, maxOf(g, b))
        val min: Int get() = minOf(r, minOf(g, b))
        val hex: String
            get() = String.format(Locale.ROOT, "#%02x%02x%02x", r.coerceIn(0, 255), g.coerceIn(0, 255), b.coerceIn(0, 255))
    }

    /**
     * Bulunan ekran. Yaya hâlde telefon eğik tutulur: ekran bir paralelkenardır, aşağı indikçe sola ya da sağa kayar.
     * [box]: ekranı çevreleyen dikdörtgen (0–1, kareye göre); [topLeft]: üst kenarda ekranın sol kenarı (x); [lean]: bir
     * kare yüksekliği aşağı inince sol kenarın x olarak kayması (dik telefonda 0); [width]: ekranın genişliği.
     */
    data class Panel(val box: TextBox, val topLeft: Double, val lean: Double, val width: Double) {
        /** Telefonun dönme açısı (derece, saat yönü artı; kare 16:9). */
        val angle: Double get() = atan(-lean * 16 / 9) * 180 / Math.PI

        /** [y] yüksekliğinde ekranın sol kenarı. */
        fun left(y: Double): Double = topLeft + lean * (y - box.top)

        fun center(y: Double): Double = left(y) + width / 2
    }

    /** Koyu ekranın satırlarının en az bu kadarında beyaz yazı noktası olmalı. */
    internal const val DARK_TEXT_SHARE = 0.15
    /** Küçültülmüş karede koyu ekrandaki yazının noktası (bulanıklaşmış beyaz): en parlak kanalı en az bu kadar. */
    internal const val DARK_TEXT_FLOOR = 110
    /** Koyu temalı ekran: en parlak kanal bundan koyu. */
    internal const val DARK_SCREEN_CEILING = 75
    /** Koyu ekranın çevresindeki gövde ekrandan belirgin açıktır: en parlak kanalı en az bu kadar. */
    internal const val BEZEL_FLOOR = 85
    /** Telefon ekranında uyan iki satır arasındaki en uzun boşluk (küçültülmüş karede satır). */
    internal const val MAX_ROW_GAP = 10
    /** Bir renk kanalı en az bu kadar parlaksa (ve üçü birbirine yakınsa) nokta beyaz sayılır. */
    internal const val WHITE_FLOOR = 118
    /** Telefonun siyah çerçevesi: ekranın hemen solu ve sağı bundan koyu olmalı. */
    internal const val DARK_CEILING = 90
    /** Telefon ekranının genişliği (kare genişliğine oranla). */
    internal const val MIN_WIDTH = 0.12
    internal const val MAX_WIDTH = 0.30
    /** Telefon ekranının ortasının durabileceği yer (x). */
    internal const val MIN_CENTER = 0.30
    internal const val MAX_CENTER = 0.80
    /** Telefon ekranının yüksekliği (kare yüksekliğine oranla). */
    internal const val MIN_HEIGHT = 0.38
    internal const val MAX_HEIGHT = 0.86
    /** Sınanan en çok aday (bkz. [find]). */
    internal const val MAX_ATTEMPTS = 32

    /** C# Math.Round(value, MidpointRounding.AwayFromZero). */
    internal fun round(value: Double): Int = if (value < 0) -Math.round(-value).toInt() else Math.round(value).toInt()

    /**
     * Karede telefonun beyaz ekranı; yoksa null. Kare küçültülür ve her satırda en uzun beyaz şerit aranır. Telefonun
     * ekranı çok sayıda satırda aynı genişlikte, kenarları bir doğru üzerinde duran şerit verir; hemen iki yanında
     * telefonun siyah çerçevesi vardır.
     */
    fun find(frame: RgbImage): Panel? {
        val width = 240
        val height = 135
        val pixels = frame.downscaled(width, height) ?: return null
        // (en koyu kanal, en parlak − en koyu)
        fun low(x: Int, y: Int): IntArray {
            val i = (y * width + x) * 3
            val r = pixels[i].toInt() and 0xff
            val g = pixels[i + 1].toInt() and 0xff
            val b = pixels[i + 2].toInt() and 0xff
            val lo = minOf(r, minOf(g, b))
            return intArrayOf(lo, maxOf(r, maxOf(g, b)) - lo)
        }
        find(width, height,
            { x, y -> val p = low(x, y); p[0] >= WHITE_FLOOR && p[1] <= 45 },
            { x, y -> low(x, y)[0] < DARK_CEILING })?.let { return it }
        // Nino: telefon elde bir süre dokunulmadan durunca ekranı kararıyor (gece sahnesinde beyaz ekran ≈70). Kare
        // karanlıksa ortasındaki en aydınlık kısım beyaza çekilip beyaz ekran yeniden aranır.
        val middle = mutableListOf<Int>()
        run {
            var y = height / 10
            while (y < height * 9 / 10) {
                var x = width * 15 / 100
                while (x < width * 85 / 100) { middle.add(low(x, y)[0]); x += 2 }
                y += 2
            }
        }
        middle.sort()
        val bright = if (middle.isEmpty()) 0 else middle[middle.size * 95 / 100]
        if (bright >= 40 && bright < WHITE_FLOOR) {
            val gain = 225.0 / bright
            fun lifted(x: Int, y: Int): IntArray {
                val p = low(x, y)
                return intArrayOf((p[0] * gain).toInt(), (p[1] * gain).toInt())
            }
            find(width, height,
                { x, y -> val p = lifted(x, y); p[0] >= WHITE_FLOOR && p[1] <= 45 },
                { x, y -> lifted(x, y)[0] < DARK_CEILING })?.let { return it }
        }
        // Nino: koyu temalı uygulama (GTA 6 Rydeme): ekran koyu, çevresindeki gövde açık. Aynı şekil sınamaları tersine
        // çevrilmiş renklerle.
        val dark = find(width, height,
            { x, y -> val p = low(x, y); p[0] + p[1] <= DARK_SCREEN_CEILING && p[1] <= 40 },
            { x, y -> val p = low(x, y); p[0] + p[1] >= BEZEL_FLOOR }) ?: return null
        if (dark.box.bottom > 0.96) return null
        // Koyu kıyafet ya da gölge de koyu dikdörtgen verebiliyor: koyu ekranın satırlarının belirgin bir kısmında beyaz
        // yazı noktaları olmalı.
        val top = (dark.box.top * height).toInt()
        val bottom = (dark.box.bottom * height).toInt()
        var texty = 0
        for (y in top until maxOf(top + 1, bottom)) {
            val from = (dark.left(y.toDouble() / height) * width).toInt() + 2
            val to = from + (dark.width * width).toInt() - 4
            if (to <= from) continue
            var lit = 0
            for (x in from..to) {
                val p = low(minOf(width - 1, maxOf(0, x)), y)
                if (p[0] + p[1] >= DARK_TEXT_FLOOR) lit++
            }
            if (lit >= 2 && lit <= (to - from + 1) * 0.6) texty++
        }
        return if (texty >= maxOf(1, bottom - top) * DARK_TEXT_SHARE) dark else null
    }

    private data class Candidate(val votes: Int, val slope: Double, val key: Int)

    /** Beyaz/koyu nokta haritasında telefonun ekranı (sınama için ayrı). */
    internal fun find(width: Int, height: Int, isWhite: (Int, Int) -> Boolean, isDark: (Int, Int) -> Boolean): Panel? {
        // Her satırın telefon genişliğindeki beyaz şeritleri. Yazının ince çizgileri şeridi bölmez (≤3 nokta).
        val runs = Array(height) { mutableListOf<IntArray>() }
        val minRun = (width * MIN_WIDTH).toInt()
        val maxRun = (width * MAX_WIDTH).toInt()
        for (y in 0 until height) {
            var x = 0
            while (x < width) {
                if (!isWhite(x, y)) { x++; continue }
                var end = x
                var probe = x + 1
                while (probe < width && probe - end <= 4) {
                    if (isWhite(probe, y)) end = probe
                    probe++
                }
                // Gümüş çerçevenin 1-2 noktalık parlak çizgisi ekranın şeridine eklenip sol kenarı kaydırıyordu; şeridin
                // başındaki ve sonundaki böyle kırıntılar atılır.
                var start = x
                var finish = end
                fun crumb(from: Int, step: Int): Int {
                    var n = 0
                    var p = from
                    while (p >= start && p <= finish && isWhite(p, y)) { n++; p += step }
                    return n
                }
                while (finish - start > 6) {
                    val head = crumb(start, 1)
                    if (!(head <= 2 && !isWhite(start + head, y) && !isWhite(start + head + 1, y))) break
                    start += head
                    while (start < finish && !isWhite(start, y)) start++
                }
                while (finish - start > 6) {
                    val tail = crumb(finish, -1)
                    if (!(tail <= 2 && !isWhite(finish - tail, y) && !isWhite(finish - tail - 1, y))) break
                    finish -= tail
                    while (finish > start && !isWhite(finish, y)) finish--
                }
                val length = finish - start + 1
                if (length in minRun..maxRun) runs[y].add(intArrayOf(start, finish))
                x = end + 1
            }
        }
        // Sol kenar bir doğrudur: başlangıç = a + eğim·satır. Her eğimin en güçlü birkaç adayı; en çok oy alandan
        // başlanarak sınamaları geçen ilk aday telefondur.
        val candidates = mutableListOf<Candidate>()
        val slopes = mutableListOf(0.0)
        for (i in 1..15) { slopes.add(i * 0.02); slopes.add(i * -0.02) }
        for (slope in slopes) {
            val votes = HashMap<Int, Int>()
            for (y in 0 until height) for (run in runs[y]) {
                val intercept = round(run[0] - slope * y)
                val key = (intercept + 400) / 2 * 1000 + (run[1] - run[0]) / 2
                votes[key] = (votes[key] ?: 0) + 1
            }
            votes.entries.sortedWith(compareByDescending<Map.Entry<Int, Int>> { it.value }.thenBy { it.key }).take(3)
                .forEach { if (it.value >= 8) candidates.add(Candidate(it.value, slope, it.key)) }
        }
        // Eşitlikte dik telefon (eğim 0, listede önce) öne geçer: sıralama kararlıdır.
        val ordered = candidates.sortedByDescending { it.votes }

        fun attempt(best: Candidate): Panel? {
            val guess = (best.key / 1000 * 2 - 400).toDouble()
            val span = best.key % 1000 * 2
            fun leftEdge(y: Int, intercept: Double) = intercept + best.slope * y
            val fit = HashMap<Int, IntArray>()
            for (y in 0 until height) for (run in runs[y]) {
                if (abs(run[0] - leftEdge(y, guess)) <= 3.5 && abs(run[1] - run[0] - span) <= 4) {
                    fit[y] = run
                    break
                }
            }
            var rows = fit.keys.sorted()
            // Telefonun üstündeki aydınlık pencere de aynı hizada ve genişlikte beyaz verebiliyor. Uyan satırlar uzun
            // boşluklarla parçalara ayrılır; başka parça varken karenin üst ya da alt kenarına değen parça atılır.
            val clusters = mutableListOf<MutableList<Int>>()
            for (y in rows) {
                if (clusters.isNotEmpty() && y - clusters.last().last() <= MAX_ROW_GAP) clusters.last().add(y)
                else clusters.add(mutableListOf(y))
            }
            val inner = clusters.filter { it[0] > 1 && it.last() < height - 2 }
            if (clusters.size > 1 && inner.isNotEmpty()) rows = inner.flatten()
            if (rows.size < 8) return null
            val intercepts = rows.map { fit[it]!![0] - best.slope * it }.sorted()
            val intercept = intercepts[intercepts.size / 2]
            val widths = rows.map { fit[it]!![1] - fit[it]!![0] }.sorted()
            val runWidth = widths[widths.size / 2]
            fun left(y: Int) = round(leftEdge(y, intercept))
            fun near(y: Int, test: (Int, Int) -> Boolean, positive: Boolean): Boolean {
                for (d in 1..4) {
                    val hit = test(maxOf(0, left(y) - d), y)
                    if (if (positive) hit else !hit) return true
                }
                return false
            }
            fun nearRight(y: Int, test: (Int, Int) -> Boolean, positive: Boolean): Boolean {
                for (d in 1..4) {
                    val hit = test(minOf(width - 1, left(y) + runWidth + d), y)
                    if (if (positive) hit else !hit) return true
                }
                return false
            }
            // Siyah çerçeve: bu satırların çoğunda ekranın hemen solu ve sağı koyu (kenarın 1-4 nokta yakınında).
            val framed = rows.count { near(it, isDark, true) && nearRight(it, isDark, true) }
            // Gündüz telefonun bir yanı güneşli tahta olabiliyor: satırların çoğunda iki yanı beyaz olmayan ve en az üçte
            // birinde koyu çerçeveli beyaz şerit de telefondur.
            val edged = rows.count { near(it, isWhite, false) && nearRight(it, isWhite, false) }
            if (!(framed >= rows.size * 0.7 || (edged >= rows.size * 0.85 && framed >= rows.size * 0.35))) return null
            // Üst ve alt kenar: şeridin yarıdan çoğu beyaz olduğu sürece ekrandır.
            fun bright(y: Int): Boolean {
                val from = maxOf(0, left(y))
                val to = minOf(width - 1, left(y) + runWidth)
                if (to <= from) return false
                var white = 0
                for (x in from..to) if (isWhite(x, y)) white++
                return white >= (to - from + 1) * 0.5
            }
            var first = rows[0]
            var last = rows.last()
            while (first > 0 && bright(first - 1)) first--
            while (last < height - 1 && bright(last + 1)) last++
            rows = rows.filter { it in first..last }
            val tall = (last - first + 1).toDouble() / height
            // Ekranın en az dörtte biri baştan sona beyaz olmalı.
            if (tall < MIN_HEIGHT || tall > MAX_HEIGHT || rows.size < (last - first + 1) * 0.25) return null
            // Dikey dikdörtgen (nokta olarak yükseklik/genişlik; kare 16:9).
            val shape = tall * 9 / ((runWidth + 1).toDouble() / width * 16)
            if (shape < 1.2 || shape > 2.6) return null
            val w = width.toDouble()
            val h = height.toDouble()
            val topLeft = leftEdge(first, intercept)
            val bottomLeft = leftEdge(last, intercept)
            val box = TextBox(maxOf(0.0, minOf(topLeft, bottomLeft)) / w, first / h,
                minOf(w, maxOf(topLeft, bottomLeft) + runWidth + 1) / w, (last + 1) / h)
            // Telefon ekranın ortasında (yaya) ya da sağ yarısında (araçta) durur ve kenarlara değmez. Telefon eğilip aşağı
            // indirilince ekranın alt kenarından taşar; üstü ekranın ortalarındaysa telefondur.
            val center = (box.left + box.right) / 2
            if (center < MIN_CENTER || center > MAX_CENTER || box.top < 0.04 || !(box.bottom <= 0.96 || box.top >= 0.2)) return null
            return Panel(box, topLeft / w, best.slope * h / w, (runWidth + 1) / w)
        }
        // Aynı beyaz alan birkaç eğimde de aday çıkar; telefonun sırası gelsin diye yeterince aday sınanır (Windows ile
        // aynı: 32 aday).
        for (best in ordered.take(MAX_ATTEMPTS)) attempt(best)?.let { return it }
        return null
    }

    /**
     * Karedeki bir noktanın rengi (0–1 kesirlerle x, y; çevresindeki 3×3 noktanın ortalaması). Kare bir kez
     * [width]×[height] boyutuna getirilir (küçük karede büyütülerek, Windows gibi).
     */
    fun sampler(frame: RgbImage, width: Int = 960, height: Int = 540): ColorSampler {
        val pixels = frame.downscaled(width, height) ?: return { _, _ -> null }
        return sample@{ x, y ->
            val cx = round(x * width)
            val cy = round(y * height)
            if (cx < 1 || cy < 1 || cx >= width - 1 || cy >= height - 1) return@sample null
            var r = 0
            var g = 0
            var b = 0
            for (dy in -1..1) for (dx in -1..1) {
                val i = ((cy + dy) * width + cx + dx) * 3
                r += pixels[i].toInt() and 0xff
                g += pixels[i + 1].toInt() and 0xff
                b += pixels[i + 2].toInt() and 0xff
            }
            Rgb(r / 9, g / 9, b / 9)
        }
    }

    /**
     * Nino: telefonun ekranı kararmışsa (dokunulmadan duran telefon) renkler aydınlatılarak okunur: ekranın en aydınlık
     * kısmı (zemin) beyaza çekilir. Koyu temalı uygulamanın ekranı olduğu gibi kalır.
     */
    fun liftedSampler(frame: RgbImage, panel: Panel): ColorSampler {
        val base = sampler(frame)
        var colors = mutableListOf<Rgb>()
        var y = panel.box.top + 0.03
        while (y < panel.box.bottom - 0.02) {
            var share = 0.05
            while (share <= 0.95 + 1e-9) {
                base(panel.left(y) + panel.width * share, y)?.let { colors.add(it) }
                share += 0.1
            }
            y += 0.02
        }
        colors = colors.sortedBy { it.max }.toMutableList()
        val lights = colors.map { it.max }
        if (lights.isEmpty()) return base
        val screen = lights[lights.size * 8 / 10]
        val middle = lights[lights.size / 2]
        val zone = colors[colors.size * 8 / 10]
        val gray = zone.min.toDouble() / maxOf(1, zone.max)
        val brightest = lights.last()
        if (!(screen >= 40 && screen < 232 && middle >= screen * 0.8 && gray >= 0.8 && brightest <= screen * 1.3)) return base
        val gain = 238.0 / screen
        return { x, yy ->
            base(x, yy)?.let { c -> Rgb(minOf(255, (c.r * gain).toInt()), minOf(255, (c.g * gain).toInt()), minOf(255, (c.b * gain).toInt())) }
        }
    }

    /**
     * Telefon uygulamasının yazılarından telefon ekranının tahmini yeri: elde tutulan GTA 6 telefonu ≈ 0,21 genişlik,
     * ekranın 0,20–0,82'si; yazılar bu tahminin dışına taşıyorsa kutu onları da içine alır.
     */
    fun guess(boxes: List<TextBox>): Panel {
        val minLeft = if (boxes.isNotEmpty()) boxes.minOf { it.left } else 0.6
        val maxRight = if (boxes.isNotEmpty()) boxes.maxOf { it.right } else 0.78
        val left = maxOf(0.02, minLeft - 0.015)
        val right = minOf(0.98, maxOf(maxRight + 0.015, left + 0.21))
        val top = minOf(0.2, (if (boxes.isNotEmpty()) boxes.minOf { it.top } else 0.3) - 0.02)
        val bottom = minOf(0.95, maxOf(0.82, (if (boxes.isNotEmpty()) boxes.maxOf { it.bottom } else 0.8) + 0.03))
        return Panel(TextBox(left, maxOf(0.04, top), right, bottom), left, 0.0, right - left)
    }

    /** Ekranın içindeki noktaların ne kadarı koyu ([dark]) ya da beyaz ekran rengi. */
    internal fun screenShare(panel: Panel, frame: RgbImage, dark: Boolean): Double {
        val sample = sampler(frame, 480, 270)
        var hits = 0
        var total = 0
        for (row in 1..14) {
            val y = panel.box.top + (panel.box.bottom - panel.box.top) * row / 15
            for (column in 1..7) {
                val c = sample(panel.left(y) + panel.width * column / 8, y) ?: continue
                total++
                if (if (dark) c.max <= DARK_SCREEN_CEILING + 10 else c.min >= WHITE_FLOOR && c.max - c.min <= 45) hits++
            }
        }
        return if (total == 0) 0.0 else hits.toDouble() / total
    }

    /**
     * Nino: bir kez bulunan telefonu takip eder. Koyu temalı uygulamada (Rydeme) kartlar ve alt pencere ekranı böldüğünden
     * telefon her karede baştan bulunamıyordu. Bulunamayan karede, son bulunan yerde hâlâ aynı tür ekran (koyu ya da
     * beyaz) duruyorsa telefon orada sayılır. Takip en son gerçek bulunuştan [maxAgeMs] sürer.
     */
    class Tracker(clock: (() -> Long)? = null) {
        private val gate = Any()
        private val now: () -> Long = clock ?: { System.nanoTime() / 1_000_000 }
        private var last: Panel? = null
        private var dark = false
        private var lastSeen = Long.MIN_VALUE / 2
        @Volatile var maxAgeMs: Long = 20_000

        /**
         * Nino: telefon uygulamasının sözcükleri görüldü ama telefon bulunamadı (alt penceresi açık koyu uygulama).
         * Telefonun yeri bu yazıların yerinden tahmin edilip takip oradan başlar.
         */
        fun adopt(boxes: List<TextBox>, frame: RgbImage) {
            if (boxes.isEmpty()) return
            synchronized(gate) { if (!(last == null || now() - lastSeen > 2000)) return }
            val guess = guess(boxes)
            val isDark = screenShare(guess, frame, dark = true) >= 0.45
            synchronized(gate) { last = guess; dark = isDark; lastSeen = now() }
        }

        fun locate(frame: RgbImage): Panel? {
            find(frame)?.let { found ->
                val isDark = screenShare(found, frame, dark = true) >= 0.5
                synchronized(gate) { last = found; dark = isDark; lastSeen = now() }
                return found
            }
            val previous: Panel
            val wasDark: Boolean
            synchronized(gate) {
                val kept = last
                if (now() - lastSeen >= maxAgeMs || kept == null) return null
                previous = kept
                wasDark = dark
            }
            // Nino (Android): kare 960×540 kopyadan okunur; koyu telefon bir nokta dar bulunur ve kapüşonlu menü karesinde
            // aynı yerin koyu payı 0,47 ölçülüp (tam boyda 0,45 altı) telefon bırakılmıyordu: altyazı 20 sn maskeleniyordu.
            // Koyu ekranda eşik 0,50 (gerçek koyu alt pencere 0,59). Mac/Windows tam boy karede 0,45 kullanır.
            if (screenShare(previous, frame, wasDark) < (if (wasDark) KEEP_DARK_SHARE else 0.45)) {
                synchronized(gate) { last = null }
                return null
            }
            return previous
        }

        fun reset() {
            synchronized(gate) { last = null }
        }

        companion object {
            /** Koyu telefon (Rydeme, alt pencere) bulunamayan karede bu koyu payla yerinde sayılır (bkz. [locate]). */
            const val KEEP_DARK_SHARE = 0.5
        }
    }
}
