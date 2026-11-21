// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Nino: oyundaki telefonda (GTA 6) bir sohbet açıksa mesajlarını okur, çevirir ve telefonun boş yanına mesajlaşma paneli
/// olarak koyar; sohbet olmayan uygulamada (BuckMe, Rydeme) her yazının Türkçesi uygulamanın renginde baloncuktur.
/// Eskiden bu yazılar altyazı sanılıp telefonun üstünde kocaman siyah kutuda çıkıyordu.
///
/// Kurallar Mac'teki `AppModel.watchPhone` / `trackPhone` ile ve Windows'taki `PhoneWatcher` ile aynıdır; iPhone bunu
/// kullanır (Mac sonra bu sınıfa geçebilir).
///
/// - Ana okuma hattını beklemez, bekletmez: `offer` hemen döner; okuma ayrı görevde, düşük öncelikle sürer.
/// - Türkçeler yerleşmeden 0,6 sn'de, yerleştikten sonra 1,5 sn'de bir okunur (bütün yazı okumaları aynı motoru
///   paylaşır; sık okuma altyazıyı bekletiyordu).
/// - Aynı okuma iki kez görülünce çevrilir (kaydırma sürerken yarım okunan satırlar çevrilmez).
/// - Türkçeler yerleştikten sonra telefon elde sallanırsa yazı yeniden okunmadan yalnız telefonun yeri bulunur ve
///   balonlar onunla birlikte kaydırılır.
@MainActor
public final class PhoneWatcher {
    /// Bir çeviri: yazı (yoksa nil) ve hafızaya yazılıp yazılmayacağı (cihazın yedek çevirisi yazılmaz; sonraki okumada
    /// havuz yeniden sorulur, o arada doğru çeviri girmiş olabilir).
    public struct Translation: Sendable {
        public var text: String?
        public var remember: Bool
        public init(text: String?, remember: Bool) {
            self.text = text
            self.remember = remember
        }
    }

    /// Mesajı (sohbette önceki en çok üç mesajla birlikte) çevirir.
    public typealias Translate = @Sendable (_ text: String, _ context: [String]) async -> Translation

    /// Telefon bu kadardan az kaydıysa (elde sallanma) panel yerinde kalır.
    nonisolated static let steady = 0.05
    /// Telefondaki yazılar altyazı okumasında bu kadar süre altyazı sayılmaz.
    public nonisolated static let recentTextsMs = 30_000
    /// Haritanın tuş listesi: telefon sanılan bölgede okunduysa bu haritadır.
    nonisolated static let mapKeys: Set<String> = ["recenter", "2d view", "3d view", "add marker", "set destination", "close menu"]

    private let reader: TextReader
    private let translate: Translate
    private let now: () -> Int
    private let memoryFile: URL?
    /// Telefonu takip eder (koyu temalı uygulamada her karede bulunamıyor; bkz. `PhonePanel.Tracker`).
    public let tracker = PhonePanel.Tracker()

    /// Satırın hazır çevirisi (ortak havuz); yoksa nil. Hafızadakinden önce gelir.
    public var known: ((String) -> String?)?
    /// Telefon uygulamalarının sabit Türkçeleri (`PhoneThread.glossary`) kullanılsın mı (hedef dil Türkçe).
    public var useGlossary = true
    /// true döndüğü sürece (harita ya da menü açık) telefon aranmaz.
    public var paused: (() -> Bool)?
    /// Çevrilmemiş mesajlar (havuza bildirilmek üzere).
    public var onUnknown: (([String]) -> Void)?
    /// Gösterilecek öğeler değişti (boşsa telefonun yanı temizlenir).
    public var onChange: (([ScreenTranslation.Item]) -> Void)?
    public var onLog: ((String) -> Void)?
    /// Nino: oyunun telefonunda sohbet ya da uygulama okundu (oyun buradan da tanınır: bu telefon GTA 6'ya özgü).
    public var onPhoneScreen: (() -> Void)?
    /// Telefonun yerinin (yazı okunmadan) en sık bulunma aralığı.
    public var trackIntervalMs = 100

    public private(set) var items: [ScreenTranslation.Item] = []
    private var key = ""
    private var pending = ""
    private var seen = Int.min / 2
    private var lastCheck = Int.min / 2
    private var task: Task<Void, Never>?
    private var session = 0
    private var recent: (texts: [String], at: Int) = ([], Int.min / 2)
    /// Bu oturumda çevrilmiş mesajlar: sohbet kaydırılınca aynı mesaj yeniden çevrilmez. Dosya verildiyse diske de
    /// yazılır: Nino yeniden açılınca telefonun Türkçeleri baştan çevrilmeden hemen gelir.
    private var memory: [String: String]
    /// Örtülerin yerleştirildiği andaki telefon ekranı ve örtüler: telefon kayınca örtüler aynı kadar kaydırılır.
    private var placed: (panel: TextBox, items: [ScreenTranslation.Item])?
    /// Yerleştirildiği anda her mesajın telefon ekranına göre yeri (kaydırma bununla anlaşılır).
    private var anchors: [String: Double] = [:]
    private var trackTask: Task<Void, Never>?
    private var trackAt = Int.min / 2
    private var shift = (dx: 0.0, dy: 0.0)
    /// Bir önceki ölçümde görülen kayma: örtüler ancak belirgin kayma iki ölçüm üst üste görülünce kaydırılır.
    private var shiftSeen: (dx: Double, dy: Double)?

    /// - Parameters:
    ///   - reader: telefonun okuyucusu (gerçekte `VisionReader(language: "en", cpuOnly: true)`; Neural Engine altyazıya kalsın).
    ///   - memoryFile: çevrilen mesajların saklandığı dosya (çeviri diline özel); nil ise yalnız bellekte.
    public init(reader: TextReader, memoryFile: URL? = nil, clock: @escaping () -> Int = SubtitleStabilizer.uptimeMs,
                translate: @escaping Translate) {
        self.reader = reader
        self.translate = translate
        self.memoryFile = memoryFile
        now = clock
        memory = memoryFile.flatMap { try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: $0)) } ?? [:]
    }

    /// Telefonda son okunan mesajlar (son `recentTextsMs` içinde); altyazı okuması bunları atlar.
    public var recentTexts: [String] { now() - recent.at < Self.recentTextsMs ? recent.texts : [] }

    /// Bir okuma sürüyor mu.
    public var isBusy: Bool { task != nil }

    /// Telefon uygulamasının sözcükleri altyazı okumasında görüldü: telefon bu yazıların yerinden de bulunur.
    public func adopt(_ boxes: [TextBox], in frame: CGImage) { tracker.adopt(around: boxes, in: frame) }

    /// Her karede çağrılır: Türkçeler ekrandaysa telefonun yeri izlenir; okuma zamanı geldiyse okuma arka planda başlar.
    public func offer(_ frame: CGImage) {
        track(frame)
        guard task == nil, now() - lastCheck > (items.isEmpty ? 600 : 1500) else { return }
        // Harita/menü açıkken telefon aranmaz: haritanın aydınlık kısmı telefon sanılıp tuş listesi çevriliyordu.
        if paused?() == true {
            if !items.isEmpty { clear() }
            return
        }
        lastCheck = now()
        let started = session
        task = Task { [weak self] in
            await self?.check(frame, started: started)
            if self?.session == started { self?.task = nil }
        }
    }

    /// Telefonun yanını temizler, takibi bırakır; süren okumanın sonucu gösterilmez.
    public func reset() {
        session += 1
        task?.cancel()
        task = nil
        trackTask?.cancel()
        trackTask = nil
        let had = !items.isEmpty
        items = []
        placed = nil
        key = ""
        pending = ""
        recent = ([], Int.min / 2)
        shift = (0, 0)
        shiftSeen = nil
        if had { onChange?([]) }
    }

    /// Süren okumanın bitmesini bekler (testler için).
    public func waitUntilIdle() async { await task?.value }

    private func clear() {
        guard !items.isEmpty else { return }
        items = []
        placed = nil
        key = ""
        pending = ""
        onChange?([])
    }

    /// Bir okuma turu: telefon bulunur, ekranı okunur.
    func check(_ frame: CGImage, started: Int) async {
        let tracker = self.tracker
        let reader = self.reader
        let found = await Task.detached(priority: .utility) { () -> (PhonePanel.Panel, Reading)? in
            guard let panel = tracker.locate(in: frame) else { return nil }
            let box = panel.box
            let region = CropRegion(top: box.top, bottom: box.bottom, left: box.left, right: box.right)
            let reading = (try? reader.readLines(RegionCropper.crop(frame, to: region), deep: false)) ?? .empty
            return (panel, reading.placed(in: box))
        }.value
        guard session == started, !Task.isCancelled else { return }
        guard let (panel, reading) = found else {
            if !items.isEmpty, now() - seen > 1200 { clear() }
            return
        }
        await process(frame, panel: panel, reading: reading, started: started)
    }

    /// Okunmuş telefon ekranından öğeleri kurar (testler doğrudan çağırır).
    func process(_ frame: CGImage, panel: PhonePanel.Panel, reading: Reading, started: Int) async {
        if reading.lines.contains(where: { Self.mapKeys.contains(MenuBlock.clean($0.text).lowercased()) }) {
            clear()
            return
        }
        // Sohbet: mesajlar balon olarak. Mesaj listesi çevrilmez. Başka uygulama (BuckMe bankası): satırları ayrı ayrı.
        // Başlığı ortalı uygulama ekranı ("Trip Details", Rydeme) sohbet sanılmasın: sohbette en az bir cümle olur.
        let threadMessages = PhoneThread.isThread(reading, panel: panel) ? PhoneThread.messages(in: reading, panel: panel) : []
        let chat = threadMessages.contains { PhoneThread.isSentence($0.text) }
        var messages = chat ? threadMessages
            : (PhoneThread.isMessageList(reading) ? [] : PhoneThread.appLines(in: reading, panel: panel))
        guard !messages.isEmpty else {
            if !items.isEmpty, now() - seen > 1200 { clear() }
            return
        }
        seen = now()
        onPhoneScreen?()
        // Kaydırınca mesajların yeri değişir: anahtar yeri de içerir (telefonun ekranına göre; el sallanınca değişmez).
        let readKey = messages.map { TextMatch.normalize($0.text) + "@\(Int(($0.box.top - panel.box.top) * 60))" }.joined(separator: "|")
        guard readKey != key else { return }
        // Sohbet kaydırıldı ya da mesajlar değişti: eski Türkçeler hemen kalkar (yenileri gelene kadar başka mesajların
        // balonlarının üstünde yanlış yazı durmasın).
        if let base = placed, !items.isEmpty {
            let positions = Dictionary(messages.map { (TextMatch.normalize($0.text), $0.box.top - panel.box.top) }, uniquingKeysWith: { a, _ in a })
            // Okuyucu bir mesajı arada kaçırabiliyor (6 → 5 → 6); bu kaydırma değildir.
            let keys = base.items.filter { !$0.backdrop }.map { TextMatch.normalize($0.source) }
            let common = keys.filter { positions[$0] != nil }
            let moved = common.contains { key in
                guard let top = positions[key], let anchor = anchors[key] else { return false }
                return abs(anchor - top) > 0.02
            }
            if moved || common.count * 2 < keys.count {
                items = []
                placed = nil
                key = ""
                onChange?([])
            }
        }
        guard readKey == pending else { pending = readKey; return }
        let memory = self.memory
        // Yarım okunan mesaj daha önce tam görüldüyse tam halinin çevirisi kullanılır.
        func remembered(_ text: String) -> String? {
            let key = TextMatch.normalize(text)
            guard key.split(separator: " ").count >= 5 else { return memory[key] }
            return memory.filter { $0.key == key || $0.key.hasPrefix(key + " ") || $0.key.hasSuffix(" " + key) }
                .max { $0.key.count < $1.key.count }?.value
        }
        // Ekranın dibinde cümlesi bitmemiş çok satırlı son mesaj, tamamı görünene kadar yarım çevrilmez.
        if chat, let last = messages.last, remembered(last.text) == nil,
           last.box.bottom > panel.box.bottom - 0.06, last.box.bottom - last.box.top > last.lineHeight * 1.8,
           !(last.text.trimmingCharacters(in: .whitespaces).last.map { ".!?…\")".contains($0) } ?? false) {
            messages.removeLast()
            guard !messages.isEmpty else { return }
        }
        // Ekranın üstünde baştan kesik (küçük harfle başlayan) ilk mesaj, tamamı görülmediyse yarım çevrilmez.
        if chat, let first = messages.first, messages.count > 1, remembered(first.text) == nil,
           first.text.first?.isLowercase == true {
            messages.removeFirst()
        }
        // Havuzun (elden geçmiş) çevirisi cihazın hafızasındakinden önce gelir.
        var texts = messages.map { (useGlossary ? PhoneThread.glossary($0.text) : nil) ?? known?($0.text) ?? remembered($0.text) ?? "" }
        let missing = messages.indices.filter { texts[$0].isEmpty }
        let sources = missing.map { messages[$0].text }
        if !sources.isEmpty { onUnknown?(sources) }
        // Sohbette her mesaj önceki (en çok üç) mesajla birlikte sorulur: kısaltma ve argo bağlamla doğru çevrilir.
        let contexts = missing.map { index in chat ? Array(messages[max(0, index - 3)..<index].map(\.text)) : [] }
        // Aynı anda en çok iki çeviri: cihaz üstü çeviri Neural Engine'i yazı okumayla paylaşır.
        let translate = self.translate
        let translated = await withTaskGroup(of: (Int, Translation).self) { group -> [Int: Translation] in
            var out: [Int: Translation] = [:]
            var next = 0
            func add() {
                guard next < sources.count else { return }
                let index = next, text = sources[index], context = contexts[index]
                next += 1
                group.addTask { (index, await translate(text, context)) }
            }
            add(); add()
            for await (index, result) in group {
                out[index] = result
                add()
            }
            return out
        }
        guard session == started, !Task.isCancelled else { return }
        var wrote = false
        for (slot, index) in missing.enumerated() {
            let clean = translated[slot]?.text.map(Self.withoutIcons)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !clean.isEmpty, translated[slot]?.remember == true {
                self.memory[TextMatch.normalize(messages[index].text)] = clean
                wrote = true
            }
            texts[index] = clean
        }
        if self.memory.count > 600 { self.memory.removeAll() }
        if wrote, let memoryFile, let data = try? JSONEncoder().encode(self.memory) { try? data.write(to: memoryFile, options: .atomic) }
        // Sohbet: telefonun yanında dikey mesajlaşma paneli. Uygulama (BuckMe): her yazının hemen altında sade Türkçe.
        let color = PhonePanel.liftedSampler(for: frame, panel: panel)
        var built = chat
            ? PhoneThread.sideBubbles(for: messages, translations: texts, panel: panel, chat: true,
                                      title: PhoneThread.titleText(reading, panel: panel), color: color) { text, width, line in
                let wrapped = ScreenHints.wrap(text, width: width, line: line)
                return (wrapped.count, wrapped.map(\.count).max() ?? 0)
            }
            : PhoneThread.appBubbles(for: messages, translations: texts, panel: panel, color: color)
        recent = (messages.map(\.text), now())
        anchors = Dictionary(messages.map { (TextMatch.normalize($0.text), $0.box.top - panel.box.top) }, uniquingKeysWith: { a, _ in a })
        // Kullanıcı isteği: panel telefonun yanında ayrı durur; telefon az oynadıysa yeni yerleşim eski telefon yerine göre
        // kurulur (panel yerinde kalır); telefon belirgin taşınınca panel de gider.
        var anchorPanel = panel.box
        if let old = placed {
            let dx = (panel.box.left + panel.box.right - old.panel.left - old.panel.right) / 2
            let dy = (panel.box.top + panel.box.bottom - old.panel.top - old.panel.bottom) / 2
            if abs(dx) < Self.steady, abs(dy) < Self.steady {
                built = PhoneThread.shifted(built, dx: -dx, dy: -dy)
                anchorPanel = old.panel
            }
            // Aynı mesaj yeniden okunduysa ve yeri az oynadıysa eski kutusu korunur (yazı boyu ve yeri zıplamasın).
            let current = PhoneThread.shifted(old.items, dx: shift.dx, dy: shift.dy)
            let sameScreen = !chat && current.count == built.count
                && zip(current, built).allSatisfy { $0.translation == $1.translation && abs($0.box.top - $1.box.top) < 0.06 }
            let reach = chat ? (0.012, 0.015) : (0.04, 0.06)
            built = sameScreen ? current : built.map { item in
                guard let same = current.first(where: { $0.source == item.source && $0.translation == item.translation }),
                      abs(same.box.left - item.box.left) < reach.0, abs(same.box.top - item.box.top) < reach.1 else { return item }
                return same
            }
        }
        placed = (anchorPanel, built)
        items = built
        shift = (0, 0)
        shiftSeen = nil
        key = readKey
        pending = ""
        let shown = built.filter { !$0.backdrop }
        onLog?("telefon: \(shown.count) yazı" + (shown.first.map { " (\(SubtitleLog.excerpt($0.source)) → \($0.translation))" } ?? "") + (chat ? "" : " · uygulama"))
        onChange?(built)
    }

    /// Türkçeler balonların üstündeyken telefon elde sallanır; yazıyı yeniden okumadan (pahalı) yalnız telefonun yeri
    /// sık sık bulunur ve örtüler onunla birlikte kaydırılır.
    private func track(_ frame: CGImage) {
        guard let base = placed, !items.isEmpty, trackTask == nil, now() - trackAt > trackIntervalMs else { return }
        trackAt = now()
        let started = session
        trackTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { PhonePanel.find(in: frame)?.box }.value
            guard let self, session == started else { return }
            trackTask = nil
            guard let found, let current = placed, current.panel == base.panel else { return }
            // Telefonun ortası ne kadar kaydı (kenar okuması bir iki nokta oynar; ortalama daha sakin).
            let dx = (found.left + found.right - base.panel.left - base.panel.right) / 2
            let dy = (found.top + found.bottom - base.panel.top - base.panel.bottom) / 2
            guard abs(dx - shift.dx) > 0.009 || abs(dy - shift.dy) > 0.012, abs(dx) < 0.08, abs(dy) < 0.08 else {
                shiftSeen = nil
                return
            }
            // Tek ölçümlük sıçrama gürültüdür; aynı yöndeki ikinci ölçümde kaydırılır (iki ölçümün ortalamasıyla).
            guard let seen = shiftSeen, abs(seen.dx - dx) < 0.008, abs(seen.dy - dy) < 0.011 else {
                shiftSeen = (dx, dy)
                return
            }
            shiftSeen = nil
            shift = ((seen.dx + dx) / 2, (seen.dy + dy) / 2)
            items = PhoneThread.shifted(base.items, dx: shift.dx, dy: shift.dy)
            onChange?(items)
        }
    }

    /// HTML varlıkları ("&amp;", "&#39;") düz yazıya çevrilir (Mac: AppModel.withoutEntities).
    public nonisolated static func withoutEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&apos;", with: "'")
    }

    /// Çeviriye karışan simgeler atılır, boşluklar sadeleşir (Mac: AppModel.withoutIcons).
    public nonisolated static func withoutIcons(_ text: String) -> String { ScreenHints.withoutIcons(withoutEntities(text)) }
}
