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

        /// Telefonun dönme açısı (derece, saat yönü artı; kare 16:9). Aşağı indikçe sol kenar sola kayıyorsa telefonun
        /// üstü sağa yatmıştır: saat yönünde dönmüştür.
        public var angle: Double { atan(-lean * 16 / 9) * 180 / .pi }

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
        if let light = find(width: width, height: height,
                            isWhite: { x, y in let p = low(x, y); return p.low >= whiteFloor && p.spread <= 45 },
                            isDark: { x, y in low(x, y).low < darkCeiling }) {
            return light
        }
        // Nino: telefon elde bir süre dokunulmadan durunca ekranı kararıyor (gece sahnesinde beyaz ekran ≈70). Kare
        // karanlıksa ortasındaki en aydınlık kısım beyaza çekilip beyaz ekran yeniden aranır (köşelerdeki parlak HUD
        // yazıları hesaba katılmaz).
        var middle: [Int] = []
        for y in stride(from: height / 10, to: height * 9 / 10, by: 2) {
            for x in stride(from: width * 15 / 100, to: width * 85 / 100, by: 2) { middle.append(low(x, y).low) }
        }
        middle.sort()
        let bright = middle.isEmpty ? 0 : middle[middle.count * 95 / 100]
        if bright >= 40, bright < whiteFloor {
            let gain = 225.0 / Double(bright)
            func lifted(_ x: Int, _ y: Int) -> (low: Int, spread: Int) {
                let p = low(x, y)
                return (Int(Double(p.low) * gain), Int(Double(p.spread) * gain))
            }
            if let dim = find(width: width, height: height,
                              isWhite: { x, y in let p = lifted(x, y); return p.low >= whiteFloor && p.spread <= 45 },
                              isDark: { x, y in lifted(x, y).low < darkCeiling }) {
                return dim
            }
        }
        // Nino: koyu temalı uygulama (GTA 6 Rydeme): ekran koyu, çevresindeki gövde açık. Beyaz ekran aranırken telefon
        // bulunamıyor, içindeki yazılar altyazı ve mesaj kartı sanılıyordu. Aynı şekil sınamaları tersine çevrilmiş renklerle.
        guard let dark = find(width: width, height: height,
                              isWhite: { x, y in let p = low(x, y); return p.low + p.spread <= darkScreenCeiling && p.spread <= 40 },
                              isDark: { x, y in let p = low(x, y); return p.low + p.spread >= bezelFloor }),
              dark.box.bottom <= 0.96 else { return nil }
        // Koyu kıyafet ya da gölge de koyu dikdörtgen verebiliyor (Lucia'nın kapüşonlusu, Jason'ın sırtı): koyu ekranın
        // satırlarının belirgin bir kısmında beyaz yazı noktaları olmalı.
        let top = Int(dark.box.top * Double(height)), bottom = Int(dark.box.bottom * Double(height))
        var texty = 0
        for y in top..<max(top + 1, bottom) {
            let from = Int(dark.left(at: Double(y) / Double(height)) * Double(width)) + 2
            let to = from + Int(dark.width * Double(width)) - 4
            guard to > from else { continue }
            let bright = (from...to).filter { let p = low(min(width - 1, max(0, $0)), y); return p.low + p.spread >= darkTextFloor }.count
            if bright >= 2, Double(bright) <= Double(to - from + 1) * 0.6 { texty += 1 }
        }
        return Double(texty) >= Double(max(1, bottom - top)) * darkTextShare ? dark : nil
    }

    /// Koyu ekranın satırlarının en az bu kadarında beyaz yazı noktası olmalı.
    static let darkTextShare = 0.15
    /// Küçültülmüş karede koyu ekrandaki yazının noktası (bulanıklaşmış beyaz): en parlak kanalı en az bu kadar.
    static let darkTextFloor = 110

    /// Koyu temalı ekran: en parlak kanal bundan koyu.
    static let darkScreenCeiling = 75
    /// Koyu ekranın çevresindeki gövde ekrandan belirgin açıktır: en parlak kanalı en az bu kadar (gölgedeki kenar da).
    static let bezelFloor = 85

    /// Bir renk kanalı en az bu kadar parlaksa (ve üçü birbirine yakınsa) nokta beyaz sayılır. Gece telefonun ekranı
    /// kısılır ve sarımsı olur (araçta ≈185–225, yaya gece ≈130–175); gündüz 250'dir. Eşik düşüktür; telefonu asıl
    /// ayıran şekli, sabit genişliği ve iki yanındaki siyah çerçevedir.
    /// Telefon ekranında uyan iki satır arasındaki en uzun boşluk (küçültülmüş karede satır).
    static let maxRowGap = 10
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
                // Gümüş çerçevenin 1-2 noktalık parlak çizgisi, araya giren koyu boşluk kısa olduğu için ekranın şeridine
                // ekleniyor ve sol kenarı kaydırıyordu (GTA 6, Kenton sohbeti: telefon bulunamıyordu). Şeridin başındaki ve
                // sonundaki böyle kırıntılar atılır.
                var start = x, finish = end
                func crumbLength(from: Int, step: Int) -> Int {
                    var n = 0, p = from
                    while p >= start, p <= finish, isWhite(p, y) { n += 1; p += step }
                    return n
                }
                while finish - start > 6 {
                    let head = crumbLength(from: start, step: 1)
                    guard head <= 2, !isWhite(start + head, y), !isWhite(start + head + 1, y) else { break }
                    start += head
                    while start < finish, !isWhite(start, y) { start += 1 }
                }
                while finish - start > 6 {
                    let tail = crumbLength(from: finish, step: -1)
                    guard tail <= 2, !isWhite(finish - tail, y), !isWhite(finish - tail - 1, y) else { break }
                    finish -= tail
                    while finish > start, !isWhite(finish, y) { finish -= 1 }
                }
                let length = finish - start + 1
                if length >= minRun, length <= maxRun { runs[y].append((start, finish)) }
                x = end + 1
            }
        }
        // Sol kenar bir doğrudur: başlangıç = a + eğim·satır. Her eğim için en çok satırın paylaştığı (a, genişlik) aranır.
        // Her eğimin en güçlü birkaç adayı; en çok oy alandan başlanarak sınamaları geçen ilk aday telefondur. Telefonun
        // üstündeki aydınlık pencere bazen daha çok oy alıyor, telefon (mesaj listesinde resimler satırları böler) ikinci
        // kalıyordu.
        var candidates: [(votes: Int, slope: Double, key: Int)] = []
        let slopes = [0.0] + (1...15).flatMap { [Double($0) * 0.02, Double($0) * -0.02] }
        for slope in slopes {
            var votes: [Int: Int] = [:]
            for (y, row) in runs.enumerated() {
                for run in row {
                    let intercept = Int((Double(run.start) - slope * Double(y)).rounded())
                    votes[(intercept + 400) / 2 * 1000 + (run.end - run.start) / 2, default: 0] += 1
                }
            }
            for top in votes.sorted(by: { $0.value > $1.value }).prefix(3) where top.value >= 8 {
                candidates.append((top.value, slope, top.key))
            }
        }
        // Eşitlikte dik telefon (eğim 0, listede önce) öne geçer: sıralama kararlıdır.
        candidates = candidates.enumerated().sorted { $0.element.votes != $1.element.votes ? $0.element.votes > $1.element.votes : $0.offset < $1.offset }.map(\.element)
        func attempt(_ best: (votes: Int, slope: Double, key: Int)) -> Panel? {
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
        // Telefonun üstündeki aydınlık pencere de aynı hizada ve genişlikte beyaz verebiliyor; telefon ona eklenince ekranın
        // üst kenarına dayanıyor ve reddediliyordu (GTA 6, Kenton sohbeti). Uyan satırlar uzun boşluklarla parçalara
        // ayrılır; başka parça varken karenin üst ya da alt kenarına değen parça atılır. (Sohbetteki fotoğraf da ekranı
        // ikiye böler; o parçalar kenara değmez, birlikte kalır.)
        var clusters: [[Int]] = []
        for y in rows {
            if let last = clusters.last?.last, y - last <= maxRowGap { clusters[clusters.count - 1].append(y) } else { clusters.append([y]) }
        }
        let inner = clusters.filter { $0.first! > 1 && $0.last! < height - 2 }
        if clusters.count > 1, !inner.isEmpty { rows = inner.flatMap { $0 } }
        guard rows.count >= 8 else { return nil }
        let intercepts = rows.map { Double(fit[$0]!.start) - best.slope * Double($0) }.sorted()
        let intercept = intercepts[intercepts.count / 2]
        let widths = rows.map { fit[$0]!.end - fit[$0]!.start }.sorted()
        let runWidth = widths[widths.count / 2]
        func left(_ y: Int) -> Int { Int(leftEdge(y, intercept).rounded()) }
        // Siyah çerçeve: bu satırların çoğunda ekranın hemen solu ve sağı koyu. GTA 6'nın gümüş telefonunda koyu kısım
        // ekranın kenarındaki 1-2 noktalık çizgidir, dışı açık gridir; tam 3 nokta dışarıya bakılınca gümüşe denk gelip
        // telefon hiç bulunamıyordu (sohbet altyazı sanılıyordu). Koyu nokta kenarın 1-4 nokta yakınında aranır.
        let framed = rows.filter { y in
            (1...4).contains { isDark(max(0, left(y) - $0), y) }
                && (1...4).contains { isDark(min(width - 1, left(y) + runWidth + $0), y) }
        }
        // Nino (kullanıcı: "telefon çok bariz"): gündüz telefonun bir yanı güneşli tahta, korkuluk olabiliyor; o satırlarda
        // dışı koyu değil ama beyaz da değil. Satırların çoğunda iki yanı beyaz olmayan (ekrandan ayrışan) ve en az üçte
        // birinde koyu çerçeveli beyaz şerit de telefondur. Gökyüzü, pencere gibi dışı da beyaz alanlar yine elenir.
        let edged = rows.filter { y in
            (1...4).contains { !isWhite(max(0, left(y) - $0), y) }
                && (1...4).contains { !isWhite(min(width - 1, left(y) + runWidth + $0), y) }
        }
        guard Double(framed.count) >= Double(rows.count) * 0.7
                || (Double(edged.count) >= Double(rows.count) * 0.85 && Double(framed.count) >= Double(rows.count) * 0.35) else { return nil }
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
        // Nino: telefon eğilip aşağı indirilince ekranın alt kenarından taşar (GTA 6); üstü ekranın ortalarındaysa telefondur.
        // Kenara değen duvar ve kapılar ya üstten başlar ya da yukarıdaki çerçeve/şekil sınamalarını geçemez.
        guard centerRange.contains((box.left + box.right) / 2), box.top >= 0.04, box.bottom <= 0.96 || box.top >= 0.2 else { return nil }
        // Eğim: nokta/satır → kare genişliği / kare yüksekliği.
        return Panel(box: box, topLeft: topLeft / w, lean: best.slope * h / w, width: Double(runWidth + 1) / w)
        }
        // Aynı beyaz alan birkaç eğimde de aday çıkar; telefonun sırası gelsin diye yeterince aday sınanır.
        if ProcessInfo.processInfo.environment["NINO_TESHIS"] != nil {
            for best in candidates.prefix(16) { print("ADAY", best.votes, best.slope, attempt(best)?.box as Any) }
        }
        for best in candidates.prefix(16) {
            if let panel = attempt(best) { return panel }
        }
        return nil
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
        title(in: reading, panel: panel) != nil
    }

    /// Sohbetin başlığındaki ad ("Lucia", "Fleeca, Laguna Lane"): Türkçe panelin en üstünde ortada gösterilir.
    public static func titleText(_ reading: Reading, panel: PhonePanel.Panel) -> String? {
        guard let box = title(in: reading, panel: panel) else { return nil }
        return reading.lines.first { $0.box == box }?.text.trimmingCharacters(in: .whitespaces)
    }

    /// Sohbetin başlığı (kişinin adı) olan satırın kutusu. Başlık şeridinde ya da ekrandaki en üst satırdır: parlamalı
    /// karede telefonun beyaz gövdesi ekrandan sayılıyor, ekran olduğundan yukarıda ve dar bulunuyordu ("Brian" başlığı
    /// şeridin altında kalıp sohbet uygulama sanılıyordu).
    static func title(in reading: Reading, panel: PhonePanel.Panel) -> TextBox? {
        let height = panel.box.bottom - panel.box.top
        let boxes = reading.lines.compactMap(\.box)
        let topmost = boxes.map(\.top).min() ?? 0
        return reading.lines.first { line in
            guard let box = line.box, box.top < panel.box.top + height * headerShare || box.top <= topmost + 0.002 else { return false }
            let text = line.text.trimmingCharacters(in: .whitespaces)
            let middle = (box.top + box.bottom) / 2
            // Başlık kişi ya da yer adıdır; yer adında virgül, nokta, kesme ve & olabilir ("Fleeca, Laguna Lane").
            let nameLike = text.count >= 2 && text.split(separator: " ").count <= 5
                && text.allSatisfy { $0.isLetter || " ,.'’&-".contains($0) } && text.contains(where: \.isLetter)
            // Gezinme düğmesi ("Back", "< Back") kişi adı değildir; haber uygulaması sohbet sanılıyordu.
            guard !["back", "geri", "done", "close", "cancel", "edit"].contains(text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "<‹ "))) else { return false }
            guard MessageCard.isName(text) || nameLike,
                  abs((box.left + box.right) / 2 - panel.center(at: middle)) < panel.width * 0.12 else { return false }
            // Listede adın hemen altında, aynı hizada önizleme satırı durur ("Chuck's Gun Shop" / "Hey Jason. You good?");
            // sohbet başlığının altında aynı hizada satır yoktur.
            let indent = box.left - panel.left(at: box.top)
            return !boxes.contains { other in
                other.top > box.top + 0.008 && other.top < box.top + 0.05
                    && abs(other.left - panel.left(at: other.top) - indent) < 0.015
            }
        }?.box
    }

    /// Telefon ekranının en üstündeki başlık şeridi (ekran yüksekliğine oranla).
    static let headerShare = 0.07
    /// Başlık şeridinin hemen altında bu kadar (kare yüksekliğine oranla) içinde başlayan satır kesiktir.
    static let clippedTop = 0.012

    /// Sohbet ekranındaki mesajlar, yukarıdan aşağı. Başlık (kişinin adı), "New message", yer/eşya etiketleri
    /// ("Stoplight Parrotfish Spot") ve harfsiz satırlar mesaj değildir.
    public static func messages(in reading: Reading, panel found: PhonePanel.Panel) -> [Message] {
        let panel = found.box
        let panelHeight = panel.bottom - panel.top
        // Başlık şeridinin alt kenarı: şerit ya da (ekran yukarıda bulunduysa) başlığın kendisi hangisi aşağıdaysa.
        let header = max(panel.top + panelHeight * headerShare, title(in: reading, panel: found).map(\.bottom) ?? 0)
        // Satırın ortasındaki emoji ("scares the tourists 👎 Take it") satırı ikiye bölüyor; sağdaki parça ayrı mesaj
        // sanılıp bir görünüp bir kayboluyordu. Aynı satırdaki parçalar önce birleşir.
        let lines = joiningPieces(reading).lines.compactMap { line -> (text: String, box: TextBox)? in
            guard let box = line.box else { return nil }
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard text.filter(\.isLetter).count >= 2 else { return nil }
            // En üstteki başlık şeridi: kişinin adı ve geri oku.
            guard box.top > header else { return nil }
            // Başlığın hemen altında yarısı kesik satır (sohbet kaydırılmış): her okumada başka okunuyordu ("IOOK?",
            // "TOOK?") ve panel boşuna yeniden kuruluyordu. Tam görünen ilk mesajın yazısı balonun payı kadar aşağıdadır.
            guard box.top > header + clippedTop else { return nil }
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

    /// Aynı satırda, aralarında küçük boşlukla (emoji) yan yana okunan parçalar tek satır olur. Eğik telefonda alt
    /// alta satırlar birbirine karışmasın diye örtüşme sıkı, boşluk kısa tutulur.
    static func joiningPieces(_ reading: Reading) -> Reading {
        var rows: [TextLine] = []
        for line in reading.lines.sorted(by: { ($0.box?.left ?? 0) < ($1.box?.left ?? 0) }) {
            guard let box = line.box else { rows.append(line); continue }
            if let index = rows.firstIndex(where: { row in
                guard let other = row.box else { return false }
                let overlap = min(box.bottom, other.bottom) - max(box.top, other.top)
                let smaller = min(box.bottom - box.top, other.bottom - other.top)
                return smaller > 0 && overlap >= smaller * 0.75 && box.left - other.right <= 0.03 && box.left > other.right - 0.005
            }), let other = rows[index].box {
                rows[index] = TextLine(rows[index].text + " " + line.text, box: other.union(box), confidence: rows[index].confidence)
            } else {
                rows.append(line)
            }
        }
        return Reading(lines: rows)
    }

    /// Mesaj olmayan satır: "New message", "Typing...", ek olarak gönderilen yer ya da eşyanın adı (her sözcüğü büyük
    /// harfle başlar, cümle noktalaması yoktur).
    static func isLabel(_ text: String) -> Bool {
        let lowered = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".…• "))
        if ["new message", "new messages", "typing", "delivered", "read", "today", "yesterday", "messages encrypted"].contains(lowered) { return true }
        // Kilit simgesi harf sanılıyor ("A Messages encrypted").
        if lowered.hasSuffix("messages encrypted") || lowered.hasSuffix("message encrypted") { return true }
        // Mesaja eklenen uygulama bağlantısının kartı ("BuckMe") mesaj değildir.
        if phoneAppNames.contains(TextMatch.normalize(text)) { return true }
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

extension PhonePanel {
    /// Nino: telefonun ekranı kararmışsa (dokunulmadan duran telefon) renkler aydınlatılarak okunur: ekranın en aydınlık
    /// kısmı (zemin) beyaza çekilir. Yoksa panelin zemini kahverengi-siyah, giden mavi mesaj gri çıkıyor, hepsi solda kalıyordu.
    public static func liftedSampler(for frame: CGImage, panel: Panel) -> @Sendable (Double, Double) -> (r: Int, g: Int, b: Int)? {
        let base = sampler(for: frame)
        var colors: [(r: Int, g: Int, b: Int)] = []
        for y in stride(from: panel.box.top + 0.03, to: panel.box.bottom - 0.02, by: 0.02) {
            for share in stride(from: 0.05, through: 0.95, by: 0.1) {
                if let c = base(panel.left(at: y) + panel.width * share, y) { colors.append(c) }
            }
        }
        colors.sort { max($0.r, $0.g, $0.b) < max($1.r, $1.g, $1.b) }
        let lights = colors.map { max($0.r, $0.g, $0.b) }
        guard !lights.isEmpty else { return base }
        let screen = lights[lights.count * 8 / 10]
        // Koyu temalı uygulamanın (Rydeme) ekranı zaten koyudur; yalnız açık ekranın kararmışı aydınlatılır.
        // Açık ekranda noktaların çoğu zemindir (ortanca, en aydınlık kısma yakın); koyu temada çoğu koyudur.
        let middle = lights[lights.count / 2]
        // Kararmış beyaz ekran gri kalır (renk payı az); koyu temanın laciverti renklidir.
        let zone = colors[colors.count * 8 / 10]
        let gray = Double(min(zone.r, zone.g, zone.b)) / Double(max(1, max(zone.r, zone.g, zone.b)))
        // Koyu temada beyaz yazı zeminden çok aydınlıktır; kararmış açık ekranda en aydınlık nokta zemine yakındır.
        let brightest = lights.last ?? screen
        // Kullanıcı: Türkçe panel telefondaki kadar parlak görünmeli. Açık ekran (gece sahnesinde ≈170 okunur) her zaman
        // telefondaki beyaz balon kadar aydınlatılır; telefon karanlıkta gözle beyaz görünür.
        guard screen >= 40, screen < 232, Double(middle) >= Double(screen) * 0.8, gray >= 0.8,
              Double(brightest) <= Double(screen) * 1.3 else { return base }
        let gain = 238.0 / Double(screen)
        return { x, y in
            base(x, y).map { (min(255, Int(Double($0.r) * gain)), min(255, Int(Double($0.g) * gain)), min(255, Int(Double($0.b) * gain))) }
        }
    }

    /// Karedeki bir noktanın rengi (0–1 kesirlerle x, y; çevresindeki 3×3 noktanın ortalaması). Kare bir kez küçültülür.
    public static func sampler(for frame: CGImage, width: Int = 960, height: Int = 540) -> @Sendable (Double, Double) -> (r: Int, g: Int, b: Int)? {
        guard let pixels = rgba(frame, width: width, height: height) else { return { _, _ in nil } }
        return { x, y in
            let cx = Int((x * Double(width)).rounded()), cy = Int((y * Double(height)).rounded())
            guard cx >= 1, cy >= 1, cx < width - 1, cy < height - 1 else { return nil }
            var r = 0, g = 0, b = 0
            for dy in -1...1 {
                for dx in -1...1 {
                    let i = ((cy + dy) * width + cx + dx) * 4
                    r += Int(pixels[i]); g += Int(pixels[i + 1]); b += Int(pixels[i + 2])
                }
            }
            return (r / 9, g / 9, b / 9)
        }
    }
}

extension PhoneThread {
    /// Nino (kullanıcı isteği, 20 Kasım 2026): mesajların Türkçesi telefonun yanında değil, her mesaj balonunun tam
    /// üstünde, balonun kendi rengiyle ve koyu yazıyla durur; telefonun kendi yazısı gibi görünür. Balonun rengi yazının
    /// hemen solundan (balonun iç payı) okunur.
    public static func covers(for messages: [Message], translations: [String], angle: Double = 0,
                              color: (Double, Double) -> (r: Int, g: Int, b: Int)?) -> [ScreenTranslation.Item] {
        zip(messages, translations).compactMap { message, turkish in
            let text = turkish.trimmingCharacters(in: .whitespacesAndNewlines)
            // Ek kartının adı ("BuckMe" bağlantısı) "BuckMe mi?" diye soruya çevrilip mesaj gibi çıkıyordu.
            guard !text.isEmpty, worthShowing(source: message.text, translation: text) else { return nil }
            let box = message.box
            // Yazının solundaki iç paydan birkaç noktada okunur; harf ve balon kenarı rengi koyulttuğu için en aydınlığı alınır.
            let points = [0.15, 0.35, 0.5, 0.65, 0.85].flatMap { share in
                [bubbleInset, bubbleInset * 0.6].map { inset in (box.left - inset, box.top + (box.bottom - box.top) * share) }
            }
            let luminance = { (c: (r: Int, g: Int, b: Int)) in c.r * 299 + c.g * 587 + c.b * 114 }
            // Eğik telefonda yazının solu balonun dışına (duvar kağıdına) düşüyor, mavi giden mesaj beyaz sanılıyordu.
            // Balonun içinden de okunur: kutunun içindeki noktaların aydınlık yarısı (harf değil, balonun zemini); ortancası.
            let inside = stride(from: 0.15, through: 0.85, by: 0.1).flatMap { y in
                stride(from: 0.1, through: 0.9, by: 0.1).compactMap { x in
                    color(box.left + (box.right - box.left) * x, box.top + (box.bottom - box.top) * y)
                }
            }.sorted { luminance($0) < luminance($1) }
            let ground = inside.count >= 10 ? Array(inside.suffix(inside.count * 4 / 10)) : []
            let edge = points.compactMap { color($0.0, $0.1) }.max { luminance($0) < luminance($1) } ?? (233, 233, 236)
            // İçerisi harf kadar koyuysa (kutu yazıyı sıkı sarıyor) yazının solundaki pay kullanılır.
            let fill = ground.isEmpty || luminance(ground[ground.count / 2]) * 4 < luminance(edge) * 3 ? edge : ground[ground.count / 2]
            let light = (fill.r * 299 + fill.g * 587 + fill.b * 114) / 1000 > 140
            var item = ScreenTranslation.Item(source: message.text, translation: text,
                                              box: TextBox(left: box.left - coverPadX, top: box.top - coverPadY,
                                                           right: box.right + coverPadX, bottom: box.bottom + coverPadY),
                                              lineHeight: message.lineHeight)
            item.fill = String(format: "#%02x%02x%02x", fill.r, fill.g, fill.b)
            item.ink = light ? "#2c2c2e" : "#f5f5f7"
            item.angle = angle
            return item
        }
    }

    /// Yazının kenarından balonun içine doğru: rengin okunduğu yer (karede ≈ balonun iç payının yarısı).
    static let bubbleInset = 0.0045
    /// Örtünün yazıdan taşması: İngilizcenin harf uçları görünmesin, balonun kenarına da varmasın.
    static let coverPadX = 0.0035
    public static let coverPadY = 0.004

    /// Telefon kaydıysa (el sallanıyor) örtüler de aynı kadar kaydırılır; yazı yeniden okunmaz.
    public static func shifted(_ items: [ScreenTranslation.Item], dx: Double, dy: Double) -> [ScreenTranslation.Item] {
        items.map { item in
            var moved = item
            moved.box = TextBox(left: item.box.left + dx, top: item.box.top + dy, right: item.box.right + dx, bottom: item.box.bottom + dy)
            return moved
        }
    }
}

extension PhoneThread {
    /// Nino (kullanıcı isteği, 20 Kasım 2026): mesajların Türkçesi telefonun yanında, telefon boyunda dikey bir mesajlaşma
    /// paneli içinde: zemin telefondaki sohbetin zemini gibi ve biraz saydam; gelen mesajlar solda, giden mesajlar (sağa
    /// yaslı mavi balonlar) sağda, her biri kendi balonunun renginde ve mesajın hizasında. İlk öğe panelin zeminidir.
    /// `lines(text, width, line)` Türkçenin o genişlikte kaç satır tuttuğunu ve en uzun satırın harf sayısını verir.
    public static func sideBubbles(for messages: [Message], translations: [String], panel: PhonePanel.Panel,
                                   chat: Bool = true, title: String? = nil,
                                   color: (Double, Double) -> (r: Int, g: Int, b: Int)?,
                                   lines: (String, Double, Double) -> (count: Int, longest: Int)) -> [ScreenTranslation.Item] {
        let covers = covers(for: messages, translations: translations, color: color)
        guard !covers.isEmpty else { return [] }
        let kept = covers.compactMap { cover in messages.first { $0.text == cover.source } }
        let column = column(beside: panel, maxWidth: sideWidth)
        let inset = 0.012, gap = 0.012
        let inner = (left: column.left + inset, right: column.right - inset)
        let bubbleMax = (inner.right - inner.left) * 0.82
        let pad = 0.012
        var counts: [Int] = [], longest: [Int] = [], heights: [Double] = []
        for (index, cover) in covers.enumerated() {
            // Kullanıcı isteği: Türkçe %4 (0,88 → 0,915), sonra %6 daha büyütüldü (→ 0,97).
            let line = min(max(kept[index].lineHeight, 0.018), 0.028) * 0.97
            let measured = lines(cover.translation, bubbleMax - pad, line)
            counts.append(measured.count); longest.append(measured.longest); heights.append(line)
        }
        var boxes = boxes(for: kept, lineCounts: counts, lineHeights: heights, column: (inner.left, inner.right))
        // Panel telefonun boyundadır; balonlar sığmazsa yukarı doğru sıkışır (en alttaki mesaj en yenisidir).
        // Panelin sağ altında Nino logosu durur (TV çizer); en alttaki balon ona binmesin.
        let bottom = panel.box.bottom - gap - badgeSpace
        if let last = boxes.last, last.bottom > bottom {
            let shift = last.bottom - bottom
            boxes = boxes.map { TextBox(left: $0.left, top: $0.top - shift, right: $0.right, bottom: $0.bottom - shift) }
        }
        // Giden mesaj: telefonda sağa yaslı ya da aynı sohbetin en gri balonundan belirgin mavi. Işık balonların hepsini
        // mavimsi gösterebiliyor (gelen balon "#899ab7" okundu, sağa kondu); renk tek başına değil, karşılaştırmayla bakılır.
        let blueness = covers.map { blueShift($0.fill) }
        let grayest = blueness.min() ?? 0
        // Uygulama ekranında (sohbet değil) gelen/giden yoktur; satırlar sola yaslıdır.
        // Kullanıcı: hizalamaya da bak. Sohbetteki en soldaki mesajlara göre belirgin içeride başlayıp en sağdakilerle
        // aynı yerde biten mesaj sağa yaslıdır (eğik telefonda kenara göre ölçülür).
        let indents = kept.map { $0.box.left - panel.left(at: $0.box.top) }
        let rights = kept.map { $0.box.right - panel.left(at: $0.box.top) }
        let leftmost = indents.min() ?? 0, rightmost = rights.max() ?? 0
        let rightAligned = kept.indices.map { indents[$0] - leftmost > panel.width * 0.1 && rightmost - rights[$0] < panel.width * 0.08 }
        let outgoing = covers.indices.map { chat && (isOutgoing(kept[$0], panel: panel) || rightAligned[$0] || blueness[$0] - grayest >= 14) }
        var items: [ScreenTranslation.Item] = []
        // Zemin: sohbetin zemini balonların arasından (gelen balonların sağındaki boşluk) okunur.
        let samples = kept.filter { !isOutgoing($0, panel: panel) }.compactMap {
            // Eğik telefonda kutunun sağ kenarı ekranın dışına düşer; ekranın o yükseklikteki sağ kenarına göre okunur.
            let y = ($0.box.top + $0.box.bottom) / 2
            return color(panel.left(at: y) + panel.width - 0.012, y)
        }
        let ground = samples.sorted { $0.r + $0.g + $0.b < $1.r + $1.g + $1.b }.dropFirst(samples.count / 2).first ?? (226, 228, 233)
        var backdrop = ScreenTranslation.Item(source: "", translation: "", box: TextBox(left: column.left, top: panel.box.top,
                                              right: column.right, bottom: panel.box.bottom), lineHeight: 0.02)
        // Kullanıcı: balonlar zeminden ayrışsın (soluk duruyordu). Açık sohbette zemin bir tık koyulaşır, gelen balon
        // beyaza yaklaşır, giden balonun mavisi belirginleşir.
        let lightChat = chat && (ground.r * 299 + ground.g * 587 + ground.b * 114) / 1000 > 150
        // Kullanıcı: zemin koyu gri değil, beyaz ve şeffaf olsun (mesajlar uygulamasının açık zemini gibi).
        let toWhite = lightChat ? 0.6 : 0.0
        func lift(_ v: Int) -> Int { Int(Double(v) + (255 - Double(v)) * toWhite) }
        backdrop.fill = String(format: "#%02x%02x%02x", lift(ground.r), lift(ground.g), lift(ground.b))
        backdrop.alpha = backdropAlpha
        backdrop.backdrop = true
        // Kullanıcı isteği: panelin en üstünde ortada gönderenin adı (TV başlık olarak çizer; ad çevrilmez).
        if chat, let title, !title.isEmpty {
            backdrop.translation = title
            backdrop.lineHeight = min(max(kept.map(\.lineHeight).max() ?? 0.022, 0.02), 0.028)
        }
        items.append(backdrop)
        for index in covers.indices {
            var box = boxes[index]
            let width = min(bubbleMax, Double(longest[index]) * heights[index] * 0.5 * 9 / 16 + pad + 0.012)
            if !chat {
                // Uygulama ekranı (kullanıcı isteği): panel uygulamanın Türkçe kopyası gibi; her satır telefondaki yatay
                // yerine ve genişliğine göre (telefon ekranından panele ölçeklenerek) durur, ortalı satır ortada kalır.
                let message = kept[index]
                let scale = (inner.right - inner.left) / panel.width
                let left = message.box.left - panel.left(at: message.box.top)
                box.left = inner.left + max(0, left) * scale - pad / 2
                box.right = min(inner.right, box.left + max(width, (message.box.right - message.box.left) * scale + pad))
            } else if outgoing[index] { box.left = inner.right - width; box.right = inner.right }
            else { box.left = inner.left; box.right = inner.left + width }
            box.bottom += heights[index] * 0.3
            var item = covers[index]
            if lightChat, let fill = item.fill, fill.count == 7, let value = Int(fill.dropFirst(), radix: 16) {
                let r = Double((value >> 16) & 0xff), g = Double((value >> 8) & 0xff), b = Double(value & 0xff)
                let tuned = outgoing[index]
                    ? (r * 0.86, g * 0.93, min(255, b * 1.04))
                    : (r + (255 - r) * 0.7, g + (255 - g) * 0.7, b + (255 - b) * 0.7)
                item.fill = String(format: "#%02x%02x%02x", Int(tuned.0), Int(tuned.1), Int(tuned.2))
            }
            item.box = box
            item.lineHeight = heights[index]
            item.angle = nil
            item.alpha = sideAlpha
            item.side = true
            items.append(item)
        }
        return items
    }

    /// Rengin maviliği: mavi kanalın kırmızı ve yeşilin ortalamasından farkı.
    static func blueShift(_ hex: String?) -> Int {
        guard let hex, hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return 0 }
        let r = (value >> 16) & 0xff, g = (value >> 8) & 0xff, b = value & 0xff
        return b - (r + g) / 2
    }

    /// Giden mesaj: telefonda sağa yaslı balon (sol kenarı ekranın içinde epey içeride başlar).
    static func isOutgoing(_ message: Message, panel: PhonePanel.Panel) -> Bool {
        message.box.left - panel.left(at: message.box.top) > panel.width * 0.2
    }

    /// Panelin genişliği (kare genişliğine oranla), balonların ve zeminin saydamlığı.
    public static let sideWidth = 0.27
    public static let sideAlpha = 0.95
    public static let backdropAlpha = 0.6
    /// Panelin altında logoya bırakılan yer (kare yüksekliğine oranla).
    static let badgeSpace = 0.03
}

extension PhoneThread {
    /// Nino (kullanıcı isteği, 20 Kasım 2026): sohbet olmayan telefon uygulaması (BuckMe bankası): her yazı satırı ayrı
    /// çevrilir ve yandaki panelde kendi hizasında gösterilir ("Checking Account", "$4,900 to next goal"). Harfsiz
    /// satırlar ($500), üstteki başlık şeridi ve alt kenarda yarısı görünen satır alınmaz.
    public static func appLines(in reading: Reading, panel found: PhonePanel.Panel) -> [Message] {
        let panel = found.box
        let panelHeight = panel.bottom - panel.top
        let lines = reading.lines.compactMap { line -> Message? in
            guard let box = line.box else { return nil }
            // Satırın başındaki simge ("◆ Checking Account") çevrilmez.
            let text = String(line.text.trimmingCharacters(in: .whitespaces)
                .drop { !$0.isLetter && !$0.isNumber && $0 != "$" && $0 != "€" && $0 != "£" }).trimmingCharacters(in: .whitespaces)
            // Boş sohbetin "Messages encrypted" yazısı uygulama yazısı değildir.
            let lowered = text.lowercased()
            guard !lowered.hasSuffix("messages encrypted"), !lowered.hasSuffix("message encrypted") else { return nil }
            guard text.filter(\.isLetter).count >= 3, box.top > panel.top + panelHeight * headerShare,
                  box.bottom < panel.bottom - 0.01 else { return nil }
            return Message(text: text, box: box, lineHeight: (box.bottom - box.top) * 0.85)
        }.sorted { $0.box.top < $1.box.top }
        // Alt alta devam eden satırlar tek cümledir (haber başlığı: "Patrons note improvement" / "after Leonida Man" /
        // "defecates in waffle house"): sonraki satır küçük harfle başlıyorsa ya da önceki satır noktalamasız ve en az üç
        // sözcüklüyse. Ayrı etiketler ("Muscle - High" / "Body Fat - Low") ayrı kalır.
        var merged: [Message] = []
        for line in lines {
            if var last = merged.last {
                let gap = line.box.top - last.box.bottom, height = line.box.bottom - line.box.top
                let words = last.text.split(separator: " ").filter { $0.contains(where: \.isLetter) }.count
                let ended = last.text.last.map { ".!?:".contains($0) } ?? false
                // Yazar satırı ("By Rusty Travers") paragrafa katılmaz.
                let byline = last.text.lowercased().hasPrefix("by ") && words <= 4
                let continues = !byline && (line.text.first?.isLowercase == true || (!ended && words >= 3))
                if gap < height * 0.6, abs(line.box.left - last.box.left) < 0.02, continues {
                    last.text += " " + line.text
                    last.box = last.box.union(line.box)
                    merged[merged.count - 1] = last
                    continue
                }
            }
            merged.append(line)
        }
        return merged
    }
}

extension PhoneThread {
    /// Kutudaki yazı açık zeminde koyu yazı mı (telefon ekranı, mesaj balonu): zemin (ortanca parlaklık) yazının
    /// noktalarından aydınlıktır. Altyazı ise koyu sahnede (ya da siyah kutuda) beyaz yazıdır.
    public static func isDarkOnLight(_ box: TextBox, color: (Double, Double) -> (r: Int, g: Int, b: Int)?) -> Bool {
        var values: [Int] = []
        for y in stride(from: box.top, through: box.bottom, by: max((box.bottom - box.top) / 6, 0.001)) {
            for share in stride(from: 0.02, through: 0.98, by: 0.03) {
                if let c = color(box.left + (box.right - box.left) * share, y) { values.append((c.r * 299 + c.g * 587 + c.b * 114) / 1000) }
            }
        }
        guard values.count >= 20 else { return false }
        values.sort()
        let darkest = values[values.count / 20], middle = values[values.count / 2], brightest = values[values.count * 19 / 20]
        // Zemin yazıdan belirgin aydınlık ve yazı zeminden koyu: koyu yazı. Beyaz altyazıda en aydınlık noktalar zeminden
        // çok uzaktır, en koyular zemine yakındır.
        return middle - darkest >= 25 && middle - darkest > (brightest - middle) * 2
    }
}

extension PhoneThread {
    /// Çevrilecek yazı mı: çevirisi boş değil, aslının aynısı değil ve tek sözcüklü aslını olduğu gibi içermiyor ("buckme" →
    /// "BuckMe mi?": marka adı çevrilmez).
    public static func worthShowing(source: String, translation: String) -> Bool {
        let a = TextMatch.normalize(source), b = TextMatch.normalize(translation)
        return !b.isEmpty && a != b && !(b.contains(a) && !a.contains(" "))
    }

}

extension PhoneThread {
    /// Nino: oyun telefonunun arayüz yazıları (GTA 6 BuckMe bankası, mesajlar) için sabit Türkçe. Kısa arayüz yazısı
    /// bağlamsız çevrilince saçmalıyordu ("Checking Account" → "Borsa Hesabı").
    public static func glossary(_ text: String) -> String? {
        let key = TextMatch.normalize(text)
        if let fixed = glossaryTerms[key] { return fixed }
        // "Book Ryde ($82)" → "Ryde Çağır ($82)": parantez içindeki tutar korunur.
        if let open = text.firstIndex(of: "("), text.hasSuffix(")"),
           let fixed = glossaryTerms[TextMatch.normalize(String(text[..<open]))] {
            return fixed + " " + text[open...]
        }
        // "Muscle - High" → "Kas - Yüksek", "Body Fat - Low" → "Vücut Yağı - Düşük"
        let parts = text.components(separatedBy: " - ")
        if parts.count == 2, let left = statNames[TextMatch.normalize(parts[0])], let right = statLevels[TextMatch.normalize(parts[1])] {
            return left + " - " + right
        }
        // Tanıma tireyi düşürebiliyor ("Muscle High").
        let words = key.split(separator: " ").map(String.init)
        if words.count >= 2, let right = statLevels[words.last!], let left = statNames[words.dropLast().joined(separator: " ")] {
            return left + " - " + right
        }
        // "Level 3/4" → "Seviye 3/4"
        if key.hasPrefix("level "), let rest = text.split(separator: " ").dropFirst().first, rest.contains("/") {
            return "Seviye " + rest
        }
        // "$4,900 to next goal" → "Sonraki hedefe $4.900"
        if key.hasSuffix(" to next goal"), let amount = text.split(separator: " ").first, amount.contains(where: \.isNumber) {
            return "Sonraki hedefe " + amount.replacingOccurrences(of: ",", with: ".")
        }
        return nil
    }

    /// Telefonun mesaj listesi mi: "…" ile kesilmiş önizlemeler var. Büyük harfle başlayan arayüz satırları ("Standard Ryde",
    /// "Choose Ryde") tek başına liste değildir (Rydeme ekranı liste sanılıp hiç çevrilmiyordu).
    public static func isMessageList(_ reading: Reading) -> Bool {
        MessageCard.isList(reading) && reading.lines.contains {
            let text = $0.text.trimmingCharacters(in: .whitespaces)
            return text.hasSuffix("...") || text.hasSuffix("…")
        }
    }

    /// Cümle mi (sohbet mesajı): cümle noktalaması ya da küçük harfle başlayan sözcüğü var. Her sözcüğü büyük harfle
    /// başlayan arayüz yazısı ("Book Ryde ($82)", "Righto Cash & Carry") cümle değildir.
    public static func isSentence(_ text: String) -> Bool {
        let words = text.split(separator: " ").filter { $0.contains(where: \.isLetter) }
        // Cümle sonu noktalaması (sayı içindeki nokta değil: "1.74 mi"); en az iki sözcüklü yazıda.
        if words.count >= 2, let last = text.trimmingCharacters(in: .whitespaces).last, ".!?".contains(last) { return true }
        if text.contains(where: { "!?".contains($0) }) && words.count >= 2 { return true }
        return words.count >= 3 && words.dropFirst().contains { $0.first?.isLowercase == true }
    }

    /// Nino (kullanıcı fikri): oyun telefonunun uygulamalarına özgü sözcükler (uygulama adları, başlıklar, düğmeler). Bu
    /// yazılar her zaman telefondadır: telefon o karede bulunamasa da altyazı, mesaj kartı ya da ipucu sayılmaz.
    public static func isPhoneUI(_ text: String) -> Bool {
        // Kök olarak aranır: yazı tanıma bir harfi yanlış okusa da ("Destinatior") tanınsın.
        let key = " " + TextMatch.normalize(text)
        if phoneUIWords.contains(where: { key.contains(" " + $0) }) { return true }
        // Uygulama adları tam sözcük olarak ("Ryde", "Rydeme"; "Rydell" değil).
        let words = Set(key.split(separator: " ").map(String.init))
        if !words.isDisjoint(with: phoneAppNames) { return true }
        let bare = TextMatch.normalize(text.replacingOccurrences(of: #"\(.*\)"#, with: "", options: .regularExpression))
        if glossaryTerms[bare] != nil { return true }
        // Sözlüğün kalıplarıyla çevrilen yazı ("Muscle High", "Level 1/4", "$4,900 to next goal") da telefondadır;
        // tek sözcükler ("Focus", "Cost") ise diyalogda da geçebilir, sayılmaz.
        return text.split(separator: " ").count >= 2 && glossary(text) != nil
    }

    /// Uygulama adları ve uygulamaya özgü sözcükler (tek başına geçince yeter).
    static let phoneUIWords = ["trip detail", "change destinat", "destinatio", "messages encrypt",
                               "map pin expir", "checking accoun", "family saving",
                               // Fitness uygulaması (Jason'ın açlık, antrenman, kalori bilgileri)
                               // (tek sözcük değil kalıp: diyalogdaki "workout" altyazı olarak kalsın)
                               "workout window", "strength workout", "cardio workout", "calorie balanc", "maintain weight",
                               "gain weight", "lose weight"]
    static let phoneAppNames: Set<String> = ["ryde", "rydeme", "buckme"]

    static let statNames: [String: String] = ["muscle": "Kas", "body fat": "Vücut Yağı", "stamina": "Dayanıklılık",
                                              "strength": "Güç", "fat": "Yağ"]
    static let statLevels: [String: String] = ["high": "Yüksek", "low": "Düşük", "medium": "Orta", "average": "Ortalama",
                                               "very high": "Çok Yüksek", "very low": "Çok Düşük"]

    static let glossaryTerms: [String: String] = [
        // Gazete adları çevrilmez (aynısı döner, baloncuk gösterilmez): "Vice City Horn" → "Vice City Borusu" oluyordu.
        "vice city horn": "Vice City Horn", "the leonida journal": "The Leonida Journal", "leonida journal": "Leonida Journal",
        "ripped": "Kaslı", "toned": "Sıkı", "average": "Ortalama", "body & nutrition": "Vücut ve Beslenme",
        "body nutrition": "Vücut ve Beslenme",
        "strength workout": "Güç Antrenmanı", "cardio workout": "Kardiyo Antrenmanı", "workout window": "Antrenman zamanı",
        "focus": "Odak", "fitness": "Fitness", "calorie balance": "Kalori Dengesi", "you will maintain weight": "Kilonu koruyacaksın",
        "you will gain weight": "Kilo alacaksın", "you will lose weight": "Kilo vereceksin", "hungry": "Aç", "full": "Tok",
        "trip details": "Yolculuk Bilgileri", "cost": "Ücret", "choose ryde": "Ryde Seç", "standard ryde": "Standart Ryde",
        "change destination": "Varış Noktasını Değiştir", "book ryde": "Ryde Çağır", "cancel ryde": "Ryde'ı İptal Et",
        "checking account": "Vadesiz Hesap", "savings account": "Birikim Hesabı", "family savings": "Aile Birikimi", "family savings video": "Aile Birikimi Videosu", "atm finder": "ATM Bulucu", "faqs": "SSS",
        "savings": "Birikim", "balance": "Bakiye", "deposit": "Para Yatır", "withdraw": "Para Çek", "transfer": "Transfer",
        "transactions": "Hesap Hareketleri", "recent transactions": "Son Hareketler", "set a goal": "Hedef Belirle",
        "messages encrypted": "Mesajlar şifreli", "new message": "Yeni mesaj", "all contacts": "Tüm Kişiler",
        "suggested": "Önerilenler", "messages": "Mesajlar", "map pin expired": "Konum süresi doldu",
    ]
}

extension PhoneThread {
    /// Nino (kullanıcı isteği, 20 Kasım 2026): sohbet olmayan uygulamada (BuckMe) Türkçe, telefonun yanındaki boşlukta
    /// uygulamanın kendi renginde (ekrandaki en canlı renk; BuckMe'de mor) baloncuklar olarak, her yazının hizasında ve
    /// telefona yakın kenara yaslı durur. Zemin paneli yoktur.
    public static func appBubbles(for lines: [Message], translations: [String], panel: PhonePanel.Panel,
                                  color: (Double, Double) -> (r: Int, g: Int, b: Int)?) -> [ScreenTranslation.Item] {
        let kept = zip(lines, translations).filter { worthShowing(source: $0.text, translation: $1) }
        guard !kept.isEmpty else { return [] }
        // Uygulamanın rengi: önce üst başlık şeridi (Rydeme'nin pembesi), yoksa yazıların hemen çevresi (BuckMe'nin mor
        // kartı, fitness'ın turkuaz çubuğu). Ekranın geri kalanına bakılmaz: haberin fotoğrafı uygulamanın rengi değildir.
        // Renk bulunamazsa (beyaz haber uygulaması) baloncuk sade koyu gridir.
        var accent: (r: Int, g: Int, b: Int) = (58, 58, 60)
        func strongest(_ points: [(Double, Double)]) -> (r: Int, g: Int, b: Int)? {
            var best = 60, found: (r: Int, g: Int, b: Int)?
            for (x, y) in points {
                guard let c = color(x, y) else { continue }
                let saturation = max(c.r, c.g, c.b) - min(c.r, c.g, c.b)
                // Yeterince aydınlık olmalı (koyu ekrandaki koyu lacivert uygulamanın rengi değildir).
                if saturation > best, max(c.r, c.g, c.b) >= 120 { best = saturation; found = c }
            }
            return found
        }
        let header = stride(from: panel.box.top - 0.04, to: panel.box.top + 0.06, by: 0.01).flatMap { y in
            stride(from: 0.1, through: 0.9, by: 0.1).map { (panel.left(at: y) + panel.width * $0, y) }
        }
        let around = kept.flatMap { line, _ -> [(Double, Double)] in
            let middle = (line.box.top + line.box.bottom) / 2
            return [(line.box.left - 0.006, middle), (line.box.right + 0.006, middle), ((line.box.left + line.box.right) / 2, line.box.top - 0.006),
                    ((line.box.left + line.box.right) / 2, line.box.bottom + 0.006)]
        }
        // Nino (kullanıcı fikri): uygulamanın belirgin rengi yoksa (beyaz haber uygulaması) baloncuk ekranın baskın arka
        // planı ve yazı rengiyle çizilir: arka plan ekranda en çok görülen renk, yazı rengi satırların içinde o
        // arka plandan en uzak renk.
        var ink = "#ffffff"
        if let found = strongest(header) ?? strongest(around) {
            accent = found
        } else {
            func light(_ c: (r: Int, g: Int, b: Int)) -> Int { c.r * 299 + c.g * 587 + c.b * 114 }
            // Arka plan: telefon ekranında en çok görülen renk (16'lık kümelere ayrılıp en kalabalık kümenin ortalaması).
            var bins: [Int: [(r: Int, g: Int, b: Int)]] = [:]
            for y in stride(from: panel.box.top + 0.02, to: panel.box.bottom - 0.01, by: 0.01) {
                for share in stride(from: 0.05, through: 0.95, by: 0.05) {
                    guard let c = color(panel.left(at: y) + panel.width * share, y) else { continue }
                    bins[(c.r / 16) << 8 | (c.g / 16) << 4 | (c.b / 16), default: []].append(c)
                }
            }
            if let crowd = bins.values.max(by: { $0.count < $1.count }) {
                let back = (r: crowd.map(\.r).reduce(0, +) / crowd.count, g: crowd.map(\.g).reduce(0, +) / crowd.count,
                            b: crowd.map(\.b).reduce(0, +) / crowd.count)
                func distance(_ c: (r: Int, g: Int, b: Int)) -> Int { abs(c.r - back.r) + abs(c.g - back.g) + abs(c.b - back.b) }
                // Yazı rengi: satırların içinde arka plandan en uzak nokta (örnekler 3×3 ortalama olduğundan biraz soluk
                // çıkar; arka plana göre koyulaştırılır ya da açılır).
                let strokes = kept.flatMap { line, _ -> [(r: Int, g: Int, b: Int)] in
                    stride(from: line.box.top, through: line.box.bottom, by: max((line.box.bottom - line.box.top) / 8, 0.002)).flatMap { y in
                        stride(from: 0.02, through: 0.98, by: 0.02).compactMap { color(line.box.left + (line.box.right - line.box.left) * $0, y) }
                    }
                }
                accent = back
                let lightBack = light(back) > 128_000
                if let text = strokes.max(by: { distance($0) < distance($1) }), distance(text) >= 90 {
                    let k = lightBack ? 0.6 : 1.0
                    ink = lightBack
                        ? String(format: "#%02x%02x%02x", Int(Double(text.r) * k), Int(Double(text.g) * k), Int(Double(text.b) * k))
                        : String(format: "#%02x%02x%02x", 255 - (255 - text.r) / 2, 255 - (255 - text.g) / 2, 255 - (255 - text.b) / 2)
                } else {
                    ink = lightBack ? "#1c1c1e" : "#ffffff"
                }
            }
        }
        let column = column(beside: panel, maxWidth: sideWidth)
        let onLeft = column.right <= panel.box.left
        var floor = 0.0
        // Bütün baloncuklarda aynı yazı boyu (ortanca satır yüksekliği): OCR her satırı biraz farklı ölçtüğünden
        // "Hedefi Değiştir" büyük, "Standart Ryde" küçük çıkıyordu.
        let heights = kept.map { $0.0.lineHeight / 0.85 }.sorted()
        let size = min(max(heights[heights.count / 2], 0.018), 0.028) * 0.95
        return kept.map { line, turkish in
            let text = turkish.trimmingCharacters(in: .whitespacesAndNewlines)
            // Uzun yazı (haber paragrafı) sütun genişliğinde alt satırlara kaydırılır.
            let charWidth = size * 0.5 * 9 / 16, room = column.right - column.left
            let perLine = max(8, Int((room - 0.03) / (charWidth * 0.85)))
            let rows = max(1, Int((Double(text.count) / Double(perLine)).rounded(.up)))
            let width = rows > 1 ? room : min(room, Double(text.count) * charWidth + 0.03)
            let height = rows > 1 ? size * (1.22 * Double(rows) + 0.45) : size * 1.55
            let top = min(max(rows > 1 ? line.box.top : (line.box.top + line.box.bottom) / 2 - height / 2, floor), max(0, 0.98 - height))
            floor = top + height + size * 0.4
            let left = onLeft ? column.right - width : column.left
            var item = ScreenTranslation.Item(source: line.text, translation: text,
                                              box: TextBox(left: left, top: top, right: left + width, bottom: top + height), lineHeight: size)
            item.fill = String(format: "#%02x%02x%02x", accent.r, accent.g, accent.b)
            item.ink = ink
            item.alpha = sideAlpha
            item.side = true
            return item
        }
    }
}

extension PhonePanel {
    /// Nino: bir kez bulunan telefonu takip eder. Koyu temalı uygulamada (Rydeme) kartlar, düğmeler ve alt pencere ekranı
    /// böldüğünden telefon her karede baştan bulunamıyordu; içindeki yazılar mesaj kartı ve ipucu sanılıyordu. Bulunamayan
    /// karede, son bulunan yerde hâlâ aynı tür ekran (koyu ya da beyaz) duruyorsa telefon orada sayılır. Takip en son
    /// gerçek bulunuştan `maxAge` saniye sürer.
    public final class Tracker: @unchecked Sendable {
        private let lock = NSLock()
        private var last: Panel?
        private var dark = false
        private var lastSeen = Date.distantPast
        public var maxAge: TimeInterval = 20

        public init() {}

        /// Nino (kullanıcı fikri): telefon uygulamasının sözcükleri görüldü ama telefon bulunamadı (alt penceresi açık
        /// koyu uygulama). Telefonun yeri bu yazıların yerinden tahmin edilip takip oradan başlar.
        public func adopt(around boxes: [TextBox], in frame: CGImage) {
            guard !boxes.isEmpty, lock.withLock({ last == nil || Date().timeIntervalSince(lastSeen) > 2 }) else { return }
            let guess = PhonePanel.guess(around: boxes)
            let isDark = PhonePanel.screenShare(guess, in: frame, dark: true) >= 0.45
            lock.withLock { last = guess; dark = isDark; lastSeen = Date() }
        }

        public func locate(in frame: CGImage) -> Panel? {
            if let found = PhonePanel.find(in: frame) {
                let isDark = PhonePanel.screenShare(found, in: frame, dark: true) >= 0.5
                lock.withLock { last = found; dark = isDark; lastSeen = Date() }
                return found
            }
            guard let (previous, wasDark) = lock.withLock({ Date().timeIntervalSince(lastSeen) < maxAge ? last.map { ($0, dark) } : nil })
            else { return nil }
            guard PhonePanel.screenShare(previous, in: frame, dark: wasDark) >= 0.45 else {
                lock.withLock { last = nil }
                return nil
            }
            return previous
        }
    }

    /// Telefon uygulamasının yazılarından telefon ekranının tahmini yeri: elde tutulan GTA 6 telefonu ≈ 0,21 genişlik,
    /// ekranın 0,20–0,82'si; yazılar bu tahminin dışına taşıyorsa kutu onları da içine alır.
    public static func guess(around boxes: [TextBox]) -> Panel {
        let minLeft = boxes.map(\.left).min() ?? 0.6, maxRight = boxes.map(\.right).max() ?? 0.78
        let left = max(0.02, minLeft - 0.015), right = min(0.98, max(maxRight + 0.015, left + 0.21))
        let top = min(0.2, (boxes.map(\.top).min() ?? 0.3) - 0.02), bottom = min(0.95, max(0.82, (boxes.map(\.bottom).max() ?? 0.8) + 0.03))
        return Panel(box: TextBox(left: left, top: max(0.04, top), right: right, bottom: bottom), topLeft: left, lean: 0, width: right - left)
    }

    /// Ekranın içindeki noktaların ne kadarı koyu (`dark`) ya da beyaz ekran rengi.
    static func screenShare(_ panel: Panel, in frame: CGImage, dark: Bool) -> Double {
        let sample = sampler(for: frame, width: 480, height: 270)
        var hits = 0, total = 0
        for row in 1...14 {
            let y = panel.box.top + (panel.box.bottom - panel.box.top) * Double(row) / 15
            for column in 1...7 {
                guard let c = sample(panel.left(at: y) + panel.width * Double(column) / 8, y) else { continue }
                total += 1
                let high = max(c.r, c.g, c.b), low = min(c.r, c.g, c.b)
                if dark ? (high <= darkScreenCeiling + 10) : (low >= whiteFloor && high - low <= 45) { hits += 1 }
            }
        }
        return total == 0 ? 0 : Double(hits) / Double(total)
    }
}
