// SPDX-License-Identifier: AGPL-3.0-only
// Nino: geçersiz PS5 adresi (0.0.0.0) süzgeci ve yerel ağ izni işareti. Based on CouchSubs by Sinan Yorulmaz
// (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-19.

import Foundation

/// PS5'in adresi kaydedilmeden ve kullanılmadan önce denetlenir. Gerçek bir bildirimde (Mac16,12, 3.4.0) kayıtlı adres
/// `0.0.0.0` olmuştu: macOS bu adrese gönderimi her zaman "No route to host" ile reddeder, PS5 bir daha bulunamaz.
public enum ConsoleAddress {
    /// Bir PS5'in adresi olabilir mi. Boş metin, `0.0.0.0` (ve 0 ile başlayan "bu ağ" adresleri), yayın adresi
    /// (`255.255.255.255`), çok noktaya yayın (224 ve üstü) ve yarım yazılmış IPv4 (ör. "192.168.1") olamaz. Ağ adı
    /// (ör. "ps5.local") olabilir: elle adres girerken kabul ediliyor.
    public static func isUsable(_ host: String) -> Bool {
        let text = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else {
            // Ağ adı: en az bir harf, boşluk yok.
            return text.contains(where: \.isLetter) && !text.contains(where: \.isWhitespace)
        }
        guard let value = ipv4(text) else { return false }
        let first = value >> 24
        return first != 0 && first < 224
    }

    /// Noktalı dört parçalı IPv4 (her parça 0–255), ana bilgisayar sıralı; başka her şey nil.
    static func ipv4(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard (1...3).contains(part.count), let octet = UInt32(part), octet <= 255 else { return nil }
            value = value << 8 | octet
        }
        return value
    }
}

/// Bir aramadaki gönderimlerin özeti: yalnız bu cihazın doğrudan bağlı olduğu alt ağlardaki tek tek adreslere
/// (yayın adresleri hariç) yapılan gönderimler sayılır.
public struct SearchSendTally: Equatable, Sendable {
    /// Sorulan farklı yerel adres sayısı.
    public var targets = 0
    /// Sistemin kabul ettiği gönderimler.
    public var delivered = 0
    /// "No route to host" (EHOSTUNREACH) ya da "Operation not permitted" ile reddedilen gönderimler.
    public var blocked = 0
    /// Başka hatayla düşen gönderimler (ör. "Host is down": o adreste cihaz yok).
    public var otherFailures = 0
    /// Yanıt veren PS5 sayısı.
    public var answers = 0

    public init(targets: Int = 0, delivered: Int = 0, blocked: Int = 0, otherFailures: Int = 0, answers: Int = 0) {
        self.targets = targets
        self.delivered = delivered
        self.blocked = blocked
        self.otherFailures = otherFailures
        self.answers = answers
    }
}

/// macOS'un Yerel Ağ izni kapalı mı? İzni kesin okuyan bir API yok; aramadaki gönderim sonuçlarından tahmin edilir.
///
/// Beklenen (Apple'ın belgelediği, burada izin gerçekten kapatılıp DENENMEDİ): izin kapalıyken sistem yerel adreslere
/// giden her paketi daha yola çıkmadan "No route to host" (EHOSTUNREACH) ile reddeder.
///
/// Ölçülen (macOS 27, izin açık): aynı hata izin açıkken de olağandır. O adreste cihaz yoksa ilk bir-iki gönderim
/// kabul edilir, sonra "No route to host", ardından "Host is down" gelir (253 adreslik olağan bir taramada 63–167
/// "No route to host"); `0.0.0.0`'a gönderim de hep "No route to host" verir. Bu yüzden tek bir hata satırı işaret
/// sayılmaz. İşaret yalnız şudur: bütün alt ağ tarandı (en az `minimumTargets` farklı yerel adres), tek bir gönderim
/// bile kabul edilmedi, hepsi "No route to host"/"not permitted" ile düştü ("Host is down" hiç yok) ve hiçbir PS5
/// yanıt vermedi. İzin açıkken modeme ve öbür cihazlara gönderim hep kabul edildiğinden bu tablo oluşmaz.
public enum LocalNetworkAccess {
    public enum Verdict: Equatable, Sendable {
        /// Güçlü işaret: yerel ağ izni kapalı görünüyor.
        case blocked
        /// Yerel ağa ulaşılıyor (en az bir gönderim kabul edildi ya da bir PS5 yanıt verdi).
        case reachable
        /// Karar verilemez (tek adres soruldu, ağ çok büyük olduğu için taranmadı, karışık hatalar…).
        case unknown
    }

    /// Bu kadar farklı yerel adres sorulmadan karar verilmez (tek adrese gönderim yanıltabilir).
    static let minimumTargets = 4

    static func verdict(_ tally: SearchSendTally) -> Verdict {
        if tally.answers > 0 || tally.delivered > 0 { return .reachable }
        if tally.targets >= minimumTargets, tally.blocked > 0, tally.otherFailures == 0 { return .blocked }
        return .unknown
    }

    static let sendFailurePrefix = "Discovery failed to send: "

    /// libchiaki'nin "Discovery failed to send: …" satırı yerel ağ engeline mi işaret ediyor (EHOSTUNREACH ya da EPERM).
    static func isBlockedSendError(_ line: String) -> Bool {
        line.contains("No route to host") || line.contains("not permitted")
    }

    private static let lock = NSLock()
    private static var blocked = false

    /// Son aramalara göre yerel ağ izni kapalı görünüyor mu. Kararsız aramalar değeri değiştirmez.
    public static var looksBlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return blocked
    }

    /// Bir aramanın sonucunu işler; değer değiştiyse günlüğe yazar.
    static func note(_ tally: SearchSendTally) { note(verdict(tally), tally: tally) }

    /// Yerel ağa ulaşıldığı başka yoldan anlaşıldı (ör. PS5 oturumu açıldı).
    static func noteReachable() { note(.reachable, tally: nil) }

    private static func note(_ verdict: Verdict, tally: SearchSendTally?) {
        guard verdict != .unknown else { return }
        let now = verdict == .blocked
        lock.lock()
        let changed = blocked != now
        blocked = now
        lock.unlock()
        guard changed else { return }
        if now, let tally {
            RemotePlayLog.write("Yerel ağ izni kapalı görünüyor: \(tally.targets) yerel adrese gönderimlerin hepsi (\(tally.blocked)) reddedildi, kabul edilen yok")
        } else if !now {
            RemotePlayLog.write("Yerel ağa yeniden ulaşılıyor")
        }
    }

    /// Testler için.
    static func reset() {
        lock.lock()
        blocked = false
        lock.unlock()
    }
}
