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
}
