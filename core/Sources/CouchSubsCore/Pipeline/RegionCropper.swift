// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics

/// Görüntüde altyazının arandığı bölge, kenarlara oranla (0–1, üstten ve soldan).
public struct CropRegion: Codable, Equatable, Sendable {
    public var top = 0.62
    public var bottom = 0.97
    public var left = 0.14
    public var right = 0.86

    public init(top: Double = 0.62, bottom: Double = 0.97, left: Double = 0.14, right: Double = 0.86) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }
}

public enum RegionCropper {
    public static func crop(_ image: CGImage, to region: CropRegion) -> CGImage {
        let width = Double(image.width), height = Double(image.height)
        let rect = CGRect(x: width * region.left, y: height * region.top,
                          width: width * (region.right - region.left), height: height * (region.bottom - region.top))
        return image.cropping(to: rect.integral) ?? image
    }

    /// Nino: kesilmiş bölgenin içinde kalan bir kutu (karenin tamamına göre, 0–1) siyaha boyanır. Telefon açıkken
    /// altyazı bölgesindeki telefon yazıları okunmasın diye: okunup sonra atılıyorlardı ama kalabalık yazı Vision'ı 9 sn
    /// meşgul edip Nino'yu "takıldı" diye yeniden açtırıyordu (20 Kasım 2026, GTA 6).
    public static func masking(_ area: CGImage, box: TextBox, in region: CropRegion, margin: Double = 0.01) -> CGImage {
        let width = region.right - region.left, height = region.bottom - region.top
        guard width > 0, height > 0 else { return area }
        let left = (box.left - margin - region.left) / width, right = (box.right + margin - region.left) / width
        let top = (box.top - margin - region.top) / height, bottom = (box.bottom + margin - region.top) / height
        guard right > 0, left < 1, bottom > 0, top < 1 else { return area }
        let w = area.width, h = area.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return area }
        context.draw(area, in: CGRect(x: 0, y: 0, width: w, height: h))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        // CoreGraphics'in y ekseni aşağıdan yukarıdır.
        let x0 = max(0, left) * Double(w), x1 = min(1, right) * Double(w)
        let y0 = (1 - min(1, bottom)) * Double(h), y1 = (1 - max(0, top)) * Double(h)
        context.fill(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
        return context.makeImage() ?? area
    }

    /// Bölgenin küçültülmüş gri kopyası: iki kareyi yazı tanımaya gerek kalmadan karşılaştırmaya yeter.
    public static func signature(of image: CGImage) -> [UInt8] {
        let width = ReadScheduler.signatureWidth, height = ReadScheduler.signatureHeight
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }
}
