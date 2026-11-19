// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import SwiftUI

/// Salon sahnesindeki TV ekranının arka planı. Oyun tanınınca oyuna özel, buzlu (bulanık) bir fon gösterilir; Türkçe
/// satır bunun önünde durur. GTA 6'da Nino'nun kendi çizimi (gün batımı renkleri) kullanılır: oyunun logosu Rockstar'ın
/// tescilli görseli olduğu için uygulamayla dağıtılmaz. Kullanıcı kendi görselini koyarsa (bkz. `GameCovers.directory`)
/// o kullanılır ve bu Mac'ten çıkmaz.
struct GameBackdrop: View {
    let gameID: String?
    let poolFirst: Bool

    var body: some View {
        if let image = GameCovers.image(for: gameID, poolFirst: poolFirst) {
            GeometryReader { geo in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: 14, opaque: true)
                    .overlay(Color.black.opacity(0.36))
            }
        } else if poolFirst {
            SunsetBackdrop()
        } else {
            LinearGradient(colors: [Color(red: 0.09, green: 0.12, blue: 0.24), Color(red: 0.15, green: 0.09, blue: 0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// GTA 6 için Nino'nun kendi fonu: laciverd-mor-pembe gün batımı geçişi. Yalnız bir geçiştir: güneş, bulanıklık ya da
/// ayrı katman yoktur (ilk sürümde ortadaki sarı güneş `blur(opaque:)` yüzünden kareli bir blok olarak çıkıyordu;
/// kullanıcı ortada sarı bir şey istemiyor, 19 Kasım 2026).
private struct SunsetBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Color(red: 0.10, green: 0.08, blue: 0.34), location: 0),
                .init(color: Color(red: 0.46, green: 0.16, blue: 0.62), location: 0.40),
                .init(color: Color(red: 0.93, green: 0.29, blue: 0.60), location: 0.74),
                .init(color: Color(red: 1.00, green: 0.55, blue: 0.48), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            Color.black.opacity(0.28)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Kullanıcının oyun için koyduğu arka plan görseli: `~/Library/Application Support/Nino/Covers/<oyun-kimliği>.png`
/// (jpg, jpeg, heic, webp de olur). GTA 6 için `gta-6` adı da kabul edilir. Görsel yalnız bu Mac'te kalır.
enum GameCovers {
    static let directory = AppFolder.support.appendingPathComponent("Covers", isDirectory: true)
    private static let extensions = ["png", "jpg", "jpeg", "heic", "webp"]
    private static var cache: [String: (modified: Date, image: NSImage)] = [:]

    static func image(for gameID: String?, poolFirst: Bool) -> NSImage? {
        var names: [String] = []
        if let gameID, !gameID.isEmpty { names.append(gameID) }
        if poolFirst { names.append("gta-6") }
        for name in names {
            for ext in extensions {
                let url = directory.appendingPathComponent(name + "." + ext)
                guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
                if let cached = cache[url.path], cached.modified == modified { return cached.image }
                guard let image = NSImage(contentsOf: url) else { continue }
                cache[url.path] = (modified, image)
                return image
            }
        }
        return nil
    }
}
