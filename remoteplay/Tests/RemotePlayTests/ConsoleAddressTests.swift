// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import RemotePlay

/// Gerçek bildirim (Mac16,12, 3.4.0): güncellemeden sonra kayıtlı PS5 adresi `0.0.0.0` olmuş, PS5 bir daha
/// bulunamamıştı. Bu testlerin hiçbiri ağa paket göndermez.
final class ConsoleAddressTests: XCTestCase {
    private func console(host: String, name: String = "PS5-A") -> RegisteredConsole {
        RegisteredConsole(host: host, name: name, registKey: Data(repeating: 0x31, count: 16), morning: Data(repeating: 1, count: 16))
    }

    func testOnlyRealAddressesAreUsable() {
        for host in ["192.168.1.70", "10.0.0.5", "172.16.4.9", "127.0.0.1", "ps5.local", " 192.168.1.70 "] {
            XCTAssertTrue(ConsoleAddress.isUsable(host), host)
        }
        for host in ["", "   ", "0.0.0.0", "0.1.2.3", "255.255.255.255", "224.0.0.1", "192.168.1", "192.168.1.256", "1.2.3.4.5", "...", "12345"] {
            XCTAssertFalse(ConsoleAddress.isUsable(host), host)
        }
    }

    // MARK: - 0.0.0.0 kaydedilmez

    /// Bütün ağ taranırken kaynağı 0.0.0.0 görünen yanıt listeye girmez (hangi adresten geldiği bilinemez).
    func testSweepDropsRepliesWithUnusableSource() {
        let bad = ConsoleInfo(host: "0.0.0.0", name: "PS5-A", isAwake: true)
        let good = ConsoleInfo(host: "192.168.1.70", name: "PS5-B", isAwake: true)
        XCTAssertEqual(Console.usableReplies([bad], asked: nil), [])
        XCTAssertEqual(Console.usableReplies([bad, good], asked: nil), [good])
        XCTAssertEqual(Console.usableReplies([ConsoleInfo(host: "", name: "PS5-A", isAwake: true)], asked: nil), [])
    }

    /// Tek adrese sorulduysa yanıt o adresten gelmiştir: kaynağı okunamayan yanıt sorulan adrese yazılır.
    func testReplyToASingleAddressKeepsTheAskedAddress() {
        let bad = ConsoleInfo(host: "0.0.0.0", name: "PS5-A", isAwake: false, runningAppTitleId: "PPSA01", runningAppName: "Game")
        let fixed = Console.usableReplies([bad], asked: "192.168.1.70")
        XCTAssertEqual(fixed, [ConsoleInfo(host: "192.168.1.70", name: "PS5-A", isAwake: false, runningAppTitleId: "PPSA01", runningAppName: "Game")])
        // Ağ adına sorulduysa paket genel yayına gider; kim yanıtladığı bilinemez.
        XCTAssertEqual(Console.usableReplies([bad], asked: "ps5.local"), [])
    }

    /// Taramada tek yanıt 0.0.0.0 ise PS5 "taşınmış" sayılmaz: adres değişmez, kaydedilecek bir şey çıkmaz.
    func testZeroAddressIsNeverPickedAsTheNewAddress() {
        let bad = ConsoleInfo(host: "0.0.0.0", name: "PS5-A", isAwake: true)
        XCTAssertNil(StreamSession.moved(console(host: "192.168.1.70"), found: [bad]))
        XCTAssertNil(StreamSession.moved(console(host: "192.168.1.70"), found: [ConsoleInfo(host: "", name: "PS5-A", isAwake: true)]))
        // Geçerli yeni adres kabul edilir; aynı adres "taşınma" değildir.
        let good = ConsoleInfo(host: "192.168.1.71", name: "PS5-A", isAwake: true)
        XCTAssertEqual(StreamSession.moved(console(host: "192.168.1.70"), found: [bad, good]), good)
        XCTAssertNil(StreamSession.moved(console(host: "192.168.1.71"), found: [good]))
    }

    func testRegistrationRefusesUnusableAddress() async {
        for host in ["0.0.0.0", "", "255.255.255.255"] {
            do {
                _ = try await Registration.register(host: host, accountId: Data(repeating: 1, count: 8), pin: 12_345_678)
                XCTFail("kayıt olmamalıydı: \(host)")
            } catch let error as Registration.RegistrationError {
                XCTAssertEqual(error.kind, .badAddress, host)
            } catch {
                XCTFail("beklenmeyen hata: \(error)")
            }
        }
    }

    // MARK: - Kayıtlı 0.0.0.0 yeniden aramaya düşer

    /// Kayıtlı adres 0.0.0.0 ise yeni adres adıyla bulunur.
    func testSavedZeroAddressIsReplacedByTheFoundOne() {
        let saved = console(host: "0.0.0.0", name: "PS5-A")
        let a = ConsoleInfo(host: "192.168.1.70", name: "PS5-A", isAwake: true)
        let b = ConsoleInfo(host: "192.168.1.80", name: "PS5-B", isAwake: true)
        XCTAssertEqual(StreamSession.moved(saved, found: [a]), a)
        XCTAssertEqual(StreamSession.moved(saved, found: [b, a]), a)
        XCTAssertNil(StreamSession.moved(saved, found: []))
    }

    /// Oturum, kayıtlı 0.0.0.0'a hiç sormaz: doğrudan bütün ağı tarar. PS5 bulunamazsa 0.0.0.0'a bağlanmayı denemez,
    /// "0.0.0.0 adresinde bulunamadı" demez ve yeni adres kaydetmez.
    func testSessionWithSavedZeroAddressSweepsInsteadOfAskingIt() {
        let session = StreamSession(console: console(host: "0.0.0.0"), accountId: Data(repeating: 1, count: 8))
        let lock = NSLock()
        var asked: [String?] = []
        session.searchConsoles = { _, host in
            lock.lock()
            asked.append(host)
            lock.unlock()
            return []
        }
        var movedTo: [String] = []
        session.onConsoleMoved = { movedTo.append($0.host) }
        let disconnected = expectation(description: "kopma bildirildi")
        disconnected.assertForOverFulfill = false
        var reasons: [DisconnectReason] = []
        session.onState = { state in
            guard case .disconnected(let reason) = state else { return }
            lock.lock()
            reasons.append(reason)
            lock.unlock()
            disconnected.fulfill()
        }
        session.start()
        wait(for: [disconnected], timeout: 5)
        session.stop()
        lock.lock()
        defer { lock.unlock() }
        XCTAssertEqual(asked.first ?? "?", nil, "ilk arama bütün ağ olmalı")
        XCTAssertFalse(asked.contains("0.0.0.0"))
        XCTAssertEqual(reasons.first, .network)
        XCTAssertTrue(movedTo.isEmpty)
    }

    /// Geçerli kayıtlı adreste yol değişmedi: önce o adrese sorulur, yanıt yoksa bütün ağ taranır, PS5 bulunamazsa da
    /// kayıtlı adrese bağlanmak denenir ve adres değişmez. (Ağa arama paketi gitmez; oturum bu makinede açılamaz.)
    func testSessionWithValidSavedAddressAsksItFirstAndKeepsIt() {
        let session = StreamSession(console: console(host: "127.0.0.1"), accountId: Data(repeating: 1, count: 8))
        let lock = NSLock()
        var asked: [String?] = []
        session.searchConsoles = { _, host in
            lock.lock()
            asked.append(host)
            lock.unlock()
            return []
        }
        var movedTo: [String] = []
        session.onConsoleMoved = { movedTo.append($0.host) }
        let disconnected = expectation(description: "kopma bildirildi")
        disconnected.assertForOverFulfill = false
        var reasons: [DisconnectReason] = []
        session.onState = { state in
            guard case .disconnected(let reason) = state else { return }
            lock.lock()
            reasons.append(reason)
            lock.unlock()
            disconnected.fulfill()
        }
        session.start()
        wait(for: [disconnected], timeout: 30)
        let begin = Date()
        session.stop()
        XCTAssertLessThan(Date().timeIntervalSince(begin), 0.2)
        lock.lock()
        defer { lock.unlock() }
        XCTAssertEqual(Array(asked.prefix(2)), ["127.0.0.1", nil])
        XCTAssertTrue(movedTo.isEmpty)
        // Arama yanıtsız ve oturum da açılamadı: "bulunamadı" kayıtlı adresle söylenir (PS5 yanıt verip reddettiyse neden odur).
        if case .notFound(let host)? = reasons.first { XCTAssertEqual(host, "127.0.0.1") }
    }

    func testUnknownAddressIsNotShownAsNotFoundAtZero() {
        XCTAssertEqual(DisconnectReason.classify(.network, searchAnswered: false, host: "0.0.0.0"), .network)
        XCTAssertEqual(DisconnectReason.classify(.other("x"), searchAnswered: false, host: ""), .network)
        XCTAssertEqual(DisconnectReason.classify(.network, searchAnswered: false, host: "192.168.1.70"), .notFound("192.168.1.70"))
    }

    /// Geçersiz adrese arama paketi gönderilmez (macOS 0.0.0.0'a gönderimi "No route to host" ile reddeder).
    func testSearchSkipsUnusableAddressWithoutSending() {
        for host in ["0.0.0.0", ""] {
            let result = Console.searchDetailed(timeout: .seconds(5), host: host)
            XCTAssertEqual(result.consoles, [])
            XCTAssertEqual(result.sends, SearchSendTally())
        }
    }
}

/// Yerel Ağ izni işareti: yalnız güçlü işarette "kapalı" denir.
final class LocalNetworkAccessTests: XCTestCase {
    override func tearDown() {
        LocalNetworkAccess.reset()
        super.tearDown()
    }

    func testSendErrorLines() {
        XCTAssertTrue(LocalNetworkAccess.isBlockedSendError("Discovery failed to send: No route to host"))
        XCTAssertTrue(LocalNetworkAccess.isBlockedSendError("Discovery failed to send: Operation not permitted"))
        // O adreste cihaz yok: izinle ilgisi yok.
        XCTAssertFalse(LocalNetworkAccess.isBlockedSendError("Discovery failed to send: Host is down"))
        XCTAssertFalse(LocalNetworkAccess.isBlockedSendError("Discovery failed to send: Network is unreachable"))
    }

    /// EHOSTUNREACH işareti: bütün alt ağ tarandı, tek gönderim bile kabul edilmedi, hepsi "No route to host".
    func testEveryLocalSendRefusedMeansBlocked() {
        let tally = SearchSendTally(targets: 253, delivered: 0, blocked: 253 * 6, otherFailures: 0, answers: 0)
        XCTAssertEqual(LocalNetworkAccess.verdict(tally), .blocked)
    }

    /// İzin açıkken de boş adresler "No route to host" verir (ölçüldü: bir tur, sonra "Host is down"); ama ilk
    /// gönderimler ve modeme gönderim kabul edilir. Bu yanlış alarm olmamalı.
    func testNormalSweepWithUnansweredAddressesIsNotBlocked() {
        // Ölçülen tablo: 232 boş adres × (2 kabul, 1 "No route to host", 3 "Host is down"), 21 cihaz hep kabul.
        let measured = SearchSendTally(targets: 253, delivered: 232 * 2 + 21 * 6, blocked: 232, otherFailures: 232 * 3, answers: 0)
        XCTAssertEqual(LocalNetworkAccess.verdict(measured), .reachable)
        // Tek bir gönderim bile kabul edildiyse engel yok.
        XCTAssertEqual(LocalNetworkAccess.verdict(SearchSendTally(targets: 253, delivered: 1, blocked: 1500)), .reachable)
        // PS5 yanıt verdiyse engel yok.
        XCTAssertEqual(LocalNetworkAccess.verdict(SearchSendTally(targets: 253, blocked: 1500, answers: 1)), .reachable)
    }

    func testWeakSignsAreNotEnough() {
        // Tek adrese sorulan arama (kayıtlı PS5 kapalı olabilir): karar yok.
        XCTAssertEqual(LocalNetworkAccess.verdict(SearchSendTally(targets: 1, blocked: 4)), .unknown)
        // "Host is down" karışmışsa paketler ağa çıkabiliyor demektir: karar yok.
        XCTAssertEqual(LocalNetworkAccess.verdict(SearchSendTally(targets: 253, blocked: 253, otherFailures: 253 * 5)), .unknown)
        // Ağ çok büyük olduğu için taranmadı ya da ağ yok: karar yok.
        XCTAssertEqual(LocalNetworkAccess.verdict(SearchSendTally()), .unknown)
    }

    /// Kararsız aramalar son kararı değiştirmez; ulaşılan ilk arama uyarıyı kaldırır.
    func testFlagFollowsDecisiveSearchesOnly() {
        XCTAssertFalse(LocalNetworkAccess.looksBlocked)
        LocalNetworkAccess.note(SearchSendTally(targets: 1, blocked: 4))
        XCTAssertFalse(LocalNetworkAccess.looksBlocked)
        LocalNetworkAccess.note(SearchSendTally(targets: 253, blocked: 1518))
        XCTAssertTrue(LocalNetworkAccess.looksBlocked)
        LocalNetworkAccess.note(SearchSendTally(targets: 1, blocked: 4))
        XCTAssertTrue(LocalNetworkAccess.looksBlocked)
        LocalNetworkAccess.note(SearchSendTally(targets: 1, delivered: 4))
        XCTAssertFalse(LocalNetworkAccess.looksBlocked)
        LocalNetworkAccess.note(SearchSendTally(targets: 253, blocked: 1518))
        LocalNetworkAccess.noteReachable()
        XCTAssertFalse(LocalNetworkAccess.looksBlocked)
    }

    /// Oturum, işaret değişince uygulamaya bildirir.
    func testSessionReportsBlockedLocalNetwork() {
        let session = StreamSession(
            console: RegisteredConsole(host: "0.0.0.0", name: "PS5-A", registKey: Data(repeating: 0x31, count: 16), morning: Data(repeating: 1, count: 16)),
            accountId: Data(repeating: 1, count: 8))
        // Sahte arama: bütün ağ tarandı, hiçbir gönderim kabul edilmedi.
        session.searchConsoles = { _, _ in
            LocalNetworkAccess.note(SearchSendTally(targets: 253, blocked: 1518))
            return []
        }
        let reported = expectation(description: "yerel ağ engeli bildirildi")
        reported.assertForOverFulfill = false
        session.onLocalNetworkBlocked = { if $0 { reported.fulfill() } }
        session.start()
        wait(for: [reported], timeout: 5)
        session.stop()
    }

    func testOnLinkAddresses() {
        let networks: [(address: UInt32, netmask: UInt32)] = [(0xC0A8_00DB, 0xFFFF_FF00)]   // 192.168.0.219/24
        XCTAssertTrue(Console.isOnLink(0xC0A8_005D, networks: networks))    // 192.168.0.93
        XCTAssertFalse(Console.isOnLink(0xC0A8_00DB, networks: networks))   // kendi adresi
        XCTAssertFalse(Console.isOnLink(0xC0A8_00FF, networks: networks))   // ağın yayın adresi
        XCTAssertFalse(Console.isOnLink(0xC0A8_0000, networks: networks))   // ağ adresi
        XCTAssertFalse(Console.isOnLink(0xC0A8_015D, networks: networks))   // başka alt ağ
        XCTAssertFalse(Console.isOnLink(0xFFFF_FFFF, networks: networks))   // genel yayın
        XCTAssertFalse(Console.isOnLink(0, networks: networks))             // 0.0.0.0
        // Noktadan noktaya bağlantı (VPN, /32): yerel ağ sayılmaz.
        XCTAssertFalse(Console.isOnLink(0x0A08_0002, networks: [(0x0A08_0001, 0xFFFF_FFFF)]))
    }
}
