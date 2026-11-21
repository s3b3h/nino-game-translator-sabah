// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Nino: oyunu ekrandaki kendine özgü yazılardan, sunucuya sormadan tanır. PS5'in keşif yanıtı çalışan oyunu çoğu zaman
/// bildirmiyor (21 Kasım 2026: PS5 14.23, GTA 6 açıkken `running-app-name` hiç yok); ekrandan tanıma da yalnız ortak havuz
/// açıkken ve dakikada bir deneniyor. Bu yüzden yeni kurulumda oyun "Bilinmiyor" kalıyor, GTA 6'ya özgü telefon ve harita
/// çevirisi açılmıyordu. Android (GameMarkers.kt) ve Windows (GameMarkers.cs) ile aynı kurallar.
public enum GameMarkers {
    /// Listede ve ekranda görünen ad; `GameName.key` ile "Grand Theft Auto VI" ile aynıdır, havuzda da öyle eşleşir.
    public static let gta6 = "GTA 6"

    /// Karenin (ya da büyük bir kısmının) okumasında GTA 6'ya özgü yazı varsa oyunun adı, yoksa nil.
    /// - Harita: sağ alttaki tuş listesi ("RECENTER", "2D VIEW", "ADD MARKER"…; bkz. `MapCard.isMapScreen`).
    /// - Duraklatma menüsünün sekme şeridi: "JASON & LUCIA" (iki kahramanın adı birlikte) ya da şeritteki "BRIEF" ve
    ///   "PROGRESS" birlikte.
    /// - Oyun içi telefon: ana ekrandaki "WhatUp" uygulaması.
    public static func game(in reading: Reading) -> String? {
        if MapCard.isMapScreen(reading) { return gta6 }
        let lines = reading.lines.map { TextMatch.normalize(MenuBlock.clean($0.text)) }
        let words = Set(lines.flatMap { $0.split(separator: " ").map(String.init) })
        if lines.contains(where: { $0.contains("jason") && $0.contains("lucia") }) { return gta6 }
        if lines.contains("brief") && lines.contains("progress") && (words.contains("jason") || words.contains("lucia") || lines.contains("map")) {
            return gta6
        }
        if lines.contains("whatup") { return gta6 }
        return nil
    }
}
