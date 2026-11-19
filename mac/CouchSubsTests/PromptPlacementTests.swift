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

final class PromptIconTests: XCTestCase {
    func testIconsAreDroppedButButtonNamesStay() {
        XCTAssertEqual(AppModel.withoutIcons("Fotoğraf Stüdyosu □ Seç ✕ Geri ○"), "Fotoğraf Stüdyosu Seç Geri")
        XCTAssertEqual(AppModel.withoutIcons("Nişan almak için L1 tuşunu basılı tut"), "Nişan almak için L1 tuşunu basılı tut")
    }

    func testSamePromptKeepsItsPlace() {
        let old = ScreenTranslation.Item(source: "BACK", translation: "Geri", box: TextBox(left: 0.80, top: 0.85, right: 0.86, bottom: 0.88), lineHeight: 0.03)
        let new = ScreenTranslation.Item(source: "BACK", translation: "Geri", box: TextBox(left: 0.81, top: 0.852, right: 0.87, bottom: 0.882), lineHeight: 0.03)
        XCTAssertEqual(AppModel.steady([new], previous: [old])[0].box.left, 0.80)
        let far = ScreenTranslation.Item(source: "BACK", translation: "Geri", box: TextBox(left: 0.2, top: 0.3, right: 0.26, bottom: 0.33), lineHeight: 0.03)
        XCTAssertEqual(AppModel.steady([far], previous: [old])[0].box.left, 0.2)
    }
}

final class PromptSplitTests: XCTestCase {
    func testEachButtonGetsItsOwnTranslationAboveIt() {
        let item = ScreenTranslation.Item(source: "PHOTO STUDIO □ SELECT ✕ BACK ○", translation: "Fotoğraf Stüdyosu □ Seçmek ✕ Geri ○",
                                          box: TextBox(left: 0.45, top: 0.90, right: 0.92, bottom: 0.94), lineHeight: 0.04)
        let pieces = AppModel.splitAtIcons(item, knownWords: true)
        XCTAssertEqual(pieces.map(\.translation), ["Fotoğraf Stüdyosu", "Seç", "Geri"])
        // Aynı satırın parçaları yerleşince yan yana kalır, biri yukarı itilmez.
        let placed = AppModel.placeAbove(pieces)
        XCTAssertEqual(Set(placed.map { ($0.box.bottom * 1000).rounded() }).count, 1)
        XCTAssertLessThan(pieces[0].box.right, pieces[1].box.left + 0.02)
        XCTAssertLessThan(pieces[1].box.right, pieces[2].box.left + 0.02)
        // "Geri", BACK'in üstünde: satırın sağ bölümünde.
        XCTAssertGreaterThan((pieces[2].box.left + pieces[2].box.right) / 2, 0.80)
    }

    func testPlainSentenceIsNotSplit() {
        let item = ScreenTranslation.Item(source: "Hold L2 to slow down", translation: "Yavaşlamak için L2'yi basılı tut",
                                          box: TextBox(left: 0.1, top: 0.5, right: 0.4, bottom: 0.53), lineHeight: 0.03)
        XCTAssertEqual(AppModel.splitAtIcons(item).count, 1)
    }
}

final class CornerWrapTests: XCTestCase {
    func testLongTipWrapsToTheBoxWidth() {
        let text = "Yatak odasında uyuyarak dinlenebilir ve zamanı ilerletebilirsin. Ayrıca gizli para zulana da erişebilirsin."
        let lines = AppModel.wrap(text, width: 0.3, line: 0.03)
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertEqual(lines.joined(separator: " "), text)
        XCTAssertTrue(lines.allSatisfy { $0.count <= 40 })
    }
}

final class PromptAvoidTests: XCTestCase {
    func testPromptBelowWhenSubtitleIsAbove() {
        let prompt = ScreenTranslation.Item(source: "Press ✕ to talk", translation: "Konuşmak için tuşa bas",
                                            box: TextBox(left: 0.35, top: 0.80, right: 0.65, bottom: 0.84), lineHeight: 0.04)
        let subtitle = TextBox(left: 0.2, top: 0.70, right: 0.9, bottom: 0.78)
        let placed = AppModel.placeAbove([prompt], avoiding: [subtitle])[0]
        XCTAssertGreaterThan(placed.box.top, prompt.box.bottom)
        let free = AppModel.placeAbove([prompt])[0]
        XCTAssertLessThan(free.box.bottom, prompt.box.top)
    }
}

final class NavigationWordTests: XCTestCase {
    func testPlainNavigationIsNotTranslated() {
        XCTAssertTrue(AppModel.isNavigationWord("BACK ○"))
        XCTAssertTrue(AppModel.isNavigationWord("SELECT"))
        XCTAssertTrue(AppModel.isNavigationWord("PHOTO STUDIO"))
        XCTAssertTrue(AppModel.isNavigationWord("THREATEN □"))
        XCTAssertTrue(AppModel.isNavigationWord("CLERK L2"))
        XCTAssertTrue(AppModel.isNavigationWord("L1 BASEBALL BAT"))
        XCTAssertTrue(AppModel.isNavigationWord("△ USE"))
        XCTAssertFalse(AppModel.isNavigationWord("Hold L1 to open the equipment menu"))
        XCTAssertFalse(AppModel.isNavigationWord("Press ✕ to talk"))
    }
}

final class PromptKeyTests: XCTestCase {
    func testRingAroundTheIconDoesNotChangeThePrompt() {
        XCTAssertEqual(AppModel.promptKey("Hold L1 to open your loadout"), AppModel.promptKey("Hold ◯ L1 to open your loadout"))
        XCTAssertEqual(AppModel.promptKey("Hold □ to open your loadout"), AppModel.promptKey("Hold to open your loadout"))
        XCTAssertEqual(AppModel.promptKey("Hold L1 to open your loadout"), AppModel.promptKey("Hold to open your loadout"))
    }
}
