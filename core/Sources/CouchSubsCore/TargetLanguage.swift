// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import NaturalLanguage

/// Nino: yazı zaten hedef dilde mi (ör. PS5'in Türkçe menüleri)? Öyleyse çevirmene hiç gönderilmez; önceden çevrilip
/// "zaten hedef dilde" diye atılıyordu ve Gemini'nin günlük ücretsiz hakkını boşa harcıyordu.
public enum TargetLanguage {
    /// Nino: seçilebilen çeviri dilleri (kod, kendi dilindeki adı). Varsayılan Türkçe.
    public static let choices: [(code: String, name: String)] = [("tr", "Türkçe"), ("ar", "العربية")]

    /// Sözlük, ek kuralları, Türkçe düzeltmeler, oyun paketleri ve dublaj yalnız Türkçe hedefte çalışır. Çevrimiçi
    /// motorlar (yapay zekâ, DeepL) Arapçaya da çevirir; istemleri hedef dile göre yazılır.
    public static func isTurkish(_ target: String) -> Bool { code(target) == "tr" }

    /// İstemlerde kullanılan İngilizce dil adı.
    public static func englishName(_ target: String) -> String {
        switch code(target) {
        case "ar": "Arabic"
        default: "Turkish"
        }
    }

    /// Nino: ilk açılışta çeviri dili: sistemin dili Arapçaysa Arapça, değilse Türkçe.
    public static func preferred(_ languages: [String] = Locale.preferredLanguages) -> String {
        languages.first.map(code) == "ar" ? "ar" : "tr"
    }

    /// Sağdan sola yazılan hedef dil mi (Arapça).
    public static func isRightToLeft(_ target: String) -> Bool { ["ar", "fa", "he", "ur"].contains(code(target)) }

    /// Yalnız o dilde bulunan harfler: İngilizce bir oyun yazısında bunlardan biri varsa yazı hedef dildedir.
    static let ownLetters: [String: Set<Character>] = [
        "tr": ["ı", "İ", "ğ", "Ğ", "ş", "Ş"],
    ]

    /// Arap yazısının harfleri (Arapça, ek harfler ve sunum biçimleri).
    public static func isArabicLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0620...0x064A, 0x066E...0x06D3, 0x06FA...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF,
             0xFB50...0xFDFF, 0xFE70...0xFEFF: true
        default: false
        }
    }

    /// Yazıda Arap harfi var mı (TV'de ve altyazı penceresinde yön buna göre seçilir).
    public static func containsArabic(_ text: String) -> Bool { text.unicodeScalars.contains(where: isArabicLetter) }

    /// Sağdan sola gösterim için: her paragrafın başına sağdan sola işareti (U+200F) konur. Böylece Latin harfli
    /// konuşmacı adıyla başlayan satır ("ATREUS: …") da sağdan sola dizilir. Arap harfi yoksa yazı olduğu gibi döner.
    public static func displayText(_ text: String) -> String {
        guard containsArabic(text) else { return text }
        let mark = "\u{200F}"
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix(mark) ? String($0) : mark + $0 }.joined(separator: "\n")
    }

    public static func isAlready(_ text: String, in target: String, source: String = "en") -> Bool {
        let target = code(target)
        if let letters = ownLetters[target], text.contains(where: letters.contains) { return true }
        // Arap harfli yazı İngilizce kaynakta çıkmaz: Arapça hedefte bu yazı zaten Arapçadır (PS5'in Arapça menüleri).
        if target == "ar", containsArabic(text) { return true }
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

    private static func code(_ language: String) -> String { String(language.prefix(2)).lowercased() }
}
