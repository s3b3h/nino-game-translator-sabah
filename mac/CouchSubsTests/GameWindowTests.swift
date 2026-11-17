// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import XCTest
@testable import Nino

@MainActor
final class GameWindowTests: XCTestCase {
    /// Nino: PS5'i olmayan kullanıcı ilk ekrandan kurulumu bitirir; yeniden açınca sihirbaz çıkmaz, çeviri başlatılabilir.
    func testSetupWithoutPS5WhenPlayingOnThisComputer() {
        let defaults = UserDefaults.isolated()
        let store = MemoryStore()
        let model = AppModel(services: FakeServices(), store: store, defaults: defaults)
        XCTAssertEqual(model.step, .welcome)
        XCTAssertFalse(model.canStart)
        model.useGameWindowSetup()
        XCTAssertEqual(model.step, .done)
        XCTAssertTrue(model.canStart)
        XCTAssertTrue(model.showsOnComputer)
        XCTAssertFalse(model.showsOnTV)
        let reopened = AppModel(services: FakeServices(), store: store, defaults: defaults)
        XCTAssertEqual(reopened.step, .done)
        XCTAssertEqual(reopened.settings.videoSource, .window)
    }

    private func window(_ app: String, _ w: CGFloat, _ h: CGFloat, id: CGWindowID = 1, bundle: String = "") -> GameWindowInfo {
        GameWindowInfo(id: id, appName: app, bundleID: bundle, title: "", frame: CGRect(x: 0, y: 0, width: w, height: h), fillsScreen: false)
    }

    func testPicksLargestRemotePlayWindow() {
        let picked = GameWindowPicker.pick([
            window("Safari", 1600, 900, id: 1),
            window("PS Remote Play", 400, 300, id: 2),
            window("PS Remote Play", 1280, 748, id: 3),
            window("chiaki-ng", 200, 100, id: 4),
        ], wanted: ["remote play", "chiaki"])
        XCTAssertEqual(picked?.id, 3)
    }

    func testMatchesBundleIdAndIgnoresTinyWindows() {
        XCTAssertEqual(GameWindowPicker.pick([window("Chiaki", 960, 560, bundle: "io.github.chiaki")], wanted: ["chiaki"])?.id, 1)
        XCTAssertNil(GameWindowPicker.pick([window("PS Remote Play", 300, 150)], wanted: ["remote play"]))
        XCTAssertNil(GameWindowPicker.pick([window("Finder", 1200, 800)], wanted: ["remote play"]))
    }

    /// Nino: Xbox: Greenlight ya da başlığında "Xbox" olan tarayıcı penceresi; PS5 pencereleri seçilmez.
    func testPicksXboxStreamWindow() {
        func titled(_ app: String, _ bundle: String, _ title: String, _ w: CGFloat, id: CGWindowID) -> GameWindowInfo {
            GameWindowInfo(id: id, appName: app, bundleID: bundle, title: title, frame: CGRect(x: 0, y: 0, width: w, height: w * 9 / 16), fillsScreen: false)
        }
        let windows = [
            titled("Safari", "com.apple.Safari", "Haberler", 1800, id: 1),
            titled("Safari", "com.apple.Safari", "Xbox Cloud Gaming on Xbox.com", 1400, id: 2),
            titled("PS Remote Play", "com.playstation.RemotePlay", "", 1600, id: 3),
            titled("TextEdit", "com.apple.TextEdit", "xbox notları", 1700, id: 4),
        ]
        XCTAssertEqual(GameWindowPicker.pick(windows, target: .xbox)?.id, 2)
        XCTAssertEqual(GameWindowPicker.pick(windows + [titled("Greenlight", "com.unknownskl.greenlight", "", 1500, id: 5)], target: .xbox)?.id, 5)
        XCTAssertNil(GameWindowPicker.pick([titled("Greenlight", "", "", 300, id: 6)], target: .xbox))
        XCTAssertEqual(GameWindowPicker.pick(windows, target: .playStation)?.id, 3)
    }

    /// Nino: Chrome'daki "Xbox.com'da Xbox Uzaktan Oynama" sekmesi; başlıkta Xbox yoksa tam ekran tarayıcı oyundur.
    func testPicksXboxBrowserTabOrFullScreenBrowser() {
        func win(_ title: String, full: Bool, id: CGWindowID) -> GameWindowInfo {
            GameWindowInfo(id: id, appName: "Google Chrome", bundleID: "com.google.Chrome", title: title,
                           frame: CGRect(x: 0, y: 0, width: 1512, height: 945), fillsScreen: full)
        }
        XCTAssertEqual(GameWindowPicker.pick([win("Apple Hesabı", full: false, id: 1),
                                              win("Xbox.com'da Xbox Uzaktan Oynama", full: false, id: 2)], target: .xbox)?.id, 2)
        XCTAssertEqual(GameWindowPicker.pick([win("Apple Hesabı", full: false, id: 1),
                                              win("Forza Horizon 5", full: true, id: 3)], target: .xbox)?.id, 3)
        XCTAssertNil(GameWindowPicker.pick([win("Apple Hesabı", full: false, id: 1)], target: .xbox))
    }

    /// Nino: "Xbox'ta oynuyorum": PS5 adımları atlanır, pencere yolu Xbox'la açılır; eski kayıtlar PS5 kalır.
    func testXboxWindowSetup() {
        let defaults = UserDefaults.isolated()
        let store = MemoryStore()
        let model = AppModel(services: FakeServices(), store: store, defaults: defaults)
        XCTAssertEqual(model.settings.gameConsole, .ps5)
        model.useXboxWindowSetup()
        // Xbox'ta oyun genelde TV'de: altyazı TV'ye gider, bu yüzden TV adımı sorulur.
        XCTAssertEqual(model.step, .tv)
        XCTAssertEqual(model.settings.videoSource, .window)
        XCTAssertTrue(model.usesXboxWindow)
        XCTAssertTrue(model.showsOnTV)
        XCTAssertFalse(model.showsOnComputer)
        XCTAssertFalse(model.canStart)
        model.back()
        XCTAssertEqual(model.step, .welcome)
        // "TV'm yok": altyazı bu bilgisayarda, pencerenin üstünde.
        model.settings.output = .computer
        XCTAssertTrue(model.canStart)
        XCTAssertTrue(model.showsOnComputer)
        model.step = .done
        let reopened = AppModel(services: FakeServices(), store: store, defaults: defaults)
        XCTAssertEqual(reopened.settings.gameConsole, .xbox)
        reopened.useGameWindowSetup()
        XCTAssertEqual(reopened.settings.gameConsole, .ps5)
    }

    /// Nino: kurulum önce konsolu sorar; Xbox'ta PS5 adımları atlanır, geri gelince Xbox karşılaması ve konsol seçimi görünür.
    func testConsoleChoiceComesFirst() {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: UserDefaults.isolated())
        XCTAssertEqual(model.step, .welcome)
        XCTAssertNil(model.welcomeConsole)
        XCTAssertFalse(model.canAdvance)
        model.chooseWelcomeConsole(.xbox)
        model.advance()
        XCTAssertEqual(model.step, .tv)
        XCTAssertTrue(model.usesXboxWindow)
        model.back()
        XCTAssertEqual(model.step, .welcome)
        XCTAssertEqual(model.welcomeConsole, .xbox)
        model.back()
        XCTAssertNil(model.welcomeConsole)
        model.chooseWelcomeConsole(.ps5)
        XCTAssertEqual(model.settings.videoSource, .ps5)
        XCTAssertEqual(model.settings.gameConsole, .ps5)
        model.advance()
        XCTAssertEqual(model.step, .secondAccount)
        // Sıfırlanınca yeniden konsol sorulur.
        model.resetSetup()
        XCTAssertEqual(model.step, .welcome)
        XCTAssertNil(model.welcomeConsole)
    }

    /// Nino: Ayarlar › Bağlantı'da Xbox'a geçince PS5'e doğrudan bağlanma bırakılır, Xbox penceresi okunur.
    func testSwitchConsoleInSettings() {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: UserDefaults.isolated())
        XCTAssertEqual(model.settings.videoSource, .ps5)
        model.switchConsole(to: .xbox)
        XCTAssertEqual(model.settings.gameConsole, .xbox)
        XCTAssertEqual(model.settings.videoSource, .window)
        model.settings.videoSource = .card
        model.switchConsole(to: .ps5)
        XCTAssertEqual(model.settings.videoSource, .card)
    }

    func testGameAreaBelowTitleBarAndLetterboxed() {
        // 1280 × 748 pencere: 28 pt başlık, altında 1280 × 720 oyun.
        XCTAssertEqual(GameArea.rect(windowSize: CGSize(width: 1280, height: 748), fillsScreen: false),
                       CGRect(x: 0, y: 28, width: 1280, height: 720))
        // Geniş pencere: oyun ortada, yanlarda siyah bant.
        let wide = GameArea.rect(windowSize: CGSize(width: 2000, height: 748), fillsScreen: false)
        XCTAssertEqual(wide.size, CGSize(width: 1280, height: 720))
        XCTAssertEqual(wide.midX, 1000)
        // Tam ekran 16:10: başlık yok, üstte ve altta bant.
        let full = GameArea.rect(windowSize: CGSize(width: 1440, height: 900), fillsScreen: true)
        XCTAssertEqual(full, CGRect(x: 0, y: 45, width: 1440, height: 810))
    }

    func testFullScreenOnNotchedDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertTrue(GameWindowCapture.fills(display, CGRect(x: 0, y: 32, width: 1512, height: 950)))
        XCTAssertFalse(GameWindowCapture.fills(display, CGRect(x: 100, y: 100, width: 1280, height: 748)))
    }

    func testStatusMapsToSessionState() {
        XCTAssertEqual(GameWindowStream.sessionState(for: .capturing(appName: "PS Remote Play")), .streaming)
        XCTAssertEqual(GameWindowStream.sessionState(for: .lookingForWindow), .connecting)
        XCTAssertEqual(GameWindowStream.sessionState(for: .needsPermission), .connecting)
    }

    /// Nino: Greenlight kurucusu GitHub yanıtından Mac dosyasını ve SHA-256 özetini seçer.
    func testGreenlightReleaseParsing() {
        let json = """
        {"assets":[{"name":"Greenlight-2.4.2-win.zip","size":1,"browser_download_url":"https://x/win.zip"},
        {"name":"Greenlight-2.4.2-universal.dmg","size":222606842,"digest":"sha256:ABC123",
        "browser_download_url":"https://x/Greenlight-2.4.2-universal.dmg"}]}
        """
        let release = GreenlightInstaller.release(fromJSON: Data(json.utf8))
        XCTAssertEqual(release?.url.lastPathComponent, "Greenlight-2.4.2-universal.dmg")
        XCTAssertEqual(release?.size, 222606842)
        XCTAssertEqual(release?.sha256, "abc123")
        XCTAssertNil(GreenlightInstaller.release(fromJSON: Data(#"{"assets":[]}"#.utf8)))
    }

    /// Nino: "Xbox'ı Bağla" adımları Greenlight'ın durumundan çıkar; yayın penceresi menüden önce seçilir.
    func testXboxConnectStepsAndGreenlightStreamWindow() {
        XCTAssertEqual(GreenlightProbe.step(installed: false, signedIn: false, streaming: false), .install)
        XCTAssertEqual(GreenlightProbe.step(installed: true, signedIn: false, streaming: false), .signIn)
        XCTAssertEqual(GreenlightProbe.step(installed: true, signedIn: true, streaming: false), .stream)
        XCTAssertEqual(GreenlightProbe.step(installed: true, signedIn: true, streaming: true), .done)

        XCTAssertTrue(GreenlightProbe.signedIn(configJSON: Data(#"{"user":{"tokenstore":"{\"userToken\":1}"}}"#.utf8)))
        XCTAssertFalse(GreenlightProbe.signedIn(configJSON: Data(#"{"user":{"tokenstore":"{}"}}"#.utf8)))
        XCTAssertFalse(GreenlightProbe.signedIn(configJSON: Data(#"{"settings":{}}"#.utf8)))

        XCTAssertTrue(GreenlightProbe.isStreamTitle("Greenlight - Streaming F4000F1E2D3C4B5A"))
        XCTAssertTrue(GreenlightProbe.isStreamTitle("Greenlight - Akış F4000F1E2D3C4B5A"))
        XCTAssertFalse(GreenlightProbe.isStreamTitle("Greenlight - My consoles"))
        XCTAssertFalse(GreenlightProbe.isStreamTitle("Greenlight"))

        func gl(_ title: String, _ w: CGFloat, id: CGWindowID) -> GameWindowInfo {
            GameWindowInfo(id: id, appName: "Greenlight", bundleID: "com.unknownskl.greenlight", title: title,
                           frame: CGRect(x: 0, y: 0, width: w, height: w * 9 / 16), fillsScreen: false)
        }
        XCTAssertEqual(GameWindowPicker.pick([gl("Greenlight - My consoles", 1600, id: 1),
                                              gl("Greenlight - Streaming F4000F1E2D3C4B5A", 1280, id: 2)], target: .xbox)?.id, 2)
        XCTAssertEqual(GameWindowPicker.pick([gl("Greenlight - My consoles", 1600, id: 1)], target: .xbox)?.id, 1)
    }
}
