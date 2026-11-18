// SPDX-License-Identifier: AGPL-3.0-only
// Tuş ipucunun Türkçesi oyunun yazısına binmez (TV kutuyu 0,008 payla çizer).
import XCTest
import CouchSubsCore
@testable import Nino

final class PromptPlacementTests: XCTestCase {
    private func item(_ source: String, _ translation: String, top: Double, left: Double = 0.75, right: Double = 0.85) -> ScreenTranslation.Item {
        ScreenTranslation.Item(source: source, translation: translation, box: TextBox(left: left, top: top, right: right, bottom: top + 0.03),
                               lineHeight: 0.03)
    }

    func testTranslationSitsAboveWithRoomForTheTVPadding() {
        let original = item("TURBINE R3", "Türbin R3", top: 0.80)
        let placed = AppModel.placeAbove([original])[0]
        // TV'deki kutunun alt kenarı (bottom + 0,008) oyunun yazısının üst kenarının (top - 0,008) üstünde kalır.
        XCTAssertLessThan(placed.box.bottom + 0.008, original.box.top - 0.008 + 0.0001)
    }

    func testLongerTurkishWidensTowardsTheMiddle() {
        let original = item("BACK", "Geri dön buradan", top: 0.80)
        let placed = AppModel.placeAbove([original])[0]
        XCTAssertLessThan(placed.box.left, original.box.left)
        XCTAssertEqual(placed.box.right, original.box.right)
    }

    func testStackedPromptsDoNotOverlap() {
        let lower = item("PHOTO STUDIO", "Fotoğraf Stüdyosu", top: 0.80)
        let upper = item("SELECT", "Seç", top: 0.76)
        let placed = AppModel.placeAbove([lower, upper])
        XCTAssertEqual(placed.count, 2)
        let (a, b) = (placed[0].box, placed[1].box)
        XCTAssertLessThanOrEqual(a.bottom + 0.008, b.top - 0.008 + 0.0001)
    }
}
