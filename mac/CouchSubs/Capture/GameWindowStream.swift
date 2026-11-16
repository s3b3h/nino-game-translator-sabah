// SPDX-License-Identifier: AGPL-3.0-only
// Nino: `GameWindowCapture`'ı uygulamanın görüntü kaynağı arayüzüne bağlayan ince katman.

import CoreGraphics
import RemotePlay

/// Oyun penceresinden okunan görüntüyü PS5 bağlantısıyla aynı arayüzle verir; okuma hattı farkı bilmez.
final class GameWindowStream: StreamControlling {
    var onFrame: ((CGImage) -> Void)?
    var onState: ((SessionState) -> Void)?
    var onConsoleMoved: ((RegisteredConsole) -> Void)?
    /// Pencerenin ayrıntılı durumu (ana iş parçacığında).
    var onWindowStatus: ((GameWindowCapture.Status) -> Void)?
    /// Oyun alanının ekrandaki yeri (ana iş parçacığında).
    var onGameArea: ((CGRect?) -> Void)?

    private let capture = GameWindowCapture()

    init() {
        capture.onFrame = { [weak self] frame in self?.onFrame?(frame) }
        capture.onStatus = { [weak self] status in
            self?.onWindowStatus?(status)
            self?.onState?(Self.sessionState(for: status))
        }
        capture.onGameArea = { [weak self] area in self?.onGameArea?(area) }
    }

    static func sessionState(for status: GameWindowCapture.Status) -> SessionState {
        switch status {
        case .capturing: .streaming
        case .stopped: .disconnected(.stopped)
        case .needsPermission, .lookingForWindow: .connecting
        }
    }

    /// Nino: aranan pencere (PS5 ya da Xbox).
    var target: GameWindowTarget {
        get { capture.target }
        set { capture.target = newValue }
    }

    func start() { capture.start() }
    func stop() { capture.stop() }
    func reconnectNow() { capture.refresh() }
}
