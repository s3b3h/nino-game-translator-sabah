// SPDX-License-Identifier: AGPL-3.0-only
// Nino (yalnız geliştirici derlemesi): çeviri sürerken iki saniyede bir PS5 karesini, okuma bölgesini, son okunan
// yazının kutusunu ve son çeviriyi ~/Library/Logs/CouchSubs/frames/ altına kaydeder. Ekrandaki sorunları incelemek için.

#if DEBUG
import AppKit
import CouchSubsCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum NinoDebugFrames {
    nonisolated(unsafe) private static var last: TimeInterval = 0
    private static let queue = DispatchQueue(label: "nino.debug-frames")
    static var folder: URL {
        AppFolder.logs.appendingPathComponent("frames", isDirectory: true)
    }

    // Video kaydı: frames/video/KAYIT dosyası varken saniyede 10 ham kare frames/video/v-<ms>.jpg olarak yazılır
    // (ekrandaki sorunları birleşik videoda incelemek için).
    nonisolated(unsafe) private static var lastVideo: TimeInterval = 0
    nonisolated(unsafe) private static var recordingCheckedAt: TimeInterval = 0
    nonisolated(unsafe) private static var recording = false
    static var videoFolder: URL { folder.appendingPathComponent("video", isDirectory: true) }

    private static func recordVideo(_ frame: CGImage, now: TimeInterval) {
        if now - recordingCheckedAt > 0.5 {
            recordingCheckedAt = now
            recording = FileManager.default.fileExists(atPath: videoFolder.appendingPathComponent("KAYIT").path)
        }
        guard recording, now - lastVideo >= 0.1 else { return }
        lastVideo = now
        let name = "v-\(Int(now * 1000)).jpg"
        queue.async {
            guard let dest = CGImageDestinationCreateWithURL(videoFolder.appendingPathComponent(name) as CFURL,
                                                             UTType.jpeg.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dest, frame, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            CGImageDestinationFinalize(dest)
        }
    }

    /// Ses kaydı: KAYIT varken 48 kHz iki kanal float örnekler video/ses.f32 dosyasına eklenir; ilk örneğin zamanı
    /// (ms) video/ses-baslangic.txt'ye yazılır (video hazırlanırken görüntüyle eşlemek için).
    nonisolated(unsafe) private static var audioFile: FileHandle?
    private static let audioQueue = DispatchQueue(label: "nino.debug-audio")
    static func recordAudio(_ samples: [Float]) {
        let now = Date().timeIntervalSince1970
        audioQueue.async {
            if !recording {
                if audioFile != nil { try? audioFile?.close(); audioFile = nil }
                return
            }
            if audioFile == nil {
                let url = videoFolder.appendingPathComponent("ses.f32")
                FileManager.default.createFile(atPath: url.path, contents: nil)
                audioFile = try? FileHandle(forWritingTo: url)
                let start = Int((now - Double(samples.count / 2) / 48_000) * 1000)
                try? String(start).write(to: videoFolder.appendingPathComponent("ses-baslangic.txt"), atomically: true, encoding: .utf8)
            }
            samples.withUnsafeBufferPointer { audioFile?.write(Data(buffer: $0)) }
        }
    }

    static func capture(_ frame: CGImage, region: CropRegion, box: TextBox?, source: String, translation: String) {
        let now = Date().timeIntervalSince1970
        recordVideo(frame, now: now)
        guard now - last >= 2 else { return }
        last = now
        queue.async {
            let w = frame.width, h = frame.height
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(frame, in: CGRect(x: 0, y: 0, width: w, height: h))
            func rect(_ l: Double, _ t: Double, _ r: Double, _ b: Double) -> CGRect {
                CGRect(x: l * Double(w), y: (1 - b) * Double(h), width: (r - l) * Double(w), height: (b - t) * Double(h))
            }
            // Okuma bölgesi: sarı kesikli
            ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0, alpha: 1))
            ctx.setLineWidth(3)
            ctx.setLineDash(phase: 0, lengths: [12, 8])
            ctx.stroke(rect(region.left, region.top, region.right, region.bottom))
            // Köşe bölgeleri: mavi kesikli
            ctx.setStrokeColor(CGColor(red: 0.2, green: 0.6, blue: 1, alpha: 1))
            ctx.stroke(rect(0.0, 0.0, 0.40, 0.36))
            ctx.stroke(rect(0.08, 0.885, 0.92, 0.995))
            // Son okunan yazının kutusu: kırmızı
            if let box {
                ctx.setLineDash(phase: 0, lengths: [])
                ctx.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.2, alpha: 1))
                ctx.setLineWidth(4)
                ctx.stroke(rect(box.left, box.top, box.right, box.bottom))
            }
            // Üst şerit: okunan ve çevrilen
            let caption = "OKUNAN: \(source)\nÇEVİRİ: \(translation)" as NSString
            let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns
            NSColor(white: 0, alpha: 0.7).setFill()
            NSRect(x: 0, y: Double(h) - 90, width: Double(w), height: 90).fill()
            caption.draw(in: NSRect(x: 16, y: Double(h) - 86, width: Double(w) - 32, height: 82),
                         withAttributes: [.font: NSFont.boldSystemFont(ofSize: 26), .foregroundColor: NSColor.white])
            NSGraphicsContext.restoreGraphicsState()
            guard let out = ctx.makeImage() else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            // Çizimli kare ve (simge tanımayı denemek için) çizimsiz ham kare.
            for (name, image, quality) in [("latest.jpg", out, 0.7), ("f-\(stamp).jpg", out, 0.7), ("r-\(stamp).jpg", frame, 0.92)] {
                guard let dest = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL,
                                                                 UTType.jpeg.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                CGImageDestinationFinalize(dest)
            }
            // Her türden en çok 120 kare tutulur.
            for prefix in ["f-", "r-"] {
                if let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path).filter({ $0.hasPrefix(prefix) }).sorted(),
                   files.count > 120 {
                    for f in files.prefix(files.count - 120) { try? FileManager.default.removeItem(at: folder.appendingPathComponent(f)) }
                }
            }
        }
    }
}
#endif
