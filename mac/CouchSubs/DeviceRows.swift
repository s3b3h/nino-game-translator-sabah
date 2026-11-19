// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "Cihaz bilgileri". Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-19.

import CouchSubsCore
import Foundation

extension AppModel {
    /// Ayarlar › Sistem sağlığı'ndaki "Cihaz bilgileri" ve bildirimlere eklenen özet. Değerler destek içindir; ekran
    /// dili değişse de aynı kalır. TV'nin kullanıcının verdiği adı ("Salon", "Ali'nin TV'si") kişisel olabildiği için
    /// yazılmaz; marka ve (biliniyorsa) model yazılır.
    var deviceRows: [DeviceInfo.Row] {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let app = AppIdentity.version + (build.map { " (\($0))" } ?? "")
        return DeviceInfo.rows(app: app, tv: deviceTV, console: deviceConsole, status: deviceStatus)
    }

    var deviceSummary: String { DeviceInfo.summary(deviceRows) }

    private var deviceTV: String? {
        guard let tv else { return nil }
        var parts: [String]
        switch tv.brand {
        case .lg: parts = ["LG webOS"]
        case .samsung: parts = ["Samsung Tizen"]
        case .androidTV: parts = ["Android TV"]
        }
        if tv.brand == .samsung, let year = samsungModelYear { parts.append("\(year) model") }
        switch tvApp {
        case .upToDate(let version): parts.append("TV uygulaması \(version)")
        case .unknown: break
        case .working: parts.append("TV uygulaması kuruluyor")
        case .devModeOff: parts.append("geliştirici modu kapalı")
        case .needsPassphrase: parts.append("parola bekleniyor")
        case .failed(let error, let reason): parts.append("kurulum hatası \(error)" + (reason.map { " (\($0))" } ?? ""))
        case .signIn: parts.append("Samsung girişi bekleniyor")
        case .approveOnTV: parts.append("TV'de onay bekleniyor")
        case .hostPcMismatch: parts.append("Host PC IP uyuşmuyor")
        }
        parts.append(tvClients > 0 ? "bağlı" : "bağlı değil")
        return parts.joined(separator: " · ")
    }

    private var deviceConsole: String {
        let console = settings.gameConsole == .xbox ? "Xbox" : "PS5"
        switch settings.videoSource {
        case .ps5: return "\(console) · Remote Play (Nino bağlanıyor)"
        case .window: return "\(console) · oyun penceresi"
        case .card: return "\(console) · yakalama kartı"
        }
    }

    private var deviceStatus: String {
        let translation = isRunning ? "çeviri açık" : "çeviri kapalı"
        guard settings.videoSource == .ps5 else { return translation }
        return "\(translation), PS5: \(sessionState)"
    }
}
