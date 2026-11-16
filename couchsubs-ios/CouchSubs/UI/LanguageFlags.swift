// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// Nino: çeviri dili için bayraklar (Mac'teki karşılama ekranıyla aynı): seçili olan tam renkli ve ince halkalı, öteki
/// soluk. `showsNames` ile (Ayarlar) bayrağın yanında dilin kendi adı da yazar.
struct LanguageFlags: View {
    @Binding var selection: String
    var showsNames = false

    private static let flags = ["tr": "🇹🇷", "ar": "🇸🇦"]

    var body: some View {
        HStack(spacing: showsNames ? Mobile.Space.inline : 4) {
            ForEach(TargetLanguage.choices, id: \.code) { choice in
                let selected = selection == choice.code
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = choice.code }
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: Self.flags[choice.code] ?? "").font(.system(size: 20))
                        if showsNames {
                            Text(verbatim: choice.name).font(Mobile.TypeScale.headline.weight(selected ? .semibold : .regular))
                        }
                    }
                    .padding(.horizontal, showsNames ? 14 : 0)
                    .frame(minWidth: 40, minHeight: 40)
                    .background(Capsule().fill(Mobile.Palette.accent.opacity(selected ? 0.10 : 0)))
                    .overlay(Capsule().strokeBorder(Mobile.Palette.accent.opacity(selected ? 0.8 : 0), lineWidth: 1.5))
                    .opacity(selected ? 1 : 0.45)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: choice.name))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
