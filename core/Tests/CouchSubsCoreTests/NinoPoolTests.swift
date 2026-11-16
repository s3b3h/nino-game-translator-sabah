// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import Foundation
import XCTest

final class NinoPoolTests: XCTestCase {
    /// Sahte sunucu: gelen parçaları kaydeder, yanıtı sırayla verilen kurallardan üretir.
    final class FakeServer: @unchecked Sendable {
        enum Answer { case ok, status(Int, retryAfter: String? = nil), offline, lostAck, wrongBody }
        private let lock = NSLock()
        var answers: [Answer] = []
        var fallback: Answer = .ok
        private(set) var received: [NinoPool.Batch] = []
        private(set) var paths: [String] = []

        var send: NinoPool.Send {
            { [self] request in
                let batch = try JSONDecoder().decode(NinoPool.Batch.self, from: request.httpBody ?? Data())
                let answer: Answer = lock.withLock {
                    paths.append(request.url?.path ?? "")
                    return answers.isEmpty ? fallback : answers.removeFirst()
                }
                func reply(_ code: Int, _ body: String, _ headers: [String: String] = [:]) -> (Data, URLResponse) {
                    (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!)
                }
                switch answer {
                case .ok:
                    lock.withLock { received.append(batch) }
                    return reply(200, #"{"ok":true,"batch":"\#(batch.batch)","accepted":\#(batch.lines.count),"rejected":[]}"#)
                case let .status(code, retryAfter):
                    return reply(code, #"{"ok":false}"#, retryAfter.map { ["Retry-After": $0] } ?? [:])
                case .offline:
                    throw URLError(.notConnectedToInternet)
                case .lostAck:
                    lock.withLock { received.append(batch) }
                    throw URLError(.networkConnectionLost)
                case .wrongBody:
                    return reply(200, "<html>captive portal</html>")
                }
            }
        }

        var lines: [NinoPool.WireLine] { lock.withLock { received.flatMap(\.lines) } }
    }

    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_763_300_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    var directory: URL!
    let endpoint = URL(string: "http://localhost:8787")!
    let server = FakeServer()
    let clock = Clock()

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ninopool-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func makePool(endpoint: URL?? = nil, app: String = "0.1.6", enabled: Bool = true, legacy: URL? = nil,
                  limits: NinoPool.Limits = NinoPool.Limits()) -> NinoPool {
        let clock = self.clock
        return NinoPool(directory: directory, endpoint: endpoint ?? self.endpoint, app: app, platform: "mac", enabled: enabled,
                        legacyFile: legacy, limits: limits, send: server.send, clock: { clock.now })
    }

    // MARK: - Kalıcılık

    func testLineIsOnDiskImmediatelyAndSurvivesCrash() async {
        let pool = makePool()
        let accepted = await pool.offer("Where is Lamar going?", game: "gta-v")
        XCTAssertTrue(accepted)
        // `close()` çağrılmadan (çökme gibi) yeni örnek açılır.
        let reopened = makePool()
        let status = await reopened.status()
        XCTAssertEqual(status.pendingLines, 1)
        await reopened.flush(force: true)
        XCTAssertEqual(server.lines.map(\.text), ["Where is Lamar going?"])
        XCTAssertEqual(server.lines.first?.game, "gta-v")
    }

    func testNoEndpointKeepsLinesQueued() async {
        let pool = makePool(endpoint: .some(nil))
        await pool.offer("This line waits for a server.")
        await pool.flush(force: true)
        XCTAssertTrue(server.received.isEmpty)
        let status = await pool.status()
        XCTAssertEqual(status.pendingLines, 1)
        XCTAssertFalse(status.hasEndpoint)
        // Adres gelince gider.
        await pool.setEndpoint(endpoint)
        await pool.flush(force: true)
        XCTAssertEqual(server.lines.count, 1)
    }

    func testTornLastLineIsSkippedOthersKept() async throws {
        let pool = makePool()
        await pool.offer("First full line here.")
        await pool.offer("Second full line here.")
        await pool.close()
        let pending = directory.appendingPathComponent("pending.jsonl")
        let handle = try FileHandle(forWritingTo: pending)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"s":3,"t":"Half writ"#.utf8))
        try handle.close()
        let reopened = makePool()
        await reopened.offer("Third full line here.")
        await reopened.flush(force: true)
        XCTAssertEqual(Set(server.lines.map(\.text)), ["First full line here.", "Second full line here.", "Third full line here."])
    }

    func testOutboxSurvivesRestartBeforeSending() async {
        server.fallback = .offline
        let pool = makePool()
        await pool.offer("Frozen but not sent.")
        await pool.flush(force: true)
        let status = await pool.status()
        XCTAssertEqual(status.outboxBatches, 1)
        XCTAssertEqual(status.pendingLines, 0)
        server.fallback = .ok
        let reopened = makePool()
        await reopened.flush()
        XCTAssertEqual(server.lines.map(\.text), ["Frozen but not sent."])
        let after = await reopened.status()
        XCTAssertEqual(after.outboxBatches, 0)
    }

    func testCrashBetweenOutboxAndStateDoesNotDoubleSend() async throws {
        server.fallback = .offline
        let pool = makePool()
        await pool.offer("Counted exactly once.")
        await pool.flush(force: true)
        // Durum dosyası parçadan önceki hâline döner (parça yazıldı, durum yazılamadan kapandı) ve bekleyen satır geri gelir.
        let stateURL = directory.appendingPathComponent("state.json")
        var state = try JSONDecoder().decode(NinoPool.State.self, from: Data(contentsOf: stateURL))
        state.frozenThrough = 0
        state.nextAttempt = 0
        try JSONEncoder().encode(state).write(to: stateURL)
        let sighting = NinoPool.Sighting(s: 1, t: "Counted exactly once.", g: nil, e: nil, a: clock.now.timeIntervalSince1970)
        try (JSONEncoder().encode(sighting) + Data([0x0A])).write(to: directory.appendingPathComponent("pending.jsonl"))
        server.fallback = .ok
        let reopened = makePool()
        let status = await reopened.status()
        XCTAssertEqual(status.pendingLines, 0)
        await reopened.flush(force: true)
        XCTAssertEqual(server.lines.map(\.count), [1])
    }

    func testCrashMidFreezeKeepsUnwrittenChunks() async throws {
        server.fallback = .offline
        var limits = NinoPool.Limits()
        limits.batchSize = 3
        let pool = makePool(limits: limits)
        for index in 0..<7 { await pool.offer("Chunked line number \(index).") }
        await pool.close()
        let pending = try Data(contentsOf: directory.appendingPathComponent("pending.jsonl"))
        await pool.flush(force: true)
        // Çökme: yalnız ilk parça diske yazılmış, durum yazılamamış, bekleyenler henüz silinmemiş.
        let outbox = NinoPool.batchFiles(in: directory.appendingPathComponent("outbox"))
        XCTAssertEqual(outbox.count, 3)
        for file in outbox.dropFirst() { try FileManager.default.removeItem(at: file) }
        try pending.write(to: directory.appendingPathComponent("pending.jsonl"))
        let stateURL = directory.appendingPathComponent("state.json")
        var state = try JSONDecoder().decode(NinoPool.State.self, from: Data(contentsOf: stateURL))
        state.frozenThrough = 0
        try JSONEncoder().encode(state).write(to: stateURL)
        server.fallback = .ok
        let reopened = makePool(limits: limits)
        await reopened.flush(force: true)
        XCTAssertEqual(Set(server.lines.map(\.text)), Set((0..<7).map { "Chunked line number \($0)." }))
        XCTAssertEqual(server.lines.count, 7)
        XCTAssertTrue(server.lines.allSatisfy { $0.count == 1 })
    }

    func testInertPoolKeepsQueue() async {
        server.fallback = .offline
        let pool = makePool()
        await pool.offer("Waiting line stays put.")
        await pool.flush(force: true)
        await pool.offer("Pending line stays put.")
        // Test ya da klip çalışması: havuz kapalı açılır ama kuyruk silinmez.
        let inert = makePool(enabled: false)
        let accepted = await inert.offer("Not taken while inert.")
        XCTAssertFalse(accepted)
        let status = await inert.status()
        XCTAssertEqual(status.outboxBatches, 1)
        XCTAssertEqual(status.pendingLines, 1)
    }

    func testLargeQueueOpensQuickly() async throws {
        var data = Data()
        let encoder = JSONEncoder()
        for index in 0..<50_000 {
            let sighting = NinoPool.Sighting(s: Int64(index + 1), t: "Seeded line number \(index) for timing.", g: "gta-v",
                                             e: nil, a: 1_763_300_000)
            data.append(try encoder.encode(sighting))
            data.append(0x0A)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("pending.jsonl"))
        let start = Date()
        let pool = makePool()
        let elapsed = Date().timeIntervalSince(start)
        let status = await pool.status()
        XCTAssertEqual(status.pendingLines, 50_000)
        print("50 000 bekleyen satırla açılış: \(String(format: "%.2f", elapsed)) sn")
        XCTAssertLessThan(elapsed, 3)
    }

    // MARK: - Gönderim

    func testRepeatsAreCountedAndBatched() async {
        var limits = NinoPool.Limits()
        limits.batchSize = 3
        let pool = makePool(limits: limits)
        for _ in 0..<4 { await pool.offer("Same line again and again.", game: "GTA V") }
        clock.advance(10)
        await pool.offer("Same line again and again.", game: "GTA V")
        for index in 0..<4 { await pool.offer("Different line number \(index).") }
        await pool.flush(force: true)
        XCTAssertEqual(server.received.count, 2)
        XCTAssertEqual(server.received.map(\.lines.count), [3, 2])
        let repeated = server.lines.first { $0.text == "Same line again and again." }
        XCTAssertEqual(repeated?.count, 5)
        XCTAssertEqual(repeated?.game, "gta-v")
        XCTAssertEqual(repeated.map { $0.last - $0.first }, 10)
        let sessions = Set(server.lines.compactMap(\.session))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(server.paths.first, "/v1/batches")
    }

    func testWaitsBeforeSendingSmallAmounts() async {
        let pool = makePool()
        await pool.offer("Not sent right away.")
        await pool.flush()
        XCTAssertTrue(server.received.isEmpty)
        clock.advance(NinoPool.sendEvery)
        await pool.flush()
        XCTAssertEqual(server.lines.count, 1)
    }

    func testServerErrorKeepsBatchWithGrowingBackoff() async {
        server.fallback = .status(500)
        let pool = makePool()
        await pool.offer("Server is down right now.")
        await pool.flush(force: true)
        XCTAssertEqual(server.paths.count, 1)
        // Bekleme dolmadan yeniden denenmez.
        clock.advance(10)
        await pool.flush()
        XCTAssertEqual(server.paths.count, 1)
        clock.advance(40)
        await pool.flush()
        XCTAssertEqual(server.paths.count, 2)
        // İkinci hatadan sonra bekleme ~60 sn: 40 sn yetmez.
        clock.advance(40)
        await pool.flush()
        XCTAssertEqual(server.paths.count, 2)
        server.fallback = .ok
        clock.advance(40)
        await pool.flush()
        XCTAssertEqual(server.lines.map(\.text), ["Server is down right now."])
        let status = await pool.status()
        XCTAssertEqual(status.outboxBatches, 0)
    }

    func testNetworkBackResetsBackoff() async {
        server.fallback = .offline
        let pool = makePool()
        await pool.offer("Sent when network returns.")
        await pool.flush(force: true)
        await pool.flush(force: true)
        XCTAssertEqual(server.paths.count, 1)
        server.fallback = .ok
        await pool.networkAvailable()
        XCTAssertEqual(server.lines.count, 1)
    }

    func testLostAckResendsSameBatchID() async {
        server.answers = [.lostAck]
        let pool = makePool()
        await pool.offer("The reply never arrived.")
        await pool.flush(force: true)
        await pool.networkAvailable()
        XCTAssertEqual(server.received.count, 2)
        XCTAssertEqual(server.received[0].batch, server.received[1].batch)
    }

    func testForeignOKDoesNotDeleteBatch() async {
        server.answers = [.wrongBody]
        let pool = makePool()
        await pool.offer("Captive portal says OK.")
        await pool.flush(force: true)
        let status = await pool.status()
        XCTAssertEqual(status.outboxBatches, 1)
        await pool.networkAvailable()
        XCTAssertEqual(server.lines.count, 1)
    }

    func testRetryAfterIsRespected() async {
        server.answers = [.status(429, retryAfter: "600")]
        let pool = makePool()
        await pool.offer("Slow down, please.")
        await pool.flush(force: true)
        await pool.networkAvailable()
        clock.advance(599)
        await pool.flush()
        XCTAssertTrue(server.received.isEmpty)
        clock.advance(2)
        await pool.flush()
        XCTAssertEqual(server.lines.count, 1)
    }

    func testRejectedBatchIsParkedAndRetriedAfterUpdate() async {
        server.answers = [.status(400)]
        let pool = makePool()
        await pool.offer("Server did not like this.")
        await pool.offer("Nor this one.")
        await pool.flush(force: true)
        let status = await pool.status()
        XCTAssertEqual(status.outboxBatches, 0)
        XCTAssertEqual(status.parkedBatches, 1)
        // Aynı sürümde yeniden açılınca kenarda kalır; yeni sürümde yeniden denenir.
        await makePool().flush(force: true)
        XCTAssertTrue(server.received.isEmpty)
        let updated = makePool(app: "0.1.7")
        await updated.flush()
        XCTAssertEqual(server.lines.count, 2)
    }

    func testTooLargeBatchIsSplit() async {
        server.answers = [.status(413)]
        let pool = makePool()
        for index in 0..<5 { await pool.offer("Split line number \(index).") }
        await pool.flush(force: true)
        XCTAssertEqual(server.received.map(\.lines.count), [2, 3])
        XCTAssertEqual(Set(server.lines.map(\.text)).count, 5)
    }

    func testNotFoundIsRetriedNotDropped() async {
        server.answers = [.status(404)]
        let pool = makePool()
        await pool.offer("Wrong address for a while.")
        await pool.flush(force: true)
        let status = await pool.status()
        XCTAssertEqual(status.outboxBatches, 1)
        XCTAssertEqual(status.parkedBatches, 0)
    }

    // MARK: - Ayar ve süzgeç

    func testDisablingWipesEverything() async {
        server.fallback = .offline
        let pool = makePool()
        await pool.offer("Line before opting out.")
        await pool.flush(force: true)
        await pool.offer("Another before opting out.")
        await pool.setEnabled(false)
        let status = await pool.status()
        XCTAssertEqual(status.pendingLines + status.outboxBatches + status.parkedBatches, 0)
        let accepted = await pool.offer("Ignored while off.")
        XCTAssertFalse(accepted)
    }

    func testImportsLegacyQueueOnce() async throws {
        let legacy = directory.deletingLastPathComponent().appendingPathComponent("legacy-\(UUID().uuidString).json")
        let json = #"{"install":"x","queue":[{"text":"Old queued line here.","key":"k","firstSeen":"2026-11-11T03:17:00Z"},{"text":"Oturum Açtı","key":"k2","firstSeen":"2026-11-11T03:17:00Z"}],"sent":[]}"#
        try Data(json.utf8).write(to: legacy)
        defer { try? FileManager.default.removeItem(at: legacy.appendingPathExtension("imported")) }
        let pool = makePool(legacy: legacy)
        let status = await pool.status()
        XCTAssertEqual(status.pendingLines, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        _ = makePool(legacy: legacy)
        await pool.flush(force: true)
        XCTAssertEqual(server.lines.map(\.text), ["Old queued line here."])
        XCTAssertEqual(server.lines.first?.first, 1_794_367_020)
    }

    func testFilter() {
        XCTAssertTrue(NinoPool.accepts("Run!"))
        XCTAssertTrue(NinoPool.accepts("Where are you going, Franklin?"))
        XCTAssertFalse(NinoPool.accepts("Oturum Açtı"))
        XCTAssertFalse(NinoPool.accepts("PlayerOne signed in"))
        XCTAssertFalse(NinoPool.accepts("100/100 HP 25%"))
        XCTAssertFalse(NinoPool.accepts(String(repeating: "Long sentence. ", count: 40)))
        XCTAssertEqual(NinoPool.clean("  Hello\u{200B}\n  there.  "), "Hello there.")
        XCTAssertEqual(NinoPool.gameID("GTA V"), "gta-v")
        XCTAssertEqual(NinoPool.gameID("red-dead-redemption-2"), "red-dead-redemption-2")
        XCTAssertNil(NinoPool.gameID("  "))
        XCTAssertNil(NinoPool.gameID(nil))
    }

    func testEndpointConfiguration() {
        let defaults = UserDefaults(suiteName: "ninopool-\(UUID().uuidString)")!
        XCTAssertEqual(NinoPool.configuredEndpoint(environment: [:], defaults: defaults), NinoPool.liveEndpoint)
        defaults.set("http://localhost:9000", forKey: NinoPool.defaultsKey)
        XCTAssertEqual(NinoPool.configuredEndpoint(environment: [:], defaults: defaults)?.absoluteString, "http://localhost:9000")
        XCTAssertEqual(NinoPool.configuredEndpoint(environment: ["NINO_POOL_URL": "https://pool.example"], defaults: defaults)?.host,
                       "pool.example")
    }

    /// Yerel sunucuya (wrangler dev) gerçek gönderim: `NINO_POOL_E2E_URL=http://localhost:8787 swift test --filter NinoPoolE2E`.
    func testE2ELocalServer() async throws {
        guard let value = ProcessInfo.processInfo.environment["NINO_POOL_E2E_URL"], let url = URL(string: value) else {
            throw XCTSkip("NINO_POOL_E2E_URL yok")
        }
        let pool = NinoPool(directory: directory, endpoint: url, app: "e2e", platform: "mac")
        for text in ["You fucked up now, boy!", "Get down!", "GET DOWN!", "Where is Lamar going?"] {
            await pool.offer(text, game: "gta-v")
        }
        await pool.offer("A line from an unknown game.")
        await pool.offer("Oturum Açtı")
        await pool.flush(force: true)
        let status = await pool.status()
        XCTAssertEqual(status.outboxBatches, 0, "sunucu parçayı onaylamadı")
        XCTAssertEqual(status.pendingLines, 0)
        print("E2E kurulum: \(await pool.installID) oturum: \(await pool.sessionID)")
    }
}
