// SPDX-License-Identifier: AGPL-3.0-only
// Nino (kullanıcı isteği, 21 Kasım 2026): altyazının arkası buzlu cam gibi olsun; siyah kutu değil, İngilizce de
// görünmesin. TV oyunun görüntüsünü (HDMI katmanı) bulanıklaştıramıyor; bu yüzden karenin altyazı bölgesi burada
// iyice bulanıklaştırılıp küçük bir JPEG olarak TV'ye gönderilir, TV onu örtünün zemini yapar.

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CoverBlur {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// `box` (kareye oranla) çevresinin bulanık hali, base64 JPEG. Yazı bulanıklıkta tamamen kaybolur.
    public static func make(frame: CGImage, box: TextBox, pad: (x: Double, y: Double) = (0.04, 0.035)) -> String? {
        let w = Double(frame.width), h = Double(frame.height)
        let left = max(0, box.left - pad.x), right = min(1, box.right + pad.x)
        let top = max(0, box.top - pad.y), bottom = min(1, box.bottom + pad.y)
        guard right > left, bottom > top else { return nil }
        // CoreImage'in y ekseni aşağıdan yukarıdır.
        let rect = CGRect(x: left * w, y: (1 - bottom) * h, width: (right - left) * w, height: (bottom - top) * h).integral
        // Küçük gönderilir (TV büyütür; bulanık olduğu için fark edilmez).
        let scale = min(1, 360 / rect.width)
        let image = CIImage(cgImage: frame).cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY).scaledBy(x: scale, y: scale))
        let extent = image.extent
        // Yazının yüksekliğinden büyük yarıçap: harfler tamamen erir. Kenarlar uzatılarak bulanıklaştırılır (kararmasın).
        let radius = max(8, (box.bottom - box.top) * h * scale * 0.55)
        guard let blurred = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: image.clampedToExtent(),
                                                                          kCIInputRadiusKey: radius])?.outputImage?.cropped(to: extent),
              // Buzlu camın hafif karartması ve renk doygunluğu (beyaz yazı okunsun).
              let toned = CIFilter(name: "CIColorControls", parameters: [kCIInputImageKey: blurred, kCIInputBrightnessKey: -0.12,
                                                                          kCIInputSaturationKey: 1.15, kCIInputContrastKey: 0.9])?.outputImage,
              let cg = context.createCGImage(toned, from: extent) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.55] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (data as Data).base64EncodedString()
    }
}
