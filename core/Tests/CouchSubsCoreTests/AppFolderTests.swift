// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// Veri ve günlük klasörünün CouchSubs → Nino taşınması. Hiçbir test kullanıcının gerçek klasörüne dokunmaz: karar
/// işlevi saftır, disk testleri geçici bir klasörde çalışır.
final class AppFolderTests: XCTestCase {
    private struct Failure: Error {}

    // MARK: - Saf karar

    /// Yalnız eski klasör var → taşınır, yenisi kullanılır.
    func testOnlyLegacyIsMoved() {
        var moved = 0, copied = 0
        let decision = AppFolder.decide(currentExists: false, legacyExists: true, legacyShared: false,
                                        move: { moved += 1 }, copy: { copied += 1 }, currentExistsNow: { true })
        XCTAssertEqual(decision, AppFolder.Decision(useLegacy: false, moved: true))
        XCTAssertEqual([moved, copied], [1, 0])
    }

    /// Asıl CouchSubs kurulu → klasör taşınmaz, kopyalanır.
    func testSharedLegacyIsCopiedNotMoved() {
        var moved = 0, copied = 0
        let decision = AppFolder.decide(currentExists: false, legacyExists: true, legacyShared: true,
                                        move: { moved += 1 }, copy: { copied += 1 }, currentExistsNow: { true })
        XCTAssertEqual(decision, AppFolder.Decision(useLegacy: false, copied: true))
        XCTAssertEqual([moved, copied], [0, 1])
    }

    /// İkisi de var → Nino; hiçbir şey taşınmaz ya da kopyalanmaz.
    func testBothExistUsesNino() {
        for shared in [false, true] {
            var touched = 0
            let decision = AppFolder.decide(currentExists: true, legacyExists: true, legacyShared: shared,
                                            move: { touched += 1 }, copy: { touched += 1 }, currentExistsNow: { true })
            XCTAssertEqual(decision, AppFolder.Decision(useLegacy: false))
            XCTAssertEqual(touched, 0)
        }
    }

    /// Taşıma (ya da kopya) hatası → eski klasörle devam.
    func testFailedMoveKeepsLegacy() {
        let moved = AppFolder.decide(currentExists: false, legacyExists: true, legacyShared: false,
                                     move: { throw Failure() }, copy: nil, currentExistsNow: { false })
        XCTAssertTrue(moved.useLegacy)
        XCTAssertFalse(moved.moved)
        XCTAssertNotNil(moved.error)
        let copied = AppFolder.decide(currentExists: false, legacyExists: true, legacyShared: true,
                                      move: nil, copy: { throw Failure() }, currentExistsNow: { false })
        XCTAssertTrue(copied.useLegacy)
        XCTAssertFalse(copied.copied)
        XCTAssertNotNil(copied.error)
    }

    /// Taşıma, başka bir kopya işi önce bitirdiği için başarısız olduysa yeni klasör kullanılır.
    func testFailedMoveUsesNinoIfItAppearedMeanwhile() {
        let decision = AppFolder.decide(currentExists: false, legacyExists: true, legacyShared: false,
                                        move: { throw Failure() }, copy: nil, currentExistsNow: { true })
        XCTAssertFalse(decision.useLegacy)
        XCTAssertFalse(decision.moved)
    }

    func testNothingExistsUsesNino() {
        let decision = AppFolder.decide(currentExists: false, legacyExists: false, legacyShared: true,
                                        move: { XCTFail("taşınacak bir şey yok") }, copy: { XCTFail("kopyalanacak bir şey yok") },
                                        currentExistsNow: { false })
        XCTAssertEqual(decision, AppFolder.Decision(useLegacy: false))
    }

    /// Taşımasız karar (testler, araçlar): eski klasör kullanılır, diske dokunulmaz.
    func testWithoutMigrationLegacyStays() {
        for shared in [false, true] {
            let decision = AppFolder.decide(currentExists: false, legacyExists: true, legacyShared: shared,
                                            move: nil, copy: nil, currentExistsNow: { false })
            XCTAssertEqual(decision, AppFolder.Decision(useLegacy: true))
        }
    }

    // MARK: - Diskte (geçici klasörde)

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("appfolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private var nino: URL { root.appendingPathComponent("Nino", isDirectory: true) }
    private var legacy: URL { root.appendingPathComponent("CouchSubs", isDirectory: true) }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func write(_ text: String, _ path: String, in folder: URL) throws {
        let file = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    private func read(_ path: String, in folder: URL) -> String? {
        try? String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)
    }

    private func seedLegacy() throws {
        try write("geçmiş", "history.json", in: legacy)
        try write("anahtar", "adb/adbkey", in: legacy)
        try write("model", "dubbing/rev/model.safetensors", in: legacy)
    }

    func testMoveRenamesTheWholeFolder() throws {
        try seedLegacy()
        let result = AppFolder.onDisk(root: root, migrate: true)
        XCTAssertEqual(result, AppFolder.Resolution(url: nino, folderName: "Nino", moved: true))
        XCTAssertFalse(exists(legacy))
        XCTAssertEqual(read("history.json", in: nino), "geçmiş")
        XCTAssertEqual(read("adb/adbkey", in: nino), "anahtar")
        XCTAssertEqual(read("dubbing/rev/model.safetensors", in: nino), "model")
        // Sonraki açılış: yeni klasör var, başka bir şey yapılmaz.
        XCTAssertEqual(AppFolder.onDisk(root: root, migrate: true), AppFolder.Resolution(url: nino, folderName: "Nino"))
    }

    /// Asıl CouchSubs kuruluysa eski klasör olduğu gibi kalır; içerik (model dahil) yenisine kopyalanır.
    func testSharedFolderIsCopiedAndLeftIntact() throws {
        try seedLegacy()
        try write("x", ".DS_Store", in: legacy)
        let result = AppFolder.onDisk(root: root, migrate: true, legacyShared: true)
        XCTAssertEqual(result, AppFolder.Resolution(url: nino, folderName: "Nino", copied: true))
        for folder in [legacy, nino] {
            XCTAssertEqual(read("history.json", in: folder), "geçmiş")
            XCTAssertEqual(read("adb/adbkey", in: folder), "anahtar")
            XCTAssertEqual(read("dubbing/rev/model.safetensors", in: folder), "model")
        }
        XCTAssertTrue(exists(nino.appendingPathComponent(AppFolder.copyNoteFile)))
        XCTAssertFalse(exists(legacy.appendingPathComponent(AppFolder.copyNoteFile)))
        XCTAssertFalse(exists(nino.appendingPathComponent(".DS_Store")))
        // Geçici kopya klasörü kalmaz.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), ["CouchSubs", "Nino"])
        // Sonraki açılış: Nino; eski klasöre yazılanlar artık Nino'ya geçmez (birleştirilmez).
        try write("yeni", "history.json", in: legacy)
        XCTAssertEqual(AppFolder.onDisk(root: root, migrate: true, legacyShared: true), AppFolder.Resolution(url: nino, folderName: "Nino"))
        XCTAssertEqual(read("history.json", in: nino), "geçmiş")
    }

    /// Ortak günlük klasörü kopyalanmaz: Nino'nun günlüğü boş başlar, eskisi yerinde kalır.
    func testSharedLogsStartEmpty() throws {
        try write("satır", "remoteplay.log", in: legacy)
        let result = AppFolder.onDisk(root: root, migrate: true, legacyShared: true, copiesData: false)
        XCTAssertEqual(result, AppFolder.Resolution(url: nino, folderName: "Nino", copied: true))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: nino.path), [])
        XCTAssertEqual(read("remoteplay.log", in: legacy), "satır")
    }

    func testBothFoldersUseNinoAndLeaveLegacyAlone() throws {
        try seedLegacy()
        try write("nino", "history.json", in: nino)
        for shared in [false, true] {
            XCTAssertEqual(AppFolder.onDisk(root: root, migrate: true, legacyShared: shared), AppFolder.Resolution(url: nino, folderName: "Nino"))
        }
        XCTAssertEqual(read("history.json", in: nino), "nino")
        XCTAssertEqual(read("history.json", in: legacy), "geçmiş")
        XCTAssertFalse(exists(nino.appendingPathComponent("adb")))
    }

    /// Boş bir Nino klasörü (yalnız .DS_Store) eski verinin önüne geçmez.
    func testEmptyNinoFolderDoesNotHideLegacyData() throws {
        try seedLegacy()
        try write("x", ".DS_Store", in: nino)
        // Taşımasız kararda eski klasör kullanılır ve boş klasöre dokunulmaz.
        XCTAssertEqual(AppFolder.onDisk(root: root, migrate: false), AppFolder.Resolution(url: legacy, folderName: "CouchSubs"))
        XCTAssertTrue(exists(nino.appendingPathComponent(".DS_Store")))
        let result = AppFolder.onDisk(root: root, migrate: true)
        XCTAssertEqual(result, AppFolder.Resolution(url: nino, folderName: "Nino", moved: true))
        XCTAssertEqual(read("history.json", in: nino), "geçmiş")
        XCTAssertFalse(exists(legacy))
    }

    /// Taşımasız karar diske hiç yazmaz: ne taşır, ne kopyalar, ne klasör oluşturur.
    func testResolvingWithoutMigrationWritesNothing() throws {
        XCTAssertEqual(AppFolder.onDisk(root: root, migrate: false), AppFolder.Resolution(url: nino, folderName: "Nino"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        try seedLegacy()
        for shared in [false, true] {
            XCTAssertEqual(AppFolder.onDisk(root: root, migrate: false, legacyShared: shared), AppFolder.Resolution(url: legacy, folderName: "CouchSubs"))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["CouchSubs"])
    }

    func testNothingOnDiskCreatesNino() {
        XCTAssertEqual(AppFolder.onDisk(root: root, migrate: true), AppFolder.Resolution(url: nino, folderName: "Nino"))
        XCTAssertTrue(exists(nino))
        XCTAssertFalse(exists(legacy))
    }

    /// Nino'nun başka bir kopyası açıkken klasöre dokunulmaz (macOS açık dosyalı klasörün adını değiştirmeye izin verir).
    func testNothingMovesWhileAnotherCopyRuns() throws {
        try seedLegacy()
        for shared in [false, true] {
            let result = AppFolder.onDisk(root: root, migrate: true, legacyShared: shared, otherCopyRunning: true)
            XCTAssertEqual(result.url, legacy)
            XCTAssertEqual(result.folderName, "CouchSubs")
            XCTAssertNotNil(result.error)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["CouchSubs"])
        // O kopya kapanınca sonraki açılışta taşınır.
        XCTAssertTrue(AppFolder.onDisk(root: root, migrate: true).moved)
    }

    /// Taşıma başarısızsa eski klasörle devam edilir ve yeni klasör oluşturulmaz (sonraki açılış yeniden dener).
    func testFailedMoveOnDiskKeepsLegacyAndCreatesNothing() throws {
        final class NoMove: FileManager {
            override func moveItem(at srcURL: URL, to dstURL: URL) throws { throw CocoaError(.fileWriteNoPermission) }
        }
        try seedLegacy()
        let result = AppFolder.onDisk(root: root, migrate: true, fileManager: NoMove())
        XCTAssertEqual(result.url, legacy)
        XCTAssertEqual(result.folderName, "CouchSubs")
        XCTAssertFalse(result.moved)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["CouchSubs"])
        XCTAssertEqual(read("history.json", in: legacy), "geçmiş")
    }

    /// Kopya yarıda kalırsa yarım klasör bırakılmaz: eski klasörle devam edilir.
    func testFailedCopyLeavesNoHalfFolder() throws {
        final class FailsOnAdb: FileManager {
            override func copyItem(at srcURL: URL, to dstURL: URL) throws {
                if srcURL.lastPathComponent == "adb" { throw CocoaError(.fileWriteOutOfSpace) }
                try super.copyItem(at: srcURL, to: dstURL)
            }
        }
        try seedLegacy()
        let result = AppFolder.onDisk(root: root, migrate: true, legacyShared: true, fileManager: FailsOnAdb())
        XCTAssertEqual(result.url, legacy)
        XCTAssertFalse(result.copied)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["CouchSubs"])
        XCTAssertEqual(read("adb/adbkey", in: legacy), "anahtar")
    }

    /// Yarıda kesilmiş eski bir kopya denemesinin artığı temizlenir.
    func testStaleCopyAttemptIsCleaned() throws {
        try seedLegacy()
        let stale = root.appendingPathComponent("Nino" + AppFolder.copySuffix + "eski", isDirectory: true)
        try write("yarım", "history.json", in: stale)
        XCTAssertTrue(AppFolder.onDisk(root: root, migrate: true, legacyShared: true).copied)
        XCTAssertFalse(exists(stale))
        XCTAssertEqual(read("history.json", in: nino), "geçmiş")
    }

    /// Test sürecinde açılış hazırlığı hiçbir şeyi taşımaz (`swift test` Xcode'un ortam değişkenini vermez).
    func testTestProcessIsRecognised() {
        XCTAssertTrue(AppFolder.isTesting)
    }

    // MARK: - Yollar

    /// Eski adla kurulan yollar, önceki sürümlerin kurduğu yollarla aynıdır (iPhone'da ad hep budur).
    func testLegacyPathsAreUnchanged() {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(AppFolder.root(.logs).appendingPathComponent(AppFolder.legacyName, isDirectory: true).appendingPathComponent("altyazi.log").path,
                       library.appendingPathComponent("Logs/CouchSubs/altyazi.log").path)
        XCTAssertEqual(AppFolder.root(.support).appendingPathComponent(AppFolder.legacyName, isDirectory: true).appendingPathComponent("packs", isDirectory: true).path,
                       support.appendingPathComponent("CouchSubs", isDirectory: true).appendingPathComponent("packs", isDirectory: true).path)
    }

    /// Ortak yollar tek yerden (`AppFolder`) kurulur ve aynı klasörü gösterir.
    func testSharedPathsFollowTheResolvedFolder() {
        let support = AppFolder.resolution(.support), logs = AppFolder.resolution(.logs)
        XCTAssertTrue(["Nino", "CouchSubs"].contains(support.folderName))
        XCTAssertEqual(GamePackLibrary.userDirectory.path, support.url.appendingPathComponent("packs").path)
        XCTAssertEqual(GlossaryStore.userDirectory.path, support.url.appendingPathComponent("Glossary").path)
        XCTAssertEqual(SubtitleHistory.defaultFile.path, support.url.appendingPathComponent("history.json").path)
        XCTAssertEqual(SubtitleLog.defaultFile.path, logs.url.appendingPathComponent("altyazi.log").path)
        // Testlerde hiçbir şey taşınmaz.
        XCTAssertFalse(support.moved || support.copied || logs.moved || logs.copied)
    }
}
