// SPDX-License-Identifier: AGPL-3.0-only
import CouchSubsCore
import SwiftUI
import XCTest
@testable import Nino

@MainActor
final class DownloadCounterTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "download-counter-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testParsesTheServerReply() {
        XCTAssertEqual(DownloadCounter.parse(Data(#"{"ok":true,"downloads":3439}"#.utf8)), 3439)
        XCTAssertNil(DownloadCounter.parse(Data(#"{"ok":true}"#.utf8)))
        XCTAssertNil(DownloadCounter.parse(Data(#"{"downloads":0}"#.utf8)))
        XCTAssertNil(DownloadCounter.parse(Data("bozuk".utf8)))
    }

    /// Sayı alınamazsa son bilinen sayı kalır; yeniden açılışta da oradan başlar. Üstüne ekleme yapılmaz.
    func testKeepsTheLastKnownTotalWhenTheServerCannotBeReached() async {
        let store = defaults()
        let reply = Box(Data(#"{"downloads":3439}"#.utf8))
        let counter = DownloadCounter(defaults: store, endpoint: URL(string: "https://example.invalid"), fetch: { _ in reply.value })
        XCTAssertNil(counter.total)
        await counter.refresh(now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(counter.total, 3439)
        reply.value = nil
        await counter.refresh(now: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(counter.total, 3439)
        XCTAssertEqual(DownloadCounter(defaults: store, endpoint: nil, fetch: { _ in nil }).total, 3439)
    }

    /// Bekleme ekranı çizilebiliyor (ve istenirse göz denetimi için dosyaya yazılır: NINO_RENDER_DIR).
    func testStandbyScreenRenders() throws {
        let view = TVStandbyScreen(downloads: 3439).frame(width: 626, height: 324).environment(\.locale, Locale(identifier: "tr"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, 0)
        if let dir = ProcessInfo.processInfo.environment["NINO_RENDER_DIR"],
           let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("tv-bekleme.png"))
        }
    }
}

@MainActor
final class PlugTests: XCTestCase {
    private let socket = CGPoint(x: 1564, y: 378), rest = CGPoint(x: 1600, y: 885)

    /// Fiş dinlenirken aşağı bakar; prize yaklaştıkça uçları prize döner (eskiden hep aşağı bakıyordu).
    func testPlugTurnsTowardTheSocketAsItGetsCloser() {
        XCTAssertEqual(LivingRoomScene.plugTurn(plug: rest, socket: socket, rest: rest), 0, accuracy: 0.001)
        // Prizden uzaklaşınca (aşağı/sağa çekilince) dönmez.
        XCTAssertEqual(LivingRoomScene.plugTurn(plug: CGPoint(x: 1640, y: 930), socket: socket, rest: rest), 0, accuracy: 0.001)
        // Prizin hemen altında: uçlar yukarı (prize) bakar: (−sin θ, cos θ) ≈ (0, −1).
        let below = LivingRoomScene.plugTurn(plug: CGPoint(x: 1564, y: 470), socket: socket, rest: rest)
        XCTAssertEqual(-sin(below), 0, accuracy: 0.05)
        XCTAssertEqual(cos(below), -1, accuracy: 0.05)
        // Prizin solunda: uçlar sağa bakar.
        let left = LivingRoomScene.plugTurn(plug: CGPoint(x: 1460, y: 378), socket: socket, rest: rest)
        XCTAssertEqual(-sin(left), 1, accuracy: 0.05)
        // Yol ortasında kısmen dönmüştür.
        let mid = abs(LivingRoomScene.plugTurn(plug: CGPoint(x: 1585, y: 640), socket: socket, rest: rest))
        XCTAssertGreaterThan(mid, 0.2)
        XCTAssertLessThan(mid, Double.pi - 0.2)
    }

    /// Göz denetimi: sahnenin fiş bölgesi dört durumda dosyaya çizilir (NINO_RENDER_DIR verilmişse).
    func testSceneRendersForVisualCheck() throws {
        guard let dir = ProcessInfo.processInfo.environment["NINO_RENDER_DIR"] else { throw XCTSkip("NINO_RENDER_DIR yok") }
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        for (name, console, drag) in [("ps5-dinlenme", GameConsole.ps5, CGSize.zero), ("ps5-yolda", .ps5, CGSize(width: -15, height: -250)),
                                      ("ps5-yakin", .ps5, CGSize(width: -30, height: -410)), ("xbox-dinlenme", .xbox, .zero),
                                      ("xbox-yakin", .xbox, CGSize(width: -80, height: -430))] {
            model.settings.gameConsole = console
            let view = LivingRoomScene(available: LivingRoomScene.canvas, drag: drag).environmentObject(model)
                .frame(width: LivingRoomScene.canvas.width + 120, height: LivingRoomScene.canvas.height + 40, alignment: .topLeading)
                .background(Color(red: 0.86, green: 0.9, blue: 0.97))
            let renderer = ImageRenderer(content: view)
            let image = try XCTUnwrap(renderer.nsImage)
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fis-\(name).png"))
        }
    }
}

private final class Box<T>: @unchecked Sendable {
    var value: T?
    init(_ value: T?) { self.value = value }
}
