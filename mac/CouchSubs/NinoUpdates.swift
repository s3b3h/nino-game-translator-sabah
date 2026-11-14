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

    @Published private(set) var available: Release?
    private var checked = Date.distantPast

    /// En çok altı saatte bir bakılır; ağ yoksa sessizce geçilir.
    func check() async {
        guard Date().timeIntervalSince(checked) > 6 * 3600 else { return }
        checked = Date()
        var request = URLRequest(url: Self.latestURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Nino-Mac", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let download = assets.first { ($0["name"] as? String) == "Nino-Mac.zip" }?["browser_download_url"] as? String
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Self.isNewer(version, than: AppIdentity.version) else { return }
        available = Release(version: version, page: page, download: download.flatMap(URL.init(string:)))
    }

    func open() {
        guard let available else { return }
        NSWorkspace.shared.open(available.download ?? available.page)
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
