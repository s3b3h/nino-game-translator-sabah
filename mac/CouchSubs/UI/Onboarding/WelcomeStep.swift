// SPDX-License-Identifier: AGPL-3.0-only
// Nino: hoş geldin ekranı yeniden tasarlandı (2026-11-14).

import CouchSubsCore
import SwiftUI

struct WelcomeStep: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StepLayout(title: "Welcome to Nino",
                   // Nino: Arapça seçilince karşılama da "Arapça çevirisini" der.
                   message: model.settings.targetLanguage == "ar"
                       ? "Nino reads the English subtitles of your PS5 games and shows an Arabic translation on your TV, on top of the game. You keep playing on the TV with your own controller."
                       : "Nino reads the English subtitles of your PS5 games and shows a Turkish translation on your TV, on top of the game. You keep playing on the TV with your own controller.") {
            VStack(alignment: .leading, spacing: Theme.space("m")) {
                // Nino: süre başlık satırının sağında; altta iki kısa yol yan yana (PS5 eşleştirmesi ve ikinci hesap
                // gerekmeyen yollar: Remote Play penceresi ve yakalama kartı). İkisi de kaydırmadan görünür.
                HStack(spacing: Theme.space("m")) {
                    Text("What you need")
                        .font(.csCallout)
                        .foregroundStyle(Color.csSecondary)
                        .textCase(.uppercase)
                    Spacer(minLength: Theme.space("s"))
                    Label("Setup takes about 5 minutes.", systemImage: "clock")
                        .font(.csCallout)
                        .foregroundStyle(Color.csSecondary)
                }
                .padding(.horizontal, Theme.space("xs"))
                HStack(spacing: Theme.space("m")) {
                    RequirementTile(symbol: "gamecontroller.fill", title: "PS5", detail: "On the same Wi-Fi as this Mac")
                    RequirementTile(symbol: "tv.fill", title: "Smart TV",
                                    detail: "Android TV, Google TV, LG or Samsung")
                    RequirementTile(symbol: "person.crop.circle.badge.plus", title: "Second PSN account",
                                    detail: "Free, takes 2 minutes")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.space("l")) { shortcuts }
                    VStack(alignment: .leading, spacing: Theme.space("s")) { shortcuts }
                }
                .padding(.top, Theme.space("s"))
                .padding(.horizontal, Theme.space("xs"))
            }
        }
        // Nino: çeviri dili sağ üstte yalnız bayraklarla seçilir (sonra Ayarlar > Dil'den de değişir). Arapça arayüzde de
        // sağda kalır.
        .overlay(alignment: .top) {
            HStack { Spacer(); TranslationLanguageFlags(selection: $model.settings.targetLanguage) }
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    /// PS5 eşleştirmesi ve ikinci hesap gerekmeyen iki yol.
    @ViewBuilder private var shortcuts: some View {
        Button {
            model.useGameWindowSetup()
        } label: {
            Label("I play on this computer with PS Remote Play", systemImage: "macwindow")
                .font(.csCallout.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.csAccentText)
        .help(Text("No TV or second account needed. Nino reads the Remote Play window and shows the translation on top of the game."))
        Spacer(minLength: 0)
        Button {
            model.useCaptureCardSetup()
        } label: {
            Label("I have a capture card", systemImage: "cable.connector")
                .font(.csCallout.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.csAccentText)
        .help(Text("No second account needed. Nino reads the game from the card and shows it with the translation on top."))
    }
}

/// Nino: çeviri dili için yalnız bayraklar: seçili olan tam renkli ve ince mavi halkalı, öteki soluk. Üzerine gelince dilin
/// adı görünür.
private struct TranslationLanguageFlags: View {
    @Binding var selection: String

    private static let flags = ["tr": "🇹🇷", "ar": "🇸🇦"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TargetLanguage.choices, id: \.code) { choice in
                let selected = selection == choice.code
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = choice.code }
                } label: {
                    Text(verbatim: Self.flags[choice.code] ?? choice.name)
                        .font(.system(size: 18))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(selected ? 0.10 : 0)))
                        .overlay(Circle().strokeBorder(Color.csAccent.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
                        .opacity(selected ? 1 : 0.45)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: choice.name))
                .accessibilityLabel(Text(verbatim: choice.name))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Gereksinim karosu: büyük mavi simge, başlık ve tek satırlık açıklama; cam yüzey üzerinde.
private struct RequirementTile: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("m")) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.csAccentHi, Color(red: 0.0, green: 0.19, blue: 0.52)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Color.csAccent.opacity(0.4), radius: 10, y: 4)
                icon
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.csHeadline)
                Text(detail)
                    .font(.csCallout)
                    .foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .tile()
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05)) { appeared = true } }
    }

    private var icon: some View { Image(systemName: symbol) }
}
