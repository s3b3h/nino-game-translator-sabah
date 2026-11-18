// SPDX-License-Identifier: AGPL-3.0-only
// Nino: çeviri havuzundan sonradan gelen çeviri ekrandaki satırın yerine konur (TV'ye `replaces: true`).
#if canImport(CoreGraphics)
import CoreGraphics
import XCTest
@testable import CouchSubsCore

private final class UpgradeReader: TextReader, @unchecked Sendable {
    var texts: [String]
    init(_ texts: [String]) { self.texts = texts }
    func read(_ image: CGImage) throws -> String { texts.isEmpty ? "" : texts.removeFirst() }
}
private final class UpgradeSender: SubtitleSending {
    var sent: [(text: String, replaces: Bool)] = []
    func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) { sent.append((text, replaces)) }
    func clear() {}
}
private final class UpgradeTranslator: TextTranslator {
    func translate(_ text: String) async throws -> String { "Cihaz: " + text }
}

@MainActor
final class PoolUpgradeTests: XCTestCase {
    private var image: CGImage {
        CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    func testPoolTranslationReplacesLineStillOnScreen() async {
        var time = 0
        let line = "Who the fuck are you?"
        let sender = UpgradeSender()
        let pipeline = SubtitlePipeline(reader: UpgradeReader(Array(repeating: line, count: 4)), translator: UpgradeTranslator(),
                                        server: sender, clock: { time })
        var missed: [String] = []
        pipeline.onPackMiss = { missed.append($0) }
        pipeline.packWait = 0; pipeline.cleanWait = 0
        for _ in 0..<4 { await pipeline.process(image, region: CropRegion()); await pipeline.waitForTranslations(); time += 100 }
        XCTAssertEqual(missed, [line])
        XCTAssertEqual(sender.sent.map(\.text), ["Cihaz: " + line])
        pipeline.upgrade(source: line, translation: "Sen de kimsin lan?")
        XCTAssertEqual(sender.sent.last?.text, "Sen de kimsin lan?")
        XCTAssertEqual(sender.sent.last?.replaces, true)
        XCTAssertEqual(pipeline.lastPair?.translation, "Sen de kimsin lan?")
        // Aynı çeviri ikinci kez gelirse yeniden gönderilmez.
        pipeline.upgrade(source: line, translation: "Sen de kimsin lan?")
        XCTAssertEqual(sender.sent.count, 2)
    }

    func testUpgradeForOldLineDoesNotTouchScreen() async {
        var time = 0
        let first = "Get in the car!", second = "Drive, drive, drive!"
        let sender = UpgradeSender()
        let frames = Array(repeating: first, count: 3) + Array(repeating: second, count: 3)
        let pipeline = SubtitlePipeline(reader: UpgradeReader(frames), translator: UpgradeTranslator(), server: sender, clock: { time })
        pipeline.packWait = 0; pipeline.cleanWait = 0
        for _ in frames { await pipeline.process(image, region: CropRegion()); await pipeline.waitForTranslations(); time += 100 }
        let before = sender.sent.count
        pipeline.upgrade(source: first, translation: "Bin arabaya!")
        XCTAssertEqual(sender.sent.count, before, "ekrandan kalkmış satır yeniden gösterilmez")
    }

    func testEngineResultYieldsToPoolTranslationThatArrivedFirst() async {
        var time = 0
        let line = "No more stupid shit."
        let sender = UpgradeSender()
        var pooled: String?
        let pipeline = SubtitlePipeline(reader: UpgradeReader(Array(repeating: line, count: 3)), translator: UpgradeTranslator(),
                                        server: sender, clock: { time })
        pipeline.packWait = 0; pipeline.cleanWait = 0
        // Havuz ilk bakışta boş; satır motora gittikten sonra sunucunun çevirisi gelir.
        pipeline.packLookup = { $0 == line ? pooled.map { PackMatch(text: $0, spoken: []) } : nil }
        pipeline.onPackMiss = { _ in pooled = "Artık saçma sapan bok yemek yok." }
        for _ in 0..<3 { await pipeline.process(image, region: CropRegion()); await pipeline.waitForTranslations(); time += 100 }
        XCTAssertEqual(sender.sent.first?.text, "Artık saçma sapan bok yemek yok.")
    }
}
#endif
