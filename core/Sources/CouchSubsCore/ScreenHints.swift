// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Nino: "kendiliğinden köşe ve mesaj çevirisi". Alttaki altyazının yanında oyunun öbür yazılarını kendiliğinden tanır,
/// çevirir ve gösterilecek listeyi (`ScreenTranslation.Item`, kare koordinatında) geri çağrıyla verir:
///
/// 1. Sol üstteki ipucu kutusu ve görev kartı (`CornerBlock`): çevirisi kutunun hemen altında, kutusuz sade yazıyla.
/// 2. En alttaki görev/öğretici satırı: yalnız oyunun altyazı çizgisi (`hudTop`) biliniyorsa.
/// 3. Telefona gelen mesaj ve arama kartı (`MessageCard`; okuma hattının `onMessage`'ından): çevirisi kartın hemen
///    üstünde, gönderenin adıyla, sade yazıyla. Kart 3 sn görülmezse çevirisi kalkar.
///
/// Mantık Mac uygulamasındaki `watchCorners` / `showMessage` ile aynıdır (oradan taşındı; Mac bu sınıfa sonra geçer).
/// Platformdan bağımsızdır: okuyucu, çevirmen ve saat dışarıdan verilir.
///
/// - Ana okuma hattını beklemez, bekletmez: `offer` hemen döner; tur ayrı görevde, düşük öncelikle sürer.
/// - Köşeler en çok `intervalMs`'te bir (1,5 sn) okunur; önceki tur bitmediyse kare atlanır.
/// - Yazı iki okumada aynı (ya da çok benzer) görülünce çevrilir; belirirken yarım okunan yazı çevrilmez.
/// - Okuma dört kez üst üste boş dönmeden çeviri kalkmaz (sahne geçişinde titremesin).
/// - Daha önce çevrilen (ya da çok benzeyen) yazı çevirmene yeniden gitmez.
@MainActor
public final class ScreenHints {
    /// Çevrilen yazının türü; çevirmen havuza gidip gitmeyeceğine buna göre karar verir (görev şeridi yalnız cihazla).
    public enum Kind: Sendable { case tip, objective, message }

    /// Oyunun menü/harita ekranı görüldü: okuma hattı (başka iş parçacığından) bu bayrak açıkken altyazı okumaz.
    public final class MenuFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var until = 0
        private let now: () -> Int

        init(clock: @escaping () -> Int) { now = clock }

        func set(until time: Int) { lock.withLock { until = time } }
        public var active: Bool { lock.withLock { now() < until } }
    }

    /// İki tur arasındaki en kısa süre.
    public nonisolated static let defaultIntervalMs = 1500
    /// Sol üst: oyunun ipucu kutusu. GTA 6'nın yardım kutusu ekranın ortasına kadar iner; son satırı kesilmesin.
    public static let tipRegion = CropRegion(top: 0.0, bottom: 0.48, left: 0.0, right: 0.40)
    /// Menü araması: bütün ekran (üç turda bir, küçültülmüş kareyle).
    static let menuRegion = CropRegion(top: 0.03, bottom: 0.95, left: 0.0, right: 1.0)
    /// Mesaj kartı bu kadar süre görülmezse çevirisi kalkar.
    public static let messageStaleMs = 3000

    private let reader: TextReader
    private let menuReader: TextReader?
    private let translate: (String, Kind) async throws -> String
    private let intervalMs: Int
    private let now: () -> Int

    /// Çeviri dili: yazı zaten bu dildeyse (PS5'in kendi ekranı) çevrilmez.
    public var targetLanguage = "tr"
    /// Oyunun öğrenilen altyazı çizgisi (0–1); verilirse altındaki görev/öğretici şeridi de okunur.
    public var hudTop: Double?
    /// Gösterilecek liste her değiştiğinde (boşsa: hepsi kalktı).
    public var onChange: (([ScreenTranslation.Item]) -> Void)?
    public var onLog: ((String) -> Void)?
    public let menuFlag: MenuFlag
    /// Tamamlanan tur ve yazı tanıma sayısı (ölçüm ve testler için).
    public private(set) var passes = 0
    public private(set) var reads = 0

    private static let slotNames = ["sol üst", "görev"]
    private var texts = ["", ""]
    private var pending = ["", ""]
    private var emptyReads = [0, 0]
    private var slotItems: [[ScreenTranslation.Item]] = [[], []]
    /// Son çevrilen köşe yazıları. Aynı kutu her okumada biraz farklı çıkar; benzeri çevrildiyse çevirmene gitmez.
    private var memory: [(text: String, items: [ScreenTranslation.Item])] = []
    private var menuCounter = 0
    private var menuSeenAt: Int?
    private var menuBoxes: [TextBox] = []
    /// PS5'in kendi (hedef dildeki) ekranı görüldü; bu zamana kadar köşe yazıları çevrilmez.
    private var systemScreenUntil = 0
    private var lastPass: Int?
    private var running: Task<Void, Never>?
    private var session = 0

    private var messageText = ""
    private var messagePending = ""
    private var messageItems: [ScreenTranslation.Item] = []
    private var messageSeen: Int?
    private var messageTask: Task<Void, Never>?

    /// - Parameters:
    ///   - reader: köşe okuyucusu (gerçekte `VisionReader(edgeIcons: true)`).
    ///   - menuReader: menü araması için okuyucu; nil ise menü aranmaz.
    ///   - translate: parçayı çevirir. Sıra çağırana aittir (Mac'teki gibi: havuz eşleşmesi, havuz, seçili çevirmen).
    public init(reader: TextReader, menuReader: TextReader? = nil,
                intervalMs: Int = ScreenHints.defaultIntervalMs, clock: @escaping () -> Int = SubtitleStabilizer.uptimeMs,
                translate: @escaping (String, Kind) async throws -> String) {
        self.reader = reader
        self.menuReader = menuReader
        self.translate = translate
        self.intervalMs = intervalMs
        self.now = clock
        menuFlag = MenuFlag(clock: clock)
    }

    /// Şu an gösterilecek çeviriler: sol üst, görev şeridi, mesaj.
    public var items: [ScreenTranslation.Item] { slotItems.flatMap { $0 } + messageItems }

    /// Bir tur sürüyor mu.
    public var isBusy: Bool { running != nil }

    /// Her karede çağrılır; tur zamanı geldiyse ve önceki tur bittiyse turu arka planda başlatır, hemen döner.
    /// `subtitleBox`/`subtitleText`: ekrandaki altyazı (görev şeridi onu ikinci kez çevirmesin).
    public func offer(_ frame: CGImage, subtitleBox: TextBox? = nil, subtitleText: String = "") {
        clearStaleMessage()
        guard running == nil else { return }
        let time = now()
        if let lastPass, time - lastPass < intervalMs { return }
        lastPass = time
        let session = self.session
        running = Task { [weak self] in
            await self?.pass(frame, subtitleBox: subtitleBox, subtitleText: subtitleText)
            // Bu arada sıfırlandıysa yeni oturumun turuna dokunulmaz.
            if self?.session == session { self?.running = nil }
        }
    }

    /// PS5'in kendi (hedef dildeki) ekranı okundu: köşe yazıları 15 sn çevrilmez (ana ekrandaki oyun adları ipucu sanılmasın).
    public func noteSystemScreen() { systemScreenUntil = now() + 15_000 }

    /// Oturum bitti ya da çevirmen/dil değişti: süren işler bırakılır, her şey unutulur, ekrandakiler kalkar.
    public func reset() {
        session += 1
        running?.cancel()
        running = nil
        messageTask?.cancel()
        messageTask = nil
        let shown = !items.isEmpty
        texts = ["", ""]
        pending = ["", ""]
        emptyReads = [0, 0]
        slotItems = [[], []]
        memory = []
        menuCounter = 0
        menuSeenAt = nil
        menuBoxes = []
        systemScreenUntil = 0
        lastPass = nil
        menuFlag.set(until: 0)
        messageText = ""
        messagePending = ""
        messageItems = []
        messageSeen = nil
        if shown { onChange?([]) }
    }

    // MARK: - Köşeler

    /// Bir tur: sol üst kutusu (ve varsa görev şeridi, sırası geldiyse menü) okunur; değişen ve kararlı yazı çevrilir.
    /// Testler doğrudan çağırır.
    public func pass(_ frame: CGImage, subtitleBox: TextBox? = nil, subtitleText: String = "") async {
        let started = session
        passes += 1
        // Bütün ekranın okunması yazı tanımayı yorar: menü üç turda bir (~4,5 sn) ve küçültülmüş kareyle aranır.
        menuCounter = (menuCounter + 1) % 3
        let readMenu = menuReader != nil && menuCounter == 0
        let recentMenu = menuSeenAt.map { now() - $0 < 6000 } == true ? menuBoxes : []

        var readings: [Reading] = [.empty, .empty]
        // Sol üst: yalnız ipucu kutusu ya da görev kartı (haritadaki yer adları değil; bkz. CornerBlock).
        readings[0] = CornerBlock.tipBox(in: await read(frame, region: Self.tipRegion, with: reader))
        guard session == started else { return }
        if let hudTop, hudTop < 0.995 {
            // Görev şeridi: altyazının yerindeki ya da altyazıyla aynı satır ikinci kez çevrilmez (onu altyazı okuyucusu çevirdi).
            let strip = await read(frame, region: CropRegion(top: hudTop, bottom: 0.995, left: 0.08, right: 0.92), with: reader)
            guard session == started else { return }
            let shown = TextMatch.normalize(subtitleText)
            readings[1] = Reading(lines: strip.lines.filter { line in
                Self.isObjectiveLine(line) && !Self.repeatsSubtitle(line, box: subtitleBox, text: shown)
            })
        }
        var menuArea = recentMenu
        if readMenu, let menuReader {
            let screen = await read(frame, region: Self.menuRegion, with: menuReader, maxWidth: 1280)
            guard session == started else { return }
            if MenuBlock.isMenuScreen(screen) {
                // Harita/duraklatma ekranı: okuma hattı 5 sn altyazı okumaz (yer adları altyazı sanılıyordu).
                menuFlag.set(until: now() + 5000)
            }
            let menus = MenuBlock.groups(in: Reading(lines: screen.lines.map { line in
                var cleaned = line
                cleaned.text = MenuBlock.clean(line.text)
                return cleaned
            }.filter { !$0.text.isEmpty }))
            menuArea = menus.flatMap(\.lines).compactMap(\.box)
            if !menuArea.isEmpty { menuSeenAt = now(); menuBoxes = menuArea }
        }
        // Menü ekrandayken (son 6 sn'de görüldüyse) sol üst kutusu menü satırlarını çevirmez.
        if !menuArea.isEmpty {
            readings[0] = Reading(lines: readings[0].lines.filter { line in
                guard let box = line.box else { return true }
                return !menuArea.contains { $0.top < box.bottom + 0.02 && box.top - 0.02 < $0.bottom }
            })
        }

        var changed = false
        for i in readings.indices {
            let reading = readings[i]
            let text = reading.text
            if text == texts[i] { emptyReads[i] = 0; continue }
            // Yazı ekranda durdukça çevirisi de durur: okuma bir iki kez boş dönünce (sahne geçişi, parlaklık)
            // silinmez; dört okuma (~6 sn) üst üste yoksa kalkar.
            if text.isEmpty, !texts[i].isEmpty {
                emptyReads[i] += 1
                if emptyReads[i] < 4 { continue }
            }
            emptyReads[i] = 0
            if !text.isEmpty {
                // Kutu belirirken ya da kaybolurken yarım okunan yazı çevrilmez: iki okumada aynı (ya da çok benzer) olmalı.
                let seen = TextMatch.normalize(text), before = TextMatch.normalize(pending[i])
                pending[i] = text
                guard seen == before || (seen.count >= 30 && TextMatch.isSimilar(seen, before, threshold: 0.8)) else { continue }
            }
            pending[i] = ""
            texts[i] = text
            changed = true
            guard !text.isEmpty else {
                slotItems[i] = []
                continue
            }
            // Yalnız oyunun yazıları çevrilir. Satırlarından biri zaten hedef dildeyse bu PS5'in kendi ekranıdır.
            let already = TargetLanguage.hasLine(text, in: targetLanguage)
            if already { systemScreenUntil = now() + 15_000 }
            if already || now() < systemScreenUntil {
                if !slotItems[i].isEmpty { onLog?("köşe \(Self.slotNames[i]): PS5 ekranı, çevrilmedi") }
                slotItems[i] = []
                // Hedef dilde değilse bekleme bitince yeniden bakılsın (oyuna dönülünce çıkan ipucu kaçmasın).
                if !already { texts[i] = "" }
                continue
            }
            // Sol üst ipucu kutusu cümledir: en az üç gerçek sözcük. Duraklatma menüsünün kalıntısı ("11 Map", "Help")
            // ve okuma çöpü çevrilmez.
            if i == 0, text.split(whereSeparator: { !$0.isLetter && $0 != "'" }).filter({ $0.count >= 2 }).count < 3 {
                slotItems[i] = []
                continue
            }
            let key = TextMatch.normalize(text)
            // Kısa yazıda tek harf anlamı değiştirir ("Follow John" / "Follow Josh"); benzerlik yalnız uzun kutuda.
            if let known = memory.last(where: { $0.text == key || (key.count >= 30 && TextMatch.isSimilar($0.text, key, threshold: 0.8)) }) {
                slotItems[i] = known.items
                continue
            }
            let kind: Kind = i == 0 ? .tip : .objective
            let translate = self.translate
            let translatePiece: (String) async throws -> String = { try await translate($0, kind) }
            // Görev kartı: büyük harfli başlık ("UNWANTED ATTENTION", "HELP") metne karışmasın; ayrı çevrilir, üstte büyük harfle.
            var title = ""
            var body = reading
            if i == 0, reading.lines.count >= 2, let first = reading.lines.first, Reading.isItemLabel(first.text) {
                title = ((try? await translatePiece(first.text)) ?? first.text).uppercased(with: Locale(identifier: targetLanguage))
                body = Reading(lines: Array(reading.lines.dropFirst()))
            }
            var translated = (try? await ScreenTranslation.translate(body, using: translatePiece)) ?? []
            // Bu arada sıfırlandıysa (dil değişti) eski dildeki sonuç yazılmaz.
            guard session == started, !Task.isCancelled else { return }
            if !title.isEmpty, var first = translated.first {
                first.translation = title + "\n" + first.translation
                translated[0] = first
            }
            // Sol üstteki çeviri oyunun yazısının üstüne değil hemen altına konur (oyunun yazısı ve işareti görünür).
            if i == 0 { translated = translated.map { Self.placedBelow($0, locale: Locale(identifier: targetLanguage)) } }
            slotItems[i] = translated
            if !translated.isEmpty {
                memory.append((key, translated))
                if memory.count > 40 { memory.removeFirst() }
            }
            onLog?("köşe \(Self.slotNames[i]): \"\(text.replacingOccurrences(of: "\n", with: " / "))\" → \(translated.map(\.translation).joined(separator: " / "))")
        }
        if changed { onChange?(items) }
    }

    private func read(_ frame: CGImage, region: CropRegion, with reader: TextReader, maxWidth: Int? = nil) async -> Reading {
        reads += 1
        let place = TextBox(left: region.left, top: region.top, right: region.right, bottom: region.bottom)
        return await Task.detached(priority: .utility) { () -> Reading in
            var area = RegionCropper.crop(frame, to: region)
            if let maxWidth, let small = Self.downscaled(area, maxWidth: maxWidth) { area = small }
            return ((try? reader.readLines(area, deep: false)) ?? .empty).withoutOcrNoise().placed(in: place)
        }.value
    }

    /// Sol üstteki çeviri: bloğun tamamının altına (satırlara değmeden), simgesiz ve kutusuz. Oyunun yazısından küçük
    /// (yarı saydam not gibi), oyunun kutusuyla aynı genişlikte birkaç satır; görev başlığı (büyük harf) kendi satırında.
    nonisolated static func placedBelow(_ item: ScreenTranslation.Item, locale: Locale = Locale(identifier: "tr")) -> ScreenTranslation.Item {
        var moved = item
        let line = min(item.lineHeight > 0 ? item.lineHeight : 0.03, 0.032) * 0.8
        moved.lineHeight = line
        let right = max(item.box.right, item.box.left + 0.2)
        var parts = item.translation.split(separator: "\n").map { withoutLeadingSymbols(String($0)) }
        let heading = parts.count >= 2 && parts[0] == parts[0].uppercased(with: locale)
            && parts[0].contains(where: \.isLetter) ? parts.removeFirst() : nil
        let text = withoutIcons(parts.joined(separator: " "))
        let wrapped = (heading.map { [withoutIcons($0)] } ?? []) + wrap(text, width: right - item.box.left, line: line)
        let lines = Double(wrapped.count)
        let top = min(1 - line * lines * 1.3, item.box.bottom + line * 0.8 + 0.03)
        moved.box = TextBox(left: item.box.left, top: top, right: right, bottom: top + line * lines * 1.3)
        moved.translation = wrapped.joined(separator: "\n")
        moved.plain = true
        return moved
    }

    /// Görev şeridindeki satır altyazının yerinde ya da altyazıyla aynıysa (altyazı okuyucusu çevirdi) atlanır.
    nonisolated static func repeatsSubtitle(_ line: TextLine, box: TextBox?, text: String) -> Bool {
        if let box, let own = line.box, own.top < box.bottom + 0.01, box.top - 0.01 < own.bottom,
           own.left < box.right, box.left < own.right { return true }
        let read = TextMatch.normalize(line.text)
        guard read.count >= 6, !text.isEmpty else { return false }
        if text.contains(read) || read.contains(text) { return true }
        let words = Set(read.split(separator: " ")), shown = Set(text.split(separator: " "))
        return !words.isEmpty && Double(words.intersection(shown).count) / Double(words.count) >= 0.5
    }

    /// Alt şeritte ekranın ortasına yakın duran satır görev/öğretici yazısıdır; kenardaki menü yazıları atlanır.
    nonisolated static func isObjectiveLine(_ line: TextLine) -> Bool {
        guard let box = line.box else { return false }
        // Konuşan adıyla başlayan satır altyazıdır (ana okuyucu alır).
        if SpeakerPrefix.split(line.text) != nil { return false }
        let center = (box.left + box.right) / 2
        return center > 0.32 && center < 0.68
    }

    // MARK: - Telefon mesajları

    /// Okuma hattının `onMessage`'ı: telefona gelen mesaj ya da arama kartı (satırlar kare koordinatında).
    /// Çevirisi kartın hemen üstüne konur; aynı kart yeniden çevrilmez.
    public func message(_ card: Reading) {
        messageSeen = now()
        if let call = MessageCard.call(card) {
            showCall(card, name: call.name, status: call.status)
            return
        }
        let (name, body) = MessageCard.parts(card)
        let key = TextMatch.normalize(body)
        // Kart belirirken yarım okunabilir: aynı metin iki okumada görülünce çevrilir.
        guard key != messageText, messageTask == nil else { return }
        guard key == messagePending else { messagePending = key; return }
        messageText = key
        let boxes = card.lines.compactMap(\.box)
        let translate = self.translate
        let session = self.session
        messageTask = Task { [weak self] in
            let translated = try? await translate(body, .message)
            guard let self, session == self.session else { return }
            messageTask = nil
            guard let translated = translated.map(Self.withoutIcons), !translated.isEmpty else { return }
            messageItems = [Self.messageItem(name: name, body: body, translation: translated, boxes: boxes)]
            onLog?("mesaj: \(name): \(SubtitleLog.excerpt(body)) → \(translated)")
            onChange?(items)
        }
    }

    /// Süren mesaj çevirisi bitene kadar bekler (testler için).
    public func waitForMessage() async { await messageTask?.value }

    /// Telefon araması kartı: "Paradise Taxi aranıyor…" kartın hemen üstünde eğik yazıyla (çeviriye gitmez). Konuşma
    /// sürerken (kartta süre) bir şey gösterilmez. Durum metinleri Türkçedir; başka çeviri dilinde gösterilmez.
    private func showCall(_ card: Reading, name: String, status: String) {
        let key = "arama:" + name + status
        guard key != messageText else { return }
        messageText = key
        messagePending = ""
        guard !status.isEmpty, TargetLanguage.isTurkish(targetLanguage) else {
            if !messageItems.isEmpty { messageItems = []; onChange?(items) }
            return
        }
        messageItems = [Self.callItem(name: name, status: status, boxes: card.lines.compactMap(\.box))]
        onLog?("arama: \(name) \(status)")
        onChange?(items)
    }

    /// Kart ekrandan kalktıysa (3 sn görülmediyse) çevirisi de kalkar. `offer` her karede çağırır.
    public func clearStaleMessage() {
        guard !messageItems.isEmpty, let messageSeen, now() - messageSeen > Self.messageStaleMs else { return }
        messageItems = []
        messageText = ""
        messagePending = ""
        onChange?(items)
    }

    /// Mesajın çevirisi: kartın hemen üstünde, ilk satırda gönderenin adı, kutusuz sade yazı; oyunun yazısından küçük.
    nonisolated static func messageItem(name: String, body: String, translation: String, boxes: [TextBox]) -> ScreenTranslation.Item {
        let left = boxes.map(\.left).min() ?? 0.5, right = boxes.map(\.right).max() ?? 0.9
        let top = boxes.map(\.top).min() ?? 0.7
        let line = min(boxes.dropFirst().first.map { $0.bottom - $0.top } ?? 0.03, 0.032) * 0.8
        let wrapped = wrap(translation, width: max(0.2, right - left), line: line)
        let height = line * Double(wrapped.count + 1) * 1.3
        let itemTop = max(0, top - height - 0.02)
        var item = ScreenTranslation.Item(source: body, translation: ([name] + wrapped).joined(separator: "\n"),
                                          box: TextBox(left: left, top: itemTop, right: max(right, left + 0.2), bottom: itemTop + height),
                                          lineHeight: line)
        item.plain = true
        return item
    }

    nonisolated static func callItem(name: String, status: String, boxes: [TextBox]) -> ScreenTranslation.Item {
        let left = boxes.map(\.left).min() ?? 0.1, right = boxes.map(\.right).max() ?? 0.4
        let top = boxes.map(\.top).min() ?? 0.8
        let line = min(boxes.first.map { $0.bottom - $0.top } ?? 0.03, 0.032) * 0.8
        let height = line * 1.3
        let itemTop = max(0, top - height - 0.035)
        var item = ScreenTranslation.Item(source: name, translation: "\(name) \(status)",
                                          box: TextBox(left: left, top: itemTop, right: max(right, left + 0.2), bottom: itemTop + height),
                                          lineHeight: line)
        item.plain = true
        item.italic = true
        return item
    }

    // MARK: - Yardımcılar (Mac'teki AppModel'den kopyalandı)

    /// Yazıyı verilen genişliğe (ekran oranı) sığacak satırlara böler; harf genişliği satır yüksekliğinin ~0,5'i (16:9).
    nonisolated static func wrap(_ text: String, width: Double, line: Double) -> [String] {
        let perLine = max(12, Int(width / max(0.004, line * 0.5 * 9 / 16)))
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if !current.isEmpty, current.count + 1 + word.count > perLine {
                lines.append(current)
                current = ""
            }
            current += current.isEmpty ? String(word) : " " + word
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [text] : lines
    }

    /// Tuş simgeleri ("□", "✕", "○", "△", "⊙") çıkarılır; "L1", "R2" gibi tuş adları kalır.
    nonisolated static func withoutIcons(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .otherSymbol, .mathSymbol, .privateUse: return false
            default: return true
            }
        }
        return String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Çevirinin başındaki oyun simgeleri (◆, ✦, yazı tanımanın okuduğu işaretler) atılır.
    nonisolated static func withoutLeadingSymbols(_ text: String) -> String {
        String(text.drop { !$0.isLetter && !$0.isNumber && $0 != "\"" && $0 != "'" && $0 != "(" })
    }

    /// Kareyi en çok `maxWidth` piksel genişliğe küçültür (oran korunur); zaten küçükse nil.
    nonisolated static func downscaled(_ image: CGImage, maxWidth: Int) -> CGImage? {
        guard image.width > maxWidth else { return nil }
        let height = Int(Double(image.height) * Double(maxWidth) / Double(image.width))
        guard let context = CGContext(data: nil, width: maxWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
        return context.makeImage()
    }
}
