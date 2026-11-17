// SPDX-License-Identifier: AGPL-3.0-only
// Nino: hoş geldin ekranı yeniden tasarlandı (2026-11-14).

import CouchSubsCore
import SwiftUI

struct WelcomeStep: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            switch model.welcomeConsole {
            case nil: ConsolePicker()
            case .ps5?: ps5Welcome
            case .xbox?: xboxWelcome
            }
        }
        .id(model.welcomeConsole)
        .transition(.opacity)
        // Nino: çeviri dili sağ üstte yalnız bayraklarla seçilir (sonra Ayarlar > Dil'den de değişir). Arapça arayüzde de
        // sağda kalır.
        .overlay(alignment: .top) {
            HStack { Spacer(); TranslationLanguageFlags(selection: $model.settings.targetLanguage) }
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    private var arabic: Bool { model.settings.targetLanguage == "ar" }
    private var turkish: Bool { TargetLanguage.isTurkish(model.settings.targetLanguage) }

    private var ps5Welcome: some View {
        StepLayout(title: "Welcome to Nino",
                   // Nino: Arapça seçilince karşılama da "Arapça çevirisini" der.
                   message: arabic
                       ? "Nino reads the English subtitles of your PS5 games and shows an Arabic translation on your TV, on top of the game. You keep playing on the TV with your own controller."
                       : !turkish
                       ? "Nino reads the English subtitles of your PS5 games and shows them in your language on your TV, on top of the game. You keep playing on the TV with your own controller."
                       : "Nino reads the English subtitles of your PS5 games and shows a Turkish translation on your TV, on top of the game. You keep playing on the TV with your own controller.") {
            requirements {
                RequirementTile(symbol: "gamecontroller.fill", title: "PS5", detail: "On the same Wi-Fi as this Mac")
                RequirementTile(symbol: "tv.fill", title: "Smart TV",
                                detail: "Android TV, Google TV, LG or Samsung")
                RequirementTile(symbol: "person.crop.circle.badge.plus", title: "Second PSN account",
                                detail: "Free, takes 2 minutes")
            } shortcuts: {
                // Nino: PS5 eşleştirmesi ve ikinci hesap gerekmeyen iki yol.
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
                captureCardButton
            }
        }
    }

    /// Nino: Xbox seçilince karşılama yerine iş gören sayfa: "Xbox'ı Bağla" listesi. Görüntü Greenlight ile gelir
    /// (1080p, tarayıcı süsü yok; altyazı en doğru böyle okunur). Nino her adımı kendisi denetler ve yeşile çevirir.
    /// Tarayıcı ve yakalama kartı yedek yollardır. Devam, TV adımına geçer (`AppModel.advance`).
    private var xboxWelcome: some View {
        StepLayout(title: "Connect Your Xbox",
                   message: "Nino checks each step by itself and moves on. You only set this up once.") {
            VStack(spacing: Theme.space("m")) {
                XboxConnectChecklist()
                HStack(spacing: Theme.space("l")) {
                    Button {
                        if let url = URL(string: "https://www.xbox.com/play/consoles") { openURL(url) }
                    } label: {
                        Label("Try in the browser without installing", systemImage: "safari")
                            .font(.csCallout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.csAccentText)
                    captureCardButton
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .environment(\.onboardingSymbol, "gamecontroller.fill")
    }

    private var captureCardButton: some View {
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

    private func requirements<Tiles: View, Links: View>(@ViewBuilder _ tiles: () -> Tiles,
                                                        @ViewBuilder shortcuts: () -> Links) -> some View {
        VStack(alignment: .leading, spacing: Theme.space("m")) {
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
            HStack(spacing: Theme.space("m")) { tiles() }
            HStack(spacing: Theme.space("l")) { shortcuts() }
                .padding(.top, Theme.space("s"))
                .padding(.horizontal, Theme.space("xs"))
        }
    }
}

/// Nino: kurulumun ilk ekranı: "Hangi konsolda oynuyorsunuz?" Kart görselleri kullanıcının PS5 ve Xbox One S'li tek
/// görselinin ikiye bölünmüş hâli (`Assets/ConsolePS5`, `Assets/ConsoleXbox`, saydam zemin). "Capture Card'ım var"
/// konsol seçildikten sonraki karşılamadadır.
/// Not: PS5 ve Xbox çizimleri Sony'nin ve Microsoft'un tasarımlarına benzer; mağazaya gönderilmeden önce markasız bir çizimle değiştirilmelidir
/// (bkz. CLAUDE.md, Marka ve `LivingRoomScene`).
private struct ConsolePicker: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StepLayout(title: "Which console do you play on?",
                   message: "Nino works with both. You can change it later in Settings.") {
            VStack(spacing: Theme.space("l")) {
                HStack(spacing: Theme.space("m")) {
                    ConsoleCard(title: "PS5", detail: "Remote Play over Wi-Fi with a second PSN account") {
                        Image("ConsolePS5").resizable().scaledToFit()
                    } action: { model.chooseWelcomeConsole(.ps5) }
                    ConsoleCard(title: "Xbox", detail: "Xbox Series X|S or Xbox One; streamed to this Mac") {
                        Image("ConsoleXbox").resizable().scaledToFit().padding(.horizontal, Theme.space("m"))
                    } action: { model.chooseWelcomeConsole(.xbox) }
                }
            }
        }
    }
}

/// Nino: Xbox adım kartı: simge, numara, kısa başlık ve yol (PS5 eşleştirme kartlarıyla aynı görünüm).
private struct XboxStepCard: View {
    let number: Int
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("s")) {
            HStack {
                GradientIcon(symbol: symbol, size: 36)
                Spacer()
                Text(verbatim: "\(number)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.csSecondary.opacity(0.6))
            }
            Text(title).font(.csHeadline).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.csCallout).foregroundStyle(Color.csSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .tile(padding: Theme.space("m"))
    }
}

/// Büyük seçim kartı: üstte salon sahnesinden konsol görseli, altta ad ve tek satırlık açıklama.
private struct ConsoleCard<Art: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder var art: Art
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.space("s")) {
                // Konsollar sehpadaymış gibi alttan hizalı (PS5 dik ve uzun, Xbox yatık).
                art
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .frame(height: 180)
                    .padding(.top, Theme.space("s"))
                HStack {
                    Text(title).font(.csHeadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.csSecondary)
                        .flipsForRightToLeftLayoutDirection(true)
                }
                Text(detail)
                    .font(.csCallout)
                    .foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
            .tile()
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.csAccent.opacity(hovering ? 0.9 : 0), lineWidth: 1.5))
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(.easeOut(duration: 0.15)) { hovering = over } }
    }
}

/// Nino: çeviri dili için yalnız bayraklar: seçili olan tam renkli ve ince mavi halkalı, öteki soluk. Üzerine gelince dilin
/// adı görünür.
private struct TranslationLanguageFlags: View {
    @Binding var selection: String

    /// Nino: sağ üstte seçili dilin bayrağı; basınca bayraklı dil listesi açılır (Türkçe en başta).
    var body: some View {
        Menu {
            ForEach(TargetLanguage.choices, id: \.code) { choice in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = choice.code }
                } label: {
                    Text(verbatim: TargetLanguage.flag(choice.code) + "  " + choice.name
                         + (selection == choice.code ? "  ✓" : ""))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: TargetLanguage.flag(selection)).font(.system(size: 18))
                Text(verbatim: TargetLanguage.nativeName(selection)).font(.csCallout.weight(.semibold))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.csSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.csAccent.opacity(0.6), lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Translation language"))
        .accessibilityLabel(Text("Translation language"))
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
