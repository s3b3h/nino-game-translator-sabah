// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// Nino: altyazının seçilen yazı tipi (Mac ve iPhone ortak). Dosyalar tv-webos/fonts'tan paketin "fonts" klasörüne gelir.
/// Arapça, Tayca, Hintçe gibi bu yazı tiplerinde olmayan harfler sistemin yazı tipiyle kendiliğinden çizilir.
extension Font {
    static func subtitle(_ font: SubtitleFont, size: CGFloat, weight: Font.Weight) -> Font {
        SubtitleFontRegistry.registerBundledFonts()
        let bold = weight == .bold || weight == .heavy || weight == .black
        // Sabit boy: .system(size:) gibi Dinamik Yazı ayarıyla büyüyüp küçülmez.
        guard let name = font.postScriptName(bold: bold) else { return .system(size: size, weight: weight) }
        return .custom(name, fixedSize: size)
    }
}

extension SubtitleFont {
    /// Seçicide görünen ad.
    var title: LocalizedStringKey {
        switch self {
        case .condensed: "Action (GTA style)"
        case .modern: "Modern"
        case .rounded: "Rounded"
        case .system: "System"
        }
    }

    /// Seçicideki sıra: varsayılan (Aksiyon) başta.
    static let pickerOrder: [SubtitleFont] = [.condensed, .modern, .rounded, .system]
}

extension Text {
    /// Altyazı yazısını seçilen yazı tipiyle (ve TV sayfasındaki harf aralığıyla) çizer.
    func subtitleFont(_ font: SubtitleFont, size: CGFloat, weight: Font.Weight) -> Text {
        self.font(.subtitle(font, size: size, weight: weight)).tracking(size * CGFloat(font.tracking))
    }
}
