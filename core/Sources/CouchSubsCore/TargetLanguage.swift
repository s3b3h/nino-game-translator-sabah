// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import NaturalLanguage

/// Nino: yazı zaten hedef dilde mi (ör. PS5'in Türkçe menüleri)? Öyleyse çevirmene hiç gönderilmez; önceden çevrilip
/// "zaten hedef dilde" diye atılıyordu ve Gemini'nin günlük ücretsiz hakkını boşa harcıyordu.
public enum TargetLanguage {
    /// Nino: seçilebilen çeviri dilleri (kod, kendi dilindeki adı). Varsayılan ve ilk sıradaki Türkçe. GTA 6 gibi
    /// oyunların altyazı listesinde olmayan diller. Filipince, `prefix(2)` ile Fince ("fi") sanılmasın diye Tagalogca
    /// koduyla ("tl") tutulur.
    public static let choices: [(code: String, name: String)] = [
        ("tr", "Türkçe"), ("ar", "العربية"), ("hi", "हिन्दी"), ("id", "Bahasa Indonesia"), ("th", "ไทย"),
        ("vi", "Tiếng Việt"), ("ur", "اردو"), ("bn", "বাংলা"), ("ms", "Bahasa Melayu"), ("tl", "Filipino"),
        ("nl", "Nederlands"),
    ]

    /// Dilin bayrağı (seçicide adın önünde).
    public static func flag(_ target: String) -> String {
        [
            "tr": "🇹🇷", "ar": "🇸🇦", "hi": "🇮🇳", "id": "🇮🇩", "th": "🇹🇭", "vi": "🇻🇳", "ur": "🇵🇰", "bn": "🇧🇩",
            "ms": "🇲🇾", "tl": "🇵🇭", "nl": "🇳🇱",
        ][code(target)] ?? "🌐"
    }

    /// Dilin kendi adı ("Türkçe", "हिन्दी"); listede yoksa kodu.
    public static func nativeName(_ target: String) -> String {
        choices.first { $0.code == code(target) }?.name ?? target
    }

    /// Nino: Türkçe ve Arapça dışındaki dillerde deneme ekranının üç satırı (İngilizcesi ve çevirisi; Android'deki ile aynı).
    public static func sampleLines(_ target: String) -> [(source: String, translation: String)] {
        let english = ["Who's there?", "They're coming. Stay out of sight.", "Get to the rooftop. Now!"]
        let translated: [String]
        switch code(target) {
        case "hi": translated = ["वहाँ कौन है?", "वे आ रहे हैं। नज़रों से दूर रहो।", "छत पर जाओ। अभी!"]
        case "id": translated = ["Siapa di sana?", "Mereka datang. Jangan sampai terlihat.", "Naik ke atap. Sekarang!"]
        case "th": translated = ["ใครอยู่ตรงนั้น?", "พวกมันมาแล้ว อย่าให้ใครเห็น", "ขึ้นไปบนดาดฟ้า เดี๋ยวนี้!"]
        case "vi": translated = ["Ai ở đó?", "Chúng đang đến. Đừng để bị nhìn thấy.", "Lên sân thượng. Ngay!"]
        case "ur": translated = ["وہاں کون ہے؟", "وہ آ رہے ہیں۔ نظروں سے دور رہو۔", "چھت پر جاؤ۔ ابھی!"]
        case "bn": translated = ["ওখানে কে?", "ওরা আসছে। চোখের আড়ালে থাকো।", "ছাদে যাও। এখনই!"]
        case "ms": translated = ["Siapa di sana?", "Mereka datang. Jangan sampai dilihat.", "Naik ke bumbung. Sekarang!"]
        case "tl": translated = ["Sino'ng nandiyan?", "Paparating na sila. Huwag kang magpapakita.", "Umakyat ka sa bubong. Ngayon na!"]
        case "nl": translated = ["Wie is daar?", "Ze komen eraan. Blijf uit het zicht.", "Ga naar het dak. Nu!"]
        default: return []
        }
        return zip(english, translated).map { ($0, $1) }
    }

    /// Sözlük, ek kuralları, Türkçe düzeltmeler, oyun paketleri ve dublaj yalnız Türkçe hedefte çalışır. Çevrimiçi
    /// motorlar (yapay zekâ, DeepL) öbür dillere de çevirir; istemleri hedef dile göre yazılır.
    public static func isTurkish(_ target: String) -> Bool { code(target) == "tr" }

    /// İstemlerde kullanılan İngilizce dil adı.
    public static func englishName(_ target: String) -> String {
        switch code(target) {
        case "ar": "Arabic"
        case "hi": "Hindi"
        case "id": "Indonesian"
        case "th": "Thai"
        case "vi": "Vietnamese"
        case "ur": "Urdu"
        case "bn": "Bengali"
        case "ms": "Malay"
        case "tl": "Filipino"
        case "nl": "Dutch"
        default: "Turkish"
        }
    }

    /// DeepL'in çevirebildiği hedef diller (Hintçe, Urduca, Bengalce, Malayca ve Filipince yok).
    public static func deepLSupports(_ target: String) -> Bool {
        ["tr", "ar", "id", "th", "vi", "nl"].contains(code(target))
    }

    /// Nino: ilk açılışta çeviri dili: sistemin dili listedeyse o, değilse Türkçe.
    public static func preferred(_ languages: [String] = Locale.preferredLanguages) -> String {
        guard let first = languages.first else { return "tr" }
        let language = first.lowercased().hasPrefix("fil") ? "tl" : code(first)
        return choices.contains { $0.code == language } ? language : "tr"
    }

    /// Nino: arayüzün dili çeviri dilini izler; listedeki her dilin arayüz çevirisi var. Apple Filipinceyi "fil" koduyla
    /// tanır (çeviri dilinde "tl" tutulur).
    public static func interfaceLanguage(_ target: String) -> String {
        let language = code(target)
        guard choices.contains(where: { $0.code == language }) else { return "en" }
        return language == "tl" ? "fil" : language
    }

    /// Sağdan sola yazılan hedef dil mi (Arapça).
    public static func isRightToLeft(_ target: String) -> Bool { ["ar", "fa", "he", "ur"].contains(code(target)) }

    /// Yalnız o dilde bulunan harfler: İngilizce bir oyun yazısında bunlardan biri varsa yazı hedef dildedir.
    static let ownLetters: [String: Set<Character>] = [
        "tr": ["ı", "İ", "ğ", "Ğ", "ş", "Ş"],
    ]

    /// Kendine özgü yazısı olan diller: Tay, Devanagari (Hintçe), Bengal.
    static let ownScript: [String: ClosedRange<UInt32>] = ["th": 0x0E00...0x0E7F, "hi": 0x0900...0x097F, "bn": 0x0980...0x09FF]

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
        if let letters = ownLetters[target], text.contains(where: letters.contains) {
            return !isSourceWithOneStrayWord(text, letters: letters, target: target, source: source)
        }
        // Arap harfli yazı İngilizce kaynakta çıkmaz: Arapça hedefte bu yazı zaten Arapçadır (PS5'in Arapça menüleri).
        if target == "ar" || target == "ur", containsArabic(text) { return true }
        // Kendi yazısı olan diller: o yazının harfi İngilizce kaynakta çıkmaz.
        if let range = ownScript[target], text.unicodeScalars.contains(where: { range.contains($0.value) }) { return true }
        // Kendine özgü harfi olmayan kısa yazı (ör. "Ayarlar") için dil tanıyıcı; yalnız emin olduğunda.
        let words = text.split(whereSeparator: { !$0.isLetter }).filter { $0.count > 1 }
        guard words.count >= 3 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [NLLanguage(target), NLLanguage(String(source.prefix(2)).lowercased())]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        return (hypotheses[NLLanguage(target)] ?? 0) >= 0.9
    }

    /// Nino: hedef dile özgü harf tek bir sözcükteyse ve geri kalanı açıkça kaynak dildeyse yazı kaynak dildedir. Yazı
    /// tanıma yanındaki tuş simgesini harf sanıp sözcüğe yapıştırabiliyor (GTA 6: "Sure beats jailsır"): satır "zaten
    /// Türkçe" sayılıp gösterilmiyor, önceki kısa çevirinin kutusu bu uzun İngilizcenin üstünde kalıp iki yanından taşıyordu.
    static func isSourceWithOneStrayWord(_ text: String, letters: Set<Character>, target: String, source: String) -> Bool {
        let words: [String] = text.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 1 }
        let marked: [String] = words.filter { word in word.contains(where: { letters.contains($0) }) }
        let rest: [String] = words.filter { word in !word.contains(where: { letters.contains($0) }) }
        guard marked.count == 1, rest.count >= 3 else { return false }
        let sourceLanguage = NLLanguage(code(source))
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [NLLanguage(target), sourceLanguage]
        recognizer.processString(rest.joined(separator: " "))
        let confidence: Double = recognizer.languageHypotheses(withMaximum: 2)[sourceLanguage] ?? 0
        return confidence >= 0.9
    }

    /// Okunan bloğun herhangi bir satırı hedef dildeyse blok oyunun değil konsolun ekranıdır (PS5 menüsü, ana ekran).
    public static func hasLine(_ text: String, in target: String, source: String = "en") -> Bool {
        text.split(separator: "\n").contains { isAlready(String($0), in: target, source: source) }
    }

    private static func code(_ language: String) -> String { String(language.prefix(2)).lowercased() }
}
