// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Nino: harita ekranında seçilen görevin bilgi kartı (GTA 6): büyük harfli başlık ("BUY FLOWERS"), altında bir iki
/// cümle ("Lucia will appreciate this", "Have some flowers delivered to the house for Lucia."). Menü çevrilmez ama bu
/// kartın Türkçesi kartın hemen altına yarı saydam yazılır (kullanıcı isteği, 19 Kasım 2026).
public enum MapCard {
    public struct Found: Equatable, Sendable {
        /// Başlık (yoksa boş) ve cümleler, yukarıdan aşağı; her cümle ayrı çevrilir.
        public var title: String
        public var sentences: [String]
        /// Kartın yazılarını çevreleyen kutu (0–1, kareye göre).
        public var box: TextBox
        public var lineHeight: Double
    }

    /// Harita ekranı mı: sağ alttaki tuş listesi ("RECENTER", "2D VIEW", "ADD MARKER", "SET DESTINATION", "CLOSE MENU").
    public static func isMapScreen(_ reading: Reading) -> Bool {
        let keys: Set<String> = ["recenter", "2d view", "3d view", "add marker", "remove marker", "set destination",
                                 "remove destination", "close menu"]
        let found = Set(reading.lines.map { MenuBlock.clean($0.text).lowercased() }.filter(keys.contains))
        return found.count >= 2
    }

    /// Haritadaki kart: ekranın sol menüsü ve sağ alttaki tuş listesi dışında kalan, alt alta duran cümle satırları ve
    /// hemen üstlerindeki büyük harfli başlık.
    public static func find(in reading: Reading) -> Found? {
        let lines = reading.lines.compactMap { line -> (text: String, box: TextBox)? in
            guard let box = line.box, box.left > 0.30 else { return nil }
            let text = line.text.trimmingCharacters(in: .whitespaces)
            return text.filter(\.isLetter).count >= 2 ? (text, box) : nil
        }.sorted { $0.box.top < $1.box.top }
        // Cümle satırı: küçük harfli, en az üç sözcük (yer adları ve uzaklıklar değil).
        func isSentence(_ text: String) -> Bool {
            text.split(separator: " ").count >= 3 && text.filter(\.isLowercase).count >= 6
        }
        let body = lines.filter { isSentence($0.text) }
        guard let first = body.first else { return nil }
        // İlk cümleyle aynı kartta olanlar: alt alta (aralarında en çok bir buçuk satır) ve yatayda üst üste.
        var card = [first]
        for line in body.dropFirst() {
            guard let last = card.last else { break }
            let height = last.box.bottom - last.box.top
            if line.box.top - last.box.bottom < height * 1.5, line.box.left < last.box.right, last.box.left < line.box.right,
               abs(line.box.left - first.box.left) < 0.06 {
                card.append(line)
            }
        }
        // Cümleler: sol kenarı aynı olan art arda satırlar tek cümledir ("Have some flowers delivered to the" + "house
        // for Lucia."); simgeyle başlayan satır ("♥ Lucia will appreciate this") biraz içeridedir, ayrı cümledir.
        // Erken biten satırdan (sağ kenara varmadan) sonra büyük harfle başlayan satır da yeni cümledir.
        let reach = card.map(\.box.right).max() ?? 1
        var sentences: [[(text: String, box: TextBox)]] = []
        for line in card {
            if let head = sentences.last?.first, let last = sentences.last?.last, abs(line.box.left - head.box.left) < 0.012,
               !(last.box.right < reach - 0.04 && line.text.first?.isUppercase == true) {
                sentences[sentences.count - 1].append(line)
            } else {
                sentences.append([line])
            }
        }
        let top = first.box
        let title = lines.last { line in
            line.box.bottom <= top.top + 0.01 && top.top - line.box.bottom < 0.06
                && line.box.left < top.right && top.left < line.box.right + 0.05
                && line.text == line.text.uppercased() && line.text.filter(\.isLetter).count >= 3
        }
        var box = card.dropFirst().reduce(first.box) { $0.union($1.box) }
        if let title { box = box.union(title.box) }
        let heights = card.map { $0.box.bottom - $0.box.top }.sorted()
        return Found(title: title?.text ?? "", sentences: sentences.map { $0.map(\.text).joined(separator: " ") },
                     box: box, lineHeight: heights[heights.count / 2])
    }
}
