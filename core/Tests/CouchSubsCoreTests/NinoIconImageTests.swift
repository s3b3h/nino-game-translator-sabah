import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import CouchSubsCore

/// Sentetik ipucu satırı: "Hold (simge) to lock on an animal" — Vision simgeyi okumasa da yerine doğru düğme konmalı.
final class NinoIconImageTests: XCTestCase {
    private func render(_ draw: (CGContext, CGFloat) -> Void) -> CGImage {
        let w = 900, h = 120
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        draw(ctx, 60)
        return ctx.makeImage()!
    }

    fileprivate func text(_ ctx: CGContext, _ s: String, x: CGFloat, y: CGFloat) -> CGFloat {
        let font = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        let attr = NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: font,
                                                              kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1)])
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
        return x + CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func line(with symbol: (CGContext, CGPoint, CGFloat) -> Void) -> CGImage {
        render { ctx, _ in
            var x = text(ctx, "Hold", x: 20, y: 45)
            let c = CGPoint(x: x + 34, y: 58)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: c.x - 19, y: c.y - 19, width: 38, height: 38))
            symbol(ctx, c, 9)
            x = c.x + 40
            _ = text(ctx, "to lock on an animal", x: x, y: 45)
        }
    }

    private func read(_ image: CGImage) throws -> String {
        try VisionReader(language: "en").readLines(image, deep: false).lines.map(\.text).joined(separator: " | ")
    }

    func testSquareIcon() throws {
        let image = line { ctx, c, r in ctx.setLineWidth(3); ctx.stroke(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
        let result = try read(image); print("ICON square:", result)
        XCTAssertTrue(result.contains("□"), result)
    }

    func testTriangleIcon() throws {
        let image = line { ctx, c, r in
            ctx.setLineWidth(3)
            ctx.move(to: CGPoint(x: c.x, y: c.y + r)); ctx.addLine(to: CGPoint(x: c.x - r, y: c.y - r * 0.8))
            ctx.addLine(to: CGPoint(x: c.x + r, y: c.y - r * 0.8)); ctx.closePath(); ctx.strokePath()
        }
        let result = try read(image); print("ICON triangle:", result)
        XCTAssertTrue(result.contains("△"), result)
    }

    func testCrossIcon() throws {
        let image = line { ctx, c, r in
            ctx.setLineWidth(4)
            ctx.move(to: CGPoint(x: c.x - r, y: c.y - r)); ctx.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
            ctx.move(to: CGPoint(x: c.x + r, y: c.y - r)); ctx.addLine(to: CGPoint(x: c.x - r, y: c.y + r)); ctx.strokePath()
        }
        let result = try read(image); print("ICON cross:", result)
        XCTAssertTrue(result.contains("✕"), result)
    }

    func testCircleIcon() throws {
        let image = line { ctx, c, r in ctx.setLineWidth(3); ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
        let result = try read(image); print("ICON circle:", result)
        XCTAssertTrue(result.contains("○"), result)
    }

    func testL2Icon() throws {
        let image = line { ctx, c, _ in _ = text(ctx, "L2", x: c.x - 13, y: c.y - 9) }
        let result = try read(image); print("ICON L2:", result)
        XCTAssertTrue(result.contains("L2"), result)
    }
}
