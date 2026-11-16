// SPDX-License-Identifier: AGPL-3.0-only
// Nino: telefon altyazı ekranındaki satırın ne kadar kalacağı (TV ve Mac'teki kuralla aynı süre).
package com.couchsubs.mobile.core

/** Telefon ekranında gösterilen satırın görünme süresi. */
object PhoneLine {
    /** Bilgisayarın ya da okuma hattının bildirdiği süre en az bu kadardır. */
    const val MIN_VISIBLE_MS = 1_200L
    /** Süre bildirilmezse yazının uzunluğundan hesaplanır, en çok bu kadar. */
    const val MAX_READING_MS = 8_000L

    /**
     * Satır bu süre sonunda kendiliğinden kalkar; oyun altyazıyı kaldırdığında "temizle" gelmese de telefonda eski satır
     * asılı kalmaz. Yeni satır gelirse süre baştan başlar.
     */
    fun visibleMs(text: String, durationMs: Int): Long =
        if (durationMs > 0) maxOf(MIN_VISIBLE_MS, durationMs.toLong())
        else minOf(MAX_READING_MS, 2_000L + text.length * 60L)
}
