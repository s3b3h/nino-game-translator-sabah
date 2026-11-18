// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import Foundation
import XCTest

/// "Nino'ya Sor": gövdenin biçimi, sınırlar (fotoğraflar yalnız son iki fotoğraflı mesajda), cevap ve hata eşlemesi.
/// Ağa çıkılmaz: gönderim kapanışı sahte cevap döner.
final class AssistantChatTests: XCTestCase {
    private let endpoint = URL(string: "https://example.invalid")!

    private func payload(_ turns: [AssistantChat.Turn]) -> AssistantChat.Payload {
        AssistantChat.Payload(install: "0f8fad5b-d9cb-469f-a165-70867728950e", app: "0.2.0", platform: "mac", language: "tr", turns: turns)
    }

    private func response(_ status: Int, _ json: String, headers: [String: String] = [:]) -> (Data, URLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: endpoint, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }

    // MARK: Gövde

    func testJSONShapeMatchesServer() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0x01, 0x02])
        let body = try AssistantChat.encode(payload([
            .init(role: .user, text: "  TV'de altyazı çıkmıyor \n", images: [jpeg]),
            .init(role: .assistant, text: "Hangi TV?"),
            .init(role: .user, text: "Samsung"),
        ]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["v"] as? Int, 1)
        XCTAssertEqual(json["install"] as? String, "0f8fad5b-d9cb-469f-a165-70867728950e")
        XCTAssertEqual(json["app"] as? String, "0.2.0")
        XCTAssertEqual(json["platform"] as? String, "mac")
        XCTAssertEqual(json["language"] as? String, "tr")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
        XCTAssertEqual(messages[0]["text"] as? String, "TV'de altyazı çıkmıyor")
        let images = try XCTUnwrap(messages[0]["images"] as? [[String: String]])
        XCTAssertEqual(images.first?["mime"], "image/jpeg")
        XCTAssertEqual(Data(base64Encoded: images.first?["data"] ?? ""), jpeg)
        XCTAssertNil(messages[1]["images"], "asistan mesajında fotoğraf alanı yok")
        XCTAssertNil(messages[2]["images"])
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(#"\/"#))
    }

    func testOnlyLastTwoImageMessagesCarryImages() {
        let image = Data([1, 2, 3])
        let turns: [AssistantChat.Turn] = [
            .init(role: .user, text: "bir", images: [image]),
            .init(role: .assistant, text: "a"),
            .init(role: .user, text: "", images: [image]),
            .init(role: .assistant, text: "b"),
            .init(role: .user, text: "üç", images: [image, image]),
            .init(role: .assistant, text: "c"),
            .init(role: .user, text: "dört", images: [image]),
        ]
        let messages = AssistantChat.messages(from: turns)
        XCTAssertEqual(messages.count, 7)
        XCTAssertNil(messages[0].images)
        XCTAssertEqual(messages[0].text, "[screenshot] bir")
        XCTAssertNil(messages[2].images)
        XCTAssertEqual(messages[2].text, "[screenshot]", "yalnız fotoğraflı eski mesaj yazıya döner")
        XCTAssertEqual(messages[4].images?.count, 2)
        XCTAssertEqual(messages[4].text, "üç")
        XCTAssertEqual(messages[6].images?.count, 1)
    }

    func testLimitsAreApplied() {
        var turns: [AssistantChat.Turn] = []
        for i in 0 ..< 30 {
            turns.append(.init(role: i.isMultiple(of: 2) ? .user : .assistant, text: "m\(i)"))
        }
        turns.append(.init(role: .user, text: String(repeating: "ğ", count: 2500), images: Array(repeating: Data([9]), count: 5)))
        let messages = AssistantChat.messages(from: turns)
        XCTAssertEqual(messages.count, AssistantChat.maxMessages)
        XCTAssertEqual(messages.last?.text.utf16.count, AssistantChat.maxTextLength)
        XCTAssertEqual(messages.last?.images?.count, AssistantChat.maxImagesPerMessage)
        XCTAssertEqual(messages.first?.text, "m7")
    }

    func testEmptyMessagesAreDroppedAndLastMustBeUser() {
        XCTAssertEqual(AssistantChat.messages(from: [.init(role: .user, text: "  "), .init(role: .user, text: "selam")]).count, 1)
        XCTAssertFalse(payload([.init(role: .user, text: "selam"), .init(role: .assistant, text: "merhaba")]).isSendable)
        XCTAssertFalse(payload([]).isSendable)
        XCTAssertTrue(payload([.init(role: .user, text: "", images: [Data([1])])]).isSendable)
    }

    func testRequestTargetsAssistantEndpoint() throws {
        let request = try AssistantChat.request(for: payload([.init(role: .user, text: "selam")]), endpoint: endpoint)
        XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/v1/assistant")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertThrowsError(try AssistantChat.request(for: payload([]), endpoint: endpoint)) { error in
            XCTAssertEqual(error as? AssistantChat.Failure, .rejected)
        }
    }

    func testOversizedBodyKeepsOnlyNewestImages() throws {
        // İki mesaj × 3 × 1.2 MB ≈ 9.6 MB base64: yalnız sonuncunun fotoğrafları kalır (≈4.8 MB).
        let big = Data(repeating: 7, count: 1_200_000)
        let request = try AssistantChat.request(for: payload([
            .init(role: .user, text: "eski", images: [big, big, big]),
            .init(role: .assistant, text: "tamam"),
            .init(role: .user, text: "yeni", images: [big, big, big]),
        ]), endpoint: endpoint)
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertLessThanOrEqual(body.count, AssistantChat.maxBodyBytes)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertNil(messages[0]["images"])
        XCTAssertEqual(messages[0]["text"] as? String, "[screenshot] eski")
        XCTAssertEqual((messages[2]["images"] as? [Any])?.count, 3)
    }

    // MARK: Cevap

    func testReplyAndReportAreDecoded() throws {
        var (data, response) = response(200, #"{"ok":true,"reply":"Merhaba!\n1. Ayarlar","report":null}"#)
        XCTAssertEqual(try AssistantChat.reply(data: data, response: response), .init(text: "Merhaba!\n1. Ayarlar"))
        (data, response) = self.response(200, #"{"ok":true,"reply":"Gönderdim.","report":"r_123"}"#)
        XCTAssertEqual(try AssistantChat.reply(data: data, response: response), .init(text: "Gönderdim.", report: "r_123"))
    }

    func testErrorsAreMapped() {
        let cases: [(Int, String, AssistantChat.Failure)] = [
            (503, #"{"ok":false,"error":"assistant_disabled"}"#, .disabled),
            (503, "", .busy),
            (429, #"{"ok":false,"error":"rate_limited"}"#, .rateLimited),
            (429, #"{"ok":false,"error":"busy"}"#, .busy),
            (400, #"{"ok":false,"error":"bad_request"}"#, .rejected),
            (413, #"{"ok":false,"error":"image_too_large"}"#, .tooLarge),
            (502, #"{"ok":false,"error":"model_failed"}"#, .server(502)),
            (502, #"{"ok":false,"error":"refused"}"#, .server(502)),
            (200, #"{"ok":true,"reply":"  "}"#, .server(200)),
            (200, "not json", .server(200)),
        ]
        for (status, json, expected) in cases {
            let (data, response) = response(status, json)
            XCTAssertThrowsError(try AssistantChat.reply(data: data, response: response), "\(status) \(json)") { error in
                XCTAssertEqual(error as? AssistantChat.Failure, expected, "\(status) \(json)")
            }
        }
        XCTAssertTrue(AssistantChat.Failure.offline.isRetryable)
        XCTAssertTrue(AssistantChat.Failure.server(502).isRetryable)
        XCTAssertFalse(AssistantChat.Failure.disabled.isRetryable)
        XCTAssertFalse(AssistantChat.Failure.rateLimited.isRetryable)
    }

    func testNetworkErrorIsOffline() async {
        do {
            _ = try await AssistantChat.send(payload([.init(role: .user, text: "selam")]), endpoint: endpoint) { _ in
                throw URLError(.notConnectedToInternet)
            }
            XCTFail("hata beklenirdi")
        } catch {
            XCTAssertEqual(error as? AssistantChat.Failure, .offline)
        }
        do {
            _ = try await AssistantChat.send(payload([.init(role: .user, text: "selam")]), endpoint: nil)
            XCTFail("hata beklenirdi")
        } catch {
            XCTAssertEqual(error as? AssistantChat.Failure, .noEndpoint)
        }
    }

    // MARK: Metin

    func testLinksAreClickable() {
        let text = "Rehber: https://nino.example/kurulum. Sonra 1. adım."
        let links = AssistantChat.links(in: text)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.url.absoluteString, "https://nino.example/kurulum")
        let attributed = AssistantChat.attributed(text)
        XCTAssertEqual(String(attributed.characters), text)
        XCTAssertEqual(attributed.runs.compactMap(\.link).first?.absoluteString, "https://nino.example/kurulum")
        XCTAssertTrue(AssistantChat.links(in: "e-posta: a@b.com").isEmpty, "mailto bağlantı yapılmaz")
    }

    // MARK: Oturum

    @MainActor
    func testSessionSendsHistoryAndKeepsFailedMessageForRetry() async throws {
        final class Recorder: @unchecked Sendable {
            var bodies: [[String: Any]] = []
            var replies: [(Int, String)] = []
        }
        let recorder = Recorder()
        recorder.replies = [(200, #"{"ok":true,"reply":"Merhaba!","report":null}"#),
                            (502, #"{"ok":false,"error":"model_failed"}"#),
                            (200, #"{"ok":true,"reply":"Gönderdim.","report":"r1"}"#)]
        let session = AssistantChatSession(endpoint: endpoint) { request in
            recorder.bodies.append((try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:])
            let (status, json) = recorder.replies.removeFirst()
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let context: @Sendable () async -> AssistantChatSession.Context = {
            .init(install: "0f8fad5b-d9cb-469f-a165-70867728950e", app: "0.2.0", platform: "ios", language: "tr")
        }
        XCTAssertTrue(session.isEmpty)
        XCTAssertFalse(session.canSend)
        session.submit("PS5 + TV + telefon", context: context)
        try await waitUntil { !session.isWaiting }
        XCTAssertEqual(session.entries.map(\.text), ["PS5 + TV + telefon", "Merhaba!"])

        session.draft = "Samsung"
        session.submit(context: context)
        XCTAssertEqual(session.draft, "")
        try await waitUntil { !session.isWaiting }
        XCTAssertEqual(session.entries.last?.notice, .server(502))
        XCTAssertNotNil(session.failedEntry)

        session.retry(context: context)
        try await waitUntil { !session.isWaiting }
        XCTAssertNil(session.failedEntry)
        XCTAssertEqual(session.entries.map(\.text), ["PS5 + TV + telefon", "Merhaba!", "Samsung", "Gönderdim."])
        XCTAssertEqual(session.entries.last?.report, "r1")
        let last = try XCTUnwrap(recorder.bodies.last?["messages"] as? [[String: Any]])
        XCTAssertEqual(last.compactMap { $0["text"] as? String }, ["PS5 + TV + telefon", "Merhaba!", "Samsung"],
                       "yerel hata bildirimi sunucuya gitmez")
        XCTAssertEqual(recorder.bodies.last?["platform"] as? String, "ios")

        session.reset()
        XCTAssertTrue(session.isEmpty)
    }

    @MainActor
    func testDisabledServerShowsNotice() async throws {
        let session = AssistantChatSession(endpoint: endpoint) { request in
            (Data(#"{"ok":false,"error":"assistant_disabled"}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }
        session.submit("selam") { .init(install: "0f8fad5b-d9cb", app: "0.2.0", platform: "mac", language: "tr") }
        try await waitUntil { !session.isWaiting }
        XCTAssertEqual(session.entries.last?.notice, .disabled)
    }

    @MainActor
    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        for _ in 0 ..< 200 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition())
    }

    // MARK: Cevabın blokları (balondaki adım rozetleri)

    func testBlocksSplitParagraphsAndSpacedSteps() {
        let reply = """
        Kolay yol var, TV'ye iki farklı şekilde kurabilirsin.

        1. Mac'inde Nino'yu aç ve ilk kurulumda TV seçimine gel.

        2. TV'ni seç (Android TV / Google TV, Samsung ya da LG); Nino uygulamayı TV'ye kendisi kurar.

        3. TV'de bir kez izin istenirse kumandayla onayla.

        Hangi TV markasını kullanıyorsun?
        """
        XCTAssertEqual(AssistantChat.blocks(reply), [
            .paragraph("Kolay yol var, TV'ye iki farklı şekilde kurabilirsin."),
            .step(number: "1", text: "Mac'inde Nino'yu aç ve ilk kurulumda TV seçimine gel."),
            .step(number: "2", text: "TV'ni seç (Android TV / Google TV, Samsung ya da LG); Nino uygulamayı TV'ye kendisi kurar."),
            .step(number: "3", text: "TV'de bir kez izin istenirse kumandayla onayla."),
            .paragraph("Hangi TV markasını kullanıyorsun?"),
        ])
    }

    func testBlocksConsecutiveStepsInsideParagraph() {
        let reply = "Şunu dene:\r\n1. Ayarlar'ı aç.\n2) https://nino.example/kurulum adresine git.\n   Sayfa açılmazsa bekle.\nOlmazsa yaz.\nBen buradayım.\n\n\n"
        XCTAssertEqual(AssistantChat.blocks(reply), [
            .paragraph("Şunu dene:"),
            .step(number: "1", text: "Ayarlar'ı aç."),
            .step(number: "2", text: "https://nino.example/kurulum adresine git.\nSayfa açılmazsa bekle."),
            .paragraph("Olmazsa yaz.\nBen buradayım."),
        ])
    }

    func testBlocksBulletsAndNonSteps() {
        let reply = "Gerekenler:\n- PS5\n• Remote Play için ikinci hesap\n* Aynı Wi-Fi\n\n2024. yılında çıkan oyunlar da olur.\n10. adım: 1.5 saniye bekle."
        XCTAssertEqual(AssistantChat.blocks(reply), [
            .paragraph("Gerekenler:"),
            .bullet("PS5"),
            .bullet("Remote Play için ikinci hesap"),
            .bullet("Aynı Wi-Fi"),
            .paragraph("2024. yılında çıkan oyunlar da olur."),
            .step(number: "10", text: "adım: 1.5 saniye bekle."),
        ])
        XCTAssertEqual(AssistantChat.blocks("  \n\n"), [])
        XCTAssertEqual(AssistantChat.blocks("-yok\n1.yok"), [.paragraph("-yok\n1.yok")])
    }
}
