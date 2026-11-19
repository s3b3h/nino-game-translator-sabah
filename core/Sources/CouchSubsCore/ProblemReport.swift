// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Nino: "Sorun Bildir". Kullanıcının açıklaması, isteğe bağlı iletişim bilgisi, (açıksa) uygulama günlüğünün sonu ve
/// en çok 3 ekran görüntüsü Nino havuz sunucusuna (`POST /v1/reports`, nino-pool/src/reports.js) gönderilir.
/// Mac ve iPhone aynı kodu kullanır: fotoğraflar burada küçültülüp JPEG yapılır, günlükten anahtar ve jetonlar silinir.
/// Kuruluş kimliği havuzunkiyle (NinoPool.installID) aynıdır; sunucu onu tuzlayıp özetler, IP adresi tutmaz.
public enum ProblemReport {
    public static let maxTextLength = 4000
    public static let maxContactLength = 200
    /// Sunucu günlüğün ilk 60 000 UTF-16 birimini saklar; biz sonunu (en yeni satırları) göndeririz.
    public static let maxLogLength = 60_000
    public static let maxImages = 3
    /// Fotoğrafın en uzun kenarı (piksel).
    public static let maxImageSide = 1600
    /// Sunucu tek fotoğrafa 1.5 MB'ye kadar izin veriyor; ama gövdenin tamamı 4 MB'yi geçemez ve base64 boyutu 4/3'e
    /// çıkarır. Üç fotoğraf × 900 KB × 4/3 ≈ 3.6 MB; günlük ve metinle birlikte 4 MB'nin altında kalır.
    public static let maxImageBytes = 900_000
    public static let maxBodyBytes = 4 * 1024 * 1024
    public static let jpegQuality: Double = 0.7

    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Gönderilen fotoğraf (her zaman JPEG).
    public struct Image: Codable, Equatable, Sendable {
        public var mime: String
        public var data: String

        public init(jpeg: Data) {
            mime = "image/jpeg"
            data = jpeg.base64EncodedString()
        }
    }

    /// Sunucuya giden gövde. Boş iletişim, günlük ve fotoğraf listesi gönderilmez.
    public struct Payload: Codable, Equatable, Sendable {
        public var v = 1
        public var install: String
        public var app: String
        public var platform: String
        public var language: String
        public var text: String
        public var contact: String?
        public var log: String?
        public var images: [Image]?
        /// Cihaz bilgileri (DeviceInfo.summary): uygulama, cihaz modeli, sistem, TV, konsol. Kişisel bilgi içermez.
        public var device: String?

        public init(install: String, app: String, platform: String, language: String, text: String,
                    contact: String? = nil, log: String? = nil, images: [Data] = [], device: String? = nil) {
            let device = String((device ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(DeviceInfo.maxLength))
            self.device = device.isEmpty ? nil : device
            self.install = install
            self.app = app
            self.platform = platform
            self.language = language
            self.text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ProblemReport.maxTextLength))
            let contact = (contact ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self.contact = contact.isEmpty ? nil : String(contact.prefix(ProblemReport.maxContactLength))
            let log = log.map { ProblemReport.lastUTF16($0, ProblemReport.maxLogLength) } ?? ""
            self.log = log.isEmpty ? nil : log
            let images = images.prefix(ProblemReport.maxImages).map(Image.init(jpeg:))
            self.images = images.isEmpty ? nil : Array(images)
        }

        /// Açıklama boşsa gönderilemez (sunucu da kabul etmez).
        public var isSendable: Bool { !text.isEmpty }
    }

    public enum Failure: Error, Equatable, Sendable {
        /// Açıklama boş ya da sunucu biçimi kabul etmedi (400).
        case rejected
        /// Gövde çok büyük (413 ya da gönderilmeden önce).
        case tooLarge
        /// Bugün çok bildirim gönderildi (429).
        case rateLimited
        /// Sunucu hatası (5xx ve diğerleri).
        case server(Int)
        /// Ağ yok ya da sunucuya ulaşılamadı.
        case offline
        /// Sunucu adresi yok.
        case noEndpoint
    }

    // MARK: - İstek

    public static func encode(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        // Base64'teki "/" kaçırılırsa ("\/") gövde gereksiz büyür.
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// `endpoint`: havuz sunucusunun kökü (NinoPool.configuredEndpoint()).
    public static func request(for payload: Payload, endpoint: URL) throws -> URLRequest {
        guard payload.isSendable else { throw Failure.rejected }
        let body = try encode(payload)
        guard body.count <= maxBodyBytes else { throw Failure.tooLarge }
        // Birkaç MB'lık yükleme yavaş ağda sürebilir; havuzun 30 sn'si yetmez.
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/reports"), timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("nino-report/1 (\(payload.platform); \(payload.app))", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        return request
    }

    /// Bildirimi gönderir; başarılıysa sunucunun verdiği kimliği döner.
    public static func send(_ payload: Payload, endpoint: URL? = NinoPool.configuredEndpoint(),
                            send: Send = { try await URLSession.shared.data(for: $0) }) async throws -> String {
        guard let endpoint else { throw Failure.noEndpoint }
        let request = try request(for: payload, endpoint: endpoint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(request)
        } catch {
            throw Failure.offline
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.offline }
        switch http.statusCode {
        case 200 ..< 300:
            struct Reply: Decodable { var ok: Bool; var id: String? }
            let reply = try? JSONDecoder().decode(Reply.self, from: data)
            guard reply?.ok != false else { throw Failure.server(http.statusCode) }
            return reply?.id ?? ""
        case 400: throw Failure.rejected
        case 413: throw Failure.tooLarge
        case 429: throw Failure.rateLimited
        default: throw Failure.server(http.statusCode)
        }
    }

    // MARK: - Fotoğraf

    /// Fotoğrafı (JPEG, PNG, HEIC…) en uzun kenarı en çok `maxSide` piksel olacak biçimde küçültür, döndürme bilgisini
    /// uygular, saydamlığı beyaza çevirir ve JPEG yapar. `maxBytes`'a sığmazsa önce kaliteyi, sonra boyutu düşürür.
    /// Okunamayan dosyada nil.
    public static func prepareImage(_ data: Data, maxSide: Int = maxImageSide, maxBytes: Int = maxImageBytes) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        var side = maxSide
        while side >= 200 {
            guard let image = downscaled(source, maxSide: side) else { return nil }
            for quality in [jpegQuality, 0.55, 0.4] {
                if let jpeg = jpeg(image, quality: quality), jpeg.count <= maxBytes { return jpeg }
            }
            side = side * 3 / 4
        }
        return nil
    }

    private static func downscaled(_ source: CGImageSource, maxSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // Saydam PNG JPEG'de siyah zemin olmasın: beyaz zemine çizilir (renk uzayı sRGB, alfa yok).
        let width = thumb.width, height = thumb.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return thumb }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(thumb, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? thumb
    }

    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    // MARK: - Günlük

    /// Günlük dosyalarının sonlarını birleştirir: her dosya "=== ad ===" başlığıyla, en çok `maxLength` UTF-16 birim.
    /// Pay dosyalara bölünür (son dosya ötekileri dışarıda bırakmasın); kısa dosyanın artan payı ötekilere kalır.
    /// Anahtar ve jetonlar silinir. Hiç günlük yoksa nil.
    public static func recentLog(files: [URL], header: String? = nil, maxLength: Int = maxLogLength) -> String? {
        let readBytes = maxLength * 4
        var texts: [(name: String, text: String)] = []
        for file in files {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            let end = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: end > UInt64(readBytes) ? end - UInt64(readBytes) : 0)
            guard let data = try? handle.readToEnd(), !data.isEmpty else { continue }
            var text = String(decoding: data, as: UTF8.self)
            // Ortadan başlandıysa ilk (yarım) satır atılır.
            if end > UInt64(readBytes), let newline = text.firstIndex(of: "\n") { text = String(text[text.index(after: newline)...]) }
            text = scrub(text).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { texts.append((file.lastPathComponent, text)) }
        }
        guard !texts.isEmpty else { return nil }
        let head = header.map { scrub($0) + "\n" } ?? ""
        var remaining = maxLength - head.utf16.count
        var parts = [String](repeating: "", count: texts.count)
        // Kısadan uzuna: kısa dosyanın kullanmadığı pay sonrakilere kalır.
        let order = texts.indices.sorted { texts[$0].text.utf16.count < texts[$1].text.utf16.count }
        for (n, i) in order.enumerated() {
            let title = "=== \(texts[i].name) ===\n"
            let share = remaining / (order.count - n)
            let room = max(0, share - title.utf16.count - 2)
            let body = lastUTF16(texts[i].text, room)
            parts[i] = title + body
            remaining -= parts[i].utf16.count + 2
        }
        return lastUTF16(head + parts.joined(separator: "\n\n"), maxLength)
    }

    private static let secretPatterns: [(NSRegularExpression, String)] = [
        // "Authorization: Bearer xyz", "Bearer xyz"
        (try! NSRegularExpression(pattern: #"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=\-]+"#), "$1 [gizli]"),
        // key=…, token: …, api_key=…, password=…, "secret": "…"
        (try! NSRegularExpression(pattern: #"(?i)\b([A-Za-z_\-]*(?:key|token|secret|password|passwd|passcode|auth|credential|cookie|session_id))(["']?\s*[=:]\s*["']?)[^\s"',;&]+"#),
         "$1$2[gizli]"),
        // Google (AIza…), OpenAI / Anthropic (sk-…), DeepL (…:fx)
        (try! NSRegularExpression(pattern: #"AIza[0-9A-Za-z_\-]{20,}"#), "[gizli]"),
        (try! NSRegularExpression(pattern: #"\bsk-[A-Za-z0-9_\-]{16,}"#), "[gizli]"),
        (try! NSRegularExpression(pattern: #"\b[0-9a-fA-F\-]{30,}:fx\b"#), "[gizli]"),
    ]

    /// Uzun base64 / onaltılık diziler (jeton, anahtar, hesap kimliği). Dosya yolları ("/Users/…/Logs") ve sözcükler
    /// silinmesin diye yalnız içinde hem harf hem en az 4 rakam olanlar silinir.
    private static let longToken = try! NSRegularExpression(pattern: #"[A-Za-z0-9+/_\-]{32,}={0,2}"#)

    /// Günlükten anahtar, jeton ve parola benzeri her şeyi siler.
    public static func scrub(_ text: String) -> String {
        var result = text
        for (pattern, template) in secretPatterns {
            result = pattern.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        let matches = longToken.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let token = result[range]
            let digits = token.filter(\.isNumber).count
            let letters = token.filter(\.isLetter).count
            // Yol parçası gibi görünen (çok "/" içeren, rakamı az) diziler kalır.
            let slashes = token.filter { $0 == "/" }.count
            if digits >= 4, letters >= 4, slashes <= token.count / 16 { result.replaceSubrange(range, with: "[gizli]") }
        }
        return result
    }

    /// Metnin son `count` UTF-16 birimi (sunucu UTF-16 ile sayar); bölünen karakter bırakılmaz.
    static func lastUTF16(_ text: String, _ count: Int) -> String {
        let utf16 = text.utf16
        guard utf16.count > count else { return text }
        guard count > 0 else { return "" }
        var start = utf16.index(utf16.endIndex, offsetBy: -count)
        while start < utf16.endIndex, String.Index(start, within: text) == nil { start = utf16.index(after: start) }
        return String(text[start...])
    }
}

/// "Sorun Bildir" formunun durumu (Mac ve iPhone aynı formu kullanır; görünüm platformda).
@MainActor
public final class ProblemReportForm: ObservableObject {
    public struct Attachment: Identifiable, Equatable {
        public let id = UUID()
        /// Küçültülmüş JPEG (gönderilen ve küçük resimde gösterilen).
        public let jpeg: Data
    }

    public enum Phase: Equatable {
        case editing
        /// Fotoğraflar hazırlanıyor.
        case preparing
        case sending
        case sent
        case failed(ProblemReport.Failure)
    }

    @Published public var text = ""
    @Published public var contact = ""
    @Published public var includeLog = true
    @Published public private(set) var attachments: [Attachment] = []
    @Published public private(set) var phase: Phase = .editing
    /// Okunamayan (fotoğraf olmayan) dosya eklenmeye çalışıldı.
    @Published public private(set) var unreadableImage = false

    private let send: ProblemReport.Send
    private let endpoint: URL?

    public init(endpoint: URL? = NinoPool.configuredEndpoint(), send: @escaping ProblemReport.Send = { try await URLSession.shared.data(for: $0) }) {
        self.endpoint = endpoint
        self.send = send
    }

    public var canAddImage: Bool { attachments.count < ProblemReport.maxImages && phase != .sending }
    public var remainingImages: Int { max(0, ProblemReport.maxImages - attachments.count) }
    public var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .sending && phase != .preparing && phase != .sent
    }
    public var isBusy: Bool { phase == .sending || phase == .preparing }

    /// Fotoğrafları (dosya içeriği) arka planda küçültüp ekler; en çok 3.
    public func addImages(_ items: [Data]) async {
        let room = remainingImages
        guard room > 0, !items.isEmpty, !isBusy else { return }
        phase = .preparing
        let prepared = await Task.detached(priority: .userInitiated) {
            items.prefix(room).map { ProblemReport.prepareImage($0) }
        }.value
        unreadableImage = prepared.contains(nil)
        for jpeg in prepared.compactMap({ $0 }) where attachments.count < ProblemReport.maxImages {
            attachments.append(Attachment(jpeg: jpeg))
        }
        phase = .editing
    }

    public func remove(_ attachment: Attachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    /// Gönderir. `logFiles`: "Uygulama günlüğünü ekle" açıksa sonları eklenecek günlükler. Hata olursa form korunur.
    public func submit(install: String, app: String, platform: String, language: String,
                       logFiles: [URL], logHeader: String? = nil, device: String? = nil) async {
        guard canSend else { return }
        phase = .sending
        let includeLog = includeLog
        let log = includeLog ? await Task.detached(priority: .userInitiated) {
            ProblemReport.recentLog(files: logFiles, header: logHeader)
        }.value : nil
        let payload = ProblemReport.Payload(install: install, app: app, platform: platform, language: language, text: text,
                                            contact: contact, log: log, images: attachments.map(\.jpeg), device: device)
        do {
            _ = try await ProblemReport.send(payload, endpoint: endpoint, send: send)
            phase = .sent
        } catch {
            phase = .failed(error as? ProblemReport.Failure ?? .offline)
        }
    }

    /// Gönderildikten sonra boş forma döner (taslak, form kapatılıp açılınca kaybolmasın diye uygulamada saklanır).
    public func reset() {
        guard !isBusy else { return }
        text = ""
        contact = ""
        includeLog = true
        attachments = []
        unreadableImage = false
        phase = .editing
    }

    /// Hata gösterildikten sonra kullanıcı formu değiştirince.
    public func clearError() {
        if case .failed = phase { phase = .editing }
        unreadableImage = false
    }
}
