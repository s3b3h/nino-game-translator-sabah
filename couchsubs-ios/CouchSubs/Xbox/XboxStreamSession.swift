// SPDX-License-Identifier: AGPL-3.0-only
// Xbox ev yayını (Beta): Windows'taki XboxStreamSession + player.html'in iPhone karşılığı (Android: XboxStreamSession.kt).
// Görüntü yerel WebRTC'yle (stasel/WebRTC) alınır; VideoToolbox'ın verdiği kare CGImage olarak okuma hattına gider.
// Oyun sesi ayar açıksa ("Play Xbox sound on this device", varsayılan açık) telefonda çalınır: Xbox uzaktan oynatma
// sürerken sesi istemciye verip TV'yi susturabilir. Yerel ses parçası eklenmez, Xbox'a ses gönderilmez. Ayar kapalıyken
// eski davranış: WebRTC ses birimi hiç başlatılmaz. Kumanda girdisi gönderilmez.

import AVFoundation
import CoreGraphics
import Foundation
import RemotePlay
import VideoToolbox
import WebRTC

final class XboxStreamSession: NSObject, StreamControlling, @unchecked Sendable {
    var onFrame: ((CGImage) -> Void)?
    var onState: ((SessionState) -> Void)?
    var onConsoleMoved: ((RegisteredConsole) -> Void)?

    private static let iceGatherMs = 5000
    private static let keepaliveSeconds: UInt64 = 30
    private static let firstFrameSeconds: TimeInterval = 20
    /// Okuma saniyede birkaç kez yapılır; her kareyi CGImage'a çevirmeye gerek yok.
    private static let frameInterval: TimeInterval = 0.066
    /// Kare onayları oynatıcıdaki gibi 16 ms'de bir paketlenir (Input.ts `_inputInterval`).
    private static let ackIntervalNs: UInt64 = 16_000_000

    private let auth: XboxAuth
    private let console: XboxConsole
    private let home: XboxHome
    private let describe: (XboxErrorKind) -> String
    private let lock = NSLock()
    private var machine = XboxSessionMachine()
    private var task: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private var peer: RTCPeerConnection?
    private var channels: [String: RTCDataChannel] = [:]
    private var channelDelegates: [ChannelDelegate] = []
    private var localCandidates: [XboxIceCandidate] = []
    private var gatheringComplete = false
    private var endReason: String?
    private var sessionId: String?
    private var lastConverted: TimeInterval = 0
    private(set) var framesReceived = 0
    /// Kare onayı (Windows'taki xbox-xcloud-player her gösterilen karede yapar): Xbox onay gelmeyen yayını kısa sürede
    /// kapatır (Greenlight wiki, WebRTC: "Without sending any data back the stream will only last for +- 40 seconds").
    private var pendingAcks: [XboxFrameAck] = []
    private var acking = false
    private var ackSequence: UInt32 = 0
    private var acksSent = 0
    private var ackTask: Task<Void, Never>?
    /// Onay paketlerindeki anların sıfırı (oynatıcıdaki performance.now() gibi).
    private var clockStart: TimeInterval = 0
    private var firstFrameAt: TimeInterval = 0

    /// Oyun sesi bu telefonda çalınır (Android'deki `playAudio` ile aynı).
    private let playAudio: Bool

    init(auth: XboxAuth, console: XboxConsole, playAudio: Bool = true, describe: @escaping (XboxErrorKind) -> String) {
        self.auth = auth
        self.console = console
        self.home = XboxHome(auth: auth)
        self.playAudio = playAudio
        self.describe = describe
    }

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        // Ses birimi elle açılır: ayar kapalıyken hiç başlatılmaz (bkz. `setAudio`).
        let audio = RTCAudioSession.sharedInstance()
        audio.useManualAudio = true
        audio.isAudioEnabled = false
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    }()

    /// Oyun sesini açar ya da kapatır. Ses hoparlörden (ya da bağlı kulaklıktan) medya sesi gibi çalınır; WebRTC'nin
    /// varsayılan görüşme ayarı (voiceChat) sesi kulaklık hoparlörüne verirdi. Yerel ses parçası olmadığından
    /// mikrofondan Xbox'a hiçbir şey gönderilmez.
    private static func setAudio(_ enabled: Bool) {
        let session = RTCAudioSession.sharedInstance()
        if enabled {
            let config = RTCAudioSessionConfiguration.webRTC()
            config.category = AVAudioSession.Category.playAndRecord.rawValue
            config.categoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP]
            config.mode = AVAudioSession.Mode.default.rawValue
            RTCAudioSessionConfiguration.setWebRTC(config)
        }
        session.isAudioEnabled = enabled
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func log(_ text: String) { RemotePlayLog.write("Xbox: \(text)") }

    func start() {
        guard task == nil else { return }
        task = Task.detached(priority: .userInitiated) { [weak self] in await self?.run() }
    }

    func stop() {
        locked { machine.stop() }
        task?.cancel()
        task = nil
        Task.detached { [weak self] in
            await self?.teardown()
        }
        onState?(.disconnected(.stopped))
    }

    /// Uygulama öne gelince: süren el sıkışma ya da bağlantı kapatılıp baştan açılır.
    func reconnectNow() {
        locked { if endReason == nil { endReason = "Yeniden bağlanılıyor" } }
    }

    private var stopped: Bool { locked { machine.phase == .stopped } }

    private func run() async {
        log("konsol: \(console.name)")
        while !Task.isCancelled && !stopped {
            var action = locked { machine.start() }
            // Makine `/state` yanıtında kendisi karar verdiyse (Failed, errorDetails) aynı hata yeniden sayılmaz.
            var decided: XboxSessionMachine.Action?
            onState?(.connecting)
            do {
                log("oturum açılıyor: \(console.name)")
                let id = try await home.play(consoleId: console.id)
                log("play yanıtı: oturum \(id.prefix(8))…")
                locked { sessionId = id }
                action = locked { machine.played() }
                loop: while !Task.isCancelled {
                    switch action {
                    case let .pollState(delay):
                        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000) }
                        let status = try await home.state(id)
                        if status.state != "Provisioning" { log("durum: \(status.state)") }
                        if let details = status.errorDetails { log("errorDetails: \(details)") }
                        action = locked { machine.status(status.state, errorDetails: status.errorDetails) }
                    case .connect:
                        try await home.connect(id)
                        log("connect: başarılı")
                        action = locked { machine.connected() }
                    case .negotiate:
                        try await negotiate(id)
                        break loop
                    case .retry:
                        decided = action
                        if case let .failed(kind, message, _, _) = locked({ machine.phase }) { throw XboxError(kind, message) }
                        throw XboxError(.service, "Xbox")
                    case .play, .nothing:
                        break loop
                    }
                }
                if !Task.isCancelled && !stopped { throw XboxError(.network, locked { endReason } ?? "Xbox görüntü bağlantısı kapandı") }
            } catch is CancellationError {
            } catch let error as XboxError {
                action = decided ?? locked { machine.fail(error.kind, error.message) }
                report(error.kind, error.message)
            } catch {
                action = locked { machine.fail(.service, error.localizedDescription) }
                report(.service, error.localizedDescription)
            }
            summarize()
            await teardown()
            guard !Task.isCancelled, !stopped, case let .retry(delay?) = action else { break }
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
        }
    }

    /// Bağlantı bitince: kaç kare geldi, kaç onay gitti, ilk kareden kaç saniye sonra ve neden bitti.
    private func summarize() {
        let (frames, sent, first, reason, error) = locked { (framesReceived, acksSent, firstFrameAt, endReason, lastError) }
        guard frames > 0 || reason != nil || error != nil else { return }
        let lived = first > 0 ? "\(Int(ProcessInfo.processInfo.systemUptime - first)) sn" : "ilk kare yok"
        log("bağlantı bitti: \(reason ?? error ?? "durduruldu"); kare \(frames), onay \(sent), ilk kareden sonra \(lived)")
    }

    private var lastError: String?

    private func report(_ kind: XboxErrorKind, _ detail: String) {
        locked { lastError = "\(kind.rawValue): \(detail)" }
        guard !stopped else { return }
        log("kopma (\(kind.rawValue)): \(detail)")
        let (phase, delays) = locked { (machine.phase, machine.retryDelaysMs) }
        if case let .failed(_, _, true, attempt) = phase, attempt > 0 {
            log("yeniden deneme \(attempt)/\(delays.count): \(delays[attempt - 1] / 1000) sn sonra")
        } else if case .failed = phase, !XboxSessionMachine.fatal.contains(kind) {
            // Denemeler bitti ya da konsol yayını reddetti: yayın durur, yeniden denenmez.
            log("yeniden denenmiyor, yayın durdu")
            let reason = detail.trimmingCharacters(in: .whitespaces).isEmpty ? kind.rawValue : detail
            onState?(.disconnected(.other(String(format: String(localized: "The Xbox connection was lost: %@. Restart the Xbox to reconnect."), reason))))
            return
        }
        onState?(.disconnected(.other(describe(kind))))
    }

    private func teardown() async {
        keepaliveTask?.cancel()
        ackTask?.cancel()
        ackTask = nil
        locked {
            acking = false
            pendingAcks = []
        }
        let (peer, channels, id) = locked { () -> (RTCPeerConnection?, [RTCDataChannel], String?) in
            let result = (self.peer, Array(self.channels.values), self.sessionId)
            self.peer = nil
            self.channels = [:]
            self.channelDelegates = []
            self.sessionId = nil
            return result
        }
        channels.forEach { $0.delegate = nil; $0.close() }
        peer?.close()
        Self.setAudio(false)
        if let id { try? await home.stop(id) }
    }

    // MARK: - WebRTC

    private func negotiate(_ id: String) async throws {
        locked {
            endReason = nil
            localCandidates = []
            gatheringComplete = false
            framesReceived = 0
            firstFrameAt = 0
            lastError = nil
            acking = false
            pendingAcks = []
            ackSequence = 0
            acksSent = 0
            clockStart = ProcessInfo.processInfo.systemUptime
        }
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]), RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let connection = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw XboxError(.service, "WebRTC bağlantısı kurulamadı")
        }
        locked { peer = connection }
        // Oynatıcıdaki sıra: önce veri kanalları, sonra ses (gönder-al) ve görüntü (yalnız al).
        for (name, proto) in XboxChannels.channels {
            let channelConfig = RTCDataChannelConfiguration()
            channelConfig.isOrdered = true
            channelConfig.`protocol` = proto
            guard let channel = connection.dataChannel(forLabel: name, configuration: channelConfig) else {
                throw XboxError(.service, "Veri kanalı açılamadı: \(name)")
            }
            let delegate = ChannelDelegate(name: name, owner: self)
            channel.delegate = delegate
            locked {
                channels[name] = channel
                channelDelegates.append(delegate)
            }
        }
        let audioInit = RTCRtpTransceiverInit()
        audioInit.direction = .sendRecv
        let videoInit = RTCRtpTransceiverInit()
        videoInit.direction = .recvOnly
        let audio = connection.addTransceiver(of: .audio, init: audioInit)
        let video = connection.addTransceiver(of: .video, init: videoInit)
        audio?.receiver.track?.isEnabled = playAudio
        Self.setAudio(playAudio)
        log(playAudio ? "oyun sesi bu telefonda çalınır" : "oyun sesi kapalı (ayar)")
        guard let track = video?.receiver.track as? RTCVideoTrack else { throw XboxError(.service, "Görüntü alıcısı kurulamadı") }
        track.add(self)

        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            connection.offer(for: constraints) { description, error in
                if let description { continuation.resume(returning: description) }
                else { continuation.resume(throwing: XboxError(.service, "SDP teklifi: \(error?.localizedDescription ?? "?")")) }
            }
        }
        let munged = RTCSessionDescription(type: .offer, sdp: XboxChannels.mungeOffer(offer.sdp))
        try await set(connection, local: munged)
        log("SDP gönderiliyor")
        let answer = try await home.sdp(id, offer: munged.sdp)
        try await set(connection, remote: RTCSessionDescription(type: .answer, sdp: answer))
        // Yerel adaylar toplanana kadar (en çok 5 sn) beklenir.
        for _ in 0..<(Self.iceGatherMs / 100) where !locked({ gatheringComplete }) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let candidates = locked { localCandidates }
        log("ICE: \(candidates.count) yerel aday gönderiliyor")
        let remote = try await home.ice(id, candidates: candidates)
        var added = 0
        for candidate in remote {
            guard let line = candidate.sdpLine else { continue }
            let ice = RTCIceCandidate(sdp: line, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid)
            let ok: Bool = await withCheckedContinuation { continuation in
                connection.add(ice) { error in continuation.resume(returning: error == nil) }
            }
            if ok { added += 1 }
        }
        log("ICE: Xbox'tan \(remote.count) aday, \(added) eklendi")

        let negotiatedAt = Date()
        while !Task.isCancelled && !stopped {
            if locked({ endReason }) != nil { return }
            if locked({ framesReceived }) == 0 && Date().timeIntervalSince(negotiatedAt) > Self.firstFrameSeconds {
                throw XboxError(.consoleUnavailable, "Xbox'tan \(Int(Self.firstFrameSeconds)) sn içinde görüntü gelmedi")
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func set(_ connection: RTCPeerConnection, local: RTCSessionDescription? = nil, remote: RTCSessionDescription? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let done: (Error?) -> Void = { error in
                if let error { continuation.resume(throwing: XboxError(.service, "SDP: \(error.localizedDescription)")) }
                else { continuation.resume() }
            }
            if let local { connection.setLocalDescription(local, completionHandler: done) }
            else if let remote { connection.setRemoteDescription(remote, completionHandler: done) }
        }
    }

    fileprivate func channelChanged(_ name: String, _ channel: RTCDataChannel) {
        log("kanal \(name): \(channel.readyState.rawValue)")
        switch (name, channel.readyState) {
        case ("message", .open): send("message", Data(XboxChannels.handshake.utf8), binary: false)
        case ("input", .open): startKeepalive()
        case ("input", .closed): locked { if endReason == nil { endReason = "Xbox görüntü bağlantısı kapandı" } }
        default: break
        }
    }

    fileprivate func channelMessage(_ name: String, _ buffer: RTCDataBuffer) {
        if buffer.isBinary {
            // input kanalından gelenler: 16 = ServerMetadata, 128 = titreşim (her an gelir, yazılmaz).
            let type = buffer.data.first.map { Int($0) } ?? -1
            if type != 128 { log("kanal \(name): ikili ileti, tür \(type), \(buffer.data.count) bayt") }
            return
        }
        let text = String(decoding: buffer.data, as: UTF8.self)
        guard name == "message", XboxChannels.isHandshakeAck(text) else {
            // Xbox'ın kapatma bildirimi gibi iletiler (ör. TransactionStart) burada görünür.
            log("kanal \(name): \(text.prefix(300))")
            return
        }
        log("el sıkışma tamam")
        send("control", Data(XboxChannels.authorization.utf8), binary: false)
        send("control", Data(XboxChannels.gamepadAdded.utf8), binary: false)
        send("input", XboxChannels.clientMetadataPacket(timestampMs: sessionMs()), binary: true)
        XboxChannels.configurationMessages().forEach { send("message", Data($0.utf8), binary: false) }
        startAcks()
    }

    private func sessionMs(_ at: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
        (at - locked { clockStart }) * 1000
    }

    /// El sıkışmadan sonra gösterilen karelerin onayı 16 ms'de bir `input` kanalına gider (oynatıcıdaki döngü).
    private func startAcks() {
        ackTask?.cancel()
        locked {
            pendingAcks = []
            acking = true
        }
        ackTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.ackIntervalNs)
                guard let self, !Task.isCancelled else { return }
                let batch = self.locked { () -> (frames: [XboxFrameAck], sequence: UInt32)? in
                    guard self.acking, !self.pendingAcks.isEmpty else { return nil }
                    let frames = Array(self.pendingAcks.prefix(XboxChannels.maxFrameAcks))
                    self.pendingAcks.removeFirst(frames.count)
                    self.ackSequence &+= 1
                    self.acksSent += frames.count
                    return (frames, self.ackSequence)
                }
                guard let batch else { continue }
                self.send("input", XboxChannels.frameAckPacket(sequence: batch.sequence, timestampMs: self.sessionMs(), frames: batch.frames), binary: true)
                if batch.sequence == 1 { self.log("kare onayı başladı") }
            }
        }
    }

    private func send(_ name: String, _ data: Data, binary: Bool) {
        guard let channel = locked({ channels[name] }), channel.readyState == .open else { return }
        channel.sendData(RTCDataBuffer(data: data, isBinary: binary))
    }

    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.keepaliveSeconds * 1_000_000_000)
                guard let self, !Task.isCancelled, let id = self.locked({ self.sessionId }) else { return }
                do { try await self.home.keepalive(id) } catch { self.log("canlı tutma: \(error)") }
            }
        }
    }
}

// MARK: - Kareler

extension XboxStreamSession: RTCVideoRenderer {
    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let (count, due) = locked { () -> (Int, Bool) in
            framesReceived += 1
            if framesReceived == 1 { firstFrameAt = now }
            let due = now - lastConverted >= Self.frameInterval
            if due { lastConverted = now }
            if acking {
                // timeStamp: karenin RTP zaman damgası (90 kHz), oynatıcıdaki serverDataKey (rtpTimestamp).
                let at = (now - clockStart) * 1000
                if pendingAcks.count >= 600 { pendingAcks.removeFirst() }
                pendingAcks.append(XboxFrameAck(serverDataKey: UInt32(bitPattern: frame.timeStamp), arrivalMs: at, decodedMs: at))
            }
            return (framesReceived, due)
        }
        if count == 1 {
            log("ilk kare \(frame.width)x\(frame.height)")
            if locked({ machine.streaming() }) { onState?(.streaming) }
        }
        guard due, let image = Self.image(from: frame.buffer) else { return }
        onFrame?(image)
    }

    /// VideoToolbox karesi doğrudan CGImage olur; yazılım çözücüsünün I420 karesinden gri (Y düzlemi) resim.
    static func image(from buffer: RTCVideoFrameBuffer) -> CGImage? {
        if let pixel = buffer as? RTCCVPixelBuffer {
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(pixel.pixelBuffer, options: nil, imageOut: &image)
            return image
        }
        let i420 = buffer.toI420()
        let width = Int(i420.width), height = Int(i420.height), stride = Int(i420.strideY)
        let data = Data(bytes: i420.dataY, count: stride * height)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: stride,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

// MARK: - Bağlantı olayları

extension XboxStreamSession: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        log("ICE: \(newState.rawValue)")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState == .complete { locked { gatheringComplete = true } }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        locked { localCandidates.append(XboxIceCandidate(candidate: candidate.sdp, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex)) }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        log("bağlantı: \(newState.rawValue)")
        if newState == .failed || newState == .closed {
            locked { if endReason == nil { endReason = "Xbox WebRTC bağlantısı kesildi" } }
        }
    }
}

private final class ChannelDelegate: NSObject, RTCDataChannelDelegate {
    let name: String
    weak var owner: XboxStreamSession?
    init(name: String, owner: XboxStreamSession) {
        self.name = name
        self.owner = owner
    }
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) { owner?.channelChanged(name, dataChannel) }
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) { owner?.channelMessage(name, buffer) }
}
