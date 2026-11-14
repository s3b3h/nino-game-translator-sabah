import XCTest
@testable import CouchSubsCore

final class VoiceTrackerTests: XCTestCase {
    /// Sesli konuşmaya benzeyen sinyal: temel perde + harmonikler (renk `tilt` ile değişir), biraz gürültü.
    private func voice(_ f0: Double, seconds: Double, tilt: Double = 0.7, amplitude: Float = 0.2) -> [Float] {
        let n = Int(seconds * VoiceTracker.sampleRate)
        var rng = SystemRandomNumberGenerator()
        return (0..<n).map { i in
            let t = Double(i) / VoiceTracker.sampleRate
            var s = 0.0
            for h in 1...12 { s += pow(tilt, Double(h - 1)) * sin(2 * .pi * f0 * Double(h) * t) }
            let noise = Double(Int.random(in: -100...100, using: &rng)) / 4000
            return Float(s * 0.3 + noise) * amplitude
        }
    }

    func testMaleAndFemalePitch() throws {
        let male = try XCTUnwrap(VoiceTracker.analyze(voice(110, seconds: 1)))
        let female = try XCTUnwrap(VoiceTracker.analyze(voice(215, seconds: 1)))
        // Harmonikleri güçlü erkek sesi iki katı (≈250 Hz) sanılmamalı.
        let strong = try XCTUnwrap(VoiceTracker.analyze(voice(125, seconds: 1, tilt: 0.97)))
        XCTAssertEqual(strong.pitch, 125, accuracy: 8)
        XCTAssertEqual(male.pitch, 110, accuracy: 6)
        XCTAssertEqual(female.pitch, 215, accuracy: 10)
        XCTAssertEqual(male.gender, .male)
        XCTAssertEqual(female.gender, .female)
    }

    func testSilenceAndNoiseGiveNothing() {
        XCTAssertNil(VoiceTracker.analyze([Float](repeating: 0, count: 16_000)))
        var rng = SystemRandomNumberGenerator()
        let noise = (0..<16_000).map { _ in Float(Int.random(in: -1000...1000, using: &rng)) / 5000 }
        XCTAssertNil(VoiceTracker.analyze(noise))
    }

    func testTrackerWindow() throws {
        let tracker = VoiceTracker(seconds: 5)
        tracker.append(voice(120, seconds: 1), at: 10)
        tracker.append(voice(220, seconds: 1), at: 11)
        let first = try XCTUnwrap(tracker.analyze(from: 9.05, to: 9.95))
        let second = try XCTUnwrap(tracker.analyze(from: 10.05, to: 10.95))
        XCTAssertEqual(first.gender, .male)
        XCTAssertEqual(second.gender, .female)
    }

    /// Üç erkek: perdeleri ya da renkleri farklı; aynı kişi tekrar konuşunca aynı numarayı alır.
    func testSpeakersAreToldApart() throws {
        var book = SpeakerBook()
        let arthur = try XCTUnwrap(VoiceTracker.analyze(voice(105, seconds: 1, tilt: 0.75)))
        let dutch = try XCTUnwrap(VoiceTracker.analyze(voice(135, seconds: 1, tilt: 0.55)))
        let kieran = try XCTUnwrap(VoiceTracker.analyze(voice(150, seconds: 1, tilt: 0.85)))
        let a = book.identify(arthur).id, d = book.identify(dutch).id, k = book.identify(kieran).id
        XCTAssertEqual(Set([a, d, k]).count, 3)
        let again = try XCTUnwrap(VoiceTracker.analyze(voice(107, seconds: 1, tilt: 0.75)))
        XCTAssertEqual(book.identify(again).id, a)
    }
}

final class EmotionMeterTests: XCTestCase {
    private func sample(_ pitch: Double, _ loudness: Double, spread: Double = 2) -> VoiceSample {
        VoiceSample(pitch: pitch, voiced: 1, print: [], loudness: loudness, spread: spread)
    }

    func testShoutingBecomesAngryAndFaster() {
        var meter = EmotionMeter()
        for _ in 0..<4 { _ = meter.delivery(for: sample(120, -30), speaker: 1, english: "We ride at dawn.", textEmotion: nil) }
        let shout = meter.delivery(for: sample(160, -18, spread: 4), speaker: 1, english: "Get down", textEmotion: nil)
        XCTAssertEqual(shout.emotion, .angry)
        XCTAssertGreaterThan(shout.rate, 1)
        XCTAssertGreaterThan(shout.gain, 0)
        let asked = meter.delivery(for: sample(165, -17), speaker: 1, english: "What did you do?", textEmotion: nil)
        XCTAssertEqual(asked.emotion, .surprised)
    }

    func testQuietBecomesCalmAndSofter() {
        var meter = EmotionMeter()
        for _ in 0..<4 { _ = meter.delivery(for: sample(120, -25), speaker: 1, english: "Fine.", textEmotion: nil) }
        let whisper = meter.delivery(for: sample(110, -38), speaker: 1, english: "Keep quiet.", textEmotion: nil)
        XCTAssertEqual(whisper.emotion, .calm)
        XCTAssertLessThan(whisper.gain, 0)
    }

    func testNormalLineStaysPlainUntilBaselineKnown() {
        var meter = EmotionMeter()
        XCTAssertEqual(meter.delivery(for: sample(120, -10), speaker: 1, english: "Hey!", textEmotion: nil).rate, 1)
    }

    func testStyledAudioIsShorterAndLouderButNotClipped() {
        let audio = SpeechAudio(samples: (0..<24_000).map { Float(sin(Double($0) / 10)) * 0.5 }, sampleRate: 24_000)
        let styled = audio.styled(rate: 1.1, gain: 6)
        XCTAssertLessThan(styled.duration, audio.duration)
        XCTAssertLessThanOrEqual(styled.samples.map(abs).max()!, 0.981)
    }
}

final class RisingEndTests: XCTestCase {
    /// 120 Hz'lik ses: son kısmı +4 yarım tona (≈151 Hz) çıkmalı, baş kısmı aynı kalmalı, süre değişmemeli.
    func testEndPitchRisesAndLengthStays() throws {
        let rate = 16_000
        let tone = (0..<(rate * 2)).map { i -> Float in
            let t = Double(i) / Double(rate)
            return Float((1...6).reduce(0.0) { $0 + pow(0.6, Double($1 - 1)) * sin(2 * .pi * 120 * Double($1) * t) }) * 0.2
        }
        let audio = SpeechAudio(samples: tone, sampleRate: rate).withRisingEnd(semitones: 4, from: 0.5)
        XCTAssertEqual(audio.samples.count, tone.count)
        let head = try XCTUnwrap(VoiceTracker.analyze(Array(audio.samples[0..<8000])))
        let tail = try XCTUnwrap(VoiceTracker.analyze(Array(audio.samples[26_000..<32_000])))
        XCTAssertEqual(head.pitch, 120, accuracy: 6)
        XCTAssertGreaterThan(tail.pitch, 134); print("KUYRUK PERDE", tail.pitch)
    }
}


final class QuietGateTests: XCTestCase {
    func testQuietSoundsAreNotSpeechEvenAtSessionStart() {
        let meter = EmotionMeter()
        XCTAssertTrue(meter.isTooQuiet(VoiceSample(pitch: 230, voiced: 1, print: [], loudness: -38, spread: 4)))
        XCTAssertFalse(meter.isTooQuiet(VoiceSample(pitch: 125, voiced: 1, print: [], loudness: -23, spread: 2)))
    }
}
