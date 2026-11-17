// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// Ek alanlar: ana altyazıdan ayrı, seyrek okunur; yazı kararlıysa ve değiştiyse çevrilir (Windows: RegionWatcherTests.cs).
@MainActor
final class RegionWatcherTests: XCTestCase {
    /// Okunacak yazı test içinde değiştirilir.
    private final class Reader: TextReader, @unchecked Sendable {
        var lines: [TextLine] = []
        var count = 0
        var failuresRemaining = 0
        private enum Failure: Error { case expected }
        func read(_ image: CGImage) throws -> String { lines.map(\.text).joined(separator: "\n") }
        func read(_ image: CGImage, deep: Bool) throws -> String { try read(image) }
        func readLines(_ image: CGImage, deep: Bool) throws -> Reading {
            count += 1
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw Failure.expected
            }
            return Reading(lines: lines)
        }
    }

    private final class Translator: TextTranslator {
        var calls: [String] = []
        var failuresRemaining = 0
        func translate(_ text: String) async throws -> String {
            calls.append(text)
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw Failure.expected
            }
            return "TR: " + text
        }

        private enum Failure: Error { case expected }
    }

    private final class Server: RegionSending {
        var sent: [(id: String, text: String, box: TextBox?)] = []
        var lineHeights: [Double?] = []
        var clears = 0
        func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?) {
            sent.append((id, text, box))
            lineHeights.append(lineHeight)
        }
        func clearRegions() { clears += 1 }
    }

    /// Düz gri kare; `shade` değişince bölge izi değişir.
    private func frame(_ shade: UInt8) -> CGImage {
        let width = 320, height = 180
        var pixels = [UInt8](repeating: shade, count: width * height)
        let context = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        }
        return context!.makeImage()!
    }

    private let quest = ExtraArea(id: "q", name: "Quest", region: ExtraAreaPreset.quest.region)
    private func line(_ text: String, top: Double = 0.2, height: Double = 0.1) -> TextLine {
        TextLine(text, box: TextBox(left: 0.1, top: top, right: 0.9, bottom: top + height))
    }

    func testFailedReadRetriesOnAnUnchangedFrameThenStopsReading() async {
        let reader = Reader(), translator = Translator(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: translator, server: server)
        reader.lines = [line("Find the blacksmith")]
        reader.failuresRemaining = 1
        await watcher.pass(frame(10), areas: [quest])
        await watcher.pass(frame(10), areas: [quest])
        XCTAssertTrue(server.sent.isEmpty)
        for _ in 0..<4 { await watcher.pass(frame(10), areas: [quest]) }
        XCTAssertEqual(reader.count, 2)
        XCTAssertEqual(translator.calls, ["Find the blacksmith"])
        XCTAssertEqual(server.sent.map(\.text), ["TR: Find the blacksmith"])
    }

    func testFailedReadKeepsShownTextAndDiscardsUnconfirmedReading() async {
        let reader = Reader(), translator = Translator(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: translator, server: server)
        reader.lines = [line("Talk to Arthur")]
        await watcher.pass(frame(10), areas: [quest])
        await watcher.pass(frame(10), areas: [quest])
        reader.lines = [line("Meet Arthur at the barn")]
        await watcher.pass(frame(60), areas: [quest])
        reader.failuresRemaining = 1
        await watcher.pass(frame(100), areas: [quest])
        reader.lines = [line("Find the blacksmith")]
        await watcher.pass(frame(100), areas: [quest])
        XCTAssertEqual(server.sent.map(\.text), ["TR: Talk to Arthur"])
        await watcher.pass(frame(100), areas: [quest])
        XCTAssertEqual(translator.calls, ["Talk to Arthur", "Find the blacksmith"])
        XCTAssertEqual(server.sent.map(\.text), ["TR: Talk to Arthur", "TR: Find the blacksmith"])
    }

    func testFailedReadDoesNotBlockAnotherArea() async {
        let reader = Reader(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: Translator(), server: server)
        let phone = ExtraArea(id: "p", name: "Phone", region: ExtraAreaPreset.phone.region)
        reader.lines = [line("Find the blacksmith")]
        reader.failuresRemaining = 1
        await watcher.pass(frame(10), areas: [quest, phone])
        await watcher.pass(frame(10), areas: [quest, phone])
        XCTAssertEqual(server.sent.map(\.id), ["p"])
        await watcher.pass(frame(10), areas: [quest, phone])
        XCTAssertEqual(server.sent.map(\.id), ["p", "q"])
        XCTAssertEqual(reader.count, 3)
    }

    func testRepeatedReadFailuresStillRespectThePassInterval() async {
        var clock = 0
        let reader = Reader(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: Translator(), server: server, clock: { clock })
        reader.failuresRemaining = 10
        for step in 0...20 {
            clock = step * 100
            watcher.offer(frame(10), areas: [quest])
            while watcher.isBusy { await Task.yield() }
        }
        XCTAssertEqual(watcher.passes, 3)
        XCTAssertEqual(reader.count, 3)
        XCTAssertTrue(server.sent.isEmpty)
    }

    func testStableTextIsTranslatedOnceAndPlacedInItsArea() async {
        let reader = Reader(), translator = Translator(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: translator, server: server)
        reader.lines = [line("Find the blacksmith")]
        await watcher.pass(frame(10), areas: [quest])
        XCTAssertTrue(server.sent.isEmpty, "ilk okuma kararlı sayılmaz")
        await watcher.pass(frame(10), areas: [quest])
        XCTAssertEqual(server.sent.map(\.text), ["TR: Find the blacksmith"])
        let box = server.sent[0].box!
        XCTAssertGreaterThan(box.left, quest.region.left)
        XCTAssertLessThan(box.right, quest.region.right)
        // Kare değişmedikçe ne okunur ne çevrilir.
        await watcher.pass(frame(10), areas: [quest])
        await watcher.pass(frame(10), areas: [quest])
        XCTAssertEqual(reader.count, 1)
        XCTAssertEqual(translator.calls.count, 1)
        XCTAssertEqual(server.sent.count, 1)
    }

    func testSameTextAtNewGeometryUpdatesRegionWithoutRetranslating() async {
        let reader = Reader(), translator = Translator(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: translator, server: server)
        reader.lines = [line("Find the blacksmith", top: 0.2, height: 0.1)]
        await watcher.pass(frame(10), areas: [quest])
        await watcher.pass(frame(10), areas: [quest])
        let firstBox = server.sent[0].box!
        let firstHeight = server.lineHeights[0]!

        reader.lines = [line("Find the blacksmith", top: 0.45, height: 0.2)]
        await watcher.pass(frame(60), areas: [quest])

        XCTAssertEqual(server.sent.map(\.text), ["TR: Find the blacksmith", "TR: Find the blacksmith"])
        XCTAssertNotEqual(server.sent[1].box?.top, firstBox.top)
        XCTAssertNotEqual(server.lineHeights[1], firstHeight)
        XCTAssertEqual(translator.calls, ["Find the blacksmith"])
    }

    func testFailedTranslationRetriesWithoutLosingPreviouslyShownText() async {
        let reader = Reader(), translator = Translator(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: translator, server: server)
        reader.lines = [line("Talk to Arthur")]
        await watcher.pass(frame(10), areas: [quest])
        await watcher.pass(frame(10), areas: [quest])
        XCTAssertEqual(server.sent.map(\.text), ["TR: Talk to Arthur"])

        reader.lines = [line("Meet Arthur at the barn")]
        translator.failuresRemaining = 1
        await watcher.pass(frame(90), areas: [quest])
        await watcher.pass(frame(90), areas: [quest])
        XCTAssertEqual(server.sent.map(\.text), ["TR: Talk to Arthur"])

        await watcher.pass(frame(90), areas: [quest])
        XCTAssertEqual(translator.calls, ["Talk to Arthur", "Meet Arthur at the barn", "Meet Arthur at the barn"])
        XCTAssertEqual(server.sent.map(\.text), ["TR: Talk to Arthur", "TR: Meet Arthur at the barn"])
    }

    func testMovingBackgroundWithTheSameTextIsNotTranslatedAgain() async {
        let reader = Reader(), translator = Translator(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: translator, server: server)
        reader.lines = [line("Talk to Arthur")]
        for shade: UInt8 in [10, 60, 110, 160, 210] { await watcher.pass(frame(shade), areas: [quest]) }
        XCTAssertEqual(reader.count, 5)
        XCTAssertEqual(translator.calls, ["Talk to Arthur"])
        XCTAssertEqual(server.sent.map(\.text), ["TR: Talk to Arthur"])
    }

    func testChangedTextIsTranslatedAndEmptyAreaRemovesTheBox() async {
        let reader = Reader(), translator = Translator(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: translator, server: server)
        reader.lines = [line("Talk to Arthur")]
        await watcher.pass(frame(10), areas: [quest])
        await watcher.pass(frame(10), areas: [quest])
        reader.lines = [line("Meet Arthur at the barn")]
        await watcher.pass(frame(90), areas: [quest])
        await watcher.pass(frame(90), areas: [quest])
        reader.lines = []
        await watcher.pass(frame(200), areas: [quest])
        await watcher.pass(frame(200), areas: [quest])
        XCTAssertEqual(server.sent.map(\.text), ["TR: Talk to Arthur", "TR: Meet Arthur at the barn", ""])
    }

    func testPromptsNumbersAndUntranslatedTextShowNothing() async {
        let reader = Reader(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: Translator(), server: server)
        reader.lines = [line("R2 Swing"), line("23m", top: 0.5)]
        await watcher.pass(frame(10), areas: [quest])
        await watcher.pass(frame(10), areas: [quest])
        XCTAssertTrue(server.sent.isEmpty)
    }

    func testPackTranslationIsUsedBeforeTheEngine() async {
        let reader = Reader(), translator = Translator(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: translator, server: server)
        watcher.packLookup = { $0 == "New message" ? PackMatch(text: "Yeni mesaj", spoken: []) : nil }
        reader.lines = [line("New message", top: 0.1), line("Call me when you get this.", top: 0.25)]
        await watcher.pass(frame(10), areas: [quest])
        await watcher.pass(frame(10), areas: [quest])
        XCTAssertEqual(server.sent.map(\.text), ["Yeni mesaj\nTR: Call me when you get this."])
        XCTAssertEqual(translator.calls, ["Call me when you get this."])
    }

    func testRemovedAreaLosesItsBoxAndResetClearsAll() async {
        let reader = Reader(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: Translator(), server: server)
        let phone = ExtraArea(id: "p", name: "Phone", region: ExtraAreaPreset.phone.region)
        reader.lines = [line("Where are you?")]
        await watcher.pass(frame(10), areas: [quest, phone])
        await watcher.pass(frame(10), areas: [quest, phone])
        XCTAssertEqual(Set(server.sent.map(\.id)), ["q", "p"])
        await watcher.pass(frame(10), areas: [quest])
        XCTAssertEqual(server.sent.last?.id, "p")
        XCTAssertEqual(server.sent.last?.text, "")
        watcher.reset()
        XCTAssertEqual(server.clears, 1)
        watcher.reset()
        XCTAssertEqual(server.clears, 1, "gösterilen kutu yoksa temizleme gönderilmez")
    }

    func testOfferRunsAtMostOncePerInterval() async {
        var clock = 0
        let reader = Reader(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: Translator(), server: server, clock: { clock })
        reader.lines = [line("Find the blacksmith")]
        let image = frame(10)
        watcher.offer(image, areas: [quest])
        while watcher.isBusy { await Task.yield() }
        for step in 1...9 {
            clock = step * 100
            watcher.offer(image, areas: [quest])
            while watcher.isBusy { await Task.yield() }
        }
        XCTAssertEqual(watcher.passes, 1)
        clock = 1000
        watcher.offer(image, areas: [quest])
        while watcher.isBusy { await Task.yield() }
        XCTAssertEqual(watcher.passes, 2)
        XCTAssertEqual(server.sent.map(\.text), ["TR: Find the blacksmith"])
    }

    func testNoAreasMeansNoWork() async {
        let reader = Reader()
        let watcher = RegionWatcher(reader: reader, translator: Translator(), server: Server())
        watcher.offer(frame(10), areas: [])
        XCTAssertFalse(watcher.isBusy)
        XCTAssertEqual(reader.count, 0)
    }

    func testSettingsHaveNoExtraAreasByDefaultAndKeepAtMostThree() throws {
        XCTAssertTrue(UserSettings().extraAreas.isEmpty)
        var settings = UserSettings()
        for preset in ExtraAreaPreset.allCases { XCTAssertNotNil(settings.addExtraArea(preset, name: preset.rawValue)) }
        XCTAssertNil(settings.addExtraArea(.quest, name: "fourth"))
        XCTAssertEqual(settings.extraAreas.count, ExtraArea.maxCount)
        settings.updateExtraArea(id: settings.extraAreas[1].id) { $0.enabled = false }
        XCTAssertEqual(settings.activeExtraAreas.map(\.name), ["quest", "phone"])
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.extraAreas, settings.extraAreas)
        // Eski kayıt: alan yok.
        let old = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"sourceLanguage":"en"}"#.utf8))
        XCTAssertTrue(old.extraAreas.isEmpty)
    }
}
