// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı.
//
// "Xbox'ı Bağla": Xbox görüntüsü bu Mac'e Greenlight (https://github.com/unknownskl/greenlight, MIT) ile gelir.
// Nino Greenlight'ı yönetmez, yalnız dışarıdan izler ve kullanıcıyı bir sonraki adıma götürür:
//   1. Greenlight kurulu mu (Uygulamalar klasörü),
//   2. Microsoft hesabıyla girilmiş mi (Greenlight'ın ayar dosyasında `user.tokenstore` kaydı; içeriği okunmaz),
//   3. Xbox yayını açık mı (yayın penceresinin başlığı "Greenlight - <Yayın> <konsol kimliği>").

import AppKit
import Combine
import Foundation

/// Xbox bağlantısının adımları; ekranda sırayla yeşile döner.
enum XboxConnectStep: Int, CaseIterable, Comparable {
    case install, signIn, stream, done

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

enum GreenlightProbe {
    static let bundleID = "com.unknownskl.greenlight"

    /// Greenlight'ın ayar dosyası (electron-store).
    static var configFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/greenlight-desktop/config.json")
    }

    /// Ayar dosyasında Microsoft girişinin kaydı var mı. Jetonların kendisine bakılmaz, yalnız varlığına.
    static func signedIn(configJSON data: Data) -> Bool {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        let stored = (root["user"] as? [String: Any])?["tokenstore"] ?? root["user.tokenstore"]
        guard let text = stored as? String else { return stored is [String: Any] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "{}"
    }

    static var signedIn: Bool {
        guard let data = try? Data(contentsOf: configFile) else { return false }
        return signedIn(configJSON: data)
    }

    /// Yayın penceresinin başlığı: "Greenlight - Streaming F4000F1E2D3C4B5A" (orta kelime Greenlight'ın diline göre
    /// değişir, sondaki konsol kimliği değişmez). Menü sayfaları "Greenlight - My consoles" gibidir.
    static func isStreamTitle(_ title: String) -> Bool {
        guard title.hasPrefix("Greenlight - "), let last = title.split(separator: " ").last, last.count >= 8 else { return false }
        return last.allSatisfy(\.isHexDigit) && last.contains(where: \.isNumber)
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Greenlight'ın Xbox yayını gösteren penceresi var mı (başlıkları okumak için Ekran Kaydı izni gerekir).
    static var isStreaming: Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { info in
            let owner = (info[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            return owner.contains("greenlight") && isStreamTitle(info[kCGWindowName as String] as? String ?? "")
        }
    }

    /// Bulunulan adım: ilk tamamlanmamış adım.
    static func step(installed: Bool, signedIn: Bool, streaming: Bool) -> XboxConnectStep {
        if streaming { return .done }
        if !installed { return .install }
        return signedIn ? .stream : .signIn
    }
}

/// Greenlight'ın durumunu saniyede bir izler; "Xbox'ı Bağla" ekranı ve ana ekrandaki düğme bunu gösterir.
@MainActor
final class XboxConnectModel: ObservableObject {
    static let shared = XboxConnectModel()

    @Published private(set) var installed = false
    @Published private(set) var running = false
    @Published private(set) var signedIn = false
    @Published private(set) var streaming = false
    /// Kurulum sürüyorsa 0…1.
    @Published private(set) var installProgress: Double?
    @Published private(set) var installError: String?

    var step: XboxConnectStep { GreenlightProbe.step(installed: installed, signedIn: signedIn, streaming: streaming) }

    private var timer: Timer?
    private var watchers = 0

    /// Ekran görünürken izlemeyi başlatır (iç içe ekranlar sayılır; son ekran kapanınca durur).
    func watch() {
        watchers += 1
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let installed = GreenlightInstaller.installedApp != nil
        if self.installed != installed { self.installed = installed }
        let running = installed && GreenlightProbe.isRunning
        if self.running != running { self.running = running }
        let signedIn = installed && GreenlightProbe.signedIn
        if self.signedIn != signedIn { self.signedIn = signedIn }
        let streaming = running && GreenlightProbe.isStreaming
        if self.streaming != streaming { self.streaming = streaming }
    }

    /// Greenlight'ı indirip kurar, sonra açar: kullanıcı dmg ile uğraşmaz.
    func install() {
        guard installProgress == nil else { return }
        installError = nil
        installProgress = 0
        Task {
            do {
                _ = try await GreenlightInstaller.install { [weak self] in self?.installProgress = $0 }
                installProgress = nil
                refresh()
                openGreenlight()
            } catch {
                installProgress = nil
                installError = error.localizedDescription
            }
        }
    }

    /// Greenlight'ı açar ya da öne getirir.
    func openGreenlight() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: GreenlightProbe.bundleID).first {
            app.activate()
        } else {
            GreenlightInstaller.open()
        }
    }

    /// Microsoft'un kod girme sayfası (Greenlight girişte bir kod gösterir).
    func openLinkPage() {
        if let url = URL(string: "https://www.microsoft.com/link") { NSWorkspace.shared.open(url) }
    }
}
