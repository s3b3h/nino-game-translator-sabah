// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı. Yalnız Apple'ın çerçevelerini (AVFoundation) kullanır.

import AVFoundation
import CoreImage
import CoreMedia
import os

/// Bilgisayara takılı bir yakalama kartının (ya da başka bir görüntü aygıtının) özeti; seçim kuralları bununla sınanır.
struct CaptureCardInfo: Equatable {
    let id: String
    let name: String
    /// USB aygıtlarında üretici ve ürün numarası; kartın ses aygıtı bununla eşleştirilir.
    let modelID: String
}

/// Takılı aygıtlar arasından oyunun geldiği kartı seçer. HDMI yakalama kartları macOS'ta kamera gibi görünür
/// (UVC); bilgisayara takılı bir web kamerası da aynı listede çıkar. Adı bilinen bir karta benzeyen önce seçilir.
enum CaptureCardPicker {
    /// Kart adlarında sık geçen parçalar (küçük harf).
    static let hints = ["capture", "hdmi", "elgato", "avermedia", "live gamer", "game", "cam link", "razer", "ripsaw",
                        "ugreen", "usb video", "uvc", "hd60", "4k x", "4k s", "magewell", "video"]
    /// Web kamerası olduğu belli olanlar (yakalama kartı değil).
    static let cameras = ["facetime", "webcam", "iphone", "ipad", "logitech", "brio", "c920", "c922", "continuity", "desk view"]

    /// `preferred`: kullanıcının seçtiği aygıt (takılıysa o).
    static func pick(_ devices: [CaptureCardInfo], preferred: String? = nil) -> CaptureCardInfo? {
        if let preferred, let chosen = devices.first(where: { $0.id == preferred }) { return chosen }
        let usable = devices.filter { d in !cameras.contains { d.name.lowercased().contains($0) } }
        return usable.first { d in hints.contains { d.name.lowercased().contains($0) } } ?? usable.first
    }

    /// Kartın ses aygıtı: aynı USB kimliği, yoksa adı benzeyen.
    static func audio(for card: CaptureCardInfo, in devices: [CaptureCardInfo]) -> CaptureCardInfo? {
        if !card.modelID.isEmpty, let same = devices.first(where: { $0.modelID == card.modelID }) { return same }
        let name = card.name.lowercased()
        return devices.first { d in
            let other = d.name.lowercased()
            return other.contains(name) || name.contains(other)
        }
    }
}

/// Karenin neredeyse tamamen siyah olup olmadığı (PS5'te HDCP açıkken kart simsiyah görüntü verir).
enum BlackFrame {
    /// BGRA satırlarından seyrek örnek alır; en parlak örnek bile çok karanlıksa kare siyah sayılır.
    static func isBlack(_ base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int, step: Int = 32) -> Bool {
        var y = step / 2
        while y < height {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            var x = step / 2
            while x < width {
                let p = row + x * 4
                if max(p[0], p[1], p[2]) > 24 { return false }
                x += step
            }
            y += step
        }
        return true
    }
}

/// Yakalama kartından görüntüyü (ve isteğe bağlı sesi) okur. Kareler okuma hattına PS5 yolundaki boyda
/// (1920 × 1080) ve saniyede 10 kez verilir. Kart çıkarılıp yeniden takılınca kendiliğinden yeniden bağlanır.
///
/// Oyunu bilgisayarda gösteren pencere (`CaptureCardPlayer`) aynı oturumu (`session`) kullanır: görüntü ekrana
/// doğrudan ekran kartından çizilir, okuma hattından geçmez; böylece oyuna en az gecikme eklenir.
final class CaptureCardCapture: NSObject, @unchecked Sendable {
    enum Status: Equatable {
        case stopped
        /// Kamera (ya da ses için mikrofon) izni yok.
        case needsPermission
        /// Takılı kart bulunamadı.
        case noCard
        /// Kart bağlı ama görüntü simsiyah: PS5 kapalı, kablo takılı değil ya da PS5'te HDCP açık.
        case blackPicture(name: String)
        case capturing(name: String)
    }

    var onFrame: ((CGImage) -> Void)?
    var onStatus: ((Status) -> Void)?
    /// Kartın sesi, 16 kHz tek kanal (dublajda konuşanı tanımak için). Yalnız `wantsAudio` açıkken.
    var onAudio: (([Float]) -> Void)?
    /// Ses okunsun mu (başlamadan önce ayarlanır).
    var wantsAudio = false
    /// Oyunun sesi bu bilgisayardan çalınsın mı (oyun bu bilgisayarda gösteriliyorsa; başlamadan önce ayarlanır).
    var playsAudio = false
    /// Kullanıcının seçtiği aygıt (yoksa kendiliğinden seçilir).
    var preferredID: String?
    /// Oturum takılıp yeniden kurulduktan sonra (ana iş parçacığında); oyun penceresi görüntüsünü yeniden bağlar.
    var onRestart: (() -> Void)?

    static let outputSize = CGSize(width: 1920, height: 1080)
    static let framesPerSecond = 10.0
    /// Bu kadar saniye simsiyah gelirse kullanıcıya HDCP uyarısı gösterilir.
    static let blackSeconds = 4.0
    /// Kart bu kadar saniye hiç kare vermezse oturum takılmış sayılır ve yeniden kurulur (ses gelir ama görüntü donar).
    static let stallSeconds = 3.0
    /// Takılan oturum en fazla bu aralıkla yeniden denenir (kartta sinyal yokken sesi sürekli kesmemek için).
    static let maxRetrySeconds = 30.0

    /// Görüntü penceresi bu oturuma bağlanır.
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "nino.capture-card")
    private let audioQueue = DispatchQueue(label: "nino.capture-card.audio")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let audioPreview = AVCaptureAudioPreviewOutput()
    private var current: CaptureCardInfo?
    private var running = false
    private var status = Status.stopped
    private var lastEmit: CFTimeInterval = 0
    private var blackSince: CFTimeInterval?
    private var observers: [NSObjectProtocol] = []
    /// Son görüntü karesinin geldiği an (her karede; okuma hattına giden 10 kareden bağımsız).
    private var lastFrameAt: CFTimeInterval = 0
    private var lastRestartAt: CFTimeInterval = 0
    private var retryGap = CaptureCardCapture.stallSeconds
    private var watchdog: DispatchSourceTimer?
    private static let log = Logger(subsystem: "com.ninotranslator.mac", category: "capture-card")

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            let center = NotificationCenter.default
            for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                    self?.queue.async { self?.connect() }
                })
            }
            // Oturum hata verip durursa ya da kesinti biterse baştan kurulur.
            for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.interruptionEndedNotification] {
                observers.append(center.addObserver(forName: name, object: session, queue: nil) { [weak self] note in
                    Self.log.notice("session \(note.name.rawValue, privacy: .public)")
                    self?.queue.async { self?.restart(reason: "session") }
                })
            }
            startWatchdog()
            authorizeThenConnect()
        }
    }

    func stop() {
        queue.async { [self] in
            running = false
            watchdog?.cancel()
            watchdog = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            endSession()
            set(.stopped)
        }
    }

    /// Kartı yeniden arar (ör. Mac uykudan uyandı).
    func refresh() {
        queue.async { [self] in restart(reason: "refresh") }
    }

    /// Oturumu baştan kurar; `connect()`'in "zaten çalışıyor" kısa yolu atlanır (takılı oturum da çalışıyor görünür).
    private func restart(reason: String) {
        guard running else { return }
        Self.log.notice("restart: \(reason, privacy: .public)")
        lastRestartAt = CACurrentMediaTime()
        endSession()
        connect()
        let done = onRestart
        DispatchQueue.main.async { done?() }
    }

    /// Kartın kare verip vermediğini saniyede bir yoklar. Ses akarken görüntü durabiliyor (kart sinyali yeniden
    /// kurunca, oyun duraklatılıp uzun süre beklenince); bu durumda oturum yeniden kurulur.
    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.checkStall() }
        timer.resume()
        watchdog = timer
    }

    private func checkStall() {
        guard running, current != nil else { return }
        let now = CACurrentMediaTime()
        if now - lastFrameAt < Self.stallSeconds {
            retryGap = Self.stallSeconds
            return
        }
        guard now - lastRestartAt >= retryGap else { return }
        retryGap = min(retryGap * 2, Self.maxRetrySeconds)
        restart(reason: "no frames for \(Int(now - lastFrameAt)) s")
    }

    /// Takılı görüntü aygıtları (ayarlardaki seçici için).
    static func videoDevices() -> [CaptureCardInfo] { devices(for: .video).map(info) }

    // MARK: - İzin ve bağlantı

    private func authorizeThenConnect() {
        let needAudio = wantsAudio || playsAudio
        Self.authorize(.video) { [weak self] video in
            guard let self else { return }
            guard video else { return self.queue.async { self.set(.needsPermission) } }
            guard needAudio else { return self.queue.async { self.connect() } }
            // Ses izni verilmezse görüntü yine okunur; yalnız ses çalınmaz.
            Self.authorize(.audio) { _ in self.queue.async { self.connect() } }
        }
    }

    private static func authorize(_ type: AVMediaType, then done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: done(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: type, completionHandler: done)
        default: done(false)
        }
    }

    private func connect() {
        guard running, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        let videos = Self.devices(for: .video)
        guard let picked = CaptureCardPicker.pick(videos.map(Self.info), preferred: preferredID),
              let device = videos.first(where: { $0.uniqueID == picked.id }) else {
            endSession()
            set(.noCard)
            return
        }
        // Aynı kart zaten okunuyorsa (başka bir aygıt takıldı) bir şey yapılmaz.
        if current == picked, session.isRunning { return }
        endSession()
        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            set(.noCard)
            return
        }
        session.addInput(input)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        // macOS kareyi istenen boya kendisi ölçekler; okuma hattı PS5 yolundaki 1920 × 1080'i alır.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(Self.outputSize.width),
            kCVPixelBufferHeightKey as String: Int(Self.outputSize.height),
        ]
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        addAudio(for: picked)
        session.commitConfiguration()
        current = picked
        lastEmit = 0
        blackSince = nil
        let format = device.activeFormat.formatDescription
        let size = CMVideoFormatDescriptionGetDimensions(format)
        let fps = device.activeFormat.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        Self.log.notice("card \(picked.name, privacy: .public): \(size.width)x\(size.height) @\(fps) fourcc \(CMFormatDescriptionGetMediaSubType(format)) preset \(self.session.sessionPreset.rawValue, privacy: .public)")
        session.startRunning()
        lastFrameAt = CACurrentMediaTime()
        set(.capturing(name: picked.name))
    }

    private func addAudio(for card: CaptureCardInfo) {
        guard wantsAudio || playsAudio, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        let audios = Self.devices(for: .audio)
        guard let match = CaptureCardPicker.audio(for: card, in: audios.map(Self.info)),
              let device = audios.first(where: { $0.uniqueID == match.id }),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        if wantsAudio {
            // Ses tanıyıcı 16 kHz tek kanal bekler; macOS dönüştürmeyi kendisi yapar.
            audioOutput.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
            ]
            audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
            if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
        }
        if playsAudio {
            audioPreview.volume = 1
            if session.canAddOutput(audioPreview) { session.addOutput(audioPreview) }
        }
    }

    private func endSession() {
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
        current = nil
    }

    private func set(_ new: Status) {
        guard status != new else { return }
        status = new
        let report = onStatus
        DispatchQueue.main.async { report?(new) }
    }

    // MARK: - Aygıtlar

    private static func devices(for type: AVMediaType) -> [AVCaptureDevice] {
        let kinds: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            kinds = type == .video ? [.external] : [.microphone, .external]
        } else {
            kinds = type == .video ? [.externalUnknown] : [.builtInMicrophone, .externalUnknown]
        }
        return AVCaptureDevice.DiscoverySession(deviceTypes: kinds, mediaType: type, position: .unspecified).devices
    }

    private static func info(_ device: AVCaptureDevice) -> CaptureCardInfo {
        CaptureCardInfo(id: device.uniqueID, name: device.localizedName, modelID: device.modelID)
    }
}

extension CaptureCardCapture: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === audioOutput {
            audio(sampleBuffer)
            return
        }
        // Kart saniyede 60 kare verir; okuma hattına saniyede 10 kare yeter (okuma zaten önceki kare bitmeden yenisini almaz).
        let now = CACurrentMediaTime()
        lastFrameAt = now
        guard now - lastEmit >= 1 / Self.framesPerSecond, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastEmit = now
        checkBlack(pixels, now: now)
        // Kopya alınır: kartın kare havuzu okuma hattında bekleyen karelerle tükenmesin.
        guard let image = ciContext.createCGImage(CIImage(cvPixelBuffer: pixels),
                                                  from: CGRect(origin: .zero, size: Self.outputSize)) else { return }
        onFrame?(image)
    }

    private func checkBlack(_ pixels: CVPixelBuffer, now: CFTimeInterval) {
        guard let card = current else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return }
        let black = BlackFrame.isBlack(base, width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels),
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(pixels))
        if black {
            let since = blackSince ?? now
            blackSince = since
            if now - since >= Self.blackSeconds { set(.blackPicture(name: card.name)) }
        } else {
            blackSince = nil
            set(.capturing(name: card.name))
        }
    }

    private func audio(_ sampleBuffer: CMSampleBuffer) {
        guard let onAudio, let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                          dataPointerOut: &pointer) == noErr, let pointer else { return }
        let count = length / MemoryLayout<Float>.size
        let samples = pointer.withMemoryRebound(to: Float.self, capacity: count) { Array(UnsafeBufferPointer(start: $0, count: count)) }
        if !samples.isEmpty { onAudio(samples) }
    }
}
