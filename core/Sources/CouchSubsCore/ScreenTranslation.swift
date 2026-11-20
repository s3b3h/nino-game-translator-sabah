// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// "Ekranı çevir": karenin tamamı bir kez okunur, yazılar yerlerine göre gruplara ayrılır (menü, görev paneli, bilgi
/// kutusu, altyazı...) ve her grup ayrı çevrilir. TV her çeviriyi kendi İngilizce yazısının üstüne, o yazının
/// boyutunda koyar (Windows: CouchSubs.Core/ScreenTranslation.cs ile aynı kurallar).
public enum ScreenTranslation {
    /// Ekrandaki bir yazı grubu.
    public struct Group: Equatable, Sendable {
        /// Ayrı ayrı çevrilecek parçalar (başlık, cümle, menü satırı...).
        public var paragraphs: [String]
        /// Karedeki yeri, kenarlara oranla.
        public var box: TextBox
        /// Satırlarının tipik yüksekliği, karenin yüksekliğine oranla; TV yazı boyunu buna göre seçer.
        public var lineHeight: Double
    }

    public struct Item: Equatable, Sendable {
        public var source: String
        /// Parçaların çevirisi, her parça ayrı satırda.
        public var translation: String
        public var box: TextBox
        public var lineHeight: Double
        /// Nino: kutusuz, oyunun kendi yazısı gibi gölgeli sade yazı (sol üstteki görevin altına konan çeviri).
        public var plain = false
        /// Nino: eğik yazı (telefon araması: "Paradise Taxi aranıyor…").
        public var italic = false
        /// Nino: oyunun kendi kutusunun rengi ("#e9e9ec"); verilmişse Türkçe o kutunun tam üstüne, aynı zeminle ve
        /// `ink` renginde yazılır, orijinal yazı gibi durur (GTA 6 telefon mesaj balonları).
        public var fill: String?
        public var ink: String?
        /// Nino: yazının dönme açısı (derece, saat yönü artı): eğik tutulan telefonun balonları da eğiktir.
        public var angle: Double?
        /// Nino: zeminin saydamlığı (0–1; `fill` ile). Telefonun yanındaki balonlar biraz saydamdır.
        public var alpha: Double?
        /// Nino: oyunun kutusunun üstünde değil yanında duran balon (TV daha yuvarlak, gölgeli çizer).
        public var side = false
        /// Nino: yazısız zemin (telefonun yanındaki mesajlaşma paneli); balonlar onun üstünde durur.
        public var backdrop = false
        /// Nino: harita kartının Türkçesi; TV oyunun kartı gibi çizer (koyu zemin, üstte pembe çizgi, ilk satır başlık).
        public var card = false

        public init(source: String, translation: String, box: TextBox, lineHeight: Double) {
            self.source = source
            self.translation = translation
            self.box = box
            self.lineHeight = lineHeight
        }

        /// Birden çok parça var: TV satır satır, sola yaslı gösterir.
        public var paragraphs: Bool { translation.contains("\n") }
    }

    /// Kalabalık ekranda TV'yi kutuyla doldurmamak ve çeviriyi uzatmamak için en çok bu kadar grup çevrilir.
    public static let maxGroups = 30

    /// Grupları sırayla çevirir; her grup çevrilince o ana kadarki sonuçlarla `progress` çağrılır. Çevirisi aslıyla
    /// aynı olan (ad, sayı, zaten Türkçe yazı) grup gösterilmez.
    public static func translate(_ reading: Reading, using translate: (String) async throws -> String,
                                 progress: ([Item]) -> Void = { _ in }) async throws -> [Item] {
        var items: [Item] = []
        for group in groups(reading) {
            try Task.checkCancellation()
            var translated: [String] = []
            for paragraph in group.paragraphs { translated.append(try await translatePreservingIcons(paragraph, using: translate)) }
            guard let item = item(group, translated) else { continue }
            items.append(item)
            progress(items)
        }
        return items
    }

    /// Nino: düğme simgeleri ("SELECT ✕ BACK ○", "Hold ● to continue") çevirmene "[1]" gibi yer tutucularla gider,
    /// çeviride aynı yere geri konur. Çevirmen yer tutucuyu düşürürse simge satırın başına eklenir.
    private static let turkish = Locale(identifier: "tr_TR")
    /// Büyük harfli menüde gerçek sözcük olabilen kısa parçalar.
    private static let shortWords: Set<String> = ["GO", "UP", "ON", "TO", "OF", "IN", "MY", "OK", "NO", "BY", "AT", "IT"]
    private static let instructionVerbs: Set<String> = ["press", "hold", "tap", "push", "use", "mash", "release", "double", "pull", "click"]

    static func translatePreservingIcons(_ text: String, using translate: (String) async throws -> String) async throws -> String {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.contains(where: ButtonPrompts.isIcon) else { return try await translate(text) }
        var icons: [String] = []
        let masked = tokens.map { token -> String in
            guard ButtonPrompts.isIcon(token) else { return token }
            icons.append(ButtonPrompts.display(token))
            return "[\(icons.count)]"
        }.joined(separator: " ")
        // Yalnız simgeden oluşan satır çevrilmez.
        if tokens.allSatisfy(ButtonPrompts.isIcon) { return icons.joined(separator: " ") }
        // Nino: menü açıklaması ("SELECT ✕  BACK ○", "✕ Select ○ Back"): her yazı parçası ayrı çevrilir, simgeler yerinde
        // kalır. Tek parça çevrilince çevirmen sözcükleri karıştırıyordu ("✕ Geri ○ seç").
        // Büyük harfli satırdaki iki harflik anlamsız parçalar ("MO", "BO") da simgedir; menü sayılmasında onlar da sayılır.
        let shoutingLine = text == text.uppercased()
        let junk = shoutingLine ? tokens.filter { !ButtonPrompts.isIcon($0) && $0.count <= 2 && !Self.shortWords.contains($0) }.count : 0
        // Büyük harfli tek simgeli menü öğesi ("MAINTAIN R3", "△ MOUNT HORSE") da parça parça çevrilir; bütün satır
        // çevrilince simge nesne sanılıyordu ("R3'i koru").
        let iconAtEdge = ButtonPrompts.isIcon(tokens.last!) || ButtonPrompts.isIcon(tokens[0])
        if icons.count + junk >= 2 || (shoutingLine && iconAtEdge && tokens.count <= 5),
           !Self.instructionVerbs.contains(tokens[0].lowercased()) {
            var parts: [String] = []
            var words: [String] = []
            func flush() async throws {
                guard !words.isEmpty else { return }
                let label = words.joined(separator: " ")
                words = []
                var text = try await translate(label).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { text = label }
                // Menü yazısı oyundaki gibi her sözcük büyük harfle başlar ("Fotoğraf Modu", "Seç", "Geri").
                parts.append(text.lowercased(with: Self.turkish).capitalized(with: Self.turkish))
            }
            let shouting = text == text.uppercased()
            for token in tokens {
                // Simgenin artığı ("#", "|", büyük harfli menüde tek "I") çevrilmez.
                // Büyük harfli menüde iki harflik parça da çoğunlukla simgedir (dokunmatik yüzey "▦" → "ME", "MI").
                if !ButtonPrompts.isIcon(token),
                   !token.contains(where: \.isLetter) || (shouting && token.count <= 2 && !Self.shortWords.contains(token)) {
                    // Simge artığı iki menü öğesini ayırır ("PHOTO MODE ▦ SELECT").
                    try await flush()
                    continue
                }
                if ButtonPrompts.isIcon(token) {
                    try await flush()
                    parts.append(ButtonPrompts.display(token))
                } else {
                    words.append(token)
                }
            }
            try await flush()
            return parts.joined(separator: " ")
        }
        var result = try await translate(masked)
        var missing: [String] = []
        for (i, icon) in icons.enumerated() {
            let mark = "[\(i + 1)]"
            if result.contains(mark) { result = result.replacingOccurrences(of: mark, with: icon) } else { missing.append(icon) }
        }
        return missing.isEmpty ? result : missing.joined(separator: " ") + " " + result
    }

    /// Çevirmen parçaları tek istekte çevirebiliyorsa (yapay zekâ) ekranın bütün parçaları birlikte gider ve sonuç bir
    /// kerede gelir; yoksa gruplar sırayla çevrilip hazırlandıkça bildirilir.
    public static func translate(_ reading: Reading, using translator: TextTranslator,
                                 progress: ([Item]) -> Void = { _ in }) async throws -> [Item] {
        guard translator.translatesTogether else {
            return try await translate(reading, using: { try await translator.translate($0) }, progress: progress)
        }
        let groups = groups(reading)
        let paragraphs = groups.flatMap(\.paragraphs)
        guard !paragraphs.isEmpty else { return [] }
        // Nino: düğme simgesi olan parça ("Hold ✕ to aim") simgesi korunarak tek tek çevrilir; kalanlar tek istekte gider.
        let withIcons = paragraphs.indices.filter { index in
            paragraphs[index].split(separator: " ").contains { ButtonPrompts.isIcon(String($0)) }
        }
        let plain = paragraphs.indices.filter { !withIcons.contains($0) }
        var translations = paragraphs
        let together = plain.isEmpty ? [] : try await translator.translateAll(plain.map { paragraphs[$0] })
        for (index, translation) in zip(plain, together) { translations[index] = translation }
        for index in withIcons {
            translations[index] = try await translatePreservingIcons(paragraphs[index], using: { try await translator.translate($0) })
        }
        try Task.checkCancellation()
        var items: [Item] = []
        var next = 0
        for group in groups {
            let count = group.paragraphs.count
            let translated = (next..<next + count).map { $0 < translations.count ? translations[$0] : paragraphs[$0] }
            next += count
            if let item = item(group, translated) { items.append(item) }
        }
        if !items.isEmpty { progress(items) }
        return items
    }

    /// Grubun gösterilecek çevirisi; çevirisi aslıyla aynıysa (ad, sayı, zaten Türkçe yazı) nil.
    private static func item(_ group: Group, _ translations: [String]) -> Item? {
        var changed = false
        let texts = zip(group.paragraphs, translations).map { paragraph, translation in
            var text = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { text = paragraph }
            changed = changed || !TextMatch.isSimilar(TextMatch.normalize(paragraph), TextMatch.normalize(text), threshold: 0.90)
            return text
        }
        guard changed else { return nil }
        return Item(source: group.paragraphs.joined(separator: "\n"), translation: texts.joined(separator: "\n"),
                    box: group.box, lineHeight: group.lineHeight)
    }

    /// Satırları gruplara toplar. Kumanda ipuçları ve yazı tanıma çöpleri atılır; harfi olmayan ya da tek harfli satırlar
    /// ("23m", "9", "+") göstergedir, çevrilmez. Bir satır, üstündeki satırın hemen altındaysa, yatayda onunla üst üste
    /// biniyorsa ve yazı boyu benziyorsa o gruba katılır. Gruplar yukarıdan aşağı, en çok `maxGroups`.
    public static func groups(_ reading: Reading) -> [Group] {
        // Nino: kumanda ipuçları da çevrilir; düğme simgeleri yerinde korunur (`translatePreservingIcons`).
        let lines = reading.withoutOcrNoise().lines
            .filter { $0.box != nil && isWords($0.text) }
            .sorted { $0.box!.top < $1.box!.top }
        // Nino: ipucu satırı ("R2 Swing") kendi grubunda çevrilir ama sütun sınırı sayılmaz (CouchSubs onu baştan atıyordu).
        let columnLines = lines.filter { !ButtonPrompts.isPrompt($0.text) }
        var groups: [[TextLine]] = []
        for line in lines {
            if let index = groups.lastIndex(where: { belongs(line.box!, below: $0.last!.box!) }),
               !bridgesColumns(groups[index].last!.box!, line.box!, columnLines),
               !bridgesColumns(line.box!, groups[index].last!.box!, columnLines) {
                groups[index].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.prefix(maxGroups).map { group in
            let heights = group.map { $0.box!.bottom - $0.box!.top }.sorted()
            let box = group.dropFirst().reduce(group[0].box!) { $0.union($1.box!) }
            return Group(paragraphs: paragraphs(group), box: box, lineHeight: heights[heights.count / 2])
        }
    }

    // Geniş başlık/alt satır iki bağımsız sütundan birine katılmasın. Filtrelenmiş OCR satırlarına bakılır.
    private static func bridgesColumns(_ wide: TextBox, _ column: TextBox, _ lines: [TextLine]) -> Bool {
        lines.contains { line in
            let peer = line.box!
            guard min(column.right, peer.right) <= max(column.left, peer.left) else { return false }
            let rowOverlap = min(column.bottom, peer.bottom) - max(column.top, peer.top)
            guard rowOverlap > 0, rowOverlap >= min(column.bottom - column.top, peer.bottom - peer.top) * 0.5 else { return false }
            return (belongs(column, below: wide) && belongs(peer, below: wide))
                || (belongs(wide, below: column) && belongs(wide, below: peer))
        }
    }

    /// Alt satır üsttekinin hemen altında (arada satır yüksekliğinin %80'inden az), yatayda onunla üst üste ve yazı boyu benzer.
    private static func belongs(_ lower: TextBox, below upper: TextBox) -> Bool {
        let a = upper.bottom - upper.top, b = lower.bottom - lower.top
        guard max(a, b) <= min(a, b) * 1.6 else { return false }
        guard lower.top - upper.bottom < max(a, b) * 0.8, lower.top >= upper.top else { return false }
        let overlap = min(lower.right, upper.right) - max(lower.left, upper.left)
        let narrower = min(lower.right - lower.left, upper.right - upper.left)
        return overlap > 0 && overlap >= narrower * 0.5
    }

    /// Önceki parça cümleyi bitirdiyse ya da kısa bir başlık/menü satırıysa (en çok üç sözcük, virgülsüz) ve yeni satır
    /// büyük harfle başlıyorsa yeni parça başlar; yoksa satır öncekinin devamıdır (cümle iki satıra sarılmış).
    static func paragraphs(_ lines: [TextLine]) -> [String] {
        var result: [String] = []
        for line in lines.map({ $0.text.trimmingCharacters(in: .whitespaces) }) {
            if let previous = result.last, !startsNew(after: previous, line) {
                result[result.count - 1] += " " + line
            } else {
                result.append(line)
            }
        }
        return result
    }

    private static func startsNew(after previous: String, _ line: String) -> Bool {
        if SubtitleStabilizer.endsSentence(previous) { return true }
        return line.first?.isUppercase == true && wordCount(previous) <= 3 && !previous.hasSuffix(",")
    }

    /// En az iki harfi ve iki harfli bir sözcüğü olan satır yazıdır; geri kalanı sayı ve simgedir.
    static func isWords(_ text: String) -> Bool {
        text.filter(\.isLetter).count >= 2 && text.split(whereSeparator: \.isWhitespace).contains { $0.filter(\.isLetter).count >= 2 }
    }

    private static func wordCount(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }

    /// Çevirilerin TV'de kalma süresi (ms): yazı çoksa daha uzun; tuşa yeniden basınca hemen kalkar.
    public static func displayMilliseconds(_ items: [Item]) -> Int {
        min(60000, max(12000, 8000 + items.reduce(0) { $0 + $1.translation.count } * 50))
    }
}
