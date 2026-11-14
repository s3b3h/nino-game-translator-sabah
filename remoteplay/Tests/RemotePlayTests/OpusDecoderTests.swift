import AVFoundation
import XCTest
@testable import RemotePlay

final class OpusDecoderTests: XCTestCase {
    /// macOS'un Opus kodlayıcısıyla 48 kHz stereo bir ton sıkıştırılır, Nino'nun çözücüsüyle geri çözülür.
    func testRoundTrip() throws {
        let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        var opusDesc = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
                                                   mFramesPerPacket: 480, mBytesPerFrame: 0, mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        let opusFormat = try XCTUnwrap(AVAudioFormat(streamDescription: &opusDesc))
        let encoder = try XCTUnwrap(AVAudioConverter(from: pcmFormat, to: opusFormat))
        let decoder = try XCTUnwrap(OpusAudioDecoder(channels: 2, rate: 48_000, frameSize: 480))
        var decoded: [Float] = []
        var t = 0.0
        for _ in 0..<100 {
            let pcm = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 480)!
            pcm.frameLength = 480
            for i in 0..<480 {
                let v = Float(sin(2 * .pi * 150 * (t + Double(i) / 48_000))) * 0.3
                pcm.floatChannelData![0][i] = v; pcm.floatChannelData![1][i] = v
            }
            t += 480 / 48_000
            let out = AVAudioCompressedBuffer(format: opusFormat, packetCapacity: 1, maximumPacketSize: 1500)
            var fed = false
            var error: NSError?
            let status = encoder.convert(to: out, error: &error) { _, s in
                if fed { s.pointee = .noDataNow; return nil }
                fed = true; s.pointee = .haveData; return pcm
            }
            if out.packetCount == 0 { continue }
            XCTAssertNotEqual(status, .error, "\(String(describing: error))")
            let bytes = Data(bytes: out.data, count: Int(out.byteLength))
            decoded += decoder.decode(bytes)
        }
        print("ÇÖZÜLEN ÖRNEK", decoded.count, "RMS", sqrt(decoded.map { $0 * $0 }.reduce(0, +) / Float(max(decoded.count, 1))))
        XCTAssertGreaterThan(decoded.count, 8_000)
    }
}
