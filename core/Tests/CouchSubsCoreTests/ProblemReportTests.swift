// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// "Sorun Bildir": gövdenin biçimi, fotoğraf küçültme ve boyut sınırı, günlükten anahtar silme. Ağa çıkılmaz.
final class ProblemReportTests: XCTestCase {
    private let endpoint = URL(string: "https://example.invalid")!

    private func payload(text: String = "Altyazı gelmedi", contact: String? = nil, log: String? = nil, images: [Data] = []) -> ProblemReport.Payload {
        ProblemReport.Payload(install: "0f8fad5b-d9cb-469f-a165-70867728950e", app: "0.1.4", platform: "mac", language: "tr",
                              text: text, contact: contact, log: log, images: images)
    }

    // MARK: Gövde

    func testJSONShapeMatchesServer() throws {
        let jpeg = try XCTUnwrap(ProblemReport.prepareImage(Self.png(width: 400, height: 300)))
        let body = try ProblemReport.encode(payload(text: "  Altyazı gelmedi \n", contact: " @nino ", log: "satır", images: [jpeg]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["v"] as? Int, 1)
        XCTAssertEqual(json["install"] as? String, "0f8fad5b-d9cb-469f-a165-70867728950e")
        XCTAssertEqual(json["app"] as? String, "0.1.4")
        XCTAssertEqual(json["platform"] as? String, "mac")
        XCTAssertEqual(json["language"] as? String, "tr")
        XCTAssertEqual(json["text"] as? String, "Altyazı gelmedi")
        XCTAssertEqual(json["contact"] as? String, "@nino")
        XCTAssertEqual(json["log"] as? String, "satır")
        let images = try XCTUnwrap(json["images"] as? [[String: String]])
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0]["mime"], "image/jpeg")
        XCTAssertEqual(Data(base64Encoded: images[0]["data"] ?? ""), jpeg)
        // Base64'teki "/" kaçırılmaz.
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(#"\/"#))
    }

    func testEmptyOptionalFieldsAreOmitted() throws {
        let body = try ProblemReport.encode(payload(contact: "   ", log: ""))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["contact"])
        XCTAssertNil(json["log"])
        XCTAssertNil(json["images"])
    }

    func testLimitsAreApplied() {
        let long = payload(text: String(repeating: "a", count: 5000), contact: String(repeating: "b", count: 300),
                           log: String(repeating: "c", count: 70_000) + "SON", images: Array(repeating: Data([1]), count: 5))
        XCTAssertEqual(long.text.count, ProblemReport.maxTextLength)
        XCTAssertEqual(long.contact?.count, ProblemReport.maxContactLength)
        XCTAssertEqual(long.log?.utf16.count, ProblemReport.maxLogLength)
        XCTAssertTrue(long.log?.hasSuffix("SON") == true, "günlüğün sonu (en yenisi) kalır")
        XCTAssertEqual(long.images?.count, ProblemReport.maxImages)
    }

    func testEmptyDescriptionIsNotSent() {
        XCTAssertFalse(payload(text: " \n ").isSendable)
        XCTAssertThrowsError(try ProblemReport.request(for: payload(text: " "), endpoint: endpoint)) {
            XCTAssertEqual($0 as? ProblemReport.Failure, .rejected)
        }
    }

    func testRequest() throws {
        let request = try ProblemReport.request(for: payload(), endpoint: endpoint)
        XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/v1/reports")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(request.httpBody)
    }

    // MARK: Gönderme (sahte sunucu)

    private func reply(_ status: Int, _ body: String = "{}") -> ProblemReport.Send {
        { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testSendSuccessReturnsID() async throws {
        let id = try await ProblemReport.send(payload(), endpoint: endpoint, send: reply(200, #"{"ok":true,"id":"abc"}"#))
        XCTAssertEqual(id, "abc")
    }

    func testSendMapsErrors() async {
        let cases: [(ProblemReport.Send, ProblemReport.Failure)] = [
            (reply(429), .rateLimited), (reply(413), .tooLarge), (reply(400), .rejected), (reply(500), .server(500)),
            ({ _ in throw URLError(.notConnectedToInternet) }, .offline),
        ]
        for (send, expected) in cases {
            do {
                _ = try await ProblemReport.send(payload(), endpoint: endpoint, send: send)
                XCTFail("hata bekleniyordu: \(expected)")
            } catch {
                XCTAssertEqual(error as? ProblemReport.Failure, expected)
            }
        }
        do {
            _ = try await ProblemReport.send(payload(), endpoint: nil, send: reply(200))
            XCTFail("adres yokken gönderilmemeli")
        } catch {
            XCTAssertEqual(error as? ProblemReport.Failure, .noEndpoint)
        }
    }

    // MARK: Fotoğraf

    func testImageIsDownscaledToJPEG() throws {
        let jpeg = try XCTUnwrap(ProblemReport.prepareImage(Self.png(width: 4000, height: 2000, alpha: true)))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(max(image.width, image.height), ProblemReport.maxImageSide)
        XCTAssertEqual(image.width, 1600)
        XCTAssertEqual(image.height, 800)
        XCTAssertLessThanOrEqual(jpeg.count, ProblemReport.maxImageBytes)
    }

    func testSmallImageIsNotEnlarged() throws {
        let jpeg = try XCTUnwrap(ProblemReport.prepareImage(Self.png(width: 300, height: 500)))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(jpeg as CFData, nil)!, 0, nil))
        XCTAssertEqual(image.width, 300)
        XCTAssertEqual(image.height, 500)
    }

    func testNoisyImageShrinksUntilItFits() throws {
        // Gürültü JPEG'de çok yer tutar: sınır küçük verilince kalite ve boyut düşürülerek sığdırılır.
        let noisy = Self.png(width: 1600, height: 1600, noise: true)
        let jpeg = try XCTUnwrap(ProblemReport.prepareImage(noisy, maxBytes: 300_000))
        XCTAssertLessThanOrEqual(jpeg.count, 300_000)
    }

    func testThreeNoisyImagesFitInBody() throws {
        let noisy = Self.png(width: 2400, height: 1600, noise: true)
        let jpeg = try XCTUnwrap(ProblemReport.prepareImage(noisy))
        let full = payload(log: String(repeating: "x", count: 60_000), images: [jpeg, jpeg, jpeg])
        let request = try ProblemReport.request(for: full, endpoint: endpoint)
        XCTAssertLessThanOrEqual(request.httpBody?.count ?? .max, ProblemReport.maxBodyBytes)
    }

    func testUnreadableImageIsNil() {
        XCTAssertNil(ProblemReport.prepareImage(Data("not an image".utf8)))
    }

    // MARK: Günlük

    func testScrubRemovesSecrets() {
        let log = """
        2026-11-18 10:00:00 Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc123
        gemini key=AIzaSyA1b2C3d4E5f6G7h8I9j0KlMnOpQrStUvW
        openai sk-proj-Ab12Cd34Ef56Gh78Ij90KlMn
        deepl 0f8fad5b-d9cb-469f-a165-70867728950e:fx
        url https://x.test/?token=abc123def&x=1
        "password": "hunter2"
        psn account dGhpcyBpcyBhIHNlY3JldCB0b2tlbjEyMzQ1Njc4OTA=
        """
        let clean = ProblemReport.scrub(log)
        for secret in ["eyJhbGci", "AIzaSy", "sk-proj", "0f8fad5b", "abc123def", "hunter2", "dGhpcyBp"] {
            XCTAssertFalse(clean.contains(secret), "\(secret) silinmeliydi:\n\(clean)")
        }
        XCTAssertTrue(clean.contains("[gizli]"))
    }

    func testScrubKeepsOrdinaryLines() {
        let log = """
        2026-11-18 10:00:00.123 PS5 araması: PS5-123 192.168.0.12
        /Users/someone/Library/Logs/CouchSubs/remoteplay.log
        okuma 340 ms'dir bitmedi; okuma hattı yeniden kuruldu
        Nino 0.1.4, macOS Version 27.0 (Build 27A123)
        """
        XCTAssertEqual(ProblemReport.scrub(log), log)
    }

    func testRecentLogCombinesTailsOfFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let big = dir.appendingPathComponent("remoteplay.log")
        let small = dir.appendingPathComponent("altyazi.log")
        let missing = dir.appendingPathComponent("tvinstall.log")
        try ((0 ..< 20_000).map { "satır \($0)" }.joined(separator: "\n") + "\nEN SON key=gizlisey").write(to: big, atomically: true, encoding: .utf8)
        try "kısa altyazı günlüğü".write(to: small, atomically: true, encoding: .utf8)

        let log = try XCTUnwrap(ProblemReport.recentLog(files: [big, small, missing], header: "Nino 0.1.4", maxLength: 10_000))
        XCTAssertLessThanOrEqual(log.utf16.count, 10_000)
        XCTAssertTrue(log.hasPrefix("Nino 0.1.4\n"))
        XCTAssertTrue(log.contains("=== remoteplay.log ==="))
        XCTAssertTrue(log.contains("=== altyazi.log ===\nkısa altyazı günlüğü"), "kısa dosya bütün olarak girer")
        XCTAssertTrue(log.contains("EN SON key=[gizli]"), "büyük dosyanın sonu girer, anahtar silinir")
        XCTAssertFalse(log.contains("gizlisey"))
        XCTAssertFalse(log.contains("satır 0\n"))
        XCTAssertNil(ProblemReport.recentLog(files: [missing]))
    }

    func testLastUTF16DoesNotSplitCharacters() {
        let text = "ab😀cd"
        XCTAssertEqual(ProblemReport.lastUTF16(text, 3), "cd")
        XCTAssertEqual(ProblemReport.lastUTF16(text, 4), "😀cd")
        XCTAssertEqual(ProblemReport.lastUTF16(text, 100), text)
    }

    // MARK: Form

    @MainActor
    func testFormKeepsAtMostThreeImagesAndFlagsUnreadable() async {
        let form = ProblemReportForm(endpoint: endpoint, send: reply(200))
        let png = Self.png(width: 200, height: 100)
        await form.addImages([png, png])
        await form.addImages([png, Data("bozuk".utf8)])
        XCTAssertEqual(form.attachments.count, 3)
        XCTAssertFalse(form.canAddImage)
        await form.addImages([png])
        XCTAssertEqual(form.attachments.count, 3)
        form.remove(form.attachments[0])
        XCTAssertEqual(form.attachments.count, 2)
        await form.addImages([Data("bozuk".utf8)])
        XCTAssertTrue(form.unreadableImage)
    }

    @MainActor
    func testFormFailureKeepsDraftAndLogToggleIsRespected() async throws {
        final class Box: @unchecked Sendable { var bodies: [Data] = []; var status = 429 }
        let box = Box()
        let form = ProblemReportForm(endpoint: endpoint) { request in
            box.bodies.append(request.httpBody ?? Data())
            return (Data(#"{"ok":true,"id":"1"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: box.status, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertFalse(form.canSend)
        form.text = "TV'de altyazı görünmüyor"
        form.includeLog = false
        let logFile = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString).log")
        try "günlük satırı".write(to: logFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: logFile) }

        await form.submit(install: "0f8fad5b-d9cb-469f-a165-70867728950e", app: "0.1.4", platform: "ios", language: "tr", logFiles: [logFile])
        XCTAssertEqual(form.phase, .failed(.rateLimited))
        XCTAssertEqual(form.text, "TV'de altyazı görünmüyor", "hata olunca form korunur")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: box.bodies[0]) as? [String: Any])
        XCTAssertNil(json["log"], "günlük kapalıyken gönderilmez")

        box.status = 200
        form.includeLog = true
        await form.submit(install: "0f8fad5b-d9cb-469f-a165-70867728950e", app: "0.1.4", platform: "ios", language: "tr", logFiles: [logFile])
        XCTAssertEqual(form.phase, .sent)
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: box.bodies[1]) as? [String: Any])
        XCTAssertTrue((json["log"] as? String)?.contains("günlük satırı") == true)
        XCTAssertEqual(json["platform"] as? String, "ios")
    }

    // MARK: Yardımcı

    /// Denemelik PNG: düz renk geçişi ya da gürültü.
    static func png(width: Int, height: Int, alpha: Bool = false, noise: Bool = false) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
        if noise, let pixels = context.data?.assumingMemoryBound(to: UInt32.self) {
            var seed: UInt32 = 12345
            for i in 0 ..< width * height {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                pixels[i] = seed | 0xFF00_0000
            }
        } else {
            context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: alpha ? 0.5 : 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        }
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }
}
