// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// Nino: GTA 6 ekrandaki kendine özgü yazılarından tanınır (PS5 oyunu çoğu zaman bildirmiyor; 21 Kasım 2026).
final class GameMarkersTests: XCTestCase {
    private func line(_ text: String, _ top: Double = 0.1) -> TextLine {
        TextLine(text, box: TextBox(left: 0.4, top: top, right: 0.6, bottom: top + 0.03))
    }

    func testMapScreenIsGTA6() throws {
        let image = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-harita-buckme.jpg"))
        let reading = try VisionReader(language: "en", cpuOnly: true).readLines(image, deep: false)
        XCTAssertEqual(GameMarkers.game(in: reading), "GTA 6")
    }

    func testPauseMenuTabsAreGTA6() {
        // Duraklatma menüsünün sekme şeridi (kullanıcının TV fotoğrafı): "L1 JASON & LUCIA MAP BRIEF PROGRESS R1".
        XCTAssertEqual(GameMarkers.game(in: Reading(lines: [line("JASON & LUCIA"), line("MAP"), line("BRIEF"), line("PROGRESS")])), "GTA 6")
        XCTAssertEqual(GameMarkers.game(in: Reading(lines: [line("MAP"), line("BRIEF"), line("PROGRESS")])), "GTA 6")
    }

    func testPhoneHomeScreenIsGTA6() {
        XCTAssertEqual(GameMarkers.game(in: Reading(lines: [line("Reminders"), line("7 Notifications"), line("WhatUp", 0.8)])), "GTA 6")
    }

    func testOtherScreensAreNotRecognised() throws {
        XCTAssertNil(GameMarkers.game(in: Reading(lines: [line("Options"), line("Map"), line("Progress"), line("Quit Game")])))
        XCTAssertNil(GameMarkers.game(in: Reading(lines: [line("Jason, wait for me!", 0.85)])))
        let image = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-altyazi-beyaz.jpg"))
        let reading = try VisionReader(language: "en", cpuOnly: true).readLines(image, deep: false)
        XCTAssertNil(GameMarkers.game(in: reading), reading.text)
    }

    func testCatalogShowsTheShortNameAndStillMatchesTheLongOne() {
        XCTAssertEqual(GameName.key("GTA 6"), GameName.key("Grand Theft Auto VI"))
        XCTAssertTrue(GameCatalog.suggestions(query: "grand theft", packs: [], last: nil).contains("GTA 6"))
        XCTAssertEqual(GameCatalog.suggestions(query: "", packs: [], last: nil).first, "GTA 6")
    }
}
