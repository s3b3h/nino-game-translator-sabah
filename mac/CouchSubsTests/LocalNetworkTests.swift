// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import RemotePlay
import XCTest
@testable import Nino

/// Gerçek bildirim (Mac16,12, 3.4.0): güncellemeden sonra kayıtlı PS5 adresi `0.0.0.0` olmuş, PS5 bir daha
/// bulunamamıştı. Geçersiz adres kaydedilmez; Yerel Ağ izni kapalı görünüyorsa kullanıcıya söylenir.
@MainActor
final class LocalNetworkTests: XCTestCase {
    private func pairedModel() async throws -> (AppModel, FakeServices, MemoryStore) {
        let services = FakeServices()
        let store = MemoryStore()
        let model = AppModel(services: services, store: store, defaults: .isolated())
        model.accountId = Data(repeating: 1, count: 8)
        try await model.register(host: "192.168.1.70", pin: "12345678")
        model.settings.output = .computer
        return (model, services, store)
    }

    /// Oturum PS5'i `0.0.0.0`'da (ya da boş adreste) "bulursa" adres kaydedilmez; eski adres kalır.
    func testZeroAddressIsNotSavedAsTheNewAddress() async throws {
        let (model, services, store) = try await pairedModel()
        await model.start()
        for host in ["0.0.0.0", "", "255.255.255.255"] {
            let moved = RegisteredConsole(host: host, name: "PS5-789", registKey: Data(repeating: 0x31, count: 16),
                                          morning: Data(repeating: 2, count: 16))
            services.streams.first?.onConsoleMoved?(moved)
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(model.console?.host, "192.168.1.70", host)
            XCTAssertEqual(store.load(RegisteredConsole.self, for: StoreKey.console)?.host, "192.168.1.70", host)
        }
        model.stop()
    }

    /// Elle `0.0.0.0` yazılırsa eşleştirme başlamaz ve hiçbir şey kaydedilmez.
    func testZeroAddressCannotBePaired() async {
        let services = FakeServices()
        let store = MemoryStore()
        let model = AppModel(services: services, store: store, defaults: .isolated())
        model.accountId = Data(repeating: 1, count: 8)
        do {
            try await model.register(host: "0.0.0.0", pin: "12345678")
            XCTFail("eşleşmemeliydi")
        } catch {
            XCTAssertEqual(error as? AppError, .badAddress)
        }
        XCTAssertNil(model.console)
        XCTAssertNil(store.load(RegisteredConsole.self, for: StoreKey.console))
        XCTAssertNil(services.registeredPin)
    }

    /// İzin kapalı görünüyorsa PS5 durumu "bulunamadı" yerine ne yapılacağını söyler; PS5 yanıt verdiyse karışmaz.
    func testStatusTextExplainsBlockedLocalNetwork() {
        let warning = AppModel.localNetworkWarning
        XCTAssertEqual(AppModel.statusText(.disconnected(.notFound("192.168.1.70")), running: true, localNetworkBlocked: true), warning)
        XCTAssertEqual(AppModel.statusText(.disconnected(.network), running: true, localNetworkBlocked: true), warning)
        XCTAssertEqual(AppModel.statusText(.connecting, running: true, localNetworkBlocked: true), warning)
        // PS5 yanıt verdiyse (kullanımda, eşleme geçersiz) ya da bağlıysa asıl durum söylenir.
        XCTAssertEqual(AppModel.statusText(.disconnected(.inUse), running: true, localNetworkBlocked: true),
                       String(localized: "Remote Play is in use on another device"))
        XCTAssertEqual(AppModel.statusText(.streaming, running: true, localNetworkBlocked: true), String(localized: "Connected"))
        // Çeviri sürmüyorsa uyarı yok.
        XCTAssertEqual(AppModel.statusText(.disconnected(.stopped), running: false, localNetworkBlocked: true), String(localized: "Not connected"))
        // İşaret yoksa eski metinler.
        XCTAssertTrue(AppModel.statusText(.disconnected(.notFound("192.168.1.70")), running: true).contains("192.168.1.70"))
        XCTAssertEqual(AppModel.localNetworkSettingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
    }

    /// Oturumun işareti (bütün yerel gönderimler "No route to host") modele ulaşır; bağlanınca ve durunca kalkar.
    func testBlockedSignalReachesTheModelAndClears() async throws {
        let (model, services, _) = try await pairedModel()
        // Çeviri sürmüyorken işaret yok sayılır.
        model.localNetworkChanged(blocked: true)
        XCTAssertFalse(model.localNetworkBlocked)

        await model.start()
        let stream = try XCTUnwrap(services.streams.first)
        stream.onState?(.disconnected(.notFound("192.168.1.70")))
        stream.onLocalNetworkBlocked?(true)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(model.localNetworkBlocked)
        XCTAssertEqual(model.ps5StatusText, AppModel.localNetworkWarning)

        stream.onLocalNetworkBlocked?(false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(model.localNetworkBlocked)
        XCTAssertTrue(model.ps5StatusText.contains("192.168.1.70"))

        // PS5 bağlandıysa yerel ağa ulaşılıyor demektir.
        stream.onLocalNetworkBlocked?(true)
        try await Task.sleep(for: .milliseconds(50))
        stream.onState?(.streaming)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(model.localNetworkBlocked)

        stream.onLocalNetworkBlocked?(true)
        try await Task.sleep(for: .milliseconds(50))
        model.stop()
        XCTAssertFalse(model.localNetworkBlocked)
    }

    /// Yeni metinler katalogda 12 dilin hepsiyle durur; Türkçesi istenen cümledir.
    func testNewStringsAreTranslatedIntoEveryLanguage() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CouchSubs/Resources/Localizable.xcstrings")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let strings = root?["strings"] as? [String: Any] ?? [:]
        let languages: Set<String> = ["en", "tr", "ar", "bn", "fil", "hi", "id", "ms", "nl", "th", "ur", "vi"]
        let expectedTurkish = [
            "This Mac's local network permission may be off. Turn on Nino in System Settings › Privacy & Security › Local Network, then restart Nino.":
                "Mac'in yerel ağ izni kapalı olabilir. Sistem Ayarları › Gizlilik ve Güvenlik › Yerel Ağ'da Nino'yu aç, sonra Nino'yu yeniden başlat.",
            "Open System Settings": "Sistem Ayarları'nı aç",
        ]
        for (key, turkish) in expectedTurkish {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            XCTAssertEqual(Set(localizations.keys), languages, key)
            for (language, entry) in localizations {
                let unit = (entry as? [String: Any])?["stringUnit"] as? [String: Any]
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(key) [\(language)]")
                XCTAssertFalse((unit?["value"] as? String ?? "").isEmpty, "\(key) [\(language)]")
            }
            let tr = ((localizations["tr"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            XCTAssertEqual(tr, turkish, key)
        }
    }
}
