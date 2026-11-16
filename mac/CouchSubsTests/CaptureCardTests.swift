// SPDX-License-Identifier: AGPL-3.0-only
// Nino: yakalama kartı kaynağının sınamaları (sıfırdan yazıldı).

import CouchSubsCore
import XCTest
@testable import Nino

@MainActor
final class CaptureCardTests: XCTestCase {
    private func card(_ name: String, id: String = UUID().uuidString, model: String = "") -> CaptureCardInfo {
        CaptureCardInfo(id: id, name: name, modelID: model)
    }

    /// Kartı olan kullanıcı ilk ekrandan kurulumu bitirir; PS5 eşleştirmesi gerekmez, altyazı bilgisayarda.
    func testSetupWithCaptureCard() {
        let defaults = UserDefaults.isolated()
        let store = MemoryStore()
        let model = AppModel(services: FakeServices(), store: store, defaults: defaults)
        XCTAssertFalse(model.canStart)
        model.useCaptureCardSetup()
        XCTAssertTrue(model.cardSetupActive)
        XCTAssertEqual(model.step, .welcome)
        model.finishCaptureCardSetup(toTV: false)
        XCTAssertFalse(model.cardSetupActive)
        // Bilgisayar seçildi: TV adımı atlanır, deneme adımına geçilir.
        XCTAssertEqual(model.step, .test)
        model.step = .done
        XCTAssertTrue(model.usesCaptureCard)
        XCTAssertTrue(model.canStart)
        XCTAssertTrue(model.showsOnComputer)
        XCTAssertFalse(model.showsOnTV)
        let reopened = AppModel(services: FakeServices(), store: store, defaults: defaults)
        XCTAssertEqual(reopened.step, .done)
        XCTAssertEqual(reopened.settings.videoSource, .card)
    }

    /// Kartla altyazı TV'ye de gidebilir (geçişli kart: PS5 → kart → TV); oyun penceresi yolunda gidemez.
    func testCardCanSendToTV() {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: UserDefaults.isolated())
        model.useCaptureCardSetup()
        model.finishCaptureCardSetup(toTV: true)
        // TV seçildi ama TV eşleşmemiş: TV adımına geçilir.
        XCTAssertEqual(model.step, .tv)
        XCTAssertTrue(model.showsOnTV)
        XCTAssertFalse(model.showsOnComputer)
    }

    /// Kart rehberinden geri dönülünce PS5 adımları sürer; seçilen aygıt yeniden açılışta hatırlanır.
    func testCancelGuideAndRememberDevice() {
        let defaults = UserDefaults.isolated()
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: defaults)
        model.useCaptureCardSetup()
        model.cancelCaptureCardSetup()
        XCTAssertFalse(model.cardSetupActive)
        XCTAssertEqual(model.settings.videoSource, .ps5)
        model.preferredCardID = "card-1"
        XCTAssertEqual(AppModel(services: FakeServices(), store: MemoryStore(), defaults: defaults).preferredCardID, "card-1")
    }

    /// PS5 yolunda altyazının yeri seçilmez; PS5'e dönülünce altyazı TV'ye gider.
    func testBackToPS5SendsSubtitlesToTV() {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: UserDefaults.isolated())
        model.settings.videoSource = .card
        model.settings.output = .computer
        model.settings.videoSource = .ps5
        XCTAssertEqual(model.settings.output, .tv)
        XCTAssertTrue(model.showsOnTV)
    }

    func testPrefersCaptureCardOverWebcam() {
        let picked = CaptureCardPicker.pick([card("Logitech BRIO"), card("USB Video", id: "card")])
        XCTAssertEqual(picked?.id, "card")
        XCTAssertEqual(CaptureCardPicker.pick([card("Elgato HD60 X", id: "e"), card("Some Device")])?.id, "e")
    }

    func testFallsBackToFirstDeviceAndHonoursChoice() {
        XCTAssertEqual(CaptureCardPicker.pick([card("Mystery", id: "m")])?.id, "m")
        XCTAssertNil(CaptureCardPicker.pick([card("FaceTime HD Camera")]))
        XCTAssertNil(CaptureCardPicker.pick([]))
        let chosen = CaptureCardPicker.pick([card("Elgato HD60 X", id: "e"), card("Mystery", id: "m")], preferred: "m")
        XCTAssertEqual(chosen?.id, "m")
    }

    func testMatchesCardAudioByUSBIdThenName() {
        let video = card("USB Video", id: "v", model: "UVC Camera VendorID_13407 ProductID_8496")
        let audios = [card("MacBook Pro Microphone", id: "mic"), card("USB Digital Audio", id: "a", model: video.modelID)]
        XCTAssertEqual(CaptureCardPicker.audio(for: video, in: audios)?.id, "a")
        let elgato = card("Elgato HD60 X", id: "v2")
        XCTAssertEqual(CaptureCardPicker.audio(for: elgato, in: [card("MacBook Pro Microphone"), card("Elgato HD60 X", id: "a2")])?.id, "a2")
        XCTAssertNil(CaptureCardPicker.audio(for: elgato, in: [card("MacBook Pro Microphone")]))
    }

    func testBlackFrameDetection() {
        let width = 64, height = 36, row = width * 4
        var pixels = [UInt8](repeating: 0, count: row * height)
        XCTAssertTrue(pixels.withUnsafeBytes { BlackFrame.isBlack($0.baseAddress!, width: width, height: height, bytesPerRow: row, step: 4) })
        // Tek parlak nokta (altyazı yazısı gibi) karenin siyah sayılmamasına yeter.
        let y = 18, x = 18
        pixels[y * row + x * 4 + 1] = 200
        XCTAssertFalse(pixels.withUnsafeBytes { BlackFrame.isBlack($0.baseAddress!, width: width, height: height, bytesPerRow: row, step: 4) })
    }

    /// Oyun penceresindeki 16:9 alan ekran koordinatına (sol üst başlangıç) çevrilir; geniş ekranda yanlarda bant kalır.
    func testPlayerGameArea() {
        let full = CaptureCardPlayer.gameArea(content: CGRect(x: 0, y: 0, width: 1920, height: 1080), primaryHeight: 1080)
        XCTAssertEqual(full, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let wide = CaptureCardPlayer.gameArea(content: CGRect(x: 0, y: 0, width: 3440, height: 1440), primaryHeight: 1440)
        XCTAssertEqual(wide, CGRect(x: 440, y: 0, width: 2560, height: 1440))
        // Pencere ekranın altında (AppKit'te sol alt başlangıç): üstten 400 nokta aşağıda.
        let small = CaptureCardPlayer.gameArea(content: CGRect(x: 100, y: 100, width: 1280, height: 720), primaryHeight: 1220)
        XCTAssertEqual(small, CGRect(x: 100, y: 400, width: 1280, height: 720))
    }
}
