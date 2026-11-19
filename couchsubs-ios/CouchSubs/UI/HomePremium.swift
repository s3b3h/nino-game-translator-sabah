// SPDX-License-Identifier: AGPL-3.0-only
// Nino: telefonun ana ekranı (Android'deki HomePremium ile aynı): durum satırı, büyük başlık, sahne kartı, bayrak renkli
// kaydırma çubuğu ve altta üç kısa yol. Arapça arayüzde her şey sağdan sola; kaydırma da sağdan sola yapılır.

import CoreMotion
import RemotePlay
import CouchSubsCore
import SwiftUI
import UIKit

// MARK: - Arayüz dili (çeviri dilini izler)

/// Arayüz dili çeviri dilini izler: Türkçe → Türkçe arayüz, Arapça ve Urduca sağdan sola, her dil kendi arayüzüyle.
/// Yeni metinler `Home` tablosunda.
enum UILanguage {
    static func code(for target: String) -> String { TargetLanguage.interfaceLanguage(target) }

    static func locale(for target: String) -> Locale { Locale(identifier: code(for: target)) }

    static func direction(for target: String) -> LayoutDirection {
        TargetLanguage.isRightToLeft(target) ? .rightToLeft : .leftToRight
    }

    /// Verilen dilin paketinden metin; yoksa ana paket.
    static func text(_ key: String, _ locale: Locale, table: String = "Home") -> String {
        let code = locale.language.languageCode?.identifier ?? "tr"
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) {
            let value = bundle.localizedString(forKey: key, value: "\u{0}", table: table)
            if value != "\u{0}" { return value }
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: table)
    }

    /// `String(localized:)` kullanan eski ekranlar da bir sonraki açılışta aynı dilde olsun.
    static func remember(target: String) {
        UserDefaults.standard.set([code(for: target)], forKey: "AppleLanguages")
    }
}

/// Bayrak renkleri: Türkçe kırmızı, Arapça yeşil; öbür diller bayraklarının baskın rengi.
enum FlagColors {
    static let red = Color(hex: 0xE30A17)
    static let redDeep = Color(hex: 0xA80514)
    static let green = Color(hex: 0x0B8A4A)
    static let greenDeep = Color(hex: 0x056236)

    static func pair(for target: String) -> (Color, Color) {
        switch String(target.prefix(2)) {
        case "ar", "ur", "bn": (green, greenDeep)
        case "hi", "nl": (Color(hex: 0xF08A1C), Color(hex: 0xB85F00))
        case "th", "ms", "tl": (Color(hex: 0x2D4FB3), Color(hex: 0x1A3380))
        default: (red, redDeep)
        }
    }
}

private let ink = Color(hex: 0x0A1430)
private let inkSoft = Color(hex: 0x55607A)
private let stageTop = Color(hex: 0x151E36)
private let stageBottom = Color(hex: 0x06080F)
private let liveGreen = Color(hex: 0x30C578)

/// Ana ekranın durumu.
enum HomeState { case notPaired, ready, connecting, live }

// MARK: - Ana ekran

struct HomeScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @EnvironmentObject private var app: AppModel
    @Environment(\.locale) private var locale
    @Binding var path: [Route]
    /// Kurulumdan açılan PS5'siz önizleme: üstte yalnız logo ve Kapat; kısa yollar yok.
    var demoOnly = false
    var onClose: (() -> Void)?
    @State private var showSubtitles = false
    @StateObject private var sideways = SidewaysWatcher()

    private func t(_ key: String) -> String { UILanguage.text(key, locale) }

    private var state: HomeState {
        if model.isDemo { return .live }
        if model.isRunning { return model.sessionState == .streaming ? .live : .connecting }
        if model.isStarting { return .connecting }
        return model.canStart ? .ready : .notPaired
    }

    private var target: String { model.settings.targetLanguage }
    private var onPhone: Bool { model.isDemo || model.settings.output.showsOnComputer }
    private var languageName: String {
        TargetLanguage.isTurkish(target) ? t("lang.tr") : target.hasPrefix("ar") ? t("lang.ar") : TargetLanguage.nativeName(target)
    }

    var body: some View {
        MobileScreen {
            if demoOnly {
                HStack {
                    LogoView(size: 36)
                    Spacer()
                    Button(t("common.close")) { onClose?() }.buttonStyle(.mobileGhost)
                }
                .frame(height: Mobile.Control.icon)
            } else {
                HomeHeader(path: $path)
            }
        } content: {
            statusLine
                .padding(.top, Mobile.Space.inline)
            Text(verbatim: title)
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.25), value: state)
            HomeStage(state: state, line: currentLine, source: model.isDemo ? model.demoLine?.source : nil,
                      badge: t(model.isDemo ? "demo.badge" : "home.live"), locale: locale,
                      sunset: state == .live && !model.isDemo && model.liveGamePoolFirst,
                      onFullScreen: onPhone ? { openFullScreen() } : nil)
                .padding(.top, 8)
            SlideToTranslate(state: state, target: target, label: slideLabel,
                             onStart: start, onStop: stop, onSetup: { path.append(.ps5) })
                .tourTarget(.start)
                .padding(.top, 10)
            // PS5 eşlenmemişken: uygulamanın nasıl çalıştığını PS5'siz gösteren demo (App İnceleme de kullanır).
            if state == .notPaired && !model.isDemo {
                TryWithoutPS5Button(title: t("demo.try")) { model.startDemo() }
                    .frame(maxWidth: .infinity)
            }
            if state == .live && onPhone {
                HStack(spacing: 8) {
                    Image(systemName: "rotate.right").font(.system(size: 15, weight: .medium))
                    Text(verbatim: t("home.rotateHint")).font(.system(size: 14))
                }
                .foregroundStyle(inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .transition(.opacity)
            }
            if !demoOnly { HStack(spacing: 10) {
                // Xbox (Beta) seçildiyse kısa yol Xbox'ı gösterir (CouchSubs'tan).
                if model.isXbox {
                    Shortcut(symbol: "gamecontroller.fill", title: "Xbox · Beta",
                             value: model.xboxConsole.map { $0.name.isEmpty ? "Xbox" : $0.name } ?? String(localized: "Choose your Xbox")) { path.append(.ps5) }
                } else {
                    Shortcut(symbol: "gamecontroller.fill", title: "PS5",
                             value: model.console.map { $0.name.isEmpty ? "PS5" : $0.name } ?? t("home.status.notPaired")) { path.append(.ps5) }
                }
                Shortcut(symbol: onPhone ? "iphone" : "tv", title: t("home.output"),
                         value: onPhone ? t("home.output.phone") : (model.tv?.name ?? "TV")) { path.append(.target) }
                    .tourTarget(.target)
                Shortcut(symbol: "shippingbox.fill", title: t("home.packs"), value: t("home.packs.free")) { path.append(.packs) }
                    .tourTarget(.packs)
            }
            .padding(.top, 16) }
            if !demoOnly {
                // TV uygulaması bu telefondan kurulur ya da güncellenir (CouchSubs'tan).
                if let update = model.tvAppUpdate {
                    TVAppUpdateTile(update: update) { path.append(.tvUpdate) }
                } else if model.tvAppMissing {
                    Button { path.append(.tvInstall) } label: {
                        InfoTile(symbol: "arrow.down.app", title: "Install the TV app from this phone", caption: "Samsung · LG · Android TV")
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.translatorStatus == .needsDownload, #available(iOS 26, *) { LanguagePackTile() }
            if model.translatorStatus == .unsupported, !Translator.isAvailable {
                MobileNote(text: String(localized: "Apple's free translation needs iOS 26 or later. Game packs, DeepL and AI translation work on this device."))
            } else if model.translatorStatus == .unsupported, !model.onlineTranslationActive {
                // Nino: Apple'ın ücretsiz çevirisinde olmayan dil (Urduca, Bengalce, Filipince).
                MobileNote(text: String(localized: "Apple's free translation doesn't support this language yet. Turn on AI translation in Settings › Translation; Gemini is free."))
            }
            if model.isRunning && !model.isDemo {
                // İlk altyazı gelene kadar: kolu açınca PS5'te ana hesap seçilmeli (GitHub #231).
                if model.recentLines.isEmpty && !model.isXbox {
                    MobileNote(text: String(localized: "When you turn on the controller to play, choose your MAIN account on the PS5. Don't play with the second account Nino signs in with, or the controller won't work in the game."),
                               tone: Mobile.Palette.secondary)
                }
                GameSection(choice: model.gameChoice)
                if model.sessionState == .streaming { ScreenTranslateButton() }
            }
            if model.isRunning {
                Text("Keep Nino open on the screen while you play. iOS stops the connection when the app goes to the background; the screen stays on while translating.")
                    .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.tertiary)
                    .padding(.top, 4)
            }
        } bottom: {
            EmptyView()
        }
        .animation(.easeOut(duration: 0.25), value: state)
        .fullScreenCover(isPresented: $showSubtitles, onDismiss: { sideways.disarm() }) { SubtitleScreen() }
        .onChange(of: model.isRunning) { running in
            // Çeviri başlayınca, altyazı telefondaysa tam ekran açılır (Android'de de öyle).
            if running && onPhone { openFullScreen() }
            updateWatcher()
        }
        .onChange(of: model.settings.output) { _ in updateWatcher() }
        .onChange(of: model.isDemo) { _ in updateWatcher() }
        .onAppear {
            sideways.onSideways = { if !showSubtitles { openFullScreen() } }
            updateWatcher()
            #if DEBUG
            // Hata ayıklama: COUCHSUBS_START_DEMO=1 ile demo açılışta başlar (ekran görüntüsü için).
            if ProcessInfo.processInfo.environment["COUCHSUBS_START_DEMO"] == "1" { model.startDemo() }
            // COUCHSUBS_FULLSCREEN=1: demo tam ekran altyazıyla açılır (iPad/iPhone tam ekran denetimi için).
            if ProcessInfo.processInfo.environment["COUCHSUBS_FULLSCREEN"] == "1" {
                model.startDemo()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { showSubtitles = true }
            }
            #endif
        }
        .onDisappear { sideways.stop() }
        .task {
            app.analytics.screen("home")
            await model.refreshTranslatorStatus()
            await model.checkTVApp()
        }
    }

    private var title: String {
        switch state {
        case .notPaired: t("home.title.pair")
        case .live: t("home.title.live")
        default: String(format: t("home.title.ready"), languageName)
        }
    }

    private var slideLabel: String {
        switch state {
        case .notPaired: t("slide.pair")
        case .ready: t("slide.start")
        default: t("slide.stop")
        }
    }

    private var currentLine: String? {
        if model.isDemo { return model.demoLine?.translation }
        if let line = model.phoneLines.last?.text, !line.isEmpty { return line }
        return model.recentLines.first?.translation
    }

    private var statusLine: some View {
        let (color, text): (Color, String) = switch state {
        case .notPaired: (inkSoft, t("home.status.notPaired"))
        case .ready: (Mobile.Palette.accent, t("home.status.ready"))
        case .connecting: (Mobile.Palette.accent, t("home.status.connecting"))
        case .live: (liveGreen, t(onPhone ? "home.status.live" : "home.status.tv"))
        }
        let name = model.isXbox ? model.xboxConsole.map { $0.name.isEmpty ? "Xbox" : $0.name } ?? "Xbox"
            : model.console.map { $0.name.isEmpty ? "PS5" : $0.name } ?? "PS5"
        let shown = model.isDemo ? t("demo.status") : (state == .notPaired ? text : "\(name)  ·  \(text)")
        return HStack(spacing: 8) {
            PulsingDot(color: color, pulses: state == .live || state == .connecting)
            Text(verbatim: shown)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(inkSoft)
                .lineLimit(1)
        }
    }

    private func start() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await model.start() }
    }

    private func stop() {
        if model.isDemo { model.stopDemo() } else { model.stop() }
    }

    private func openFullScreen() {
        sideways.disarm()
        showSubtitles = true
    }

    private func updateWatcher() {
        if (model.isRunning || model.isDemo) && onPhone { sideways.start() } else { sideways.stop() }
    }
}

// MARK: - Parçalar

private struct PulsingDot: View {
    let color: Color
    let pulses: Bool
    @State private var dim = false

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .opacity(pulses && dim ? 0.3 : 1)
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { dim = true } }
    }
}

/// Sahne: koyu ekran. Canlıyken altyazı akar (dokununca tam ekran); değilken tek satırlık sakin bir yazı.
private struct HomeStage: View {
    let state: HomeState
    let line: String?
    var source: String?
    var badge: String
    let locale: Locale
    /// Tanınan oyun havuz öncelikli (GTA 6): koyu zemin yerine buzlu gün batımı fonu; altyazı önünde durur.
    var sunset = false
    let onFullScreen: (() -> Void)?

    private func t(_ key: String) -> String { UILanguage.text(key, locale) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [stageTop, stageBottom], startPoint: .top, endPoint: .bottom))
            if sunset {
                SunsetBackdrop().clipShape(shape).transition(.opacity)
            }
            if state == .live {
                VStack {
                    Spacer(minLength: 0)
                    if let source, line != nil {
                        Text(verbatim: source).font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1).padding(.bottom, 4).transition(.opacity)
                    }
                    if let line, !line.isEmpty {
                        Text(verbatim: TargetLanguage.displayText(line))
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .subtitleDirection(line)
                            .id(line)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        Text(verbatim: t("home.stage.waiting")).font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 22)
                .animation(.easeOut(duration: 0.2), value: line)
            } else {
                Text(verbatim: t(state == .connecting ? "home.stage.connecting" : "home.stage.idle"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .multilineTextAlignment(.center)
                    .padding(24)
            }
        }
        .frame(height: 196)
        .animation(.easeOut(duration: 0.3), value: sunset)
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .overlay(alignment: .topLeading) {
            if state == .live {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: 0xE5162B)).frame(width: 8, height: 8)
                    Text(verbatim: badge).font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.black.opacity(0.45), in: Capsule())
                .padding(14)
            }
        }
        .overlay(alignment: .topTrailing) {
            if state == .live, let onFullScreen {
                Button(action: onFullScreen) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13, weight: .semibold))
                        Text(verbatim: t("home.fullScreen")).font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 12).padding(.trailing, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
                    .background(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), in: Capsule())
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .environment(\.colorScheme, .dark)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(12)
                .transition(.opacity)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .shadow(color: ink.opacity(0.35), radius: 18, y: 10)
        .contentShape(shape)
        .onTapGesture { if state == .live { onFullScreen?() } }
    }
}

/// GTA 6 için Nino'nun kendi fonu (Mac'teki `SunsetBackdrop` ile aynı): laciverd-mor-pembe gün batımı geçişi,
/// hafif karartılmış. Oyunun logosu ya da görseli kullanılmaz, yalnız renk geçişi.
private struct SunsetBackdrop: View {
    // Yalnız bir geçiş: güneş, bulanıklık ya da ayrı katman yok (Mac: GameBackdrop.swift ile aynı renkler).
    var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Color(red: 0.10, green: 0.08, blue: 0.34), location: 0),
                .init(color: Color(red: 0.46, green: 0.16, blue: 0.62), location: 0.40),
                .init(color: Color(red: 0.93, green: 0.29, blue: 0.60), location: 0.74),
                .init(color: Color(red: 1.00, green: 0.55, blue: 0.48), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            Color.black.opacity(0.28)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Kaydırarak başlatma: koyu iz, beyaz yuvarlak tutamaç, üzerinde akan parlak yazı. Sona kadar kaydırınca başlar; açıkken
/// iz bayrak renginde, tutamaç camlı bayrak küresi; geri kaydırınca durur. Eşlenmemişse dokununca kurulum açılır. Arapça
/// arayüzde tutamaç sağda başlar ve sola kaydırılır.
private struct SlideToTranslate: View {
    @Environment(\.layoutDirection) private var direction
    let state: HomeState
    let target: String
    let label: String
    let onStart: () -> Void
    let onStop: () -> Void
    let onSetup: () -> Void
    @State private var drag: CGFloat = 0

    private let height: CGFloat = 68
    private let knob: CGFloat = 56
    private let inset: CGFloat = 6

    var body: some View {
        let rtl = direction == .rightToLeft
        let on = state == .live || state == .connecting
        GeometryReader { proxy in
            let travel = max(1, proxy.size.width - knob - inset * 2)
            let base: CGFloat = on ? travel : 0
            let x = min(max(base + drag, 0), travel)
            let progress = x / travel
            let (top, bottom) = FlagColors.pair(for: target)
            ZStack(alignment: .leading) {
                Capsule().fill(ink)
                Capsule().fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)).opacity(progress)
                Capsule().fill(LinearGradient(stops: [.init(color: .white.opacity(0.22 * progress), location: 0), .init(color: .clear, location: 0.5)],
                                              startPoint: .top, endPoint: .bottom))
                Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                ShimmerText(text: label, rtl: rtl, base: 0.55 + 0.25 * progress)
                    .opacity(on ? 1 : max(0, 1 - progress * 1.4))
                    .frame(maxWidth: .infinity)
                    // Yazı, tutamacın bulunduğu tarafta ona yer bırakır (kapalıyken başta, açıkken sonda).
                    .padding((on != rtl) ? .trailing : .leading, knob + inset * 2)
                    .padding((on != rtl) ? .leading : .trailing, inset * 2)
                ZStack {
                    Circle().fill(Color.white)
                    if state == .connecting {
                        ProgressView().tint(Mobile.Palette.accent)
                    } else {
                        Image(systemName: rtl ? "arrow.left" : "arrow.right")
                            .font(.system(size: 22, weight: .semibold)).foregroundStyle(ink)
                            .opacity(1 - progress)
                        FlagGlass(target: target).opacity(progress)
                    }
                }
                .frame(width: knob, height: knob)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                .offset(x: inset + (rtl ? travel - x : x))
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { value in drag = rtl ? -value.translation.width : value.translation.width }
                    .onEnded { _ in
                        let end = (base + drag) / travel
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { drag = 0 }
                        switch state {
                        case .notPaired: if end > 0.5 { onSetup() }
                        default:
                            if !on && end > 0.85 { onStart() } else if on && end < 0.15 { onStop() }
                        }
                    })
                .onTapGesture {
                    switch state {
                    case .notPaired: onSetup()
                    case .ready: onStart()
                    default: onStop()
                    }
                }
            }
            .shadow(color: top.opacity(0.4 * progress), radius: 14, y: 6)
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: on)
        }
        .frame(height: height)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            switch state {
            case .notPaired: onSetup()
            case .ready: onStart()
            default: onStop()
            }
        }
    }
}

/// iPhone'un eski "kaydırarak aç" ışıltısı gibi soldan sağa (Arapça'da sağdan sola) akan parlak yazı.
private struct ShimmerText: View {
    let text: String
    let rtl: Bool
    let base: Double

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
            let sweep = -0.3 + 1.6 * t
            let center = rtl ? 1 - sweep : sweep
            Text(verbatim: text)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(LinearGradient(stops: [
                    .init(color: .white.opacity(base), location: max(0, center - 0.18)),
                    .init(color: .white, location: min(1, max(0, center))),
                    .init(color: .white.opacity(base), location: min(1, center + 0.18)),
                ], startPoint: .leading, endPoint: .trailing))
        }
    }
}

/// Camlı bayrak küresi: bayrak dairenin içinde, üstünde buzlu parlama ve ince ışıklı kenar.
private struct FlagGlass: View {
    /// Türkçede çizilmiş ay yıldız, öbür dillerde dilin bayrağı (emoji).
    let target: String

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                if !TargetLanguage.isTurkish(target) {
                    Text(verbatim: TargetLanguage.flag(target)).font(.system(size: size * 1.15)).fixedSize()
                } else {
                    FlagColors.red
                    CrescentStar().frame(width: size * 0.6, height: size * 0.6)
                }
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.1), .white.opacity(0.5)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                Ellipse().fill(LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.6, height: size * 0.3)
                    .offset(y: -size * 0.27)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        }
    }
}

/// Bayraktaki ay yıldız: beyaz ay (iç daire kırmızıyla oyulur) ve ucu aya bakan beş köşeli yıldız.
private struct CrescentStar: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let r = s * 0.42
            let moon = CGPoint(x: s * 0.42, y: s / 2)
            context.fill(Path(ellipseIn: CGRect(x: moon.x - r, y: moon.y - r, width: r * 2, height: r * 2)), with: .color(.white))
            let inner = r * 0.8
            let cut = CGPoint(x: moon.x + r * 0.32, y: s / 2)
            context.fill(Path(ellipseIn: CGRect(x: cut.x - inner, y: cut.y - inner, width: inner * 2, height: inner * 2)), with: .color(FlagColors.red))
            let center = CGPoint(x: s * 0.8, y: s / 2)
            let outer = s * 0.17
            let innerStar = outer * 0.382
            var star = Path()
            for i in 0..<10 {
                let angle = Double.pi + Double(i) * Double.pi / 5
                let radius = i % 2 == 0 ? outer : innerStar
                let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                if i == 0 { star.move(to: point) } else { star.addLine(to: point) }
            }
            star.closeSubpath()
            context.fill(star, with: .color(.white))
        }
    }
}

private struct Shortcut: View {
    let symbol: String
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(Mobile.Palette.accent)
                Spacer().frame(height: 12)
                Text(verbatim: title).font(.system(size: 12)).foregroundStyle(inkSoft).lineLimit(1)
                Text(verbatim: value).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 14)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Yan çevirme (ekran dönmeden)

/// Ana ekran dikey kilitlidir; telefonun yan çevrildiğini ivmeölçerle anlar (sistemin yön kilidi açık olsa da çalışır).
/// Yan durum en az 0,7 sn sürerse `onSideways` çağrılır; sonra telefon yeniden dik gelmeden tekrar çağrılmaz.
@MainActor
final class SidewaysWatcher: ObservableObject {
    var onSideways: (() -> Void)?
    private let motion = CMMotionManager()
    private var armed = false
    private var sidewaysSince: Date?

    func start() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 0.1
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            MainActor.assumeIsolated { self.handle(x: a.x, y: a.y) }
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        sidewaysSince = nil
    }

    /// Tam ekran açıldı ya da kapandı: telefon önce dik gelmeli.
    func disarm() {
        armed = false
        sidewaysSince = nil
    }

    private func handle(x: Double, y: Double) {
        let upright = y < -0.75 && abs(x) < 0.45
        let side = abs(x) > 0.75 && abs(y) < 0.45
        if upright { armed = true; sidewaysSince = nil; return }
        guard side, armed, UIApplication.shared.applicationState == .active else { sidewaysSince = nil; return }
        let now = Date()
        if let since = sidewaysSince {
            if now.timeIntervalSince(since) >= 0.7 {
                disarm()
                onSideways?()
            }
        } else {
            sidewaysSince = now
        }
    }
}

// MARK: - Yön

/// Uygulamanın izin verdiği yönler: ana ekran dikey, tam ekran altyazı yatay (iPad'de hepsi).
final class NinoAppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : Self.orientations
    }
}
