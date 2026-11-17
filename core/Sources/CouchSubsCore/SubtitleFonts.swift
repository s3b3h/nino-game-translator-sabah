// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
#if canImport(CoreText)
import CoreText
#endif

/// Nino: altyazı yazı tiplerinin (TV sayfasındakiyle aynı OFL dosyaları, tv-webos/fonts) uygulama içindeki adları.
/// Mac ve iPhone bu dosyaları paketin içine "fonts" klasörü olarak koyar ve açılışta kaydeder.
public extension SubtitleFont {
    /// Seçilen yazı tipinin PostScript adı; `system` için nil (cihazın kendi yazı tipi).
    /// Barlow'da orta (medium) kalınlık yok; kalın olmayan her şey yarı kalın (SemiBold) olur.
    func postScriptName(bold: Bool) -> String? {
        switch self {
        case .system: nil
        case .modern: bold ? "Barlow-Bold" : "Barlow-SemiBold"
        case .condensed: bold ? "BarlowCondensed-Bold" : "BarlowCondensed-SemiBold"
        case .rounded: bold ? "Nunito-Bold" : "Nunito-SemiBold"
        }
    }

    /// TV sayfası Dar/Aksiyon yazıya biraz harf aralığı verir (0.01em); aynısı burada.
    var tracking: Double { self == .condensed ? 0.01 : 0 }
}

#if canImport(CoreText)
public enum SubtitleFontRegistry {
    /// Paketteki yazı tipi dosyaları (tv-webos/fonts ile aynı).
    public static let fileNames = ["Barlow-SemiBold.ttf", "Barlow-Bold.ttf", "BarlowCondensed-SemiBold.ttf",
                                   "BarlowCondensed-Bold.ttf", "Nunito-Variable.ttf"]

    private static let registered: Void = {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("fonts", isDirectory: true) else { return }
        register(folder: folder)
    }()

    /// Uygulama paketindeki "fonts" klasörünü bir kez kaydeder (yalnız bu uygulama için; sisteme kurulmaz).
    public static func registerBundledFonts() { _ = registered }

    /// Bir klasördeki altyazı yazı tiplerini kaydeder; zaten kayıtlı olanlar sessizce geçilir.
    public static func register(folder: URL) {
        for name in fileNames {
            let url = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
#endif
