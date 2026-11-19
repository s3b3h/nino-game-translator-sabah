// SPDX-License-Identifier: AGPL-3.0-only
#if canImport(CoreGraphics)
import CoreGraphics
import XCTest
@testable import CouchSubsCore

private final class PlacedReader: TextReader, @unchecked Sendable {
    let line: TextLine
    init(_ line: TextLine) { self.line = line }
    func read(_ image: CGImage) throws -> String { line.text }
    func readLines(_ image: CGImage, deep: Bool) throws -> Reading { Reading(lines: [line]) }
}
private final class FloorSender: SubtitleSending {
    var sent: [String] = []
    func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) { sent.append(text) }
    func clear() {}
}
private final class FloorTranslator: TextTranslator, @unchecked Sendable {
    var requested: [String] = []
    func translate(_ text: String) async throws -> String { requested.append(text); return "Türkçe çeviri burada." }
}

/// Altyazının yerinde olmayan (tabanın epey üstünde biten) blok yalnız pakette biliniyorsa gösterilir.
@MainActor
final class SubtitleFloorTests: XCTestCase {
    private var image: CGImage {
        CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
    private let whole = CropRegion(top: 0, bottom: 1, left: 0, right: 1)

    private func run(_ text: String, top: Double, bottom: Double, floor: Double?, known: Bool = false) async
        -> (sent: [String], requested: [String], offered: [String]) {
        var time = 0
        let translator = FloorTranslator(), sender = FloorSender()
        let line = TextLine(text, box: TextBox(left: 0.3, top: top, right: 0.7, bottom: bottom))
        let pipeline = SubtitlePipeline(reader: PlacedReader(line), translator: translator, server: sender, clock: { time })
        pipeline.packWait = 0; pipeline.cleanWait = 0
        pipeline.subtitleFloor = floor
        var offered: [String] = []
        pipeline.onPackMiss = { offered.append($0) }
        if ProcessInfo.processInfo.environment["NINO_LOG"] != nil { pipeline.onLog = { print("GÜNLÜK", $0) } }
        if known { pipeline.packLookup = { _ in PackMatch(text: "Paketten", spoken: []) } }
        for _ in 0..<6 { await pipeline.process(image, region: whole); await pipeline.waitForTranslations(); time += 150 }
        return (sender.sent, translator.requested, offered)
    }

    func testSignAboveTheSubtitlePlaceIsNotTranslated() async {
        let result = await run("Pick a focal flower and add a few accents.", top: 0.62, bottom: 0.655, floor: 0.845)
        XCTAssertTrue(result.sent.isEmpty)
        XCTAssertTrue(result.requested.isEmpty)
        // Temiz okunan yazı havuza önerilir: bir dahaki sefere bilinir.
        XCTAssertEqual(result.offered, ["Pick a focal flower and add a few accents."])
    }

    func testDialogueAtTheSubtitlePlaceIsTranslated() async {
        let result = await run("You trying to kill me?", top: 0.881, bottom: 0.916, floor: 0.845)
        XCTAssertEqual(result.sent, ["Türkçe çeviri burada."])
    }

    func testKnownTextAboveTheSubtitlePlaceIsStillShown() async {
        let result = await run("The size of the minimap on the HUD.", top: 0.62, bottom: 0.655, floor: 0.845, known: true)
        XCTAssertEqual(result.sent, ["Paketten"])
    }

    /// Haritanın ortasında okunan tek sözcük pakette bir repliğe benzese de ("Chest." → "Göğüs.") gösterilmez.
    func testShortKnownTextAboveTheSubtitlePlaceIsNotShown() async {
        let result = await run("Chest.", top: 0.62, bottom: 0.655, floor: 0.845, known: true)
        XCTAssertTrue(result.sent.isEmpty)
    }

    func testShortKnownDialogueAtTheSubtitlePlaceIsShown() async {
        let result = await run("Chest.", top: 0.881, bottom: 0.916, floor: 0.845, known: true)
        XCTAssertEqual(result.sent, ["Paketten"])
    }

    func testWithoutAFloorEverythingIsTranslated() async {
        let result = await run("Pick a focal flower and add a few accents.", top: 0.62, bottom: 0.655, floor: nil)
        XCTAssertEqual(result.sent, ["Türkçe çeviri burada."])
    }
}
#endif
