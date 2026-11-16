// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Nino'nun ortak altyazı havuzu istemcisi. Pakette bulunmayan İngilizce oyun satırları cihazda kalıcı bir kuyruğa
/// yazılır ve sunucu "aldım" diyene kadar orada kalır. Kayıp olmaması için:
///
/// 1. Her satır görüldüğü anda `pending.jsonl` dosyasının sonuna eklenir (uygulama çökse de diskte kalır).
/// 2. Gönderim zamanı gelince bekleyenler aynı (oyun, oturum, metin) için sayılarak birleştirilir ve kimliği olan
///    parçalar hâlinde `outbox/` klasörüne yazılır. Parça, sunucu kimliğini geri söyleyene kadar silinmez; yanıt
///    kaybolursa aynı kimlikle yeniden gider, sunucu onu ikinci kez saymaz.
/// 3. Ağ yoksa ya da sunucu hata verirse artan aralıklarla (30 sn → 1 sa) yeniden denenir; ağ gelince hemen denenir.
///    Sunucu "bekle" derse (429) istediği kadar beklenir.
/// 4. Sunucunun biçimini kabul etmediği parça (400) silinmez, `parked/` klasörüne alınır; uygulama güncellenince
///    yeniden denenir. Çok büyük parça (413) ikiye bölünür.
/// 5. Canlı sunucu adresi yoksa satırlar kuyrukta bekler.
///
/// Giden: satırın metni, varsa oyun ipucu (son eşleşen paket), uygulamanın her açılışta ürettiği rastgele oturum kimliği,
/// kaç kez ve ne zaman görüldüğü, kuruluma özgü rastgele kimlik, uygulama sürümü ve platform. Kişisel veri yok.
public actor NinoPool {
    /// Canlı havuz sunucusu (Cloudflare Workers, nino-pool/). Denemede `NINO_POOL_URL` ortam değişkeni ya da
    /// `ninoPoolURL` ayarı ile başka adres verilir.
    public static let liveEndpoint: URL? = URL(string: "https://nino-pool.y-demirbag2506.workers.dev")
    public static let defaultsKey = "ninoPoolURL"
    /// Uygulamanın bu aralıkla `flush()` çağırması yeter; asıl zamanlamayı havuz kendisi yapar.
    public static let tickInterval: TimeInterval = 60
    /// Gönderim en erken bu kadar biriktirince yapılır (ya da en eski satır bu kadar bekleyince).
    public static let sendEvery: TimeInterval = 120

    public struct Limits: Sendable {
        public var batchSize = 200
        /// Bekleyen satır dosyası bu boyutu aşarsa yeni satır yazılmaz (ör. aylarca çevrimdışı kalan cihaz).
        public var maxPendingBytes = 64 * 1024 * 1024
        /// En çok bu kadar parça bekletilir (200 satırla ~400 000 satır).
        public var maxOutbox = 2000
        public var maxTextLength = 500
        public var maxRejectedBytes = 1024 * 1024
        public var backoffBase: TimeInterval = 30
        public var backoffMax: TimeInterval = 3600
        public init() {}
    }

    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Diskteki küçük durum dosyası.
    struct State: Codable {
        var install: String
        /// Bu sıra numarasına kadarki bekleyen satırlar parçalara aktarıldı.
        var frozenThrough: Int64 = 0
        var failures: Int = 0
        var nextAttempt: Double = 0
        var serverRetryAt: Double = 0
        var app: String = ""
        var dropped: Int = 0
    }

    /// `pending.jsonl` içindeki tek görülme.
    struct Sighting: Codable {
        var s: Int64
        var t: String
        var g: String?
        var e: String?
        var a: Double
    }

    /// Sunucuya giden satır (biçim: nino-pool/README.md).
    struct WireLine: Codable, Equatable {
        var text: String
        var game: String?
        var session: String?
        var count: Int
        var first: Int64
        var last: Int64
    }

    /// `outbox/` içindeki parça: gönderilen gövdenin aynısı + hangi sıraya kadar kapsadığı.
    struct Batch: Codable {
        var v = 1
        var batch: String
        var install: String
        var app: String
        var platform: String
        var lines: [WireLine]
        var upTo: Int64
    }

    struct Reply: Decodable {
        var ok: Bool
        var batch: String?
        var rejected: [Rejected]?
        struct Rejected: Decodable { var i: Int; var reason: String }
    }

    public struct Status: Sendable, Equatable {
        public var pendingLines: Int
        public var outboxBatches: Int
        public var parkedBatches: Int
        public var dropped: Int
        public var hasEndpoint: Bool
    }

    private let directory: URL
    private let app: String
    private let platform: String
    private let send: Send
    private let clock: @Sendable () -> Date
    private let limits: Limits
    private let session = UUID().uuidString.lowercased()
    private var endpoint: URL?
    private var state: State
    private var nextSeq: Int64
    private var pendingBytes: Int
    private var pendingCount: Int
    private var oldestPending: Double?
    private var handle: FileHandle?
    private var flushing = false
    public private(set) var isEnabled: Bool

    private var stateFile: URL { directory.appendingPathComponent("state.json") }
    private var pendingFile: URL { directory.appendingPathComponent("pending.jsonl") }
    private var outboxDir: URL { directory.appendingPathComponent("outbox", isDirectory: true) }
    private var parkedDir: URL { directory.appendingPathComponent("parked", isDirectory: true) }
    private var rejectedFile: URL { directory.appendingPathComponent("rejected.jsonl") }

    /// Adres: `NINO_POOL_URL` ortam değişkeni, sonra `ninoPoolURL` ayarı, sonra `liveEndpoint`.
    public static func configuredEndpoint(environment: [String: String] = ProcessInfo.processInfo.environment,
                                          defaults: UserDefaults = .standard) -> URL? {
        for value in [environment["NINO_POOL_URL"], defaults.string(forKey: defaultsKey)] {
            if let value, let url = URL(string: value.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true {
                return url
            }
        }
        return liveEndpoint
    }

    /// - Parameters:
    ///   - directory: havuzun klasörü (ör. Application Support/Nino/pool).
    ///   - legacyFile: CouchSubs'tan kalan `pool.json`; içindeki gönderilmemiş satırlar bir kez kuyruğa alınır.
    public init(directory: URL, endpoint: URL? = NinoPool.configuredEndpoint(), app: String, platform: String,
                enabled: Bool = true, legacyFile: URL? = nil, limits: Limits = Limits(),
                send: @escaping Send = { try await URLSession.shared.data(for: $0) },
                clock: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.endpoint = endpoint
        self.app = app
        self.platform = platform
        self.send = send
        self.clock = clock
        self.limits = limits
        isEnabled = enabled
        let fm = FileManager.default
        for dir in [directory, directory.appendingPathComponent("outbox"), directory.appendingPathComponent("parked")] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let stateFile = directory.appendingPathComponent("state.json")
        var loaded: State
        if let data = try? Data(contentsOf: stateFile), let saved = try? JSONDecoder().decode(State.self, from: data) {
            loaded = saved
        } else {
            if fm.fileExists(atPath: stateFile.path) {
                // Okunamayan durum dosyası silinmez, yanına saklanır; satırlar ayrı dosyalarda olduğundan kaybolmaz.
                try? fm.moveItem(at: stateFile, to: directory.appendingPathComponent("state.broken-\(Int(clock().timeIntervalSince1970)).json"))
            }
            loaded = State(install: UUID().uuidString.lowercased())
        }
        // Parça yazılıp durum yazılamadan kapanmışsa: parçaların kapsadığı sıra numarası esastır.
        for batch in Self.batchFiles(in: directory.appendingPathComponent("outbox")) {
            if let upTo = Self.readBatch(batch)?.upTo { loaded.frozenThrough = max(loaded.frozenThrough, upTo) }
        }
        // Uygulama güncellendiyse: kabul edilmemiş parçalar yeniden denenir.
        if loaded.app != app {
            for file in Self.batchFiles(in: directory.appendingPathComponent("parked")) {
                try? fm.moveItem(at: file, to: directory.appendingPathComponent("outbox").appendingPathComponent(file.lastPathComponent))
            }
            loaded.app = app
        }
        // Açılışta hemen denenir (sunucunun istediği bekleme korunur).
        loaded.failures = 0
        loaded.nextAttempt = 0
        let pending = directory.appendingPathComponent("pending.jsonl")
        // `enabled: false` yalnız bu çalışmada etkisiz olmak demek (test, klip): kuyruk silinmez. Kullanıcı havuzu
        // kapatınca silme `setEnabled(false)` ile yapılır.
        Self.repairPending(pending)
        var scan = Self.scanPending(pending, after: loaded.frozenThrough)
        if enabled, let legacyFile {
            Self.importLegacy(legacyFile, into: pending, firstSeq: max(scan.maxSeq, loaded.frozenThrough) + 1,
                              maxLength: limits.maxTextLength, now: clock().timeIntervalSince1970)
            scan = Self.scanPending(pending, after: loaded.frozenThrough)
        }
        state = loaded
        nextSeq = max(scan.maxSeq, loaded.frozenThrough) + 1
        pendingBytes = scan.bytes
        pendingCount = scan.count
        oldestPending = scan.oldest
        Self.write(loaded, to: stateFile)
    }

    public var installID: String { state.install }
    public var sessionID: String { session }

    public func status() -> Status {
        Status(pendingLines: pendingCount, outboxBatches: Self.batchFiles(in: outboxDir).count,
               parkedBatches: Self.batchFiles(in: parkedDir).count, dropped: state.dropped, hasEndpoint: endpoint != nil)
    }

    public func setEndpoint(_ url: URL?) {
        endpoint = url
        state.failures = 0
        state.nextAttempt = 0
        writeState()
    }

    /// Kapatılınca bekleyen her şey silinir: kullanıcı vazgeçtiyse hiçbir şey gitmez.
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { wipe() }
    }

    /// Okunan (pakette bulunmayan) satırı kuyruğa yazar. `game`: varsa oyun ipucu (paket kimliği).
    @discardableResult
    public func offer(_ raw: String, game: String? = nil) -> Bool {
        guard isEnabled else { return false }
        let text = Self.clean(raw)
        guard Self.accepts(text, maxLength: limits.maxTextLength) else { return false }
        return append(text: text, game: Self.gameID(game), session: session, at: clock().timeIntervalSince1970)
    }

    /// Zamanı geldiyse bekleyenleri parçalara aktarır ve gönderir. Sık çağrılabilir (ör. dakikada bir).
    public func flush(force: Bool = false) async {
        guard isEnabled, let endpoint, !flushing else { return }
        let now = clock().timeIntervalSince1970
        guard now >= state.nextAttempt, now >= state.serverRetryAt else { return }
        flushing = true
        defer { flushing = false }
        let due = force || pendingCount >= limits.batchSize || (oldestPending.map { now - $0 >= Self.sendEvery } ?? false)
        if due { freeze() }
        await sendOutbox(to: endpoint)
    }

    /// Ağ yeniden geldi: artan bekleme sıfırlanır ve hemen denenir (sunucunun istediği bekleme korunur).
    public func networkAvailable() async {
        state.failures = 0
        state.nextAttempt = 0
        writeState()
        await flush()
    }

    /// Bekleyen satırların dosyası kapatılır (uygulama kapanırken). Satırlar zaten diskte.
    public func close() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        writeState()
    }

    // MARK: - Süzgeç

    /// Havuza uygun satır: harf içeriyor, en çok 500 karakter, yazı tanıma çöpü değil; Türkçe, PS5 sistem yazısı
    /// (ör. "X signed in": PSN adı taşıyabilir) ya da yarım okuma değil (`PoolFilter`).
    public static func accepts(_ text: String, maxLength: Int = 500) -> Bool {
        guard !text.isEmpty, text.unicodeScalars.count <= maxLength, text.contains(where: \.isLetter) else { return false }
        return !LinePool.looksLikeNoise(text) && PoolFilter.accepts(text)
    }

    static func clean(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 0x00...0x1F, 0x7F...0x9F, 0x200B...0x200F, 0x2028, 0x2029, 0xFEFF: " "
            default: Character(scalar)
            }
        }
        return String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Paket kimliği sunucunun beklediği biçimde: küçük harf, harf/rakam/.-_ dışı tire, en çok 64 karakter.
    static func gameID(_ game: String?) -> String? {
        guard let game else { return nil }
        let mapped = String(game.lowercased().map { ch -> Character in
            (ch.isASCII && (ch.isLetter || ch.isNumber)) || ch == "." || ch == "_" || ch == "-" ? ch : "-"
        }).trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return mapped.isEmpty ? nil : String(mapped.prefix(64))
    }

    // MARK: - Bekleyenler

    private func append(text: String, game: String?, session: String?, at: Double) -> Bool {
        guard pendingBytes < limits.maxPendingBytes else {
            state.dropped += 1
            writeState()
            return false
        }
        let record = Sighting(s: nextSeq, t: text, g: game, e: session, a: at)
        guard var data = try? JSONEncoder().encode(record) else { return false }
        data.append(0x0A)
        do {
            let handle = try openPending()
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            handle = nil
            return false
        }
        nextSeq += 1
        pendingBytes += data.count
        pendingCount += 1
        if oldestPending == nil { oldestPending = at }
        return true
    }

    private func openPending() throws -> FileHandle {
        if let handle { return handle }
        if !FileManager.default.fileExists(atPath: pendingFile.path) {
            FileManager.default.createFile(atPath: pendingFile.path, contents: nil)
        }
        let opened = try FileHandle(forWritingTo: pendingFile)
        handle = opened
        return opened
    }

    /// Çökmede yarım kalan son satır kesilir; yoksa sonraki satır ona yapışıp onu da bozardı.
    static func repairPending(_ file: URL) {
        guard let data = try? Data(contentsOf: file), let last = data.last, last != 0x0A else { return }
        let keep = data.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        try? handle.truncate(atOffset: UInt64(keep))
        try? handle.close()
    }

    static func scanPending(_ file: URL, after: Int64) -> (sightings: [Sighting], maxSeq: Int64, bytes: Int, count: Int, oldest: Double?) {
        guard let data = try? Data(contentsOf: file) else { return ([], 0, 0, 0, nil) }
        let decoder = JSONDecoder()
        var list: [Sighting] = []
        var maxSeq: Int64 = 0
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            // Yarım yazılmış son satır (çökme) atlanır.
            guard let sighting = try? decoder.decode(Sighting.self, from: Data(line)) else { continue }
            maxSeq = max(maxSeq, sighting.s)
            if sighting.s > after { list.append(sighting) }
        }
        return (list, maxSeq, data.count, list.count, list.map(\.a).min())
    }

    /// Bekleyenleri birleştirip parçalara yazar; parçalar diske yazılmadan bekleyenler silinmez.
    private func freeze() {
        guard pendingCount > 0 else { return }
        let outboxCount = Self.batchFiles(in: outboxDir).count
        guard outboxCount < limits.maxOutbox else { return }
        try? handle?.synchronize()
        let scan = Self.scanPending(pendingFile, after: state.frozenThrough)
        guard !scan.sightings.isEmpty else {
            compactPending()
            return
        }
        // Parçalar sıra numarasına göre ardışık dilimlerdir: her parçanın `upTo`'su yalnız kendi kapsadığı son satırdır,
        // birleştirme parça sınırını aşmaz. Parçalar sırayla yazıldığından, yarıda çökülse de yazılmamış parçaların
        // satırları bekleyenlerde kalır (açılışta en büyük `upTo` esas alınır).
        let stamp = Int64(clock().timeIntervalSince1970 * 1000)
        var chunks: [(lines: [WireLine], upTo: Int64)] = []
        var merged: [String: Int] = [:]
        var lines: [WireLine] = []
        var last = state.frozenThrough
        for sighting in scan.sightings.sorted(by: { $0.s < $1.s }) {
            let id = "\(sighting.g ?? "")\u{0}\(sighting.e ?? "")\u{0}\(sighting.t)"
            let at = Int64(sighting.a)
            if let index = merged[id] {
                lines[index].count += 1
                lines[index].first = min(lines[index].first, at)
                lines[index].last = max(lines[index].last, at)
            } else {
                if lines.count == limits.batchSize {
                    chunks.append((lines, last))
                    lines = []
                    merged = [:]
                }
                merged[id] = lines.count
                lines.append(WireLine(text: sighting.t, game: sighting.g, session: sighting.e, count: 1, first: at, last: at))
            }
            last = sighting.s
        }
        if !lines.isEmpty { chunks.append((lines, last)) }
        for (index, chunk) in chunks.enumerated() {
            let batch = Batch(batch: UUID().uuidString.lowercased(), install: state.install, app: app, platform: platform,
                              lines: chunk.lines, upTo: chunk.upTo)
            let url = outboxDir.appendingPathComponent(String(format: "%015lld-%04d-%@.json", stamp, index, batch.batch))
            // Yazılamadıysa (disk dolu): yazılan parçalar kalır, gerisi bekleyenlerde sürer.
            guard writeBatch(batch, to: url) else { break }
            state.frozenThrough = chunk.upTo
        }
        writeState()
        compactPending()
    }

    /// Parçalara aktarılmış satırları bekleyenler dosyasından atar.
    private func compactPending() {
        try? handle?.close()
        handle = nil
        let scan = Self.scanPending(pendingFile, after: state.frozenThrough)
        let encoder = JSONEncoder()
        var data = Data()
        for sighting in scan.sightings {
            if let line = try? encoder.encode(sighting) { data.append(line); data.append(0x0A) }
        }
        if (try? data.write(to: pendingFile, options: .atomic)) != nil {
            pendingBytes = data.count
        }
        pendingCount = scan.sightings.count
        oldestPending = scan.sightings.map(\.a).min()
    }

    // MARK: - Gönderim

    private func sendOutbox(to endpoint: URL) async {
        // Aynı tur içinde ikinci kez görülen dosya (taşınamadı, bölünemedi) bir sonraki tura kalır.
        var tried = Set<String>()
        while isEnabled {
            guard let file = Self.batchFiles(in: outboxDir).first(where: { !tried.contains($0.lastPathComponent) }) else { return }
            tried.insert(file.lastPathComponent)
            guard let batch = Self.readBatch(file) else {
                // Bozuk parça dosyası silinmez, kenara alınır.
                park(file)
                continue
            }
            var request = URLRequest(url: endpoint.appendingPathComponent("v1/batches"), timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("nino-pool/1 (\(platform); \(app))", forHTTPHeaderField: "User-Agent")
            request.httpBody = try? Self.encoder.encode(batch)
            let reply: (Data, URLResponse)
            do {
                reply = try await send(request)
            } catch {
                failed()
                return
            }
            guard let http = reply.1 as? HTTPURLResponse else {
                failed()
                return
            }
            let now = clock().timeIntervalSince1970
            switch http.statusCode {
            case 200..<300:
                guard let body = try? JSONDecoder().decode(Reply.self, from: reply.0), body.ok,
                      body.batch?.lowercased() == batch.batch else {
                    // "Tamam" dese de bizim sunucumuz değilse (yanlış adres) parça silinmez.
                    failed()
                    return
                }
                recordRejected(body.rejected ?? [], in: batch)
                try? FileManager.default.removeItem(at: file)
                state.failures = 0
                state.nextAttempt = 0
                writeState()
            case 413:
                if batch.lines.count > 1 { split(file, batch) } else { park(file) }
            case 429, 503:
                let wait = Self.retryDelay(http.value(forHTTPHeaderField: "Retry-After"), now: Date(timeIntervalSince1970: now))
                state.serverRetryAt = now + wait
                writeState()
                return
            case 400, 422:
                park(file)
            default:
                // Adres yanlış (404), yetki (401/403) ya da sunucu hatası: parça kalır, sonra yeniden denenir.
                failed()
                return
            }
        }
    }

    private func failed() {
        state.failures += 1
        let exponent = min(state.failures - 1, 16)
        let delay = min(limits.backoffBase * pow(2, Double(exponent)), limits.backoffMax)
        let jitter = delay * Double.random(in: -0.2...0.2)
        state.nextAttempt = clock().timeIntervalSince1970 + delay + jitter
        writeState()
    }

    private func split(_ file: URL, _ batch: Batch) {
        let half = batch.lines.count / 2
        let name = file.deletingPathExtension().lastPathComponent
        for (index, part) in [Array(batch.lines[..<half]), Array(batch.lines[half...])].enumerated() {
            var piece = batch
            piece.batch = UUID().uuidString.lowercased()
            piece.lines = part
            let url = outboxDir.appendingPathComponent("\(name.prefix(20))-\(index)-\(piece.batch).json")
            guard writeBatch(piece, to: url) else { return }
        }
        try? FileManager.default.removeItem(at: file)
    }

    private func park(_ file: URL) {
        try? FileManager.default.removeItem(at: parkedDir.appendingPathComponent(file.lastPathComponent))
        try? FileManager.default.moveItem(at: file, to: parkedDir.appendingPathComponent(file.lastPathComponent))
    }

    private func recordRejected(_ rejected: [Reply.Rejected], in batch: Batch) {
        guard !rejected.isEmpty else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: rejectedFile.path)[.size] as? Int) ?? 0
        guard size < limits.maxRejectedBytes else { return }
        var data = Data()
        for item in rejected where batch.lines.indices.contains(item.i) {
            let entry = ["reason": item.reason, "text": batch.lines[item.i].text]
            if let line = try? JSONSerialization.data(withJSONObject: entry) { data.append(line); data.append(0x0A) }
        }
        if !FileManager.default.fileExists(atPath: rejectedFile.path) {
            FileManager.default.createFile(atPath: rejectedFile.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: rejectedFile) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }

    // MARK: - Eski CouchSubs kuyruğu

    struct LegacyState: Decodable {
        struct Line: Decodable { var text: String; var firstSeen: String? }
        var queue: [Line]
    }

    /// CouchSubs'tan kalan `pool.json` kuyruğundaki (henüz gönderilmemiş) satırlar bir kez bekleyenlere eklenir,
    /// dosya `.imported` adıyla kenara konur.
    static func importLegacy(_ file: URL, into pending: URL, firstSeq: Int64, maxLength: Int, now: Double) {
        guard let data = try? Data(contentsOf: file) else { return }
        if let legacy = try? JSONDecoder().decode(LegacyState.self, from: data) {
            let formatter = ISO8601DateFormatter()
            let encoder = JSONEncoder()
            var out = Data()
            var seq = firstSeq
            for line in legacy.queue {
                let text = clean(line.text)
                guard accepts(text, maxLength: maxLength) else { continue }
                let at = line.firstSeen.flatMap(formatter.date)?.timeIntervalSince1970 ?? now
                guard let record = try? encoder.encode(Sighting(s: seq, t: text, g: nil, e: nil, a: at)) else { continue }
                out.append(record)
                out.append(0x0A)
                seq += 1
            }
            guard appendData(out, to: pending) else { return }
        }
        let moved = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".imported")
        try? FileManager.default.removeItem(at: moved)
        try? FileManager.default.moveItem(at: file, to: moved)
    }

    static func appendData(_ data: Data, to file: URL) -> Bool {
        if data.isEmpty { return true }
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: file) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Dosyalar

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static func batchFiles(in directory: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func readBatch(_ file: URL) -> Batch? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Batch.self, from: $0) }
    }

    private func writeBatch(_ batch: Batch, to url: URL) -> Bool {
        guard let data = try? Self.encoder.encode(batch) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    private func writeState() { Self.write(state, to: stateFile) }

    static func write(_ state: State, to file: URL) {
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: file, options: .atomic) }
    }

    /// Bekleyen, gönderilecek ve kenara alınmış bütün satırları siler (kullanıcı havuzu kapattı).
    static func removeQueued(in directory: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: directory.appendingPathComponent("pending.jsonl"))
        try? fm.removeItem(at: directory.appendingPathComponent("rejected.jsonl"))
        for name in ["outbox", "parked"] {
            let dir = directory.appendingPathComponent(name, isDirectory: true)
            for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: file) }
        }
    }

    private func wipe() {
        try? handle?.close()
        handle = nil
        Self.removeQueued(in: directory)
        pendingBytes = 0
        pendingCount = 0
        oldestPending = nil
        state.failures = 0
        state.nextAttempt = 0
        state.serverRetryAt = 0
        writeState()
    }

    /// `Retry-After`: saniye ya da HTTP tarihi; yoksa bir dakika, en çok bir gün.
    static func retryDelay(_ header: String?, now: Date) -> TimeInterval {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return 60 }
        if let seconds = Double(header) { return min(max(seconds, 1), 86400) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: header) else { return 60 }
        return min(max(date.timeIntervalSince(now), 1), 86400)
    }
}
