// SPDX-License-Identifier: AGPL-3.0-only
// Nino çeviri havuzu (sunucu: nino-pool/src/translate.js). Oyun satırlarının sunucuda Claude ile yapılmış çevirileri:
//   - oyun başlarken o oyunun bütün çevirileri tek seferde, sonra birkaç dakikada bir yalnız değişenler iner;
//   - pakette ve havuzda olmayan satır sunucuya sorulur; sunucu o an çevirir, herkes için saklar.
// Havuzdaki çeviri, hazır paketten sonra ve cihazın kendi çevirisinden önce kullanılır (11 dilin hepsinde).
// Ayarlar'daki ortak havuz kapalıysa hiçbir şey gönderilmez ve indirilmez.

import Foundation

/// Bellekteki çeviriler (anahtar → çeviri). Altyazı hattı eşzamanlı sorduğu için kilitli; diske dil başına yazılır.
public final class PoolTranslations: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String: String] = [:]
    private var language = ""

    public init() {}

    /// Satırın havuzdaki çevirisi (yoksa nil). Anahtar oyun paketleriyle ve sunucuyla aynı (`PackKey`).
    public func match(_ source: String) -> String? {
        guard let key = PackKey.key(source) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return texts[key]
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return texts.count
    }

    func replace(language: String, texts new: [String: String]) {
        lock.lock()
        self.language = language
        texts = new
        lock.unlock()
    }

    /// Yalnız aynı dilin çevirileri eklenir (dil değişirken gelen eski cevap karışmasın).
    func merge(language: String, _ items: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        guard language == self.language else { return }
        texts.merge(items) { _, new in new }
    }

    func snapshot() -> (language: String, texts: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        return (language, texts)
    }
}

public actor TranslationPool {
    /// Sunucudan gelen ayar (`GET /v1/config`); sunucuya ulaşılamazsa bu varsayılanlar.
    public struct Config: Codable, Equatable, Sendable {
        public var enabled = true
        public var deadlineMs = 900
        public var syncSeconds = 180
        public var contextLines = 4
        public var maxLines = 12
        public init() {}
    }

    struct Cursor: Codable, Equatable {
        var since: Int = 0
        var after: String = ""
        var checked: Double = 0
    }

    struct Saved: Codable {
        var language: String
        var texts: [String: String]
        var cursors: [String: Cursor]
    }

    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Altyazı hattının eşzamanlı baktığı çeviriler.
    public nonisolated let store = PoolTranslations()
    public private(set) var config = Config()
    public private(set) var isEnabled: Bool

    private let directory: URL
    private var endpoint: URL?
    private let install: String
    private let app: String
    private let platform: String
    private let send: Send
    private let clock: @Sendable () -> Date
    private var language: String
    private var cursors: [String: Cursor] = [:]
    private var configChecked: Double = 0
    private var inFlight: [String: Task<String?, Never>] = [:]
    private var dirty = false

    /// Sunucudan en çok bu kadar çeviri tutulur (dil başına); fazlası diske yazılmaz.
    static let maxStored = 400_000

    /// - Parameter install: kuruluma özgü rastgele kimlik (sunucuda yalnız tuzlanmış özetiyle, kaba hız sınırı için);
    ///   verilmezse klasördeki `install` dosyasından okunur ya da üretilir.
    public init(directory: URL, endpoint: URL? = NinoPool.configuredEndpoint(), install: String? = nil, app: String, platform: String,
                language: String, enabled: Bool = true,
                send: @escaping Send = { try await URLSession.shared.data(for: $0) },
                clock: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.endpoint = endpoint
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.install = install ?? Self.installID(in: directory)
        self.app = app
        self.platform = platform
        self.send = send
        self.clock = clock
        self.language = Self.code(language)
        isEnabled = enabled
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let saved = Self.load(directory: directory, language: self.language)
        cursors = saved?.cursors ?? [:]
        store.replace(language: self.language, texts: enabled ? saved?.texts ?? [:] : [:])
    }

    private static func installID(in directory: URL) -> String {
        let file = directory.appendingPathComponent("install")
        if let saved = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           UUID(uuidString: saved) != nil { return saved.lowercased() }
        let made = UUID().uuidString.lowercased()
        try? made.write(to: file, atomically: true, encoding: .utf8)
        return made
    }

    static func code(_ language: String) -> String {
        String(language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }

    private static func file(_ directory: URL, _ language: String) -> URL {
        directory.appendingPathComponent("translations-\(language).json")
    }

    private static func load(directory: URL, language: String) -> Saved? {
        guard let data = try? Data(contentsOf: file(directory, language)) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    // MARK: - Ayar

    /// Hedef dil değişince o dilin çevirileri yüklenir.
    public func setLanguage(_ value: String) {
        let code = Self.code(value)
        guard code != language else { return }
        save()
        language = code
        let saved = Self.load(directory: directory, language: code)
        cursors = saved?.cursors ?? [:]
        store.replace(language: code, texts: isEnabled ? saved?.texts ?? [:] : [:])
    }

    /// Kullanıcı ortak havuzu kapatınca hiçbir şey sorulmaz ve indirilen çeviriler kullanılmaz.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        // Kapatmadan önce yazılır; kapalıyken diskteki çeviriler boş listeyle ezilmez (bkz. `save`).
        if !enabled { save() }
        isEnabled = enabled
        let saved = enabled ? Self.load(directory: directory, language: language) : nil
        store.replace(language: language, texts: saved?.texts ?? [:])
    }

    public func setEndpoint(_ url: URL?) { endpoint = url }

    /// Havuz şu an kullanılabilir mi (ayar açık, sunucu açık, adres var).
    public var isActive: Bool { isEnabled && config.enabled && endpoint != nil }

    /// Sunucunun ayarını en çok 10 dakikada bir sorar.
    public func refreshConfig(force: Bool = false) async {
        guard let endpoint else { return }
        let now = clock().timeIntervalSince1970
        guard force || now - configChecked > 600 else { return }
        configChecked = now
        struct Reply: Decodable { var translate: Config? }
        guard let data = await get(endpoint.appendingPathComponent("v1/config")),
              let reply = try? JSONDecoder().decode(Reply.self, from: data), let translate = reply.translate else { return }
        config = translate
    }

    // MARK: - Toplu indirme

    /// Oyunun yeni çevirilerini indirir (oyun başlarken hemen, sonra `syncSeconds` aralıkla). `game` yoksa bütün oyunlar.
    @discardableResult
    public func sync(game rawGame: String?, force: Bool = false) async -> Int {
        await refreshConfig()
        guard isActive, let endpoint else { return 0 }
        let game = NinoPool.gameID(rawGame) ?? ""
        let lang = language
        var cursor = cursors[game] ?? Cursor()
        let now = clock().timeIntervalSince1970
        guard force || now - cursor.checked >= Double(max(30, config.syncSeconds)) else { return 0 }
        cursor.checked = now
        cursors[game] = cursor
        var added = 0
        for _ in 0..<50 {
            var components = URLComponents(url: endpoint.appendingPathComponent("v1/translations"), resolvingAgainstBaseURL: false)
            var query = [URLQueryItem(name: "lang", value: lang), URLQueryItem(name: "since", value: String(cursor.since))]
            if !game.isEmpty { query.append(URLQueryItem(name: "game", value: game)) }
            if !cursor.after.isEmpty { query.append(URLQueryItem(name: "after", value: cursor.after)) }
            components?.queryItems = query
            guard let url = components?.url, let data = await get(url) else { break }
            struct Page: Decodable {
                struct Next: Decodable { var since: Int; var after: String }
                var items: [[Item]]
                var next: Next?
            }
            guard let page = try? JSONDecoder().decode(Page.self, from: data), lang == language else { break }
            var items: [String: String] = [:]
            var newest = cursor.since
            for row in page.items where row.count >= 3 {
                guard case .text(let key) = row[0], case .text(let text) = row[1], case .number(let updated) = row[2] else { continue }
                items[key] = text
                newest = max(newest, updated)
            }
            store.merge(language: lang, items)
            added += items.count
            if !items.isEmpty { dirty = true }
            if let next = page.next {
                cursor.since = next.since
                cursor.after = next.after
            } else {
                cursor.since = newest
                cursor.after = ""
                break
            }
        }
        cursors[game] = cursor
        if dirty { save() }
        return added
    }

    /// Sayfadaki karışık dizi öğesi ([anahtar, çeviri, zaman, aşama]).
    enum Item: Decodable {
        case text(String), number(Int)
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let n = try? value.decode(Int.self) { self = .number(n) } else { self = .text(try value.decode(String.self)) }
        }
    }

    // MARK: - Anında çeviri

    /// Satırı sunucuya sorar; sunucu biliyorsa ya da o an çevirirse çeviri döner ve havuza eklenir. Aynı satır aynı anda
    /// iki kez sorulmaz. Ulaşılamazsa, sınır dolduysa ya da havuz kapalıysa nil.
    public func translate(_ line: String, context: [String] = [], game rawGame: String? = nil) async -> String? {
        await refreshConfig()
        guard isActive, let endpoint, NinoPool.accepts(NinoPool.clean(line)), let key = PackKey.key(line) else { return nil }
        if let known = store.match(line) { return known }
        let lang = language
        let flightKey = lang + "\u{1F}" + key
        if let running = inFlight[flightKey] { return await running.value }
        let body: [String: Any] = [
            "v": 1, "install": install, "app": app, "platform": platform, "lang": lang,
            "game": NinoPool.gameID(rawGame) ?? "", "lines": [line],
            "context": Array(context.suffix(max(0, config.contextLines))),
        ]
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/translate"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("nino-pool/1 (\(platform); \(app))", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let send = self.send
        let task = Task<String?, Never> {
            guard let (data, response) = try? await send(request), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            struct Reply: Decodable {
                struct Line: Decodable { var text: String? }
                var translations: [Line]
            }
            return (try? JSONDecoder().decode(Reply.self, from: data))?.translations.first?.text
        }
        inFlight[flightKey] = task
        let result = await task.value
        inFlight[flightKey] = nil
        if let result, !result.isEmpty {
            store.merge(language: lang, [key: result])
            dirty = true
        }
        return result
    }

    // MARK: - Oyunu ekrandan tanıma

    /// Remote Play karesinden oyunu tanır (sunucuda Claude). `jpeg`: küçültülmüş kare (≤ 450 KB). Tanınamazsa nil.
    public func identify(jpeg: Data) async -> String? {
        guard isEnabled, let endpoint, jpeg.count <= 450 * 1024 else { return nil }
        let body: [String: Any] = ["v": 1, "install": install, "app": app, "platform": platform, "image": jpeg.base64EncodedString()]
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/identify"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("nino-pool/1 (\(platform); \(app))", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await send(request), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        struct Reply: Decodable { var game: String? }
        return (try? JSONDecoder().decode(Reply.self, from: data))?.game
    }

    // MARK: - Panel

    /// Çeviri sürerken dakikada bir "buradayım" (Nino panelindeki "şu an oynayan"). Havuz kapalıysa gönderilmez.
    public func ping(game rawGame: String?) async {
        guard isEnabled, let endpoint else { return }
        var components = URLComponents(url: endpoint.appendingPathComponent("v1/ping"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "install", value: install), URLQueryItem(name: "platform", value: platform),
            URLQueryItem(name: "app", value: app), URLQueryItem(name: "game", value: NinoPool.gameID(rawGame) ?? ""),
            URLQueryItem(name: "lang", value: language),
        ]
        guard let url = components?.url else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("nino-pool/1 (\(platform); \(app))", forHTTPHeaderField: "User-Agent")
        _ = try? await send(request)
    }

    // MARK: - Disk

    /// Çevirileri diske yazar (indirmeden sonra ve kapanırken).
    public func save() {
        guard dirty, isEnabled else { return }
        dirty = false
        let snapshot = store.snapshot()
        guard snapshot.language == language else { return }
        var texts = snapshot.texts
        if texts.count > Self.maxStored { texts = Dictionary(uniqueKeysWithValues: texts.prefix(Self.maxStored).map { ($0.key, $0.value) }) }
        let saved = Saved(language: language, texts: texts, cursors: cursors)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: Self.file(directory, language), options: .atomic)
    }

    private func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("nino-pool/1 (\(platform); \(app))", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await send(request), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

/// Havuza sorulan satırların bağlamı: son birkaç satır (çok eskiyse atılır). Sunucu kısa satırı ("Do it.") bununla
/// doğru hitap ve anlamla çevirir.
public final class PoolContext: @unchecked Sendable {
    public static let maxAge: TimeInterval = 30
    private let lock = NSLock()
    private var lines: [(text: String, at: Date)] = []
    private let clock: () -> Date

    public init(clock: @escaping () -> Date = Date.init) { self.clock = clock }

    /// Satırı ekler; ondan önceki (taze) satırları döner.
    public func add(_ text: String, keep: Int = 4) -> [String] {
        lock.withLock {
            let now = clock()
            lines.removeAll { now.timeIntervalSince($0.at) > Self.maxAge || $0.text == text }
            let context = lines.suffix(keep).map(\.text)
            lines.append((text, now))
            if lines.count > keep { lines.removeFirst(lines.count - keep) }
            return context
        }
    }
}
