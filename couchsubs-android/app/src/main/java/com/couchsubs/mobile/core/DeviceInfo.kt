// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "Cihaz bilgileri". Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-19.
package com.couchsubs.mobile.core

/**
 * Kullanıcının ne kullandığının kısa özeti: uygulama sürümü, cihaz modeli, işletim sistemi, TV ve konsol.
 * Ayarlar › Sistem sağlığı'nda gösterilir ve Sorun Bildir ile Nino'ya Sor bildirimlerine eklenir (sunucuda `device`
 * alanı); biri hata bildirdiğinde hangi cihazlarla denediği sorulmadan görülür.
 * Kişiyi tanıtan hiçbir şey içermez: cihazın adı ("Ali'nin telefonu"), seri numarası, IP adresi, hesap adı yoktur.
 * Bu dosya Android'e bağlı değildir (JVM testi: DeviceInfoTest); telefonun değerlerini account/ThisDevice.kt okur.
 * Mac/iPhone: DeviceInfo.swift, Windows: CouchSubs.Core/DeviceInfo.cs (aynı satır adları ve özet biçimi).
 */
object DeviceInfo {
    /** Sunucunun sakladığı en çok uzunluk (nino-pool/src/reports.js ile aynı). */
    const val MAX_LENGTH = 600

    /** [id]: satırın sabit adı ("app", "device", "system", "tv", "console", "status"); çevrilmez, sunucuya bu gider. */
    data class Row(val id: String, val value: String)

    /** Cihazın üreticisi ve modeli: "samsung SM-S918B", "Google Pixel 8" (Build.MANUFACTURER + Build.MODEL). */
    fun model(manufacturer: String?, model: String?): String =
        listOf(manufacturer, model).mapNotNull { it?.trim()?.takeIf(String::isNotEmpty) }.joinToString(" ")

    /** İşletim sistemi ve sürümü: "Android 14 (API 34)". */
    fun system(release: String?, sdk: Int): String =
        "Android " + listOfNotNull(release?.trim()?.takeIf(String::isNotEmpty), "(API $sdk)").joinToString(" ")

    /** TV satırı: marka ve TV uygulamasının sürümü ("Samsung · TV uygulaması 3.4.0"); marka bilinmiyorsa null. */
    fun tv(brand: String?, appVersion: String?): String? {
        val name = brand?.trim()?.takeIf(String::isNotEmpty) ?: return null
        val version = appVersion?.trim()?.takeIf(String::isNotEmpty)
        return if (version == null) name else "$name · TV uygulaması $version"
    }

    /** Konsol satırı: konsol ve bağlantı yolu ("PS5 · Remote Play"); ikisi de bilinmiyorsa null. */
    fun console(kind: String?, path: String?): String? =
        listOf(kind, path).mapNotNull { it?.trim()?.takeIf(String::isNotEmpty) }.joinToString(" · ").takeIf(String::isNotEmpty)

    /**
     * Satırlar, sırayla. Boş ya da bilinmeyen değer satır olmaz.
     * [app]: uygulama sürümü ("3.4.0 (19)"). [tv]: TV'nin markası ve TV uygulamasının sürümü ("Samsung · TV uygulaması
     * 3.4.0"); yoksa null. [console]: konsol ve bağlantı yolu ("PS5 · Remote Play"); bilinmiyorsa null. [status]: şu anki
     * durum ya da son hata; yoksa null.
     */
    fun rows(app: String, model: String, system: String, tv: String? = null, console: String? = null, status: String? = null): List<Row> =
        listOf(Row("app", app), Row("device", model), Row("system", system), Row("tv", tv.orEmpty()),
            Row("console", console.orEmpty()), Row("status", status.orEmpty()))
            .map { Row(it.id, clean(it.value)) }
            .filter { it.value.isNotEmpty() }

    /** Sunucuya giden tek satır: "app: 3.4.0 (19) | device: Google Pixel 8 | system: Android 14 (API 34) | tv: …". */
    fun summary(rows: List<Row>): String = rows.joinToString(" | ") { "${it.id}: ${it.value}" }.take(MAX_LENGTH)

    /** Satır sonları ve ayırıcı çizgi değerin içinde kalmaz (özet tek satırdır). */
    internal fun clean(value: String): String = value.lines().joinToString(" ").replace("|", "/").trim()

    private val address = Regex("\\b\\d{1,3}(?:\\.\\d{1,3}){3}\\b(?::\\d{1,5})?")

    /**
     * Durum metninden adres ve adları çıkarır: "PS5 192.168.1.20 adresinde bulunamadı" gibi bir durum, IP adresini ya da
     * [names] içindeki cihaz adlarını (konsolun, TV'nin adı ve adresi) taşıyabilir. Bunlar özete girmez.
     */
    fun withoutAddresses(text: String, names: List<String?> = emptyList()): String {
        var result = text
        for (name in names.mapNotNull { it?.trim() }.filter { it.length >= 3 }.sortedByDescending { it.length })
            result = result.replace(name, "…", ignoreCase = true)
        return address.replace(result, "…")
    }
}
