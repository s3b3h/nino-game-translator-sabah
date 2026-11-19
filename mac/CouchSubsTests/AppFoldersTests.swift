// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import RemotePlay
import XCTest
@testable import Nino

/// Veri ve günlük klasörünün CouchSubs → Nino taşınmasının Mac'e özgü kısmı: asıl CouchSubs kurulu mu, başka kopya açık
/// mı, dublaj ayar dosyasındaki tam yol ve kullanıcıya gösterilen günlük yolları. Karar işlevinin testleri
/// core/Tests/CouchSubsCoreTests/AppFolderTests.swift içinde. Hiçbiri kullanıcının gerçek klasörüne yazmaz.
final class AppFoldersTests: XCTestCase {
    private let upstream = "com.couchsubs.mac"

    private func installed(registered: Set<String> = [], running: Set<String> = [], bundles: [String: String] = [:]) -> Bool {
        AppFolders.upstreamInstalled(registered: registered.contains, bundleID: { bundles[$0] }, running: running.contains, home: "/Users/test")
    }

    func testUpstreamBundleIdentifier() {
        XCTAssertEqual(AppFolders.upstreamBundleID, upstream)
        // Nino'nun kendi kimliği başka; kendini asıl uygulama sanmaz.
        XCTAssertNotEqual(Bundle.main.bundleIdentifier, upstream)
    }

    /// Asıl CouchSubs kimliğiyle kayıtlıysa, açıksa ya da olağan yerinde duruyorsa kurulu sayılır.
    func testUpstreamIsDetected() {
        XCTAssertFalse(installed())
        XCTAssertTrue(installed(registered: [upstream]))
        XCTAssertTrue(installed(running: [upstream]))
        XCTAssertTrue(installed(bundles: ["/Applications/CouchSubs.app": upstream]))
        XCTAssertTrue(installed(bundles: ["/Users/test/Applications/CouchSubs.app": upstream]))
    }

    /// Yalnız dosya adına bakılmaz: Mac App Store'daki Nino da CouchSubs.app adını taşır ama kimliği başkadır.
    func testOtherAppsNamedCouchSubsAreNotUpstream() {
        XCTAssertFalse(installed(bundles: ["/Applications/CouchSubs.app": "com.couchsubs.ios"]))
        XCTAssertFalse(installed(registered: ["com.ninotranslator.mac"], running: ["com.ninotranslator.mac"],
                                 bundles: ["/Applications/Nino.app": "com.ninotranslator.mac"]))
    }

    func testAnotherRunningCopy() {
        XCTAssertFalse(AppFolders.otherCopyRunning(pids: [], own: 10))
        XCTAssertFalse(AppFolders.otherCopyRunning(pids: [10], own: 10))
        XCTAssertTrue(AppFolders.otherCopyRunning(pids: [10, 11], own: 10))
    }

    /// Testler uygulamanın içinde çalışır: açılıştaki hazırlık hiçbir şeyi taşımamış ya da kopyalamamış olmalı.
    func testNothingIsMigratedInsideTests() {
        let prepared = AppFolders.prepareAtLaunch()
        XCTAssertFalse(prepared.support.moved || prepared.support.copied || prepared.logs.moved || prepared.logs.copied)
        XCTAssertNil(prepared.support.error)
        XCTAssertNil(prepared.logs.error)
    }

    /// Hata iletilerindeki ve "günlüğü göster" düğmelerindeki yollar gerçekten kullanılan klasörü gösterir.
    func testLogPathsShowTheFolderInUse() {
        let logs = AppFolder.resolution(.logs)
        XCTAssertEqual(TVInstallLog.file.path, logs.url.appendingPathComponent("tvinstall.log").path)
        XCTAssertTrue(TVInstallLog.displayPath.hasSuffix("Logs/\(logs.folderName)/tvinstall.log"), TVInstallLog.displayPath)
        XCTAssertEqual(RemotePlayLog.defaultFile.path, logs.url.appendingPathComponent("remoteplay.log").path)
        XCTAssertEqual(SubtitleLog.defaultFile.deletingLastPathComponent().path, logs.url.path)
        XCTAssertEqual(TVHelper.dataDirectory.path, AppFolder.resolution(.support).url.path)

        // Klasör Nino olunca yol da Nino'yu gösterir.
        let before = RemotePlayLog.folderName
        defer { RemotePlayLog.folderName = before }
        RemotePlayLog.folderName = AppFolder.name
        XCTAssertTrue(RemotePlayLog.displayPath.hasSuffix("Logs/Nino/remoteplay.log"), RemotePlayLog.displayPath)
        XCTAssertFalse(RemotePlayLog.displayPath.contains("CouchSubs"))
    }

    /// Dublaj modelinin ayar dosyasında klasörün tam yolu yazar; klasör taşınınca/kopyalanınca yenilenir.
    func testDubbingConfigFollowsTheFolder() throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("dubbing-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: base) }
        let old = base.appendingPathComponent("CouchSubs/dubbing/rev", isDirectory: true)
        let new = base.appendingPathComponent("Nino/dubbing/rev", isDirectory: true)
        try manager.createDirectory(at: old, withIntermediateDirectories: true)
        let original = "weights_path: hf://model.safetensors\ntokenizer_path: hf://tokenizer.model\nflow:\n  depth: 6\n"
        try original.write(to: old.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        try DubbingModel.localConfig(from: original, directory: old).write(to: old.appendingPathComponent("couchsubs.yaml"), atomically: true, encoding: .utf8)

        // Model hazır değilse (işaret dosyası yok) dokunulmaz.
        XCTAssertFalse(DubbingModelStore.repairConfig(directory: old))
        try Data().write(to: old.appendingPathComponent(".ready"))
        // Yol doğruysa yeniden yazılmaz.
        XCTAssertFalse(DubbingModelStore.repairConfig(directory: old))

        // Klasör kopyalandı (asıl CouchSubs kurulu): eski dosya eski klasörü gösterir, içerik karşılaştırılıp yenilenir.
        try manager.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: old, to: new)
        let stale = try String(contentsOf: new.appendingPathComponent("couchsubs.yaml"), encoding: .utf8)
        XCTAssertTrue(stale.contains("/CouchSubs/dubbing/rev/model.safetensors"))
        XCTAssertTrue(DubbingModelStore.repairConfig(directory: new))
        let fixed = try String(contentsOf: new.appendingPathComponent("couchsubs.yaml"), encoding: .utf8)
        XCTAssertTrue(fixed.contains("/Nino/dubbing/rev/model.safetensors"))
        XCTAssertTrue(fixed.contains("/Nino/dubbing/rev/tokenizer.model"))
        XCTAssertFalse(fixed.contains("CouchSubs"))
        XCTAssertFalse(DubbingModelStore.repairConfig(directory: new))
    }
}
