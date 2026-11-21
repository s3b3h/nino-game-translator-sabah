// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation
import CoreML
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
    /// Nino: okuma yalnız işlemcide yapılır (Neural Engine kullanılmaz). Telefon ekranı gibi sık okunan büyük ve net
    /// yazılar için: Neural Engine'deki istek sıklığı artınca Apple'ın yazı tanıması takılıp Nino'yu yeniden açtırıyordu.
    public var cpuOnly = false
    /// Nino: hızlı düzey (Neural Engine modelini kullanmaz; yedek okuyucuda model derlenirken).
    public var fastLevel = false

    public init(language: String = "en", edgeIcons: Bool = false, cpuOnly: Bool = false) {
        self.language = language
        self.edgeIcons = edgeIcons
        self.cpuOnly = cpuOnly
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
        //
        // Vision bazen tek bir okumada sonsuza dek takılıyor (Apple'ın hatası); kapı kilidi de bırakılmadığı için bütün
        // sonraki okumalar sıraya girip birikiyordu (22 iş parçacığı) ve altyazı ancak Nino yeniden açılınca dönüyordu.
        // Artık kapı en çok `gateWait` beklenir; dolarsa takılan istek iptal edilir, yine açılmazsa kapı yenilenir (takılan
        // iş parçacığı bırakılır) ve bu kare atlanır. Sonraki kare yeni kapıdan okunur.
        #if os(macOS)
        // Nino 4.0.5: asıl okuma takılıyken okumalar yedek okuyucuya (ayrı süreç) gider; bu süreçteki Vision beklenmez.
        if Self.watch.rescuing, let rescuer = Self.rescuer {
            do { return try rescuer.read(image, language: language, deep: deep, edgeIcons: edgeIcons) }
            catch OcrHelperReader.NotReady.warming { throw VisionBusy() }
        }
        #endif
        let gate = Self.watch.gate
        guard gate.lock(before: Date().addingTimeInterval(Self.gateWait)) else {
            // Nino: kapıyı tutan okuma kısa süredir sürüyorsa takılma yoktur, yalnız sıra kalabalıktır (telefon, altyazı,
            // köşeler ve harita aynı anda okunuyor). Bu kare atlanır; eskiden bu da "takıldı" sayılıp Nino kendini 20-30
            // sn'de bir yeniden açıyordu (20 Kasım 2026, GTA 6 telefonu).
            if let held = Self.watch.heldFor, held < Self.stuckAfter { throw VisionBusy() }
            // Takılma Neural Engine'de (TextRecognition bir semaforda sonsuza dek bekliyor; sonraki her istek aynı
            // dedektörün sırasına girip o da takılıyordu). Bundan sonraki okumalar işlemcide (CPU) yapılır: ayrı bir
            // dedektör açılır, altyazı Nino'yu kapatıp açmadan sürer.
            #if os(macOS)
            // Nino 4.0.5: Vision'ın kilidi süreç genelinde; takılan okumanın yanına bu süreçte yenisi verilmez. Okumalar
            // yedek okuyucuya geçer; takılan okuma bitince (Watch.released) asıl okuyucuya dönülür. PS5 bağlantısı kopmaz.
            if let rescuer = Self.rescuer, !rescuer.isExhausted {
                Self.watch.cancelRunning()
                if Self.watch.beginRescue() {
                    Self.onLog?("Vision okuması \(Self.watch.holdingInfo) takıldı; okumalar yedek okuyucuya (ayrı süreç) geçti\(rescuer.isReady ? "" : " (yedek henüz ısınıyor)"), PS5 bağlantısı sürüyor")
                }
                do { return try rescuer.read(image, language: language, deep: deep, edgeIcons: edgeIcons) }
                catch OcrHelperReader.NotReady.warming { throw VisionBusy() }
            }
            #endif
            Self.watch.switchToCPU()
            Self.watch.cancelRunning()
            guard gate.lock(before: Date().addingTimeInterval(1)) else {
                // Nino V4: telefon, harita ve köşe okumaları eklenince tek bir okuma 9-10 sn sürebiliyor ama bitiyor.
                // Bunu "takıldı" sayıp Nino'yu yeniden açmak PS5 bağlantısını 5 dakikada bir koparıyordu (21 Kasım
                // 2026). Yavaş okumada yalnız bu kare atlanır; kapı ancak okuma `hardStuckAfter`'dan uzun sürerse
                // (gerçek takılma, hiç bitmez) yenilenir ve Nino yeniden açılır.
                if let held = Self.watch.heldFor, held < Self.hardStuckAfter { throw VisionBusy() }
                Self.watch.replace(gate)
                throw VisionStuck()
            }
            Self.watch.took(holderInfo(image))
            defer { Self.watch.released(); gate.unlock() }
            return deep ? try Self.firstLines(of: image, using: recognize) : try recognize(image)
        }
        Self.watch.took(holderInfo(image))
        defer { Self.watch.released(); gate.unlock() }
        let reading = deep ? try Self.firstLines(of: image, using: recognize) : try recognize(image)
        #if os(macOS)
        // Nino 4.0.5: yedek okuyucu oturumun ilk başarılı okumasında bu kareyle ısıtılır (açıksa bir şey yapmaz).
        if let rescuer = Self.rescuer, !reading.lines.isEmpty { rescuer.prepare(image, language: language) }
        #endif
        return reading
    }

    /// Kapı en çok bu kadar beklenir (saniye); normal bir okuma 0,1-0,5 sn sürer.
    static let gateWait: TimeInterval = 4
    /// Kapıyı tutan tek bir okuma bundan uzun sürerse takılmış sayılır. Cihaz üstü çeviri de Neural Engine'i kullanır;
    /// telefonun mesajları çevrilirken bir okuma birkaç saniye sürebiliyor. Gerçek takılma hiç bitmez, bu sınırla da yakalanır.
    static let stuckAfter: TimeInterval = 8
    /// Kapıyı tutan okuma bundan uzun sürerse kalıcı takılma sayılır (Mac Nino'yu yeniden açar). Yavaş ama biten
    /// okumalar (9-10 sn) bu sınırın çok altında kalır.
    static let hardStuckAfter: TimeInterval = 45

    /// Nino: okuma sırası kalabalık; bu kare okunmadan atlanır (takılma değildir).
    public struct VisionBusy: Error, CustomStringConvertible {
        public var description: String { "Vision okuma sırası dolu; kare atlandı" }
    }

    /// Vision'ın takıldığını bildirir; bu kare okunmaz.
    public struct VisionStuck: Error, CustomStringConvertible {
        public var description: String { "Vision okuması takıldı; istek iptal edildi" }
    }

    /// Okuma kapısı ve süren Vision istekleri (takılınca iptal için).
    final class Watch: @unchecked Sendable {
        private let lock = NSLock()
        private var current = NSLock()
        private var running: [ObjectIdentifier: VNRequest] = [:]
        private var cpu = false
        private var holderSince: Date?
        private var holder = ""
        private var stuckHolder = ""

        /// Takıldığında kapıyı tutan okuma (görüntünün boyu, işlemci mi) ve ne zamandır sürdüğü.
        var stuckInfo: String { lock.withLock { stuckHolder } }
        func took(_ info: String) { lock.withLock { holderSince = Date(); holder = info } }

        /// Kapıyı şu an tutan okuma ne zamandır sürüyor (kapı boşsa nil).
        var heldFor: TimeInterval? { lock.withLock { holderSince.map { Date().timeIntervalSince($0) } } }
        func released() {
            let rescued: Date? = lock.withLock {
                holderSince = nil
                defer { rescueSince = nil }
                return rescueSince
            }
            // Nino 4.0.5: takılan asıl okuma sonunda bitti; okumalar asıl okuyucuya döner, yedek kapanır.
            if let rescued {
                VisionReader.onLog?(String(format: "asıl okuyucu düzeldi (%.0f sn yedekte okundu)", Date().timeIntervalSince(rescued)))
                #if os(macOS)
                VisionReader.rescuer?.standDown()
                #endif
            }
        }

        /// Nino 4.0.5: okumalar yedekte mi (asıl okuma takılı).
        private var rescueSince: Date?
        var rescuing: Bool { lock.withLock { rescueSince != nil } }
        /// Yedeğe geçer; zaten yedekteyse false.
        func beginRescue() -> Bool { lock.withLock { guard rescueSince == nil else { return false }; rescueSince = Date(); return true } }
        /// Kapıyı tutan okuma ve ne zamandır sürdüğü (günlük için).
        var holdingInfo: String {
            lock.withLock { "(" + holder + (holderSince.map { String(format: ", %.1f sn", Date().timeIntervalSince($0)) } ?? "") + ")" }
        }

        /// Neural Engine takıldıysa okumalar işlemcide yapılır (bu oturum boyunca).
        var usesCPU: Bool { lock.withLock { cpu } }
        func switchToCPU() { lock.withLock { cpu = true } }

        var gate: NSLock { lock.withLock { current } }

        func replace(_ stuck: NSLock) {
            lock.withLock {
                if current === stuck { current = NSLock() }
                wasStuck = true
                stuckHolder = holder + (holderSince.map { String(format: ", %.1f sn", Date().timeIntervalSince($0)) } ?? "")
            }
        }

        /// Nino 4.0.4: takılan okuma bırakılır, kapı yenilenir ve takılma bayrağı silinir (Mac uygulamayı kapatmadan
        /// okumayı yeniden kurar; PS5 bağlantısı kopmaz).
        func recover() {
            lock.withLock {
                current = NSLock()
                wasStuck = false
                holderSince = nil
                cpu = true
            }
        }

        /// Bir okuma takıldı ve kapı yenilendi (Nino: Mac bunu görünce kendini yeniden açar; aynı süreçte Vision düzelmiyor).
        private var wasStuck = false
        var stuck: Bool { lock.withLock { wasStuck } }

        func started(_ request: VNRequest) { lock.withLock { running[ObjectIdentifier(request)] = request } }
        func finished(_ request: VNRequest) { lock.withLock { running[ObjectIdentifier(request)] = nil } }

        func cancelRunning() {
            let requests = lock.withLock { Array(running.values) }
            requests.forEach { $0.cancel() }
        }
    }

    static let watch = Watch()

    #if os(macOS)
    /// Nino 4.0.5: takılmada okumaları devralan yedek okuyucu (Mac uygulaması kurar; yoksa eski davranış).
    nonisolated(unsafe) public static var rescuer: OcrHelperReader?
    #endif
    /// Nino: okuyucu olayları için günlük (Mac uygulaması kurar).
    nonisolated(unsafe) public static var onLog: (@Sendable (String) -> Void)?
    /// Yedek okuyucu şu an kullanılıyor mu (asıl Vision takılı).
    public static var isRescuing: Bool { watch.rescuing }

    /// Nino: takılma anında kapıyı tutan okuma (günlüğe yazılır; hangi okumanın takıldığı anlaşılsın).
    public static var stuckInfo: String { watch.stuckInfo }

    private func holderInfo(_ image: CGImage) -> String {
        "\(image.width)×\(image.height)" + (cpuOnly ? " işlemci" : "") + (deepLabel)
    }
    private var deepLabel: String { edgeIcons ? " simgeli" : "" }

    /// Nino 4.0.4: takılmadan sonra uygulamayı kapatmadan devam: süren istekler iptal edilir, takılan okuma bırakılır ve
    /// bundan sonraki okumalar işlemcide (Neural Engine'siz) yapılır.
    public static func recoverInProcess() {
        watch.cancelRunning()
        watch.recover()
    }

    /// Vision bu süreçte takıldı mı (bkz. `Watch.replace`).
    public static var isStuck: Bool { watch.stuck }

    /// İsteği yalnız işlemcide çalıştırır (Neural Engine ve GPU kullanılmaz).
    static func runOnCPU(_ request: VNRequest) {
        if #available(macOS 14.0, iOS 17.0, *) {
            if let devices = try? request.supportedComputeStageDevices {
                for (stage, choices) in devices {
                    if let cpu = choices.first(where: { if case .cpu = $0 { return true } else { return false } }) {
                        request.setComputeDevice(cpu, for: stage)
                    }
                }
                return
            }
        }
        request.usesCPUOnly = true
    }

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
        // Nino: sırayla (eskiden aynı anda): aynı anda iki Vision isteği Neural Engine'i kilitleyebiliyor; boş karede
        // bu yol çok sık çalışıyordu ve takılmalar en çok buradan geliyordu.
        let results = Results(count: fallbacks.count)
        for index in fallbacks.indices {
            results.set(index, Result { try fallbacks[index]() ?? .empty })
            if case .success(let reading)? = results.all[index], !reading.lines.isEmpty { break }
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
            request.recognitionLevel = fastLevel ? .fast : .accurate
            request.recognitionLanguages = [language]
            request.usesLanguageCorrection = true
            if cpuOnly || Self.watch.usesCPU { Self.runOnCPU(request) }
            Self.watch.started(request)
            defer { Self.watch.finished(request) }
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
                // Nino: boyu iki kattan fazla farklı parçalar aynı yazı değildir (altyazının yanına düşen dev tabela harfi,
                // gösterge); birleşirlerse satır "dev" ölçülür ve altyazı tabela sanılıp atılırdı.
                guard min(rh, height) >= max(rh, height) * 0.5 else { return false }
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
