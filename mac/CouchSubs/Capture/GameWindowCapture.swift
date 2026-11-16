// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı. Yalnız Apple'ın çerçevelerini kullanır; uygulamanın geri kalanına
// bağlı değildir, yeni Nino'ya olduğu gibi taşınabilir.

import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit

/// Ekrandaki bir pencerenin özeti (ScreenCaptureKit'ten bağımsız; seçim kuralları bununla sınanır).
struct GameWindowInfo: Equatable {
    let id: CGWindowID
    let appName: String
    let bundleID: String
    let title: String
    /// Ekran koordinatlarında, nokta cinsinden (sol üst köşe başlangıç).
    let frame: CGRect
    /// Pencere bir ekranı tamamen kaplıyor (tam ekran).
    let fillsScreen: Bool
}

/// Oyunun oynandığı pencereyi seçer: PS Remote Play (Sony) ya da chiaki-ng.
enum GameWindowPicker {
    /// Ad ya da paket kimliğinde aranan parçalar (küçük harf). `NinoGameWindowApp` ayarı (yalnız deneme için) başka
    /// bir uygulamayı hedefler: `defaults write <paket> NinoGameWindowApp "Safari"`.
    static var wanted: [String] {
        #if DEBUG
        // Yalnız geliştirici derlemesinde: yayımlanan sürüm başka uygulamaların pencerelerini okuyamaz.
        if let custom = UserDefaults.standard.string(forKey: "NinoGameWindowApp"), !custom.isEmpty {
            return [custom.lowercased()]
        }
        #endif
        return ["remote play", "remoteplay", "chiaki"]
    }

    /// Küçük pencereler (araç çubuğu, ayar penceresi) oyun sayılmaz.
    static let minimumSize = CGSize(width: 320, height: 180)

    static func pick(_ windows: [GameWindowInfo], wanted: [String] = wanted) -> GameWindowInfo? {
        windows
            .filter { w in
                let name = (w.appName + " " + w.bundleID).lowercased()
                return wanted.contains { name.contains($0) }
                    && w.frame.width >= minimumSize.width && w.frame.height >= minimumSize.height
            }
            // En büyük pencere oyundur (Remote Play'in giriş ya da ayar pencereleri daha küçüktür).
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}

/// Pencerenin içinde oyun görüntüsünün durduğu alan. Remote Play görüntüyü 16:9 olarak, pencereye sığdırıp ortalar;
/// pencerede başlık çubuğu varsa görüntü onun altındadır. Hesap piksellerden değil pencerenin ölçüsünden yapılır:
/// karanlık sahnelerde siyah bant aramak yanılır.
enum GameArea {
    static let aspect: CGFloat = 16.0 / 9.0
    /// macOS'un standart başlık çubuğu. Bir uygulamanın penceresi farklıysa (yalnız deneme için) değiştirilebilir:
    /// `defaults write <paket> NinoGameWindowTopInset 0`.
    static var titleBar: CGFloat {
        let custom = UserDefaults.standard.object(forKey: "NinoGameWindowTopInset") as? Double
        return CGFloat(custom ?? 28)
    }

    /// Pencereye göre (sol üst başlangıç), nokta cinsinden.
    static func rect(windowSize: CGSize, fillsScreen: Bool) -> CGRect {
        let top = fillsScreen ? 0 : min(titleBar, windowSize.height / 4)
        let area = CGRect(x: 0, y: top, width: windowSize.width, height: max(1, windowSize.height - top))
        var size = CGSize(width: area.width, height: area.width / aspect)
        if size.height > area.height { size = CGSize(width: area.height * aspect, height: area.height) }
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                      width: size.width, height: size.height).integral
    }

    /// Oyun alanı ekran koordinatlarında (sol üst başlangıç).
    static func screenRect(of window: GameWindowInfo) -> CGRect {
        rect(windowSize: window.frame.size, fillsScreen: window.fillsScreen).offsetBy(dx: window.frame.minX, dy: window.frame.minY)
    }
}

/// Seçilen oyun penceresini okur ve yalnız oyun alanını, PS5'ten gelen karelerle aynı boyda (1920 × 1080) verir.
///
/// - Yalnız o pencere okunur; Nino'nun kendi altyazı penceresi asla kareye girmez.
/// - Görüntü durunca (menü, duraklatma) ScreenCaptureKit yeni kare göndermez; son kare sabit hızla yeniden verilir,
///   böylece okuma hattı satırı bitirip kaldırabilir.
/// - Pencere kapanır, taşınır, büyür ya da tam ekrana geçerse kendiliğinden yeniden bulunur.
final class GameWindowCapture: NSObject, @unchecked Sendable {
    enum Status: Equatable {
        case stopped
        /// Ekran Kaydı izni yok (Sistem Ayarları › Gizlilik ve Güvenlik › Ekran ve Sistem Sesi Kaydı).
        case needsPermission
        /// PS Remote Play ya da chiaki-ng penceresi bulunamadı.
        case lookingForWindow
        case capturing(appName: String)
    }

    var onFrame: ((CGImage) -> Void)?
    var onStatus: ((Status) -> Void)?
    /// Oyun alanının ekrandaki yeri (sol üst başlangıç); altyazı penceresi bunu izleyebilir.
    var onGameArea: ((CGRect?) -> Void)?

    static let outputSize = CGSize(width: 1920, height: 1080)
    /// Okuma hattına saniyede verilen kare (PS5 yolundaki gibi; okuma zaten önceki kare bitmeden yenisini almaz).
    static let framesPerSecond = 10.0

    private let queue = DispatchQueue(label: "nino.game-window-capture")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var stream: SCStream?
    private var current: GameWindowInfo?
    private var latest: CGImage?
    private var watcher: DispatchSourceTimer?
    private var emitter: DispatchSourceTimer?
    private var running = false
    private var askedPermission = false
    private var status = Status.stopped
    private var lookups = 0

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            lookups = 0
            let watcher = DispatchSource.makeTimerSource(queue: queue)
            watcher.schedule(deadline: .now(), repeating: 1.5)
            watcher.setEventHandler { [weak self] in self?.lookUp() }
            watcher.resume()
            self.watcher = watcher
            let emitter = DispatchSource.makeTimerSource(queue: queue)
            emitter.schedule(deadline: .now() + 0.5, repeating: 1 / Self.framesPerSecond)
            emitter.setEventHandler { [weak self] in
                guard let self, let frame = self.latest else { return }
                self.onFrame?(frame)
            }
            emitter.resume()
            self.emitter = emitter
        }
    }

    func stop() {
        queue.async { [self] in
            running = false
            watcher?.cancel()
            emitter?.cancel()
            watcher = nil
            emitter = nil
            endStream()
            set(.stopped)
        }
    }

    /// Pencereyi hemen yeniden arar (ör. Mac uykudan uyandı).
    func refresh() {
        queue.async { [self] in
            endStream()
            lookUp()
        }
    }

    // MARK: - Pencereyi bulma

    private func lookUp() {
        guard running else { return }
        guard CGPreflightScreenCaptureAccess() else {
            if !askedPermission {
                askedPermission = true
                // macOS izin penceresini bir kez gösterir; izin verilince Nino yeniden açılmalıdır.
                DispatchQueue.main.async { _ = CGRequestScreenCaptureAccess() }
            }
            endStream()
            set(.needsPermission)
            return
        }
        lookups += 1
        let lookup = lookups
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, _ in
            guard let self else { return }
            self.queue.async { self.found(content, lookup: lookup) }
        }
    }

    private func found(_ content: SCShareableContent?, lookup: Int) {
        guard running, lookup == lookups else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let displays = content?.displays.map(\.frame) ?? []
        let windows = (content?.windows ?? []).filter { $0.windowLayer == 0 && $0.owningApplication?.processID != ownPID }
        let infos = windows.map { w in
            GameWindowInfo(id: w.windowID, appName: w.owningApplication?.applicationName ?? "",
                           bundleID: w.owningApplication?.bundleIdentifier ?? "", title: w.title ?? "", frame: w.frame,
                           fillsScreen: displays.contains { Self.fills($0, w.frame) })
        }
        guard let pick = GameWindowPicker.pick(infos), let window = windows.first(where: { $0.windowID == pick.id }) else {
            endStream()
            set(.lookingForWindow)
            return
        }
        if pick == current, stream != nil { return }
        if let current, current.id == pick.id, let stream {
            // Aynı pencere taşındı ya da boyu değişti: akış kapatılmadan oyun alanı güncellenir.
            self.current = pick
            stream.updateConfiguration(configuration(for: pick)) { _ in }
            report(pick)
            return
        }
        endStream()
        begin(window, info: pick)
    }

    /// Tam ekran pencere ekranın genişliğini ve alt kenarını kaplar. Çentikli ekranlarda tam ekran pencere ekrandan
    /// kısa olabilir (çentiğin altı), bu yüzden yükseklik değil alt kenar karşılaştırılır.
    static func fills(_ display: CGRect, _ window: CGRect) -> Bool {
        abs(display.minX - window.minX) < 2 && abs(display.width - window.width) < 2 && abs(display.maxY - window.maxY) < 2
            && window.height > display.height * 0.85
    }

    // MARK: - Akış

    private func configuration(for info: GameWindowInfo) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = GameArea.rect(windowSize: info.frame.size, fillsScreen: info.fillsScreen)
        config.width = Int(Self.outputSize.width)
        config.height = Int(Self.outputSize.height)
        config.scalesToFit = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Self.framesPerSecond * 2))
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        return config
    }

    private func begin(_ window: SCWindow, info: GameWindowInfo) {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let stream = SCStream(filter: filter, configuration: configuration(for: info), delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        } catch {
            set(.lookingForWindow)
            return
        }
        self.stream = stream
        current = info
        stream.startCapture { [weak self] error in
            guard let self, error != nil else { return }
            self.queue.async {
                guard self.stream === stream else { return }
                self.endStream()
                self.set(.lookingForWindow)
            }
        }
        report(info)
    }

    private func endStream() {
        // Zaten okunmuyorsa bir şey değişmez; aranırken her turda "alan yok" bildirilmesin.
        guard stream != nil || current != nil || latest != nil else { return }
        stream?.stopCapture { _ in }
        stream = nil
        current = nil
        latest = nil
        DispatchQueue.main.async { [onGameArea] in onGameArea?(nil) }
    }

    private func report(_ info: GameWindowInfo) {
        set(.capturing(appName: info.appName))
        let area = GameArea.screenRect(of: info)
        DispatchQueue.main.async { [onGameArea] in onGameArea?(area) }
    }

    private func set(_ new: Status) {
        guard new != status else { return }
        status = new
        DispatchQueue.main.async { [onStatus] in onStatus?(new) }
    }
}

extension GameWindowCapture: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, stream === self.stream, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = sampleBuffer.imageBuffer else { return }
        // Kare kendi belleğine kopyalanır; akışın yüzeyi tutulmaz (tutulursa ScreenCaptureKit yeni kare veremez).
        let image = CIImage(cvPixelBuffer: pixels)
        guard let frame = ciContext.createCGImage(image, from: image.extent, format: .BGRA8,
                                                  colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return }
        latest = frame
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [self] in
            guard self.stream === stream else { return }
            endStream()
            set(.lookingForWindow)
        }
    }
}
