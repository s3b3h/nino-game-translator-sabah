// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import ImageIO
import XCTest
@testable import CouchSubsCore

/// Nino: kendiliğinden köşe ve mesaj çevirisi (sol üst ipucu kutusu, görev şeridi, telefon mesajı ve araması).
@MainActor
final class ScreenHintsTests: XCTestCase {
    /// Okunacak yazı test içinde değiştirilir. Sol üst kesiti dar (karenin %40'ı), görev şeridi geniştir.
    private final class Reader: TextReader, @unchecked Sendable {
        var tip: [TextLine] = []
        var strip: [TextLine] = []
        var count = 0
        func read(_ image: CGImage) throws -> String { "" }
        func readLines(_ image: CGImage, deep: Bool) throws -> Reading {
            count += 1
            return Reading(lines: image.width < 160 ? tip : strip)
        }
    }

    private final class Translator {
        var calls: [(text: String, kind: ScreenHints.Kind)] = []
        var known = [
            "HELP": "Yardım",
            "You can swim underwater to avoid being seen by the police.": "Polise görünmemek için su altında yüzebilirsin.",
            "Hurry home babe": "Çabuk eve gel bebeğim",
            "Chase down and lasso the O'Driscoll": "O'Driscoll'u kovala ve kementle yakala",
        ]
        func translate(_ text: String, _ kind: ScreenHints.Kind) async throws -> String {
            calls.append((text, kind))
            return known[text] ?? "çeviri \(calls.count)"
        }
    }

    private final class Clock {
        var ms = 1_000_000
    }

    private func frame() -> CGImage {
        let width = 320, height = 180
        var pixels = [UInt8](repeating: 40, count: width * height)
        let context = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        }
        return context!.makeImage()!
    }

    private func line(_ text: String, _ left: Double, _ top: Double, _ width: Double, _ height: Double) -> TextLine {
        TextLine(text, box: TextBox(left: left, top: top, right: left + width, bottom: top + height))
    }

    /// GTA 6'daki gibi yardım kutusu: başlık ve iki satır (yerler sol üst kesitine göre).
    private var helpBox: [TextLine] {
        [line("HELP", 0.06, 0.10, 0.10, 0.05),
         line("You can swim underwater to avoid", 0.06, 0.17, 0.60, 0.05),
         line("being seen by the police.", 0.06, 0.23, 0.45, 0.05)]
    }

    private func make(menuReader: TextReader? = nil) -> (ScreenHints, Reader, Translator, Clock) {
        let reader = Reader(), translator = Translator(), clock = Clock()
        let hints = ScreenHints(reader: reader, menuReader: menuReader, clock: { clock.ms },
                                translate: { try await translator.translate($0, $1) })
        return (hints, reader, translator, clock)
    }

    func testTipBoxIsTranslatedOnceItIsStableAndPlacedBelowAsPlainText() async {
        let (hints, reader, translator, _) = make()
        var changes: [[ScreenTranslation.Item]] = []
        hints.onChange = { changes.append($0) }
        reader.tip = helpBox
        await hints.pass(frame())
        // Kutu belirirken yarım okunmuş olabilir: ilk görülüşte çevrilmez.
        XCTAssertTrue(hints.items.isEmpty)
        XCTAssertTrue(translator.calls.isEmpty)
        await hints.pass(frame())
        XCTAssertEqual(hints.items.count, 1)
        XCTAssertEqual(changes.last, hints.items)
        let item = hints.items[0]
        XCTAssertTrue(item.plain)
        // Başlık ayrı çevrilir, büyük harfle kendi satırında durur; gövde tek cümle olarak çevrilir.
        XCTAssertEqual(translator.calls.map(\.text), ["HELP", "You can swim underwater to avoid being seen by the police."])
        XCTAssertTrue(translator.calls.allSatisfy { $0.kind == .tip })
        XCTAssertEqual(item.translation.split(separator: "\n").first, "YARDIM")
        XCTAssertTrue(item.translation.contains("su altında"))
        // Çeviri oyunun kutusunun hemen altında (üstünü kapatmaz), aynı sol kenarda; kare koordinatında.
        let sourceBottom = ScreenHints.tipRegion.bottom * 0.28
        XCTAssertGreaterThan(item.box.top, sourceBottom)
        XCTAssertLessThan(item.box.top, sourceBottom + 0.08)
        XCTAssertEqual(item.box.left, 0.06 * ScreenHints.tipRegion.right, accuracy: 0.001)
    }

    func testTranslationLeavesWhenTheTextLeavesButNotOnASingleEmptyRead() async {
        let (hints, reader, _, _) = make()
        var changes: [[ScreenTranslation.Item]] = []
        hints.onChange = { changes.append($0) }
        reader.tip = helpBox
        await hints.pass(frame())
        await hints.pass(frame())
        XCTAssertEqual(hints.items.count, 1)
        reader.tip = []
        // Sahne geçişinde bir iki boş okuma çeviriyi silmez.
        for _ in 0..<3 { await hints.pass(frame()) }
        XCTAssertEqual(hints.items.count, 1)
        await hints.pass(frame())
        XCTAssertTrue(hints.items.isEmpty)
        XCTAssertEqual(changes.last, [])
    }

    func testSameTextIsNotTranslatedAgain() async {
        let (hints, reader, translator, _) = make()
        reader.tip = helpBox
        for _ in 0..<5 { await hints.pass(frame()) }
        XCTAssertEqual(translator.calls.count, 2)
        // Kutu kalkıp aynı yazıyla (bir harfi farklı okunmuş) geri gelir: çevirmene gitmez, eski çeviri gösterilir.
        reader.tip = []
        for _ in 0..<4 { await hints.pass(frame()) }
        XCTAssertTrue(hints.items.isEmpty)
        var again = helpBox
        again[2].text = "being seen by the poIice."
        reader.tip = again
        await hints.pass(frame())
        await hints.pass(frame())
        XCTAssertEqual(hints.items.count, 1)
        XCTAssertEqual(translator.calls.count, 2)
    }

    func testMapLabelsAndShortLeftoversAreNotTranslated() async {
        let (hints, reader, translator, _) = make()
        reader.tip = [line("Cumberland", 0.2, 0.05, 0.2, 0.05), line("CA", 0.9, 0.3, 0.05, 0.05)]
        for _ in 0..<3 { await hints.pass(frame()) }
        XCTAssertTrue(hints.items.isEmpty)
        XCTAssertTrue(translator.calls.isEmpty)
    }

    func testConsoleScreenInTheTargetLanguageIsLeftAlone() async {
        let (hints, reader, translator, _) = make()
        reader.tip = [line("Oyun Kütüphanesi ve Ayarlar", 0.06, 0.10, 0.6, 0.05),
                      line("Arkadaşların şu anda çevrimiçi değil.", 0.06, 0.17, 0.7, 0.05)]
        for _ in 0..<3 { await hints.pass(frame()) }
        XCTAssertTrue(hints.items.isEmpty)
        XCTAssertTrue(translator.calls.isEmpty)
    }

    func testMessageCardGoesAboveTheCardAsPlainTextWithTheSender() async {
        let (hints, _, translator, _) = make()
        var changes = 0
        hints.onChange = { _ in changes += 1 }
        let card = Reading(lines: [line("Cal", 0.66, 0.76, 0.04, 0.03), line("Hurry home babe", 0.66, 0.80, 0.16, 0.03)])
        hints.message(card)
        await hints.waitForMessage()
        // Kart belirirken yarım okunabilir: ilk görülüşte çevrilmez.
        XCTAssertTrue(hints.items.isEmpty)
        hints.message(card)
        await hints.waitForMessage()
        XCTAssertEqual(hints.items.count, 1)
        let item = hints.items[0]
        XCTAssertTrue(item.plain)
        XCTAssertFalse(item.italic)
        XCTAssertEqual(item.translation, "Cal\nÇabuk eve gel bebeğim")
        XCTAssertEqual(translator.calls.map(\.text), ["Hurry home babe"])
        XCTAssertEqual(translator.calls.first?.kind, .message)
        // Kartın üstünde: kartı kapatmaz, sol kenarı kartla aynı.
        XCTAssertLessThan(item.box.bottom, 0.76)
        XCTAssertEqual(item.box.left, 0.66, accuracy: 0.001)
        // Kart ekranda durdukça yeniden çevrilmez, liste yeniden bildirilmez.
        for _ in 0..<3 { hints.message(card) }
        await hints.waitForMessage()
        XCTAssertEqual(translator.calls.count, 1)
        XCTAssertEqual(changes, 1)
    }

    func testMessageLeavesThreeSecondsAfterTheCardWasLastSeen() async {
        let (hints, _, _, clock) = make()
        let card = Reading(lines: [line("Cal", 0.66, 0.76, 0.04, 0.03), line("Hurry home babe", 0.66, 0.80, 0.16, 0.03)])
        hints.message(card)
        hints.message(card)
        await hints.waitForMessage()
        XCTAssertEqual(hints.items.count, 1)
        clock.ms += 2000
        hints.clearStaleMessage()
        XCTAssertEqual(hints.items.count, 1)
        clock.ms += 1500
        hints.clearStaleMessage()
        XCTAssertTrue(hints.items.isEmpty)
    }

    func testCallCardIsShownInItalicWithoutTranslating() async {
        let (hints, _, translator, _) = make()
        let card = Reading(lines: [line("Paradise Taxi", 0.10, 0.80, 0.12, 0.03), line("Calling...", 0.10, 0.84, 0.08, 0.03)])
        hints.message(card)
        XCTAssertEqual(hints.items.map(\.translation), ["Paradise Taxi aranıyor…"])
        XCTAssertTrue(hints.items[0].italic && hints.items[0].plain)
        XCTAssertLessThan(hints.items[0].box.bottom, 0.80)
        XCTAssertTrue(translator.calls.isEmpty)
        // Konuşma başladı (kartta süre): yazı kalkar.
        hints.message(Reading(lines: [line("Paradise Taxi", 0.10, 0.80, 0.12, 0.03), line("00:05", 0.10, 0.84, 0.05, 0.03)]))
        XCTAssertTrue(hints.items.isEmpty)
    }

    func testCallStatusIsTurkishOnly() {
        let (hints, _, _, _) = make()
        hints.targetLanguage = "ar"
        hints.message(Reading(lines: [line("Paradise Taxi", 0.10, 0.80, 0.12, 0.03), line("Calling...", 0.10, 0.84, 0.08, 0.03)]))
        XCTAssertTrue(hints.items.isEmpty)
    }

    func testObjectiveStripIsReadOnlyBelowAKnownSubtitleLine() async {
        let (hints, reader, translator, _) = make()
        // Şeridin kesitine göre ortalı görev satırı.
        reader.strip = [line("Chase down and lasso the O'Driscoll", 0.30, 0.2, 0.40, 0.4)]
        for _ in 0..<2 { await hints.pass(frame()) }
        XCTAssertTrue(hints.items.isEmpty, "altyazı çizgisi bilinmiyorsa görev şeridi okunmaz")
        hints.hudTop = 0.90
        for _ in 0..<2 { await hints.pass(frame()) }
        XCTAssertEqual(hints.items.map(\.translation), ["O'Driscoll'u kovala ve kementle yakala"])
        XCTAssertEqual(translator.calls.last?.kind, .objective)
        XCTAssertGreaterThan(hints.items[0].box.top, 0.90)
    }

    func testObjectiveStripSkipsTheLineTheSubtitleReaderAlreadyTranslated() async {
        let (hints, reader, translator, _) = make()
        hints.hudTop = 0.90
        reader.strip = [line("Chase down and lasso the O'Driscoll", 0.30, 0.2, 0.40, 0.4)]
        for _ in 0..<3 { await hints.pass(frame(), subtitleText: "Chase down and lasso the O'Driscoll") }
        XCTAssertTrue(hints.items.isEmpty)
        XCTAssertTrue(translator.calls.isEmpty)
    }

    /// Duraklatma menüsü açıkken sol üst kutusu menü satırlarını çevirmez; menü ekranı bayrağı okuma hattını durdurur.
    func testPauseMenuIsNotATipAndRaisesTheMenuFlag() async {
        final class MenuReader: TextReader, @unchecked Sendable {
            var lines: [TextLine] = []
            func read(_ image: CGImage) throws -> String { "" }
            func readLines(_ image: CGImage, deep: Bool) throws -> Reading { Reading(lines: lines) }
        }
        let menuReader = MenuReader()
        let (hints, reader, translator, clock) = make(menuReader: menuReader)
        // Menü üç turda bir aranır: ilk iki tur oyun, üçüncü turda menü açılır.
        await hints.pass(frame())
        await hints.pass(frame())
        let rows = [("Map", 0.25), ("Game", 0.33), ("Store", 0.41), ("Help", 0.49)]
        // Bütün ekran kesitine (0,03–0,95) göre yerler.
        menuReader.lines = rows.map { line($0.0, 0.10, $0.1, 0.05, 0.03) }
        // Menünün yanındaki açıklama sol üst kesitinde de okunur (alt alta, ipucu kutusu gibi).
        reader.tip = [line("Map Game Store Help and more", 0.25, 0.50, 0.3, 0.06), line("Retry the last checkpoint", 0.25, 0.58, 0.3, 0.06)]
        XCTAssertFalse(hints.menuFlag.active)
        for _ in 0..<3 { await hints.pass(frame()) }
        XCTAssertTrue(hints.menuFlag.active)
        XCTAssertTrue(hints.items.isEmpty)
        XCTAssertTrue(translator.calls.isEmpty)
        clock.ms += 6000
        XCTAssertFalse(hints.menuFlag.active)
    }

    func testOfferReadsAtMostEveryIntervalAndNeverWhileBusy() async {
        let (hints, reader, _, clock) = make()
        reader.tip = helpBox
        hints.offer(frame())
        hints.offer(frame())
        while hints.isBusy { await Task.yield() }
        XCTAssertEqual(hints.passes, 1)
        clock.ms += 1000
        hints.offer(frame())
        XCTAssertEqual(hints.passes, 1)
        clock.ms += 600
        hints.offer(frame())
        while hints.isBusy { await Task.yield() }
        XCTAssertEqual(hints.passes, 2)
        XCTAssertEqual(hints.items.count, 1)
    }

    func testResetForgetsEverythingAndTellsTheScreen() async {
        let (hints, reader, _, _) = make()
        var changes: [[ScreenTranslation.Item]] = []
        reader.tip = helpBox
        await hints.pass(frame())
        await hints.pass(frame())
        hints.onChange = { changes.append($0) }
        hints.reset()
        XCTAssertTrue(hints.items.isEmpty)
        XCTAssertEqual(changes, [[]])
        // Sıfırlamadan sonra aynı kutu yine iki okumada ve yeniden çevrilerek gelir.
        await hints.pass(frame())
        XCTAssertTrue(hints.items.isEmpty)
        await hints.pass(frame())
        XCTAssertEqual(hints.items.count, 1)
    }

    /// Elle çalıştırılır: NINO_HINT_FRAMES (virgülle ayrılmış PNG'ler) gerçek yazı tanımayla okunur; sol üst kutusu,
    /// altyazı ve mesaj kartı yazdırılır (simülatör denemesinin karelerini hazırlarken).
    func testProbeFrames() async throws {
        guard let list = ProcessInfo.processInfo.environment["NINO_HINT_FRAMES"] else { throw XCTSkip("NINO_HINT_FRAMES yok") }
        final class Sink: SubtitleSending {
            func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) { print("HINTPROBE altyazı:", text) }
            func clear() { print("HINTPROBE altyazı kalktı") }
        }
        struct Echo: TextTranslator {
            func translate(_ text: String) async throws -> String { "«" + String(text.reversed()) + "»" }
        }
        let sink = Sink()
        for path in list.split(separator: ",").map(String.init) {
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let name = (path as NSString).lastPathComponent
            let hints = ScreenHints(reader: VisionReader(language: "en", edgeIcons: true), menuReader: VisionReader(language: "en"),
                                    translate: { text, _ in "«" + String(text.reversed()) + "»" })
            for _ in 0..<3 { await hints.pass(image) }
            print("HINTPROBE", name, "köşe:", hints.items.map { "\($0.translation) @\($0.box)" }, "menü:", hints.menuFlag.active)
            let pipeline = SubtitlePipeline(reader: VisionReader(language: "en"), translator: Echo(), server: sink)
            pipeline.onMessage = { card in
                print("HINTPROBE", name, "kart:", card.lines.map { "\($0.text) @\($0.box.map { "\($0)" } ?? "-")" })
                hints.message(card)
            }
            for step in 0..<8 {
                await pipeline.process(image, region: CropRegion(), capturedAt: SubtitleStabilizer.uptimeMs())
                try await Task.sleep(nanoseconds: 300_000_000)
                if step == 7 { await hints.waitForMessage() }
            }
            print("HINTPROBE", name, "sonuç:", hints.items.map { "\($0.translation.replacingOccurrences(of: "\n", with: " / ")) @\($0.box)" })
        }
    }
}
