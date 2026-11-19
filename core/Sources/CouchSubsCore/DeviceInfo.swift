// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "Cihaz bilgileri". Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-19.

import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Kullanıcının ne kullandığının kısa özeti: uygulama sürümü, cihaz modeli, işletim sistemi, TV ve konsol.
/// Ayarlar › Sistem sağlığı'nda gösterilir ve Sorun Bildir ile Nino'ya Sor bildirimlerine eklenir (sunucuda `device`
/// alanı); biri hata bildirdiğinde hangi cihazlarla denediği sorulmadan görülür.
/// Kişiyi tanıtan hiçbir şey içermez: cihazın adı ("Ali'nin MacBook'u"), seri numarası, IP adresi, hesap adı yoktur.
/// Windows: CouchSubs.Core/DeviceInfo.cs, Android: core/DeviceInfo.kt.
public enum DeviceInfo {
    /// Sunucunun sakladığı en çok uzunluk (nino-pool/src/reports.js ile aynı).
    public static let maxLength = 600

    public struct Row: Equatable, Identifiable, Sendable {
        /// Satırın sabit adı ("app", "device", "system", "tv", "console", "status"); çevrilmez, sunucuya bu gider.
        public var id: String
        public var value: String

        public init(_ id: String, _ value: String) {
            self.id = id
            self.value = value
        }
    }

    /// Cihazın model kodu: Mac'te "Mac16,1", iPhone'da "iPhone17,1" (simülatörde simüle edilen model).
    public static var model: String {
        #if os(macOS)
        return sysctl("hw.model") ?? "Mac"
        #else
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        return sysctl("hw.machine") ?? "iPhone"
        #endif
    }

    /// İşletim sistemi ve sürümü: "macOS 27.0", "iOS 27.0.1".
    public static var system: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = version.patchVersion == 0 ? "\(version.majorVersion).\(version.minorVersion)"
            : "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #if os(macOS)
        return "macOS \(number)"
        #elseif os(tvOS)
        return "tvOS \(number)"
        #else
        return "iOS \(number)"
        #endif
    }

    /// Satırlar, sırayla. Boş ya da bilinmeyen değer satır olmaz.
    /// - Parameters:
    ///   - app: Uygulama sürümü ("3.4.0 (19)").
    ///   - tv: TV'nin markası, modeli ve TV uygulamasının sürümü ("Samsung QE55Q70C · TV uygulaması 3.4.0"); yoksa nil.
    ///   - console: Konsol ve bağlantı yolu ("PS5 · Remote Play", "Xbox Series X"); bilinmiyorsa nil.
    ///   - status: Şu anki durum ya da son hata ("PS5: bağlanıyor", "0x80108b12"); yoksa nil.
    public static func rows(app: String, tv: String? = nil, console: String? = nil, status: String? = nil,
                            model: String = DeviceInfo.model, system: String = DeviceInfo.system) -> [Row] {
        [Row("app", app), Row("device", model), Row("system", system), Row("tv", tv ?? ""), Row("console", console ?? ""),
         Row("status", status ?? "")]
            .map { Row($0.id, clean($0.value)) }
            .filter { !$0.value.isEmpty }
    }

    /// Sunucuya giden tek satır: "app: 3.4.0 (19) | device: Mac16,1 | system: macOS 27.0 | tv: …".
    public static func summary(_ rows: [Row]) -> String {
        String(rows.map { "\($0.id): \($0.value)" }.joined(separator: " | ").prefix(maxLength))
    }

    /// Satır sonları ve ayırıcı çizgi değerin içinde kalmaz (özet tek satırdır).
    static func clean(_ value: String) -> String {
        value.components(separatedBy: .newlines).joined(separator: " ").replacingOccurrences(of: "|", with: "/")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func sysctl(_ name: String) -> String? {
        #if canImport(Darwin)
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(cString: buffer).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
        #else
        return nil
        #endif
    }
}
