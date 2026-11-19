// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// Alanda altyazının yanında menü, köşe göstergesi ve kumanda ipucu da okunur (Red Dead Redemption 2).
final class SubtitleBlockTests: XCTestCase {
    private let area = TextBox(left: 0, top: 0.6, right: 1, bottom: 1)

    private func line(_ text: String, _ left: Double, _ top: Double, _ right: Double, height: Double = 0.07) -> TextLine {
        TextLine(text, box: TextBox(left: left, top: top, right: right, bottom: top + height))
    }

    func testMenuAndCornerTextAreNotSubtitles() {
        let menu = ["MAP", "HELP", "PROGRESS", "PLAYER", "STORY", "ONLINE", "SOCIAL CLUB", "SETTINGS"].enumerated().map {
            line($0.element, 0.05, 0.05 + Double($0.offset) * 0.1, 0.05 + Double($0.element.count) * 0.015)
        }
        let reading = Reading(lines: menu + [line("PHOTO MODE", 0.85, 0.9, 0.97)])
        XCTAssertEqual(reading.subtitleBlock(in: area), .empty)
    }

    func testCenteredSubtitleIsKeptWithoutCornerGauge() {
        let reading = Reading(lines: [
            line("We'll lose these tracks if we don't hurry.", 0.25, 0.7, 0.75),
            line("9", 0.02, 0.7, 0.04),
            line("PHOTO MODE", 0.85, 0.9, 0.97),
        ])
        let block = reading.subtitleBlock(in: area)
        XCTAssertEqual(block.text, "We'll lose these tracks if we don't hurry.")
        XCTAssertEqual(block.box, TextBox(left: 0.25, top: 0.7, right: 0.75, bottom: 0.77))
    }

    /// Nino: RDR2'nin açılıştaki yasal uyarısı alanın iki yanından taşar ("rema pay or play, or copy protector…"); çevrilmez.
    func testLineClippedOnBothSidesIsNotSubtitle() {
        let reading = Reading(lines: [line("rema pay or play, or copy protector crediverton is promoted a volutes coun", 0.0, 0.8, 1.0)])
        XCTAssertEqual(reading.withoutClippedLines().subtitleBlock(in: area), .empty)
        // Tek yana taşan (dar alan) ya da ortalı uzun altyazı kalır.
        let wide = Reading(lines: [line("Arthur, we need to get to the boat before the storm reaches the valley!", 0.06, 0.8, 0.94)])
        XCTAssertEqual(wide.withoutClippedLines().text, wide.text)
        let oneSide = Reading(lines: [line("before the storm reaches the valley", 0.0, 0.8, 0.7)])
        XCTAssertEqual(oneSide.withoutClippedLines().text, oneSide.text)
    }

    func testTwoLineSubtitleStaysTogether() {
        let reading = Reading(lines: [
            line("Mac and John... they were both shot.", 0.3, 0.6, 0.7),
            line("We need to move.", 0.4, 0.68, 0.6),
        ])
        XCTAssertEqual(reading.subtitleBlock(in: area).text, "Mac and John... they were both shot.\nWe need to move.")
    }

    func testLeftAlignedSentenceIsStillRead() {
        let reading = Reading(lines: [line("Mafioso: We're worried about this one.", 0.05, 0.8, 0.5)])
        XCTAssertEqual(reading.subtitleBlock(in: area).text, "Mafioso: We're worried about this one.")
    }

    func testLinesWithoutPlaceAreUntouched() {
        let reading = Reading(text: "MAP\nHELP")
        XCTAssertEqual(reading.subtitleBlock(in: area), reading)
    }

    func testButtonAtTheEndIsAPrompt() {
        XCTAssertTrue(ButtonPrompts.isPrompt("PHOTO MODE L1 + R1"))
        XCTAssertTrue(ButtonPrompts.isPrompt("PHOTO MODE [L1] + [R3]"))
        XCTAssertFalse(ButtonPrompts.isPrompt("Hand me the L1."))
    }

    func testGaugeNumberStuckToLineIsDropped() {
        XCTAssertEqual(OcrNoise.clean("9? We'll lose these tracks."), "We'll lose these tracks.")
        XCTAssertEqual(OcrNoise.clean("100. Mac and John..."), "Mac and John...")
        XCTAssertEqual(OcrNoise.clean("23m CESARE: It's here! Shoot him!"), "CESARE: It's here! Shoot him!")
        XCTAssertEqual(OcrNoise.clean("100 men came"), "100 men came")
    }

    // MARK: - Dev yazılar (tabela, reklam panosu)

    private let lowerHalf = TextBox(left: 0.06, top: 0.56, right: 0.98, bottom: 1)

    func testNormalSubtitleLinesAreKept() {
        // Alanın %9'u × alan yüksekliği 0.44 ≈ karenin %4'ü: sıradan altyazı satırı.
        let reading = Reading(lines: [
            TextLine("I told you not to come here.", box: TextBox(left: 0.3, top: 0.60, right: 0.7, bottom: 0.69)),
            TextLine("You never listen.", box: TextBox(left: 0.38, top: 0.70, right: 0.62, bottom: 0.79)),
        ])
        XCTAssertEqual(reading.withoutOversizedLines(in: lowerHalf), reading)
        XCTAssertFalse(reading.isOversizedBlock(in: lowerHalf))
    }

    func testGiantSignLineIsDroppedButSubtitleStays() {
        // Tabela satırı alanın %30'u ≈ karenin %13'ü; altyazı yanında kalır.
        let sign = TextLine("Welcome to Leonida", box: TextBox(left: 0.1, top: 0.05, right: 0.9, bottom: 0.35))
        let subtitle = TextLine("Where are we going?", box: TextBox(left: 0.35, top: 0.80, right: 0.65, bottom: 0.88))
        let reading = Reading(lines: [sign, subtitle]).withoutOversizedLines(in: lowerHalf)
        XCTAssertEqual(reading.lines, [subtitle])
    }

    func testLineHeightIsMeasuredAgainstTheWholeFrame() {
        // Aynı satır dar bir alanda alanın yarısını kaplar ama karede %5'tir: atılmaz.
        let narrow = TextBox(left: 0.2, top: 0.85, right: 0.8, bottom: 0.95)
        let line = TextLine("Stay close to me.", box: TextBox(left: 0.2, top: 0.2, right: 0.8, bottom: 0.7))
        XCTAssertEqual(Reading(lines: [line]).withoutOversizedLines(in: narrow).lines, [line])
        // Aynı oran bütün karede okunursa karenin yarısıdır: atılır.
        let full = TextBox(left: 0, top: 0, right: 1, bottom: 1)
        XCTAssertTrue(Reading(lines: [line]).withoutOversizedLines(in: full).lines.isEmpty)
    }

    func testLinesWithoutBoxesAreNeverDropped() {
        let reading = Reading(lines: [TextLine("No position known.")])
        XCTAssertEqual(reading.withoutOversizedLines(in: lowerHalf), reading)
        XCTAssertFalse(reading.isOversizedBlock(in: lowerHalf))
    }

    func testTallBlockIsNotASubtitle() {
        // Normal boyda ama üst üste yedi satır (afiş, not): blok karenin %26'sından yüksek ve 5 satırdan çok.
        let lines = (0 ..< 7).map { index -> TextLine in
            let top = 0.05 + Double(index) * 0.12
            return TextLine("Line number \(index) of a poster.", box: TextBox(left: 0.3, top: top, right: 0.7, bottom: top + 0.09))
        }
        XCTAssertTrue(Reading(lines: lines).isOversizedBlock(in: lowerHalf))
        // Üç satırlık uzun altyazı kalır.
        XCTAssertFalse(Reading(lines: Array(lines.prefix(3))).isOversizedBlock(in: lowerHalf))
    }

    func testFewLinesCoveringTooMuchHeightAreNotASubtitle() {
        // İki satır ama aralarında büyük boşluk: kutu karenin %30'u.
        let reading = Reading(lines: [
            TextLine("Top of a billboard", box: TextBox(left: 0.3, top: 0.05, right: 0.7, bottom: 0.15)),
            TextLine("bottom of a billboard", box: TextBox(left: 0.3, top: 0.65, right: 0.7, bottom: 0.75)),
        ])
        XCTAssertTrue(reading.isOversizedBlock(in: lowerHalf))
    }
}
