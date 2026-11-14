// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import NaturalLanguage

/// Nino: yazı zaten hedef dilde mi (ör. PS5'in Türkçe menüleri)? Öyleyse çevirmene hiç gönderilmez; önceden çevrilip
/// "zaten hedef dilde" diye atılıyordu ve Gemini'nin günlük ücretsiz hakkını boşa harcıyordu.
public enum TargetLanguage {
    /// Yalnız o dilde bulunan harfler: İngilizce bir oyun yazısında bunlardan biri varsa yazı hedef dildedir.
    static let ownLetters: [String: Set<Character>] = [
        "tr": ["ı", "İ", "ğ", "Ğ", "ş", "Ş"],
    ]

    public static func isAlready(_ text: String, in target: String, source: String = "en") -> Bool {
        let target = String(target.prefix(2)).lowercased()
        if let letters = ownLetters[target], text.contains(where: letters.contains) { return true }
        // Kendine özgü harfi olmayan kısa yazı (ör. "Ayarlar") için dil tanıyıcı; yalnız emin olduğunda.
        let words = text.split(whereSeparator: { !$0.isLetter }).filter { $0.count > 1 }
        guard words.count >= 3 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [NLLanguage(target), NLLanguage(String(source.prefix(2)).lowercased())]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        return (hypotheses[NLLanguage(target)] ?? 0) >= 0.9
    }

    /// Okunan bloğun herhangi bir satırı hedef dildeyse blok oyunun değil konsolun ekranıdır (PS5 menüsü, ana ekran).
    public static func hasLine(_ text: String, in target: String, source: String = "en") -> Bool {
        text.split(separator: "\n").contains { isAlready(String($0), in: target, source: source) }
    }
}
