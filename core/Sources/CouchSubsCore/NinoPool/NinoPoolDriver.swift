// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Network

/// Havuzu çalıştırır: açılışta ve dakikada bir `flush()` (asıl zamanlamayı havuz yapar), ağ geri gelince hemen dener,
/// uygulama kapanırken bekleyenler dosyasını kapatır (satırlar zaten diskte; kapanışta ağ beklenmez).
public final class NinoPoolDriver: @unchecked Sendable {
    private let pool: NinoPool
    private let monitor = NWPathMonitor()
    private var ticker: Task<Void, Never>?
    private let lock = NSLock()
    private var online: Bool?

    public init(pool: NinoPool) {
        self.pool = pool
    }

    public func start() {
        let pool = self.pool
        ticker = Task.detached(priority: .background) {
            await pool.flush()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(NinoPool.tickInterval * 1_000_000_000))
                await pool.flush()
            }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let now = path.status == .satisfied
            let cameBack = self.lock.withLock { () -> Bool in
                defer { self.online = now }
                return now && self.online == false
            }
            if cameBack { Task.detached(priority: .background) { await pool.networkAvailable() } }
        }
        monitor.start(queue: DispatchQueue(label: "nino.pool-network", qos: .background))
    }

    /// Kapanışta çağrılır; en çok bir saniye bekler.
    public func stop() {
        ticker?.cancel()
        monitor.cancel()
        let pool = self.pool
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await pool.close()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }
}
