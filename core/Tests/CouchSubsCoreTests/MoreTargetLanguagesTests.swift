// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import XCTest

/// Nino: Türkçe ve Arapçanın yanında GTA 6 gibi oyunların listesinde olmayan diller.
final class MoreTargetLanguagesTests: XCTestCase {
    func testChoicesStartWithTurkishAndHaveFlags() {
        XCTAssertEqual(TargetLanguage.choices.first?.code, "tr")
        XCTAssertEqual(TargetLanguage.choices.map(\.code), ["tr", "ar", "hi", "id", "th", "vi", "ur", "bn", "ms", "tl", "nl"])
        for choice in TargetLanguage.choices {
            XCTAssertNotEqual(TargetLanguage.flag(choice.code), "🌐", choice.code)
            XCTAssertNotEqual(TargetLanguage.englishName(choice.code), choice.code == "tr" ? "" : "Turkish", choice.code)
        }
        XCTAssertEqual(TargetLanguage.flag("tr"), "🇹🇷")
        XCTAssertEqual(TargetLanguage.nativeName("hi"), "हिन्दी")
    }

    func testPreferredFollowsSystemLanguage() {
        XCTAssertEqual(TargetLanguage.preferred(["hi-IN"]), "hi")
        XCTAssertEqual(TargetLanguage.preferred(["fil-PH"]), "tl")
        XCTAssertEqual(TargetLanguage.preferred(["nl-NL", "en"]), "nl")
        XCTAssertEqual(TargetLanguage.preferred(["fi-FI"]), "tr")
        XCTAssertEqual(TargetLanguage.preferred(["en-US"]), "tr")
    }

    func testAlreadyInTargetByScript() {
        XCTAssertTrue(TargetLanguage.isAlready("ตั้งค่า", in: "th"))
        XCTAssertTrue(TargetLanguage.isAlready("सेटिंग्स", in: "hi"))
        XCTAssertTrue(TargetLanguage.isAlready("সেটিংস", in: "bn"))
        XCTAssertTrue(TargetLanguage.isAlready("ترتیبات", in: "ur"))
        XCTAssertFalse(TargetLanguage.isAlready("Where is the camp?", in: "th"))
        XCTAssertTrue(TargetLanguage.isRightToLeft("ur"))
        XCTAssertFalse(TargetLanguage.isRightToLeft("hi"))
    }

    func testDeepLOnlyForItsLanguages() {
        XCTAssertTrue(TargetLanguage.deepLSupports("id"))
        XCTAssertFalse(TargetLanguage.deepLSupports("hi"))
        XCTAssertFalse(TargetLanguage.deepLSupports("tl"))
    }

    func testAIPromptNamesTheChosenLanguage() {
        XCTAssertTrue(AIRequest.systemPrompt(for: "hi").contains("natural Hindi"))
        XCTAssertTrue(AIRequest.systemPrompt(for: "tl").contains("natural Filipino"))
        XCTAssertFalse(AIRequest.systemPrompt(for: "vi").contains("Arabic"))
        XCTAssertEqual(AIRequest.systemPrompt(for: "ar"), AIRequest.arabicSystemPrompt)
    }

    func testInterfaceFollowsTheTranslationLanguage() {
        XCTAssertEqual(TargetLanguage.interfaceLanguage("hi"), "hi")
        XCTAssertEqual(TargetLanguage.interfaceLanguage("tl"), "fil")
        XCTAssertEqual(TargetLanguage.interfaceLanguage("fr"), "en")
        XCTAssertTrue(TargetLanguage.isRightToLeft("ur"))
    }
}
