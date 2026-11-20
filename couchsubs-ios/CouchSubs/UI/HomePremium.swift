// SPDX-License-Identifier: AGPL-3.0-only
// Nino: telefonun ana ekranı: durum satırı, büyük başlık, salon sahnesi (Mac ve Android'deki gibi: fiş prize takılınca
// çeviri başlar; bkz. LivingRoom.swift) ve altta üç kısa yol. Arapça arayüzde her şey sağdan sola; sahne aynalanmaz.

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

    /// Bağlanılamıyorsa nedeni (ör. "PS5'te Uzaktan Oynama kapalı…"); sahnede "Bağlanıyor…" yerine bu görünür.
    private var problem: String? { state == .connecting ? model.connectionProblemText : nil }

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
            // Nino: kaydırma çubuğu yerine bütün Nino uygulamalarındaki salon: fişi prize takmak çeviriyi başlatır,
            // çekmek durdurur (eşlenmemişse kurulum açılır).
            PhoneLivingRoom(active: model.isDemo || model.isRunning || model.isStarting,
                            streaming: state == .live,
                            line: currentLine, source: model.isDemo ? model.demoLine?.source : nil,
                            problem: problem,
                            badge: t(model.isDemo ? "demo.badge" : "home.live"),
                            gta: (model.isRunning || model.isStarting) && !model.isDemo && model.liveGamePoolFirst,
                            onToggle: toggle,
                            onTV: { openFullScreen() })
                .tourTarget(.start)
                .padding(.top, 8)
            HStack(spacing: 10) {
                Text(verbatim: sceneHint)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // Nino: altyazı TV'ye gitse de telefonda tam ekran açılabilsin.
                if state == .live {
                    Button { openFullScreen() } label: {
                        Label(t("home.fullScreen"), systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Mobile.Palette.accent)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.white.opacity(0.72), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
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
            if OldIOSTranslationNotice.applies(model) {
                // Nino: iOS 26'dan eskide ücretsiz Apple çevirisi yok: GTA 6 havuzdan çalışır, diğer oyunlara Gemini anahtarı.
                OldIOSTranslationNotice { path.append(.settings) }
            } else if Translator.isAvailable, model.translatorStatus == .unsupported, !model.onlineTranslationActive {
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
            // COUCHSUBS_FAKE_PROBLEM=1: "bağlanılamıyor" görünümü (PS5'siz ekran görüntüsü için).
            if ProcessInfo.processInfo.environment["COUCHSUBS_FAKE_PROBLEM"] == "1" { model.debugShowConnectionProblem() }
            // COUCHSUBS_TEST_FRAME=<png>[,<png>…]: PS5'siz deneme karesi okuma hattına verilir, tam ekran altyazı açılır
            // (köşe ve mesaj çevirisinin simülatörde denenmesi için; ağa çıkmaz, sunucu başlatmaz).
            if let frames = PhoneModel.debugTestFramePaths {
                model.debugStartTestFrames(frames)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if model.isRunning, !showSubtitles { openFullScreen() } }
            }
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

    /// Sahnenin altındaki tek satırlık ipucu.
    private var sceneHint: String {
        switch state {
        case .notPaired: model.isDemo ? t("scene.unplug") : t("slide.pair")
        case .ready: t("scene.plug")
        default: t("scene.unplug")
        }
    }

    /// Fişe ya da prize dokunulunca (ya da fiş sürüklenince): çeviri açıksa durur, kapalıysa başlar; eşlenmemişse kurulum.
    private func toggle() {
        if model.isDemo { model.stopDemo(); return }
        // Hazırlık sürerken (bir saniyeden kısa) çekilirse hazırlık biter bitmez durdurulur; dokunuş kaybolmaz (Mac gibi).
        if model.isStarting {
            Task { @MainActor in
                while model.isStarting { try? await Task.sleep(for: .milliseconds(50)) }
                if model.isRunning { model.stop() }
            }
            return
        }
        if model.isRunning { stop() } else if model.canStart { start() } else { path.append(.ps5) }
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
        case .connecting: (problem == nil ? Mobile.Palette.accent : Mobile.Palette.warning, t("home.status.connecting"))
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

/// GTA 6 için Nino'nun kendi fonu (Mac'teki `SunsetBackdrop` ile aynı): laciverd-mor-pembe gün batımı geçişi,
/// hafif karartılmış. Oyunun logosu ya da görseli kullanılmaz, yalnız renk geçişi.
struct SunsetBackdrop: View {
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
