// SPDX-License-Identifier: AGPL-3.0-only

import CChiaki
import CoreGraphics
import Foundation

/// Saniyede en fazla belirli sayıda karenin geçmesine izin verir.
struct FrameThrottle {
    let minInterval: TimeInterval
    let now: () -> Date
    private var last: Date?

    init(minInterval: TimeInterval, now: @escaping () -> Date = Date.init) {
        self.minInterval = minInterval
        self.now = now
    }

    mutating func shouldPass() -> Bool {
        let current = now()
        if let last, current.timeIntervalSince(last) < minInterval { return false }
        last = current
        return true
    }
}

/// Bağlantı koptuğunda yeniden deneme aralıkları: 2, 4, 8, 16, en çok 30 sn.
///
/// Aralık bağlanınca hemen değil, oturum `stableAfter` kadar sürdükten sonra kapanınca baştan başlar. Eskiden her
/// bağlanışta sıfırlanıyordu: PS5 oturumu açılıp birkaç saniyede düşürünce (ör. aynı ikinci hesapla bağlı başka bir
/// cihaz) telefon 2 sn sonra yeniden bağlanıyor, PS5'te ikinci hesap durmadan girip çıkıyordu.
struct ReconnectPolicy {
    static let stableAfter: TimeInterval = 60
    private var attempt = 0
    private var connectedAt: Date?

    /// `inUse`: Uzaktan Oynatma başka cihazda; sık denemek boşuna, en az 8 sn beklenir (8, 16, 30). Hemen en uzuna
    /// atlanmaz: telefonun kendi eski oturumu PS5'te birkaç saniye daha açık görünebilir.
    mutating func nextDelay(inUse: Bool = false) -> Int {
        if inUse { attempt = max(attempt, 2) }
        defer { attempt = min(attempt + 1, 5) }
        return min(30, 2 << attempt)
    }

    mutating func reset() {
        attempt = 0
        connectedAt = nil
    }

    mutating func connected(at now: Date = Date()) { connectedAt = now }

    /// Oturum kapandı: uzun sürdüyse aralık baştan başlar, kısa sürdüyse büyümeye devam eder.
    mutating func ended(at now: Date = Date()) {
        if let connectedAt, now.timeIntervalSince(connectedAt) >= Self.stableAfter { attempt = 0 }
        connectedAt = nil
    }
}

/// Bağlı oturumda PS5'ten görüntü gelmiyor mu (Windows'taki PictureWatchdog ve Android'deki eşi ile aynı kural).
///
/// libchiaki bir karenin FEC onarımı tutmayınca PS5'ten bir kez yeni anahtar kare (IDR) ister ve o gelene kadar bütün
/// kareleri atlar (`enable_idr_on_fec_failure`). İstenen IDR karesinin kendisi de bozuk gelirse yeniden istemez
/// ("Video FEC failure, already waiting for requested IDR"): bağlantı açık kalır, ama bir daha hiç kare gelmez. Kablosuz
/// ağda bu birkaç dakikada bir olur; altyazı duruyor, TV bağlı görünüyor ve ancak uygulamayı kapatıp açmak düzeltiyordu.
/// Bağlıyken `stallAfter` boyunca hiç görüntü gelmezse oturum yeniden kurulur; yeni oturum anahtar kareyle başlar.
struct PictureWatchdog {
    /// IDR ile olağan toparlanma bir saniyeden kısa sürer; bundan uzun boşluk takılmadır.
    static let stallAfter: TimeInterval = 8
    /// Yeniden bağlanırken ana ekranda "Yeniden bağlanılıyor… (…)" içinde görünen neden.
    static let reason = "no picture from the PS5"
    /// Art arda bu kadar oturumda hiç görüntü gelmezse yeniden bağlanma bırakılır (Android'deki eşi ile aynı).
    static let maxNoPictureSessions = 3

    /// Takılma sonrası ne yapılacak.
    enum Next: Equatable {
        /// Yeniden kur.
        case reconnect
        /// Art arda `maxNoPictureSessions` oturumda hiç görüntü gelmedi: sonsuz "Yeniden bağlanılıyor…" yerine dur.
        case giveUp
    }

    /// Bağlıyken son görüntünün (ya da bağlanmanın) anı; bağlı değilken nil.
    private var since: Date?
    /// Bu oturumda görüntü geldi mi.
    private var hasPicture = false
    /// Art arda hiç görüntü gelmeyen oturum sayısı; görüntü gelince sıfırlanır.
    private(set) var noPictureSessions = 0

    /// Kullanıcı başlattı ya da ağ değişti: sayaç sıfırdan.
    mutating func reset() {
        since = nil
        hasPicture = false
        noPictureSessions = 0
    }

    /// Oturum bağlandı: süre bağlanma anından sayılır (ilk kare hiç gelmezse de yakalanır).
    mutating func connected(at now: Date = Date()) {
        since = now
        hasPicture = false
    }

    /// Görüntü geldi.
    mutating func picture(at now: Date = Date()) {
        guard since != nil else { return }
        since = now
        hasPicture = true
        noPictureSessions = 0
    }

    /// `stalled` boşluk bildirdi; oturum kapatılırken ne yapılacağı.
    mutating func afterStall() -> Next {
        if hasPicture { return .reconnect }
        noPictureSessions += 1
        return noPictureSessions >= Self.maxNoPictureSessions ? .giveUp : .reconnect
    }

    /// Oturum kapandı ya da yeniden kuruluyor.
    mutating func ended() { since = nil }

    /// Bağlıyken `stallAfter`'dan uzun süredir görüntü yoksa boşluğun süresi (sn); yoksa nil.
    func stalled(at now: Date = Date()) -> TimeInterval? {
        guard let since else { return nil }
        let gap = now.timeIntervalSince(since)
        return gap >= Self.stallAfter ? gap : nil
    }
}

/// Bağlantının neden koptuğu; kullanıcıya anlatılabilecek biçimde.
public enum DisconnectReason: Equatable, Sendable {
    case stopped
    /// PS5 kapalı ya da uyandırılamadı.
    case consoleAsleep
    /// Remote Play başka bir cihazda kullanılıyor.
    case inUse
    /// PS5 bağlantıyı reddetti (ör. kayıt geçersiz ya da Uzaktan Oynatma kapalı).
    case refused
    case network
    /// İkinci kullanıcının PS5'te giriş şifresi var ve Ayarlar'da kayıtlı şifre yok.
    case loginPasscode
    /// Ayarlar'daki giriş şifresini PS5 kabul etmedi. Yeniden gönderilmez (yanlış şifreyle döngüye girilmez).
    case loginPasscodeIncorrect
    /// PS5 oturum isteğinde kaydı kabul etmedi (0x80108b09 kayıt geçersiz, 0x80108b02 hesap tanınmıyor). Yeniden denemek
    /// aynı yere çıkar; PS5 ikinci hesapla yeniden eşlenmelidir.
    case registrationInvalid
    /// PS5'te Uzaktan Oynama kapalı (0x80108b12): eşleme durur ama PS5 oturum açmaz. Kullanıcı PS5'te Ayarlar › Sistem ›
    /// Uzaktan Oynama'dan açmalıdır; yeniden denemek aynı yere çıkar (CouchSubs #9'da kullanıcı doğruladı).
    case remotePlayDisabled
    /// Bağlantı kuruluyor ama art arda `PictureWatchdog.maxNoPictureSessions` oturumda PS5'ten hiç görüntü gelmedi;
    /// yeniden bağlanma bırakıldı (eskiden sonsuza kadar "Yeniden bağlanılıyor…").
    case noPicture
    /// Kayıtlı adreste PS5 aramaya yanıt vermedi ve oturum da açılamadı (değer: adres).
    case notFound(String)
    /// PS5 oturum isteğini (TCP 9295) kayıt dışı bir nedenle reddetti ya da yanıtı okunamadı; libchiaki bunu yalnız
    /// "Unknown Session Request Error" diye verir (GitHub #33, #202). Değer: PS5'in "Reported Application Reason" kodu
    /// (libchiaki'nin tanımadığı kodlar, ör. 0x80108bff; günlükte kod yoksa nil).
    case rejected(UInt32?)
    case other(String)

    /// Oturum ağ hatasıyla düştüyse ve PS5 aramaya da yanıt vermediyse neden "bulunamadı"dır (eskiden yalnız
    /// "Yeniden bağlanılıyor…" görünüyordu).
    static func classify(_ reason: DisconnectReason, searchAnswered: Bool, host: String) -> DisconnectReason {
        guard !searchAnswered else { return reason }
        switch reason {
        // Kayıtlı adres bilinmiyorsa (0.0.0.0, boş) "PS5 0.0.0.0 adresinde bulunamadı" denmez.
        case .network, .other: return ConsoleAddress.isUsable(host) ? .notFound(host) : .network
        default: return reason
        }
    }

    /// libchiaki oturum isteği (TCP 9295) düşünce yalnız "Unknown Session Request Error" der; asıl neden aynı iş
    /// parçacığının az önce yazdığı günlük satırındadır. Satırdan anlaşılan neden; anlaşılmıyorsa nil (genel metin
    /// kalır, PS5'in kodu zaten "Reported Application Reason" satırıyla remoteplay.log'dadır).
    static func sessionRequestHint(fromLog line: String) -> DisconnectReason? {
        if let marker = line.range(of: "Reported Application Reason:") {
            let token = line[marker.upperBound...].drop { $0 == " " }.prefix { !$0.isWhitespace }.lowercased()
            let hex = token.hasPrefix("0x") ? String(token.dropFirst(2)) : token
            guard let code = UInt32(hex, radix: 16) else { return nil }
            if code == remotePlayDisabledCode { return .remotePlayDisabled }
            return registrationRejectedCodes.contains(code) ? .registrationInvalid : .rejected(code)
        }
        // PS5'e bağlanılamadı ya da yanıt gelmedi: PS5 dinlenmeden yeni uyandıysa ilk denemelerde olağandır.
        return unreachableLines.contains(where: line.contains) ? .network : nil
    }

    /// CHIAKI_RP_APPLICATION_REASON_REGIST_FAILED ve _INVALID_PSN_ID; 0x80108b26: PS5 eşleme anahtarını kendi kayıtlarında
    /// bulamadı (eşleme PS5'te silinmiş ya da başka hesapla yapılmış). libchiaki bu kodu tanımaz; yeniden başlatmak
    /// düzeltmez, PS5 yeniden eşlenmelidir (panelde 9 bildirim, 19 Kasım 2026).
    static let registrationRejectedCodes: Set<UInt32> = [0x80108b09, 0x80108b02, 0x80108b26]
    /// PS5'te Uzaktan Oynama kapalıyken dönen kod.
    static let remotePlayDisabledCode: UInt32 = 0x80108b12
    private static let unreachableLines = [
        "Session request connect failed eventually",
        "Failed to send session request",
        "Failed to receive session request response",
    ]

    /// Oturum isteği bilinmeyen nedenle düştüyse günlükten anlaşılan neden kullanılır. Günlükte neden yoksa (PS5'in
    /// yanıtı okunamadı) PS5 oturumu başlatmamıştır: anlamsız İngilizce metin yerine `.rejected(nil)`.
    init(quit: ChiakiQuitReason, sessionRequestHint hint: DisconnectReason?) {
        if quit == CHIAKI_QUIT_REASON_SESSION_REQUEST_UNKNOWN {
            self = hint ?? .rejected(nil)
        } else {
            self.init(quit: quit)
        }
    }

    init(quit: ChiakiQuitReason) {
        switch quit {
        case CHIAKI_QUIT_REASON_STOPPED: self = .stopped
        case CHIAKI_QUIT_REASON_SESSION_REQUEST_RP_IN_USE: self = .inUse
        case CHIAKI_QUIT_REASON_SESSION_REQUEST_CONNECTION_REFUSED, CHIAKI_QUIT_REASON_CTRL_CONNECTION_REFUSED,
             CHIAKI_QUIT_REASON_PSN_REGIST_FAILED: self = .refused
        case CHIAKI_QUIT_REASON_STREAM_CONNECTION_REMOTE_DISCONNECTED, CHIAKI_QUIT_REASON_STREAM_CONNECTION_REMOTE_SHUTDOWN,
             CHIAKI_QUIT_REASON_CTRL_CONNECT_FAILED, CHIAKI_QUIT_REASON_STREAM_CONNECTION_UNKNOWN: self = .network
        default: self = .other(String(cString: chiaki_quit_reason_string(quit)))
        }
    }
}

/// PS5 oturum giriş şifresi (4 hane). PS5 ikinci hesapta şifre isterse Ayarlar'da kayıtlı şifre gönderilir.
public enum LoginPasscode {
    public static let length = 4

    /// Boşlukları atar; tam 4 rakam değilse nil.
    public static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.count == length, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return trimmed
    }

    /// Şifre isteğine ne yapılacağı: kayıtlı geçerli şifre varsa ilk istekte gönderilir (libchiaki rakamları ASCII
    /// olarak bekler, chiaki-ng'deki gibi). Şifre yoksa ya da PS5 önceki şifreyi kabul etmediyse oturum kapatılır.
    public enum Reply: Equatable, Sendable {
        case send(Data)
        case stop(DisconnectReason)
    }

    public static func reply(saved: String?, incorrect: Bool) -> Reply {
        if incorrect { return .stop(.loginPasscodeIncorrect) }
        guard let pin = normalized(saved) else { return .stop(.loginPasscode) }
        return .send(Data(pin.utf8))
    }
}

public enum SessionState: Equatable, Sendable {
    case connecting
    case streaming
    case disconnected(DisconnectReason)
}

/// Tek bir libchiaki oturumunun sahibi. Geri çağrılar bu kutuya gelir; kutu, oturum kapatılıp
/// iş parçacığı beklenene (join) kadar yaşar, böylece geri çağrı serbest bırakılmış belleğe düşmez.
///
/// Oturumun günlüğü de kutunundur: libchiaki `ChiakiLog`'un yalnız adresini tutar ve iş parçacığı kapanırken bile
/// günlüğe yazar. Günlük eskiden `StreamSession`'daydı; "Çeviriyi durdur"da `StreamSession` hemen bırakılıyor, oturum
/// ise arka planda kapatılıyordu. Kapanan iş parçacığı serbest kalmış günlüğe yazınca uygulama çöküyordu
/// (EXC_BAD_ACCESS, chiaki_log ← chiaki_stream_connection_run; GitHub #21).
final class ChiakiSessionBox {
    let pointer = UnsafeMutablePointer<ChiakiSession>.allocate(capacity: 1)
    let logger = ChiakiLogger()
    let generation: Int
    weak var owner: StreamSession?
    private var torn = false
    private let lock = NSLock()
    /// Oturum isteğinin günlükten anlaşılan düşme nedeni. Ayrı kilit: `tearDown` join ederken `lock`'u tutar, o sırada
    /// libchiaki günlüğe yazabilir.
    private var hint: DisconnectReason?
    private let hintLock = NSLock()

    init(generation: Int, owner: StreamSession?) {
        self.generation = generation
        self.owner = owner
        logger.onMessage = { [weak self] text, _ in
            guard let self, let found = DisconnectReason.sessionRequestHint(fromLog: text) else { return }
            self.hintLock.lock()
            self.hint = found
            self.hintLock.unlock()
        }
    }

    var sessionRequestHint: DisconnectReason? {
        hintLock.lock()
        defer { hintLock.unlock() }
        return hint
    }

    /// `chiaki_session_init`; başarısızsa kutu kullanılmamış sayılır (kapatılacak iş parçacığı yok).
    func initialize(console: RegisteredConsole, accountId: Data, audio: Bool = false) -> ChiakiErrorCode {
        var info = ChiakiConnectInfo()
        info.ps5 = true
        copy(console.registKey, into: &info.regist_key)
        copy(console.morning, into: &info.morning)
        chiaki_connect_video_profile_preset(&info.video_profile, CHIAKI_VIDEO_RESOLUTION_PRESET_1080p, CHIAKI_VIDEO_FPS_PRESET_30)
        info.video_profile.codec = CHIAKI_CODEC_H264
        info.video_profile_auto_downgrade = true
        info.enable_keyboard = false
        info.enable_dualsense = false
        // Nino: ses yalnız konuşanı tanımak için istenir (dublaj); yoksa libchiaki ses paketlerini atar.
        info.audio_video_disabled = audio ? CHIAKI_NONE_DISABLED : CHIAKI_AUDIO_DISABLED
        info.auto_regist = false
        info.holepunch_session = nil
        info.rudp_sock = nil
        copy(accountId, into: &info.psn_account_id)
        info.packet_loss_max = 0.05
        info.enable_idr_on_fec_failure = true

        // libchiaki adresi oturum açılırken kopyalar; geçici C dizgesi yeterli.
        let error = console.host.withCString { host -> ChiakiErrorCode in
            info.host = host
            return chiaki_session_init(pointer, &info, logger.pointer)
        }
        if !error.isSuccess { markUnused() }
        return error
    }

    /// Oturumu durdurur ve iş parçacığını bekler. libchiaki iş parçacığından çağrılmamalı.
    func tearDown() {
        lock.lock()
        defer { lock.unlock() }
        guard !torn else { return }
        torn = true
        chiaki_session_stop(pointer)
        chiaki_session_join(pointer)
        chiaki_session_fini(pointer)
    }

    /// `chiaki_session_init`/`start` başarısız olduysa: join edilecek iş parçacığı yok, kapatma adımları atlanır.
    func markUnused() {
        lock.lock()
        torn = true
        lock.unlock()
    }

    deinit {
        tearDown()
        pointer.deallocate()
    }
}

/// PS5'e (ikinci hesapla) Remote Play bağlantısı kurar ve görüntüyü kare kare verir.
/// Ses yalnız `wantsAudio` açıkken alınır (konuşanı tanımak için), kol girdisi gönderilmez. Bağlantı koparsa kendiliğinden yeniden bağlanır.
public final class StreamSession: @unchecked Sendable {
    public var onFrame: ((CGImage) -> Void)?
    /// Nino: PS5'in sesi, 16 kHz tek kanal örnekler (yalnız `wantsAudio` açıkken; bağlanmadan önce ayarlanır).
    public var onAudio: (([Float]) -> Void)?
    /// Nino (geliştirici video kaydı): PS5'in sesi tam kalitede, 48 kHz iki kanal sıralı örnekler.
    public var onFullAudio: (([Float]) -> Void)?
    private var fullDecoder: OpusAudioDecoder?
    public var wantsAudio = false
    private let audioQueue = DispatchQueue(label: "nino.stream-audio")
    private var audioDecoder: OpusAudioDecoder?
    public var onState: ((SessionState) -> Void)?
    /// PS5 ağda yeni bir adreste bulununca (oturum kuyruğunda) çağrılır; yeni adres kaydedilmelidir.
    public var onConsoleMoved: ((RegisteredConsole) -> Void)?
    /// Nino: macOS'un Yerel Ağ izni kapalı görünüyor (ya da artık görünmüyor); değer değişince oturum kuyruğunda
    /// çağrılır. Nasıl karar verildiği: `LocalNetworkAccess`.
    public var onLocalNetworkBlocked: ((Bool) -> Void)?
    /// Son bildirilen değer (yalnız `queue`).
    private var reportedBlocked = false
    /// PS5 araması (testlerde sahtesi; gerçek arama ağa paket gönderir). `host` nil ise bütün ağ taranır.
    var searchConsoles: (_ timeout: Double, _ host: String?) -> [ConsoleInfo] = { timeout, host in
        Console.search(timeout: .seconds(timeout), host: host)
    }

    /// Yalnız `queue` üzerinde değişir (PS5'in adresi değişirse; Windows'taki gibi).
    private var console: RegisteredConsole
    /// Son aramada PS5 yanıt verdi mi (yalnız `queue`).
    private var searchAnswered = true
    /// Tüm ağı taramak pahalı; PS5 kapalıyken her yeniden denemede yapılmaz.
    private var nextRelocate = Date.distantPast
    private let accountId: Data
    /// PS5 bu hesap için giriş şifresi isterse gönderilecek 4 hane (Ayarlar'da kayıtlıysa).
    private let loginPasscode: String?
    private let queue = DispatchQueue(label: "couchsubs.stream-session")
    private let decodeQueue = DispatchQueue(label: "couchsubs.decode")
    private var decoder = H264FrameDecoder()
    private var throttle = FrameThrottle(minInterval: 1.0 / 20)
    private var policy = ReconnectPolicy()
    /// Yalnız `queue` üzerinde okunup yazılır.
    private var box: ChiakiSessionBox?
    /// Bağlıyken görüntü gelmezse oturum yeniden kurulur. Kare çözme kuyruğundan da yazılır; `watchLock` ile korunur.
    private var watchdog = PictureWatchdog()
    private let watchLock = NSLock()

    /// Durdurma isteği ve kuşak numarası; her başlat/durdur yeni bir kuşak açar ve eski
    /// bloklar (yeniden deneme, eski oturumun kapanma olayı) kendini iptal eder.
    private let stateLock = NSLock()
    private var running = false
    private var generation = 0

    public init(console: RegisteredConsole, accountId: Data, loginPasscode: String? = nil) {
        self.console = console
        self.accountId = accountId
        self.loginPasscode = LoginPasscode.normalized(loginPasscode)
    }

    deinit {
        // Kuyruk bloklarının hiçbiri self'i güçlü tutmaz; kalan oturum (varsa) arka planda kapatılır.
        if let box { DispatchQueue.global().async { box.tearDown() } }
    }

    public func start() {
        let current = bump(running: true)
        queue.async { [weak self] in
            self?.policy.reset()
            self?.watch { $0.reset() }
            self?.connect(current)
        }
    }

    /// Bloklamaz: oturum arka planda kapatılır.
    public func stop() {
        _ = bump(running: false)
        queue.async { [weak self] in self?.closeBox() }
    }

    /// Mac uykudan uyandığında ya da ağ değiştiğinde uygulama tarafından çağrılır.
    public func reconnectNow() {
        guard isRunning else { return }
        let current = bump(running: true)
        queue.async { [weak self] in
            guard let self else { return }
            self.closeBox()
            self.policy.reset()
            self.watch { $0.reset() }
            self.connect(current)
        }
    }

    // MARK: - Durum

    private var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    private func bump(running: Bool) -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        self.running = running
        generation += 1
        return generation
    }

    private func isCurrent(_ value: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running && generation == value
    }

    // MARK: - Bağlantı (hepsi `queue` üzerinde)

    private func connect(_ current: Int) {
        guard isCurrent(current), box == nil else { return }
        emit(.connecting)

        // PS5 uyuyorsa uyandır; uyanmayı kuyruğu bloklamadan, aralıklı kontrollerle bekle.
        // Kayıtlı adres bilinmiyorsa (eski sürümlerin kaydettiği 0.0.0.0 ya da boş adres) o adrese sorulmaz; PS5 doğrudan
        // adıyla ağda aranır.
        let known = ConsoleAddress.isUsable(console.host)
        if !known { RemotePlayLog.write("PS5 oturumu: kayıtlı adres geçersiz (\"\(console.host)\"); PS5 adıyla ağda aranıyor: \(console.name)") }
        let info = (known ? searchConsoles(2, console.host).first : nil) ?? relocate()
        reportLocalNetwork()
        searchAnswered = info != nil
        // Adres hâlâ bilinmiyorsa oturum açılmaz (eskiden 0.0.0.0'a bağlanmayı deniyordu); sonraki denemede yeniden aranır.
        guard ConsoleAddress.isUsable(console.host) else {
            RemotePlayLog.write("PS5 oturumu: \(console.name) ağda bulunamadı ve kayıtlı adresi yok; yeniden aranacak")
            return scheduleReconnect(current, reason: .network)
        }
        if let info {
            RemotePlayLog.write("PS5 oturumu: \(info.name) \(info.host) \(info.isAwake ? "uyanık" : "dinlenmede, uyandırılıyor")")
        } else {
            RemotePlayLog.write("PS5 oturumu: \(console.host) aramaya yanıt vermedi, yine de bağlanılıyor")
        }
        if let info, !info.isAwake {
            do { try Console.wake(console) } catch { RemotePlayLog.write("PS5 uyandırılamadı: \(error)") }
            return waitForWake(current, deadline: Date().addingTimeInterval(20))
        }
        openSession(current)
    }

    /// Yerel ağ izni işareti değiştiyse uygulamaya bildirir (yalnız `queue`).
    private func reportLocalNetwork() {
        let blocked = LocalNetworkAccess.looksBlocked
        guard blocked != reportedBlocked else { return }
        reportedBlocked = blocked
        onLocalNetworkBlocked?(blocked)
    }

    /// Kayıtlı adreste PS5 yoksa (modem adresini değiştirmiş olabilir) ağda arar; bulursa adresi günceller.
    /// Eskiden yalnız Windows'ta vardı; Mac'te adres değişince bağlantı hiç kurulamıyordu.
    private func relocate() -> ConsoleInfo? {
        guard Date() >= nextRelocate else { return nil }
        nextRelocate = Date().addingTimeInterval(30)
        guard let moved = Self.moved(console, found: searchConsoles(3, nil)) else { return nil }
        RemotePlayLog.write("PS5 yeni adreste: \(console.host) -> \(moved.host)")
        console = console.withHost(moved.host)
        onConsoleMoved?(console)
        return moved
    }

    /// Taramada kayıtlı PS5 yeni bir adreste bulunduysa o yanıt; bulunamadıysa, adres aynıysa ya da yanıtın adresi
    /// PS5'in adresi olamayacak bir şeyse (`0.0.0.0`, boş) nil. Geçersiz adres hiçbir zaman kaydedilmez.
    static func moved(_ console: RegisteredConsole, found: [ConsoleInfo]) -> ConsoleInfo? {
        guard let moved = pickMoved(found.filter { ConsoleAddress.isUsable($0.host) }, name: console.name),
              moved.host != console.host else { return nil }
        return moved
    }

    /// Taramada bulunanlar arasından kayıtlı PS5: tek PS5 varsa odur, birden çoksa adı tek eşleşen; emin değilse nil.
    static func pickMoved(_ found: [ConsoleInfo], name: String) -> ConsoleInfo? {
        if found.count == 1 { return found[0] }
        let named = found.filter { $0.name == name }
        return named.count == 1 ? named[0] : nil
    }

    private func waitForWake(_ current: Int, deadline: Date) {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.isCurrent(current) else { return }
            if self.searchConsoles(2, self.console.host).contains(where: \.isAwake) {
                self.openSession(current)
            } else if Date() < deadline {
                self.waitForWake(current, deadline: deadline)
            } else {
                self.scheduleReconnect(current, reason: .consoleAsleep)
            }
        }
    }

    private func openSession(_ current: Int) {
        guard isCurrent(current), box == nil else { return }
        // Yeniden bağlanmada çözücü sıfırdan başlar (uykudan sonra eski oturumu geçersiz olabilir).
        decodeQueue.async { [weak self] in self?.decoder = H264FrameDecoder() }

        let box = ChiakiSessionBox(generation: current, owner: self)
        let error = box.initialize(console: console, accountId: accountId, audio: wantsAudio)
        guard error.isSuccess else {
            return scheduleReconnect(current, reason: .other(ChiakiError(code: error).description), initialized: false, box: box)
        }

        let user = Unmanaged.passUnretained(box).toOpaque()
        chiaki_session_set_event_cb(box.pointer, { event, user in
            guard let event, let user else { return }
            let box = Unmanaged<ChiakiSessionBox>.fromOpaque(user).takeUnretainedValue()
            box.owner?.handle(event.pointee, generation: box.generation, sessionRequestHint: box.sessionRequestHint)
        }, user)
        chiaki_session_set_video_sample_cb(box.pointer, { buffer, size, _, _, user in
            guard let buffer, let user else { return true }
            Unmanaged<ChiakiSessionBox>.fromOpaque(user).takeUnretainedValue().owner?.ingest(Data(bytes: buffer, count: size))
            return true
        }, user)

        if wantsAudio {
            var sink = ChiakiAudioSink()
            sink.user = user
            sink.header_cb = { header, user in
                guard let header, let user else { return }
                let h = header.pointee
                Unmanaged<ChiakiSessionBox>.fromOpaque(user).takeUnretainedValue().owner?
                    .audioHeader(channels: Int(h.channels), rate: Int(h.rate), frameSize: Int(h.frame_size))
            }
            sink.frame_cb = { buffer, size, user in
                guard let buffer, let user, size > 0 else { return }
                Unmanaged<ChiakiSessionBox>.fromOpaque(user).takeUnretainedValue().owner?.audioPacket(Data(bytes: buffer, count: size))
            }
            chiaki_session_set_audio_sink(box.pointer, &sink)
        }
        // PS5 "bu görüntü yayınlanamaz" (korumalı içerik) ya da "yeniden yayınlanabilir" dediğinde libchiaki ctrl iş parçacığı
        // `cantdisplay_cb`yi koşulsuz çağırır; atanmazsa NULL işlev çağrılır ve uygulama SIGSEGV ile kapanır. Altyazı için
        // yapılacak bir şey yok: yalnız günlüğe yazılır, akış sürer.
        var displaySink = ChiakiCtrlDisplaySink(user: user, cantdisplay_cb: { _, cantDisplay in
            RemotePlayLog.write(cantDisplay ? "PS5 stream can't display (protected content)" : "PS5 stream can display again")
        })
        chiaki_session_ctrl_set_display_sink(box.pointer, &displaySink)

        let started = chiaki_session_start(box.pointer)
        guard started.isSuccess else {
            chiaki_session_fini(box.pointer)
            return scheduleReconnect(current, reason: .other(ChiakiError(code: started).description), initialized: false, box: box)
        }
        self.box = box
    }

    /// Geçerli oturumu kapatır. Kapatma join içerdiği için kuyruğu bekletmemek adına arka planda yapılır.
    private func closeBox() {
        watch { $0.ended() }
        guard let box else { return }
        self.box = nil
        DispatchQueue.global().async { box.tearDown() }
    }

    /// libchiaki iş parçacığından çağrılır.
    fileprivate func handle(_ event: ChiakiEvent, generation eventGeneration: Int, sessionRequestHint: DisconnectReason?) {
        switch event.type {
        case CHIAKI_EVENT_CONNECTED:
            queue.async { [weak self] in
                guard let self, self.box?.generation == eventGeneration else { return }
                self.policy.connected()
                self.watch { $0.connected() }
                // Oturum açıldıysa yerel ağa ulaşılıyor demektir; izin uyarısı kalkar.
                LocalNetworkAccess.noteReachable()
                self.reportLocalNetwork()
                self.emit(.streaming)
                self.scheduleWatch(eventGeneration)
            }
        case CHIAKI_EVENT_LOGIN_PIN_REQUEST:
            // libchiaki olayı state_mutex tutarken verir; şifre kuyrukta (kilit bırakıldıktan sonra) gönderilir.
            let reply = LoginPasscode.reply(saved: loginPasscode, incorrect: event.login_pin_request.pin_incorrect)
            queue.async { [weak self] in
                guard let self, let box = self.box, box.generation == eventGeneration else { return }
                switch reply {
                case .send(let pin):
                    RemotePlayLog.write("PS5 giriş şifresi istedi; Ayarlar'daki şifre gönderiliyor")
                    pin.withUnsafeBytes { raw in
                        _ = chiaki_session_set_login_pin(box.pointer, raw.bindMemory(to: UInt8.self).baseAddress, pin.count)
                    }
                case .stop(let reason):
                    // Şifre yok ya da yanlış: yeniden denemek aynı yere çıkar, oturum kapatılır.
                    _ = self.bump(running: false)
                    self.closeBox()
                    self.emit(.disconnected(reason))
                }
            }
        case CHIAKI_EVENT_QUIT:
            let reason = DisconnectReason(quit: event.quit.reason, sessionRequestHint: sessionRequestHint)
            queue.async { [weak self] in
                // Eski bir oturumun (ör. reconnectNow ile kapatılanın) kapanma olayı yeni oturumu etkilemez.
                guard let self, self.box?.generation == eventGeneration else { return }
                self.closeBox()
                self.policy.ended()
                if reason == .registrationInvalid || reason == .remotePlayDisabled {
                    // Kayıt geçersiz ya da Uzaktan Oynama kapalı: yeniden denemek aynı yere çıkar (eskiden sonsuza kadar
                    // "Yeniden bağlanılıyor…").
                    _ = self.bump(running: false)
                    return self.emit(.disconnected(reason))
                }
                self.scheduleReconnect(eventGeneration, reason: reason)
            }
        default:
            break
        }
    }

    private func watch<T>(_ body: (inout PictureWatchdog) -> T) -> T {
        watchLock.lock()
        defer { watchLock.unlock() }
        return body(&watchdog)
    }

    /// Bağlıyken saniyede bir bakılır: görüntü `PictureWatchdog.stallAfter`'dan uzun süredir gelmiyorsa bağlantı açık
    /// görünse de oturum kapatılıp yeniden kurulur (bkz. `PictureWatchdog`).
    private func scheduleWatch(_ boxGeneration: Int) {
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.box?.generation == boxGeneration, self.isCurrent(boxGeneration) else { return }
            guard let gap = self.watch({ $0.stalled() }) else { return self.scheduleWatch(boxGeneration) }
            let next = self.watch { $0.afterStall() }
            let streak = self.watch { $0.noPictureSessions }
            RemotePlayLog.write("PS5'ten \(Int(gap)) sn'dir görüntü gelmiyor (bağlantı açık, art arda görüntüsüz oturum \(streak)): \(next)")
            self.closeBox()
            self.policy.ended()
            if next == .giveUp {
                // Görüntü hiç gelmiyor: sonsuz yeniden bağlanma döngüsü yerine dur ve nedenini söyle.
                _ = self.bump(running: false)
                return self.emit(.disconnected(.noPicture))
            }
            self.scheduleReconnect(boxGeneration, reason: .other(PictureWatchdog.reason))
        }
    }

    private func scheduleReconnect(_ current: Int, reason: DisconnectReason, initialized: Bool = true, box failed: ChiakiSessionBox? = nil) {
        // Başlatılamamış kutunun join edilecek iş parçacığı yok; yalnız belleği bırakılır.
        if let failed, !initialized { failed.markUnused() }
        emit(.disconnected(DisconnectReason.classify(reason, searchAnswered: searchAnswered, host: console.host)))
        guard isCurrent(current) else { return }
        let delay = policy.nextDelay(inUse: reason == .inUse)
        queue.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in self?.connect(current) }
    }

    /// Her kare çözülür (sonraki kareler öncekilere dayanır); görüntü saniyede en çok 20 kez üretilir.
    /// Okuma meşgulken gelen kareler zaten atlanır; sık kare, altyazının erken ve eksiksiz yakalanmasını sağlar.
    fileprivate func audioHeader(channels: Int, rate: Int, frameSize: Int) {
        audioQueue.async { [weak self] in
            self?.audioDecoder = OpusAudioDecoder(channels: channels, rate: rate, frameSize: frameSize)
            if self?.onFullAudio != nil {
                self?.fullDecoder = OpusAudioDecoder(channels: channels, rate: rate, frameSize: frameSize, outputRate: 48_000, outputChannels: 2)
            }
            RemotePlayLog.write("ses: \(channels) kanal, \(rate) Hz, \(frameSize) örnek/paket\(self?.audioDecoder == nil ? " (çözücü açılamadı)" : "")")
        }
    }

    fileprivate func audioPacket(_ packet: Data) {
        audioQueue.async { [weak self] in
            guard let self, let decoder = self.audioDecoder else { return }
            let samples = decoder.decode(packet)
            if let full = self.fullDecoder, let sink = self.onFullAudio {
                let stereo = full.decode(packet)
                if !stereo.isEmpty { sink(stereo) }
            }
            // Nino: 10 sn'de bir ses özeti (gelen paket, çözülen örnek, ortalama güç) günlüğe yazılır.
            self.audioPackets += 1
            self.audioSamples += samples.count
            for x in samples { self.audioEnergy += Double(x * x) }
            let now = Date()
            if now.timeIntervalSince(self.audioReported) > 10 {
                let rms = self.audioSamples > 0 ? sqrt(self.audioEnergy / Double(self.audioSamples)) : 0
                RemotePlayLog.write(String(format: "ses: %d paket, %d örnek, güç %.1f dB", self.audioPackets, self.audioSamples,
                                           20 * log10(max(rms, 1e-9))))
                self.audioPackets = 0; self.audioSamples = 0; self.audioEnergy = 0
                self.audioReported = now
            }
            if !samples.isEmpty { self.onAudio?(samples) }
        }
    }
    private var audioPackets = 0, audioSamples = 0
    private var audioEnergy = 0.0
    private var audioReported = Date()

    fileprivate func ingest(_ sample: Data) {
        decodeQueue.async { [weak self] in
            guard let self else { return }
            let wanted = self.throttle.shouldPass()
            if let image = self.decoder.decode(annexB: sample, makeImage: wanted), wanted {
                self.watch { $0.picture() }
                self.onFrame?(image)
            }
        }
    }

    private func emit(_ state: SessionState) {
        // Ana ekrandaki durumun nedeni remoteplay.log'da da görünsün.
        if state != .connecting { RemotePlayLog.write("PS5 oturumu: \(state)") }
        onState?(state)
    }
}
