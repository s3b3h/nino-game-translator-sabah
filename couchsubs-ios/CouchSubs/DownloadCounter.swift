// SPDX-License-Identifier: AGPL-3.0-only
// Nino: ana ekrandaki TV'nin sağ üst köşesinde görünen "Toplam indirme" sayısı (Mac: mac/CouchSubs/DownloadCounter.swift
// ile aynı; iPhone'a kopyalandı).

import CouchSubsCore
import Foundation

/// Toplam indirme sayısı (GitHub'daki uygulama dosyalarının indirme toplamı). Sunucunun `GET /v1/config` cevabındaki
/// `downloads` alanından okunur; sunucu onu yarım saatte bir GitHub'dan yeniler. İstek kullanıcıya ait hiçbir bilgi
/// taşımaz. İnternet yoksa ya da sunucu sayıyı veremiyorsa son bilinen sayı gösterilmeye devam eder (kalıcı saklanır);
/// hiç alınamadıysa sayaç görünmez. Sayı olduğu gibi gösterilir, üstüne ekleme yapılmaz.
@MainActor
final class DownloadCounter: ObservableObject {
    static let shared = DownloadCounter()
    static let defaultsKey = "ninoDownloadTotal"
    /// Sunucuya en çok bu aralıkla sorulur (sn).
    static let interval: TimeInterval = 600

    @Published private(set) var total: Int?

    private let defaults: UserDefaults
    private let fetch: @Sendable (URL) async -> Data?
    private let endpoint: URL?
    private var lastAsked = Date.distantPast

    init(defaults: UserDefaults = .standard, endpoint: URL? = NinoPool.liveEndpoint,
         fetch: @escaping @Sendable (URL) async -> Data? = DownloadCounter.get) {
        self.defaults = defaults
        self.endpoint = endpoint
        self.fetch = fetch
        let saved = defaults.integer(forKey: Self.defaultsKey)
        total = saved > 0 ? saved : nil
    }

    /// Sayıyı yeniler (en çok `interval`de bir). Alınamazsa eldeki sayı kalır.
    func refresh(now: Date = Date()) async {
        guard let endpoint, now.timeIntervalSince(lastAsked) >= Self.interval else { return }
        lastAsked = now
        guard let data = await fetch(endpoint.appendingPathComponent("v1/config")), let value = Self.parse(data) else { return }
        total = value
        defaults.set(value, forKey: Self.defaultsKey)
    }

    /// `/v1/config` cevabındaki toplam indirme; alan yoksa ya da sayı geçersizse nil.
    nonisolated static func parse(_ data: Data) -> Int? {
        struct Reply: Decodable { var downloads: Int? }
        guard let value = (try? JSONDecoder().decode(Reply.self, from: data))?.downloads, value > 0 else { return nil }
        return value
    }

    nonisolated static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
