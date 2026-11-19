// SPDX-License-Identifier: AGPL-3.0-only
// Nino: güncelleme denetimi. Açılışta GitHub'daki son sürüme bakılır; daha yenisi varsa ana ekranda bildirilir.
// GitHub sürümünde (App Store dışı) asıl işi Sparkle yapar: yeni sürüm arka planda iner ve uygulama kapanınca kendiliğinden
// kurulur; "İndir" düğmesi de Sparkle'ın kurulumunu hemen başlatır. App Store sürümünde güncellemeyi App Store yapar.

import AppKit
import CouchSubsCore
import Foundation
#if !APP_STORE
import Sparkle

/// Nino'nun tek Sparkle güncelleyicisi (bkz. project.yml: SUFeedURL, SUPublicEDKey, SUAutomaticallyUpdate).
/// Nino: yeni sürüm indiğinde sorulmadan kurulur ve uygulama yeniden açılır; çeviri sürüyorsa oyun bölünmesin diye
/// çeviri durdurulunca kurulur.
@MainActor
enum AppUpdater {
    static let delegate = AutoInstallDelegate()
    static let controller = SPUStandardUpdaterController(
        // Testlerde başlamaz (test sürecinde güncelleme penceresi açılmasın).
        startingUpdater: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
        updaterDelegate: delegate, userDriverDelegate: nil)

    /// Çeviri sürüyor mu (AppModel verir); sürüyorsa kurulum bekler.
    static var isBusy: () -> Bool = { false }

    /// Çeviri durunca çağrılır: bekleyen güncelleme varsa şimdi kurulur.
    static func installIfReady() { delegate.installIfIdle() }

    /// "Yeniden başlat"tan önce çağrılır (AppModel verir): çeviri sürüyorsa, yeniden açılınca kendiliğinden sürsün diye
    /// işaret bırakır ve oturumu düzgün kapatır.
    static var prepareForRestart: () -> Void = {}

    /// Kullanıcı "Yeniden başlat"a bastı: inmiş güncelleme çeviri sürse de hemen kurulur ve Nino yeniden açılır.
    static func installNow() {
        prepareForRestart()
        delegate.installNow()
    }
}

/// İnmiş güncellemeyi uygulama kapanmayı beklemeden kurar (Sparkle "kapanınca kur" yerine hemen kur ve yeniden aç).
final class AutoInstallDelegate: NSObject, SPUUpdaterDelegate {
    private var pending: (() -> Void)?

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        pending = immediateInstallHandler
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // Ana ekranda "Güncelleme hazır · Yeniden başlat" görünür; boştaysa beklemeden kurulur.
                NinoUpdates.shared.markReady()
                self.installIfIdle()
            }
        }
        return true
    }

    @MainActor
    func installNow() {
        guard let install = pending else { return }
        pending = nil
        install()
    }

    @MainActor
    func installIfIdle() {
        guard let install = pending, !AppUpdater.isBusy() else { return }
        pending = nil
        install()
    }
}
#endif

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
    /// Yeni sürüm indi; kurulup Nino'nun yeniden açılmasını bekliyor (çeviri sürüyorsa bekler, kullanıcı tek tıkla başlatır).
    @Published private(set) var ready = false
    /// Yeni sürüm arka planda iniyor.
    @Published private(set) var downloading = false
    private var checked = Date.distantPast

    func markReady() {
        ready = true
        downloading = false
    }

    /// Kendiliğinden en çok saatte bir bakılır; `force` ile (yenile düğmesi) hemen. Ağ yoksa ana ekran sessiz kalır.
    func check(force: Bool = false) async {
        // Testlerde (README ekran görüntüleri dahil) ağa çıkılmaz; "yeni sürüm hazır" şeridi görüntülere girmez.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard force || Date().timeIntervalSince(checked) > 3600 else { return }
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
        // Yeni sürüm bulununca sorulmadan indirilir; inince ana ekranda "Yeniden başlat" çıkar (boştaysa kendiliğinden kurulur).
        #if !APP_STORE
        startDownload()
        #endif
    }

    #if !APP_STORE
    /// Sparkle'a yeni sürümü arka planda indirtir. Sessizce indiremezse (ağ, izin) bir süre sonra Sparkle'ın kendi
    /// penceresi açılır; kullanıcı "indiriliyor"da çıkışsız kalmaz.
    private func startDownload() {
        guard !ready, !downloading else { return }
        downloading = true
        AppUpdater.controller.updater.checkForUpdatesInBackground()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(180))
            guard let self, self.downloading, !self.ready else { return }
            self.downloading = false
        }
    }
    #endif

    /// Güncelle / Yeniden başlat: sürüm indiyse hemen kurar ve Nino'yu yeniden açar; inmediyse indirir.
    func open() {
        guard available != nil || ready else { return }
        #if !APP_STORE
        if ready {
            AppUpdater.installNow()
        } else if downloading {
            // İndirme sürüyor; bitince "Yeniden başlat" görünür.
        } else if available != nil {
            // Arka planda indirilemedi: Sparkle'ın kendi penceresi indirir, imzayı doğrular, kurar ve yeniden açar.
            AppUpdater.controller.checkForUpdates(nil)
        }
        #else
        if let available { NSWorkspace.shared.open(available.download ?? available.page) }
        #endif
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
