// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı. Yalnız Apple'ın çerçevelerini (AppKit, AVFoundation) kullanır.

import AppKit
import AVFoundation

/// Yakalama kartından gelen oyunu bu bilgisayarda gösteren pencere (TV'si ya da monitörü akıllı olmayanlar için:
/// PS5 → kart → bilgisayar → ekran). Görüntü `AVCaptureVideoPreviewLayer` ile doğrudan ekran kartından çizilir; okuma
/// hattından geçmez, oyuna en az gecikme eklenir. Altyazı penceresi bunun üstünde, oyun alanının altına oturur.
///
/// Açılınca tam ekrana geçer; Esc tam ekrandan çıkar, pencereyi kapatmak çeviriyi durdurur.
@MainActor
final class CaptureCardPlayer: NSObject, NSWindowDelegate {
    /// Oyun alanının ekrandaki yeri (sol üst başlangıç); altyazı penceresi buna oturur.
    var onGameArea: ((CGRect?) -> Void)?
    /// Kullanıcı pencereyi kapattı.
    var onClose: (() -> Void)?

    private var window: NSWindow?
    private let layer: AVCaptureVideoPreviewLayer
    private var closing = false

    init(session: AVCaptureSession) {
        layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        super.init()
    }

    func show() {
        guard window == nil else { return }
        let screen = Self.gameScreen()
        let frame = screen?.visibleFrame.insetBy(dx: 80, dy: 60) ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let window = PlayerWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
        window.title = "Nino"
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.delegate = self
        let view = NSView(frame: window.contentLayoutRect)
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.backgroundColor = NSColor.black.cgColor
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        window.contentView = view
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.toggleFullScreen(nil)
        report()
    }

    /// Tam ekrana alır ya da tam ekrandan çıkarır; küçültülmüşse önce geri getirir.
    func toggleFullScreen() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.toggleFullScreen(nil)
    }

    /// Görüntüyü oturuma yeniden bağlar: oturum yeniden kurulunca ya da ekran uykudan uyanınca görüntü katmanı
    /// eski karede donup kalabiliyor (ses gelmeye devam ederken).
    func reattach() {
        guard window != nil, let session = layer.session else { return }
        layer.session = nil
        layer.session = session
    }

    /// Pencereyi kapatır (çeviri durdu); `onClose` çağrılmaz.
    func close() {
        closing = true
        onGameArea?(nil)
        window?.delegate = nil
        if let window, window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        window?.orderOut(nil)
        window = nil
        layer.session = nil
    }

    /// Oyunun açılacağı ekran: Mac'e HDMI ile bir TV ya da monitör bağlıysa o (dizüstünün kendi ekranı değil), yoksa
    /// ana ekran.
    static func gameScreen() -> NSScreen? {
        let external = NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) == 0
        }
        return external ?? NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - Oyun alanı

    /// Pencerenin içinde görüntünün durduğu 16:9 alan, ekran koordinatlarında (sol üst başlangıç).
    static func gameArea(content: CGRect, primaryHeight: CGFloat) -> CGRect {
        var size = CGSize(width: content.width, height: content.width * 9 / 16)
        if size.height > content.height { size = CGSize(width: content.height * 16 / 9, height: content.height) }
        let x = content.midX - size.width / 2
        let bottom = content.midY - size.height / 2
        return CGRect(x: x, y: primaryHeight - bottom - size.height, width: size.width, height: size.height).integral
    }

    private func report() {
        guard let window, let view = window.contentView else { return }
        let content = window.convertToScreen(view.convert(view.bounds, to: nil))
        let primaryHeight = NSScreen.screens.first?.frame.height ?? content.maxY
        onGameArea?(Self.gameArea(content: content, primaryHeight: primaryHeight))
    }

    func windowDidResize(_ notification: Notification) { report() }
    func windowDidMove(_ notification: Notification) { report() }
    func windowDidEnterFullScreen(_ notification: Notification) { report() }
    func windowDidExitFullScreen(_ notification: Notification) { report() }
    func windowDidChangeScreen(_ notification: Notification) { report() }
    func windowDidMiniaturize(_ notification: Notification) { onGameArea?(nil) }
    func windowDidDeminiaturize(_ notification: Notification) { report() }

    func windowWillClose(_ notification: Notification) {
        guard !closing else { return }
        closing = true
        onGameArea?(nil)
        window = nil
        layer.session = nil
        onClose?()
    }
}

/// Esc tam ekrandan çıkar (oyun penceresi kapanmaz); fare bir süre durunca imleç gizlenir.
private final class PlayerWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        if styleMask.contains(.fullScreen) { toggleFullScreen(nil) }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        NSCursor.setHiddenUntilMouseMoves(true)
    }
}
