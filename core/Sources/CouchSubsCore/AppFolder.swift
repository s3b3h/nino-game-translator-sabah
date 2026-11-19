// SPDX-License-Identifier: AGPL-3.0-only
// Nino: veri ve günlük klasörlerinin adı ve CouchSubs'tan kalan klasörün taşınması. Based on CouchSubs by Sinan Yorulmaz
// (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-19.

import Foundation

/// Uygulamanın kullanıcıya özel klasörleri; yollarını yalnız burası kurar.
///
/// - Mac: `~/Library/Application Support/Nino` (ayarlar dışındaki veri: paketler, sözlük, geçmiş, havuz, dublaj modeli,
///   TV anahtarları) ve `~/Library/Logs/Nino` (remoteplay.log, altyazi.log, tvinstall.log). Eski sürümler ikisinde de
///   `CouchSubs` adını kullanıyordu. `prepare` açılışta, hiçbir dosya açılmadan önce eski klasörü bir kez yenisine
///   taşır; taşınamazsa bu çalıştırmada eski klasör kullanılır ve sonraki açılışta yeniden denenir.
/// - Eski klasör asıl CouchSubs uygulamasının da klasörüdür. O uygulama bu Mac'te kuruluysa (`legacyShared`) klasör
///   TAŞINMAZ: veri yeni klasöre kopyalanır, eski klasör olduğu gibi kalır.
/// - iPhone/iPad: hiçbir şey değişmez; ad `CouchSubs` kalır (uygulamanın kendi kapsayıcısında) ve taşıma yapılmaz.
///
/// Karar süreç başına bir kez verilir ve değişmez. `prepare` çağrılmadan bir yol istenirse (testler, araçlar) karar
/// diske hiç yazmadan verilir: yeni klasör varsa o, yoksa eskisi varsa eskisi, ikisi de yoksa yenisi.
/// Windows'taki karşılığı: windows/src/CouchSubs.Core/DataFolder.cs.
public enum AppFolder {
    /// Klasörün adı.
    public static let name = "Nino"
    /// CouchSubs'tan kalan eski ad.
    public static let legacyName = "CouchSubs"
    /// Kopyalama bitene kadar kullanılan geçici klasörün eki: "Nino" + bu ek + rastgele kimlik.
    static let copySuffix = ".kopya-"
    /// Kopyalanan klasöre bırakılan kısa not.
    static let copyNoteFile = "kopyalandi.txt"

    public enum Kind: Sendable {
        /// `~/Library/Application Support/<ad>`
        case support
        /// `~/Library/Logs/<ad>`
        case logs
    }

    /// Bir klasör için verilen karar.
    public struct Resolution: Equatable, Sendable {
        public let url: URL
        /// Kullanılan klasörün adı ("Nino"; taşınamadıysa "CouchSubs").
        public let folderName: String
        /// Eski klasör bu açılışta yenisine taşındı.
        public let moved: Bool
        /// Eski klasör asıl CouchSubs'la ortak olduğu için taşınmadı; verisi bu açılışta yenisine kopyalandı.
        public let copied: Bool
        /// Taşıma ya da kopyalama denendi ve olmadıysa nedeni (tanı için).
        public let error: String?

        public init(url: URL, folderName: String, moved: Bool = false, copied: Bool = false, error: String? = nil) {
            self.url = url
            self.folderName = folderName
            self.moved = moved
            self.copied = copied
            self.error = error
        }
    }

    /// `~/Library/Application Support/Nino` (iPhone'da ve taşınamadıysa `…/CouchSubs`).
    public static var support: URL { resolution(.support).url }
    /// `~/Library/Logs/Nino` (iPhone'da ve taşınamadıysa `…/CouchSubs`).
    public static var logs: URL { resolution(.logs).url }

    /// Bu süreçte verilen karar. Daha verilmediyse burada taşımasız ve diske yazmadan verilir.
    public static func resolution(_ kind: Kind) -> Resolution {
        state.lock.lock()
        defer { state.lock.unlock() }
        if let known = state.resolved[kind] { return known }
        let made = resolve(kind, migrate: false, legacyShared: false, otherCopyRunning: false)
        state.resolved[kind] = made
        return made
    }

    /// `prepare`'in sonucu.
    public struct Prepared: Equatable, Sendable {
        public let support: Resolution
        public let logs: Resolution
        /// `prepare`'den önce bir yol istenmiş ve karar taşımasız verilmişti: bu açılışta hiçbir şey taşınmadı.
        public let resolvedEarly: Bool
    }

    /// Uygulama açılışında, veriye ya da günlüğe dokunan her şeyden önce bir kez çağrılır: gerekiyorsa eski klasörleri
    /// taşır (ya da kopyalar) ve kararı sabitler. Yalnız Mac'te iş yapar. Testlerin içinde (XCTest) hiçbir şey taşımaz:
    /// testler uygulamanın içinde çalışır ve kullanıcının gerçek klasörüne dokunmamalıdır.
    /// - Parameters:
    ///   - legacyShared: Asıl CouchSubs uygulaması bu Mac'te kurulu ya da açık: eski klasör onundur, taşınmaz.
    ///   - otherCopyRunning: Nino'nun başka bir kopyası açık (eski klasörü kullanıyor olabilir). macOS açık dosyaları olan
    ///     klasörün adını değiştirmeye izin verir; bu yüzden o durumda hiçbir şey yapılmaz, iş sonraki açılışa kalır.
    @discardableResult
    public static func prepare(legacyShared: Bool, otherCopyRunning: Bool) -> Prepared {
        state.lock.lock()
        defer { state.lock.unlock() }
        let early = !state.resolved.isEmpty
        for kind in [Kind.support, .logs] where state.resolved[kind] == nil {
            state.resolved[kind] = resolve(kind, migrate: !isTesting && !early, legacyShared: legacyShared, otherCopyRunning: otherCopyRunning)
        }
        return Prepared(support: state.resolved[.support]!, logs: state.resolved[.logs]!, resolvedEarly: early)
    }

    /// Test süreci mi. Xcode ortam değişkenini verir; `swift test` vermez (ölçüldü), o yüzden XCTest'in yüklü olup
    /// olmadığına da bakılır.
    public static var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var resolved: [Kind: Resolution] = [:]
    }

    private static let state = State()

    /// Klasörün üst klasörü (gerçek kullanıcı klasörü; Mac App Store sürümünde uygulamanın kapsayıcısı).
    static func root(_ kind: Kind) -> URL {
        switch kind {
        case .support:
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        case .logs:
            return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs", isDirectory: true)
        }
    }

    private static func resolve(_ kind: Kind, migrate: Bool, legacyShared: Bool, otherCopyRunning: Bool) -> Resolution {
        let root = root(kind)
        #if os(macOS)
        // Günlükler ortak klasördeyse kopyalanmaz: içinde asıl CouchSubs'ın kayıtları da vardır; Nino temiz başlar.
        return onDisk(root: root, migrate: migrate, legacyShared: legacyShared, otherCopyRunning: otherCopyRunning,
                      copiesData: kind == .support)
        #else
        return Resolution(url: root.appendingPathComponent(legacyName, isDirectory: true), folderName: legacyName)
        #endif
    }

    // MARK: - Karar (diske dokunmaz)

    struct Decision: Equatable {
        var useLegacy: Bool
        var moved = false
        var copied = false
        var error: String?
    }

    /// Hangi klasörün kullanılacağına karar verir; diske dokunmaz (taşıma `move`, kopya `copy` ile yapılır).
    ///
    /// - Yeni klasör varsa o kullanılır; eskisi de dursa birleştirilmez, eskisine dokunulmaz.
    /// - İkisi de yoksa yenisi kullanılır.
    /// - Yalnız eskisi varsa taşınır. Taşıma hangi nedenle olursa olsun başarısızsa eski klasör kullanılır; yeni klasör
    ///   oluşturulmaz (yoksa sonraki açılış boş yeni klasörü seçer, veriler kaybolmuş görünürdü).
    /// - Eski klasör asıl CouchSubs'la ortaksa (`legacyShared`) taşınmaz: verisi kopyalanır, eski klasör olduğu gibi
    ///   kalır. Kopya başarısızsa eski klasör kullanılır.
    /// - Taşıma ya da kopya, aynı anda açılan başka bir kopya işi önce bitirdiği için başarısız olduysa yeni klasör
    ///   kullanılır (`currentExistsNow`).
    /// - `move`/`copy` nil ise (taşımasız karar) eski klasör kullanılır.
    static func decide(currentExists: Bool, legacyExists: Bool, legacyShared: Bool,
                       move: (() throws -> Void)?, copy: (() throws -> Void)?,
                       currentExistsNow: () -> Bool) -> Decision {
        if currentExists || !legacyExists { return Decision(useLegacy: false) }
        guard let action = legacyShared ? copy : move else { return Decision(useLegacy: true) }
        do {
            try action()
            return Decision(useLegacy: false, moved: !legacyShared, copied: legacyShared)
        } catch {
            let reason = (legacyShared ? "kopyalanamadı: " : "taşınamadı: ") + error.localizedDescription
            return Decision(useLegacy: !currentExistsNow(), error: reason)
        }
    }

    // MARK: - Diskte

    /// Kararı `root` altındaki gerçek klasörlere uygular. İki klasör aynı üst klasörde olduğundan taşıma tek bir
    /// yeniden adlandırmadır: ya bütün klasör taşınır ya hiçbir şey; yarım kalmış iki klasör oluşmaz.
    /// - Parameters:
    ///   - migrate: false ise diske yazılmaz: ne taşınır, ne kopyalanır, ne klasör oluşturulur.
    ///   - copiesData: Ortak klasörün verisi kopyalansın mı (false: yeni klasör boş açılır).
    static func onDisk(root: URL, migrate: Bool, legacyShared: Bool = false, otherCopyRunning: Bool = false,
                       copiesData: Bool = true, fileManager: FileManager = .default) -> Resolution {
        let current = root.appendingPathComponent(name, isDirectory: true)
        let legacy = root.appendingPathComponent(legacyName, isDirectory: true)
        let legacyExists = isDirectory(legacy, fileManager)
        var currentExists = isDirectory(current, fileManager)
        // Boş bir yeni klasör eski verinin önüne geçmesin (yoksa veriler kaybolmuş görünürdü): boşsa yok sayılır ve
        // taşımadan önce kaldırılır. İçinde tek dosya bile varsa (.DS_Store hariç) yeni klasör kullanılır.
        if currentExists, legacyExists, isEmpty(current, fileManager) {
            if migrate, !otherCopyRunning { removeEmpty(current, fileManager) }
            currentExists = migrate && !otherCopyRunning ? isDirectory(current, fileManager) : false
        }
        if migrate, otherCopyRunning, legacyExists, !currentExists {
            return Resolution(url: legacy, folderName: legacyName,
                              error: "Nino'nun başka bir kopyası açık; klasör sonraki açılışta taşınacak")
        }
        let decision = decide(
            currentExists: currentExists, legacyExists: legacyExists, legacyShared: legacyShared,
            move: migrate ? { try fileManager.moveItem(at: legacy, to: current) } : nil,
            copy: migrate ? {
                if copiesData { try copyData(from: legacy, to: current, fileManager: fileManager) }
                else { try fileManager.createDirectory(at: current, withIntermediateDirectories: true) }
            } : nil,
            currentExistsNow: { isDirectory(current, fileManager) })
        if decision.useLegacy { return Resolution(url: legacy, folderName: legacyName, error: decision.error) }
        // İkisi de yoksa yenisi oluşturulur. Oluşturulamazsa yol yine aynıdır; yazan kod kendi hatasını görür.
        if migrate { try? fileManager.createDirectory(at: current, withIntermediateDirectories: true) }
        return Resolution(url: current, folderName: name, moved: decision.moved, copied: decision.copied, error: decision.error)
    }

    /// Eski klasörün içeriğini yeni klasöre kopyalar; eski klasöre dokunmaz. Ya hep ya hiç: önce yanındaki geçici bir
    /// klasöre kopyalanır, hepsi bitince tek bir yeniden adlandırmayla yeni klasör olur. Tek dosya bile kopyalanamazsa
    /// geçici klasör silinir ve hata fırlatılır (yarım kopya yeni klasör olup sonraki açılışlarda eksik veriyle
    /// kullanılmasın).
    ///
    /// Dublaj modeli (yüzlerce MB) de kopyalanır: APFS'te `copyItem` dosyayı klonlar, yer kaplamaz ve anında biter
    /// (ölçüldü: 400 MB 0,002 sn, boş alan değişmedi). Yeniden indirmek ise kullanıcıya yüzlerce MB'a mal olurdu.
    static func copyData(from legacy: URL, to current: URL, fileManager: FileManager = .default) throws {
        let parent = current.deletingLastPathComponent()
        // Yarıda kesilmiş (ör. bilgisayar kapanmış) önceki denemelerin artıkları.
        for stale in (try? fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
        where stale.lastPathComponent.hasPrefix(current.lastPathComponent + copySuffix) {
            try? fileManager.removeItem(at: stale)
        }
        let temporary = parent.appendingPathComponent(current.lastPathComponent + copySuffix + UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
            for entry in try fileManager.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)
            where entry.lastPathComponent != ".DS_Store" {
                // Simgesel bağlar bağ olarak kopyalanır (izlenmez).
                try fileManager.copyItem(at: entry, to: temporary.appendingPathComponent(entry.lastPathComponent))
            }
            let note = "Bu klasörün verisi \(legacy.path) klasöründen kopyalandı. O klasörü CouchSubs da kullandığı için yerinde bırakıldı.\n"
            try Data(note.utf8).write(to: temporary.appendingPathComponent(copyNoteFile))
            try fileManager.moveItem(at: temporary, to: current)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private static func isDirectory(_ url: URL, _ fileManager: FileManager) -> Bool {
        var directory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    /// İçinde `.DS_Store` dışında hiçbir şey yok mu. Okunamıyorsa boş sayılmaz (temkinli).
    private static func isEmpty(_ url: URL, _ fileManager: FileManager) -> Bool {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: url.path) else { return false }
        return entries.allSatisfy { $0 == ".DS_Store" }
    }

    /// Yalnız boş klasörü siler (`rmdir`: içinde bir şey varsa hata verir).
    private static func removeEmpty(_ url: URL, _ fileManager: FileManager) {
        guard isEmpty(url, fileManager) else { return }
        try? fileManager.removeItem(at: url.appendingPathComponent(".DS_Store"))
        rmdir(url.path)
    }
}
