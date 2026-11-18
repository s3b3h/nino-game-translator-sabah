// SPDX-License-Identifier: AGPL-3.0-only
import XCTest
@testable import CouchSubsCore

final class MenuBlockTests: XCTestCase {
    private func line(_ text: String, left: Double, top: Double, width: Double, height: Double = 0.03) -> TextLine {
        TextLine(text, box: TextBox(left: left, top: top, right: left + width, bottom: top + height))
    }

    func testPauseMenusAreFoundAndSubtitlesAreNot() {
        let reading = Reading(lines: [
            line("Map", left: 0.10, top: 0.25, width: 0.05),
            line("Game", left: 0.10, top: 0.33, width: 0.06),
            line("Store", left: 0.10, top: 0.41, width: 0.06),
            line("Help", left: 0.10, top: 0.49, width: 0.05),
            line("Retry Checkpoint", left: 0.76, top: 0.30, width: 0.14),
            line("Restart Mission", left: 0.78, top: 0.36, width: 0.12),
            line("GONE FISHING", left: 0.79, top: 0.22, width: 0.11),
            // Altyazı: uzun ve ortalı.
            line("Now, who the hell built this outhouse back here? She's a beaut.", left: 0.25, top: 0.82, width: 0.5),
            line("I need me one of those.", left: 0.38, top: 0.87, width: 0.24),
        ])
        let groups = MenuBlock.groups(in: reading)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].lines.map(\.text), ["Map", "Game", "Store", "Help"])
        XCTAssertFalse(groups[0].rightAligned)
        XCTAssertEqual(groups[1].lines.map(\.text), ["GONE FISHING", "Retry Checkpoint", "Restart Mission"])
        XCTAssertTrue(groups[1].rightAligned)
    }

    func testTwoLinesAreNotAMenu() {
        let reading = Reading(lines: [line("Map", left: 0.1, top: 0.25, width: 0.05), line("Game", left: 0.1, top: 0.33, width: 0.06)])
        XCTAssertTrue(MenuBlock.groups(in: reading).isEmpty)
    }

    func testTranslationGoesBesideNotOnTop() {
        let left = line("Map", left: 0.10, top: 0.25, width: 0.05)
        let beside = MenuBlock.placeBeside(left, translation: "Harita", rightAligned: false)
        XCTAssertGreaterThan(beside.left, left.box!.right)
        let right = line("Retry Checkpoint", left: 0.76, top: 0.30, width: 0.14)
        let before = MenuBlock.placeBeside(right, translation: "Kontrol noktasından tekrar dene", rightAligned: true)
        XCTAssertLessThan(before.right, right.box!.left)
        XCTAssertGreaterThanOrEqual(before.left, 0)
    }

    func testIconsAreStrippedAndCommonWordsKnown() {
        XCTAssertEqual(MenuBlock.clean("⊙ Store"), "Store")
        XCTAssertEqual(MenuBlock.clean("0] Photo Studio"), "Photo Studio")
        XCTAssertEqual(MenuBlock.clean("1 Help"), "Help")
        XCTAssertEqual(MenuBlock.clean("i Settings"), "Settings")
        XCTAssertEqual(MenuBlock.clean("ii Map"), "Map")
        XCTAssertEqual(MenuBlock.clean("Go Home"), "Go Home")
        XCTAssertEqual(MenuBlock.clean("i Ayarlar"), "Ayarlar")
        XCTAssertEqual(MenuBlock.clean("Chapter 1"), "Chapter 1")
        XCTAssertEqual(MenuBlock.knownTurkish("Settings"), "Ayarlar")
        XCTAssertEqual(MenuBlock.knownTurkish("CHAPTER 1"), "Bölüm 1")
        XCTAssertNil(MenuBlock.knownTurkish("Get in the car"))
    }

    func testColumnIsAlignedAndClearOfTheWords() {
        let group = MenuBlock.Group(lines: [line("Map", left: 0.10, top: 0.25, width: 0.05),
                                            line("Photo Studio", left: 0.10, top: 0.33, width: 0.12),
                                            line("Settings", left: 0.10, top: 0.41, width: 0.08)], rightAligned: false)
        let boxes = MenuBlock.placeColumn(group, translations: ["Harita", "Fotoğraf Stüdyosu", "Ayarlar"])
        XCTAssertEqual(Set(boxes.map(\.left)).count, 1)
        XCTAssertGreaterThan(boxes[0].left, 0.22)
        let right = MenuBlock.Group(lines: [line("CHAPTER 1", left: 0.80, top: 0.2, width: 0.1),
                                            line("Retry Checkpoint", left: 0.76, top: 0.3, width: 0.14),
                                            line("Restart Mission", left: 0.78, top: 0.36, width: 0.12)], rightAligned: true)
        let rb = MenuBlock.placeColumn(right, translations: ["Bölüm 1", "Kontrol Noktasından Tekrar Dene", "Görevi Yeniden Başlat"])
        XCTAssertEqual(Set(rb.map(\.right)).count, 1)
        XCTAssertLessThan(rb[0].right, 0.76)
    }
}
