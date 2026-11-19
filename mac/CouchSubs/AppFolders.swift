// SPDX-License-Identifier: AGPL-3.0-only
// Nino: veri ve günlük klasörlerinin açılıştaki taşınması. Based on CouchSubs by Sinan Yorulmaz
// (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-19.

import AppKit
import CouchSubsCore
import RemotePlay

/// Mac'te veri ve günlük klasörleri `~/Library/Application Support/Nino` ve `~/Library/Logs/Nino`'dur (yolları
/// `CouchSubsCore.AppFolder` kurar). Eski sürümler `CouchSubs` adını kullanıyordu; burası açılışta, hiçbir dosya
/// (günlük dahil) açılmadan önce eski klasörleri bir kez taşıtır ve asıl CouchSubs uygulamasının kurulu olup
/// olmadığına bakar. Anahtarlık hizmet adı, UserDefaults alanı (bundle kimliği) ve TV protokol sabitleri değişmez.
enum AppFolders {
    /// Asıl CouchSubs uygulamasının (GitHub/DMG sürümü) bundle kimliği (yukarı akışın mac/project.yml'i). Aynı
    /// `Application Support/CouchSubs` ve `Logs/CouchSubs` klasörlerini kullanır.
    static let upstreamBundleID = "com.couchsubs.mac"
    /// Asıl uygulamanın olağan kurulum yerleri (ev klasörüne göre olanın başına ev klasörü eklenir).
    static let upstreamPaths = ["/Applications/CouchSubs.app", "Applications/CouchSubs.app"]

    /// Açılışta bir kez çalışır (ikinci çağrı aynı sonucu döner). `CouchSubsApp`'in ilk işi budur.
    @discardableResult
    static func prepareAtLaunch() -> AppFolder.Prepared { prepared }

    private static let prepared: AppFolder.Prepared = {
        // Testler uygulamanın içinde çalışır; kullanıcının gerçek klasörüne dokunulmaz (AppFolder.prepare de ayrıca bakar).
        let testing = AppFolder.isTesting
        // Mac App Store sürümünün klasörleri kendi kapsayıcısındadır; asıl CouchSubs oraya erişemez.
        let shared = !testing && !Distribution.isAppStore && upstreamInstalled()
        let other = !testing && otherCopyRunning()
        let result = AppFolder.prepare(legacyShared: shared, otherCopyRunning: other)
        // remoteplay.log da aynı klasöre yazılır (RemotePlay paketi CouchSubsCore'u görmez; ad buradan verilir).
        RemotePlayLog.folderName = result.logs.folderName
        // Dublaj modelinin ayar dosyasında klasörün tam yolu yazar; klasör taşındıysa ya da kopyalandıysa yenilenir.
        if !testing { DubbingModelStore.repairConfig() }
        return result
    }()

    /// Günlük açılınca yazılacak satırlar: klasörler taşındı mı, kopyalandı mı, olmadıysa neden.
    static var launchNotes: [String] {
        let result = prepared
        var notes: [String] = []
        func note(_ label: String, _ resolution: AppFolder.Resolution, copiedText: String) {
            if resolution.moved { notes.append("\(label) klasörü taşındı: \(resolution.url.path)") }
            if resolution.copied { notes.append("\(label) klasörü \(copiedText) (asıl CouchSubs kurulu, eski klasör yerinde bırakıldı): \(resolution.url.path)") }
            if let error = resolution.error { notes.append("\(label) klasörü \(resolution.folderName) olarak kullanılıyor: \(error)") }
        }
        note("Veri", result.support, copiedText: "kopyalandı")
        // Günlükler kopyalanmaz: eski klasörde asıl CouchSubs'ın kayıtları da vardır.
        note("Günlük", result.logs, copiedText: "boş açıldı")
        if result.resolvedEarly { notes.append("Klasörler taşınmadan önce kullanılmaya başlanmıştı; bu açılışta taşıma yapılmadı") }
        return notes
    }

    // MARK: - Asıl CouchSubs kurulu mu

    /// Asıl CouchSubs bu Mac'te kurulu ya da açık mı. Kimliğiyle (LaunchServices) ya da olağan kurulum yerlerindeki
    /// paketin kimliğiyle anlaşılır; yalnız dosya adına bakılmaz (Mac App Store'daki Nino da CouchSubs.app adını taşır).
    static func upstreamInstalled() -> Bool {
        upstreamInstalled(
            registered: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
            bundleID: { Bundle(path: $0)?.bundleIdentifier },
            running: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty },
            home: NSHomeDirectory())
    }

    /// Saf karar (testlerde sahte sorgularla).
    static func upstreamInstalled(registered: (String) -> Bool, bundleID: (String) -> String?,
                                  running: (String) -> Bool, home: String) -> Bool {
        if registered(upstreamBundleID) || running(upstreamBundleID) { return true }
        return upstreamPaths.contains { path in
            let full = path.hasPrefix("/") ? path : (home as NSString).appendingPathComponent(path)
            return bundleID(full) == upstreamBundleID
        }
    }

    /// Nino'nun başka bir kopyası açık mı (eski klasörü kullanıyor olabilir).
    static func otherCopyRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        return otherCopyRunning(pids: NSRunningApplication.runningApplications(withBundleIdentifier: id).map(\.processIdentifier),
                                own: ProcessInfo.processInfo.processIdentifier)
    }

    static func otherCopyRunning(pids: [pid_t], own: pid_t) -> Bool { pids.contains { $0 != own } }
}
