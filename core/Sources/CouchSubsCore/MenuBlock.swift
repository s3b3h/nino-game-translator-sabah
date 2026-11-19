// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Nino: oyunun menüleri (duraklatma menüsü: "Map / Game / Store / Help", "Retry Checkpoint / Restart Mission").
/// Menü satırları kısadır ve alt alta, sol ya da sağ kenarları hizalı durur. Türkçesi satırın üstüne değil yanına yazılır
/// (seçili satırın şeridi ve simgeler görünür kalsın): sola yaslı menüde sağına, sağa yaslı menüde soluna.
public enum MenuBlock {
    public struct Group: Equatable, Sendable {
        public var lines: [TextLine]
        /// Satırların sağ kenarı hizalı (Türkçesi soluna yazılır).
        public var rightAligned: Bool
    }

    /// En az bu kadar satır alt alta ve hizalıysa menüdür.
    static let minimumLines = 3
    /// Kenar hizası payı (ekran oranı).
    static let edgeTolerance = 0.012
    /// İki menü satırı arasındaki en büyük boşluk (ekran yüksekliği oranı).
    static let maximumGap = 0.13

    /// Okumadaki menüler (en çok iki: sola ve sağa yaslı). Altyazı ve uzun yazılar menü sayılmaz.
    public static func groups(in reading: Reading) -> [Group] {
        let candidates = reading.lines.filter(isMenuLine)
        var used = Set<Int>()
        var result: [Group] = []
        for rightAligned in [false, true] {
            let edge: (TextLine) -> Double = { rightAligned ? $0.box!.right : $0.box!.left }
            let indices = candidates.indices.filter { !used.contains($0) }.sorted { edge(candidates[$0]) < edge(candidates[$1]) }
            var cluster: [Int] = []
            func close() {
                defer { cluster = [] }
                guard cluster.count >= minimumLines else { return }
                // Dikeyde ardışık ve sık: aradaki boşluk büyükse menü değil, ekranda ayrı yazılar.
                let sorted = cluster.sorted { candidates[$0].box!.top < candidates[$1].box!.top }
                var run: [Int] = []
                var runs: [[Int]] = []
                for index in sorted {
                    if let last = run.last, candidates[index].box!.top - candidates[last].box!.bottom > maximumGap {
                        runs.append(run)
                        run = []
                    }
                    run.append(index)
                }
                runs.append(run)
                for run in runs where run.count >= minimumLines {
                    run.forEach { used.insert($0) }
                    result.append(Group(lines: run.map { candidates[$0] }, rightAligned: rightAligned))
                }
            }
            for index in indices {
                if let first = cluster.first, edge(candidates[index]) - edge(candidates[first]) > edgeTolerance { close() }
                cluster.append(index)
            }
            close()
        }
        return result
    }

    /// Harita, duraklatma ve oyun içi menü ekranı mı: ekranda bu sekme/menü sözcüklerinden en az ikisi tek başına
    /// satır olarak duruyorsa ("MAP", "BRIEF", "PROGRESS", "SETTINGS"…). Bu ekranlarda tuş ipuçları çevrilmez.
    public static func isMenuScreen(_ reading: Reading) -> Bool {
        let words: Set<String> = ["map", "brief", "progress", "settings", "stats", "gallery", "online", "inventory", "store",
                                  "help", "photo studio", "game", "journal", "options", "wardrobe", "outfits", "missions",
                                  // Eşya inceleme ekranı (defter, not, fotoğraf): el yazısı altyazı sanılmasın.
                                  "show text", "hide text", "flip", "put back", "rotate", "inspect", "examine", "read"]
        // Dükkân ve araç tamiri ekranı: aracın özellik çubukları ("SPEED", "ACCELERATION", "ASPHALT HANDLING", "RATING").
        let shop: Set<String> = ["speed", "acceleration", "handling", "rating", "upgrade", "performance", "respray", "purchase",
                                 "owned", "braking", "armor", "armour"]
        var found = Set<String>()
        for line in reading.lines {
            let text = clean(line.text).lowercased()
            if words.contains(text) { found.insert(text) }
            for word in text.split(whereSeparator: { !$0.isLetter }).map(String.init) where shop.contains(word) { found.insert(word) }
            // Sekme şeridi tek satır okunabilir: "JASON & LUCIA MAP BRIEF PROGRESS".
            for word in text.split(separator: " ").map(String.init) where ["map", "brief", "progress"].contains(word) { found.insert(word) }
        }
        return found.count >= 2
    }

    /// Kısa (1-4 sözcük), harfli, bir satırlık yazı.
    static func isMenuLine(_ line: TextLine) -> Bool {
        guard let box = line.box, box.bottom - box.top < 0.07 else { return false }
        let text = line.text.trimmingCharacters(in: .whitespaces)
        let words = text.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }
        return (1...4).contains(words.count) && text.count <= 30 && !text.hasSuffix(".") && !text.hasSuffix("?")
    }

    /// Menü satırının yazısı simgelerden arınmış hâliyle: yazı tanıma satırın başındaki ve sonundaki simgeleri ("⊙", "0]",
    /// "1") harf sanabiliyor. Baştaki ve sondaki harfsiz parçalar atılır ("Chapter 1" gibi sayılar sözcükten sonra kalır).
    public static func clean(_ text: String) -> String {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = words.first, !first.contains(where: \.isLetter) || (first.count <= 2 && !first.allSatisfy(\.isLetter)) {
            words.removeFirst()
        }
        // Simge çoğu zaman küçük harf sanılır ("i Settings", "ii Map", "Il Game"): ardından büyük harfli sözcük gelen 1-2
        // harflik baştaki küçük harfli parça atılır.
        while words.count >= 2, let first = words.first, first.count <= 2,
              !first.contains(where: \.isUppercase) || first == "Il" || first == "II",
              words[1].first?.isUppercase == true {
            words.removeFirst()
        }
        while let last = words.last, !last.contains(where: { $0.isLetter || $0.isNumber }) { words.removeLast() }
        return words.joined(separator: " ")
    }

    /// Sık menü sözcüklerinin oyunlardaki yerleşik Türkçesi (yalnız Türkçe çeviride). Model tek sözcüğü bağlamsız
    /// çevirince "Settings" → "ayarlarım" gibi yanlışlar çıkıyordu.
    public static func knownTurkish(_ text: String) -> String? {
        let key = text.lowercased().trimmingCharacters(in: .whitespaces)
        if let hit = turkish[key] { return hit }
        if key.hasPrefix("chapter "), let number = key.split(separator: " ").last, number.allSatisfy(\.isNumber) { return "Bölüm \(number)" }
        return nil
    }

    private static let turkish: [String: String] = [
        "map": "Harita", "game": "Oyun", "store": "Mağaza", "help": "Yardım", "photo studio": "Fotoğraf Stüdyosu",
        "settings": "Ayarlar", "options": "Seçenekler", "resume": "Devam Et", "continue": "Devam Et", "quit": "Çık",
        "quit game": "Oyundan Çık", "exit": "Çık", "back": "Geri", "select": "Seç", "save": "Kaydet", "load": "Yükle",
        "load game": "Oyun Yükle", "new game": "Yeni Oyun", "save game": "Oyunu Kaydet", "inventory": "Envanter",
        "stats": "İstatistikler", "brief": "Özet", "journal": "Günlük", "gallery": "Galeri", "online": "Çevrim İçi",
        "story mode": "Hikâye Modu", "retry checkpoint": "Kontrol Noktasından Tekrar Dene", "restart mission": "Görevi Yeniden Başlat",
        "restart": "Yeniden Başlat", "skip": "Atla", "replay mission": "Görevi Tekrar Oyna", "audio": "Ses", "display": "Ekran",
        "controls": "Kontroller", "graphics": "Grafik", "accessibility": "Erişilebilirlik", "language": "Dil", "credits": "Jenerik",
        "friends": "Arkadaşlar", "messages": "Mesajlar", "contacts": "Kişiler", "phone": "Telefon", "camera": "Kamera",
        "missions": "Görevler", "objectives": "Hedefler", "weapons": "Silahlar", "vehicles": "Araçlar", "apparel": "Kıyafet",
        "gone fishing": "Balığa Gitti",
    ]

    /// Satırın Türkçesinin yeri: sola yaslı menüde satırın sağında, sağa yaslı menüde solunda; genişlik yazının uzunluğuna
    /// göre (TV harf başına yaklaşık satır yüksekliğinin yarısı kadar yer kaplar; 16:9 ekranda yatay oran 9/16).
    /// Menünün bütün satırlarının Türkçesi düzgün bir sütunda: sola yaslı menüde en uzun satırın sağında aynı hizada,
    /// sağa yaslı menüde en soldaki satırın solunda aynı hizada (kelimelere yapışmaz, birbirine binmez).
    public static func placeColumn(_ group: Group, translations: [String]) -> [TextBox] {
        let gap = 0.03
        let edge = group.rightAligned ? group.lines.compactMap { $0.box?.left }.min() ?? 0.5
                                      : group.lines.compactMap { $0.box?.right }.max() ?? 0.5
        return zip(group.lines, translations).map { line, translation in
            let box = line.box!
            let height = box.bottom - box.top
            let width = min(0.42, max(0.05, Double(translation.count) * height * 0.55 * 9 / 16 + 0.02))
            if group.rightAligned {
                let right = max(width, edge - gap)
                return TextBox(left: max(0, right - width), top: box.top, right: right, bottom: box.bottom)
            }
            let left = min(1 - width, edge + gap)
            return TextBox(left: left, top: box.top, right: min(1, left + width), bottom: box.bottom)
        }
    }

    public static func placeBeside(_ line: TextLine, translation: String, rightAligned: Bool) -> TextBox {
        let box = line.box!
        let height = box.bottom - box.top
        let width = min(0.45, max(0.06, Double(translation.count) * height * 0.55 * 9 / 16 + 0.02))
        let gap = 0.015
        if rightAligned {
            let right = max(width, box.left - gap)
            return TextBox(left: max(0, right - width), top: box.top, right: right, bottom: box.bottom)
        }
        let left = min(1 - width, box.right + gap)
        return TextBox(left: left, top: box.top, right: min(1, left + width), bottom: box.bottom)
    }
}
