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

final class ItemLabelTests: XCTestCase {
    func testGameLabelsAreNotSubtitles() {
        for label in ["TRAP SANDALS", "BLACK", "WORTHAM", "COMBAT RIFLE", "A LOOT", "MILK", "RV PARK",
                      "ADD TO TRUNK (1/5) □ WEAR ✕ EXIT ○", "STRAIGHT JEANS", "GONE FISHIN'", "COLLECTION", "JASON'S '70 GANADO", "ASS MAN.", "\"ASS\" MAN", "NYWL, SSY."] {
            XCTAssertTrue(Reading.isItemLabel(label), label)
        }
        for line in ["GET DOWN!", "WHAT?", "NO WAY!", "ENZO: Get in the car.", "I'm Jason.", "Lucia.", "Okay, how do I look?",
                     "Yeah, well, maybe change the plates", "Thanks for the tip."] {
            XCTAssertFalse(Reading.isItemLabel(line), line)
        }
    }
}

final class MessageCardTests: XCTestCase {
    private func line(_ text: String, top: Double) -> TextLine {
        TextLine(text, box: TextBox(left: 0.4, top: top, right: 0.8, bottom: top + 0.04))
    }

    func testPhoneMessageIsACard() {
        let card = Reading(lines: [line("Donnie", top: 0.70), line("You did good looking out for Brian earlier.", top: 0.76),
                                   line("We're all in this together, remember that!", top: 0.81)])
        XCTAssertTrue(MessageCard.isCard(card))
        XCTAssertEqual(MessageCard.parts(card).name, "Donnie")
        XCTAssertFalse(MessageCard.isCard(Reading(lines: [line("ENZO: Get in.", top: 0.7), line("Now, before they see us.", top: 0.76)])))
        XCTAssertFalse(MessageCard.isCard(Reading(lines: [line("Okay.", top: 0.7), line("Let's go have some fun.", top: 0.76)])))
        XCTAssertFalse(MessageCard.isCard(Reading(lines: [line("Lucia", top: 0.7)])))
        XCTAssertTrue(MessageCard.isCard(Reading(lines: [line("Chuck's Gun Shop", top: 0.70),
            line("Hey Jason. You okay? Saw those assholes", top: 0.76), line("coming at you outside the shop and...", top: 0.81)])))
    }
}

final class MenuScreenTests: XCTestCase {
    func testMapAndPauseScreensAreRecognised() {
        XCTAssertTrue(MenuBlock.isMenuScreen(Reading(lines: [TextLine("JASON & LUCIA MAP BRIEF PROGRESS")])))
        XCTAssertTrue(MenuBlock.isMenuScreen(Reading(lines: [TextLine("ii Map"), TextLine("Game"), TextLine("Store")])))
        XCTAssertFalse(MenuBlock.isMenuScreen(Reading(lines: [TextLine("Let's check the map."), TextLine("Game on.")])))
        XCTAssertTrue(MenuBlock.isMenuScreen(Reading(lines: [TextLine("SPEED"), TextLine("ACCELERATION"), TextLine("ASPHALT HANDLING")])))
        XCTAssertFalse(MenuBlock.isMenuScreen(Reading(lines: [TextLine("Slow down, you're going too fast.")])))
        XCTAssertTrue(MenuBlock.isMenuScreen(Reading(lines: [TextLine("SHOW TEXT △"), TextLine("FLIP □"), TextLine("PUT BACK ○")])))
    }
}

final class ShortMessageCardTests: XCTestCase {
    private func line(_ text: String, left: Double, top: Double) -> TextLine {
        TextLine(text, box: TextBox(left: left, top: top, right: left + 0.2, bottom: top + 0.04))
    }

    /// Kısa mesaj ("On my way") sağdaki kartta duruyorsa karttır; eskiden altyazı sanılıp siyah kutuyla üstü kapanıyordu.
    func testShortMessageOnTheRightIsACard() {
        XCTAssertTrue(MessageCard.isCard(Reading(lines: [line("Cal", left: 0.72, top: 0.80), line("On my way", left: 0.72, top: 0.85)])))
        XCTAssertTrue(MessageCard.isCard(Reading(lines: [line("Donnie", left: 0.70, top: 0.80), line("Ok", left: 0.70, top: 0.85)])))
        // Ortadaki iki satırlık altyazı kart değildir.
        XCTAssertFalse(MessageCard.isCard(Reading(lines: [line("Jason", left: 0.40, top: 0.80), line("Yeah", left: 0.40, top: 0.85)])))
        // Gövdesi yalnız rakam ya da simge olan okuma kart değildir.
        XCTAssertFalse(MessageCard.isCard(Reading(lines: [line("Cal", left: 0.72, top: 0.80), line("12:45", left: 0.72, top: 0.85)])))
    }

    func testShortCardBodyReadWithoutItsNameIsNotASubtitle() {
        XCTAssertTrue(MessageCard.repeats("On my way", of: "On my way"))
        XCTAssertTrue(MessageCard.repeats("my way", of: "On my way"))
        XCTAssertFalse(MessageCard.repeats("Get in the car", of: "On my way"))
    }
}

final class NavigationHintTests: XCTestCase {
    func testTurnByTurnLinesAreNotSubtitles() {
        for hint in ["Turn Right 405 ft 432 ft", "Keep Left O ft 2 ft", "U-Turn Left 5 ft 24 ft", "Turn Left 366 ft—",
                     "-turn Right 67 ft 82 ft", "Turn Right i 100 ft 103 ft", "Keep Right 3.9 km"] {
            XCTAssertTrue(Reading.isNavigationHint(hint), hint)
        }
        for subtitle in ["Turn right at the lights, okay?", "Turn Right", "Keep left and you'll be fine, 20 ft or so",
                         "Keep it down!", "I said turn left, 50 ft back there you idiot."] {
            XCTAssertFalse(Reading.isNavigationHint(subtitle), subtitle)
        }
        let reading = Reading(lines: [TextLine("Turn Right 405 ft"), TextLine("Where the hell are we going?")])
        XCTAssertEqual(reading.withoutNavigationHints().lines.map(\.text), ["Where the hell are we going?"])
    }
}

final class MessageRepeatTests: XCTestCase {
    func testPartOfTheCardIsNotASubtitle() {
        let body = "Hey Jason. You okay? Saw those assholes coming at you outside the shop and"
        XCTAssertTrue(MessageCard.repeats("Hey Jason. You okay? Saw those assholes", of: body))
        XCTAssertFalse(MessageCard.repeats("Get in the car, we're leaving now.", of: body))
    }
}

final class PhoneListTests: XCTestCase {
    func testInboxIsNeitherCardNorSubtitle() {
        let list = Reading(lines: ["Joey", "Hey this is Joey from ...", "Lucia (Yolanda phon", "Outside living better t...",
                                   "Shirley", "Oh that's nice hon. ar..."].enumerated().map { index, text in
            TextLine(text, box: TextBox(left: 0.4, top: 0.3 + Double(index) * 0.05, right: 0.7, bottom: 0.34 + Double(index) * 0.05))
        })
        XCTAssertTrue(MessageCard.isList(list))
        XCTAssertFalse(MessageCard.isCard(list))
        XCTAssertTrue(Reading.isItemLabel("WhatUp"))
        XCTAssertTrue(Reading.isItemLabel("Contacts"))
        XCTAssertFalse(Reading.isItemLabel("Okay."))
    }
}

final class BillboardTests: XCTestCase {
    func testBillboardIsNotAMessage() {
        let sign = Reading(lines: [TextLine("TREADBounD", box: TextBox(left: 0.1, top: 0.3, right: 0.4, bottom: 0.36)),
                                   TextLine("Take nature before it takes you", box: TextBox(left: 0.1, top: 0.38, right: 0.4, bottom: 0.44))])
        XCTAssertFalse(MessageCard.isCard(sign))
    }
}

final class PhoneCallTests: XCTestCase {
    private func card(_ status: String) -> Reading {
        Reading(lines: [TextLine("Paradise Taxi", box: TextBox(left: 0.1, top: 0.8, right: 0.3, bottom: 0.83)),
                        TextLine(status, box: TextBox(left: 0.1, top: 0.84, right: 0.2, bottom: 0.87))])
    }

    func testCallCard() {
        XCTAssertEqual(MessageCard.call(card("Calling..."))?.status, "aranıyor…")
        XCTAssertEqual(MessageCard.call(card("00:05"))?.status, "")
        XCTAssertNil(MessageCard.call(card("We need to talk about the money.")))
        XCTAssertNil(MessageCard.call(Reading(lines: [TextLine("Get in the car.", box: TextBox(left: 0.3, top: 0.8, right: 0.6, bottom: 0.83)),
                                                       TextLine("Calling...", box: TextBox(left: 0.3, top: 0.84, right: 0.5, bottom: 0.87))])))
    }
}

final class SingleNameCardTests: XCTestCase {
    func testSingleWordSenderIsCard() {
        let card = Reading(lines: [TextLine("Brian", box: TextBox(left: 0.5, top: 0.55, right: 0.6, bottom: 0.59)),
                                   TextLine("One more thing, left your", box: TextBox(left: 0.5, top: 0.62, right: 0.9, bottom: 0.66)),
                                   TextLine("pay for those packages and", box: TextBox(left: 0.5, top: 0.67, right: 0.9, bottom: 0.71))])
        XCTAssertTrue(MessageCard.isCard(card))
    }
}

final class PaintCanTests: XCTestCase {
    func testProductLabelsAreItemLabels() {
        for text in ["LOW ODOR, ZERO VOC", "MAKE IT A RIMM JOB!", "IGHT CRAY BAS!", "[POXY, ZINC, PHOSPHA?"] {
            XCTAssertTrue(Reading.isItemLabel(text), text)
        }
        for text in ["GET DOWN!", "WHAT?", "We'll find him, man. Don't worry about it.", "Okay."] {
            XCTAssertFalse(Reading.isItemLabel(text), text)
        }
    }
}
