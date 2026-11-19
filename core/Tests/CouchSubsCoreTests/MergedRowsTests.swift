// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

final class MergedRowsTests: XCTestCase {
    func testPartsOfTheSameSizeOnOneRowAreJoined() {
        let rows = VisionReader.mergedRows([
            TextLine("Hold", box: TextBox(left: 0.30, top: 0.80, right: 0.36, bottom: 0.85)),
            TextLine("to continue", box: TextBox(left: 0.42, top: 0.805, right: 0.60, bottom: 0.85)),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].text.hasPrefix("Hold"))
        XCTAssertTrue(rows[0].text.hasSuffix("to continue"))
    }

    func testGiantSignLetterIsNotJoinedToTheSubtitle() {
        // Altyazı (boyu 0.05) ve hemen sağında, aynı sırada dev tabela harfi (boyu 0.20): ayrı satır kalır, altyazının
        // kutusu büyümez.
        let subtitle = TextLine("You made it through half a scuba tour.", box: TextBox(left: 0.20, top: 0.80, right: 0.70, bottom: 0.85))
        let sign = TextLine("CAL", box: TextBox(left: 0.72, top: 0.74, right: 0.95, bottom: 0.94))
        let rows = VisionReader.mergedRows([subtitle, sign])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first { $0.text.contains("scuba") }?.box, subtitle.box)
    }
}
