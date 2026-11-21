// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil

/**
 * Nino: haritada seçili görevin kartı ("BUY FLOWERS / Lucia will appreciate this / Have some flowers delivered…")
 * çevrilir ve kartın hemen altına (yer yoksa üstüne) oyunun kartı gibi yazılır; menünün kalanı çevrilmez. Harita açıkken
 * altyazı okunmaz ve telefon aranmaz. Kurallar Mac (`AppModel.showMapCard` / `placeMapCard`), iPhone
 * (`MapCardWatcher.swift`) ve Windows (`MapCardWatcher.cs`) ile aynıdır.
 *
 * Android'de köşe çevirisi olmadığından (Windows'taki gibi) karenin tamamı seyrek ([intervalMs]'de bir) ve kendi
 * okuyucusuyla okunur.
 *
 * @param read [REGION] bölgesinden kopyalanan görüntüyü okur (satırlar görüntüye göre, 0–1).
 * @param translate parçayı çevirir (sıra çağırana ait: havuz eşleşmesi, havuz, cihaz); olmazsa null.
 */
class MapCardWatcher(
    private val read: (Any) -> Reading,
    private val translate: (String) -> String?,
    private val intervalMs: Long = DEFAULT_INTERVAL_MS,
    private val clock: () -> Long = { monotonicClock() },
    private val run: (Runnable) -> Unit,
) {
    /** Kart başlığı bu dilin büyük harfiyle yazılır ("İ"). */
    @Volatile var targetLanguage = "tr"
    /** Gösterilecek öğeler değişti (boşsa kart kalkar). Arka plan iş parçacığında çağrılır. */
    @Volatile var onChange: ((List<ScreenTranslation.Item>) -> Unit)? = null
    @Volatile var log: ((String) -> Unit)? = null
    /** Nino: her okumanın (karenin büyük kısmı) satırları; oyun buradan da tanınır (bkz. [GameMarkers]). */
    @Volatile var onScreen: ((Reading) -> Unit)? = null

    private val lock = Any()
    private var items: List<ScreenTranslation.Item> = emptyList()
    private var key = ""
    private var waiting: MapCard.Found? = null
    private var translating = false
    private val memory = HashMap<String, List<String>>()
    private var shownCard: Pair<String, Double> = "" to -1.0
    private var shownText = ""
    private var mapUntil = Long.MIN_VALUE / 2
    private var lastPass = Long.MIN_VALUE / 2
    private var busy = false
    private var session = 0
    private var lastImage: RgbImage? = null

    val shown: List<ScreenTranslation.Item> get() = synchronized(lock) { items }

    /** Harita ekranı açık mı (son [MAP_HOLD_MS] içinde tuş listesi görüldü). */
    val mapOpen: Boolean get() = synchronized(lock) { clock() < mapUntil }

    /** Harita az önce açıktı (telefon araması bu süre de bekler; harita kapanırken telefon sanılıyordu). */
    fun recentlyOpen(extraMs: Long): Boolean = synchronized(lock) { clock() < mapUntil + extraMs || items.isNotEmpty() }

    /**
     * Her karede (kare iş parçacığında) çağrılır; zamanı geldiyse [image] (renkli kopya, kartın çerçevesi için) ve [crop]
     * ([REGION] bölgesinin okunacak kopyası) alınır, okuma arka planda yapılır. Hemen döner.
     */
    fun offer(image: () -> RgbImage?, crop: (CropRegion) -> Any?) {
        val started = synchronized(lock) {
            val now = clock()
            // Harita açıkken daha sık bakılır: kart değişince Türkçesi çabuk gelsin (Mac ile aynı).
            val interval = if (now < mapUntil + 10_000) minOf(intervalMs, OPEN_INTERVAL_MS) else intervalMs
            if (busy || now - lastPass < interval) return
            lastPass = now
            busy = true
            session
        }
        val pixels = try { crop(REGION) } catch (error: Exception) { null }
        val picture = if (pixels != null) try { image() } catch (error: Exception) { null } else null
        if (pixels == null) {
            synchronized(lock) { if (session == started) busy = false }
            return
        }
        try {
            run(Runnable {
                try {
                    val place = REGION.box
                    val reading = Reading(read(pixels).lines.map { it.copy(box = it.box?.placedIn(place)) }).withoutOcrNoise()
                    process(picture, reading, started)
                } catch (error: Exception) {
                    log?.invoke("harita: okunamadı (${error.javaClass.simpleName})")
                } finally {
                    synchronized(lock) { if (session == started) busy = false }
                }
            })
        } catch (error: Exception) {
            synchronized(lock) { if (session == started) busy = false }
        }
    }

    fun reset() {
        val had = synchronized(lock) {
            session++
            busy = false
            val had = items.isNotEmpty()
            items = emptyList()
            key = ""
            waiting = null
            mapUntil = Long.MIN_VALUE / 2
            had
        }
        if (had) onChange?.invoke(emptyList())
    }

    /** Okunmuş kareden harita kartını bulur (sınamalar doğrudan çağırır). Kartın çevirisi bu iş parçacığında yapılır. */
    internal fun process(image: RgbImage?, reading: Reading, started: Int = synchronized(lock) { session }) {
        onScreen?.invoke(reading)
        if (!MapCard.isMapScreen(reading)) {
            if (synchronized(lock) { items.isNotEmpty() }) clear()
            return
        }
        synchronized(lock) {
            if (session != started) return
            mapUntil = clock() + MAP_HOLD_MS
            lastImage = image
        }
        val card = MapCard.find(reading)
        if (card != null) show(card, started) else if (synchronized(lock) { items.isNotEmpty() }) clear()
    }

    private fun clear(forget: Boolean = true) {
        synchronized(lock) {
            if (items.isEmpty()) return
            items = emptyList()
            if (forget) key = ""
        }
        onChange?.invoke(emptyList())
    }

    private fun show(card: MapCard.Found, started: Int) {
        // PS5'in kendi bildirimi zaten Türkçe; kart değildir.
        val all = (listOf(card.title) + card.sentences).joinToString(" ")
        if (all.any { it in "ğışĞİŞ" } || card.sentences.isEmpty()) return
        // PS5'in sağ üstteki bildirimi ve ekranın en üstündeki sekme şeridi görev kartı değildir.
        if (card.title.isEmpty() && card.box.left > 0.6 && card.box.top < 0.32) return
        if (card.box.top < 0.1) return
        val fullText = TextMatch.normalize(all)
        val cardKey = fullText + "@" + (card.box.top * 50).toInt()
        val remembered: List<String>?
        synchronized(lock) {
            // Aynı kartın yarım okuması (alttaki satır okunamadı) ekrandaki tam okumanın yerine geçmez.
            if (card.title.isNotEmpty() && TextMatch.normalize(card.title) == shownCard.first &&
                shownText.startsWith(fullText) && shownText != fullText) return
            if (cardKey == key) return
            key = cardKey
        }
        // İmleç başka yere geçti: eski kartın Türkçesi yeni kartın altında kalmasın. Aynı kart (aynı başlık, aynı yer) biraz
        // farklı okunduysa eski Türkçe yenisi gelene kadar kalır.
        val sameCard = synchronized(lock) {
            card.title.isNotEmpty() && TextMatch.normalize(card.title) == shownCard.first && abs(card.box.top - shownCard.second) < 0.04
        }
        if (!sameCard) clear(forget = false)
        synchronized(lock) {
            remembered = memory[cardKey]
            if (remembered == null && translating) {
                // Çeviri sürüyorsa yeni kart beklemeye alınır (en son seçilen); süren bitince o çevrilir.
                waiting = card
                return
            }
            if (remembered == null) {
                translating = true
                waiting = null
            }
        }
        if (remembered != null) {
            place(card, remembered, cardKey)
            return
        }
        val lines = ArrayList<String>()
        try {
            val locale = Locale.forLanguageTag(targetLanguage)
            if (card.title.isNotEmpty()) {
                val title = piece(card.title.lowercase(Locale.ROOT).split(' ').joinToString(" ") { word ->
                    word.replaceFirstChar { it.titlecase(Locale.ROOT) }
                })
                if (title.isNotEmpty()) lines.add(title.uppercase(locale))
            }
            for (sentence in card.sentences) {
                val text = piece(sentence)
                // Satırlara bölünmez (TV kutunun genişliğine göre böler).
                if (text.isNotEmpty()) lines.add(withMapTerms(PhoneWatcher.withoutEntities(text)))
            }
        } finally {
            synchronized(lock) { translating = false }
        }
        val next: MapCard.Found?
        synchronized(lock) {
            if (session != started) return
            if (lines.isNotEmpty()) memory[cardKey] = lines
            if (memory.size > 200) memory.clear()
            next = waiting
            waiting = null
            if (next != null) key = ""
        }
        if (next != null) {
            // Çeviri sürerken imleç başka karta geçti: bu sonuç gösterilmez, en son kart çevrilir.
            show(next, started)
            return
        }
        synchronized(lock) {
            if (key != cardKey || lines.isEmpty()) return
            if (clock() >= mapUntil) {
                // Harita çeviri sürerken kapandı: kart gösterilmez; yeniden açılınca hafızadan hemen gelir.
                key = ""
                return
            }
        }
        place(card, lines, cardKey)
    }

    private fun piece(text: String): String =
        PhoneWatcher.withoutIcons(runCatching { translate(text) }.getOrNull() ?: "").trim()

    private fun place(card: MapCard.Found, lines: List<String>, cardKey: String) {
        val image = synchronized(lock) { lastImage }
        val item = placement(card, lines, image?.let { MapCard.frame(card.box, it) })
        synchronized(lock) {
            if (key != cardKey) return
            items = listOf(item)
            shownCard = TextMatch.normalize(card.title) to card.box.top
            shownText = TextMatch.normalize((listOf(card.title) + card.sentences).joinToString(" "))
        }
        log?.invoke("harita kartı: ${(card.title.ifEmpty { card.sentences.first() }).take(40)} → ${lines.first().take(40)}")
        onChange?.invoke(listOf(item))
    }

    companion object {
        const val DEFAULT_INTERVAL_MS = 2000L
        /** Harita açıkken en sık bakma aralığı. */
        const val OPEN_INTERVAL_MS = 1500L
        /** Harita görüldükten sonra bu kadar süre açık sayılır. */
        const val MAP_HOLD_MS = 5000L
        /** Okunan bölge: karenin üstten alta çoğu (sekme şeridi ve alt kenar hariç). */
        val REGION = CropRegion(top = 0.03, bottom = 0.95, left = 0.0, right = 1.0)

        /** Oyunun sık geçen terimlerinin yanlış çevirileri düzeltilir ("marked bills" → işaretli banknot, "lockup" → depo). */
        fun withMapTerms(text: String): String {
            val fixes = listOf(
                "KAPALI TUTULMASI" to "DEPOSU", "Kapalı Tutulması" to "Deposu", "kapalı tutulması" to "deposu",
                "işaretli faturaların" to "işaretli banknotların", "işaretli faturalar" to "işaretli banknotlar",
                "işaretli fatura" to "işaretli banknot", "narkotik" to "uyuşturucu", "NARKOTİK" to "UYUŞTURUCU",
                "trafik ışığı papağan balığı" to "stoplight papağan balığı", "kırmızı ışık papağan balığı" to "stoplight papağan balığı",
            )
            return fixes.fold(text) { current, (from, to) -> current.replace(from, to) }
        }

        /** Kartın başlığı bir dükkân ya da mekân adıysa ("RIDEOUT CUSTOMS", "ONE-EYED WILLIE'S AUTO SHOP") çevrilmez. */
        fun isPlaceName(title: String, description: String = ""): Boolean {
            val business = listOf("distributor", "shop", "store", "dive bar", " bar", "restaurant", "dealer", "club", "diner", "garage",
                "convenience", "wholesaler", "boutique", "salon", "motel", "hotel", "bodega")
            val about = description.lowercase(Locale.ROOT)
            if (business.any { about.contains(it) }) return true
            val upper = title.uppercase(Locale.ROOT)
            val words = upper.split(' ').filter { it.isNotEmpty() }
            val places = setOf("CUSTOMS", "AUTO", "SHOP", "BAR", "CLUB", "MOTORS", "GARAGE", "CARE", "SPEEDWAY", "DINER",
                "CAFE", "GRILL", "MOTEL", "HOTEL", "STORE", "MART", "LOUNGE", "SALOON", "TACKLE", "ANCHOR",
                "MARINA", "AMMU-NATION", "BARBER", "TATTOO", "PAWN")
            return words.any { it in places } || (upper.startsWith("THE ") && words.size <= 4)
        }

        /**
         * Kartın Türkçesi oyunun kartı gibi; kartın çerçevesiyle aynı sol kenarda, hemen altında; yer yoksa üstünde; o da
         * yetmezse yazı küçülür. Kutu yazı kadar geniştir (çerçeve yalnız sınırdır).
         */
        fun placement(card: MapCard.Found, translated: List<String>, frameBox: TextBox?): ScreenTranslation.Item {
            val lines = translated.map { withMapTerms(PhoneWatcher.withoutEntities(it)) }.toMutableList()
            if (card.title.isNotEmpty() && lines.isNotEmpty() && isPlaceName(card.title, card.sentences.joinToString(" "))) lines[0] = card.title
            var line = card.lineHeight.coerceIn(0.02, 0.032) * 0.85
            val frame = frameBox ?: TextBox(card.box.left - 0.015, card.box.top - 0.02, card.box.right + 0.015, card.box.bottom + 0.02)
            // Dar yazı tipi: bir harf satır yüksekliğinin yaklaşık %42'si.
            val charWidth = line * 0.42 * 9 / 16
            val longest = (lines.maxOfOrNull { it.length } ?: 10).toDouble()
            val width = minOf(frame.right - frame.left, longest * charWidth + 0.035)
            val rows = lines.withIndex().sumOf { (index, text) ->
                if (index == 0) 1 else maxOf(1, ceil(text.length * charWidth / (width - 0.03)).toInt())
            }
            var height = line * rows * 1.32 + 0.022
            val below = 0.97 - (frame.bottom + 0.012)
            val above = frame.top - 0.012 - 0.02
            var top = frame.bottom + 0.012
            if (height > below) {
                if (height <= above || above > below) {
                    if (height > above) { line *= (above - 0.022) / (height - 0.022); height = above }
                    top = frame.top - 0.012 - height
                } else {
                    line *= (below - 0.022) / (height - 0.022)
                    height = below
                }
            }
            val left = maxOf(frame.left, card.box.left - 0.014)
            return ScreenTranslation.Item((listOf(card.title) + card.sentences).joinToString(" "), lines.joinToString("\n"),
                TextBox(left, top, left + width, top + height), line, card = true)
        }
    }
}
