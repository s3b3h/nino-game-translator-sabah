// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Ek alanların çevirisini TV'ye ileten taraf (gerçekte `SubtitleServer`).
public protocol RegionSending: AnyObject {
    /// `text` boşsa alanın kutusu kalkar.
    func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?)
    func clearRegions()
}

extension SubtitleServer: RegionSending {}

/// Ek alanları (görev yazısı, telefon mesajı, bildirim) ana altyazıdan ayrı ve seyrek okur, çevirip TV'ye kendi
/// yerleriyle gönderir (Windows: CouchSubs.Core/RegionWatcher.cs ile aynı kurallar).
///
/// - Ana okuma hattını beklemez, onu da bekletmez: `offer` hemen döner; tur ayrı bir görevde ve düşük öncelikle sürer.
/// - En çok `intervalMs`'te bir tur atılır; önceki tur (okuma ya da çeviri) bitmediyse kare atlanır.
/// - Bölge izi (`RegionCropper.signature`) değişmeyen alan yeniden okunmaz.
/// - Okunan yazı ancak kararlıysa çevrilir: iz bir tur değişmeden kaldıysa ya da iki okuma aynı yazıyı verdiyse (arkası
///   kıpırdayan köşe yazıları). Böylece belirirken yarım okunan yazı çevrilmez.
/// - Yazı değişmedikçe yeniden çevrilmez; boşalan alanın kutusu kalkar.
/// - Paket eşleşmesi ve çeviri motoru ana altyazıyla aynıdır; ama ek alan satırları ortak havuza önerilmez (arayüz
///   yazıları havuzu kirletmesin).
@MainActor
public final class RegionWatcher {
    /// İki tur arasındaki en kısa süre.
    public static let defaultIntervalMs = 1000

    private struct State {
        var signature: [UInt8]?
        /// Son okumanın sadeleştirilmiş yazısı; bir sonraki okuma aynıysa yazı kararlıdır.
        var lastRead: String?
        /// Okunmuş ama henüz kararlı sayılmamış yazı.
        var candidate: Candidate?
        /// TV'de şu an çevirisi duran yazı (sadeleştirilmiş); boşsa kutu yok.
        var shown = ""
        /// Son gönderilen çeviri, aynı yazı yeni bir konuma taşındığında yeniden kullanılır.
        var renderedKey: String?
        var renderedText: String?
        var renderedBox: TextBox?
        var renderedLineHeight: Double?
    }

    struct Candidate {
        var paragraphs: [String]
        var box: TextBox?
        var lineHeight: Double?
        var key: String
    }

    private let reader: TextReader
    private let translator: TextTranslator
    private let server: RegionSending
    private let intervalMs: Int
    private let now: () -> Int
    private var states: [String: State] = [:]
    private var lastPass: Int?
    private var running: Task<Void, Never>?
    private var session = 0

    /// Oyun paketi: satırın hazır Türkçesi (ana altyazıyla aynı arama).
    public var packLookup: ((String) -> PackMatch?)?
    public var onLog: ((String) -> Void)?
    /// Her okumanın süresi (ms; ölçüm için).
    public var onReadMs: ((Int) -> Void)?
    /// Tamamlanan tur sayısı ve okuma sayısı (ölçüm ve testler için).
    public private(set) var passes = 0
    public private(set) var reads = 0

    public init(reader: TextReader, translator: TextTranslator, server: RegionSending,
                intervalMs: Int = RegionWatcher.defaultIntervalMs, clock: @escaping () -> Int = SubtitleStabilizer.uptimeMs) {
        self.reader = reader
        self.translator = translator
        self.server = server
        self.intervalMs = intervalMs
        self.now = clock
    }

    /// Bir tur sürüyor mu.
    public var isBusy: Bool { running != nil }

    /// Her karede çağrılır; tur zamanı geldiyse ve önceki tur bittiyse turu arka planda başlatır, hemen döner.
    public func offer(_ frame: CGImage, areas: [ExtraArea]) {
        guard running == nil else { return }
        guard !areas.isEmpty || states.values.contains(where: { !$0.shown.isEmpty }) else { return }
        let time = now()
        if let lastPass, time - lastPass < intervalMs { return }
        lastPass = time
        let session = self.session
        running = Task { [weak self] in
            await self?.pass(frame, areas: areas)
            // Bu arada sıfırlandıysa yeni oturumun turuna dokunulmaz.
            if self?.session == session { self?.running = nil }
        }
    }

    /// Bir tur: kaldırılan alanların kutusu kalkar, her açık alan gerekirse okunur ve kararlı yazısı çevrilir.
    /// Testler doğrudan çağırır.
    public func pass(_ frame: CGImage, areas: [ExtraArea]) async {
        let started = session
        passes += 1
        let ids = Set(areas.map(\.id))
        for (id, state) in states where !ids.contains(id) {
            if !state.shown.isEmpty { server.sendRegion(id: id, text: "", box: nil, lineHeight: nil) }
            states[id] = nil
        }
        for area in areas {
            await visit(area, frame: frame)
            guard session == started else { return }
        }
    }

    private func visit(_ area: ExtraArea, frame: CGImage) async {
        let region = area.region
        let (crop, signature) = await Task.detached(priority: .utility) {
            let crop = RegionCropper.crop(frame, to: region)
            return (crop, RegionCropper.signature(of: crop))
        }.value
        var state = states[area.id] ?? State()
        let changed = state.signature.map {
            ReadScheduler.changed($0, signature, threshold: ReadScheduler.defaultChangeThreshold)
        } ?? true
        state.signature = signature
        guard changed else {
            // İz bir tur değişmedi: okunan yazı kararlıdır.
            if let candidate = state.candidate {
                state.candidate = nil
                states[area.id] = state
                await commit(candidate, area: area)
            } else {
                states[area.id] = state
            }
            return
        }
        let started = now()
        let session = self.session
        let reader = self.reader
        let reading = await Task.detached(priority: .utility) { try? reader.readLines(crop, deep: false) }.value
        guard session == self.session else { return }
        guard let reading else {
            // OCR hatası boş alan değildir. Eski kutuyu koru; aynı kareyi sonraki normal turda yeniden oku.
            // Başarısız kare, önceki adayın kararlılığını da doğrulayamaz.
            state.signature = nil
            state.lastRead = nil
            state.candidate = nil
            states[area.id] = state
            return
        }
        reads += 1
        onReadMs?(now() - started)
        let candidate = Self.candidate(reading, in: region)
        if state.lastRead == candidate.key {
            state.candidate = nil
            states[area.id] = state
            await commit(candidate, area: area)
        } else {
            state.lastRead = candidate.key
            state.candidate = candidate
            states[area.id] = state
        }
    }

    /// Okumadan çevrilecek parçalar: kumanda ipuçları, yazı tanıma çöpleri ve harfsiz göstergeler ("23m", "9") atılır;
    /// satırlar yukarıdan aşağı parçalara toplanır (başlık, cümle, madde).
    static func candidate(_ reading: Reading, in region: CropRegion) -> Candidate {
        let lines = reading.withoutButtonPrompts().withoutOcrNoise().lines
            .filter { ScreenTranslation.isWords($0.text) }
            .sorted { ($0.box?.top ?? 0) < ($1.box?.top ?? 0) }
        let paragraphs = ScreenTranslation.paragraphs(lines)
        let place = TextBox(left: region.left, top: region.top, right: region.right, bottom: region.bottom)
        let boxes = lines.compactMap(\.box)
        let box = boxes.dropFirst().reduce(boxes.first) { $0?.union($1) }?.placed(in: place)
        let heights = boxes.map { ($0.bottom - $0.top) * (region.bottom - region.top) }.sorted()
        let lineHeight = heights.isEmpty ? nil : heights[heights.count / 2]
        let key = TextMatch.normalize(paragraphs.joined(separator: " "))
        return Candidate(paragraphs: paragraphs, box: box, lineHeight: lineHeight, key: key)
    }

    /// Kararlı yazı: öncekinden farklıysa çevrilip gönderilir, boşsa kutu kalkar.
    private func commit(_ candidate: Candidate, area: ExtraArea) async {
        guard var state = states[area.id] else { return }
        if state.shown == candidate.key {
            guard state.renderedKey == candidate.key,
                  let renderedText = state.renderedText, !renderedText.isEmpty else { return }
            guard state.renderedBox != candidate.box || state.renderedLineHeight != candidate.lineHeight else { return }
            server.sendRegion(id: area.id, text: renderedText, box: candidate.box, lineHeight: candidate.lineHeight)
            state.renderedBox = candidate.box
            state.renderedLineHeight = candidate.lineHeight
            states[area.id] = state
            return
        }
        let previousShown = state.shown
        states[area.id]?.shown = candidate.key
        guard !candidate.key.isEmpty else {
            server.sendRegion(id: area.id, text: "", box: nil, lineHeight: nil)
            states[area.id]?.renderedKey = candidate.key
            states[area.id]?.renderedText = ""
            states[area.id]?.renderedBox = nil
            states[area.id]?.renderedLineHeight = nil
            onLog?("ek alan \(area.name): boşaldı")
            return
        }
        let session = self.session
        let translated: [String]
        var fromPack = 0
        do {
            translated = try await translate(candidate.paragraphs, packHits: &fromPack)
        } catch {
            guard session == self.session else { return }
            if states[area.id]?.shown == candidate.key {
                states[area.id]?.shown = previousShown
                states[area.id]?.candidate = candidate
            }
            onLog?("ek alan \(area.name): \(SubtitleLog.excerpt(candidate.paragraphs.joined(separator: " "))) çevrilemedi (\(error))")
            return
        }
        guard session == self.session, states[area.id]?.shown == candidate.key else { return }
        let text = zip(candidate.paragraphs, translated).map { source, translation in
            let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? source : trimmed
        }
        // Çevirisi aslıyla aynı (ad, sayı, zaten hedef dilde): kutu gösterilmez.
        let same = zip(candidate.paragraphs, text).allSatisfy {
            TextMatch.isSimilar(TextMatch.normalize($0), TextMatch.normalize($1), threshold: 0.90)
        }
        if same {
            server.sendRegion(id: area.id, text: "", box: nil, lineHeight: nil)
            states[area.id]?.renderedKey = candidate.key
            states[area.id]?.renderedText = ""
            states[area.id]?.renderedBox = nil
            states[area.id]?.renderedLineHeight = nil
            return
        }
        let joined = text.joined(separator: "\n")
        let origin = fromPack == candidate.paragraphs.count ? "paket" : fromPack > 0 ? "paket+motor" : "motor"
        onLog?("ek alan \(area.name): \(SubtitleLog.excerpt(candidate.paragraphs.joined(separator: " "))) → \(origin)")
        server.sendRegion(id: area.id, text: joined, box: candidate.box, lineHeight: candidate.lineHeight)
        states[area.id]?.renderedKey = candidate.key
        states[area.id]?.renderedText = joined
        states[area.id]?.renderedBox = candidate.box
        states[area.id]?.renderedLineHeight = candidate.lineHeight
    }

    /// Parçalar önce pakette aranır; kalanlar çeviri motoruna gider (yapay zekâda tek istekte).
    private func translate(_ paragraphs: [String], packHits: inout Int) async throws -> [String] {
        var result = paragraphs.map { packLookup?($0)?.text }
        packHits = result.compactMap { $0 }.count
        let missing = result.indices.filter { result[$0] == nil }
        if !missing.isEmpty {
            let texts = missing.map { paragraphs[$0] }
            let translations = translator.translatesTogether ? try await translator.translateAll(texts)
                : try await sequential(texts)
            for (index, translation) in zip(missing, translations) { result[index] = translation }
        }
        return zip(paragraphs, result).map { $1 ?? $0 }
    }

    private func sequential(_ texts: [String]) async throws -> [String] {
        var result: [String] = []
        for text in texts { result.append(try await translator.translate(text)) }
        return result
    }

    /// Çeviri durdu ya da hat yeniden kuruldu: süren tur bırakılır, TV'deki ek alan kutuları kalkar.
    public func reset() {
        session += 1
        running?.cancel()
        running = nil
        lastPass = nil
        let anyShown = states.values.contains { !$0.shown.isEmpty }
        states.removeAll()
        if anyShown { server.clearRegions() }
    }
}
