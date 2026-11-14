// SPDX-License-Identifier: AGPL-3.0-only

import Accelerate
import Foundation

/// Nino: oyunun kendi sesinden konuşanı tanır. Altyazı ekrandayken duyulan İngilizce sesin perdesi (erkek/kadın) ve
/// "rengi" (frekans bantlarındaki enerji dağılımı) ölçülür; benzer sesler aynı kişi sayılır. Böylece konuşanın adı
/// altyazıda yazmasa da her karakter dublajda kendi sesiyle konuşur.
public struct VoiceSample: Equatable, Sendable {
    /// Ortanca perde (Hz).
    public var pitch: Double
    /// Perdesi belirgin (konuşma sayılan) süre, saniye.
    public var voiced: Double
    /// Ses rengi: bant enerjilerinin (log) ortalaması, ortalaması çıkarılmış ve birim uzunlukta.
    public var print: [Float]
    /// Konuşmanın ortalama gücü (dB, sesli parçaların RMS'i).
    public var loudness: Double = 0
    /// Perdenin cümle içinde ne kadar oynadığı (yarım ton, standart sapma).
    public var spread: Double = 0

    /// Kadın sesi yalnız güçlü kanıtla: perde 200 Hz ve üstü ve ses normal konuşma gücünde (−28 dB ve üstü). Belirsiz
    /// her durum erkek sayılır; erkeklerin konuştuğu sahnede kadın sesi duymak, tersinden çok daha kötü.
    public var gender: DubbingVoice.Gender { pitch >= 200 && loudness >= -28 ? .female : .male }
}

public final class VoiceTracker: @unchecked Sendable {
    public static let sampleRate = 16_000.0
    private static let frame = 640          // 40 ms
    private static let fftSize = 1024
    private static let bands = 18

    private let lock = NSLock()
    private var samples: [Float] = []
    /// `samples[0]`'ın zamanı (sistem açılışından beri saniye).
    private var start: TimeInterval = 0
    private let capacity: Int

    public init(seconds: Double = 12) {
        capacity = Int(seconds * Self.sampleRate)
    }

    public static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// PS5'ten gelen sesi ekler (16 kHz tek kanal). `time`: bu parçanın sonunun zamanı.
    public func append(_ chunk: [Float], at time: TimeInterval = VoiceTracker.now) {
        lock.withLock {
            samples.append(contentsOf: chunk)
            if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
            start = time - Double(samples.count) / Self.sampleRate
        }
    }

    /// [from, to] aralığındaki konuşmanın perdesi ve rengi; konuşma yoksa ya da çok kısaysa nil.
    public func analyze(from: TimeInterval, to: TimeInterval) -> VoiceSample? {
        Self.analyze(window(from: from, to: to))
    }

    /// [from, to] aralığının ham sesi (16 kHz tek kanal).
    public func window(from: TimeInterval, to: TimeInterval) -> [Float] {
        lock.withLock {
            let a = max(0, Int((from - start) * Self.sampleRate)), b = min(samples.count, Int((to - start) * Self.sampleRate))
            return a < b ? Array(samples[a..<b]) : []
        }
    }

    /// Tanı için: pencerede kaç örnek var, gücü ne, kaç parçada perde bulundu.
    public static func diagnose(_ window: [Float]) -> String {
        guard !window.isEmpty else { return "pencerede hiç ses yok" }
        var rms: Float = 0
        vDSP_rmsqv(window, 1, &rms, vDSP_Length(window.count))
        var pitched = 0, total = 0, index = 0
        let band = bandPass(window, low: 70, high: 900)
        while index + frame <= window.count {
            total += 1
            if pitch(of: Array(band[index..<(index + frame)])) != nil { pitched += 1 }
            index += frame / 2
        }
        return String(format: "%.2f sn ses, güç %.1f dB, perdeli parça %d/%d", Double(window.count) / sampleRate,
                      20 * log10(Double(max(rms, 1e-9))), pitched, total)
    }

    static func analyze(_ window: [Float]) -> VoiceSample? {
        var pitches: [Double] = []
        var prints: [[Float]] = []
        var levels: [Double] = []
        // Perde, konuşmanın temel perdesinin bulunduğu banda süzülmüş seste aranır: oyun sesinde rüzgâr, ortam ve müzik
        // çoğunlukla 1 kHz'in üstündedir ve süzülmeden konuşmanın yinelenen dalgasını örtüyordu (52 parçada 3 → 21).
        let voiceBand = bandPass(window, low: 70, high: 900)
        var index = 0
        while index + frame <= window.count {
            let piece = Array(window[index..<(index + frame)])
            let band = Array(voiceBand[index..<(index + frame)])
            index += frame / 2
            guard let pitch = pitch(of: band) else { continue }
            pitches.append(pitch)
            prints.append(bandEnergies(piece))
            var rms: Float = 0
            vDSP_rmsqv(piece, 1, &rms, vDSP_Length(piece.count))
            levels.append(20 * log10(Double(max(rms, 1e-7))))
        }
        // En az ~0,2 sn konuşma gerekir.
        guard pitches.count >= 10 else { return nil }
        let sorted = pitches.sorted()
        var mean = [Float](repeating: 0, count: bands)
        for p in prints { for i in 0..<bands { mean[i] += p[i] } }
        for i in 0..<bands { mean[i] /= Float(prints.count) }
        let average = mean.reduce(0, +) / Float(bands)
        var centered = mean.map { $0 - average }
        let length = sqrt(centered.reduce(0) { $0 + $1 * $1 })
        if length > 0 { centered = centered.map { $0 / length } }
        let semitones = pitches.map { 12 * log2($0) }
        let meanST = semitones.reduce(0, +) / Double(semitones.count)
        let spread = sqrt(semitones.reduce(0) { $0 + ($1 - meanST) * ($1 - meanST) } / Double(semitones.count))
        return VoiceSample(pitch: sorted[sorted.count / 2], voiced: Double(pitches.count) * Double(frame / 2) / sampleRate,
                           print: centered, loudness: levels.reduce(0, +) / Double(levels.count), spread: spread)
    }

    /// Frekans uzayında [low, high] Hz dışını sıfırlayan süzgeç (pencere boyunda, kenarları yumuşatılmış).
    static func bandPass(_ x: [Float], low: Double, high: Double) -> [Float] {
        guard x.count > 64 else { return x }
        var n = 1
        while n < x.count { n <<= 1 }
        let log2n = vDSP_Length(log2(Float(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return x }
        defer { vDSP_destroy_fftsetup(setup) }
        var input = x + [Float](repeating: 0, count: n - x.count)
        var real = [Float](repeating: 0, count: n / 2), imag = [Float](repeating: 0, count: n / 2)
        var output = [Float](repeating: 0, count: n)
        let binHz = sampleRate / Double(n)
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
                input.withUnsafeMutableBufferPointer { p in
                    p.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2)) }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                for k in 0..<(n / 2) {
                    let f = Double(k) * binHz
                    // 20 Hz'lik yumuşak kenar.
                    let g = Float(max(0, min(1, (f - low + 20) / 40)) * max(0, min(1, (high + 20 - f) / 40)))
                    if k == 0 { r[0] *= 0; im[0] *= Float(high >= sampleRate / 2 ? 1 : 0); continue }
                    r[k] *= g; im[k] *= g
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
                output.withUnsafeMutableBufferPointer { o in
                    o.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(n / 2)) }
                }
            }
        }
        var scale = Float(1) / Float(2 * n)
        vDSP_vsmul(output, 1, &scale, &output, 1, vDSP_Length(n))
        return Array(output[0..<x.count])
    }

    /// Öz ilinti ile perde (70–320 Hz); belirgin değilse (müzik, gürültü, sessizlik) nil.
    static func pitch(of x: [Float]) -> Double? {
        var energy: Float = 0
        vDSP_svesq(x, 1, &energy, vDSP_Length(x.count))
        // Çok sessiz parça atlanır (konuşma sesi kısık olsa da birkaç yüzde birlik genliği vardır).
        guard energy / Float(x.count) > 1e-6 else { return nil }
        let minLag = Int(sampleRate / 320), maxLag = Int(sampleRate / 70)
        var best: Float = 0, bestLag = 0
        for lag in minLag...maxLag {
            var dot: Float = 0
            x.withUnsafeBufferPointer { p in
                vDSP_dotpr(p.baseAddress!, 1, p.baseAddress! + lag, 1, &dot, vDSP_Length(x.count - lag))
            }
            let normalized = dot / energy
            if normalized > best { best = normalized; bestLag = lag }
        }
        // Konuşmanın sesli kısmı güçlü yinelenir; müzik ve efektler çoğunlukla bu eşiğin altında kalır.
        guard best > 0.5, bestLag > 0 else { return nil }
        return sampleRate / Double(bestLag)
    }

    /// 100–5000 Hz arasında logaritmik aralıklı bant enerjileri (log).
    static func bandEnergies(_ x: [Float]) -> [Float] {
        let n = fftSize
        var input = [Float](repeating: 0, count: n)
        for i in 0..<min(x.count, n) {
            // Hann penceresi.
            input[i] = x[i] * (0.5 - 0.5 * cos(2 * .pi * Float(i) / Float(x.count - 1)))
        }
        var real = [Float](repeating: 0, count: n / 2), imag = [Float](repeating: 0, count: n / 2)
        var magnitudes = [Float](repeating: 0, count: n / 2)
        let log2n = vDSP_Length(log2(Float(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [Float](repeating: 0, count: bands) }
        defer { vDSP_destroy_fftsetup(setup) }
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
                input.withUnsafeBufferPointer { p in
                    p.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
            }
        }
        let binHz = sampleRate / Double(n)
        var result = [Float](repeating: 0, count: bands)
        for b in 0..<bands {
            let lo = 100 * pow(50, Double(b) / Double(bands)), hi = 100 * pow(50, Double(b + 1) / Double(bands))
            let i0 = max(1, Int(lo / binHz)), i1 = min(n / 2 - 1, max(i0 + 1, Int(hi / binHz)))
            var sum: Float = 0
            for i in i0..<i1 { sum += magnitudes[i] }
            result[b] = log(sum + 1e-9)
        }
        return result
    }
}

/// Bu oturumda duyulan konuşmacılar. Yeni ses, perdesi ve rengi bilinen birine yeterince yakınsa o kişidir; değilse
/// yeni bir kişi açılır.
public struct SpeakerBook: Sendable {
    public struct Speaker: Sendable {
        public let id: Int
        public var pitch: Double
        public var print: [Float]
        public var count: Int
        /// Kişinin cinsiyeti tek cümleden değil, duyulduğu cümlelerin çoğunluğundan (bkz. `identify`).
        public var femaleVotes = 0
        public var gender: DubbingVoice.Gender { femaleVotes * 2 > count && pitch >= 200 ? .female : .male }
    }

    public private(set) var speakers: [Speaker] = []
    public static let maximum = 8

    public init() {}

    /// Sesi bir konuşmacıya bağlar; o konuşmacıyı döner.
    public mutating func identify(_ sample: VoiceSample) -> Speaker {
        var best: (index: Int, distance: Double)?
        for (i, speaker) in speakers.enumerated() {
            let d = Self.distance(sample, speaker)
            if best == nil || d < best!.distance { best = (i, d) }
        }
        if let best, best.distance < 1.0 || speakers.count >= Self.maximum {
            var s = speakers[best.index]
            // Kişinin perdesi ve rengi yavaşça güncellenir.
            let w = 1 / Double(min(s.count + 1, 10))
            s.pitch = s.pitch * (1 - w) + sample.pitch * w
            s.print = zip(s.print, sample.print).map { $0 * Float(1 - w) + $1 * Float(w) }
            s.count += 1
            if sample.gender == .female { s.femaleVotes += 1 }
            speakers[best.index] = s
            return s
        }
        var speaker = Speaker(id: speakers.count + 1, pitch: sample.pitch, print: sample.print, count: 1)
        if sample.gender == .female { speaker.femaleVotes = 1 }
        speakers.append(speaker)
        return speaker
    }

    /// Perde farkı (yüzde 12 = 1 birim) ve renk farkı (kosinüs uzaklığı 0,15 = 1 birim) birlikte.
    static func distance(_ sample: VoiceSample, _ speaker: Speaker) -> Double {
        let pitch = abs(log(sample.pitch / speaker.pitch)) / log(1.12)
        let cosine = zip(sample.print, speaker.print).reduce(0.0) { $0 + Double($1.0 * $1.1) }
        let colour = (1 - cosine) / 0.15
        return sqrt(pitch * pitch + colour * colour) / sqrt(2)
    }
}

/// Nino: İngilizce sesin duygusu → Türkçe okuyuş. Konuşmacının kendi alışkın sesine göre ne kadar yüksek, tiz ve
/// hareketli konuştuğu ölçülür (bağıran, fısıldayan). Türkçe ses modeli duygu etiketiyle ([kızgın], [sakin]...) okur;
/// ses ayrıca biraz hızlı/yavaş ve güçlü/yumuşak çalınır.
public struct SpeechDelivery: Equatable, Sendable {
    public var emotion: SpeechEmotion?
    /// Çalma hızı (1 = olduğu gibi). Hızlanınca perde de biraz yükselir: heyecanlı konuşmada doğal.
    public var rate: Double
    /// Ses gücü değişimi (dB).
    public var gain: Double
    /// Ölçülen yoğunluk: konuşmacının alışkın sesine göre (0 = olağan, + yüksek/tiz, - alçak).
    public var intensity: Double

    public init(emotion: SpeechEmotion?, rate: Double, gain: Double, intensity: Double) {
        self.emotion = emotion
        self.rate = rate
        self.gain = gain
        self.intensity = intensity
    }

    public static let neutral = SpeechDelivery(emotion: nil, rate: 1, gain: 0, intensity: 0)
}

public struct EmotionMeter: Sendable {
    /// Bu sesin konuşma sayılmayacak kadar kısık olup olmadığı: oturumdaki olağan konuşmadan 9 dB'den fazla kısık ses
    /// (at, rüzgâr ıslığı, uzaktaki müzik) çoğunlukla konuşma değildir; kişi ve cinsiyet ondan çıkarılmaz.
    public func isTooQuiet(_ sample: VoiceSample) -> Bool {
        // Henüz karşılaştıracak konuşma yoksa sabit sınır: gerçek konuşma ölçümlerde −20…−25 dB, yanlış "kadın" sanılan
        // ortam sesleri −33…−43 dB idi.
        guard let overall, overall.count >= 3 else { return sample.loudness < -30 }
        return sample.loudness < max(overall.loudness - 9, -34)
    }

    private var baselines: [Int: (loudness: Double, pitch: Double, count: Int)] = [:]
    /// Tüm konuşmacıların ortalaması (yeni konuşmacının ilk cümlelerinde karşılaştırma için).
    private var overall: (loudness: Double, pitch: Double, count: Int)?

    public init() {}

    /// Cümlenin okuyuşu. `textEmotion`: metinden tahmin edilen duygu (varsa önceliklidir; sesle güçlendirilir).
    public mutating func delivery(for sample: VoiceSample, speaker: Int, english: String, textEmotion: SpeechEmotion?) -> SpeechDelivery {
        let base = baselines[speaker].flatMap { $0.count >= 3 ? $0 : nil } ?? overall
        defer { learn(sample, speaker: speaker) }
        guard let base, base.count >= 3 else { return SpeechDelivery(emotion: textEmotion, rate: 1, gain: 0, intensity: 0) }
        let loud = (sample.loudness - base.loudness) / 6            // 6 dB = 1 birim
        let high = 12 * log2(sample.pitch / base.pitch) / 3          // 3 yarım ton = 1 birim
        let lively = (sample.spread - 2.5) / 2                       // hareketli perde
        let intensity = 0.55 * loud + 0.35 * high + 0.1 * lively
        let question = english.contains("?")
        var emotion = textEmotion
        var rate = 1.0, gain = 0.0
        if intensity > 0.9 {
            // Bağırıyor: kızgın (soruysa şaşkın); metin mutlu/şaşkın diyorsa o kalır.
            if emotion == nil || emotion == .calm { emotion = question ? .surprised : .angry }
            rate = 1.06 + min(0.06, (intensity - 0.9) * 0.05)
            gain = min(5, 2 + (intensity - 0.9) * 2)
        } else if intensity < -0.9 {
            // Alçak, fısıltıya yakın: sakin (metin üzgün diyorsa üzgün).
            if emotion == nil || emotion == .angry { emotion = .calm }
            rate = 0.95
            gain = -4
        }
        return SpeechDelivery(emotion: emotion, rate: rate, gain: gain, intensity: intensity)
    }

    private mutating func learn(_ sample: VoiceSample, speaker: Int) {
        func blend(_ old: (loudness: Double, pitch: Double, count: Int)?) -> (loudness: Double, pitch: Double, count: Int) {
            guard let old else { return (sample.loudness, sample.pitch, 1) }
            let w = 1 / Double(min(old.count + 1, 12))
            return (old.loudness * (1 - w) + sample.loudness * w, old.pitch * (1 - w) + sample.pitch * w, old.count + 1)
        }
        baselines[speaker] = blend(baselines[speaker])
        overall = blend(overall)
    }
}
