// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı.
//
// Greenlight (https://github.com/unknownskl/greenlight, MIT), Mac için ücretsiz ve açık kaynak Xbox ev yayını
// uygulamasıdır. Nino onu kendi içine gömmez (yaklaşık 220 MB); kullanıcı tek tıkla kurar: Nino GitHub'daki son
// sürümü indirir, SHA-256 özetini GitHub'ın verdiğiyle karşılaştırır, Uygulamalar klasörüne kopyalar ve açar.

import AppKit
import CryptoKit
import Foundation

enum GreenlightInstaller {
    enum InstallError: LocalizedError {
        case noRelease, download, corrupt, copy

        var errorDescription: String? {
            switch self {
            case .noRelease: String(localized: "Couldn't find Greenlight's latest version. Check your internet connection.")
            case .download: String(localized: "Greenlight couldn't be downloaded. Check your internet connection and try again.")
            case .corrupt: String(localized: "The downloaded Greenlight file was damaged. Please try again.")
            case .copy: String(localized: "Greenlight couldn't be copied to Applications.")
            }
        }
    }

    struct Release: Equatable {
        let url: URL
        let size: Int64
        /// GitHub'ın verdiği özet (küçük harf onaltılık); yoksa denetlenmez.
        let sha256: String?
    }

    static let releaseAPI = URL(string: "https://api.github.com/repos/unknownskl/greenlight/releases/latest")!

    /// Kurulu Greenlight (Uygulamalar ya da kullanıcının Uygulamalar klasörü).
    static var installedApp: URL? {
        candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static var candidates: [URL] {
        [URL(fileURLWithPath: "/Applications/Greenlight.app"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Greenlight.app")]
    }

    /// GitHub yanıtından Mac dosyasını seçer (Apple Silicon ve Intel için tek "universal.dmg").
    static func release(fromJSON data: Data) -> Release? {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let size: Int64
                let digest: String?
                let browser_download_url: URL
            }
            let assets: [Asset]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let asset = payload.assets.first(where: { $0.name.lowercased().hasSuffix("-universal.dmg") }) else { return nil }
        let digest = asset.digest.flatMap { $0.lowercased().hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
        return Release(url: asset.browser_download_url, size: asset.size, sha256: digest)
    }

    /// İndirir, doğrular, kurar ve kurulan uygulamanın yerini verir. `progress` 0…1.
    static func install(progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        var request = URLRequest(url: releaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = release(fromJSON: data) else { throw InstallError.noRelease }

        let total = Double(max(release.size, 1))
        let dmg: URL
        do {
            dmg = try await Downloader.download(release.url) { written in
                Task { @MainActor in progress(min(0.95, Double(written) / total * 0.95)) }
            }
        } catch {
            throw InstallError.download
        }
        defer { try? FileManager.default.removeItem(at: dmg) }
        if let expected = release.sha256, try sha256(of: dmg) != expected { throw InstallError.corrupt }

        let app = try await Task.detached(priority: .userInitiated) { try copyApp(from: dmg) }.value
        await MainActor.run { progress(1) }
        return app
    }

    /// Kalıbı görünmeden bağlar, Greenlight.app'i Uygulamalar'a (yazılamıyorsa ~/Applications'a) kopyalar.
    private static func copyApp(from dmg: URL) throws -> URL {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("nino-greenlight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]) else {
            throw InstallError.copy
        }
        defer {
            _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            try? FileManager.default.removeItem(at: mount)
        }
        let items = (try? FileManager.default.contentsOfDirectory(atPath: mount.path)) ?? []
        guard let name = items.first(where: { $0.lowercased().hasSuffix(".app") }) else { throw InstallError.copy }
        let source = mount.appendingPathComponent(name)
        for target in candidates {
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.removeItem(at: target) }
            if run("/usr/bin/ditto", [source.path, target.path]) { return target }
        }
        throw InstallError.copy
    }

    /// Greenlight'ı açar; zaten açıksa öne getirir.
    static func open() {
        guard let app = installedApp else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
