// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import XCTest
@testable import CouchSubsCore

final class TranslationPoolTests: XCTestCase {
    /// Sahte sunucu: istekleri kaydeder, yola göre cevap verir.
    final class FakeServer: @unchecked Sendable {
        let lock = NSLock()
        var requests: [URLRequest] = []
        var translateReply: (URLRequest) -> String = { _ in #"{"ok":true,"translations":[{"text":"Kim lan sen?","tier":1}]}"# }
        var pages: [String] = [#"{"ok":true,"now":10,"items":[],"next":null}"#]
        var config = #"{"ok":true,"translate":{"enabled":true,"deadlineMs":700,"syncSeconds":60,"contextLines":2,"maxLines":12}}"#

        func handle(_ request: URLRequest) -> (Data, URLResponse) {
            lock.lock()
            requests.append(request)
            let path = request.url!.path
            let body: String
            if path.hasSuffix("/v1/config") { body = config }
            else if path.hasSuffix("/v1/translate") { body = translateReply(request) }
            else { body = pages.isEmpty ? #"{"ok":true,"items":[],"next":null}"# : pages.removeFirst() }
            lock.unlock()
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        var paths: [String] { lock.lock(); defer { lock.unlock() }; return requests.map { $0.url!.path } }
    }

    func makePool(_ server: FakeServer, dir: URL? = nil, language: String = "tr", enabled: Bool = true) -> TranslationPool {
        let directory = dir ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return TranslationPool(directory: directory, endpoint: URL(string: "https://pool.test")!, install: UUID().uuidString.lowercased(),
                               app: "0.2.2", platform: "test", language: language, enabled: enabled,
                               send: { server.handle($0) })
    }

    func testTranslateAsksServerOnceAndRemembers() async throws {
        let server = FakeServer()
        let pool = makePool(server)
        let first = await pool.translate("Who the fuck are you?", context: ["Hey.", "Back up!", "Wait."], game: "Grand Theft Auto VI")
        XCTAssertEqual(first, "Kim lan sen?")
        XCTAssertEqual(pool.store.match("WHO THE FUCK ARE YOU"), "Kim lan sen?")
        _ = await pool.translate("Who the fuck are you?")
        let translateCalls = server.requests.filter { $0.url!.path.hasSuffix("/v1/translate") }
        XCTAssertEqual(translateCalls.count, 1)
        let body = try JSONSerialization.jsonObject(with: translateCalls[0].httpBody!) as! [String: Any]
        XCTAssertEqual(body["lang"] as? String, "tr")
        XCTAssertEqual(body["game"] as? String, "grand-theft-auto-vi")
        XCTAssertEqual(body["context"] as? [String], ["Back up!", "Wait."], "sunucu ayarındaki kadar bağlam gider")
    }

    func testSyncDownloadsPagesAndSavesPerLanguage() async throws {
        let server = FakeServer()
        server.pages = [
            #"{"ok":true,"now":50,"items":[["\#(PackKey.key("Get in the car!")!)","Bin arabaya!",20,1]],"next":{"since":20,"after":"\#(PackKey.key("Get in the car!")!)"}}"#,
            #"{"ok":true,"now":50,"items":[["\#(PackKey.key("Move!")!)","Yürü!",30,2]],"next":null}"#,
        ]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pool = makePool(server, dir: dir)
        let added = await pool.sync(game: "gta-vi")
        XCTAssertEqual(added, 2)
        XCTAssertEqual(pool.store.match("get in the car"), "Bin arabaya!")
        let urls = server.requests.compactMap { $0.url }.filter { $0.path.hasSuffix("/v1/translations") }
        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(urls[1].query!.contains("since=20"))
        XCTAssertTrue(urls[1].query!.contains("after="))
        // Aralık dolmadan yeniden sormaz; diskten yeniden açılınca çeviriler durur.
        _ = await pool.sync(game: "gta-vi")
        XCTAssertEqual(server.requests.filter { $0.url!.path.hasSuffix("/v1/translations") }.count, 2)
        let reopened = makePool(FakeServer(), dir: dir)
        XCTAssertEqual(reopened.store.match("Move!"), "Yürü!")
        // Başka dilde boş başlar.
        await reopened.setLanguage("ar")
        XCTAssertNil(reopened.store.match("Move!"))
    }

    func testDisabledPoolSendsNothing() async {
        let server = FakeServer()
        let pool = makePool(server, enabled: false)
        let result = await pool.translate("Get down!")
        XCTAssertNil(result)
        _ = await pool.sync(game: nil)
        XCTAssertFalse(server.paths.contains { $0.hasSuffix("/v1/translate") || $0.hasSuffix("/v1/translations") })
    }

    func testServerCanSwitchPoolOff() async {
        let server = FakeServer()
        server.config = #"{"ok":true,"translate":{"enabled":false,"deadlineMs":700,"syncSeconds":60,"contextLines":2,"maxLines":12}}"#
        let pool = makePool(server)
        await pool.refreshConfig(force: true)
        let result = await pool.translate("Get down!")
        XCTAssertNil(result)
        XCTAssertFalse(server.paths.contains { $0.hasSuffix("/v1/translate") })
    }

    func testNoiseIsNotSent() async {
        let server = FakeServer()
        let pool = makePool(server)
        let result = await pool.translate("!!!")
        XCTAssertNil(result)
        XCTAssertFalse(server.paths.contains { $0.hasSuffix("/v1/translate") })
    }
}

extension TranslationPoolTests {
    func testPingCarriesInstallAndGame() async throws {
        let server = FakeServer()
        let pool = makePool(server)
        await pool.ping(game: "Grand Theft Auto VI")
        let url = try XCTUnwrap(server.requests.first?.url)
        XCTAssertEqual(url.path, "/v1/ping")
        XCTAssertTrue(url.query!.contains("game=grand-theft-auto-vi"))
        XCTAssertTrue(url.query!.contains("platform=test"))
        let off = makePool(FakeServer(), enabled: false)
        await off.ping(game: nil)
    }
}

extension TranslationPoolTests {
    func testTurningOffKeepsSavedTranslations() async {
        let server = FakeServer()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pool = makePool(server, dir: dir)
        _ = await pool.translate("Who the fuck are you?")
        await pool.setEnabled(false)
        await pool.save()
        let reopened = makePool(FakeServer(), dir: dir)
        XCTAssertEqual(reopened.store.match("Who the fuck are you?"), "Kim lan sen?")
    }
}
