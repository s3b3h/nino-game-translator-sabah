// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import CouchSubsCore

final class SystemHealthTests: XCTestCase {
    /// Elle ilerletilen saat.
    private final class Clock: @unchecked Sendable {
        var time = Date(timeIntervalSince1970: 1_000_000)
        func advance(_ seconds: TimeInterval) { time.addTimeInterval(seconds) }
    }

    private func recorder(_ clock: Clock) -> HealthRecorder {
        HealthRecorder(now: { clock.time })
    }

    func testNothingMeasuredBeforeTranslationStarts() {
        let s = HealthRecorder().snapshot()
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(HealthReport.stream(s), .unknown)
        XCTAssertEqual(HealthReport.connection(s), .unknown)
        XCTAssertEqual(HealthReport.translation(s), .unknown)
    }

    /// Wi-Fi'deki Mac'in günlüğüne benzer: dakikada yüzlerce yeniden gönderim ve sık görüntü durması.
    func testLossyWifiStreamIsAProblemAndBlamesWifi() {
        let clock = Clock()
        let health = recorder(clock)
        health.sessionStarted()
        health.connecting()
        health.streaming()
        for _ in 0..<1400 { health.remotePlayLine("[chiaki info] Takion Send Buffer re-sending packet with seqnum 0xb5f23702, tries: 5") }
        for _ in 0..<300 { health.remotePlayLine("[chiaki error] Takion Send Buffer overflow") }
        for _ in 0..<5 {
            health.remotePlayLine("[chiaki warning] FEC failed, waiting for IDR frame")
            health.remotePlayLine("[chiaki info] Received IDR frame")
        }
        clock.advance(60)
        let s = health.snapshot()
        XCTAssertEqual(s.resends, 1400)
        XCTAssertEqual(s.overflows, 300)
        XCTAssertEqual(s.stalls, 5)
        XCTAssertEqual(HealthReport.stream(s), .problem)
        XCTAssertEqual(HealthReport.network(.wifi, stream: .problem), .problem)
        XCTAssertEqual(HealthReport.network(.wired, stream: .problem), .good)
    }

    /// Kablolu sağlıklı Mac: kayıp yok, dakikada ~1 durma, bozuk kare bildirimleri (bunlar tek başına karar vermez).
    func testHealthyWiredStreamIsGood() {
        let clock = Clock()
        let health = recorder(clock)
        health.sessionStarted()
        health.streaming()
        for _ in 0..<20 { health.remotePlayLine("[chiaki warning] StreamConnection reporting corrupt frame(s) from 1 to 2") }
        health.remotePlayLine("[chiaki warning] Video FEC failure")
        clock.advance(120)
        let s = health.snapshot()
        XCTAssertEqual(s.corruptFrames, 20)
        XCTAssertEqual(HealthReport.stream(s), .good)
        XCTAssertEqual(HealthReport.network(.wifi, stream: .good), .good)
    }

    func testWifiIsNotGreenBeforeThePictureIsMeasured() {
        XCTAssertEqual(HealthReport.network(.wifi, stream: .unknown), .unknown)
        XCTAssertEqual(HealthReport.network(.wired, stream: .unknown), .good)
        XCTAssertEqual(HealthReport.network(.offline, stream: .unknown), .problem)
    }

    /// libchiaki bir durmada birkaç FEC satırı yazar; durma bir kez sayılır, anahtar kare gelince yenisi sayılabilir.
    func testOneStallPerFreezeUntilKeyFrameArrives() {
        let health = HealthRecorder()
        health.sessionStarted()
        health.remotePlayLine("[chiaki warning] FEC failed, waiting for IDR frame")
        health.remotePlayLine("[chiaki warning] Video FEC failure")
        health.remotePlayLine("[chiaki warning] FEC failed, waiting for IDR frame")
        XCTAssertEqual(health.snapshot().stalls, 1)
        health.remotePlayLine("[chiaki info] Received IDR frame")
        health.remotePlayLine("[chiaki warning] FEC failed, waiting for IDR frame")
        XCTAssertEqual(health.snapshot().stalls, 2)
    }

    func testRatesWaitForEnoughStreaming() {
        let clock = Clock()
        let health = recorder(clock)
        health.sessionStarted()
        health.streaming()
        health.remotePlayLine("FEC failed")
        clock.advance(5)
        XCTAssertNil(health.snapshot().stallsPerMinute)
        XCTAssertEqual(HealthReport.stream(health.snapshot()), .unknown)
    }

    func testStreamingTimeOnlyCountsWhilePictureArrives() {
        let clock = Clock()
        let health = recorder(clock)
        health.sessionStarted()
        health.connecting()
        clock.advance(100)
        health.streaming()
        clock.advance(60)
        health.disconnected(reason: "network")
        clock.advance(100)
        let s = health.snapshot()
        XCTAssertEqual(s.streamingSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(s.drops, 1)
        XCTAssertEqual(s.lastDisconnect, "network")
    }

    func testNeverConnectingIsAProblem() {
        let health = HealthRecorder()
        health.sessionStarted()
        health.connecting()
        health.disconnected(reason: "notFound")
        health.connecting()
        health.disconnected(reason: "notFound")
        let s = health.snapshot()
        XCTAssertEqual(HealthReport.connection(s), .problem)
        XCTAssertEqual(s.drops, 0, "görüntü hiç gelmeden kopma, akışta kopma sayılmaz")
    }

    func testFrequentDropsWarn() {
        let health = HealthRecorder()
        health.sessionStarted()
        for _ in 0..<3 {
            health.connecting()
            health.streaming()
            health.disconnected(reason: "network")
        }
        XCTAssertEqual(HealthReport.connection(health.snapshot()), .warning)
    }

    func testUserStopIsNotADrop() {
        let health = HealthRecorder()
        health.sessionStarted()
        health.streaming()
        health.disconnected(reason: nil)
        XCTAssertEqual(health.snapshot().drops, 0)
    }

    func testTranslationTimeUsesMedianAndIgnoresPackLines() {
        let health = HealthRecorder()
        health.sessionStarted()
        for ms in [400, 500, 600, 9000] { health.line(translationMs: ms) }
        health.line(translationMs: nil)
        var s = health.snapshot()
        XCTAssertEqual(s.lines, 5)
        XCTAssertEqual(s.translations, 4)
        XCTAssertEqual(s.translationMaxMs, 9000)
        XCTAssertEqual(HealthReport.translation(s), .good, "tek yavaş satır ortancayı bozmaz")
        for _ in 0..<10 { health.line(translationMs: 3500) }
        s = health.snapshot()
        XCTAssertEqual(HealthReport.translation(s), .problem)
    }

    func testCountsSurviveSessionEndAndResetOnNextStart() {
        let health = HealthRecorder()
        health.sessionStarted()
        health.remotePlayLine("Takion Send Buffer overflow")
        health.sessionEnded()
        var s = health.snapshot()
        XCTAssertFalse(s.active)
        XCTAssertEqual(s.overflows, 1)
        health.sessionStarted()
        s = health.snapshot()
        XCTAssertTrue(s.active)
        XCTAssertEqual(s.overflows, 0)
    }

    func testSummaryHasCountsButNoSubtitleText() {
        let health = HealthRecorder()
        health.sessionStarted()
        health.remotePlayLine("Takion Send Buffer overflow")
        let text = HealthReport.summary(health.snapshot(), network: .wifi)
        XCTAssertTrue(text.contains("ağ: wifi"))
        XCTAssertTrue(text.contains("tampon taşması 1"))
    }
}
