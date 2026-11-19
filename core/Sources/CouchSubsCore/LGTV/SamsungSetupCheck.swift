// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Samsung TV'ye kurulumdan önce eksik olan adım. Kullanıcıya yalnız bu adım anlatılır; "TV bu bilgisayarı kabul
/// etmedi" gibi genel bir hata yerine neyin yanlış olduğu söylenir (Nino, 2026-11-19: QE55Q70C'de kullanıcı hangi
/// adımın eksik olduğunu bilemedi).
public enum SamsungSetupProblem: Equatable, Sendable {
    /// TV ne 8001'de ne de kurulum kapısında yanıt veriyor: kapalı, yeniden başlıyor ya da başka ağda.
    case tvNotResponding
    /// Geliştirici modu kapalı: TV'de geliştirici modu penceresi açılmalı.
    case developerModeOff
    /// Host PC IP 127.0.0.1: TV'nin kendi içindeki bir kurucu (ör. TizenBrew) için ayarlanmış, bu bilgisayar kabul edilmez.
    case hostPcIpLoopback
    /// Adres doğru ama başında sıfırlarla yazılmış (192.168.001.092); TV bunu bu bilgisayarın adresi saymaz.
    case hostPcIpPadded(tvIp: String)
    /// Adres ters kaydedilmiş (92.1.168.192): TV dili sağdan sola (Arapça, İbranice) iken yazılan adres ters saklanır.
    case hostPcIpReversed(tvIp: String)
    /// TV'de başka bir adres yazıyor.
    case hostPcIpWrong(tvIp: String)
    /// Geliştirici modu açık ve adres doğru, ama kurulum kapısı (26101) kapalı: TV ayardan sonra tam yeniden başlatılmamış.
    case needsRestart
}

/// Samsung kurulum denetimi: TV'nin 8001 yanıtı, bu bilgisayarın TV'ye giden adresi ve kurulum kapısının durumu.
public struct SamsungSetupCheck: Equatable, Sendable {
    /// TV'nin 8001 yanıtındaki geliştirici modu bilgisi; TV yanıt vermediyse nil.
    public var info: SamsungDeveloperInfo?
    /// Bu bilgisayarın TV'ye giden adresi (Host PC IP'ye yazılması gereken); bulunamadıysa nil.
    public var computer: String?
    /// Kurulum kapısı (sdb, 26101) bağlantı kabul ediyor mu?
    public var portOpen: Bool

    public init(info: SamsungDeveloperInfo?, computer: String?, portOpen: Bool) {
        self.info = info
        self.computer = computer
        self.portOpen = portOpen
    }

    /// Geliştirici modu açık mı? TV 8001'de bildirmezse (eski modeller) kurulum kapısına bakılır.
    public var developerModeOn: Bool { info?.developerMode ?? portOpen }

    /// Host PC IP bu bilgisayarın adresi mi? TV'deki adres ya da bu bilgisayarın adresi bilinmiyorsa nil.
    public var hostPcIpMatches: Bool? {
        guard let tvIp = info?.developerIp, let computer else { return nil }
        return tvIp.trimmingCharacters(in: .whitespaces) == computer.trimmingCharacters(in: .whitespaces)
    }

    /// İlk eksik adım; her şey yerindeyse nil (kurulum denenebilir).
    public var problem: SamsungSetupProblem? {
        if info == nil, !portOpen { return .tvNotResponding }
        guard developerModeOn else { return .developerModeOff }
        if let tvIp = info?.developerIp?.trimmingCharacters(in: .whitespaces), !tvIp.isEmpty {
            if Self.octets(tvIp) == [127, 0, 0, 1] { return .hostPcIpLoopback }
            if let mine = computer?.trimmingCharacters(in: .whitespaces), !mine.isEmpty, tvIp != mine {
                guard let theirs = Self.octets(tvIp), let ours = Self.octets(mine) else { return .hostPcIpWrong(tvIp: tvIp) }
                if theirs == ours { return .hostPcIpPadded(tvIp: tvIp) }
                if theirs == Array(ours.reversed()) { return .hostPcIpReversed(tvIp: tvIp) }
                return .hostPcIpWrong(tvIp: tvIp)
            }
        }
        return portOpen ? nil : .needsRestart
    }

    /// "192.168.001.092" → [192, 168, 1, 92]; dört parçalı IPv4 değilse nil.
    static func octets(_ address: String) -> [Int]? {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber),
                  let value = Int(part), value <= 255 else { return nil }
            result.append(value)
        }
        return result
    }
}

extension SamsungMessages {
    /// 8001 yanıtındaki model yılı (`device.model`: "23_KANTSU2E_QLED" → 2023); okunamazsa nil.
    static func modelYear(_ data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = object["device"] as? [String: Any], let model = device["model"] as? String else { return nil }
        let prefix = model.prefix { $0 != "_" }
        guard prefix.count == 2, prefix.count < model.count, prefix.allSatisfy(\.isASCII), let year = Int(prefix),
              (15...60).contains(year) else { return nil }
        return 2000 + year
    }
}

extension SamsungDiscovery {
    /// TV'nin model yılı; geliştirici modu penceresinin nerede açıldığı yıla göre değişir (2022 ve sonrası: Uygulamalar
    /// sayfasının en altındaki Uygulama Ayarları). TV yanıt vermezse ya da yılı bildirmezse nil.
    public static func modelYear(host: String) async -> Int? {
        guard let url = URL(string: "http://\(host):8001/api/v2/"),
              let (data, _) = try? await LocalNetwork.probeSession.data(from: url) else { return nil }
        return SamsungMessages.modelYear(data)
    }
}

/// Geliştirici modu kodu: kumandadaki 1 2 3 4 5.
public enum SamsungDeveloperCode {
    public static let keys = ["KEY_1", "KEY_2", "KEY_3", "KEY_4", "KEY_5"]

    /// Kodu TV'ye kumanda bağlantısından yazar ve TV'nin verdiği jetonu döner. TV ilk bağlantıda izin sorar; tuşlar
    /// izin verildikten sonra gönderilir (yoksa ilk tuşları izin sorusu yutar: couch-tv #35). Her modelde çalışmaz:
    /// 2022 Q60B ve 2025 Frame'de pencere açıldı, 2025 S85F'te rakamlar arama kutusuna yazıldı.
    public static func type(on tv: LGTV, token: String?) async throws -> String {
        let client = SamsungClient(tv: tv, token: token)
        defer { client.close() }
        let received = try await client.connect()
        try await Task.sleep(for: .milliseconds(700))
        for key in keys {
            try await client.pressKey(key)
            try await Task.sleep(for: .milliseconds(280))
        }
        return received
    }
}
