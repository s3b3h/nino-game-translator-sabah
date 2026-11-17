// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import RemotePlay
import SwiftUI
import XCTest
@testable import Nino

/// Geliştirme aracı: README'deki ekran görüntüleri (docs/screenshots/mac). Yalnız `COUCHSUBS_SCREENSHOTS` ortam
/// değişkeni (klasör) verilince çalışır; `scripts/mac-screenshots.sh` başlatır. Uygulamanın ekranları koyu görünümde,
/// örnek verilerle (sahte hizmetler, bellekteki kayıt) birer pencerede açılır ve pencerenin kendisi (başlık çubuğu
/// dahil, ekranın 2x ölçeğinde) PNG'ye çizilir; Ekran Kaydı izni gerekmez.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var windows: [NSWindow] = []

    func testCaptureScreens() async throws {
        guard let path = ProcessInfo.processInfo.environment["COUCHSUBS_SCREENSHOTS"] else {
            throw XCTSkip("COUCHSUBS_SCREENSHOTS verilmedi")
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let main = try await mainModel()
        let setup = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        setup.accountId = Data(repeating: 1, count: 8)
        setup.step = .console

        // Nino: ilk açılış (karşılama) Türkçe seçiliyken, Arapça bayrağına basılınca ve sonraki adım.
        func firstRun(_ language: String, step: AppModel.Step) -> AppModel {
            let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
            model.settings.targetLanguage = language
            model.step = step
            return model
        }
        let welcomeTR = firstRun("tr", step: .welcome)
        // Nino: yeni kurulum ekranları (konsol seçimi, PS5 ve Xbox yolu, giriş, eşleştirme, TV, deneme).
        func onboarding(_ step: AppModel.Step, console: GameConsole? = nil, signedIn: Bool = false) -> AppModel {
            let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
            model.settings.targetLanguage = "tr"
            if let console { model.chooseWelcomeConsole(console) }
            if console == .xbox { model.settings.gameConsole = .xbox; model.settings.videoSource = .window }
            if signedIn { model.accountId = Data(repeating: 1, count: 8) }
            model.step = step
            return model
        }
        let picker = onboarding(.welcome)
        let ps5Welcome = onboarding(.welcome, console: .ps5)
        let xboxWelcome = onboarding(.welcome, console: .xbox)
        let secondAccount = onboarding(.secondAccount, console: .ps5)
        let psnLogin = onboarding(.psnLogin, console: .ps5)
        let pairing = onboarding(.console, console: .ps5, signedIn: true)
        let tvChoice = onboarding(.tv, console: .ps5, signedIn: true)
        let test = onboarding(.test, console: .ps5, signedIn: true)
        let better = onboarding(.betterTranslation, console: .ps5, signedIn: true)
        let mainXbox = try await mainModel()
        mainXbox.settings.gameConsole = .xbox
        mainXbox.settings.videoSource = .window
        mainXbox.windowStatus = .capturing(appName: "Safari")
        mainXbox.isRunning = true
        mainXbox.sessionState = .streaming
        mainXbox.lastSource = "We've been down here too long, Enzo."
        mainXbox.lastTranslation = "Burada çok uzun kaldık Enzo."
        let connection = try await mainModel()
        connection.isRunning = false
        connection.switchConsole(to: .xbox)
        let welcomeAR = firstRun("ar", step: .welcome)
        let nextAR = firstRun("ar", step: .secondAccount)

        let width = Theme.size("windowWidth"), height = Theme.size("windowHeight")
        let settingsSize = CGSize(width: width - 2 * Theme.space("screen"), height: height - 2 * Theme.space("screen"))
        let screens: [(String, AnyView, CGSize)] = [
            ("ana", AnyView(MainView().environmentObject(main)), CGSize(width: width, height: height)),
            ("ayarlar-ceviri", AnyView(SettingsView(section: .translation).environmentObject(main)), settingsSize),
            ("ayarlar-paketler", AnyView(SettingsView(section: .packs).environmentObject(main)), settingsSize),
            ("kurulum", AnyView(OnboardingView().environmentObject(setup)), CGSize(width: width, height: height)),
            ("ilk-acilis-turkce-secili", AnyView(OnboardingView().environmentObject(welcomeTR)), CGSize(width: width, height: height)),
            ("ilk-acilis-arapca-secili", AnyView(OnboardingView().environmentObject(welcomeAR)), CGSize(width: width, height: height)),
            ("arapca-sonraki-ekran", AnyView(OnboardingView().environmentObject(nextAR)), CGSize(width: width, height: height)),
            ("nino-konsol-secimi", AnyView(OnboardingView().environmentObject(picker)), CGSize(width: width, height: height)),
            ("nino-ps5-karsilama", AnyView(OnboardingView().environmentObject(ps5Welcome)), CGSize(width: width, height: height)),
            ("nino-xbox-kurulum", AnyView(OnboardingView().environmentObject(xboxWelcome)), CGSize(width: width, height: height)),
            ("nino-ikinci-hesap", AnyView(OnboardingView().environmentObject(secondAccount)), CGSize(width: width, height: height)),
            ("nino-psn-giris", AnyView(OnboardingView().environmentObject(psnLogin)), CGSize(width: width, height: height)),
            ("nino-ps5-baglama", AnyView(OnboardingView().environmentObject(pairing)), CGSize(width: width, height: height)),
            ("nino-tv-secimi", AnyView(OnboardingView().environmentObject(tvChoice)), CGSize(width: width, height: height)),
            ("nino-deneyelim", AnyView(OnboardingView().environmentObject(test)), CGSize(width: width, height: height)),
            ("nino-daha-iyi-ceviri", AnyView(OnboardingView().environmentObject(better)), CGSize(width: width, height: height)),
            ("nino-ana-ps5", AnyView(MainView().environmentObject(main)), CGSize(width: width, height: height)),
            ("nino-ana-xbox", AnyView(MainView().environmentObject(mainXbox)), CGSize(width: width, height: height)),
            ("nino-ayarlar-baglanti", AnyView(SettingsView(section: .connection).environmentObject(connection)), settingsSize),
            ("nino-ayarlar-sifirla", AnyView(SettingsView(section: .reset).environmentObject(connection)), settingsSize),
        ]
        let shown = screens.enumerated().map { index, screen in
            (screen.0, show(screen.1, size: screen.2, offset: CGFloat(index) * 40))
        }
        // Görevler (PS5 arama, paket yükleme) ve çizim bitsin.
        try await Task.sleep(for: .seconds(3))
        for (name, window) in shown {
            try capture(window).write(to: folder.appendingPathComponent("\(name).png"))
        }
        windows.forEach { $0.close() }
    }

    /// Pencereyi çerçevesiyle (başlık çubuğu ve düğmeleri dahil) PNG olarak çizer.
    private func capture(_ window: NSWindow) throws -> Data {
        let view = try XCTUnwrap(window.contentView?.superview ?? window.contentView)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// Kurulumu bitmiş, çeviri süren uygulama: PS5 ve TV bağlı, DeepL seçili, son altyazılar geçmişte.
    private func mainModel() async throws -> AppModel {
        let store = MemoryStore()
        store.save(Data(repeating: 1, count: 8), for: StoreKey.accountId)
        store.save(RegisteredConsole(host: "192.168.1.253", name: "PS5-789", registKey: Data(repeating: 0x31, count: 16),
                                     morning: Data(repeating: 2, count: 16)), for: StoreKey.console)
        store.save(LGTV(name: "LG TV", host: "192.168.1.153"), for: StoreKey.tv)
        store.save("tv-key", for: StoreKey.tvKey)
        let model = AppModel(services: FakeServices(), store: store, defaults: .isolated())
        model.settings.translationEngine = .deepL
        model.isRunning = true
        model.sessionState = .streaming
        model.tvClients = 1
        let sample = [("I gotta tell you this, Franklin.", "Bunu sana söylemem lazım, Franklin."),
                      ("Take out the Lost.", "Lost üyelerini ortadan kaldır."),
                      ("Are you listening to me?", "Dinliyor musun beni?")]
        for (source, translation) in sample {
            model.history.add(source: source, translation: translation)
            model.lastSource = source
            model.lastTranslation = translation
        }
        // Paketler açılışta arka planda yüklenir.
        let deadline = Date().addingTimeInterval(10)
        while model.installedPacks.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        return model
    }

    private func show(_ view: AnyView, size: CGSize, offset: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Nino"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Color.csBackground)
        window.contentView = NSHostingView(rootView: view.appSurface().frame(width: size.width, height: size.height))
        window.setFrameTopLeftPoint(NSPoint(x: 80 + offset, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 40 - offset))
        window.orderFrontRegardless()
        windows.append(window)
        return window
    }
}
