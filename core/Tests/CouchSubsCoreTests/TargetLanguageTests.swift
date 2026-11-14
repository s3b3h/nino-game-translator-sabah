// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// Nino: PS5'in Türkçe menüleri çevirmene gitmez; oyunun İngilizce yazıları gider.
final class TargetLanguageTests: XCTestCase {
    func testTurkishMenusAreAlreadyTurkish() {
        for text in ["Kaydedilen Veriler ve Oyun/Uygulama Ayarları", "Oyunlar Medya İçerikleri",
                     "Yakalanan Görüntüler ve Yayınlar", "Kullanıcılar ve Hesaplar",
                     "tion Plus aboneliğinizdeki Oyun Kataloğu'na dahildir"] {
            XCTAssertTrue(TargetLanguage.isAlready(text, in: "tr"), text)
        }
    }

    func testGameEnglishIsTranslated() {
        for text in ["We never saw her again.", "Arthur?", "He was a very sad man and the drink had a mean hold on him.",
                     "Chase down and lasso the O'Driscoll", "STUDIO / RED DEAD / REDEMPTION", "Hold ✕ to aim",
                     "Get back on the wagon", "What's the problem between you two?", "Ride to camp"] {
            XCTAssertFalse(TargetLanguage.isAlready(text, in: "tr"), text)
        }
    }

    func testBlockWithATurkishLineIsTheConsoleScreen() {
        XCTAssertTrue(TargetLanguage.hasLine("Oyunlar Medya İçerikleri\nshare\nSTUDIO I\nRED DEAD", in: "tr"))
        XCTAssertFalse(TargetLanguage.hasLine("AUDIO\nControls the volume of dialogue relative to\nSFX and music.", in: "tr"))
    }

    func testOtherTargetsUseOnlyTheRecognizer() {
        XCTAssertFalse(TargetLanguage.isAlready("We never saw her again.", in: "de"))
    }
}

/// Nino: yan yana okunan aynı simge tek simgedir (RDR2: "Hold ✕ to maintain the horse's canter").
final class DuplicateIconTests: XCTestCase {
    func testRepeatedIconCollapses() {
        XCTAssertEqual(ButtonPrompts.normalizedIcons("Hold ✕ ✕ to maintain the horse's canter"), "Hold ✕ to maintain the horse's canter")
        XCTAssertEqual(ButtonPrompts.normalizedIcons("Press ○ ○ ○ quickly"), "Press ○ quickly")
        XCTAssertEqual(ButtonPrompts.normalizedIcons("Use ← → to choose"), "Use ← → to choose")
    }
}
