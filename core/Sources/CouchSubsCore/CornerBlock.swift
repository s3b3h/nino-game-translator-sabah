// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Nino: sol üstteki ipucu kutusunu (RDR2'de "HELP" kutusu, görev kartı) haritadaki yer adlarından ayırır. Harita açıkken
/// aynı köşede dağınık yer adları okunuyordu ("CA" → "Kaliforniya", yan yazılmış "Dakota River" ekranı boydan boya
/// kaplayan dar bir kutu). İpucu kutusu alt alta, birbirine yakın, yatay satırlardan oluşan bir bloktur ve birkaç
/// kelimelik bir cümle içerir; yer adları ise tek tek, kısa ve dağınıktır.
public enum CornerBlock {
    /// Bloğun çevrilmeye değmesi için en az kelime sayısı ("Cumberland Falls" gibi iki kelimelik yer adı geçmez).
    public static let minimumWords = 4

    /// Okunan satırlardan ipucu kutusunu seçer; yoksa boş okuma döner. `aspect`: ekranın en/boy oranı (kutular 0–1).
    public static func tipBox(in reading: Reading, aspect: Double = 16.0 / 9.0) -> Reading {
        let candidates = reading.lines.filter { line in
            guard let box = line.box else { return false }
            // Yan ya da dik yazılmış yazı (harita) atlanır: gerçek en/boy oranıyla yatay olmalı.
            guard (box.right - box.left) * aspect > (box.bottom - box.top) * 1.2 else { return false }
            // "CA", "NH" gibi kısaltmalar ve tek harfler atlanır.
            return line.text.filter(\.isLetter).count >= 3
        }
        .sorted { ($0.box?.top ?? 0) < ($1.box?.top ?? 0) }

        var blocks: [[TextLine]] = []
        for line in candidates {
            guard let box = line.box else { continue }
            if var block = blocks.last, let last = block.last?.box, let span = Self.span(of: block) {
                let height = Self.medianHeight(block)
                let close = box.top - last.bottom <= height * 1.8
                let overlaps = box.left < span.right && box.right > span.left
                if close && overlaps {
                    block.append(line)
                    blocks[blocks.count - 1] = block
                    continue
                }
            }
            blocks.append([line])
        }
        guard let best = blocks.max(by: { Self.words($0) < Self.words($1) }), Self.words(best) >= minimumWords else {
            return Reading(lines: [])
        }
        return Reading(lines: best)
    }

    static func words(_ block: [TextLine]) -> Int {
        block.reduce(0) { $0 + $1.text.split(whereSeparator: { !$0.isLetter && $0 != "'" }).filter { $0.count >= 2 }.count }
    }

    private static func span(of block: [TextLine]) -> (left: Double, right: Double)? {
        let boxes = block.compactMap(\.box)
        guard let left = boxes.map(\.left).min(), let right = boxes.map(\.right).max() else { return nil }
        return (left, right)
    }

    private static func medianHeight(_ block: [TextLine]) -> Double {
        let heights = block.compactMap { $0.box.map { $0.bottom - $0.top } }.sorted()
        return heights.isEmpty ? 0.03 : heights[heights.count / 2]
    }
}
