// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import RemotePlay
import SwiftUI
import UIKit
import UserNotifications

/// Nino Game Translator tamamen ücretsizdir, hesap istemez ve hiçbir ölçüm ya da izleme yapmaz (CouchSubs'taki Firebase
/// ve Meta kitaplıkları kaldırıldı).
@main
struct CouchSubsApp: App {
    @UIApplicationDelegateAdaptor(NinoAppDelegate.self) private var appDelegate
    @StateObject private var model: PhoneModel
    @StateObject private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    /// Son etkin oluştan beri arka plana gidildi mi (yalnız etkin değilken dönmek bağlantıyı yenilemez).
    @State private var wasInBackground = false

    init() {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // Uygulamayla gelen paketler, üstüne sunucudan indirilen güncel sürümleri, en üstte içe aktarılan topluluk paketleri.
        let library = GamePackLibrary(bundled: GamePackLibrary.bundledDirectory,
                                      user: PackStore.filesDirectory(in: PackStore.defaultDirectory),
                                      imported: PackStore.importedDirectory)
        let model = testing ? PhoneModel(store: EphemeralStore(), packs: library)
            : Self.demoStore().map { PhoneModel(store: $0, packs: library) } ?? PhoneModel(packs: library)
        // Çeviri sürerken ekran kararmaz: iOS kilitlenen ya da arka plana geçen uygulamayı askıya alır.
        model.keepScreenAwake = { UIApplication.shared.isIdleTimerDisabled = $0 }
        // PS5 bağlantısı koptuğunda yerel bildirim (Profil'deki tercih; testlerde kapalı).
        if !testing {
            model.requestNotificationPermission = { ConnectionAlert.requestPermission() }
            model.onConnectionLost = { ConnectionAlert.post() }
        }
        // Çevrilen son satırlar ("Geçmiş"); testlerde dosyaya dokunulmaz.
        if !testing { model.loadHistory() }

        let analytics = NoAnalytics()
        let store = testing ? nil : AppConfig.packsBaseURL.map { PackStore(baseURL: $0, directory: PackStore.defaultDirectory) }
        let app = AppModel(analytics: analytics, packStore: store, library: library)
        model.onAnalytics = { [analytics] event in analytics.log(event) }
        app.onPacksChanged = { [weak model] in model?.packsChanged() }
        // Nino: arayüz yalnız Türkçe ya da Arapçadır (çeviri dili; ilk açılışta telefon Arapçaysa Arapça, değilse Türkçe).
        // Uygulama dili açılışta, metinler okunmadan önce ayarlanır; telefon İngilizce olsa da İngilizce görünmez.
        if !testing { UILanguage.remember(target: model.settings.targetLanguage) }
        model.onGameStarted = { [weak app] in Task { await app?.gameStarted() } }
        _model = StateObject(wrappedValue: model)
        _app = StateObject(wrappedValue: app)
    }

    /// Hata ayıklama: COUCHSUBS_DEMO=1 ile kurulum bitmiş gibi açılır (ekran görüntüsü ve tasarım denetimi için;
    /// PS5'e bağlanmaz). Anahtarlığa dokunmaz.
    private static func demoStore() -> CouchSubsCore.AppStore? {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["COUCHSUBS_DEMO"] == "1" else { return nil }
        let store = EphemeralStore()
        store.save(Data([1, 2, 3]), for: StoreKey.accountId)
        store.save(RegisteredConsole(host: "192.168.1.103", name: "PS5-002", registKey: Data(), morning: Data()), for: StoreKey.console)
        store.save(LGTV(name: "Salon TV", host: "192.168.1.50", brand: .lg), for: StoreKey.tv)
        store.save("demo", for: StoreKey.tvKey)
        store.save(true, for: StoreKey.setupComplete)
        return store
        #else
        return nil
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(app)
                .appSurface()
                .task { await app.start() }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                model.becameActive(afterBackground: wasInBackground)
                wasInBackground = false
            case .background:
                wasInBackground = true
                Task { await model.flushPool() }
            default: break
            }
        }
    }
}

/// "PS5 bağlantısı koptu" yerel bildirimi (Android'deki gibi). Uygulama öndeyken gösterilmez: durum ekranda görünür.
@MainActor
enum ConnectionAlert {
    private static let identifier = "connection-lost"

    /// İzin yalnız ilk seferde sorulur; sonra iOS kayıtlı yanıtı döner.
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post() {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "PS5 connection lost")
        content.body = String(localized: "Subtitles stopped. Open Nino to reconnect.")
        content.sound = .default
        // Aynı kimlik: art arda kopmalarda bildirimler birikmez, sonuncusu kalır.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

struct RootView: View {
    @EnvironmentObject private var model: PhoneModel
    @EnvironmentObject private var app: AppModel
    @AppStorage("welcomeSeen") private var welcomeSeen = false
    @State private var path: [Route] = []

    var body: some View {
        Group {
            if !welcomeSeen {
                WelcomeFlow(onFinish: finishWelcome)
            } else if model.step != .done {
                setup
            } else {
                home
            }
        }
        .preferredColorScheme(.light)
        .tint(Mobile.Palette.accent)
        // Nino: arayüz dili çeviri dilini izler (Arapça → Arapça, sağdan sola), anında.
        .environment(\.locale, UILanguage.locale(for: model.settings.targetLanguage))
        .environment(\.layoutDirection, UILanguage.direction(for: model.settings.targetLanguage))
        .onAppear { UILanguage.remember(target: model.settings.targetLanguage) }
        .onChange(of: model.settings.targetLanguage) { UILanguage.remember(target: $0) }
    }

    private func finishWelcome() {
        welcomeSeen = true
        if model.step == .welcome { model.advance() }
    }

    /// Kurulum: PSN girişi → PS5 eşleme → altyazının yeri.
    @ViewBuilder private var setup: some View {
        switch model.step {
        case .welcome, .psnLogin:
            // Önce konsol türü (PlayStation varsayılan, Xbox Beta); Xbox'ta ikinci hesap (PSN) yerine Microsoft girişi.
            if !model.platformChosen {
                PlatformScreen(onBack: { welcomeSeen = false }) {}
            } else if model.isXbox {
                XboxLoginScreen(onBack: { model.platformChosen = false }, onSkip: { model.skipSetup() }, onDone: {
                    if model.step == .welcome { model.advance() }
                    model.advance()
                })
            } else {
                PSNScreen(onBack: { model.platformChosen = false }, onSkip: { model.skipSetup() }, onDone: {
                    if model.step == .welcome { model.advance() }
                    model.advance()
                })
            }
        case .console where model.isXbox:
            XboxConsoleScreen(onBack: { model.back() }, onSkip: { model.skipSetup() }, onSignIn: { model.back() },
                              onDone: { model.advance() })
        case .console:
            PS5PairScreen(onBack: { model.back() }, onSkip: { model.skipSetup() }, onDone: { model.advance() })
        case .output, .done:
            TargetScreen(onBack: { model.back() }) { model.advance() }
        }
    }

    private var home: some View {
        NavigationStack(path: $path) {
            Group {
                HomeScreen(path: $path)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .settings: SettingsScreen(path: $path)
                case .profile: ProfileScreen(path: $path)
                case .packs: PacksScreen()
                case .target: TargetScreen(setup: false) { path.removeLast() }
                // Kurulum atlandıysa PSN girişi yoktur: PS5 eşlemeden önce giriş yapılır, ardından eşlemeye geçilir.
                case .platform:
                    PlatformScreen(onBack: { path.removeLast() }) {
                        path.removeLast()
                        if model.isXbox && (!model.xboxSignedIn || model.xboxConsole == nil) { path.append(.ps5) }
                    }
                // Xbox (Beta): giriş yoksa önce Microsoft girişi, ardından Xbox seçimi.
                case .ps5 where model.isXbox && !model.xboxSignedIn:
                    XboxLoginScreen(onBack: { path.removeLast() }, onDone: {
                        path.removeLast()
                        path.append(.ps5)
                    })
                case .ps5 where model.isXbox:
                    XboxConsoleScreen(onBack: { path.removeLast() }, onSignIn: { model.signOutXbox() }, onDone: { path.removeLast() })
                case .ps5 where model.accountId == nil:
                    PSNScreen(onBack: { path.removeLast() }, onDone: {
                        path.removeLast()
                        path.append(.ps5)
                    })
                case .ps5: PS5PairScreen(onBack: { path.removeLast() }, onDone: { path.removeLast() })
                case .psn: PSNScreen(onBack: { path.removeLast() }, onDone: { path.removeLast() })
                case .about: AboutScreen()
                case .history: HistoryScreen()
                case .tvInstall: TVInstallScreen(onDone: { path.removeAll() })
                case .tvUpdate: TVInstallScreen(update: model.tvAppUpdate, onDone: { path.removeAll() })
                }
            }
        }
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            if !app.tourDone && path.isEmpty && !model.isRunning {
                CoachTour(anchors: anchors) { withAnimation { app.tourDone = true } }
            }
        }
    }
}
