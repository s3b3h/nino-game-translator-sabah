// SPDX-License-Identifier: AGPL-3.0-only

import AVFoundation
import CouchSubsCore
import Foundation

/// Çevrilen cümleleri sırayla seslendirir. Bir cümle çalarken sonraki hazırlanır; oyun konuşması hızlıysa geride kalan
/// eski cümleler atlanır ki ses altyazının çok gerisinde kalmasın.
@MainActor
final class Dubber {
    private let engine = PocketTTSEngine()
    private let server: SubtitleServer
    private var serverPort: UInt16
    private var queue: [(line: SpokenLine, batch: Int, arrival: TimeInterval)] = []
    /// Nino: PS5'in sesi; varsa konuşan sesinden tanınır (adı yazmasa da her karakter kendi sesiyle konuşur).
    var tracker: VoiceTracker?
    private var speakers = SpeakerBook()
    var onLog: ((String) -> Void)?
    /// Konuşanı tanımak için altyazı geldikten sonra dinlenen süre.
    static let listenSeconds = 0.8
    private var worker: Task<Void, Never>?
    /// Her yeni okuma işi bir numara alır; durdurulan eski iş, yerine başlayanın kaydını silmesin.
    private var generation = 0
    private var player: AVAudioPlayer?
    private var voicesPublished = false

    var cast: VoiceCast
    var output: DubbingOutput
    /// Yeni bir karaktere ses verildi; ayarlara kaydedilir.
    var onCastChanged: ((VoiceCast) -> Void)?
    var onError: ((String) -> Void)?

    /// Bekleyen en çok cümle: fazlası eskiden başlayarak atlanır.
    static let backlog = 3

    init(server: SubtitleServer, serverPort: UInt16, settings: DubbingSettings) {
        self.server = server
        self.serverPort = serverPort
        cast = settings.cast
        output = settings.output
    }

    func update(serverPort: UInt16) {
        self.serverPort = serverPort
    }

    /// Model yüklenir, ilk cümle beklemesin.
    func prepare() {
        publishVoices()
        Task { [engine, weak self] in
            do { try await engine.start() } catch { self?.onError?(error.localizedDescription) }
        }
    }

    func speak(_ lines: [SpokenLine]) {
        guard !lines.isEmpty else { return }
        publishVoices()
        // Nino: yeni altyazı gelince çalan cümle kesilmez (yarım cümle kulağa çok kötü geliyordu); bitince doğrudan yeni
        // altyazıya geçilir. Henüz başlamamış eski cümleler atlanır ki ses altyazının gerisinde kalmasın.
        batch += 1
        let arrival = VoiceTracker.now
        queue = lines.map { ($0, batch, arrival) }
        if queue.count > Self.backlog { queue.removeFirst(queue.count - Self.backlog) }
        if worker == nil { startWorker() }
    }

    /// Her `speak` çağrısı yeni bir altyazıdır; hazırlanmış ama daha yeni altyazı gelmiş cümle çalınmaz.
    private var batch = 0

    private func startWorker() {
        generation += 1
        let current = generation
        worker = Task { await run(current) }
    }

    /// Ayarlardaki "Dinle" düğmesi.
    func preview(_ voice: DubbingVoice) {
        stop()
        previewVoice = voice
        // Dublaj yalnız Türkçe: arayüz dili ne olursa olsun deneme cümlesi Türkçedir.
        // Deneme hemen duyulsun: çalan dublaj durdurulmuştur, kuyruk boştur.
        speak([SpokenLine(english: "Listen.", turkish: "Merhaba, oyundaki karakterleri Türkçe seslendireceğim.")])
    }

    private var previewVoice: DubbingVoice?

    func stop() {
        queue.removeAll()
        worker?.cancel()
        worker = nil
        generation += 1
        player?.stop()
        player = nil
        server.stopSpeech()
    }

    func shutdown() async {
        stop()
        await engine.stop()
    }

    private func run(_ number: Int) async {
        var next = makeNext()
        while let current = next {
            guard let (audio, preview) = await current.task.value, !Task.isCancelled, number == generation else { break }
            // Bu cümle çalarken sonraki hazırlanır.
            next = makeNext()
            // Ayarlardaki deneme her zaman Mac'ten çalar: kullanıcı o an Mac'in başında. Sırada bekleyen varsa biraz
            // hızlı okunur ki ses altyazıya yetişsin.
            await play(audio, on: preview ? .computer : output, hurry: !queue.isEmpty)
            if Task.isCancelled || number != generation { next?.task.cancel(); break }
            // Çalarken daha yeni bir altyazı geldiyse hazırlanan eski cümle atlanır.
            if let prepared = next, prepared.batch < batch, queue.contains(where: { $0.batch == batch }) {
                prepared.task.cancel()
                next = makeNext()
            }
        }
        guard number == generation else { return }
        worker = nil
        if !queue.isEmpty, !Task.isCancelled { startWorker() }
    }

    private func makeNext() -> (task: Task<(SpeechAudio, Bool)?, Never>, batch: Int)? {
        // Daha yeni altyazının cümlesi varsa eskileri atlanır.
        if let newest = queue.map(\.batch).max() { queue.removeAll { $0.batch < newest } }
        guard !queue.isEmpty else { return nil }
        let (line, lineBatch, arrival) = queue.removeFirst()
        let chosen = previewVoice
        let preview = chosen != nil
        previewVoice = nil
        let port = serverPort
        let task = Task { [engine, weak self] () -> (SpeechAudio, Bool)? in
            guard let self else { return nil }
            var voice: DubbingVoice
            var delivery = SpeechDelivery(emotion: SpeechEmotion.guess(english: line.english), rate: 1, gain: 0, intensity: 0)
            if let chosen { voice = chosen } else { (voice, delivery) = await self.listen(for: line, arrival: arrival, delivery: delivery) }
            let text = SpeechText.prepare(line.turkish, emotion: delivery.emotion)
            let url = URL(string: "http://127.0.0.1:\(port)/voices/\(voice.rawValue).wav")!
            do {
                let audio = try await engine.synthesize(text, voice: url).tightened()
                let rise = Self.endRise(for: line, delivery: delivery)
                return (audio.styled(rate: delivery.rate, gain: delivery.gain).withRisingEnd(semitones: rise), preview)
            } catch {
                if !Task.isCancelled { self.onError?(error.localizedDescription) }
                return nil
            }
        }
        return (task, lineBatch)
    }

    /// Satırın sesi. Konuşanın adı yazıyorsa ad (kalıcı); yoksa oyunun sesi dinlenir: perdesi ve rengiyle tanınan kişiye
    /// kendi cinsiyetinden sabit bir ses verilir. Ses alınamazsa (konuşma kapalı, müzik) eski düzen: anlatıcı ve ikinci kişi.
    /// Oyunun İngilizce sesi dinlenir: kim konuşuyor (ses) ve nasıl konuşuyor (duygu, hız, güç).
    private func listen(for line: SpokenLine, arrival: TimeInterval, delivery: SpeechDelivery) async -> (DubbingVoice, SpeechDelivery) {
        if let tracker {
            let wait = arrival + Self.listenSeconds - VoiceTracker.now
            if wait > 0 { try? await Task.sleep(for: .milliseconds(Int(wait * 1000))) }
            if let sample = tracker.analyze(from: arrival - 0.3, to: VoiceTracker.now), emotions.isTooQuiet(sample) {
                onLog?(String(format: "konuşan: ses çok kısık (%.0f dB, %.0f Hz), konuşma sayılmadı", sample.loudness, sample.pitch))
                return (named(line), delivery)
            } else if let sample = tracker.analyze(from: arrival - 0.3, to: VoiceTracker.now) {
                let speaker = speakers.identify(sample)
                let felt = emotions.delivery(for: sample, speaker: speaker.id, english: line.english, textEmotion: delivery.emotion)
                // Konuşanın adı yazıyorsa ses addan, duygu sesten gelir.
                let voice = line.speaker == nil ? cast.voice(forSpeaker: speaker.id, gender: speaker.gender) : named(line)
                onLog?("konuşan: #\(speaker.id) \(speaker.gender == .male ? "erkek" : "kadın") \(Int(sample.pitch)) Hz "
                    + String(format: "%.0f dB, perde oynaması %.1f, yoğunluk %+.1f → %@ %@, hız %.2f, güç %+.0f dB",
                             sample.loudness, sample.spread, felt.intensity, voice.rawValue,
                             felt.emotion?.rawValue ?? "düz", felt.rate, felt.gain))
                return (voice, felt)
            }
            let window = tracker.window(from: arrival - 0.3, to: VoiceTracker.now)
            onLog?("konuşan: sesten anlaşılamadı (\(VoiceTracker.diagnose(window)))")
            #if DEBUG
            // Geliştirme: anlaşılamayan ses incelemek için kaydedilir (son 20 dosya).
            Self.saveForInspection(window)
            #endif
        }
        return (named(line), delivery)
    }

    private var emotions = EmotionMeter()

    #if DEBUG
    private static var savedCount = 0
    private static func saveForInspection(_ window: [Float]) {
        guard !window.isEmpty else { return }
        savedCount += 1
        let folder = AppFolder.logs.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("anlasilamayan-\(savedCount % 20).wav")
        try? SpeechAudio(samples: window, sampleRate: Int(VoiceTracker.sampleRate)).wav.write(to: file)
    }
    #endif

    /// Nino: cümle sonunun ne kadar yükseleceği (yarım ton). Ses modeli soru ve heyecanlı cümleleri hep aşağı doğru
    /// bitiriyor; kullanıcının kendi okuyuşunda bu cümlelerin sonu 4–6 yarım ton yükseliyordu.
    nonisolated static func endRise(for line: SpokenLine, delivery: SpeechDelivery) -> Double {
        let text = line.turkish.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("?") { return 4.5 }
        let excited = delivery.intensity > 0.9 || delivery.emotion == .angry || delivery.emotion == .surprised
        if text.hasSuffix("!") || excited { return 6 }
        return 0
    }

    /// Ada göre (ya da anlatıcı/ikinci kişi) ses.
    private func named(_ line: SpokenLine) -> DubbingVoice {
        let before = cast
        let voice = cast.voice(for: line)
        if cast.assignments != before.assignments { onCastChanged?(cast) }
        return voice
    }

    private func play(_ audio: SpeechAudio, on output: DubbingOutput, hurry: Bool = false) async {
        let wav = audio.wav
        let milliseconds = Int(audio.duration * 1000)
        switch output {
        case .tv:
            server.sendSpeech(wav, durationMs: milliseconds)
            // TV sesi ağdan alıp çalmaya biraz geç başlar; sıradaki cümle bunu kesmesin.
            try? await Task.sleep(for: .milliseconds(milliseconds + 250))
        case .computer:
            player = try? AVAudioPlayer(data: wav)
            let rate: Float = hurry ? 1.12 : 1
            player?.enableRate = true
            player?.rate = rate
            player?.play()
            try? await Task.sleep(for: .milliseconds(Int(Double(milliseconds) / Double(rate)) + 60))
        }
    }

    /// pocket-tts sesleri altyazı sunucusundan alır (`/voices/<ad>.wav`).
    private func publishVoices() {
        guard !voicesPublished, DubbingModelStore.isReady else { return }
        for voice in DubbingVoice.allCases {
            if let data = try? Data(contentsOf: DubbingModelStore.voiceFile(voice)) {
                server.publish(data, at: "/voices/\(voice.rawValue).wav")
            }
        }
        voicesPublished = true
    }
}
