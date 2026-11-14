// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Nino: her oyunun altyazısının ekranda nerede durduğunu öğrenir. Oyunlar altyazıyı farklı yüksekliklere koyar; sabit
/// bir kural ("ekranın %88'inin altı altyazı değildir") altyazısı en altta duran oyunlarda gerçek altyazıyı atlar.
/// Gösterilen her altyazının kutusu kaydedilir; yeterince örnek olunca o oyunun altyazı şeridi bilinir. Şeridin altında
/// başlayan yazılar (görev, öğretici, menü) altyazı sayılmaz.
public struct SubtitleLayout: Codable, Equatable, Sendable {
    /// Oyun başına son kutuların üst ve alt kenarları (0–1, üstten).
    public private(set) var samples: [String: [Sample]] = [:]

    public struct Sample: Codable, Equatable, Sendable {
        public var top: Double
        public var bottom: Double
    }

    /// Öğrenmek için gereken en az altyazı.
    public static let minimumSamples = 8
    /// Oyun başına tutulan en çok örnek (eskiler düşer; oyun güncellenip yeri değişirse uyum sağlanır).
    public static let maximumSamples = 60
    /// Öğrenene kadar kullanılan sınır: ekranın en alt şeridi (RDR2 gibi oyunların öğretici yazısı).
    public static let fallbackHudTop = 0.885

    public init() {}

    public mutating func record(_ box: TextBox, game: String) {
        guard box.bottom > box.top, box.top >= 0, box.bottom <= 1 else { return }
        var list = samples[game] ?? []
        list.append(Sample(top: box.top, bottom: box.bottom))
        if list.count > Self.maximumSamples { list.removeFirst(list.count - Self.maximumSamples) }
        samples[game] = list
    }

    /// Oyunun altyazı şeridi (üst, alt); yeterli örnek yoksa nil. Uç değerler (yanlış okunmuş tek tük satır) atılır.
    public func band(for game: String) -> (top: Double, bottom: Double)? {
        guard let list = samples[game], list.count >= Self.minimumSamples else { return nil }
        let tops = list.map(\.top).sorted(), bottoms = list.map(\.bottom).sorted()
        return (Self.quantile(tops, 0.1), Self.quantile(bottoms, 0.9))
    }

    /// Bu çizginin altında başlayan satır altyazı sayılmaz. Öğrenilmişse şeridin biraz altı; öğrenilmemişse eski sınır.
    /// Altyazısı ekranın en dibinde duran oyunda sınır kalkar (nil).
    public func hudTop(for game: String) -> Double? {
        guard let band = band(for: game), let list = samples[game] else { return Self.fallbackHudTop }
        // Şeridin altına bir satır yüksekliği pay: öğrenilen örnekler tek satırlıysa iki satırlık altyazının ikinci
        // satırı kesilmesin.
        let lineHeight = Self.quantile(list.map { $0.bottom - $0.top }.sorted(), 0.5)
        let line = band.bottom + max(0.012, lineHeight)
        return line >= 0.97 ? nil : max(line, band.top + 0.03)
    }

    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * q).rounded())))
        return sorted[index]
    }
}

/// Öğrenilenleri diskte saklar (Application Support/Nino/subtitle-layout.json).
public final class SubtitleLayoutStore: @unchecked Sendable {
    private let file: URL?
    private let lock = NSLock()
    private var layout: SubtitleLayout

    public init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(SubtitleLayout.self, from: data) {
            layout = saved
        } else {
            layout = SubtitleLayout()
        }
    }

    public var current: SubtitleLayout { lock.withLock { layout } }

    public func record(_ box: TextBox, game: String) {
        let snapshot: SubtitleLayout = lock.withLock {
            layout.record(box, game: game)
            return layout
        }
        guard let file, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
