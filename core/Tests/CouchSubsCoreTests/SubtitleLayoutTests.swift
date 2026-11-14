import CoreGraphics
import XCTest
@testable import CouchSubsCore

final class SubtitleLayoutTests: XCTestCase {
    private func box(_ top: Double, _ bottom: Double) -> TextBox { TextBox(left: 0.3, top: top, right: 0.7, bottom: bottom) }

    func testUsesFallbackUntilLearned() {
        var layout = SubtitleLayout()
        for _ in 0..<(SubtitleLayout.minimumSamples - 1) { layout.record(box(0.80, 0.86), game: "rdr2") }
        XCTAssertEqual(layout.hudTop(for: "rdr2"), SubtitleLayout.fallbackHudTop)
        XCTAssertNil(layout.band(for: "rdr2"))
    }

    func testLearnsBandAboveTutorialLine() throws {
        var layout = SubtitleLayout()
        for i in 0..<12 { layout.record(box(0.79 + Double(i % 3) * 0.01, 0.85 + Double(i % 3) * 0.01), game: "rdr2") }
        let hud = try XCTUnwrap(layout.hudTop(for: "rdr2"))
        // Şerit 0.79–0.87; bir satır payıyla sınır öğretici yazısının (≈0.93) üstünde kalır.
        XCTAssertGreaterThan(hud, 0.89)
        XCTAssertLessThan(hud, 0.93)
    }

    /// Altyazısı en altta duran oyunda en alt satırlar da altyazıdır: sınır aşağı iner ya da kalkar.
    func testGameWithLowSubtitlesIsNotCut() {
        var layout = SubtitleLayout()
        for _ in 0..<10 { layout.record(box(0.90, 0.95), game: "low") }
        let hud = layout.hudTop(for: "low")
        XCTAssertTrue(hud == nil || hud! > 0.95)
    }

    func testOutlierDoesNotMoveBand() throws {
        var layout = SubtitleLayout()
        for _ in 0..<20 { layout.record(box(0.80, 0.86), game: "g") }
        layout.record(box(0.30, 0.35), game: "g")
        let band = try XCTUnwrap(layout.band(for: "g"))
        XCTAssertEqual(band.top, 0.80, accuracy: 0.001)
    }

    func testGamesAreSeparate() {
        var layout = SubtitleLayout()
        for _ in 0..<10 { layout.record(box(0.90, 0.95), game: "a") }
        XCTAssertEqual(layout.hudTop(for: "b"), SubtitleLayout.fallbackHudTop)
    }

    func testStoreRoundTrips() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("layout-\(UUID().uuidString).json")
        let store = SubtitleLayoutStore(file: file)
        for _ in 0..<9 { store.record(box(0.8, 0.86), game: "g") }
        XCTAssertNotNil(SubtitleLayoutStore(file: file).current.band(for: "g"))
    }
}

private struct NoReader: TextReader { func read(_ image: CGImage) throws -> String { "" } }
private struct EchoTranslator: TextTranslator { func translate(_ text: String) async throws -> String { text } }
private final class NoSender: SubtitleSending {
    func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) {}
    func clear() {}
}

@MainActor
final class StaleLineTests: XCTestCase {
    private func line(_ text: String, _ top: Double) -> TextLine {
        TextLine(text, box: TextBox(left: 0.3, top: top, right: 0.7, bottom: top + 0.05))
    }

    /// RDR2: alttaki öğretici yazısı uzun süre aynı kalır, üstünde konuşmalar değişir; öğretici yazısı atlanır.
    func testLongLivedTutorialLineIsSkippedWhileDialogueChanges() {
        let pipeline = SubtitlePipeline(reader: NoReader(), translator: EchoTranslator(), server: NoSender())
        let tip = line("Approach your horse and hold L1 to view stored weapons", 0.9)
        _ = pipeline.withoutStaleLines(Reading(lines: [tip]), at: 0)
        let later = pipeline.withoutStaleLines(Reading(lines: [line("You two, get up there.", 0.8), tip]), at: 10_000)
        XCTAssertEqual(later.lines.map(\.text), ["You two, get up there."])
    }

    /// Tek başına duran uzun satır (uzun bir konuşma) atılmaz.
    func testLoneLongLineStays() {
        let pipeline = SubtitlePipeline(reader: NoReader(), translator: EchoTranslator(), server: NoSender())
        let only = line("A very long monologue line.", 0.85)
        _ = pipeline.withoutStaleLines(Reading(lines: [only]), at: 0)
        XCTAssertEqual(pipeline.withoutStaleLines(Reading(lines: [only]), at: 12_000).lines.count, 1)
    }
}
