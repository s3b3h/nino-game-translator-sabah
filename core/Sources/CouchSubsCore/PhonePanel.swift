// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Nino: oyundaki telefonun ekranı (GTA 6: dikey, beyaz, büyük dikdörtgen). Telefon açıkken içindeki yazılar altyazı
/// değildir: siyah altyazı kutusunda değil, telefonun yanında yarı saydam yazıyla gösterilir.
public enum PhonePanel {
    /// Bulunan ekran. Yaya hâlde telefon eğik tutulur: ekran bir paralelkenardır, aşağı indikçe sola ya da sağa kayar.
    public struct Panel: Equatable, Sendable {
        /// Ekranı çevreleyen dikdörtgen (0–1, kareye göre).
        public var box: TextBox
        /// Üst kenarda ekranın sol kenarı (x).
        public var topLeft: Double
        /// Eğim: bir kare yüksekliği aşağı inince sol kenarın x olarak kayması (dik telefonda 0).
        public var lean: Double
        /// Ekranın genişliği (her satırda aynı).
        public var width: Double

        public init(box: TextBox, topLeft: Double, lean: Double, width: Double) {
            self.box = box
            self.topLeft = topLeft
            self.lean = lean
            self.width = width
        }

        /// `y` yüksekliğinde ekranın sol kenarı ve ortası.
        public func left(at y: Double) -> Double { topLeft + lean * (y - box.top) }
        public func center(at y: Double) -> Double { left(at: y) + width / 2 }
    }

    /// Karede telefonun beyaz ekranı; yoksa nil.
    ///
    /// Kare küçültülür ve her satırda en uzun beyaz şerit aranır. Telefonun ekranı çok sayıda satırda aynı genişlikte,
    /// kenarları bir doğru üzerinde duran şerit verir; hemen iki yanında telefonun siyah çerçevesi vardır. Gökyüzü ve
    /// duvarlar ya çok geniştir ya kenarları satırdan satıra oynar ya da çerçevesi yoktur.
    public static func find(in frame: CGImage) -> Panel? {
        let width = 240, height = 135
        guard let pixels = rgba(frame, width: width, height: height) else { return nil }
        func low(_ x: Int, _ y: Int) -> (low: Int, spread: Int) {
            let i = (y * width + x) * 4
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            let low = min(r, g, b)
            return (low, max(r, g, b) - low)
        }
        return find(width: width, height: height,
                    isWhite: { x, y in let p = low(x, y); return p.low >= whiteFloor && p.spread <= 45 },
                    isDark: { x, y in low(x, y).low < darkCeiling })
    }

    /// Bir renk kanalı en az bu kadar parlaksa (ve üçü birbirine yakınsa) nokta beyaz sayılır. Gece telefonun ekranı
    /// kısılır ve sarımsı olur (araçta ≈185–225, yaya gece ≈130–175); gündüz 250'dir. Eşik düşüktür; telefonu asıl
    /// ayıran şekli, sabit genişliği ve iki yanındaki siyah çerçevedir.
    static let whiteFloor = 118
    /// Telefonun siyah çerçevesi: ekranın hemen solu ve sağı bundan koyu olmalı (duvar, gökyüzü, tabela değil).
    static let darkCeiling = 90
    /// Telefon ekranının genişliği (kare genişliğine oranla).
    static let widthRange = 0.12...0.30
    /// Telefon ekranının ortasının durabileceği yer (x; gerçek karelerde yaya ≈0.48, araçta ≈0.69).
    static let centerRange = 0.30...0.80
    /// Telefon ekranının yüksekliği (kare yüksekliğine oranla).
    static let heightRange = 0.38...0.86

    /// Beyaz/koyu nokta haritasında telefonun ekranı (sınama için ayrı).
    static func find(width: Int, height: Int, isWhite: (Int, Int) -> Bool, isDark: (Int, Int) -> Bool) -> Panel? {
        // Her satırın telefon genişliğindeki beyaz şeritleri. Yazının ince çizgileri şeridi bölmez (≤3 nokta).
        var runs: [[(start: Int, end: Int)]] = Array(repeating: [], count: height)
        let minRun = Int(Double(width) * widthRange.lowerBound), maxRun = Int(Double(width) * widthRange.upperBound)
        for y in 0..<height {
            var x = 0
            while x < width {
                guard isWhite(x, y) else { x += 1; continue }
                var end = x, probe = x + 1
                while probe < width, probe - end <= 4 {
                    if isWhite(probe, y) { end = probe }
                    probe += 1
                }
                let length = end - x + 1
                if length >= minRun, length <= maxRun { runs[y].append((x, end)) }
                x = end + 1
            }
        }
        // Sol kenar bir doğrudur: başlangıç = a + eğim·satır. Her eğim için en çok satırın paylaştığı (a, genişlik) aranır;
        // dik telefon (eğim 0) eşitlikte öne geçer.
        var best: (votes: Int, slope: Double, key: Int) = (0, 0, 0)
        let slopes = [0.0] + (1...15).flatMap { [Double($0) * 0.02, Double($0) * -0.02] }
        for slope in slopes {
            var votes: [Int: Int] = [:]
            for (y, row) in runs.enumerated() {
                for run in row {
                    let intercept = Int((Double(run.start) - slope * Double(y)).rounded())
                    votes[(intercept + 400) / 2 * 1000 + (run.end - run.start) / 2, default: 0] += 1
                }
            }
            if let top = votes.max(by: { $0.value < $1.value }), top.value > best.votes { best = (top.value, slope, top.key) }
        }
        guard best.votes >= 8 else { return nil }
        let guess = Double(best.key / 1000 * 2 - 400), span = best.key % 1000 * 2
        func leftEdge(_ y: Int, _ intercept: Double) -> Double { intercept + best.slope * Double(y) }
        // Her satırda ekrana uyan şerit (varsa).
        var fit: [Int: (start: Int, end: Int)] = [:]
        for (y, row) in runs.enumerated() {
            if let run = row.first(where: { abs(Double($0.start) - leftEdge(y, guess)) <= 3.5 && abs($0.end - $0.start - span) <= 4 }) {
                fit[y] = run
            }
        }
        var rows = fit.keys.sorted()
        guard rows.count >= 8 else { return nil }
        let intercepts = rows.map { Double(fit[$0]!.start) - best.slope * Double($0) }.sorted()
        let intercept = intercepts[intercepts.count / 2]
        let widths = rows.map { fit[$0]!.end - fit[$0]!.start }.sorted()
        let runWidth = widths[widths.count / 2]
        func left(_ y: Int) -> Int { Int(leftEdge(y, intercept).rounded()) }
        // Siyah çerçeve: bu satırların çoğunda ekranın hemen solu ve sağı koyu.
        let framed = rows.filter { y in
            isDark(max(0, left(y) - 3), y) && isDark(min(width - 1, left(y) + runWidth + 3), y)
        }
        guard Double(framed.count) >= Double(rows.count) * 0.7 else { return nil }
        // Üst ve alt kenar: şeridin yarıdan çoğu beyaz olduğu sürece (kişi resimleri, balonlar satırı bölse de) ekrandır.
        func bright(_ y: Int) -> Bool {
            let from = max(0, left(y)), to = min(width - 1, left(y) + runWidth)
            guard to > from else { return false }
            return Double((from...to).filter { isWhite($0, y) }.count) >= Double(to - from + 1) * 0.5
        }
        var first = rows[0], last = rows[rows.count - 1]
        while first > 0, bright(first - 1) { first -= 1 }
        while last < height - 1, bright(last + 1) { last += 1 }
        rows = rows.filter { $0 >= first && $0 <= last }
        let tall = Double(last - first + 1) / Double(height)
        // Ekranın en az dörtte biri baştan sona beyaz olmalı (fotoğraflı sohbette resim satırları beyaz değildir).
        guard heightRange.contains(tall), Double(rows.count) >= Double(last - first + 1) * 0.25 else { return nil }
        // Dikey dikdörtgen (nokta olarak yükseklik/genişlik; kare 16:9).
        let shape = (tall * 9) / (Double(runWidth + 1) / Double(width) * 16)
        guard (1.2...2.6).contains(shape) else { return nil }
        let w = Double(width), h = Double(height)
        let topLeft = leftEdge(first, intercept), bottomLeft = leftEdge(last, intercept)
        let box = TextBox(left: max(0, min(topLeft, bottomLeft)) / w, top: Double(first) / h,
                          right: min(w, max(topLeft, bottomLeft) + Double(runWidth + 1)) / w, bottom: Double(last + 1) / h)
        // Telefon ekranın ortasında (yaya) ya da sağ yarısında (araçta) durur ve kenarlara değmez; kenardaki aydınlık
        // duvar ve kapılar (içeride, gece) telefon değildir.
        guard centerRange.contains((box.left + box.right) / 2), box.top >= 0.04, box.bottom <= 0.96 else { return nil }
        // Eğim: nokta/satır → kare genişliği / kare yüksekliği.
        return Panel(box: box, topLeft: topLeft / w, lean: best.slope * h / w, width: Double(runWidth + 1) / w)
    }

    private static func rgba(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}

/// Nino: telefondaki sohbet ekranının mesajları ve Türkçelerinin telefonun yanındaki yeri.
public enum PhoneThread {
    public struct Message: Equatable, Sendable {
        public var text: String
        public var box: TextBox
        public var lineHeight: Double
    }

    /// Telefon ekranındaki okuma (`reading`, kareye göre yerleşmiş) bir sohbet mi: en üstte, ekranın ortasında kişinin adı
    /// durur ("Kenton"). Mesaj listesinde en üstteki yazı sola yaslıdır ("Suggested", kişi adları); liste çevrilmez.
    public static func isThread(_ reading: Reading, panel: PhonePanel.Panel) -> Bool {
        let height = panel.box.bottom - panel.box.top
        let boxes = reading.lines.compactMap(\.box)
        return reading.lines.contains { line in
            guard let box = line.box, box.top < panel.box.top + height * headerShare else { return false }
            let text = line.text.trimmingCharacters(in: .whitespaces)
            let middle = (box.top + box.bottom) / 2
            guard MessageCard.isName(text) || (text.count >= 2 && text.allSatisfy { $0.isLetter || $0 == " " }),
                  abs((box.left + box.right) / 2 - panel.center(at: middle)) < panel.width * 0.08 else { return false }
            // Listede adın hemen altında, aynı hizada önizleme satırı durur ("Chuck's Gun Shop" / "Hey Jason. You good?");
            // sohbet başlığının altında aynı hizada satır yoktur.
            let indent = box.left - panel.left(at: box.top)
            return !boxes.contains { other in
                other.top > box.top + 0.008 && other.top < box.top + 0.05
                    && abs(other.left - panel.left(at: other.top) - indent) < 0.015
            }
        }
    }

    /// Telefon ekranının en üstündeki başlık şeridi (ekran yüksekliğine oranla).
    static let headerShare = 0.07

    /// Sohbet ekranındaki mesajlar, yukarıdan aşağı. Başlık (kişinin adı), "New message", yer/eşya etiketleri
    /// ("Stoplight Parrotfish Spot") ve harfsiz satırlar mesaj değildir.
    public static func messages(in reading: Reading, panel found: PhonePanel.Panel) -> [Message] {
        let panel = found.box
        let panelHeight = panel.bottom - panel.top
        let lines = reading.lines.compactMap { line -> (text: String, box: TextBox)? in
            guard let box = line.box else { return nil }
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard text.filter(\.isLetter).count >= 2 else { return nil }
            // En üstteki başlık şeridi: kişinin adı ve geri oku.
            guard box.top > panel.top + panelHeight * headerShare else { return nil }
            // Ekranın alt kenarında yarısı görünen satır (kaydırırken) okunamaz; çöp çıkar.
            guard box.bottom < panel.bottom - 0.01 else { return nil }
            return (text, box)
        }.sorted { $0.box.top < $1.box.top }
        // Satır aralığı: art arda iki satırın üst kenarları arasındaki en küçük fark. Eğik telefonda okuyucunun kutuları
        // şişer ve üst üste biner; paragraf, kutular arasındaki boşlukla değil satır aralığıyla ayrılır.
        let steps = zip(lines, lines.dropFirst()).map { $1.box.top - $0.box.top }.filter { $0 >= 0.012 && $0 <= 0.04 }
        let pitch = steps.min() ?? (lines.map { $0.box.bottom - $0.box.top }.min() ?? 0.025) * 1.2
        var groups: [[(text: String, box: TextBox)]] = []
        for line in lines {
            // Eğik telefonda paragrafın satırları aşağı indikçe yana kayar: sol kenar ekranın kenarına göre ölçülür.
            let indent = line.box.left - found.left(at: line.box.top)
            if let last = groups.last?.last, let head = groups.last?.first,
               line.box.top - last.box.top < pitch * 1.6,
               abs(indent - (head.box.left - found.left(at: head.box.top))) < 0.02 {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.compactMap { group in
            let text = group.map(\.text).joined(separator: " ")
            guard !isLabel(text) else { return nil }
            let box = group.dropFirst().reduce(group[0].box) { $0.union($1.box) }
            return Message(text: text, box: box, lineHeight: pitch * 0.85)
        }
    }

    /// Mesaj olmayan satır: "New message", "Typing...", ek olarak gönderilen yer ya da eşyanın adı (her sözcüğü büyük
    /// harfle başlar, cümle noktalaması yoktur).
    static func isLabel(_ text: String) -> Bool {
        let lowered = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".…• "))
        if ["new message", "new messages", "typing", "delivered", "read", "today", "yesterday", "messages encrypted"].contains(lowered) { return true }
        let words = text.split(separator: " ")
        guard words.count >= 2, !text.contains(where: { ".,!?…".contains($0) }) else { return false }
        return words.allSatisfy { word in
            guard let first = word.first else { return false }
            return first.isUppercase || ["del", "de", "la", "of", "the", "&"].contains(word.lowercased())
        }
    }

    /// Türkçelerin duracağı sütun: telefonun boş kalan (geniş) yanında, en çok `maxWidth` genişliğinde.
    public static func column(beside found: PhonePanel.Panel, maxWidth: Double = 0.30) -> (left: Double, right: Double) {
        let panel = found.box
        let gap = 0.035
        if (panel.left + panel.right) / 2 > 0.5 {
            let right = panel.left - gap
            return (max(0.02, right - maxWidth), right)
        }
        let left = panel.right + gap
        return (left, min(0.98, left + maxWidth))
    }

    /// Her çevirinin kutusu: mesajın hizasında, sütunun içinde; üst üste binmesinler diye gerekirse aşağı kayar.
    public static func boxes(for messages: [Message], lineCounts: [Int], lineHeights: [Double],
                             column: (left: Double, right: Double)) -> [TextBox] {
        var result: [TextBox] = []
        var floor = 0.0
        for (index, message) in messages.enumerated() {
            let height = lineHeights[index] * Double(max(1, lineCounts[index])) * 1.3
            let top = min(max(message.box.top, floor), max(0, 0.98 - height))
            result.append(TextBox(left: column.left, top: top, right: column.right, bottom: top + height))
            floor = top + height + lineHeights[index] * 0.6
        }
        return result
    }
}
