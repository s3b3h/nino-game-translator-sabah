// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// Nino: Arapça hedefte satırlar Apple'ın çevirisinden gelir; Türkçeye özel işlemler (sözlük, ekler, düzeltmeler) çalışmaz.
final class ArabicTargetTests: XCTestCase {
    func testCacheFilesAreSeparatePerTarget() {
        let directory = URL(fileURLWithPath: "/tmp/nino-cache")
        let turkish = TranslationCache.file(in: directory, engine: Translator.engineID, source: "en", target: "tr")
        let arabic = TranslationCache.file(in: directory, engine: Translator.engineID, source: "en", target: "ar")
        XCTAssertNotEqual(turkish, arabic)
        XCTAssertTrue(arabic.lastPathComponent.hasSuffix("-en-ar.jsonl"))
    }

    /// Gerçek Apple çevirisi: konuşmacı adı korunur, Türkçe harf çıkmaz (dil paketi yoksa atlanır).
    func testAppleTranslatesEnglishToArabic() async throws {
        guard await Translator.status(source: "en", target: "ar") == .ready else {
            throw XCTSkip("Apple'ın İngilizce→Arapça dil paketi bu bilgisayarda yüklü değil")
        }
        let translator = Translator(source: "en", target: "ar", cache: TranslationCache(),
                                    glossary: GlossaryStore.builtInOnly())
        let line = try await translator.translate("ARTHUR: Where is the camp? We have to go, Dutch.")
        XCTAssertTrue(TargetLanguage.containsArabic(line), line)
        XCTAssertTrue(line.hasPrefix("ARTHUR:"), line)
        XCTAssertFalse(line.contains(where: { "ıİğĞşŞ".contains($0) }), line)
        print("Arapça deneme satırı: \(line)")
    }
}

/// Nino: çevrimiçi motorlar Arapça hedefte Arapça istemle gider; Türkçe istem ve Türkçe sözlük kullanılmaz.
final class ArabicPromptTests: XCTestCase {
    func testAIRequestUsesArabicPrompt() throws {
        let model = AIProvider.gemini.model(nil)
        let request = AIRequest.make(provider: .gemini, key: "k", model: model, sentences: ["Stay close."],
                                     context: [AIContextLine(source: "Arthur?", translation: "آرثر؟")], target: "ar")
        let body = try XCTUnwrap(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8))
        XCTAssertTrue(body.contains("Modern Standard Arabic"), body)
        XCTAssertTrue(body.contains("into Arabic"), body)
        XCTAssertFalse(body.contains("Turkish"), body)
        XCTAssertEqual(AIRequest.systemPrompt(for: "tr"), AIRequest.systemPrompt)
    }

    func testTranslationModelsGetArabicPrompt() {
        XCTAssertTrue(TranslateGemma.prompt("Hi", target: "ar").contains("English (en) to Arabic (ar)"))
        XCTAssertEqual(MiLMMT.prompt("Hi", target: "ar"), "Translate this from English to Arabic:\nEnglish: Hi\nArabic:")
        XCTAssertEqual(MiLMMT.prompt("Hi"), "Translate this from English to Turkish:\nEnglish: Hi\nTurkish:")
    }

    func testFirstLaunchFollowsSystemLanguage() {
        XCTAssertEqual(TargetLanguage.preferred(["ar-SA", "en"]), "ar")
        XCTAssertEqual(TargetLanguage.preferred(["tr-TR"]), "tr")
        XCTAssertEqual(TargetLanguage.preferred(["en-US", "ar"]), "tr")
        XCTAssertEqual(TargetLanguage.preferred([]), "tr")
    }
}
