// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// Nino: çeviri dili seçici: seçili dilin bayrağı (Ayarlar'da `showsNames` ile adı da) ve aşağı ok; basınca bütün diller
/// bayraklarıyla açılır, Türkçe en üstte. 11 bayrağı yan yana dizmek telefona sığmazdı.
struct LanguageFlags: View {
    @Binding var selection: String
    var showsNames = false

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { selection }, set: { code in
                withAnimation(.easeOut(duration: 0.2)) { selection = code }
            })) {
                ForEach(TargetLanguage.choices, id: \.code) { choice in
                    Text(verbatim: "\(TargetLanguage.flag(choice.code))  \(choice.name)").tag(choice.code)
                }
            } label: { EmptyView() }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: TargetLanguage.flag(selection)).font(.system(size: 20))
                if showsNames {
                    Text(verbatim: TargetLanguage.nativeName(selection)).font(Mobile.TypeScale.headline.weight(.semibold))
                }
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).opacity(0.7)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Capsule().fill(Mobile.Palette.accent.opacity(0.10)))
            .overlay(Capsule().strokeBorder(Mobile.Palette.accent.opacity(0.8), lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: TargetLanguage.nativeName(selection)))
    }
}
