// SPDX-License-Identifier: AGPL-3.0-only
// Havuz öncelikli oyunlar: GTA 6'da çeviri yalnız Nino'nun havuzundan, gelmezse ücretsiz çeviriden; kullanıcının motoru
// hiç çağrılmaz (Windows: PoolFirstTranslatorTests ve TranslationPoolTests'in poolFirst bölümü).
import Foundation
import XCTest
import Vision
import CoreText
@testable import CouchSubsCore

final class PoolFirstTests: XCTestCase {
    final class Server: @unchecked Sendable {
        let lock = NSLock()
        var config = #"{"ok":true,"translate":{"enabled":true,"deadlineMs":900,"syncSeconds":180,"contextLines":4,"maxLines":12}}"#
        var translate = #"{"ok":true,"translations":[{"text":"Bin arabaya!","tier":1}]}"#
        var status = 200
        var delay: UInt64 = 0
        private(set) var translateBodies: [String] = []

        func handle(_ request: URLRequest) async -> (Data, URLResponse) {
            let path = request.url!.path
            let (body, status, delay): (String, Int, UInt64) = lock.withLock {
                if path.hasSuffix("/v1/translate") {
                    translateBodies.append(String(decoding: request.httpBody ?? Data(), as: UTF8.self))
                    return (translate, self.status, self.delay)
                }
                return (path.hasSuffix("/v1/config") ? config : #"{"ok":true}"#, 200, 0)
            }
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        var asked: Int { lock.withLock { translateBodies.count } }
    }

    func makePool(_ server: Server, enabled: Bool = true) -> TranslationPool {
        TranslationPool(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                        endpoint: URL(string: "https://pool.test")!, install: UUID().uuidString.lowercased(),
                        app: "0.2.2", platform: "test", language: "tr", enabled: enabled, send: { await server.handle($0) })
    }

    // MARK: Havuz

    func testDefaultsToGta6() {
        let pool = makePool(Server())
        XCTAssertTrue(pool.isPoolFirst("Grand Theft Auto VI"))
        XCTAssertTrue(pool.isPoolFirst("GTA VI"))
        XCTAssertTrue(pool.isPoolFirst("gta6"))
        XCTAssertFalse(pool.isPoolFirst("Grand Theft Auto V"))
        XCTAssertFalse(pool.isPoolFirst("Red Dead Redemption 2"))
        XCTAssertFalse(pool.isPoolFirst(nil))
        XCTAssertEqual(pool.poolFirst.deadlineMs, 1500)
    }

    func testListAndDeadlineComeFromServer() async {
        let server = Server()
        server.config = #"{"ok":true,"translate":{"enabled":true,"deadlineMs":900,"syncSeconds":180,"contextLines":4,"maxLines":12},"poolFirst":{"games":["mafia-the-old-country"],"deadlineMs":700}}"#
        let pool = makePool(server)
        await pool.refreshConfig(force: true)
        XCTAssertTrue(pool.isPoolFirst("Mafia: The Old Country"))
        XCTAssertFalse(pool.isPoolFirst("Grand Theft Auto VI"))
        XCTAssertEqual(pool.poolFirst.deadlineMs, 700)
    }

    func testOffWhenServerTurnsTranslationOff() async {
        let server = Server()
        server.config = #"{"ok":true,"translate":{"enabled":false,"deadlineMs":900,"syncSeconds":180,"contextLines":4,"maxLines":12}}"#
        let pool = makePool(server)
        await pool.refreshConfig(force: true)
        XCTAssertFalse(pool.isPoolFirst("Grand Theft Auto VI"))
    }

    func testAskedEvenWhenSharingIsOff() async {
        let server = Server()
        let pool = makePool(server, enabled: false)
        let gta = await pool.translate("Get in the car!", game: "Grand Theft Auto VI")
        XCTAssertEqual(gta, "Bin arabaya!")
        let other = await pool.translate("Open the door now.", game: "Red Dead Redemption 2")
        XCTAssertNil(other)
        XCTAssertEqual(server.asked, 1)
    }

    func testDeadlineReturnsNilButLateAnswerIsKept() async {
        let server = Server()
        server.config = #"{"ok":true,"translate":{"enabled":true,"deadlineMs":900,"syncSeconds":180,"contextLines":4,"maxLines":12},"poolFirst":{"games":["grand-theft-auto-vi"],"deadlineMs":150}}"#
        server.delay = 600_000_000
        let pool = makePool(server)
        await pool.refreshConfig(force: true)
        let started = Date()
        let first = await pool.translateFirst("Get in the car!", game: "Grand Theft Auto VI")
        XCTAssertNil(first)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        // Süren istek beklenir; geç gelen çeviri havuza yazılır, ikinci istek gitmez.
        let late = await pool.translate("Get in the car!", game: "Grand Theft Auto VI")
        XCTAssertEqual(late, "Bin arabaya!")
        XCTAssertEqual(server.asked, 1)
        XCTAssertEqual(pool.store.match("Get in the car!"), "Bin arabaya!")
    }

    func testBudgetOrErrorGivesNil() async {
        let server = Server()
        server.translate = #"{"ok":true,"limited":"daily_cap","translations":[{"text":null,"tier":0}]}"#
        let pool = makePool(server)
        let capped = await pool.translateFirst("Get in the car!", game: "Grand Theft Auto VI")
        XCTAssertNil(capped)
        server.status = 500
        let failed = await pool.translateFirst("Open the door now.", game: "Grand Theft Auto VI")
        XCTAssertNil(failed)
    }

    func testServerRecognisedGameMakesItPoolFirst() async {
        let server = Server()
        server.translate = #"{"ok":true,"game":"grand-theft-auto-vi","translations":[{"text":"Bin arabaya!","tier":1}]}"#
        let pool = makePool(server)
        XCTAssertFalse(pool.isPoolFirst(nil))
        _ = await pool.translate("Get in the car!", game: "Call of Duty: Modern Warfare")
        XCTAssertTrue(pool.isPoolFirst(nil))
        XCTAssertTrue(pool.isPoolFirst("Call of Duty: Modern Warfare"))
        server.translate = #"{"ok":true,"game":"red-dead-redemption-2","translations":[{"text":"Aç.","tier":1}]}"#
        _ = await pool.translate("Open it now.", game: "Red Dead Redemption 2")
        XCTAssertFalse(pool.isPoolFirst(nil))
    }

    // MARK: Çevirmen

    final class Counting: TextTranslator, @unchecked Sendable {
        let answer: String
        let together: Bool
        let lock = NSLock()
        var translated: [String] = []
        init(_ answer: String, together: Bool = false) { self.answer = answer; self.together = together }
        func translate(_ text: String) async throws -> String {
            lock.withLock { translated.append(text) }
            return answer
        }
        func translateAll(_ texts: [String]) async throws -> [String] {
            lock.withLock { translated += texts }
            return texts.map { _ in answer }
        }
        var translatesTogether: Bool { together }
    }

    func testPoolFirstGameNeverCallsTheEngine() async throws {
        let engine = Counting("gemini", together: true), free = Counting("ücretsiz")
        let translator = PoolFirstTranslator(engine: engine, free: free, poolFirst: { true }, ask: { _ in "havuz" })
        let one = try await translator.translate("Get in the car!")
        XCTAssertEqual(one, "havuz")
        let all = try await translator.translateAll(["a line", "another line"])
        XCTAssertEqual(all, ["havuz", "havuz"])
        XCTAssertFalse(translator.translatesTogether)
        XCTAssertTrue(engine.translated.isEmpty)
        XCTAssertTrue(free.translated.isEmpty)
        XCTAssertEqual(translator.lastSource, "havuz")
    }

    func testSilenceFallsBackToFreeOnly() async throws {
        let engine = Counting("gemini"), free = Counting("ücretsiz")
        let translator = PoolFirstTranslator(engine: engine, free: free, poolFirst: { true }, ask: { _ in nil })
        let text = try await translator.translate("Get in the car!")
        XCTAssertEqual(text, "ücretsiz")
        let blank = PoolFirstTranslator(engine: engine, free: free, poolFirst: { true }, ask: { _ in "  " })
        let second = try await blank.translate("Get in the car!")
        XCTAssertEqual(second, "ücretsiz")
        XCTAssertTrue(engine.translated.isEmpty)
        XCTAssertEqual(free.translated.count, 2)
    }

    func testOtherGamesUseTheEngine() async throws {
        let engine = Counting("gemini", together: true), free = Counting("ücretsiz")
        var asked = 0
        let translator = PoolFirstTranslator(engine: engine, free: free, poolFirst: { false }, ask: { _ in asked += 1; return "havuz" })
        let text = try await translator.translate("Hello there.")
        XCTAssertEqual(text, "gemini")
        XCTAssertTrue(translator.translatesTogether)
        XCTAssertEqual(asked, 0)
        XCTAssertTrue(free.translated.isEmpty)
    }

    func testUnsureGameAsksPoolThenEngine() async throws {
        let engine = Counting("gemini"), free = Counting("ücretsiz")
        let hit = PoolFirstTranslator(engine: engine, free: free, poolFirst: { false }, ask: { _ in "havuz" }, probe: { true })
        let first = try await hit.translate("Get in the car!")
        XCTAssertEqual(first, "havuz")
        let miss = PoolFirstTranslator(engine: engine, free: free, poolFirst: { false }, ask: { _ in nil }, probe: { true })
        let second = try await miss.translate("Get in the car!")
        XCTAssertEqual(second, "gemini")
        XCTAssertTrue(free.translated.isEmpty)
    }

    func testContextBeforeDoesNotAddTheLine() {
        let context = PoolContext()
        _ = context.add("One.")
        _ = context.add("Two.")
        XCTAssertEqual(context.before("Three."), ["One.", "Two."])
        XCTAssertEqual(context.before("Two."), ["One."])
        XCTAssertEqual(context.add("Three."), ["One.", "Two."])
    }
}

/// Vision takılınca okuma kapısı sonsuza dek kilitli kalmasın: kapı yenilenince sonraki okuma yeni kapıdan girer.
final class VisionWatchTests: XCTestCase {
    func testStuckGateIsReplaced() {
        let watch = VisionReader.Watch()
        let stuck = watch.gate
        stuck.lock()
        XCTAssertFalse(stuck.lock(before: Date().addingTimeInterval(0.05)))
        watch.replace(stuck)
        let fresh = watch.gate
        XCTAssertFalse(fresh === stuck)
        XCTAssertTrue(fresh.lock(before: Date().addingTimeInterval(0.05)))
        fresh.unlock()
        // Eski kapıyı tutan sonradan bırakınca yeni kapı değişmez.
        watch.replace(stuck)
        XCTAssertTrue(watch.gate === fresh)
        stuck.unlock()
    }
}

final class VisionCPUTests: XCTestCase {
    /// İşlemciye geçen istek yine okur (Neural Engine takılınca kullanılan yol).
    func testCPURequestStillReads() throws {
        let size = CGSize(width: 600, height: 120)
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Get in the car", attributes: [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 48, nil),
            .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)]))
        context.textPosition = CGPoint(x: 30, y: 40)
        CTLineDraw(line, context)
        let image = context.makeImage()!
        let request = VNRecognizeTextRequest()
        VisionReader.runOnCPU(request)
        try VNImageRequestHandler(cgImage: image).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(text.lowercased().contains("car"), text)
    }
}
