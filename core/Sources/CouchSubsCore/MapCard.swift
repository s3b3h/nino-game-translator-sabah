// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
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
            guard var box = line.box, box.right > 0.30 else { return nil }
            var text = line.text.trimmingCharacters(in: .whitespaces)
            // Haritadaki uzaklık etiketi ("1.53 km") kartın satırıyla birlikte okunabiliyor; atılır ve satırın sol kenarı
            // kartın içinden sayılır (yoksa alttaki satırlar hizasız sanılıp atılıyordu).
            let distance = #"\s*\b\d+(?:[.,]\d+)?\s?(?:km|mi|ft|m)\b\s*"#
            if text.range(of: distance, options: .regularExpression) != nil {
                text = text.replacingOccurrences(of: distance, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                if box.left < 0.5 { box.left = max(box.left, 0.5) }
            }
            // Haritadaki simge harf/sayı okunup satırın başına eklenebiliyor ("(43) Cal challenged…"); atılır, sol kenar
            // kalan yazıya göre kaydırılır.
            if let lead = text.range(of: #"^(?:[^A-Za-z\s]+\s+)+(?=[A-Z])"#, options: .regularExpression) {
                let share = Double(text.distance(from: text.startIndex, to: lead.upperBound)) / Double(max(1, text.count))
                box.left += (box.right - box.left) * share
                text.removeSubrange(lead)
            }
            guard box.left > 0.30, text.filter(\.isLetter).count >= 3 else { return nil }
            return text.filter(\.isLetter).count >= 2 ? (text, box) : nil
        }.sorted { $0.box.top < $1.box.top }
        // Cümle satırı: küçük harfli, en az üç sözcük (yer adları ve uzaklıklar değil).
        func isSentence(_ text: String) -> Bool {
            text.split(separator: " ").count >= 3 && text.filter(\.isLowercase).count >= 6
        }
        let body = lines.filter { isSentence($0.text) }
        guard let first = body.first else { return nil }
        // İlk cümleyle aynı kartta olanlar: alt alta (aralarında en çok bir buçuk satır) ve yatayda üst üste.
        // Nino: cümlenin kısa son satırı ("nearby ATMs") ve paragraf boşluğundan sonraki ikinci paragraf ("Make a cash
        // deposit into your BuckMe / checking account at an ATM.") da karttadır; eskiden atlanıyor, Türkçe yarım kalıyor ve
        // kartın içine düşüyordu. Cümle olmayan satır yalnız bir önceki satırın hemen altında ve aynı hizadaysa alınır.
        var card = [first]
        for line in lines where line.box.top > first.box.top {
            guard let last = card.last else { break }
            let height = last.box.bottom - last.box.top, gap = line.box.top - last.box.bottom
            let overlaps = line.box.left < last.box.right && last.box.left < line.box.right
            if isSentence(line.text), gap < height * 2.6, overlaps, abs(line.box.left - first.box.left) < 0.06 {
                card.append(line)
            } else if gap < height * 1.2, abs(line.box.left - last.box.left) < 0.03, line.text.contains(where: \.isLowercase),
                      !(last.text.last.map { ".!?".contains($0) } ?? false) {
                card.append(line)
            }
        }
        // Cümleler: sol kenarı aynı olan art arda satırlar tek cümledir ("Have some flowers delivered to the" + "house
        // for Lucia."); simgeyle başlayan satır ("♥ Lucia will appreciate this") biraz içeridedir, ayrı cümledir.
        // Erken biten satırdan (sağ kenara varmadan) sonra büyük harfle başlayan satır da yeni cümledir.
        let reach = card.map(\.box.right).max() ?? 1
        var sentences: [[(text: String, box: TextBox)]] = []
        for line in card {
            // Paragraf boşluğu (satır yüksekliğinden büyük) yeni cümle başlatır; simge ("i Use the…") sol kenarı kaydırır.
            // Küçük harfle başlayan satır her zaman önceki cümlenin devamıdır ("… dropped off" / "at his trailer.").
            let continues = line.text.first?.isLowercase == true && !(sentences.last?.last?.text.last.map { ".!?".contains($0) } ?? true)
            if let head = sentences.last?.first, let last = sentences.last?.last,
               continues || (abs(line.box.left - head.box.left) < 0.03 && line.box.top - last.box.bottom < (last.box.bottom - last.box.top) * 1.0
                   && !(last.box.right < reach - 0.04 && line.text.first?.isUppercase == true)) {
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
        // Kartın altındaki hedef satırı ("GOAL  $100 / $5,000") cümle değildir ama karttadır; Türkçe onun üstüne binmesin.
        for line in lines where line.box.top >= box.bottom - 0.005 {
            guard line.box.top - box.bottom < 0.05, line.box.left > box.left - 0.03, line.box.right < box.right + 0.08 else { continue }
            box = box.union(line.box)
        }
        let heights = card.map { $0.box.bottom - $0.box.top }.sorted()
        // Bilgi simgesi ("ⓘ") harf okunur ("i Use the index…"); cümleye katılmaz.
        // Simge kırıntıları ("4 ml", "△", "00") baştan atılır.
        // Satır sonunda tireyle bölünen kelime ("burned-" / "out the") birleşik kalır: "burned-out the".
        let texts = sentences.map { $0.map(\.text).joined(separator: " ").replacingOccurrences(of: "- ", with: "-")
            .replacingOccurrences(of: #"^([iI•●◆△▲]|\S*\d\S*|ml)(\s+([iI•●◆△▲]|\S*\d\S*|ml))*\s+(?=[A-Z])"#, with: "", options: .regularExpression) }
        let heading = (title?.text ?? "").replacingOccurrences(of: #"(\s+[^A-Za-z\s]{1,3})+$"#, with: "", options: .regularExpression)
        return Found(title: heading, sentences: texts,
                     box: box, lineHeight: heights[heights.count / 2])
    }

    /// Nino (kullanıcı: "karenin köşelerini sınır almalı, metni değil"): kartın koyu çerçevesi, haritanın aydınlık
    /// zemininden ayrılarak görüntüden bulunur. Yazıların kutusundan dışa doğru koyu kısım bitene kadar gidilir.
    public static func frame(around box: TextBox, in image: CGImage) -> TextBox? {
        let color = PhonePanel.sampler(for: image, width: 640, height: 360)
        func dark(_ x: Double, _ y: Double) -> Bool {
            guard let c = color(x, y) else { return false }
            return (c.r * 299 + c.g * 587 + c.b * 114) / 1000 < 130
        }
        let rows = stride(from: box.top + 0.01, to: box.bottom, by: 0.02).map { $0 }
        let columns = stride(from: box.left + 0.01, to: box.right, by: 0.03).map { $0 }
        guard !rows.isEmpty, !columns.isEmpty else { return nil }
        // Bir yönde koyu satır/sütunların çoğu bitene kadar ilerlenir.
        func edge(from start: Double, step: Double, limit: Double, darkAt: (Double) -> Int, total: Int) -> Double {
            var position = start
            while abs(position - start) < limit, darkAt(position + step) * 2 >= total { position += step }
            return position
        }
        // Kenar sınıra kadar bulunamadıysa (gece haritası da koyu) o yanda yazıların kutusu biraz paylı kullanılır.
        func bounded(_ found: Double, _ start: Double, _ limit: Double, _ fallback: Double) -> Double {
            abs(found - start) >= limit - 0.004 ? fallback : found
        }
        let left = bounded(edge(from: box.left, step: -0.003, limit: 0.04, darkAt: { x in rows.filter { dark(x, $0) }.count }, total: rows.count),
                           box.left, 0.04, box.left - 0.015)
        let right = bounded(edge(from: box.right, step: 0.003, limit: 0.09, darkAt: { x in rows.filter { dark(x, $0) }.count }, total: rows.count),
                            box.right, 0.09, box.right + 0.02)
        let bottom = bounded(edge(from: box.bottom, step: 0.004, limit: 0.08, darkAt: { y in columns.filter { dark($0, y) }.count }, total: columns.count),
                             box.bottom, 0.08, box.bottom + 0.02)
        let top = bounded(edge(from: box.top, step: -0.004, limit: 0.06, darkAt: { y in columns.filter { dark($0, y) }.count }, total: columns.count),
                          box.top, 0.06, box.top - 0.02)
        // Kart en az yazıların kutusu kadardır; koyu zemin bulunamadıysa (karanlık harita) yazıların kutusu kullanılır.
        guard right - left > box.right - box.left else { return nil }
        return TextBox(left: left, top: top, right: right, bottom: bottom)
    }
}
