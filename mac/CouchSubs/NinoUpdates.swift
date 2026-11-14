// SPDX-License-Identifier: AGPL-3.0-only
// Nino: güncelleme denetimi. Açılışta GitHub'daki son sürüme bakılır; daha yenisi varsa ana ekranda bildirilir ve tek
// tıkla indirilir. (CouchSubs'ın Sparkle güncelleyicisi Nino'da kapalı; sürümler GitHub Releases'tan dağıtılır.)

import AppKit
import CouchSubsCore
import Foundation

@MainActor
final class NinoUpdates: ObservableObject {
    struct Release: Equatable {
        var version: String
        var page: URL
        var download: URL?
    }

    static let shared = NinoUpdates()
    static let latestURL = URL(string: "https://api.github.com/repos/yunusdemirbag/nino-game-translator/releases/latest")!

    /// Ayarlar › Güncellemeler'deki durum.
    enum CheckState: Equatable { case idle, checking, upToDate, failed }

    @Published private(set) var available: Release?
    @Published private(set) var state: CheckState = .idle
    @Published private(set) var lastChecked: Date?
    private var checked = Date.distantPast

    /// Kendiliğinden en çok altı saatte bir bakılır; `force` ile (Ayarlar'daki düğme) hemen. Ağ yoksa ana ekran sessiz kalır.
    func check(force: Bool = false) async {
        guard force || Date().timeIntervalSince(checked) > 6 * 3600 else { return }
        checked = Date()
        state = .checking
        defer { if state == .checking { state = .failed } }
        var request = URLRequest(url: Self.latestURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Nino-Mac", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return }
        lastChecked = Date()
        let assets = json["assets"] as? [[String: Any]] ?? []
        let download = assets.first { ($0["name"] as? String) == "Nino-Mac.zip" }?["browser_download_url"] as? String
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Self.isNewer(version, than: AppIdentity.version) else {
            available = nil
            state = .upToDate
            return
        }
        available = Release(version: version, page: page, download: download.flatMap(URL.init(string:)))
        state = .idle
    }

    func open() {
        guard let available else { return }
        NSWorkspace.shared.open(available.download ?? available.page)
    }

    /// Sürüm notları (GitHub'daki sayfa).
    func openNotes() {
        guard let available else { return }
        NSWorkspace.shared.open(available.page)
    }

    /// "0.1.10" > "0.1.9"; sayısal karşılaştırma.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
