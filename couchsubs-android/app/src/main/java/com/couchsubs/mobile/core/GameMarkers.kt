// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Nino: oyunu ekrandaki kendine özgü yazılardan, sunucuya sormadan tanır. PS5'in keşif yanıtı çalışan oyunu çoğu zaman
 * bildirmiyor (21 Kasım 2026: PS5 14.23, GTA 6 açıkken `running-app-name` hiç yok); yeni kurulumda oyun "Bilinmiyor"
 * kalıyor, GTA 6'ya özgü telefon ve harita çevirisi açılmıyordu. Mac/iPhone (GameMarkers.swift) ve Windows ile aynı kurallar.
 */
object GameMarkers {
    /** Listede ve ekranda görünen ad; [GameName.key] ile "Grand Theft Auto VI" ile aynıdır. */
    const val GTA6 = "GTA 6"

    /**
     * Okumada GTA 6'ya özgü yazı varsa oyunun adı, yoksa null: harita tuş listesi ([MapCard.isMapScreen]), duraklatma
     * menüsünün sekme şeridi ("JASON & LUCIA" ya da "BRIEF" ve "PROGRESS" birlikte) ya da telefonun "WhatUp" uygulaması.
     */
    fun game(reading: Reading): String? {
        if (MapCard.isMapScreen(reading)) return GTA6
        val lines = reading.lines.map { TextMatch.normalize(MapCard.cleanMenuText(it.text)) }
        val words = lines.flatMap { it.split(' ') }.toSet()
        if (lines.any { it.contains("jason") && it.contains("lucia") }) return GTA6
        if ("brief" in lines && "progress" in lines && ("jason" in words || "lucia" in words || "map" in lines)) return GTA6
        if ("whatup" in lines) return GTA6
        return null
    }
}
