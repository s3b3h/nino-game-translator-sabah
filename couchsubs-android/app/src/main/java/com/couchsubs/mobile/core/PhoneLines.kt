// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Nino: telefon açıkken (ya da az önce görüldüyse) altyazı okumasından oyundaki telefona ait satırlar atılır (Mac:
 * SubtitlePipeline.process, Windows: SubtitlePipeline.WithoutPhoneLines ile aynı sıra): telefonun ekranındaki satırlar,
 * açık zeminde koyu yazı (mesaj balonu), telefon uygulamasına özgü yazılar, altyazı çizgisinin üstündeki satırlar ve
 * telefonda az önce görülen mesajlar. Uygulama onları telefonun yanında gösterir (bkz. [PhoneWatcher]).
 */
object PhoneLines {
    /** Telefon görüldükten sonra bu kadar süre aynı yerde sayılır (ekran kayarak değişirken bir iki karede bulunamıyor). */
    const val PHONE_HOLD_MS = 5000L
    /** Telefon açıkken altyazı bu çizginin altındadır (karenin oranı). */
    const val FLOOR = 0.8

    /**
     * Telefon kutusu altyazı okumasında maske olarak kullanılırken alt kenarı ekranın gerçek alt kenarına kadar uzatılır
     * (çerçeveli son mesajın olduğu karede ekran kısa bulunuyor), ama altyazının başladığı yere (0,84) inmez.
     */
    fun mask(phone: TextBox): TextBox = phone.copy(bottom = maxOf(phone.bottom, minOf(phone.bottom + 0.15, 0.84)))

    /**
     * [raw]: okunan alanın satırları (kutular alana göre); [place]: okunan alanın karedeki yeri; [phone]: bulunan (ya da az
     * önce görülen) telefon ekranı; [wantsPhone]: havuz öncelikli oyun (GTA 6); [areaColor]: okunan alanın renk
     * örnekleyicisi (alana göre 0–1; yoksa null); [phoneTexts]: telefonda az önce görülen mesajlar; [onPhoneUI]: telefon
     * uygulamasına özgü yazılar görüldü (karedeki yerleri).
     */
    fun without(
        raw: Reading, place: TextBox, phone: TextBox?, wantsPhone: Boolean,
        areaColor: ((Double, Double) -> PhonePanel.Rgb?)?, phoneTexts: List<String>, onPhoneUI: ((List<TextBox>) -> Unit)? = null,
    ): Reading {
        if (!wantsPhone && phone == null && phoneTexts.isEmpty()) return raw
        fun center(box: TextBox): Pair<Double, Double> =
            (place.left + (box.left + box.right) / 2 * (place.right - place.left)) to
                (place.top + (box.top + box.bottom) / 2 * (place.bottom - place.top))
        var lines = raw.lines
        if (phone != null) {
            // Telefon açık; ekranındaki yazılar (mesajlar, kişi listesi) altyazı değildir.
            lines = lines.filter { line ->
                val box = line.box ?: return@filter true
                val (x, y) = center(box)
                !(x > phone.left - 0.02 && x < phone.right + 0.02 && y > phone.top - 0.02 && y < phone.bottom + 0.02)
            }
        }
        if (wantsPhone && areaColor != null && lines.isNotEmpty()) {
            // GTA'nın altyazısı koyu sahnede beyaz yazıdır; açık zeminde koyu yazı telefonun ekranıdır (mesaj balonu).
            lines = lines.filter { line -> line.box?.let { !PhoneThread.isDarkOnLight(it, areaColor) } ?: true }
        }
        if (wantsPhone) {
            // Telefon uygulamasına özgü yazı ("Change Destination", "Book Ryde ($82)") telefon bulunamasa da altyazı değildir.
            val phoneUI = lines.filter { PhoneThread.isPhoneUI(it.text) }
            if (phoneUI.isNotEmpty()) {
                onPhoneUI?.invoke(phoneUI.mapNotNull { it.box?.placedIn(place) })
                lines = lines.filter { !PhoneThread.isPhoneUI(it.text) }
            }
        }
        val texts = phoneTexts.map { TextMatch.normalize(it) }.filter { it.isNotEmpty() }
        if (phone != null || texts.isNotEmpty()) {
            // Telefon açıkken altyazı çizgisinin üstündeki hiçbir yazı altyazı değildir.
            lines = lines.filter { line -> line.box?.let { center(it).second >= FLOOR } ?: true }
        }
        if (texts.isNotEmpty()) {
            lines = lines.filter { line ->
                val key = TextMatch.normalize(line.text)
                key.split(' ').count { it.isNotEmpty() } < 3 || texts.none { it.contains(key) }
            }
        }
        return if (lines.size == raw.lines.size) raw else Reading(lines)
    }
}
