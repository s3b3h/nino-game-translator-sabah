// SPDX-License-Identifier: AGPL-3.0-only

import AVFoundation
import Foundation

/// Nino: PS5'in Remote Play sesini (Opus paketleri) macOS'un kendi Opus çözücüsüyle 16 kHz tek kanal örneğe çevirir.
/// Ses yalnız konuşanı tanımak için çözülür (çalınmaz). libchiaki Opus'suz derlendiği için çözme burada yapılır.
final class OpusAudioDecoder {
    private let converter: AVAudioConverter
    private let input: AVAudioFormat
    private let output: AVAudioFormat
    private let framesPerPacket: AVAudioFrameCount

    /// `outputRate`/`outputChannels`: konuşanı tanımak için 16 kHz tek kanal; video kaydı için 48 kHz iki kanal.
    init?(channels: Int, rate: Int, frameSize: Int, outputRate: Double = 16_000, outputChannels: AVAudioChannelCount = 1) {
        var description = AudioStreamBasicDescription(
            mSampleRate: Double(rate), mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: UInt32(frameSize), mBytesPerFrame: 0, mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 0, mReserved: 0)
        guard let input = AVAudioFormat(streamDescription: &description),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: outputRate, channels: outputChannels, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output) else { return nil }
        self.input = input
        self.output = output
        self.converter = converter
        framesPerPacket = AVAudioFrameCount(frameSize)
    }

    /// Bir Opus paketini çözer; 16 kHz tek kanal örnekler döner (paket bozuksa boş).
    func decode(_ packet: Data) -> [Float] {
        let compressed = AVAudioCompressedBuffer(format: input, packetCapacity: 1, maximumPacketSize: max(packet.count, 1))
        packet.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            compressed.data.copyMemory(from: base, byteCount: packet.count)
        }
        compressed.byteLength = UInt32(packet.count)
        compressed.packetCount = 1
        compressed.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0,
                                                                               mDataByteSize: UInt32(packet.count))
        let capacity = AVAudioFrameCount(Double(framesPerPacket) * output.sampleRate / input.sampleRate) + 64
        guard let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return [] }
        var given = false
        var error: NSError?
        converter.convert(to: pcm, error: &error) { _, status in
            if given {
                status.pointee = .noDataNow
                return nil
            }
            given = true
            status.pointee = .haveData
            return compressed
        }
        guard error == nil, let data = pcm.floatChannelData else { return [] }
        let frames = Int(pcm.frameLength), count = Int(output.channelCount)
        if count == 1 { return Array(UnsafeBufferPointer(start: data[0], count: frames)) }
        // Birden çok kanal: sırayla (L R L R …).
        var out = [Float](repeating: 0, count: frames * count)
        for frame in 0..<frames { for channel in 0..<count { out[frame * count + channel] = data[channel][frame] } }
        return out
    }
}
