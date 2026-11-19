// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Nino: "Nino'ya Sor" (kurulum yardımcısı). Sohbet Nino havuz sunucusuna (`POST /v1/assistant`,
/// nino-pool/src/assistant.js) gider; sunucu bilgi tabanıyla birlikte modele sorar ve cevabı döner. Mac ve iPhone aynı
/// kodu kullanır (görünüm platformda). Kuruluş kimliği, fotoğraf küçültme ve ağ kodu Sorun Bildir'inkiyle aynıdır
/// (ProblemReport.swift). Sohbet yalnız bellekte durur: uygulama kapanınca silinir.
public enum AssistantChat {
    /// Sunucunun sınırları (nino-pool ASSISTANT_LIMITS).
    public static let maxMessages = 24
    public static let maxTextLength = 2000
    public static let maxImagesPerMessage = 3
    /// Fotoğraflar yalnız fotoğraflı son iki kullanıcı mesajında gider; öncekiler "[screenshot]" yazısı olur.
    public static let imageMessages = 2
    public static let maxBodyBytes = 6 * 1024 * 1024
    public static let screenshotPlaceholder = "[screenshot]"

    public typealias Send = ProblemReport.Send

    public enum Role: String, Codable, Equatable, Sendable {
        case user, assistant
    }

    /// Sohbetteki bir mesaj (uygulamanın tuttuğu hali; fotoğraflar küçültülmüş JPEG).
    public struct Turn: Equatable, Sendable {
        public var role: Role
        public var text: String
        public var images: [Data]

        public init(role: Role, text: String, images: [Data] = []) {
            self.role = role
            self.text = text
            self.images = images
        }
    }

    /// Sunucuya giden mesaj.
    public struct Message: Codable, Equatable, Sendable {
        public var role: Role
        public var text: String
        public var images: [ProblemReport.Image]?
    }

    public struct Payload: Codable, Equatable, Sendable {
        public var v = 1
        public var install: String
        public var app: String
        public var platform: String
        public var language: String
        public var messages: [Message]
        /// Cihaz bilgileri (DeviceInfo.summary); yardımcı bildirim açarsa bildirime eklenir. Modele gönderilmez.
        public var device: String?

        public init(install: String, app: String, platform: String, language: String, turns: [Turn], device: String? = nil) {
            let device = String((device ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(DeviceInfo.maxLength))
            self.device = device.isEmpty ? nil : device
            self.install = install
            self.app = app
            self.platform = platform
            self.language = language
            messages = AssistantChat.messages(from: turns)
        }

        /// Son mesaj kullanıcınınsa ve boş değilse gönderilebilir (sunucu da başka türlüsünü kabul etmez).
        public var isSendable: Bool {
            guard let last = messages.last, last.role == .user else { return false }
            return !last.text.isEmpty || !(last.images ?? []).isEmpty
        }
    }

    /// Sunucunun cevabı. `report`: robot ekibe bildirim gönderdiyse onun kimliği.
    public struct Reply: Equatable, Sendable {
        public var text: String
        public var report: String?

        public init(text: String, report: String? = nil) {
            self.text = text
            self.report = report
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        /// Sunucuda model henüz ayarlanmadı (503 assistant_disabled).
        case disabled
        /// Bu kuruluş bugün çok soru sordu (429 rate_limited).
        case rateLimited
        /// Sunucunun günlük bütçesi doldu ya da çok yoğun (429 busy, 503).
        case busy
        /// Gövde ya da fotoğraf çok büyük (413 ya da gönderilmeden önce).
        case tooLarge
        /// Sunucu biçimi kabul etmedi (400).
        case rejected
        /// Model cevap veremedi ya da sunucu hatası (502, 5xx).
        case server(Int)
        /// Ağ yok ya da sunucuya ulaşılamadı.
        case offline
        /// Sunucu adresi yok.
        case noEndpoint

        /// Aynı mesajı yeniden denemek işe yarar mı (ağ ve sunucu hataları).
        public var isRetryable: Bool {
            switch self {
            case .offline, .server, .busy, .noEndpoint: true
            case .disabled, .rateLimited, .tooLarge, .rejected: false
            }
        }
    }

    // MARK: - İstek

    /// Uygulamadaki sohbetten sunucuya gidecek mesajlar: boş mesajlar atılır, en çok son 24 mesaj, her metin en çok 2000
    /// karakter, her mesajda en çok 3 fotoğraf; fotoğraflar yalnız fotoğraflı son iki kullanıcı mesajında gider,
    /// öncekilerde metne "[screenshot]" eklenir. İlk mesaj asistanınsa (ör. kırpılınca) atılmaz; sunucu kabul ediyor.
    public static func messages(from turns: [Turn], imageMessages: Int = imageMessages) -> [Message] {
        let turns = turns.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ($0.role == .user && !$0.images.isEmpty) }
            .suffix(maxMessages)
        var withImages = 0
        var result: [Message] = []
        for turn in turns.reversed() {
            var text = clip(turn.text.trimmingCharacters(in: .whitespacesAndNewlines))
            var images: [ProblemReport.Image]?
            if turn.role == .user, !turn.images.isEmpty {
                if withImages < imageMessages {
                    images = turn.images.prefix(maxImagesPerMessage).map(ProblemReport.Image.init(jpeg:))
                    withImages += 1
                } else {
                    text = clip(text.isEmpty ? screenshotPlaceholder : "\(screenshotPlaceholder) \(text)")
                }
            }
            result.append(Message(role: turn.role, text: text, images: images))
        }
        return result.reversed()
    }

    private static func clip(_ text: String) -> String {
        // Sunucu UTF-16 birimiyle sayar (JavaScript slice).
        guard text.utf16.count > maxTextLength else { return text }
        var end = text.utf16.index(text.utf16.startIndex, offsetBy: maxTextLength)
        while end > text.utf16.startIndex, String.Index(end, within: text) == nil { end = text.utf16.index(before: end) }
        return String(text[..<end])
    }

    public static func encode(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// `endpoint`: havuz sunucusunun kökü (NinoPool.configuredEndpoint()). Gövde 6 MB'yi geçerse önce yalnız son
    /// fotoğraflı mesajın fotoğrafları bırakılır, yine sığmazsa fotoğrafsız gönderilir.
    public static func request(for payload: Payload, endpoint: URL) throws -> URLRequest {
        guard payload.isSendable else { throw Failure.rejected }
        var payload = payload
        var body = try encode(payload)
        if body.count > maxBodyBytes {
            payload.messages = dropImages(payload.messages, keep: 1)
            body = try encode(payload)
        }
        guard body.count <= maxBodyBytes else { throw Failure.tooLarge }
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/assistant"), timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("nino-assistant/1 (\(payload.platform); \(payload.app))", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        return request
    }

    /// Son `keep` fotoğraflı mesaj dışındaki fotoğrafları "[screenshot]" yazısına çevirir.
    static func dropImages(_ messages: [Message], keep: Int) -> [Message] {
        var kept = 0
        return messages.reversed().map { message in
            guard let images = message.images, !images.isEmpty else { return message }
            if kept < keep { kept += 1; return message }
            var message = message
            message.images = nil
            message.text = clip(message.text.isEmpty ? screenshotPlaceholder : "\(screenshotPlaceholder) \(message.text)")
            return message
        }.reversed()
    }

    /// Sunucunun cevabını ya da hatasını çözer.
    public static func reply(data: Data, response: URLResponse) throws -> Reply {
        guard let http = response as? HTTPURLResponse else { throw Failure.offline }
        struct Body: Decodable { var ok: Bool?; var reply: String?; var report: String?; var error: String? }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        switch http.statusCode {
        case 200 ..< 300:
            guard body?.ok != false, let text = body?.reply?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw Failure.server(http.statusCode)
            }
            let report = body?.report.flatMap { $0.isEmpty ? nil : $0 }
            return Reply(text: text, report: report)
        case 400: throw Failure.rejected
        case 413: throw Failure.tooLarge
        case 429: throw body?.error == "busy" ? Failure.busy : Failure.rateLimited
        case 503: throw body?.error == "assistant_disabled" ? Failure.disabled : Failure.busy
        default: throw Failure.server(http.statusCode)
        }
    }

    /// Sohbeti gönderir; robotun cevabını döner.
    public static func send(_ payload: Payload, endpoint: URL? = NinoPool.configuredEndpoint(),
                            send: Send = { try await URLSession.shared.data(for: $0) }) async throws -> Reply {
        guard let endpoint else { throw Failure.noEndpoint }
        let request = try request(for: payload, endpoint: endpoint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(request)
        } catch {
            throw Failure.offline
        }
        return try reply(data: data, response: response)
    }

    // MARK: - Metin

    /// Robotun metnindeki bağlantılar (http/https ve "www."), tıklanabilir olsun diye. Sondaki noktalama dahil edilmez.
    public static func links(in text: String) -> [(range: Range<String.Index>, url: URL)] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let url = match.url, let range = Range(match.range, in: text),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return (range, url)
        }
    }

    /// Robotun cevabındaki bir blok: paragraf, numaralı adım ya da madde işaretli satır.
    public enum Block: Equatable, Sendable {
        case paragraph(String)
        /// `number`: yalnız rakamlar ("1"); balondaki yuvarlak rozette gösterilir.
        case step(number: String, text: String)
        case bullet(String)

        public var text: String {
            switch self {
            case .paragraph(let text), .step(_, let text), .bullet(let text): text
            }
        }

        public var isListItem: Bool {
            if case .paragraph = self { return false }
            return true
        }
    }

    private static let stepPattern = try! NSRegularExpression(pattern: #"^\s*([0-9]{1,2})[.)]\s+(\S.*)$"#)
    private static let bulletPattern = try! NSRegularExpression(pattern: #"^\s*[-•*]\s+(\S.*)$"#)

    /// Robotun cevabını bloklara ayırır (Mac ve iPhone balonu aynı yerleşimi çizer; Android'de NinoAssistant.blocks,
    /// Windows'ta NinoAssistant.Format aynı kurallarla). Boş satır blokları ayırır; "1." ya da "1)" ile başlayan satır
    /// numaralı adım (en çok iki basamak, "2024. yılında" adım sayılmaz), "-", "•" ya da "*" ile başlayan satır maddedir.
    /// Paragraf içindeki tek satır sonları korunur; bir adımın hemen altındaki girintili satır o adımın devamıdır,
    /// girintisiz satır yeni paragraf başlatır. Satırlar kırpılır.
    public static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var current: Block?
        func flush() {
            if let current { blocks.append(current) }
            current = nil
        }
        func match(_ regex: NSRegularExpression, _ line: String) -> [String]? {
            guard let result = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
            return (1 ..< result.numberOfRanges).compactMap { Range(result.range(at: $0), in: line).map { String(line[$0]) } }
        }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in normalized.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if let step = match(stepPattern, raw), step.count == 2 {
                flush()
                current = .step(number: step[0], text: step[1].trimmingCharacters(in: .whitespaces))
            } else if let bullet = match(bulletPattern, raw), bullet.count == 1 {
                flush()
                current = .bullet(bullet[0].trimmingCharacters(in: .whitespaces))
            } else if let open = current {
                let indented = raw.first.map { $0 == " " || $0 == "\t" } ?? false
                switch open {
                case .paragraph(let body): current = .paragraph(body + "\n" + line)
                case .step(let number, let body) where indented: current = .step(number: number, text: body + "\n" + line)
                case .bullet(let body) where indented: current = .bullet(body + "\n" + line)
                default: flush(); current = .paragraph(line)
                }
            } else {
                flush()
                current = .paragraph(line)
            }
        }
        flush()
        return blocks
    }

    /// Bağlantıları tıklanabilir yapılmış metin (SwiftUI Text'te gösterilir; satırlar ve "1." listeleri olduğu gibi kalır).
    public static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        for link in links(in: text) {
            guard let lower = AttributedString.Index(link.range.lowerBound, within: result),
                  let upper = AttributedString.Index(link.range.upperBound, within: result) else { continue }
            result[lower ..< upper].link = link.url
        }
        return result
    }
}

/// "Nino'ya Sor" sohbetinin durumu (Mac ve iPhone aynı sohbeti kullanır; görünüm platformda). Uygulama açık kaldıkça
/// bellekte durur: sayfa kapatılıp açılınca kaybolmaz, uygulama yeniden açılınca boş başlar.
@MainActor
public final class AssistantChatSession: ObservableObject {
    public struct Context: Sendable {
        public var install: String
        public var app: String
        public var platform: String
        public var language: String
        /// Cihaz bilgileri (DeviceInfo.summary). Bağlam her mesajda yeniden istenir, TV sonradan bağlanmış olabilir.
        public var device: String?

        public init(install: String, app: String, platform: String, language: String, device: String? = nil) {
            self.device = device
            self.install = install
            self.app = app
            self.platform = platform
            self.language = language
        }
    }

    public struct Attachment: Identifiable, Equatable {
        public let id = UUID()
        /// Küçültülmüş JPEG (gönderilen ve küçük resimde gösterilen).
        public let jpeg: Data
    }

    public struct Entry: Identifiable, Equatable {
        public enum State: Equatable {
            case ok
            /// Kullanıcının mesajı gönderilemedi (yeniden denenebilir).
            case failed(AssistantChat.Failure)
        }

        public let id = UUID()
        public var role: AssistantChat.Role
        public var text: String
        public var images: [Data] = []
        /// Robot ekibe bildirim gönderdi.
        public var report: String?
        public var state: State = .ok
        /// Robotun hata bildirimi (yerel; sunucuya gönderilmez).
        public var notice: AssistantChat.Failure?
    }

    @Published public var draft = ""
    @Published public private(set) var entries: [Entry] = []
    @Published public private(set) var attachments: [Attachment] = []
    @Published public private(set) var isWaiting = false
    @Published public private(set) var isPreparing = false
    @Published public private(set) var unreadableImage = false

    private let endpoint: URL?
    private let send: AssistantChat.Send
    private var task: Task<Void, Never>?

    public init(endpoint: URL? = NinoPool.configuredEndpoint(), send: @escaping AssistantChat.Send = { try await URLSession.shared.data(for: $0) }) {
        self.endpoint = endpoint
        self.send = send
    }

    /// Henüz soru sorulmadı (öneri düğmeleri görünür).
    public var isEmpty: Bool { entries.isEmpty }
    public var canAddImage: Bool { attachments.count < AssistantChat.maxImagesPerMessage && !isPreparing }
    public var remainingImages: Int { max(0, AssistantChat.maxImagesPerMessage - attachments.count) }
    public var canSend: Bool {
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) && !isWaiting && !isPreparing
    }

    /// Fotoğrafları (dosya içeriği) arka planda küçültüp ekler; mesaj başına en çok 3.
    public func addImages(_ items: [Data]) async {
        let room = remainingImages
        guard room > 0, !items.isEmpty, !isPreparing else { return }
        isPreparing = true
        let prepared = await Task.detached(priority: .userInitiated) {
            items.prefix(room).map { ProblemReport.prepareImage($0) }
        }.value
        unreadableImage = prepared.contains(nil)
        for jpeg in prepared.compactMap({ $0 }) where attachments.count < AssistantChat.maxImagesPerMessage {
            attachments.append(Attachment(jpeg: jpeg))
        }
        isPreparing = false
    }

    public func remove(_ attachment: Attachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    /// Yazılanı (ya da verilen öneriyi) gönderir.
    public func submit(_ text: String? = nil, context: @escaping @Sendable () async -> Context) {
        let text = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        let images = attachments.map(\.jpeg)
        guard !isWaiting, !isPreparing, !text.isEmpty || !images.isEmpty else { return }
        draft = ""
        attachments = []
        unreadableImage = false
        // Önceki yerel hata bildirimleri sohbetten kalkar.
        entries.removeAll { $0.notice != nil }
        entries.append(Entry(role: .user, text: String(text.prefix(AssistantChat.maxTextLength)), images: images))
        ask(context: context)
    }

    /// Gönderilemeyen son mesajı yeniden dener.
    public func retry(context: @escaping @Sendable () async -> Context) {
        guard !isWaiting, let last = entries.lastIndex(where: { $0.role == .user }), case .failed = entries[last].state else { return }
        entries.removeAll { $0.notice != nil }
        entries[last].state = .ok
        ask(context: context)
    }

    /// Yeni sohbet: her şey silinir (bekleyen istek iptal edilir).
    public func reset() {
        task?.cancel()
        task = nil
        entries = []
        draft = ""
        attachments = []
        unreadableImage = false
        isWaiting = false
    }

    /// Gönderilemeyen mesaj var mı (Yeniden dene düğmesi).
    public var failedEntry: Entry.ID? {
        guard let last = entries.last(where: { $0.role == .user }), case .failed = last.state else { return nil }
        return last.id
    }

    private func ask(context: @escaping @Sendable () async -> Context) {
        isWaiting = true
        let turns = entries.filter { $0.notice == nil && $0.state == .ok }.map { AssistantChat.Turn(role: $0.role, text: $0.text, images: $0.images) }
        let endpoint = endpoint, send = send
        task = Task { [weak self] in
            let context = await context()
            let payload = AssistantChat.Payload(install: context.install, app: context.app, platform: context.platform,
                                                language: context.language, turns: turns, device: context.device)
            let result: Result<AssistantChat.Reply, AssistantChat.Failure>
            do {
                result = .success(try await AssistantChat.send(payload, endpoint: endpoint, send: send))
            } catch {
                result = .failure(error as? AssistantChat.Failure ?? .offline)
            }
            guard !Task.isCancelled, let self else { return }
            self.finish(result)
        }
    }

    private func finish(_ result: Result<AssistantChat.Reply, AssistantChat.Failure>) {
        isWaiting = false
        task = nil
        switch result {
        case .success(let reply):
            entries.append(Entry(role: .assistant, text: reply.text, report: reply.report))
        case .failure(let failure):
            // Gönderilemeyen mesaj sohbette kalır ama sonraki isteğe katılmaz (yeniden denenince katılır).
            if let last = entries.lastIndex(where: { $0.role == .user }) { entries[last].state = .failed(failure) }
            entries.append(Entry(role: .assistant, text: "", notice: failure))
        }
    }
}
