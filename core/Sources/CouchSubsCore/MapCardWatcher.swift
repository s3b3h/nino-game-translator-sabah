// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Nino: haritada seçili görevin kartı ("BUY FLOWERS / Lucia will appreciate this / Have some flowers delivered…")
/// çevrilir ve kartın hemen altına (yer yoksa üstüne) oyunun kartı gibi yazılır; menünün kalanı çevrilmez.
///
/// Kurallar Mac'teki `AppModel.showMapCard` / `placeMapCard` ve Windows'taki `MapCardWatcher` ile aynıdır. Kart, menü
/// okumasında (`ScreenHints`) bulunur ve `show` ile buraya gelir; harita kapanınca `clear` çağrılır.
@MainActor
public final class MapCardWatcher {
    private let translate: @Sendable (String) async -> String?

    /// Kart başlığı bu dilin büyük harfiyle yazılır ("İ").
    public var targetLanguage = "tr"
    /// Harita hâlâ açık mı: çeviri sürerken kapandıysa kart gösterilmez (yeniden açılınca hafızadan hemen gelir).
    public var isMapOpen: (() -> Bool)?
    /// Gösterilecek öğeler değişti (boşsa kart kalkar).
    public var onChange: (([ScreenTranslation.Item]) -> Void)?
    public var onLog: ((String) -> Void)?

    public private(set) var items: [ScreenTranslation.Item] = []
    private var key = ""
    private var task: Task<Void, Never>?
    /// Çeviri sürerken seçilen yeni kart; süren çeviri bitince o çevrilir.
    private var waiting: (card: MapCard.Found, frame: CGImage?)?
    /// Bu oturumda çevrilmiş kartlar (anahtar → satırlar): haritada aynı yere dönülünce Türkçesi hemen gelir.
    private var memory: [String: [String]] = [:]
    /// Ekrandaki Türkçenin ait olduğu kartın başlığı, yeri ve tam metni.
    private var shown: (title: String, top: Double) = ("", -1)
    private var shownText = ""
    private var session = 0

    /// - Parameter translate: parçayı çevirir (sıra çağırana ait: havuz eşleşmesi, havuz, seçili çevirmen); olmazsa nil.
    public init(translate: @escaping @Sendable (String) async -> String?) {
        self.translate = translate
    }

    /// Çeviri sürüyor mu.
    public var isBusy: Bool { task != nil }

    /// Süren çevirinin bitmesini bekler (testler için).
    public func waitUntilIdle() async {
        while let task { await task.value }
    }

    /// Harita kapandı ya da kart görünmüyor: Türkçesi kalkar.
    public func clear() {
        key = ""
        waiting = nil
        guard !items.isEmpty else { return }
        items = []
        onChange?([])
    }

    /// Oturum bitti ya da dil değişti: süren çeviri bırakılır, hafıza silinir.
    public func reset() {
        session += 1
        task?.cancel()
        task = nil
        memory = [:]
        shown = ("", -1)
        shownText = ""
        clear()
    }

    /// Menü okumasında bulunan kart; `frame` kartın çerçevesini bulmak için.
    public func show(_ card: MapCard.Found, frame: CGImage?) {
        // PS5'in kendi bildirimi ("…, Uzaktan Oynama'yı kullanarak bağlandı.") zaten Türkçe; kart değildir.
        let all = ([card.title] + card.sentences).joined(separator: " ")
        if all.contains(where: { "ğışĞİŞ".contains($0) }) || card.sentences.isEmpty { return }
        // PS5'in sağ üstteki bildirimi ve ekranın en üstündeki sekme şeridi görev kartı değildir.
        if card.title.isEmpty, card.box.left > 0.6, card.box.top < 0.32 { return }
        if card.box.top < 0.1 { return }
        let fullText = TextMatch.normalize(all)
        // Aynı kartın yarım okuması (alttaki satır okunamadı) ekrandaki tam okumanın yerine geçmez.
        if !card.title.isEmpty, TextMatch.normalize(card.title) == shown.title, shownText.hasPrefix(fullText), shownText != fullText {
            return
        }
        let cardKey = fullText + "@\(Int(card.box.top * 50))"
        guard cardKey != key else { return }
        key = cardKey
        // İmleç başka yere geçti: eski kartın Türkçesi yeni kartın altında kalmasın. Aynı kart (aynı başlık, aynı yer)
        // biraz farklı okunduysa ("0.26 ml" / "0.26 mi") eski Türkçe yenisi gelene kadar kalır.
        let sameCard = !card.title.isEmpty && TextMatch.normalize(card.title) == shown.title && abs(card.box.top - shown.top) < 0.04
        if !items.isEmpty, !sameCard { items = []; onChange?([]) }
        if let lines = memory[cardKey] { place(card, lines: lines, frame: frame); return }
        // Çeviri sürüyorsa yeni kart beklemeye alınır (en son seçilen); süren bitince o çevrilir.
        guard task == nil else { waiting = (card, frame); return }
        waiting = nil
        let translate = self.translate
        let locale = Locale(identifier: targetLanguage)
        let started = session
        task = Task { [weak self] in
            func piece(_ text: String) async -> String {
                PhoneWatcher.withoutIcons(await translate(text) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var lines: [String] = []
            if !card.title.isEmpty {
                let title = await piece(card.title.capitalized)
                if !title.isEmpty { lines.append(title.uppercased(with: locale)) }
            }
            for sentence in card.sentences {
                let text = await piece(sentence)
                // Satırlara bölünmez (TV kutunun genişliğine göre böler); terim düzeltmesi bütün cümlede yapılır.
                if !text.isEmpty { lines.append(Self.withMapTerms(PhoneWatcher.withoutEntities(text))) }
            }
            guard let self, session == started else { return }
            task = nil
            if !lines.isEmpty { memory[cardKey] = lines }
            if memory.count > 200 { memory.removeAll() }
            if let next = waiting {
                // Çeviri sürerken imleç başka karta geçti: bu sonuç gösterilmez, en son kart çevrilir.
                waiting = nil
                key = ""
                show(next.card, frame: next.frame)
                return
            }
            guard key == cardKey, !lines.isEmpty else { return }
            guard isMapOpen?() ?? true else { key = ""; return }
            place(card, lines: lines, frame: frame)
        }
    }

    private func place(_ card: MapCard.Found, lines: [String], frame: CGImage?) {
        let box = frame.flatMap { MapCard.frame(around: card.box, in: $0) }
        let item = Self.placement(card, lines: lines, frame: box)
        items = [item]
        shown = (TextMatch.normalize(card.title), card.box.top)
        shownText = TextMatch.normalize(([card.title] + card.sentences).joined(separator: " "))
        onLog?("harita kartı: \(SubtitleLog.excerpt(item.source)) → \(item.translation.replacingOccurrences(of: "\n", with: " / "))")
        onChange?(items)
    }

    /// Kartın Türkçesi oyunun kartı gibi; kartın çerçevesiyle aynı sol kenarda, hemen altında; yer yoksa üstünde; o da
    /// yetmezse yazı küçülür. Kutu kart kadar değil yazı kadar geniştir (çerçeve yalnız sınırdır).
    nonisolated static func placement(_ card: MapCard.Found, lines translated: [String], frame frameBox: TextBox?) -> ScreenTranslation.Item {
        var lines = translated.map(PhoneWatcher.withoutEntities).map(withMapTerms)
        if !card.title.isEmpty, !lines.isEmpty, isPlaceName(card.title, description: card.sentences.joined(separator: " ")) {
            lines[0] = card.title
        }
        var line = min(max(card.lineHeight, 0.02), 0.032) * 0.85
        let frame = frameBox
            ?? TextBox(left: card.box.left - 0.015, top: card.box.top - 0.02, right: card.box.right + 0.015, bottom: card.box.bottom + 0.02)
        // Dar yazı tipi: bir harf satır yüksekliğinin yaklaşık %42'si.
        let charWidth = line * 0.42 * 9 / 16
        let longest = Double(lines.map(\.count).max() ?? 10)
        let width = min(frame.right - frame.left, longest * charWidth + 0.035)
        let rows = lines.enumerated().map { index, text in
            index == 0 ? 1 : max(1, Int((Double(text.count) * charWidth / (width - 0.03)).rounded(.up)))
        }.reduce(0, +)
        var height = line * Double(rows) * 1.32 + 0.022
        let below = 0.97 - (frame.bottom + 0.012), above = frame.top - 0.012 - 0.02
        var top = frame.bottom + 0.012
        if height > below {
            if height <= above || above > below {
                if height > above { line *= (above - 0.022) / (height - 0.022); height = above }
                top = frame.top - 0.012 - height
            } else {
                line *= (below - 0.022) / (height - 0.022); height = below
            }
        }
        let left = max(frame.left, card.box.left - 0.014)
        var item = ScreenTranslation.Item(source: ([card.title] + card.sentences).joined(separator: " "),
                                          translation: lines.joined(separator: "\n"),
                                          box: TextBox(left: left, top: top, right: left + width, bottom: top + height),
                                          lineHeight: line)
        item.card = true
        return item
    }

    /// Oyunun sık geçen terimlerinin yanlış çevirileri düzeltilir ("marked bills" → işaretli banknot, "lockup" → depo).
    public nonisolated static func withMapTerms(_ text: String) -> String {
        let fixes: [(String, String)] = [
            ("KAPALI TUTULMASI", "DEPOSU"), ("Kapalı Tutulması", "Deposu"), ("kapalı tutulması", "deposu"),
            ("işaretli faturaların", "işaretli banknotların"), ("işaretli faturalar", "işaretli banknotlar"),
            ("işaretli fatura", "işaretli banknot"), ("narkotik", "uyuşturucu"), ("NARKOTİK", "UYUŞTURUCU"),
            ("trafik ışığı papağan balığı", "stoplight papağan balığı"), ("kırmızı ışık papağan balığı", "stoplight papağan balığı"),
        ]
        return fixes.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// Kartın başlığı bir dükkân ya da mekân adıysa ("RIDEOUT CUSTOMS", "ONE-EYED WILLIE'S AUTO SHOP") çevrilmez.
    public nonisolated static func isPlaceName(_ title: String, description: String = "") -> Bool {
        // Açıklama bir işletmeyi anlatıyorsa ("Ammu-Nation distributor…", "Mod shop…", "dive bar…") başlık onun adıdır.
        let business = ["distributor", "shop", "store", "dive bar", " bar", "restaurant", "dealer", "club", "diner", "garage",
                        "convenience", "wholesaler", "boutique", "salon", "motel", "hotel", "bodega"]
        let about = description.lowercased()
        if business.contains(where: { about.contains($0) }) { return true }
        let words = title.uppercased().split(separator: " ").map(String.init)
        let places: Set<String> = ["CUSTOMS", "AUTO", "SHOP", "BAR", "CLUB", "MOTORS", "GARAGE", "CARE", "SPEEDWAY", "DINER",
                                   "CAFE", "GRILL", "MOTEL", "HOTEL", "STORE", "MART", "LOUNGE", "SALOON", "TACKLE", "ANCHOR",
                                   "MARINA", "AMMU-NATION", "BARBER", "TATTOO", "PAWN"]
        // "JASON'S MAILBOX", "DONNIE'S TRAILER" çevrilir; yalnız işletme adları kalır.
        return words.contains(where: places.contains) || (title.uppercased().hasPrefix("THE ") && words.count <= 4)
    }
}
