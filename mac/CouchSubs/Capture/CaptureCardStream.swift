// SPDX-License-Identifier: AGPL-3.0-only
// Nino: `CaptureCardCapture`'ı (ve gerekirse oyunu gösteren pencereyi) uygulamanın görüntü kaynağı arayüzüne bağlayan
// ince katman. Bu dosya Nino için sıfırdan yazıldı.

import CoreGraphics
import RemotePlay

/// Yakalama kartından okunan görüntüyü PS5 bağlantısıyla aynı arayüzle verir; okuma hattı farkı bilmez.
///
/// İki kullanım var:
/// - PS5 → kart (geçişli) → TV: oyun TV'de, altyazı TV uygulamasında. Bilgisayar yalnız okur (`showsPlayer` kapalı).
/// - PS5 → kart → bilgisayar → ekran: oyunu Nino tam ekran gösterir, sesini çalar, altyazı üstünde (`showsPlayer` açık).
final class CaptureCardStream: StreamControlling {
    var onFrame: ((CGImage) -> Void)?
    var onState: ((SessionState) -> Void)?
    var onConsoleMoved: ((RegisteredConsole) -> Void)?
    var onAudio: (([Float]) -> Void)?
    var wantsAudio = false
    /// Kartın ayrıntılı durumu (ana iş parçacığında).
    var onCardStatus: ((CaptureCardCapture.Status) -> Void)?
    /// Oyun alanının ekrandaki yeri (ana iş parçacığında).
    var onGameArea: ((CGRect?) -> Void)?
    /// Kullanıcı oyun penceresini kapattı (ana iş parçacığında).
    var onPlayerClosed: (() -> Void)?

    private let capture = CaptureCardCapture()
    private let showsPlayer: Bool
    private var player: CaptureCardPlayer?

    init(showsPlayer: Bool, preferredID: String? = nil) {
        self.showsPlayer = showsPlayer
        capture.preferredID = preferredID
        capture.playsAudio = showsPlayer
        capture.onFrame = { [weak self] frame in self?.onFrame?(frame) }
        capture.onStatus = { [weak self] status in
            self?.onCardStatus?(status)
            self?.onState?(Self.sessionState(for: status))
        }
    }

    static func sessionState(for status: CaptureCardCapture.Status) -> SessionState {
        switch status {
        case .capturing, .blackPicture: .streaming
        case .stopped: .disconnected(.stopped)
        case .needsPermission, .noCard: .connecting
        }
    }

    func start() {
        capture.wantsAudio = wantsAudio
        capture.onAudio = wantsAudio ? onAudio : nil
        capture.start()
        guard showsPlayer else { return }
        let session = capture.session
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                let player = CaptureCardPlayer(session: session)
                player.onGameArea = { [weak self] area in self?.onGameArea?(area) }
                player.onClose = { [weak self] in self?.onPlayerClosed?() }
                player.show()
                self.player = player
            }
        }
    }

    func stop() {
        capture.stop()
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                player?.close()
                player = nil
            }
        }
    }

    func reconnectNow() { capture.refresh() }

    /// Oyun penceresini tam ekrana alır ya da tam ekrandan çıkarır (ana iş parçacığında).
    @MainActor func toggleFullScreen() { player?.toggleFullScreen() }
}
