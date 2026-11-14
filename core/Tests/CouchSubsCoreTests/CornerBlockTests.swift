// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// Nino: sol üstte yalnız ipucu kutusu çevrilir; harita yer adları değil (değerler gerçek RDR2 karelerinden).
final class CornerBlockTests: XCTestCase {
    private func line(_ text: String, _ left: Double, _ top: Double, _ width: Double, _ height: Double) -> TextLine {
        TextLine(text, box: TextBox(left: left, top: top, right: left + width, bottom: top + height))
    }

    func testTipBoxIsKept() {
        let reading = Reading(lines: [
            line("Bring Pearson animals to supply the", 0.02, 0.03, 0.21, 0.02),
            line("camp. He can use the meat for food", 0.02, 0.05, 0.21, 0.03),
            line("and the skins to craft Satchels with", 0.02, 0.08, 0.21, 0.02),
            line("increased capacity.", 0.02, 0.11, 0.11, 0.02),
        ])
        XCTAssertEqual(CornerBlock.tipBox(in: reading).lines.count, 4)
    }

    func testMapLabelsAreDropped() {
        let reading = Reading(lines: [
            line("Cumberiand", 0.09, 0.01, 0.07, 0.02),
            line("Fatis", 0.12, 0.03, 0.03, 0.01),
            line("CA", 0.38, 0.16, 0.02, 0.02),
            line("Dakota River", 0.06, 0.19, 0.03, 0.17),
        ])
        XCTAssertTrue(CornerBlock.tipBox(in: reading).lines.isEmpty)
    }

    func testMissionCardKeepsItsTitleButNotTheMap() {
        let reading = Reading(lines: [
            line("Cumberland", 0.09, 0.01, 0.08, 0.02),
            line("REVEREND SWANSON", 0.06, 0.08, 0.20, 0.04),
            line("CA", 0.38, 0.16, 0.02, 0.02),
            line("WHO IS NOT WITHOUT SIN", 0.10, 0.16, 0.13, 0.02),
        ])
        XCTAssertEqual(CornerBlock.tipBox(in: reading).lines.map(\.text), ["REVEREND SWANSON", "WHO IS NOT WITHOUT SIN"])
    }

    func testSingleWordIsNotATip() {
        XCTAssertTrue(CornerBlock.tipBox(in: Reading(lines: [line("grizzlies", 0.02, 0.03, 0.06, 0.02)])).lines.isEmpty)
    }
}
