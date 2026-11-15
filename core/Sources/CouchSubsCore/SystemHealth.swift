// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Nino: Ayarlar › Sistem sağlığı. Çeviri sürerken PS5 bağlantısının, görüntü akışının ve çevirinin ne kadar sağlıklı
/// olduğunu sayar; `HealthReport` bu sayılardan her satır için yeşil/sarı/kırmızı bir karar çıkarır.
///
/// Sayılar oturum boyunca birikir ve oturum bitince silinmez: kullanıcı Ayarlar'ı çoğu zaman kötü geçen oturumdan sonra
/// açar. Yeni oturum başlayınca sıfırlanır.
///
/// Hız testi bilerek yok: 15 Kasım 2026'da 1000 Mbps internetli bir Mac'te altyazı neredeyse hiç gelmiyordu; sebep hız
/// değil, Mac'in Wi-Fi'sinde kaybolan paketlerdi (2 dakikada 2.743 yeniden gönderim, sağlıklı kablolu Mac'te 80 dakikada 0).
/// Bu yüzden Remote Play'in kendi günlüğündeki kayıp ve yeniden gönderim satırları sayılır.
public final class HealthRecorder: @unchecked Sendable {
    /// Uygulamanın tek kaydedicisi (Remote Play günlüğü, oturum ve ayarlar ekranı bunu paylaşır).
    public static let shared = HealthRecorder()

    private let lock = NSLock()
    private let now: () -> Date
    private var current = HealthSnapshot()
    private var streamingSince: Date?
    /// Görüntü durdu, yeni anahtar kare bekleniyor: libchiaki bir durmada "FEC failed" satırını birkaç kez yazar;
    /// durma, altyazı günlüğündeki `VideoStallTracker` gibi bir kez sayılır (sınırlar o sayıyla ayarlandı).
    private var stalled = false
    /// Son çeviri süreleri (ms), en çok `keptTranslations` tane; ortanca bunlardan hesaplanır.
    private var translationTimes: [Int] = []
    static let keptTranslations = 200

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Yeni oturum: önceki oturumun sayıları silinir.
    public func sessionStarted() {
        lock.withLock {
            current = HealthSnapshot(active: true, startedAt: now())
            streamingSince = nil
            stalled = false
            translationTimes = []
        }
    }

    /// Oturum bitti: sayılar kalır, akış süresi kapanır.
    public func sessionEnded() {
        lock.withLock {
            closeStreaming()
            current.active = false
        }
    }

    /// PS5 bağlantısının durumu değişti.
    public func connecting() {
        lock.withLock { current.connectAttempts += 1 }
    }

    public func streaming() {
        lock.withLock {
            current.connects += 1
            current.streamingNow = true
            if streamingSince == nil { streamingSince = now() }
        }
    }

    /// `reason`: bağlantının neden koptuğu (kullanıcının durdurması sayılmaz).
    public func disconnected(reason: String?) {
        lock.withLock {
            if current.streamingNow, reason != nil { current.drops += 1 }
            if let reason { current.lastDisconnect = reason }
            current.streamingNow = false
            closeStreaming()
        }
    }

    /// Remote Play (libchiaki) günlük satırı. libchiaki'nin iş parçacığında, saniyede yüz kez gelebilir: hızlı döner.
    public func remotePlayLine(_ line: String) {
        let kind: StreamEvent?
        if line.contains("Send Buffer re-sending packet") { kind = .resend }
        else if line.contains("Send Buffer overflow") { kind = .overflow }
        else if line.contains("FEC failed") || line.contains("Video FEC failure") { kind = .stall }
        else if line.contains("Received IDR frame") { kind = .resumed }
        else if line.contains("corrupt frame") { kind = .corrupt }
        else { kind = nil }
        guard let kind else { return }
        lock.withLock {
            switch kind {
            case .resend: current.resends += 1
            case .overflow: current.overflows += 1
            case .stall:
                if !stalled { current.stalls += 1 }
                stalled = true
            case .resumed: stalled = false
            case .corrupt: current.corruptFrames += 1
            }
        }
    }

    /// Ekrana giden bir altyazı satırı; `translationMs` paketten gelen satırda nil.
    public func line(translationMs: Int?) {
        lock.withLock {
            current.lines += 1
            guard let ms = translationMs else { return }
            translationTimes.append(ms)
            if translationTimes.count > Self.keptTranslations { translationTimes.removeFirst() }
            current.translations += 1
            current.translationMaxMs = max(current.translationMaxMs, ms)
        }
    }

    public func snapshot() -> HealthSnapshot {
        lock.withLock {
            var copy = current
            copy.streamingSeconds += streamingSince.map { now().timeIntervalSince($0) } ?? 0
            copy.translationMedianMs = Self.median(translationTimes)
            return copy
        }
    }

    private func closeStreaming() {
        if let since = streamingSince { current.streamingSeconds += now().timeIntervalSince(since) }
        streamingSince = nil
    }

    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    private enum StreamEvent { case resend, overflow, stall, resumed, corrupt }
}

/// Bir oturumun sağlık sayıları.
public struct HealthSnapshot: Equatable, Sendable {
    /// Çeviri sürüyor mu.
    public var active = false
    public var startedAt: Date?
    /// PS5 görüntüsü şu an geliyor mu.
    public var streamingNow = false
    /// Görüntünün geldiği toplam süre (sn).
    public var streamingSeconds: Double = 0
    public var connectAttempts = 0
    public var connects = 0
    /// Görüntü gelirken kopan bağlantılar.
    public var drops = 0
    public var lastDisconnect: String?
    /// Kaybolup yeniden gönderilen paketler.
    public var resends = 0
    /// Gönderim tamponu taştı (paketler sığmadı).
    public var overflows = 0
    /// Görüntünün durduğu anlar (FEC kurtaramadı, yeni anahtar kare beklendi).
    public var stalls = 0
    /// Bozuk kare bildirimleri; sağlıklı bağlantıda da olur, tek başına karar vermez.
    public var corruptFrames = 0
    public var lines = 0
    public var translations = 0
    public var translationMedianMs: Int?
    public var translationMaxMs = 0

    public init(active: Bool = false, startedAt: Date? = nil) {
        self.active = active
        self.startedAt = startedAt
    }

    /// Hiç ölçüm yok (çeviri hiç başlamadı).
    public var isEmpty: Bool { startedAt == nil }

    var streamingMinutes: Double { streamingSeconds / 60 }

    /// Dakikada kaybolan paket (yeniden gönderim + taşma).
    public var lossPerMinute: Double? {
        streamingMinutes >= Self.minimumMinutes ? Double(resends + overflows) / streamingMinutes : nil
    }

    /// Dakikada görüntü durması.
    public var stallsPerMinute: Double? {
        streamingMinutes >= Self.minimumMinutes ? Double(stalls) / streamingMinutes : nil
    }

    /// Bu kadar akış olmadan oran hesaplanmaz (ilk saniyelerdeki tek bir durma "dakikada 60" görünmesin).
    static let minimumMinutes = 0.5
}

/// Sistem sağlığı ekranındaki bir satırın kararı.
public enum HealthLevel: Int, Comparable, Sendable {
    /// Ölçüm yok (ör. çeviri başlamadı).
    case unknown
    case good
    case warning
    case problem

    public static func < (lhs: HealthLevel, rhs: HealthLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Mac'in ağa nasıl bağlı olduğu (uygulama bulur, çekirdek yalnız karar verir).
public enum NetworkKind: Sendable, Equatable {
    case wired, wifi, other, offline, unknown
}

/// Sayılardan satır kararları. Sınırlar 15 Kasım 2026'daki iki günlükle ayarlandı: Wi-Fi'deki Mac dakikada ~1.370 kayıp
/// paket ve 5,1 görüntü durması; kablolu sağlıklı Mac 0 kayıp ve 1,1 durma.
public enum HealthReport {
    public static let lossWarning = 10.0
    public static let lossProblem = 100.0
    public static let stallWarning = 2.5
    public static let stallProblem = 4.0
    /// Çevirinin ortanca süresi (ms).
    public static let translationWarningMs = 1500
    public static let translationProblemMs = 3000
    /// Görüntü gelirken bu kadar kopma olursa uyarı.
    public static let dropWarning = 3

    /// Görüntü akışı: kayıp paket ve durmalar.
    public static func stream(_ s: HealthSnapshot) -> HealthLevel {
        guard let loss = s.lossPerMinute, let stalls = s.stallsPerMinute else { return .unknown }
        if loss >= lossProblem || stalls >= stallProblem { return .problem }
        if loss >= lossWarning || stalls >= stallWarning { return .warning }
        return .good
    }

    /// PS5 bağlantısı: hiç bağlanamadı mı, sık mı kopuyor.
    public static func connection(_ s: HealthSnapshot) -> HealthLevel {
        if s.isEmpty { return .unknown }
        if s.connects == 0 { return s.connectAttempts >= 2 ? .problem : .unknown }
        return s.drops >= dropWarning ? .warning : .good
    }

    /// Çeviri süresi.
    public static func translation(_ s: HealthSnapshot) -> HealthLevel {
        guard let median = s.translationMedianMs else { return .unknown }
        if median >= translationProblemMs { return .problem }
        if median >= translationWarningMs { return .warning }
        return .good
    }

    /// Mac'in ağı: kablo iyi; Wi-Fi tek başına ne iyi ne kötüdür, görüntü ölçülünce karar verilir (kayıp varsa ilk
    /// şüpheli odur). Ölçülmeden yeşil gösterilmez: Wi-Fi'deki Mac'te asıl sorun buydu.
    public static func network(_ kind: NetworkKind, stream: HealthLevel) -> HealthLevel {
        switch kind {
        case .wired: return .good
        case .offline: return .problem
        case .unknown: return .unknown
        case .wifi, .other: return stream
        }
    }

    /// Ayrıntılar için düz metin özeti (destek için kopyalanır; altyazı metni ve adres içermez).
    public static func summary(_ s: HealthSnapshot, network: NetworkKind) -> String {
        func rate(_ value: Double?) -> String { value.map { String(format: "%.1f/dk", $0) } ?? "-" }
        return [
            "ağ: \(network)",
            String(format: "akış: %.1f dk, bağlanma denemesi %d, bağlandı %d, akışta kopma %d", s.streamingMinutes,
                   s.connectAttempts, s.connects, s.drops),
            "son kopma sebebi: \(s.lastDisconnect ?? "-")",
            "yeniden gönderim \(s.resends), tampon taşması \(s.overflows) (kayıp \(rate(s.lossPerMinute)))",
            "görüntü durması \(s.stalls) (\(rate(s.stallsPerMinute))), bozuk kare bildirimi \(s.corruptFrames)",
            "altyazı satırı \(s.lines), çeviri \(s.translations), ortanca \(s.translationMedianMs.map { "\($0) ms" } ?? "-"), en uzun \(s.translationMaxMs) ms",
        ].joined(separator: "\n")
    }
}
