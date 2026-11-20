// SPDX-License-Identifier: AGPL-3.0-only
#if canImport(CoreGraphics)
import CoreGraphics
import XCTest
@testable import CouchSubsCore

private final class StaleReader: TextReader, @unchecked Sendable {
    var texts: [String]
    init(_ texts: [String]) { self.texts = texts }
    func read(_ image: CGImage) throws -> String { texts.isEmpty ? "" : texts.removeFirst() }
}
private final class StaleSender: SubtitleSending {
    var events: [String] = []
    func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) { events.append(text) }
    func clear() { events.append("<temizle>") }
}
private final class StaleTranslator: TextTranslator {
    func translate(_ text: String) async throws -> String {
        text == "You doing okay?" ? "İyi misin?" : "Çeviri"
    }
}

/// Nino (GTA 6): gösterilmeyen yeni satır geldiğinde önceki satırın kısa çevirisi TV'de kalmamalı; kalırsa kutusu yeni
/// ve daha uzun İngilizcenin üstünde durur, yazı iki yanından taşar.
@MainActor
final class StaleSubtitleTests: XCTestCase {
    private var image: CGImage {
        CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    private func run(_ readings: [String]) async -> [String] {
        var time = 0
        let sender = StaleSender()
        let frames = readings.flatMap { [$0, $0, $0] }
        let pipeline = SubtitlePipeline(reader: StaleReader(frames), translator: StaleTranslator(), server: sender,
                                        clock: { time })
        pipeline.targetLanguage = "tr"
        pipeline.packWait = 0; pipeline.cleanWait = 0; pipeline.holdReadings = true
        for _ in frames {
            await pipeline.process(image, region: CropRegion())
            await pipeline.waitForTranslations()
            time += 100
        }
        return sender.events
    }

    func testNotShownLineClearsPreviousTranslation() async {
        // Türkçe sanılan satır (PS5'in kendi Türkçe yazısı) gösterilmez; önceki çeviri de ekranda kalmaz.
        let events = await run(["You doing okay?", "Uzaktan Oynama'yı kullanarak bağlandı"])
        XCTAssertEqual(events, ["İyi misin?", "<temizle>"])
    }

    func testStrayLetterLineIsTranslated() async {
        let events = await run(["You doing okay?", "Yeah, I guess. Sure beats jailsır"])
        XCTAssertEqual(events, ["İyi misin?", "Çeviri"])
    }
}
#endif

/// Nino: altyazının yeri öğrenilince yalnız o şerit okunur.
final class SubtitleReadBandTests: XCTestCase {
    func testLearnedBandNarrowsTheReadArea() {
        var layout = SubtitleLayout()
        XCTAssertNil(layout.readTop(for: "gta-v"), "öğrenmeden önce ayarlardaki alan")
        for _ in 0..<10 { layout.record(TextBox(left: 0.3, top: 0.84, right: 0.7, bottom: 0.92), game: "gta-v") }
        let top = try? XCTUnwrap(layout.readTop(for: "gta-v"))
        XCTAssertEqual(top ?? 0, 0.79, accuracy: 0.001)
    }
}

/// Nino: GTA 6 etkileşim ipucu (simgeler harf okunur) altyazı değildir; kısa bağıran altyazı kalır.
final class InteractionPromptTests: XCTestCase {
    func testIconsReadAsLettersBeforeCapsWordIsAPrompt() {
        XCTAssertTrue(ButtonPrompts.isPrompt("A e DRINKS"))
        XCTAssertTrue(ButtonPrompts.isPrompt("A : SIT DOWN"))
        XCTAssertFalse(ButtonPrompts.isPrompt("GET DOWN!"))
        XCTAssertFalse(ButtonPrompts.isPrompt("I am SHAKING"))
        XCTAssertFalse(ButtonPrompts.isPrompt("Hey, you got Lucia's phone."))
    }
}

/// Nino: harita kartının ikinci paragrafı ve cümlenin kısa son satırı da okunur; Türkçe kartın dışına (altına) konur.
final class MapCardParagraphTests: XCTestCase {
    func testWholeCardIsRead() throws {
        let frame = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-harita-buckme.jpg"))
        let reading = try VisionReader(language: "en", cpuOnly: true).readLines(frame, deep: false)
        let card = try XCTUnwrap(MapCard.find(in: reading))
        XCTAssertEqual(card.title, "DEPOSIT CASH INTO BUCKME")
        XCTAssertEqual(card.sentences.count, 2, "\(card.sentences)")
        XCTAssertTrue(card.sentences.first?.hasSuffix("nearby ATMs") == true, "\(card.sentences)")
        XCTAssertTrue(card.sentences.last?.contains("checking account at an ATM") == true, "\(card.sentences)")
        XCTAssertGreaterThan(card.box.bottom, 0.58)
    }
}

/// Nino: haritadaki simge ("(43)") ve uzaklık ("1.53 km") kart satırına karışınca alttaki satır atılıyordu.
final class MapCardIconJunkTests: XCTestCase {
    func testIconAndDistanceDoNotBreakTheCard() throws {
        let frame = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-harita-balik.jpg"))
        let reading = try VisionReader(language: "en", cpuOnly: true).readLines(frame, deep: false)
        let card = try XCTUnwrap(MapCard.find(in: reading))
        XCTAssertEqual(card.sentences, ["Cal challenged you to catch a stoplight parrotfish larger than 0.9 kg."])
    }
}

/// Nino: mesafesiz yol tarifleri de tarif sayılır; cümle olan tarif altyazı kalır.
final class NavigationWithoutDistanceTests: XCTestCase {
    func testCommandOnlyLinesAreHints() {
        for line in ["Turn left", "Turn Right", "Keep left", "Make a U-turn", "U-Turn Left", "Turn left 400 ft", "Keep Right."] {
            XCTAssertTrue(Reading.isNavigationHint(line), line)
        }
        for line in ["Turn left at the lights, okay?", "Keep going, we're almost there.", "Turn it down!"] {
            XCTAssertFalse(Reading.isNavigationHint(line), line)
        }
    }
}
