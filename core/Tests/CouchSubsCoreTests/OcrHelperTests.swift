// SPDX-License-Identifier: AGPL-3.0-only
#if os(macOS)
import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// Nino 4.0.5: yedek okuyucu (ayrı süreçte yazı tanıma) gerçek bir oyun karesini okur ve satırları geri getirir.
final class OcrHelperTests: XCTestCase {
    private var helper: URL? {
        // NINO_OCR_HELPER: uygulamanın kendisiyle denemek için (`…/Nino.app/Contents/MacOS/Nino`, `--ocr-helper` ile açılır).
        if let path = ProcessInfo.processInfo.environment["NINO_OCR_HELPER"] { return URL(fileURLWithPath: path) }
        // `swift build` çıktısı: test paketinin yanındaki ocr-helper.
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let url = products.appendingPathComponent("ocr-helper")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    func testFramingRoundTrip() {
        let reading = Reading(lines: [TextLine("Hello there", box: TextBox(left: 0.1, top: 0.8, right: 0.9, bottom: 0.9), confidence: 0.9)])
        XCTAssertEqual(OcrHelper.decode(OcrHelper.encode(reading)), reading)
    }

    func testHelperReadsARealFrame() throws {
        let url = try XCTUnwrap(helper, "önce `swift build --product ocr-helper`")
        let frame = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-altyazi-beyaz.jpg"))
        let subtitle = try XCTUnwrap(frame.cropping(to: CGRect(x: 0, y: Int(Double(frame.height) * 0.75), width: frame.width,
                                                              height: Int(Double(frame.height) * 0.25))))
        let reader = OcrHelperReader(executable: url)
        XCTAssertThrowsError(try reader.read(subtitle, language: "en", deep: false, edgeIcons: false), "ısınmadan okumaz")
        let deadline = Date().addingTimeInterval(120)
        while !reader.isReady, Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(reader.isReady, "yedek okuyucu ısınmalı")
        let begun = Date()
        let reading = try reader.read(subtitle, language: "en", deep: false, edgeIcons: false)
        XCTAssertFalse(reading.lines.isEmpty, "yedek okuyucu satır bulmalı")
        XCTAssertLessThan(Date().timeIntervalSince(begun), 3, "ısınmış yedek hemen okumalı")
        reader.shutdown()
    }

    func testDeadHelperIsReportedNotHung() {
        let reader = OcrHelperReader(executable: URL(fileURLWithPath: "/usr/bin/true"))
        let image = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        for _ in 0..<OcrHelperReader.maxFailures {
            reader.prepare(image, language: "en")
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(reader.isExhausted)
        XCTAssertThrowsError(try reader.read(image, language: "en", deep: false, edgeIcons: false))
    }
}
#endif
