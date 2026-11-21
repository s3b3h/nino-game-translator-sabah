// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// Nino: oyundaki telefonun (GTA 6) sohbeti ve haritanın görev kartı iPhone'da da çevrilir (Mac'teki kurallarla).
@MainActor
final class PhoneWatcherTests: XCTestCase {
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [String] = []
        func add(_ text: String) { lock.withLock { list.append(text) } }
        var all: [String] { lock.withLock { list } }
    }

    private func frame(_ name: String) throws -> CGImage {
        try XCTUnwrap(RealPhoneFrameTestsHelper.frame(name))
    }

    private func watcher(_ calls: Calls, remember: Bool = true, memoryFile: URL? = nil) -> PhoneWatcher {
        let watcher = PhoneWatcher(reader: VisionReader(language: "en", cpuOnly: true), memoryFile: memoryFile) { text, _ in
            calls.add(text)
            return .init(text: "TR " + text, remember: remember)
        }
        watcher.useGlossary = false
        return watcher
    }

    func testChatIsTranslatedBesideThePhoneAfterTwoSameReadings() async throws {
        let image = try frame("gta6-telefon-brian-parlama.jpg")
        let calls = Calls()
        let watcher = watcher(calls)
        var changes: [[ScreenTranslation.Item]] = []
        var unknown: [String] = []
        watcher.onChange = { changes.append($0) }
        watcher.onUnknown = { unknown += $0 }
        // İlk okuma yalnız bekletir (kaydırma sürerken yarım okunan satır çevrilmez).
        await watcher.check(image, started: 0)
        XCTAssertTrue(watcher.items.isEmpty)
        XCTAssertTrue(calls.all.isEmpty)
        await watcher.check(image, started: 0)
        XCTAssertFalse(watcher.items.isEmpty)
        XCTAssertFalse(calls.all.isEmpty)
        XCTAssertEqual(Set(unknown), Set(calls.all), "çeviriler aynı anda yapılır, sıra önemsiz")
        // İlk öğe panelin zeminidir; balonlar telefonun yanında.
        XCTAssertTrue(watcher.items.contains { $0.backdrop })
        XCTAssertTrue(watcher.items.contains { $0.translation.hasPrefix("TR ") })
        XCTAssertEqual(changes.last, watcher.items)
        XCTAssertFalse(watcher.recentTexts.isEmpty, "telefon yazıları altyazı sayılmasın")
        // Aynı ekran yeniden okununca çevirmene gidilmez.
        let before = calls.all.count
        await watcher.check(image, started: 0)
        XCTAssertEqual(calls.all.count, before)
    }

    func testRememberedTranslationsComeBackFromTheFile() async throws {
        let image = try frame("gta6-telefon-brian-parlama.jpg")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("phone-memory-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let first = watcher(Calls(), memoryFile: file)
        await first.check(image, started: 0)
        await first.check(image, started: 0)
        XCTAssertFalse(first.items.isEmpty)
        // Nino yeniden açıldı: hafızadan gelir, çevirmene gidilmez.
        let calls = Calls()
        let second = watcher(calls, memoryFile: file)
        await second.check(image, started: 0)
        await second.check(image, started: 0)
        XCTAssertFalse(second.items.isEmpty)
        XCTAssertTrue(calls.all.isEmpty, "\(calls.all)")
    }

    func testDeviceFallbackIsNotRemembered() async throws {
        let image = try frame("gta6-telefon-brian-parlama.jpg")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("phone-memory-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let first = watcher(Calls(), remember: false, memoryFile: file)
        await first.check(image, started: 0)
        await first.check(image, started: 0)
        XCTAssertFalse(first.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testMapScreenIsNotAPhone() async throws {
        let calls = Calls()
        let watcher = watcher(calls)
        watcher.paused = { true }
        watcher.offer(try frame("gta6-telefon-brian-parlama.jpg"))
        XCTAssertFalse(watcher.isBusy, "harita açıkken telefon aranmaz")
        XCTAssertTrue(calls.all.isEmpty)
    }

    func testResetClearsAndDropsTheRunningResult() async throws {
        let image = try frame("gta6-telefon-brian-parlama.jpg")
        let watcher = watcher(Calls())
        await watcher.check(image, started: 0)
        await watcher.check(image, started: 0)
        XCTAssertFalse(watcher.items.isEmpty)
        var cleared = false
        watcher.onChange = { cleared = $0.isEmpty }
        watcher.reset()
        XCTAssertTrue(watcher.items.isEmpty)
        XCTAssertTrue(cleared)
        XCTAssertTrue(watcher.recentTexts.isEmpty)
        // Eski oturumun okuması (started: 0) yeni oturuma yazılmaz.
        await watcher.check(image, started: 0)
        await watcher.check(image, started: 0)
        XCTAssertTrue(watcher.items.isEmpty)
    }

    func testIconsAndEntitiesAreStripped() {
        XCTAssertEqual(PhoneWatcher.withoutIcons("Tamam &amp; ✕ geliyorum"), "Tamam & geliyorum")
        XCTAssertEqual(PhoneWatcher.withoutEntities("Don&#39;t"), "Don't")
    }
}

@MainActor
final class MapCardWatcherTests: XCTestCase {
    private func card() throws -> (MapCard.Found, CGImage) {
        let image = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-harita-buckme.jpg"))
        let reading = try VisionReader(language: "en", cpuOnly: true).readLines(image, deep: false)
        return (try XCTUnwrap(MapCard.find(in: reading)), image)
    }

    func testCardTranslationGoesUnderTheCard() async throws {
        let (card, image) = try card()
        let watcher = MapCardWatcher { "Türkçe " + $0 }
        watcher.show(card, frame: image)
        await watcher.waitUntilIdle()
        let item = try XCTUnwrap(watcher.items.first)
        XCTAssertTrue(item.card)
        XCTAssertGreaterThan(item.box.top, card.box.bottom, "kartın altında")
        XCTAssertTrue(item.translation.hasPrefix("TÜRKÇE "), item.translation)
        XCTAssertEqual(item.translation.split(separator: "\n").count, 1 + card.sentences.count)
    }

    func testSameCardIsNotTranslatedTwice() async throws {
        let (card, image) = try card()
        let calls = Counter()
        let watcher = MapCardWatcher { calls.bump(); return "x " + $0 }
        watcher.show(card, frame: image)
        await watcher.waitUntilIdle()
        let count = calls.value
        watcher.clear()
        watcher.show(card, frame: image)
        await watcher.waitUntilIdle()
        XCTAssertEqual(calls.value, count, "hafızadan gelir")
        XCTAssertFalse(watcher.items.isEmpty)
    }

    func testClosedMapShowsNothing() async throws {
        let (card, image) = try card()
        let watcher = MapCardWatcher { $0 }
        watcher.isMapOpen = { false }
        watcher.show(card, frame: image)
        await watcher.waitUntilIdle()
        XCTAssertTrue(watcher.items.isEmpty)
    }

    func testPlaceNamesAndTermsAreKept() {
        XCTAssertTrue(MapCardWatcher.isPlaceName("RIDEOUT CUSTOMS"))
        XCTAssertFalse(MapCardWatcher.isPlaceName("JASON'S MAILBOX"))
        XCTAssertEqual(MapCardWatcher.withMapTerms("işaretli faturalar"), "işaretli banknotlar")
    }

    func testScreenHintsHandsTheMapCardOver() async throws {
        let (_, image) = try card()
        let hints = ScreenHints(reader: VisionReader(language: "en", edgeIcons: true), menuReader: VisionReader(language: "en")) { text, _ in text }
        var found: MapCard.Found?
        hints.onMap = { card, _ in found = card }
        // Menü üç turda bir okunur.
        for _ in 0..<3 { await hints.pass(image) }
        XCTAssertEqual(found?.title, "DEPOSIT CASH INTO BUCKME")
        XCTAssertTrue(hints.menuFlag.active, "harita da menü sayılır")
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }
}
