// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation
import Vision

public protocol TextReader: Sendable {
    func read(_ image: CGImage) throws -> String
    /// `deep` false ise boş bölgede büyütülmüş okuma denenmez (işlemciyi çok daha az yorar).
    func read(_ image: CGImage, deep: Bool) throws -> String
    /// Satırlar ayrı ayrı ve görüntüdeki yerleriyle.
    func readLines(_ image: CGImage, deep: Bool) throws -> Reading
}

extension TextReader {
    public func read(_ image: CGImage, deep: Bool) throws -> String { try read(image) }
    public func readLines(_ image: CGImage, deep: Bool) throws -> Reading { Reading(text: try read(image, deep: deep)) }
}

/// Apple Vision ile cihaz üstünde yazı tanıma. Satırlar yukarıdan aşağı sıralanır.
public struct VisionReader: TextReader {
    public var language = "en"

    /// Nino: satırın başında ve sonunda da düğme simgesi aranır ("△ Get back on the wagon"). Yalnız ipucu ve görev
    /// yazılarında açılır; her karede okunan altyazıda gereksiz yük olmasın.
    public var edgeIcons = false

    public init(language: String = "en", edgeIcons: Bool = false) {
        self.language = language
        self.edgeIcons = edgeIcons
    }

    public func read(_ image: CGImage) throws -> String {
        try readLines(image, deep: true).lines.map(\.text).joined(separator: " ")
    }

    public func read(_ image: CGImage, deep: Bool) throws -> String {
        try readLines(image, deep: deep).lines.map(\.text).joined(separator: " ")
    }

    public func readLines(_ image: CGImage, deep: Bool) throws -> Reading {
        // Nino: altyazı okuması ile köşe okuması aynı anda Vision'a girince Vision kendi iş kuyruğunda kilitleniyor,
        // okuma hiç bitmiyordu (okuma hattı 15 sn'de bir yeniden kuruluyor, altyazı gelmiyordu). Okumalar sırayla yapılır;
        // bir okumanın kendi içindeki eşzamanlı denemeleri (firstLines) aynen kalır.
        Self.gate.lock()
        defer { Self.gate.unlock() }
        return deep ? try Self.firstLines(of: image, using: recognize) : try recognize(image)
    }

    private static let gate = NSLock()

    /// Satırsız eski biçim (testler için): bulunan yazı tek metin olarak döner.
    public static func firstReading(of image: CGImage, using recognize: @escaping @Sendable (CGImage) throws -> String) throws -> String {
        try firstLines(of: image) { Reading(text: try recognize($0)) }.text
    }

    /// Vision geniş bölgede "Go!" gibi kısa satırları sık sık hiç bulmaz. Bölgede yazı çıkmazsa
    /// ortadaki şerit (altyazılar ortalıdır) ve bölgenin tamamı büyütülerek aynı anda yeniden okunur;
    /// ikisi de yazı bulursa şeridinki seçilir. Aynı anda okumak, boş karede yeni satırı geç fark etmeyi önler.
    public static func firstLines(of image: CGImage, using recognize: @escaping @Sendable (CGImage) throws -> Reading) throws -> Reading {
        let reading = try recognize(image)
        guard reading.lines.isEmpty else { return reading }

        // Şeritte bulunan satırın yeri şeridin değil bölgenin tamamının oranlarıyla verilir.
        let strip = stripRect(of: image, widthFraction: 0.4)
        let stripArea = TextBox(left: strip.minX / Double(image.width), top: 0, right: strip.maxX / Double(image.width), bottom: 1)
        let fallbacks: [@Sendable () throws -> Reading?] = [
            { try image.cropping(to: strip).flatMap { scaled($0, by: 2) }.map { try recognize($0).placed(in: stripArea) } },
            { try scaled(image, by: 2).map(recognize) },
        ]
        let results = Results(count: fallbacks.count)
        DispatchQueue.concurrentPerform(iterations: fallbacks.count) { index in
            results.set(index, Result { try fallbacks[index]() ?? .empty })
        }
        for result in results.all {
            if let reading = try result?.get(), !reading.lines.isEmpty { return reading }
        }
        return .empty
    }

    /// Aynı anda yapılan okumaların sonuçları.
    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Result<Reading, Error>?]
        init(count: Int) { values = Array(repeating: nil, count: count) }
        func set(_ index: Int, _ value: Result<Reading, Error>) { lock.withLock { values[index] = value } }
        var all: [Result<Reading, Error>?] { lock.withLock { values } }
    }

    /// Bir satırın Vision'dan alınan ham bilgisi (istek bırakıldıktan sonra da kullanılabilsin diye kopyalanır).
    private struct RawLine {
        var text: String
        var box: CGRect
        var confidence: Float
        /// Sözcükler ve kutuları; Vision vermezse boş.
        var words: [(word: String, box: CGRect)]
    }

    private func recognize(_ image: CGImage) throws -> Reading {
        // Önce Vision okuması bitirilip istek bırakılır; simge tanıma (kendi Vision isteklerini açar) ondan sonra yapılır.
        // İstek açıkken iç içe istek açmak Vision'ın sınırlı iş kuyruğunu doldurup okumayı kilitliyordu.
        let raw: [RawLine] = try autoreleasepool {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [language]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { observation -> RawLine? in
                guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.5 else { return nil }
                return RawLine(text: candidate.string, box: observation.boundingBox, confidence: candidate.confidence,
                               words: Self.words(of: candidate))
            }
        }
        let lines = raw.map { line -> TextLine in
            // Vision'ın kutusu sol alttan ölçülür; burada üstten ölçülür.
            let box = line.box
            var text = Self.withIcons(line, image: image)
            if edgeIcons { text = Self.withEdgeIcons(text, line: line, image: image) }
            return TextLine(ButtonPrompts.normalizedIcons(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                            box: TextBox(left: box.minX, top: 1 - box.maxY, right: box.maxX, bottom: 1 - box.minY),
                            confidence: Double(line.confidence))
        }
        .sorted { ($0.box?.top ?? 0) < ($1.box?.top ?? 0) }
        // Nino: satırlar birleşirken araya simge eklenir; aynı simge iki kez gelebiliyor ("Hold L2 L2 to …"). Birleşmiş
        // satır yeniden sadeleştirilir.
        return Reading(lines: Self.mergedRows(lines, aspect: Double(image.width) / Double(max(image.height, 1))) {
            ButtonIcons.classify(image, box: $0)
        }.map { TextLine(ButtonPrompts.normalizedIcons($0.text), box: $0.box, confidence: $0.confidence) })
    }

    private static func words(of candidate: VNRecognizedText) -> [(word: String, box: CGRect)] {
        let text = candidate.string
        var words: [(word: String, box: CGRect)] = []
        var index = text.startIndex
        for word in text.split(separator: " ") {
            guard let range = text.range(of: word, range: index..<text.endIndex) else { return [] }
            index = range.upperBound
            guard let box = try? candidate.boundingBox(for: range)?.boundingBox else { return [] }
            words.append((String(word), box))
        }
        return words
    }

    /// Nino: oyunlar düğmeyi yazının ortasına küçük bir resim olarak koyar ("Hold ⓧ to lock on"). Vision o resmi ya hiç
    /// okumaz (sözcükler arasında simge genişliğinde boşluk kalır) ya da "•", "(x)", "L", "O" gibi tek bir karakter sanır.
    /// İkisinde de o parça görüntüden tanınıp doğru düğmeyle değiştirilir ("Hold □ to lock on").
    private static func withIcons(_ line: RawLine, image: CGImage) -> String {
        let text = line.text, words = line.words, lineBox = line.box
        guard words.count >= 2 || (words.count == 1 && mayBeIcon(words[0].word)) else { return text }
        let w = Double(image.width), h = Double(image.height)
        let lineHeight = Double(lineBox.height) * h
        let top = 1 - Double(lineBox.maxY), bottom = 1 - Double(lineBox.minY)
        var out: [String] = []
        var changed = false
        for (i, item) in words.enumerated() {
            if i > 0 {
                let left = words[i - 1].box
                let gap = Double(item.box.minX - left.maxX) * w
                if gap > lineHeight * 0.9 {
                    let place = TextBox(left: Double(left.maxX), top: top, right: Double(item.box.minX), bottom: bottom)
                    // Boşlukta simge bulunamazsa hiçbir şey eklenmez.
                    if let icon = ButtonIcons.classify(image, box: place) {
                        out.append(icon)
                        changed = true
                    }
                }
            }
            // Büyük harfli eylem satırının sonundaki tek harf ("MOUNT HORSE A") simgedir (△ "A" okunuyor).
            let shouting = text == text.uppercased()
            let trailingLetter = i == words.count - 1 && i > 0 && shouting
                && (item.word.count == 1 || ["11", "12", "13", "21", "22", "23"].contains(item.word))
            // "Hold A to …": fiilden sonraki tek büyük harf de simge olabilir (△ "A" okunuyor).
            let afterVerb = i > 0 && item.word.count == 1 && item.word.uppercased() == item.word
                && ["press", "hold", "tap", "push", "use", "release", "mash"].contains(words[i - 1].word.lowercased())
            let suspicious = Self.mayBeIcon(item.word) || trailingLetter || afterVerb
            if suspicious,
               let icon = ButtonIcons.classify(image, box: TextBox(left: Double(item.box.minX), top: top,
                                                                   right: Double(item.box.maxX), bottom: bottom)) {
                out.append(icon)
                changed = true
            } else if suspicious, !item.word.contains(where: { $0.isLetter || $0.isNumber }) {
                // Tanınmayan resim ("*", "•", "+": ıslık, işaret simgesi): düğme değildir, atılır (eskiden ✕ sanılıyordu).
                changed = true
            } else {
                out.append(item.word)
            }
        }
        return changed ? out.joined(separator: " ") : text
    }

    /// Satırın hemen solunda ve sağında simge genişliğinde bir alan görüntüden tanınır; simge varsa satıra eklenir.
    private static func withEdgeIcons(_ text: String, line: RawLine, image: CGImage) -> String {
        let box = line.box
        let w = Double(image.width), h = Double(image.height)
        let lineHeight = Double(box.height) * h
        guard lineHeight > 4 else { return text }
        let span = lineHeight * 1.8 / w
        let top = 1 - Double(box.maxY), bottom = 1 - Double(box.minY)
        let first = text.split(separator: " ").first.map(String.init) ?? ""
        let last = text.split(separator: " ").last.map(String.init) ?? ""
        var result = text
        if !ButtonPrompts.isIcon(first), Double(box.minX) - span > 0,
           let icon = ButtonIcons.classify(image, box: TextBox(left: Double(box.minX) - span, top: top,
                                                              right: Double(box.minX) - span * 0.1, bottom: bottom), strict: true) {
            result = icon + " " + result
        }
        if !ButtonPrompts.isIcon(last), Double(box.maxX) + span < 1,
           let icon = ButtonIcons.classify(image, box: TextBox(left: Double(box.maxX) + span * 0.1, top: top,
                                                              right: Double(box.maxX) + span, bottom: bottom), strict: true) {
            result = result + " " + icon
        }
        return result
    }

    /// Simgenin yanlış okunmuş hali olabilecek parça: harfsiz kısa parça ("•", "(x)", "&") ya da tek büyük harf
    /// ("I" ve "A" gerçek sözcük olabildiği için hariç).
    private static func mayBeIcon(_ word: String) -> Bool {
        let core = word.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}.,"))
        // L1/R2 simgesinin yanlış okunmuş hali: "LD", "(C1", "Ll", "RZ".
        if word.range(of: #"^[\(\[]?[LRC][0-9DIlZ|][\)\]]?$"#, options: .regularExpression) != nil { return true }
        if word.count <= 3, word.hasPrefix("("), word.hasSuffix(")") { return true }
        if core.isEmpty { return word.count <= 3 }
        if core.count <= 2, !core.contains(where: \.isLetter), !core.contains(where: \.isNumber) { return true }
        if core.count == 1, let c = core.first, c.isUppercase, c != "I", c != "A" { return true }
        return ButtonPrompts.isIcon(core) && core.count <= 2 && !["L1", "L2", "L3", "R1", "R2", "R3"].contains(core)
    }

    /// Nino: aynı satırda yan yana duran parçalar tek satır olur. Oyunlar tuş simgesini ("Hold ✕ to continue") yazının
    /// ortasına koyar; yazı tanıma simgede satırı bölüp "Hold" ve "to continue following" diye ayrı satırlar veriyordu.
    /// Aradaki boşluk bir simge kadar genişse oraya "●" konur (tuş ipucu olarak tanınsın diye).
    /// `aspect`: görüntünün eni / boyu. Kutular ene ve boya ayrı ayrı oranlandığından yatay boşluk satır yüksekliğiyle
    /// ancak bu oranla karşılaştırılabilir (eskiden karşılaştırılmıyordu; geniş olmayan bölgede simge boşluğu kaçıyordu).
    static func mergedRows(_ lines: [TextLine], aspect: Double = 16.0 / 9.0, icon: ((TextBox) -> String?)? = nil) -> [TextLine] {
        var rows: [TextLine] = []
        for line in lines.sorted(by: { ($0.box?.left ?? 0) < ($1.box?.left ?? 0) }) {
            guard let box = line.box else { rows.append(line); continue }
            let height = box.bottom - box.top
            let center = (box.top + box.bottom) / 2
            if let i = rows.firstIndex(where: { row in
                guard let r = row.box else { return false }
                let rh = r.bottom - r.top
                let gap = (box.left - r.right) * aspect
                return abs((r.top + r.bottom) / 2 - center) < max(rh, height) * 0.45 && gap > -0.01 && gap < max(rh, height) * 4
            }) {
                let r = rows[i].box!
                let gap = (box.left - r.right) * aspect
                let place = TextBox(left: r.right, top: min(r.top, box.top), right: box.left, bottom: max(r.bottom, box.bottom))
                let found = gap > max(r.bottom - r.top, height) * 0.9 ? (icon == nil ? "●" : icon?(place)) : nil
                let joiner = found.map { " \($0) " } ?? " "
                let conf = [rows[i].confidence, line.confidence].compactMap { $0 }
                rows[i] = TextLine(rows[i].text + joiner + line.text, box: r.union(box),
                                   confidence: conf.isEmpty ? nil : conf.min())
            } else {
                rows.append(line)
            }
        }
        return rows.sorted { ($0.box?.top ?? 0) < ($1.box?.top ?? 0) }
    }

    private static func stripRect(of image: CGImage, widthFraction: Double) -> CGRect {
        let width = Double(image.width) * widthFraction
        return CGRect(x: (Double(image.width) - width) / 2, y: 0, width: width, height: Double(image.height)).integral
    }

    private static func scaled(_ image: CGImage, by factor: Int) -> CGImage? {
        let width = image.width * factor, height = image.height * factor
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
