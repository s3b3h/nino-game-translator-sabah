// SPDX-License-Identifier: AGPL-3.0-only
// SshSession'ın TV'nin başlattığı anahtar yenilemesini (RFC 4253 bölüm 9) kaldırdığını sahte bir SSH sunucusuyla
// dener: sunucu ilk anahtar değişiminden hemen sonra ve komutun girişi yüklenirken birer KEXINIT daha gönderir
// (LG webOS 4.5'teki dropbear'ın yaptığı gibi). Kanal verisi kaybolmamalı, komut sonucu tam gelmeli.

import CommonCrypto
import CryptoKit
import Darwin
import XCTest
@testable import CouchSubs

final class SshRekeyTests: XCTestCase {
    func testServerInitiatedRekeyDuringAuthAndUpload() throws {
        let server = try FakeSshServer()
        let input = (0..<150_000).map { UInt8(truncatingIfNeeded: $0 &* 31) }
        let done = expectation(description: "sunucu bitti")
        var serverError: Error?
        var uploaded: [UInt8] = []
        Thread {
            do {
                uploaded = try server.run()
            } catch {
                serverError = error
            }
            done.fulfill()
        }.start()

        let session = try SshSession.connect(host: "127.0.0.1", port: server.port, user: "prisoner", key: try RsaKey.generate(), timeout: 5)
        let result = try session.exec("cat > /tmp/paket", input: input, timeout: 20)
        session.close()
        wait(for: [done], timeout: 20)

        XCTAssertNil(serverError)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "hello world")
        XCTAssertEqual(uploaded, input)
        XCTAssertEqual(session.rekeyCount, 2)
        XCTAssertEqual(server.exchanges, 3)
    }
}

// MARK: - Sahte sunucu (curve25519-sha256, ssh-ed25519, aes128-ctr, hmac-sha2-256)

private struct FakeError: Error, CustomStringConvertible { let description: String }

private final class Ctr {
    private var cryptor: CCCryptorRef?
    init(key: [UInt8], iv: [UInt8]) {
        CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding),
                                iv, key, key.count, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
    }
    deinit { if let cryptor { CCCryptorRelease(cryptor) } }
    func apply(_ data: [UInt8]) -> [UInt8] {
        guard !data.isEmpty else { return [] }
        var output = [UInt8](repeating: 0, count: data.count)
        var moved = 0
        CCCryptorUpdate(cryptor, data, data.count, &output, output.count, &moved)
        return output
    }
}

private struct Keys {
    var cipher: Ctr?
    var macKey: [UInt8] = []
    var sequence: UInt32 = 0
}

private final class FakeSshServer {
    let port: UInt16
    private(set) var exchanges = 0
    private let listener: Int32
    private var fd: Int32 = -1
    private var outgoing = Keys()
    private var incoming = Keys()
    private var sessionId: [UInt8] = []
    private var clientVersion: [UInt8] = []
    private let serverVersion = "SSH-2.0-dropbear_2019.78"
    private let hostKey = Curve25519.Signing.PrivateKey()
    /// Anahtar değişimi beklenirken gelen istemci iletileri (eski anahtarlarla gönderilmiş kanal verisi vb.).
    private var held: [[UInt8]] = []

    init() throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        self.listener = listener
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, length) } }
        guard bound == 0, listen(listener, 1) == 0 else {
            port = 0
            throw FakeError(description: "dinlenemedi")
        }
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) } }
        port = UInt16(bigEndian: address.sin_port)
    }

    deinit {
        if fd >= 0 { close(fd) }
        close(listener)
    }

    /// Bağlantıyı baştan sona yürütür; komutun girişine yüklenen baytları döner.
    func run() throws -> [UInt8] {
        fd = accept(listener, nil, nil)
        guard fd >= 0 else { throw FakeError(description: "bağlantı yok") }
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        try write(Array((serverVersion + "\r\n").utf8))
        var line: [UInt8] = []
        while true {
            let byte = try readExactly(1)[0]
            if byte == 0x0A { break }
            line.append(byte)
        }
        if line.last == 0x0D { line.removeLast() }
        clientVersion = line

        try exchange()     // ilk el sıkışma
        try exchange()     // 1. yenileme: istemcinin SERVICE_REQUEST'i eski anahtarla yolda

        let service = try next()
        guard service.first == 5 else { throw FakeError(description: "SERVICE_REQUEST beklenirken \(service.first ?? 0)") }
        var accept = SshWriter()
        accept.byte(6)
        accept.string("ssh-userauth")
        try send(accept.bytes)
        guard try next().first == 50 else { throw FakeError(description: "USERAUTH beklenirdi") }
        try send([52])

        var open = SshReader(try next())
        guard try open.byte() == 90 else { throw FakeError(description: "CHANNEL_OPEN beklenirdi") }
        _ = try open.string()
        let clientChannel = try open.uint32()
        var confirm = SshWriter()
        confirm.byte(91)
        confirm.uint32(clientChannel)
        confirm.uint32(7)
        confirm.uint32(8 * 1024 * 1024)
        confirm.uint32(32_768)
        try send(confirm.bytes)
        guard try next().first == 98 else { throw FakeError(description: "exec beklenirdi") }
        var success = SshWriter()
        success.byte(99)
        success.uint32(clientChannel)
        try send(success.bytes)

        // Yükleme sürerken: önce biraz çıktı, sonra 2. yenileme.
        try send(channelData(clientChannel, "hello "))
        try exchange()

        var uploaded: [UInt8] = []
        while true {
            var message = SshReader(try next())
            let type = try message.byte()
            if type == 96 { break }
            guard type == 94 else { throw FakeError(description: "kanal verisi beklenirken \(type)") }
            _ = try message.uint32()
            uploaded += try message.string()
        }
        try send(channelData(clientChannel, "world"))
        var exit = SshWriter()
        exit.byte(98)
        exit.uint32(clientChannel)
        exit.string("exit-status")
        exit.bool(false)
        exit.uint32(0)
        try send(exit.bytes)
        var eof = SshWriter()
        eof.byte(96)
        eof.uint32(clientChannel)
        try send(eof.bytes)
        var closeMessage = SshWriter()
        closeMessage.byte(97)
        closeMessage.uint32(clientChannel)
        try send(closeMessage.bytes)
        guard try next().first == 97 else { throw FakeError(description: "CHANNEL_CLOSE beklenirdi") }
        return uploaded
    }

    private func channelData(_ channel: UInt32, _ text: String) -> [UInt8] {
        var data = SshWriter()
        data.byte(94)
        data.uint32(channel)
        data.string(text)
        return data.bytes
    }

    // MARK: Anahtar değişimi (sunucu tarafı)

    private func exchange() throws {
        var kexInit = SshWriter()
        kexInit.byte(20)
        kexInit.bytes += [UInt8](repeating: 7, count: 16)
        kexInit.nameList(["curve25519-sha256"])
        kexInit.nameList(["ssh-ed25519"])
        kexInit.nameList(["aes128-ctr"])
        kexInit.nameList(["aes128-ctr"])
        kexInit.nameList(["hmac-sha2-256"])
        kexInit.nameList(["hmac-sha2-256"])
        kexInit.nameList(["none"])
        kexInit.nameList(["none"])
        kexInit.nameList([])
        kexInit.nameList([])
        kexInit.bool(false)
        kexInit.uint32(0)
        let serverInit = kexInit.bytes
        try send(serverInit)

        // İstemcinin KEXINIT'ine kadar gelen diğer iletiler (eski anahtarla) saklanır.
        var clientInit = try readPacket()
        while clientInit.first != 20 {
            held.append(clientInit)
            clientInit = try readPacket()
        }
        var ecdh = SshReader(try readPacket())
        guard try ecdh.byte() == 30 else { throw FakeError(description: "KEX_ECDH_INIT beklenirdi") }
        let clientPublic = try ecdh.string()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let serverPublic = Array(ephemeral.publicKey.rawRepresentation)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: clientPublic))
            .withUnsafeBytes { Array($0) }

        var blob = SshWriter()
        blob.string("ssh-ed25519")
        blob.string(Array(hostKey.publicKey.rawRepresentation))
        var hashInput = SshWriter()
        hashInput.string(clientVersion)
        hashInput.string(serverVersion)
        hashInput.string(clientInit)
        hashInput.string(serverInit)
        hashInput.string(blob.bytes)
        hashInput.string(clientPublic)
        hashInput.string(serverPublic)
        hashInput.mpint(shared)
        let hash = Array(SHA256.hash(data: hashInput.bytes))
        var signature = SshWriter()
        signature.string("ssh-ed25519")
        signature.string(Array(try hostKey.signature(for: hash)))
        var reply = SshWriter()
        reply.byte(31)
        reply.string(blob.bytes)
        reply.string(serverPublic)
        reply.string(signature.bytes)
        try send(reply.bytes)
        try send([21])
        if sessionId.isEmpty { sessionId = hash }

        var sharedMpint = SshWriter()
        sharedMpint.mpint(shared)
        func derive(_ letter: Character, _ length: Int) -> [UInt8] {
            Array(SHA256.hash(data: sharedMpint.bytes + hash + [letter.asciiValue!] + sessionId)).prefix(length).map { $0 }
        }
        outgoing.cipher = Ctr(key: derive("D", 16), iv: derive("B", 16))
        outgoing.macKey = derive("F", 32)

        // İstemcinin NEWKEYS'i eski anahtarla gelir; ondan sonrası yenileriyle.
        var newKeys = try readPacket()
        while newKeys.first != 21 {
            guard !(30...49).contains(newKeys.first ?? 0) else { throw FakeError(description: "beklenmeyen KEX iletisi") }
            held.append(newKeys)
            newKeys = try readPacket()
        }
        incoming.cipher = Ctr(key: derive("C", 16), iv: derive("A", 16))
        incoming.macKey = derive("E", 32)
        exchanges += 1
    }

    // MARK: Paketler

    private func next() throws -> [UInt8] {
        if !held.isEmpty { return held.removeFirst() }
        return try readPacket()
    }

    private func send(_ payload: [UInt8]) throws {
        let block = outgoing.cipher == nil ? 8 : 16
        var padding = block - (5 + payload.count) % block
        if padding < 4 { padding += block }
        var plain = SshWriter()
        plain.uint32(UInt32(1 + payload.count + padding))
        plain.byte(UInt8(padding))
        plain.bytes += payload + [UInt8](repeating: 0, count: padding)
        var wire = outgoing.cipher?.apply(plain.bytes) ?? plain.bytes
        if outgoing.cipher != nil {
            var sequence = SshWriter()
            sequence.uint32(outgoing.sequence)
            wire += Array(HMAC<SHA256>.authenticationCode(for: sequence.bytes + plain.bytes, using: SymmetricKey(data: outgoing.macKey)))
        }
        outgoing.sequence &+= 1
        try write(wire)
    }

    private func readPacket() throws -> [UInt8] {
        let block = incoming.cipher == nil ? 8 : 16
        var plain = try readExactly(block)
        plain = incoming.cipher?.apply(plain) ?? plain
        var lengthReader = SshReader(plain)
        let length = Int(try lengthReader.uint32())
        guard length >= 5, length < 1_000_000 else { throw FakeError(description: "bozuk uzunluk \(length)") }
        let rest = try readExactly(4 + length - block)
        plain += incoming.cipher?.apply(rest) ?? rest
        if incoming.cipher != nil {
            var sequence = SshWriter()
            sequence.uint32(incoming.sequence)
            let expected = Array(HMAC<SHA256>.authenticationCode(for: sequence.bytes + plain, using: SymmetricKey(data: incoming.macKey)))
            guard try readExactly(32) == expected else { throw FakeError(description: "MAC tutmadı") }
        }
        incoming.sequence &+= 1
        let padding = Int(plain[4])
        return Array(plain[5..<(plain.count - padding)])
    }

    private func readExactly(_ count: Int) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let got = result.withUnsafeMutableBytes { recv(fd, $0.baseAddress! + offset, count - offset, 0) }
            guard got > 0 else { throw FakeError(description: "bağlantı kapandı") }
            offset += got
        }
        return result
    }

    private func write(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let sent = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress! + offset, bytes.count - offset, 0) }
            guard sent > 0 else { throw FakeError(description: "yazılamadı") }
            offset += sent
        }
    }
}
