import CoreGraphics
import ImageIO
import XCTest
@testable import CouchSubsCore

/// Elle çalıştırılır: NINO_FRAME (dosya ya da klasör) karelerinin köşelerini okur ve yazdırır.
final class NinoFrameProbe: XCTestCase {
    func testProbe() throws {
        guard let path = ProcessInfo.processInfo.environment["NINO_FRAME"] else { throw XCTSkip("NINO_FRAME yok") }
        var files = [path]
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            files = try FileManager.default.contentsOfDirectory(atPath: path).filter { $0.hasSuffix(".jpg") }.sorted()
                .map { path + "/" + $0 }
        }
        let regions = [CropRegion(top: 0.0, bottom: 0.36, left: 0.0, right: 0.40),
                       CropRegion(top: 0.885, bottom: 0.995, left: 0.08, right: 0.92)]
        for file in files {
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: file) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            for region in regions {
                let area = RegionCropper.crop(image, to: region)
                let lines = try VisionReader(language: "en", edgeIcons: true).readLines(area, deep: false).lines.map(\.text)
                if !lines.isEmpty { print("PROBE", (file as NSString).lastPathComponent, region.top, lines) }
            }
        }
    }

    /// Elle: NINO_ICON_FILES klasöründeki simge kesitlerini doğrudan sınıflandırır.
    func testIconFiles() throws {
        guard let dir = ProcessInfo.processInfo.environment["NINO_ICON_FILES"] else { throw XCTSkip("NINO_ICON_FILES yok") }
        for name in try FileManager.default.contentsOfDirectory(atPath: dir).sorted() where name.hasSuffix(".png") {
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: dir + "/" + name) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            print("ICONFILE", name, ButtonIcons.classify(image) ?? "nil")
        }
    }
}

/// Elle: NINO_SHAPE_DIR içindeki "giris.wav:cikis.wav:yarimTon:hiz:guc" satırlarını (NINO_SHAPE_LIST) işler.
final class NinoShapeProbe: XCTestCase {
    func testShape() throws {
        guard let dir = ProcessInfo.processInfo.environment["NINO_SHAPE_DIR"],
              let list = ProcessInfo.processInfo.environment["NINO_SHAPE_LIST"] else { throw XCTSkip("yok") }
        for job in list.split(separator: ",") {
            let p = job.split(separator: ":").map(String.init)
            let audio = try SpeechAudio(wav: Data(contentsOf: URL(fileURLWithPath: dir + "/" + p[0]))).tightened()
            let shaped = audio.styled(rate: Double(p[3])!, gain: Double(p[4])!).withRisingEnd(semitones: Double(p[2])!)
            try shaped.wav.write(to: URL(fileURLWithPath: dir + "/" + p[1]))
            print("SHAPED", p[1])
        }
    }
}


/// Elle: NINO_VOICE_FILES içindeki .wav dosyalarında konuşanı ölçer.
final class NinoVoiceProbe: XCTestCase {
    func testVoiceFiles() throws {
        guard let dir = ProcessInfo.processInfo.environment["NINO_VOICE_FILES"] else { throw XCTSkip("yok") }
        for name in try FileManager.default.contentsOfDirectory(atPath: dir).sorted() where name.hasSuffix(".wav") {
            let audio = try SpeechAudio(wav: Data(contentsOf: URL(fileURLWithPath: dir + "/" + name)))
            let sample = VoiceTracker.analyze(audio.samples)
            print("VOICE", name, VoiceTracker.diagnose(audio.samples), sample.map { String(format: "→ %.0f Hz, %.0f dB, oynama %.1f", $0.pitch, $0.loudness, $0.spread) } ?? "→ yok")
        }
    }
}
