// SPDX-License-Identifier: AGPL-3.0-only
// Ana ekran, çeviri sürüyor ekranı, yatay altyazı ekranı ve kullanım turu (tuvaldeki Telefon · 7–10).

import CouchSubsCore
import RemotePlay
import SwiftUI
import Translation
import UIKit

/// Ana ekrandan açılan sayfalar.
enum Route: Hashable {
    case settings, profile, packs, target, ps5, psn, about, history
    /// Konsol türü (PlayStation ya da Xbox Beta).
    case platform
    /// TV uygulamasını bu telefondan kurmak; `tvUpdate` ana ekrandaki güncellemeyi kendiliğinden başlatır.
    case tvInstall, tvUpdate
}

/// Turun vurguladığı öğeler.
enum TourTarget: Int, CaseIterable {
    case start, target, packs, profile
}

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func tourTarget(_ target: TourTarget) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
    }
}

/// Ana ekranın ortak üst satırı: logo, geçmiş, ayarlar, profil.
struct HomeHeader: View {
    @Binding var path: [Route]

    var body: some View {
        HStack(spacing: Mobile.Space.gap) {
            LogoView(size: 36)
            Spacer()
            IconButton(symbol: "clock.arrow.circlepath", label: "History") { path.append(.history) }
            IconButton(symbol: "gearshape", label: "Settings") { path.append(.settings) }
            AvatarButton(initials: "") { path.append(.profile) }
                .tourTarget(.profile)
        }
        .frame(height: Mobile.Control.icon)
    }
}

// MARK: - 8 Ana ekran

/// Apple çevirisinin dil paketi henüz indirilmedi: "İndir" sistemin indirme penceresini açar.
@available(iOS 26, *)
struct LanguagePackTile: View {
    @EnvironmentObject private var model: PhoneModel
    @State private var download: TranslationSession.Configuration?

    var body: some View {
        Tile {
            if TargetLanguage.isTurkish(model.settings.targetLanguage) {
                Text("The English–Turkish language pack is not downloaded yet.").font(Mobile.TypeScale.headline)
            } else if model.settings.targetLanguage.hasPrefix("ar") {
                Text("The English–Arabic language pack is not downloaded yet.").font(Mobile.TypeScale.headline)
            } else {
                // Nino: öbür diller ("İngilizce–हिन्दी").
                let english = Locale.current.localizedString(forLanguageCode: "en") ?? "English"
                Text("The \(english)–\(TargetLanguage.nativeName(model.settings.targetLanguage)) language pack is not downloaded yet.")
                    .font(Mobile.TypeScale.headline)
            }
            Button("Download") {
                download = TranslationSession.Configuration(source: Locale.Language(identifier: model.settings.sourceLanguage),
                                                            target: Locale.Language(identifier: model.settings.targetLanguage))
            }
            .buttonStyle(.mobileSecondary)
        }
        .translationTask(download) { session in
            try? await session.prepareTranslation()
            await model.refreshTranslatorStatus()
        }
    }
}

// Ana ekran (çalışırken de aynı ekran): HomePremium.swift.

// MARK: - 10 Yatay altyazı ekranı

struct SubtitleScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var savedBrightness: CGFloat?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            VStack(spacing: Mobile.Space.inline) {
                // Nino: PS5'siz demoda örnek satır.
                if model.isDemo, let demo = model.demoLine {
                    Text(verbatim: TargetLanguage.displayText(demo.translation))
                        .font(Mobile.TypeScale.subtitle(landscape: true, scale: scale, font: model.settings.style.font))
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .subtitleDirection(demo.translation)
                }
                ForEach(Array(model.phoneLines.enumerated()), id: \.element.id) { index, line in
                    // Uzun çeviri en çok 3 satıra dengeli bölünür; sığmazsa yazı biraz küçülür (bkz. SubtitleWrap).
                    let wrapped = line.wrapped
                    Text(verbatim: TargetLanguage.displayText(wrapped.text))
                        .font(Mobile.TypeScale.subtitle(landscape: true, scale: scale * CGFloat(wrapped.scale), font: model.settings.style.font))
                        // Önceki satır soldurulmaz, sabit gri olur (#7C7A76).
                        .foregroundStyle(index < model.phoneLines.count - 1 ? Color(hex: 0x7C7A76) : textColor)
                        .opacity(line.fading ? 0.4 : 1)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .subtitleDirection(line.text)
                }
            }
            .padding(.horizontal, Mobile.Space.screen)
            .padding(.bottom, Mobile.Space.screen * 2)
            // Ek alanların (görev, telefon, bildirim) çevirisi oyundaki yerinde küçük kutuda (TV'deki gibi).
            GeometryReader { proxy in
                ForEach(model.phoneRegions) { region in
                    let box = region.box ?? TextBox(left: 0.6, top: 0.05, right: 0.95, bottom: 0.2)
                    Text(verbatim: region.text)
                        .font(Mobile.TypeScale.caption)
                        .foregroundStyle(Mobile.Palette.text)
                        .padding(6)
                        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: max(120, proxy.size.width * (box.right - box.left)), alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .position(x: proxy.size.width * (box.left + box.right) / 2, y: proxy.size.height * box.top + 24)
                }
            }
            .allowsHitTesting(false)
            // "Ekranı çevir" sonuçları: her çeviri kendi yazısının yerinde ve aynı boyda (TV'deki gibi).
            GeometryReader { proxy in
                ForEach(Array(model.screenItems.enumerated()), id: \.offset) { _, item in
                    let box = item.box
                    let width = max(60, proxy.size.width * (box.right - box.left))
                    let size = max(10, min(28, proxy.size.height * item.lineHeight * 0.8))
                    Text(verbatim: item.translation)
                        .font(.system(size: size, weight: .semibold))
                        .foregroundStyle(Mobile.Palette.text)
                        .multilineTextAlignment(.leading)
                        .padding(4)
                        .frame(width: width, alignment: .leading)
                        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize(horizontal: false, vertical: true)
                        .position(x: proxy.size.width * box.left + width / 2,
                                  y: proxy.size.height * (box.top + box.bottom) / 2)
                }
            }
            .allowsHitTesting(false)
            Text("The screen stays on · brightness is lowered automatically")
                .font(Mobile.TypeScale.caption)
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.bottom, Mobile.Space.inline)
        }
        .overlay(alignment: .topLeading) {
            MobilePill(text: statusText, live: model.sessionState == .streaming || model.isDemo)
                .padding(Mobile.Space.screen)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: Mobile.Space.inline) {
                if model.sessionState == .streaming {
                    IconButton(symbol: model.screenState == .idle ? "text.viewfinder" : "xmark.circle",
                               label: model.screenState == .idle ? "Translate screen" : "Remove screen translations") {
                        model.translateScreen()
                    }
                }
                IconButton(symbol: "xmark", label: "Close") { dismiss() }
            }
            .padding(Mobile.Space.screen)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            Orientation.request(.landscape)
            dim(true)
        }
        .onDisappear {
            Orientation.request(.portrait)
            dim(false)
        }
    }

    private var statusText: String {
        if model.isDemo { return UILanguage.text("demo.status", locale) }
        guard model.sessionState == .streaming else { return model.ps5StatusText }
        return model.packsActive ? String(localized: "PS5 connected · ready translation") : String(localized: "PS5 connected")
    }

    private var scale: Double { Double(model.settings.style.fontSize) / Double(SubtitleStyle().fontSize) }

    private var textColor: Color {
        switch model.settings.style.textColor {
        case .yellow: Mobile.Palette.subtitleYellow
        case .white: Mobile.Palette.subtitleWhite
        }
    }

    /// Altyazı ekranı açıkken parlaklık kısılır (pil ve göz); kapanınca eski değer döner.
    private func dim(_ on: Bool) {
        guard let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first else { return }
        if on {
            savedBrightness = screen.brightness
            screen.brightness = min(screen.brightness, 0.4)
        } else if let savedBrightness {
            screen.brightness = savedBrightness
        }
    }
}

/// Altyazı ekranı açılınca telefon yataya döner.
enum Orientation {
    @MainActor
    static func request(_ mask: UIInterfaceOrientationMask) {
        // Nino: ana ekran dikey kilitli; tam ekran altyazı açılınca yalnız yatay izin verilir.
        NinoAppDelegate.orientations = mask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

// MARK: - 7 Kullanım turu (ilk açılışta bir kez, 4 adım)

struct CoachTour: View {
    let anchors: [TourTarget: Anchor<CGRect>]
    let onFinish: () -> Void
    @State private var step = 0

    private let steps: [(title: LocalizedStringKey, text: LocalizedStringKey)] = [
        ("Start translating here", "Tap after you open the game on the PS5. The phone takes the picture, reads the subtitles and translates them."),
        ("Where the subtitles appear", "On the TV over the game, or on this phone. Tap to change it."),
        ("Ready packs", "In popular games the subtitles come from ready translations, without waiting."),
        ("Profile and settings", "Your devices, PSN account and translation settings are here."),
    ]

    var body: some View {
        GeometryReader { proxy in
            let target = TourTarget(rawValue: step) ?? .start
            let rect = anchors[target].map { proxy[$0].insetBy(dx: -6, dy: -6) }
            ZStack(alignment: .topLeading) {
                // %72 karartma, vurgulanan öğenin çevresinde delik ve düz amber halka (parıltı yok).
                Color.black.opacity(0.72)
                    .reverseMask {
                        if let rect {
                            RoundedRectangle(cornerRadius: Mobile.Radius.control).frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                if let rect {
                    RoundedRectangle(cornerRadius: Mobile.Radius.control)
                        .strokeBorder(Mobile.Palette.accent, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                card
                    .padding(.horizontal, Mobile.Space.screen)
                    .frame(maxWidth: .infinity)
                    .position(x: proxy.size.width / 2, y: cardY(rect: rect, height: proxy.size.height))
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    private func cardY(rect: CGRect?, height: CGFloat) -> CGFloat {
        guard let rect else { return height / 2 }
        // Kart vurgulanan öğenin karşı yarısında durur.
        return rect.midY > height / 2 ? max(140, rect.minY - 120) : min(height - 140, rect.maxY + 120)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Mobile.Space.gap) {
            HStack {
                Text(verbatim: "\(step + 1) / \(steps.count)").font(Mobile.TypeScale.caption).monospacedDigit()
                    .foregroundStyle(Mobile.Palette.secondary)
                Spacer()
                Button("Skip", action: onFinish).buttonStyle(.mobileGhost)
            }
            VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                Text(steps[step].title).font(Mobile.TypeScale.title)
                Text(steps[step].text).font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                PageDots(count: steps.count, current: step)
                Spacer()
                Button(step == steps.count - 1 ? "Done" : "Next") {
                    if step == steps.count - 1 { onFinish() } else { withAnimation { step += 1 } }
                }
                .buttonStyle(MobileButtonStyle(kind: .primary))
                .frame(width: 120)
            }
        }
        .padding(Mobile.Space.tile)
        .background(Mobile.Palette.surface2, in: RoundedRectangle(cornerRadius: Mobile.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: Mobile.Radius.tile).strokeBorder(Mobile.Palette.border))
    }
}

extension View {
    /// Verilen şekli görünümden oyar (turdaki delik).
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle().overlay { mask().blendMode(.destinationOut) }.compositingGroup()
        }
    }
}

/// "Ekranı çevir": oyun ekranının tamamını çevirir; çeviri sürerken ya da sonuçlar ekrandayken dokununca kaldırır.
struct ScreenTranslateButton: View {
    @EnvironmentObject private var model: PhoneModel

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            model.translateScreen()
        } label: {
            switch model.screenState {
            case .idle: Label("Translate screen", systemImage: "text.viewfinder")
            case .working: Label("Translating the screen…", systemImage: "hourglass")
            case .shown: Label("Remove screen translations", systemImage: "xmark.circle")
            }
        }
        .buttonStyle(.mobileSecondary)
    }
}
