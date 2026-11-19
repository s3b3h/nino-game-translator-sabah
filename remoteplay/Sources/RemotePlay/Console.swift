// SPDX-License-Identifier: AGPL-3.0-only

import CChiaki
import Darwin
import Foundation

public struct ConsoleInfo: Codable, Hashable, Sendable {
    public let host: String
    public let name: String
    public let isAwake: Bool
    /// PS5'te o an çalışan uygulama (keşif yanıtındaki `running-app-titleid` ve `running-app-name`); ana ekranda ya
    /// da dinlenme modunda yok.
    public let runningAppTitleId: String?
    public let runningAppName: String?

    public init(host: String, name: String, isAwake: Bool, runningAppTitleId: String? = nil, runningAppName: String? = nil) {
        self.host = host
        self.name = name
        self.isAwake = isAwake
        self.runningAppTitleId = runningAppTitleId
        self.runningAppName = runningAppName
    }
}

/// Yerel ağdaki PS5'leri bulur ve uyutulmuş olanı uyandırır.
public enum Console {
    /// `host` verilirse yalnız o adrese sorulur (genel yayın bazı ağlarda engellenebiliyor).
    public static func discover(timeout: Duration = .seconds(3), host: String? = nil) async -> [ConsoleInfo] {
        // Arama birkaç saniye uyuyarak bekler; Swift'in iş havuzunu tutmamak için ayrı kuyrukta çalışır.
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: search(timeout: timeout, host: host))
            }
        }
    }

    /// Kayıtlı PS5'i dinlenme modundan uyandırır.
    public static func wake(_ console: RegisteredConsole) throws {
        guard let credential = console.wakeCredential else { throw ChiakiError(code: CHIAKI_ERR_INVALID_DATA) }
        let logger = ChiakiLogger()
        // Günlük çağrı bitene dek yaşamalı: Swift onu son kullanımda (`pointer` okununca) bırakabilir, libchiaki ise
        // uyandırma sırasında günlüğe yazar (serbest kalmış belleğe yazmak chiaki_log'da çökertir).
        let error = withExtendedLifetime(logger) {
            chiaki_discovery_wakeup(logger.pointer, nil, console.host, credential, true)
        }
        guard error.isSuccess else { throw ChiakiError(code: error) }
    }

    private final class Collector {
        var hosts: [String: ConsoleInfo] = [:]
        let lock = NSLock()
    }

    static func search(timeout: Duration, host: String?) -> [ConsoleInfo] {
        searchDetailed(timeout: timeout, host: host).consoles
    }

    /// Aramanın sonucu ve gönderimlerin özeti (bkz. `LocalNetworkAccess`).
    struct SearchResult {
        var consoles: [ConsoleInfo]
        var sends: SearchSendTally
    }

    /// Gönderim sırasında libchiaki'nin yazdığı hata satırı. `chiaki_discovery_send` hatayı (errno metniyle) dönmeden
    /// önce, çağıran iş parçacığında günlüğe yazar; errno ise günlük yazılırken değişebildiği için okunmaz.
    private final class SendError {
        private var line: String?
        private let lock = NSLock()
        func set(_ value: String?) {
            lock.lock()
            line = value
            lock.unlock()
        }
        var current: String? {
            lock.lock()
            defer { lock.unlock() }
            return line
        }
    }

    static func searchDetailed(timeout: Duration, host: String?) -> SearchResult {
        // Kayıtlı adres bilinmiyorsa (boş, 0.0.0.0…) sorulacak yer yok. `inet_addr("0.0.0.0")` 0 verir ve macOS bu
        // adrese gönderimi "No route to host" ile reddeder; boş metin ise genel yayına döner.
        if let host, !ConsoleAddress.isUsable(host) { return SearchResult(consoles: [], sends: SearchSendTally()) }

        let logger = ChiakiLogger()
        // İlk defer en son çalışır: günlük, aşağıdaki chiaki_discovery_fini de dahil her C çağrısından sonra bırakılır.
        defer { withExtendedLifetime(logger) {} }
        let sendError = SendError()
        logger.isQuiet = { $0.hasPrefix(LocalNetworkAccess.sendFailurePrefix) }
        logger.onMessage = { text, _ in
            if text.hasPrefix(LocalNetworkAccess.sendFailurePrefix) { sendError.set(text) }
        }
        let discovery = UnsafeMutablePointer<ChiakiDiscovery>.allocate(capacity: 1)
        let thread = UnsafeMutablePointer<ChiakiDiscoveryThread>.allocate(capacity: 1)
        defer {
            discovery.deallocate()
            thread.deallocate()
        }
        guard chiaki_discovery_init(discovery, logger.pointer, sa_family_t(AF_INET)).isSuccess else {
            return SearchResult(consoles: [], sends: SearchSendTally())
        }
        defer { chiaki_discovery_fini(discovery) }

        let collector = Collector()
        let user = Unmanaged.passUnretained(collector).toOpaque()
        guard chiaki_discovery_thread_start(thread, discovery, { host, user in
            guard let host, let user, chiaki_discovery_host_is_ps5(host), let address = host.pointee.host_addr else { return }
            let collector = Unmanaged<Collector>.fromOpaque(user).takeUnretainedValue()
            let info = ConsoleInfo(host: String(cString: address),
                                   name: host.pointee.host_name.map { String(cString: $0) } ?? "PS5",
                                   isAwake: host.pointee.state == CHIAKI_DISCOVERY_HOST_STATE_READY,
                                   runningAppTitleId: host.pointee.running_app_titleid.map { String(cString: $0) },
                                   runningAppName: host.pointee.running_app_name.map { String(cString: $0) })
            collector.lock.lock()
            collector.hosts[info.host] = info
            collector.lock.unlock()
        }, user).isSuccess else { return SearchResult(consoles: [], sends: SearchSendTally()) }

        let version = strdup(CHIAKI_DISCOVERY_PROTOCOL_VERSION_PS5)
        defer { free(version) }
        var packet = ChiakiDiscoveryPacket(cmd: CHIAKI_DISCOVERY_CMD_SRCH, protocol_version: version, user_credential: 0)

        // Adres verilmezse yerel ağdaki her adrese ayrı ayrı sorulur; macOS'ta genel yayına PS5'ten
        // yanıt gelmeyebiliyor, tek tek sorgu her ağda çalışıyor.
        let networks = localNetworks()
        let targets: [in_addr_t] = host.map { [inet_addr($0)] } ?? Self.targets(networks: networks).map { $0.bigEndian }
        // Yerel ağ izni işareti için yalnız doğrudan bağlı alt ağdaki tek tek adresler sayılır.
        let local = Set(targets.filter { isOnLink(UInt32(bigEndian: $0), networks: networks) })
        var sends = SearchSendTally(targets: local.count)
        var failures: [String: Int] = [:]

        // Yanıt kaçmasın diye arama birkaç kez tekrarlanır.
        let end = ContinuousClock.now + timeout
        while ContinuousClock.now < end {
            for target in targets {
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = in_port_t(CHIAKI_DISCOVERY_PORT_PS5).bigEndian
                address.sin_addr.s_addr = target
                sendError.set(nil)
                let sent = withUnsafeMutablePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        chiaki_discovery_send(discovery, &packet, $0, MemoryLayout<sockaddr_in>.size)
                    }
                }
                if sent.isSuccess {
                    if local.contains(target) { sends.delivered += 1 }
                    continue
                }
                let line = sendError.current ?? String(cString: chiaki_error_string(sent))
                failures[String(line.dropFirst(line.hasPrefix(LocalNetworkAccess.sendFailurePrefix) ? LocalNetworkAccess.sendFailurePrefix.count : 0)), default: 0] += 1
                guard local.contains(target) else { continue }
                if LocalNetworkAccess.isBlockedSendError(line) { sends.blocked += 1 } else { sends.otherFailures += 1 }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        chiaki_discovery_thread_stop(thread)

        collector.lock.lock()
        let found = Array(collector.hosts.values)
        collector.lock.unlock()
        let consoles = usableReplies(found, asked: host)
        sends.answers = consoles.count
        if !failures.isEmpty {
            // Eskiden her başarısız gönderim ayrı satırdı (tarama başına yüzlerce); artık tek satırlık özet.
            let summary = failures.sorted { $0.key < $1.key }.map { "\($0.value)× \($0.key)" }.joined(separator: ", ")
            RemotePlayLog.write("PS5 araması (\(host ?? "bütün ağ")): gönderilemeyen paketler: \(summary); yerel adres \(sends.targets), kabul edilen \(sends.delivered)")
        }
        LocalNetworkAccess.note(sends)
        return SearchResult(consoles: consoles, sends: sends)
    }

    /// Yanıtların kaynak adresi denetlenir: PS5'in adresi olamayacak bir kaynak (`0.0.0.0`, boş…) listeye girmez, yoksa
    /// "PS5 yeni adreste" diye kaydedilip PS5'i kalıcı olarak ulaşılmaz yapar. Tek bir adrese sorulduysa yanıt o
    /// adresten gelmiştir; kaynağı okunamayan yanıt sorulan adrese yazılır. Bütün ağ tarandıysa hangi adresten geldiği
    /// bilinemez, yanıt atılır. Her iki durum da günlüğe yazılır.
    static func usableReplies(_ found: [ConsoleInfo], asked: String?) -> [ConsoleInfo] {
        var result: [String: ConsoleInfo] = [:]
        for info in found where ConsoleAddress.isUsable(info.host) { result[info.host] = info }
        for info in found where !ConsoleAddress.isUsable(info.host) {
            if let asked, ConsoleAddress.ipv4(asked) != nil, ConsoleAddress.isUsable(asked) {
                RemotePlayLog.write("PS5 yanıtının kaynak adresi geçersiz (\"\(info.host)\"); sorulan adres kullanılıyor: \(asked)")
                if result[asked] == nil {
                    result[asked] = ConsoleInfo(host: asked, name: info.name, isAwake: info.isAwake,
                                                runningAppTitleId: info.runningAppTitleId, runningAppName: info.runningAppName)
                }
            } else {
                RemotePlayLog.write("PS5 yanıtının kaynak adresi geçersiz (\"\(info.host)\", \(info.name)); yanıt atıldı")
            }
        }
        return result.values.sorted { $0.host < $1.host }
    }

    /// Bu cihazın bağlı olduğu IPv4 ağları (ana bilgisayar sıralı adres ve ağ maskesi).
    static func localNetworks() -> [(address: UInt32, netmask: UInt32)] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var networks: [(address: UInt32, netmask: UInt32)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            // iPhone'un hücresel bağdaştırıcısı (pdp_ip) ev ağında değildir; PS5 orada aranmaz.
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, !isCellular(String(cString: entry.ifa_name)),
                  entry.ifa_addr?.pointee.sa_family == sa_family_t(AF_INET), let mask = entry.ifa_netmask else { continue }
            let address = UInt32(bigEndian: entry.ifa_addr!.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr })
            let netmask = UInt32(bigEndian: mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr })
            networks.append((address, netmask))
        }
        return networks
    }

    /// Adres, bağlı ağlardan birinin içinde tek bir cihazın adresi mi (ağ ve yayın adresi, bu cihazın kendi adresi ve
    /// noktadan noktaya bağlantılar hariç).
    static func isOnLink(_ address: UInt32, networks: [(address: UInt32, netmask: UInt32)]) -> Bool {
        networks.contains { network in
            let hostBits = ~network.netmask
            guard hostBits > 1, address != network.address, address & network.netmask == network.address & network.netmask else { return false }
            let part = address & hostBits
            return part != 0 && part != hostBits
        }
    }

    static func isCellular(_ interface: String) -> Bool { interface.hasPrefix("pdp_ip") }

    /// Arama hedefleri (ana bilgisayar sıralı): bağlı IPv4 ağlarındaki tüm adresler (en çok /22, yani 1022 adres), her
    /// ağın yayın adresi ve genel yayın. Eskiden genel yayın yalnız hiç adres bulunamazsa ekleniyordu; Wi-Fi
    /// /22'den büyükken (ör. /16) başka bir arayüz (VPN, sanal makine) adres verince PS5'in ağına hiç sorulmuyordu.
    /// Artık her ağın kendi yayın adresi ve genel yayın da her zaman eklenir.
    static func targets(networks: [(address: UInt32, netmask: UInt32)]) -> [UInt32] {
        var result: [UInt32] = []
        for network in networks {
            result += hosts(address: network.address, netmask: network.netmask)
            if ~network.netmask > 1 { result.append((network.address & network.netmask) | ~network.netmask) }
        }
        result.append(UInt32(INADDR_BROADCAST))
        var seen = Set<UInt32>()
        return result.filter { seen.insert($0).inserted }
    }

    /// Ağdaki diğer adresler (ağ ve yayın adresi hariç); /22'den büyük ağlarda boş.
    static func hosts(address: UInt32, netmask: UInt32) -> [UInt32] {
        let hostCount = ~netmask
        guard hostCount > 1, hostCount <= 1023 else { return [] }
        let network = address & netmask
        return (1..<hostCount).map { network + $0 }.filter { $0 != address }
    }
}
