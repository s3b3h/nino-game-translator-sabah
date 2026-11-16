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
}
