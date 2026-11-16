// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// Nino: Arapça çeviri sağdan sola gösterilir. Yön yazının kendisinden seçilir (Arap harfi varsa), arayüz dilinden değil:
/// satır Latin harfli konuşmacı adıyla başlasa da ("ARTHUR: …") sağdan başlar (bkz. `TargetLanguage.displayText`).
struct SubtitleDirection: ViewModifier {
    let text: String
    /// Yazı kendi satırını kaplasın (sola yaslı yerlerde Arapça sağa yaslansın).
    var fill = false
    @Environment(\.layoutDirection) private var current

    func body(content: Content) -> some View {
        let arabic = TargetLanguage.containsArabic(text)
        content
            .frame(maxWidth: fill && arabic ? .infinity : nil, alignment: .leading)
            .environment(\.layoutDirection, arabic ? .rightToLeft : current)
    }
}

extension View {
    /// Nino: Arapça arayüzde aynalanmaması gereken görünümler (PS5 görüntüsü ve çerçevesi, sürüklenen düğme, sahne,
    /// altyazı penceresinin kenar tutamakları) soldan sağa kalır. İçlerindeki Arapça altyazı yine sağdan sola dizilir.
    func fixedLeftToRight() -> some View {
        environment(\.layoutDirection, .leftToRight)
    }

    func subtitleDirection(_ text: String, fill: Bool = false) -> some View {
        modifier(SubtitleDirection(text: text, fill: fill))
    }
}
