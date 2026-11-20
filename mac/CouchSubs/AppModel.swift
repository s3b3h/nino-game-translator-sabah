// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import Darwin
import Combine
import RemotePlay

/// Dış dünyayla (PS5, PSN, TV) konuşan her şey; testlerde sahtesi kullanılır.
extension AppServices {
    func makeWindowStream() -> GameWindowStream { GameWindowStream() }
    func makeCardStream(showsPlayer: Bool, preferredID: String?) -> CaptureCardStream {
        CaptureCardStream(showsPlayer: showsPlayer, preferredID: preferredID)
    }

    /// DeepL anahtarını dener (ayarlardaki "Kaydet ve dene").
    func checkOnlineKey(_ key: String) async -> OnlineKeyCheck { await DeepLTranslator.check(key: key) }
    /// Yapay zekâ anahtarını örnek bir satırı çevirerek dener.
    func testAIKey(provider: AIProvider, key: String, model: String?) async -> Result<String, AIFailure> {
        await AITranslationCore.test(provider: provider, key: key, model: model)
    }
    /// Yerel model sunucusunu (Ollama, LM Studio) örnek bir satırı çevirerek dener; anahtar boş olabilir.
    func testLocalAI(server: LocalAIServer, key: String) async -> Result<String, AIFailure> {
        await AITranslationCore.test(provider: .local, key: key, model: server.model, server: server)
    }
    /// Bu Mac'teki Remote Play penceresinden (PS Remote Play ya da chiaki-ng) okuyan görüntü kaynağı (bkz. `RemotePlayWindowStream`).
    func makeWindowStream(app: RemotePlayApp) -> StreamControlling { RemotePlayWindowStream(app: app) }
    func remotePlayInstalled(_ app: RemotePlayApp) -> Bool { RemotePlayWindowStream.isInstalled(app) }
    /// PS5'te o an çalışan oyun: yalnız bağlı PS5'in adresine keşif sorusu gider (ortak havuz için; bkz. `RunningGame`).
    func runningGame(host: String) async -> RunningGame? {
        guard let info = await Console.discover(timeout: .seconds(2), host: host).first else { return nil }
        return RunningGame(titleId: info.runningAppTitleId, name: info.runningAppName)
    }
    /// Samsung kurulumundan önce: TV'nin 8001 yanıtı ve TV'ye giden yolun bu Mac'teki adresi (#343).
    func checkSamsung(host: String) async -> SamsungPreflight {
        SamsungPreflight(info: await SamsungDiscovery.developerInfo(host: host), computerAddress: NetworkAddress.near(host))
    }
    /// Samsung TV'nin model yılı (geliştirici modu penceresinin nerede açıldığı yıla göre değişir).
    func samsungModelYear(host: String) async -> Int? { await SamsungDiscovery.modelYear(host: host) }
    /// Geliştirici modu kodunu (1 2 3 4 5) TV'ye kumanda bağlantısından yazar; TV'nin verdiği jetonu döner.
    func typeSamsungCode(tv: LGTV, key: String?) async throws -> String {
        try await SamsungDeveloperCode.type(on: tv, token: key)
    }
}

/// Samsung kurulumundan önceki denetim: TV'nin geliştirici modu bilgisi ve TV'nin göreceği bu Mac'in adresi.
struct SamsungPreflight: Equatable {
    var info: SamsungDeveloperInfo?
    var computerAddress: String?
}

protocol AppServices: AnyObject {
    /// Yapay zekâ anahtarını örnek bir satırı çevirerek dener (varsayılanı yukarıda; testlerde sahtesi).
    func testAIKey(provider: AIProvider, key: String, model: String?) async -> Result<String, AIFailure>
    /// Yerel model sunucusunu dener (varsayılanı yukarıda; testlerde sahtesi).
    func testLocalAI(server: LocalAIServer, key: String) async -> Result<String, AIFailure>
    func discoverConsoles() async -> [ConsoleInfo]
    func accountId(fromRedirect url: URL) async throws -> Data
    func register(host: String, accountId: Data, pin: UInt32) async throws -> RegisteredConsole
    func discoverTVs() async -> [LGTV]
    /// TV ile eşleşir ve TV uygulamasını sunucu adresiyle başlatmayı dener.
    func pairTV(_ tv: LGTV, key: String?, server: String) async throws -> TVPairing
    /// `loginPasscode`: PS5 bu hesap için giriş şifresi isterse gönderilecek 4 hane (Ayarlar'da kayıtlıysa).
    func makeStream(console: RegisteredConsole, accountId: Data, loginPasscode: String?) -> StreamControlling
    /// Nino: oyun görüntüsünü bu bilgisayardaki PS Remote Play, chiaki-ng ya da Xbox yayın penceresinden okuyan kaynak.
    func makeWindowStream() -> GameWindowStream
    /// Nino: oyun görüntüsünü bu bilgisayara takılı HDMI yakalama kartından okuyan kaynak. `showsPlayer`: oyun bu
    /// bilgisayarda tam ekran gösterilir (altyazı bilgisayar ekranındaysa).
    func makeCardStream(showsPlayer: Bool, preferredID: String?) -> CaptureCardStream
    /// CouchSubs'ın Remote Play penceresi kaynağı (`UserSettings.frameSource`, `remotePlayApp`). Nino `makeWindowStream()`
    /// kullanır; bu yalnız kurulu uygulamayı sormak ve uyumluluk için durur.
    func makeWindowStream(app: RemotePlayApp) -> StreamControlling
    /// Seçilen Remote Play uygulaması (PS Remote Play ya da chiaki-ng) bu Mac'te kurulu mu.
    func remotePlayInstalled(_ app: RemotePlayApp) -> Bool
    /// `onMoved`: TV ağda yeni bir adreste bulununca çağrılır.
    /// `appConnected`: TV uygulaması bilgisayara bağlı mı (Samsung'da bağlıyken TV'ye dokunulmaz).
    /// `onKey`: TV bağlantıda yeni jeton verdi (Samsung); saklanır.
    func makeKeeper(tv: LGTV, key: String?, params: [String: Any], appConnected: @escaping @Sendable () -> Bool,
                    onMoved: @escaping (LGTV) -> Void, onKey: @escaping @Sendable (String) -> Void) -> KeeperControlling
    /// Uygulamayla gelen TV paketinin sürümü (geliştirici derlemesinde paket olmayabilir).
    var bundledTVAppVersion: String? { get }
    func isDevModeOn(host: String) async -> Bool
    func fetchDevKey(host: String, passphrase: String) async throws -> String
    func installedTVAppVersion(host: String, devKey: String) async throws -> String?
    func installTVApp(host: String, devKey: String) async throws
    /// LG geliştirici modunun süresini baştan başlatır; kalan saati döner (bilinmiyorsa nil).
    func renewDevSession(host: String, devKey: String) async -> Int?

    /// Samsung ve Android TV için uygulamayla gelen paket (geliştirici derlemesinde olmayabilir).
    func bundledApp(for brand: TVBrand) -> BundledTVApp?
    func isSamsungDevModeOn(host: String) async -> Bool
    func checkSamsung(host: String) async -> SamsungPreflight
    func samsungModelYear(host: String) async -> Int?
    func typeSamsungCode(tv: LGTV, key: String?) async throws -> String
    /// TV'deki sürüme bakar, eksik ya da eskiyse kurar; TV'deki sürümü ve kurulup kurulmadığını döner.
    func installSamsungApp(host: String, app: BundledTVApp,
                           onEvent: @escaping @Sendable (TVInstallEvent) -> Void) async throws -> (version: String, installed: Bool)
    func isAndroidDebugOn(host: String) async -> Bool
    /// Ağda ADB'si açık cihazlar.
    func scanAndroidTVs() async -> [String]
    /// Eksikse ya da eskiyse kurar; TV'deki sürümü döner.
    func installAndroidApp(host: String, app: BundledTVApp, onEvent: @escaping @Sendable (TVInstallEvent) -> Void) async throws -> String
}

struct BundledTVApp: Equatable {
    let url: URL
    let version: String

    /// `couchsubs-androidtv_0.7.0.apk` → `0.7.0`
    static func version(ofFile name: String) -> String? {
        let stem = (name as NSString).deletingPathExtension
        guard let underscore = stem.lastIndex(of: "_"), underscore < stem.index(before: stem.endIndex) else { return nil }
        return String(stem[stem.index(after: underscore)...])
    }
}

/// Denetlenemeyen TV'ler için: TV uygulaması kendisi bağlanır.
final class IdleKeeper: KeeperControlling {
    func start(interval: Duration) {}
    func stop() {}
    func reconnect() {}
}

struct TVPairing: Equatable {
    let key: String
    /// false ise TV uygulaması açılamadı; büyük olasılıkla TV'de kurulu değil.
    let launched: Bool
}

/// PS5 bağlantısı (gerçekte `StreamSession`).
protocol StreamControlling: AnyObject {
    var onFrame: ((CGImage) -> Void)? { get set }
    /// Nino: PS5'in sesi (konuşanı tanımak için); `wantsAudio` bağlanmadan önce açılır.
    var onAudio: (([Float]) -> Void)? { get set }
    /// Nino (geliştirici video kaydı): tam kalitede ses (48 kHz iki kanal).
    var onFullAudio: (([Float]) -> Void)? { get set }
    var wantsAudio: Bool { get set }
    var onState: ((SessionState) -> Void)? { get set }
    /// PS5 ağda yeni bir adreste bulundu; yeni adres kaydedilir.
    var onConsoleMoved: ((RegisteredConsole) -> Void)? { get set }
    /// Nino: macOS'un Yerel Ağ izni kapalı görünüyor ya da artık görünmüyor (yalnız gerçek PS5 oturumu bildirir).
    var onLocalNetworkBlocked: ((Bool) -> Void)? { get set }
    func start()
    func stop()
    func reconnectNow()
}

extension StreamControlling {
    var onAudio: (([Float]) -> Void)? { get { nil } set {} }
    var onFullAudio: (([Float]) -> Void)? { get { nil } set {} }
    /// Pencere ve yakalama kartı kaynakları PS5'i ağda aramaz; bildirecekleri bir şey yok (bkz. `LocalNetworkAccess`).
    var onLocalNetworkBlocked: ((Bool) -> Void)? { get { nil } set {} }
    var wantsAudio: Bool { get { false } set {} }
}

/// TV uygulamasını açık tutan görevli (gerçekte `TVKeeper`).
protocol KeeperControlling: AnyObject {
    func start(interval: Duration)
    func stop()
    func reconnect()
}

extension StreamSession: StreamControlling {}
extension TVKeeper: KeeperControlling {}

final class LiveServices: AppServices {
    func discoverConsoles() async -> [ConsoleInfo] {
        let found = await Console.discover()
        let names = found.map { "\($0.name) \($0.host)\($0.isAwake ? "" : " (dinlenmede)")" }
        RemotePlayLog.write("PS5 araması: \(names.isEmpty ? "bulunamadı" : names.joined(separator: ", "))")
        return found
    }

    func accountId(fromRedirect url: URL) async throws -> Data {
        try await PSNAccount.accountId(fromRedirect: url)
    }

    func register(host: String, accountId: Data, pin: UInt32) async throws -> RegisteredConsole {
        try await Registration.register(host: host, accountId: accountId, pin: pin)
    }

    func discoverTVs() async -> [LGTV] {
        async let lg = LGDiscovery.search()
        async let samsung = SamsungDiscovery.search()
        return await lg + samsung
    }

    func pairTV(_ tv: LGTV, key: String?, server: String) async throws -> TVPairing {
        switch tv.brand {
        case .androidTV:
            // Bilgisayar bu TV'yi denetlemez; TV uygulaması bilgisayarı kendisi bulur.
            return TVPairing(key: "", launched: true)
        case .samsung:
            let client = SamsungClient(tv: tv, token: key)
            defer { client.close() }
            let token = try await client.connect()
            try? await client.launch(appId: AppIdentity.samsungAppId, params: ["server": server])
            return TVPairing(key: token, launched: true)
        case .lg:
            break
        }
        let client = SSAPClient(tv: tv, clientKey: key)
        defer { client.close() }
        let newKey = try await client.connect()
        let launched = (try? await client.launch(appId: AppIdentity.tvAppId, params: ["server": server])) != nil
        return TVPairing(key: newKey, launched: launched)
    }

    func makeStream(console: RegisteredConsole, accountId: Data, loginPasscode: String?) -> StreamControlling {
        StreamSession(console: console, accountId: accountId, loginPasscode: loginPasscode)
    }

    func makeKeeper(tv: LGTV, key: String?, params: [String: Any], appConnected: @escaping @Sendable () -> Bool,
                    onMoved: @escaping (LGTV) -> Void, onKey: @escaping @Sendable (String) -> Void) -> KeeperControlling {
        switch tv.brand {
        case .androidTV:
            return IdleKeeper()
        case .samsung:
            let token = SamsungTokenHolder(token: key, onChange: onKey)
            let locator = TVLocator(tv: tv, connect: { tv in
                let client = SamsungClient(tv: tv, token: token.current)
                do {
                    let received = try await client.connect()
                    token.received(received)
                } catch {
                    client.close()
                    throw error
                }
                return client
            }, search: { await SamsungDiscovery.search() }, onMoved: onMoved)
            return TVKeeper(connect: { try await locator.connect() }, appId: AppIdentity.samsungAppId, params: params,
                            appConnected: appConnected)
        case .lg:
            break
        }
        let locator = TVLocator(tv: tv, connect: { tv in
            let client = SSAPClient(tv: tv, clientKey: key)
            do {
                _ = try await client.connect()
            } catch {
                client.close()
                throw error
            }
            return client
        }, search: { await LGDiscovery.search() }, onMoved: onMoved)
        return TVKeeper(connect: { try await locator.connect() }, appId: AppIdentity.tvAppId, params: params)
    }

    // MARK: - TV uygulamasını kurma

    private var bundledTVPackage: URL? {
        Bundle.main.urls(forResourcesWithExtension: "ipk", subdirectory: "tv-app")?.first
    }

    var bundledTVAppVersion: String? {
        bundledTVPackage.flatMap { DevModeInstaller.version(ofPackage: $0.lastPathComponent) }
    }

    func isDevModeOn(host: String) async -> Bool { await DevModeInstaller.isDevModeOn(host: host) }

    func fetchDevKey(host: String, passphrase: String) async throws -> String {
        try await DevModeInstaller.fetchKey(host: host, passphrase: passphrase, runner: ProcessRunner())
    }

    func installedTVAppVersion(host: String, devKey: String) async throws -> String? {
        try await withKeyFile(devKey) { file in
            try await DevModeInstaller(host: host, keyFile: file, runner: ProcessRunner()).installedVersion()
        }
    }

    func installTVApp(host: String, devKey: String) async throws {
        guard let package = bundledTVPackage, let version = bundledTVAppVersion else { throw DevModeError.installFailed }
        try await withKeyFile(devKey) { file in
            try await DevModeInstaller(host: host, keyFile: file, runner: ProcessRunner()).install(package: package, version: version)
        }
    }

    func renewDevSession(host: String, devKey: String) async -> Int? {
        try? await withKeyFile(devKey) { file in
            try await DevModeInstaller(host: host, keyFile: file, runner: ProcessRunner()).renewSession()
        }
    }

    // MARK: Samsung ve Android TV (gömülü yardımcıyla)

    func bundledApp(for brand: TVBrand) -> BundledTVApp? {
        let ext = switch brand {
        case .samsung: "wgt"
        case .androidTV: "apk"
        case .lg: "ipk"
        }
        guard brand != .lg, TVHelper.executable != nil,
              let url = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "tv-app")?.first,
              let version = BundledTVApp.version(ofFile: url.lastPathComponent) else { return nil }
        return BundledTVApp(url: url, version: version)
    }

    func isSamsungDevModeOn(host: String) async -> Bool { await Self.isPortOpen(host: host, port: 26101) }

    func installSamsungApp(host: String, app: BundledTVApp,
                           onEvent: @escaping @Sendable (TVInstallEvent) -> Void) async throws -> (version: String, installed: Bool) {
        let result = try await TVHelper.run(["samsung-install", "--host", host, "--package", app.url.path, "--version", app.version,
                                    "--profiles", TVHelper.dataDirectory.appendingPathComponent("samsung").path,
                                    "--log", TVInstallLog.file.path], onEvent: onEvent)
        let version = result.version.flatMap { $0.isEmpty ? nil : $0 } ?? app.version
        return (version, result.installed)
    }

    func isAndroidDebugOn(host: String) async -> Bool { await Self.isPortOpen(host: host, port: 5555) }

    func scanAndroidTVs() async -> [String] {
        (try? await TVHelper.run(["android-scan"]).hosts) ?? []
    }

    func installAndroidApp(host: String, app: BundledTVApp, onEvent: @escaping @Sendable (TVInstallEvent) -> Void) async throws -> String {
        let result = try await TVHelper.run(["android-install", "--host", host, "--package", app.url.path, "--version", app.version,
                                             "--key-dir", TVHelper.dataDirectory.appendingPathComponent("adb").path], onEvent: onEvent)
        return result.version ?? app.version
    }

    static func isPortOpen(host: String, port: UInt16) async -> Bool {
        await DevModeInstaller.isPortOpen(host: host, port: port)
    }

    /// ssh anahtarı dosyadan okur; dosya yalnız komut süresince durur.
    private func withKeyFile<T>(_ key: String, _ body: (URL) async throws -> T) async throws -> T {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: file.path, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw DevModeError.installFailed
        }
        defer { try? FileManager.default.removeItem(at: file) }
        return try await body(file)
    }
}

enum AppError: LocalizedError, Equatable {
    case invalidPin, invalidLogin, missingAccount, wrongAccount, registrationFailed
    /// PS5 eşleştirmesinin ayrı ayrı anlatılan sonuçları (Windows'taki AppError ile aynı).
    case missingConsole, wrongCode, consoleNoAnswer, consoleNoReply, consoleInUse, consoleCrashed, consoleVersion,
         badAddress, localNetworkBlocked
    /// PSN girişinin ayrı ayrı anlatılan sonuçları (eskiden hepsi invalidLogin ya da ham Swift hatasıydı).
    case loginRefused, loginRateLimited, loginServer, loginNetwork, loginBadResponse, loginWindowClosed, loginPageFailed

    /// PSN girişinin hatası ve iletiye eklenecek ayrıntı (Sony'nin hatası, HTTP kodu).
    static func login(_ error: PSNAccount.PSNError) -> DetailedError {
        func detail(_ status: Int?, _ text: String?) -> String? {
            let candidates: [String?] = [status.map { "HTTP \($0)" }, text]
            let parts = candidates.compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        switch error {
        case .noCode: return DetailedError(error: .invalidLogin, detail: nil)
        case .refused(let status, let text): return DetailedError(error: .loginRefused, detail: detail(status, text))
        case .rateLimited(let status, let text): return DetailedError(error: .loginRateLimited, detail: detail(status, text))
        case .http(let status, let text): return DetailedError(error: .loginServer, detail: detail(status, text))
        case .network(let text): return DetailedError(error: .loginNetwork, detail: text)
        case .badResponse: return DetailedError(error: .loginBadResponse, detail: nil)
        }
    }

    init(_ kind: Registration.RegistrationError.Kind) {
        switch kind {
        case .wrongAccount: self = .wrongAccount
        case .wrongCode: self = .wrongCode
        case .noAnswer: self = .consoleNoAnswer
        // libchiaki iptali yalnız durdurulunca bildirir; bu da PS5'in yanıtı gelmeden bitmek demektir.
        case .noReply, .canceled: self = .consoleNoReply
        case .inUse: self = .consoleInUse
        case .consoleCrashed: self = .consoleCrashed
        case .versionMismatch: self = .consoleVersion
        case .badAddress: self = .badAddress
        case .localNetworkBlocked: self = .localNetworkBlocked
        case .failed: self = .registrationFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidPin: String(localized: "The code must be 8 digits.")
        case .invalidLogin: String(localized: "Sign-in did not complete. Please try again.")
        case .missingAccount: String(localized: "Sign in to PlayStation Network first.")
        case .wrongAccount: String(localized: "The PS5 did not recognise this account. Get the code from the PS5 user signed in with the account you used in Nino, or sign in again with that user's account.")
        case .registrationFailed: String(localized: "The PS5 refused the code. Open Pair Device again on the PS5 and enter the new code.")
        case .missingConsole: String(localized: "No PS5 found. Make sure it is on and on the same network, or enter its IP address.")
        case .wrongCode: String(localized: "The code is wrong or has expired. Open Pair Device again on the PS5 and enter the new code.")
        case .consoleNoAnswer: String(localized: "The PS5 did not answer. Make sure it is on (not in rest mode), on the same network as this computer, and that Remote Play is turned on, then try again.")
        case .consoleNoReply: String(localized: "The PS5 received the request but did not answer in time. Open Pair Device again on the PS5 and enter the new code.")
        case .consoleInUse: String(localized: "Remote Play is in use on another device. Close it there and enter a new code.")
        case .consoleCrashed: String(localized: "The PS5 Remote Play service stopped unexpectedly. Restart the PS5 and enter a new code.")
        case .consoleVersion: String(localized: "This PS5 system version is not supported yet. Update Nino and try again.")
        case .badAddress: String(localized: "No PS5 found at this address. Check the PS5's IP address under Settings › Network › Connection Status.")
        case .localNetworkBlocked: String(localized: "macOS blocked the connection to the local network. Turn on Nino in System Settings › Privacy & Security › Local Network, then enter a new code.")
        case .loginRefused: String(localized: "Sony did not complete the sign-in. Wait a minute, then press Sign in again and sign in with the second account.")
        case .loginRateLimited: String(localized: "Sony received too many sign-in attempts. Wait about 15 minutes, then sign in again.")
        case .loginServer: String(localized: "Sony's sign-in server returned an error. Wait a few minutes, then sign in again.")
        case .loginNetwork: String(localized: "Could not reach Sony's sign-in server. Check the internet connection, then sign in again.")
        case .loginBadResponse: String(localized: "Sony's answer could not be read. Sign in again; if it keeps happening, update Nino.")
        case .loginWindowClosed: String(localized: "The sign-in window was closed before sign-in finished. Press Sign in and finish signing in in the window.")
        case .loginPageFailed: String(localized: "Sony's sign-in page could not be loaded. Check the internet connection, then sign in again.")
        }
    }
}

/// Başarısız PS5 eşleştirmesi ya da PSN girişi: ne yapılacağı, ayrıntı (PS5'in kodu, libchiaki'nin hata satırı, Sony'nin
/// hatası ya da HTTP kodu) ve gönderilecek günlük dosyası.
struct DetailedError: LocalizedError, Equatable {
    let error: AppError
    let detail: String?

    var errorDescription: String? {
        var text = error.errorDescription ?? ""
        if let detail, !detail.isEmpty { text += " (\(detail))" }
        return text + " " + String(format: String(localized: "If this keeps happening, send us this file: %@"), RemotePlayLog.displayPath)
    }
}

/// TV uygulamasının kurulum durumu.
enum TVAppState: Equatable {
    /// Bilinmiyor ya da yapılacak bir şey yok (ör. uygulama açılıyor ama anahtar yok).
    case unknown
    case working
    case upToDate(String)
    /// TV uygulaması açılamadı ve geliştirici modu kapalı.
    case devModeOff
    /// Geliştirici modu açık; Key Server parolası gerekiyor. `error` son denemenin sonucu.
    case needsPassphrase(error: DevModeError?)
    /// `reason`: TV'nin verdiği sebep (LG kurulumunda luna yanıtındaki errorText/reason); kullanıcıya da gösterilir.
    case failed(DevModeError, reason: String? = nil)
    /// Samsung: sertifika için tarayıcıda Samsung hesabıyla giriş bekleniyor.
    case signIn(URL)
    /// Android TV: TV ekranında hata ayıklama izni bekleniyor.
    case approveOnTV
    /// Samsung: TV'deki Host PC IP (`tvIp`) bu Mac'in adresi (`computer`) değil; sdb denenmedi (#343).
    case hostPcMismatch(tvIp: String, computer: String)
}

/// Geliştirici modu kodunu TV'ye yazma denemesinin durumu.
enum SamsungCodeState: Equatable {
    case idle, sending, sent, failed
}

extension AppAppearance {
    /// Uygulamanın tüm pencerelerinin (ana pencere, ayarlar, kurulum, altyazı penceresi, menüler) görünümü; nil sistemi
    /// izler. Theme.swift'teki renkler pencerenin görünümüne göre çözüldüğü için hepsi birlikte değişir.
    var nsAppearance: NSAppearance? {
        switch self {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .system: nil
        }
    }

    @MainActor func apply() { NSApplication.shared.appearance = nsAppearance }
}

@MainActor
final class AppModel: ObservableObject {
    enum Step: Int, CaseIterable {
        /// `betterTranslation`: isteğe bağlı ücretsiz Gemini anahtarı; atlanabilir.
        case welcome, secondAccount, psnLogin, console, tv, test, betterTranslation, done
    }

    @Published var step: Step {
        didSet {
            // Sihirbaz bitince ana ekran TV'siz de açılsın.
            if step == .done, oldValue != .done { store.save(true, for: StoreKey.setupComplete) }
        }
    }
    /// Nino: sihirbazın ilk ekranında seçilen konsol. Seçilmeden (`nil`) "Hangi konsolda oynuyorsunuz?" görünür; seçilince o
    /// konsolun karşılaması. Kaydedilmez: yarıda kalan kurulum yeniden açılınca yine sorulur.
    @Published var welcomeConsole: GameConsole?
    @Published var accountId: Data?
    @Published var console: RegisteredConsole?
    /// Nino: macOS'un Yerel Ağ izni kapalı görünüyor (PS5 aranırken yerel adreslere hiçbir paket gönderilemedi). PS5
    /// durumunda, ana ekranda ve Sistem sağlığı'nda uyarı gösterilir; çeviri durunca ya da PS5 bağlanınca kalkar.
    @Published private(set) var localNetworkBlocked = false
    /// İkinci hesabın PS5 giriş şifresi Anahtarlık'ta kayıtlı.
    @Published private(set) var hasLoginPasscode: Bool
    @Published var tv: LGTV?
    /// TV'nin eşleşme anahtarı kayıtlı.
    @Published private var tvKeySaved: Bool
    @Published var tvApp = TVAppState.unknown
    /// LG geliştirici modunun kalan süresi (saat); Nino uzattıktan sonra bilinir.
    @Published var devModeHoursLeft: Int?
    /// Son eşleşmede TV uygulaması açılamadı.
    @Published private var tvAppMissing = false
    /// TV uygulaması denetimi sürüyor (bekleme ekranı ve çeviri başlangıcı aynı anda çağırabilir).
    @Published private var refreshingTVApp = false
    /// Samsung kurulumu ya da sürüm denetimi sürüyor: olaylar (giriş, kurulum adımı) kartı değiştirebilir.
    @Published private var samsungCheckRunning = false
    /// Samsung kurulumundan önceki son denetim: geliştirici modu, Host PC IP ve kurulum kapısı. Kart hangi adımın
    /// eksik olduğunu buradan gösterir.
    @Published private(set) var samsungSetup: SamsungSetupCheck?
    /// Samsung TV'nin model yılı (ör. 2023); TV bildirmediyse nil. Bir kez okunur.
    @Published private(set) var samsungModelYear: Int?
    private var samsungModelYearHost: String?
    /// Geliştirici modu kodunun TV'ye bu Mac'ten yazılması (deneysel düğme).
    @Published private(set) var samsungCode = SamsungCodeState.idle
    /// "Yine de dene": TV'nin bildirdiği Host PC IP yanlış görünse de kurulum bir kez denenir (TV yanlış bildirebilir).
    private var samsungIgnoreAddressOnce = false
    @Published var settings: UserSettings {
        didSet {
            // Sıradan tercih; her kaydırıcı hareketinde Anahtarlık'a yazılmasın.
            // Nino: PS5 yoluna dönülünce altyazı TV'ye gider (PS5'te yer seçimi gösterilmez).
            if settings.videoSource != oldValue.videoSource, settings.videoSource == .ps5, settings.output != .tv {
                settings.output = .tv
            }
            if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: StoreKey.settings) }
            server.sendStyle(settings.style)
            if settings.output != oldValue.output {
                outputChanged()
                // Nino: yakalama kartında altyazının yeri oyunun bilgisayarda gösterilip gösterilmeyeceğini de belirler.
                if usesCaptureCard, settings.videoSource == oldValue.videoSource, isRunning {
                    stop()
                    Task { await start() }
                }
            }
            // Nino: asıl görüntü kaynağı `videoSource`'tur. CouchSubs'tan gelen `frameSource` (ikinci hesap adımındaki
            // "Remote Play penceresi" seçimi) ona yansıtılır; `videoSource` değişince de `frameSource` ona uyar.
            // Eşitleme yalnız iki seçim çeliştiğinde yapılır: yakalama kartı (`frameSource`'ta karşılığı yok) bu yansıtmayla
            // PS5'e dönmesin (aynı didSet içindeki yazma, gözlemciyi yeniden çağırır).
            if settings.frameSource != oldValue.frameSource, settings.videoSource == oldValue.videoSource {
                if settings.frameSource == .remotePlayWindow, settings.videoSource != .window { settings.videoSource = .window }
                else if settings.frameSource != .remotePlayWindow, settings.videoSource == .window { settings.videoSource = .ps5 }
            } else if settings.videoSource != oldValue.videoSource {
                settings.frameSource = settings.videoSource == .window ? .remotePlayWindow : .ps5
            }
            if settings.videoSource != oldValue.videoSource { videoSourceChanged() }
            if settings.dubbing != oldValue.dubbing { dubbingSettingsChanged(from: oldValue.dubbing) }
            if settings.targetLanguage != oldValue.targetLanguage {
                let (translations, target) = (translations, settings.targetLanguage)
                Task { await translations.setLanguage(target) }
                targetLanguageChanged()
            }
            if settings.gamePacks != oldValue.gamePacks, let pipeline { connectPacks(to: pipeline) }
            pipeline?.showSpeakerNames = settings.showSpeakerNames
            if settings.appearance != oldValue.appearance { settings.appearance.apply() }
            if settings.sharePool != oldValue.sharePool {
                let (pool, enabled, translations) = (pool, settings.sharePool, translations)
                Task { await pool.setEnabled(enabled); await translations.setEnabled(enabled) }
                if let pipeline { connectPacks(to: pipeline) }
            }
            let translationChanged = settings.onlineTranslation != oldValue.onlineTranslation
                || settings.onlineEngine != oldValue.onlineEngine || settings.geminiModel != oldValue.geminiModel
                || settings.openAIModel != oldValue.openAIModel || settings.claudeModel != oldValue.claudeModel
                || settings.localAIBaseURL != oldValue.localAIBaseURL || settings.localAIModel != oldValue.localAIModel
            if translationChanged { Task { await refreshTranslatorStatus() } }
            let languageChanged = settings.sourceLanguage != oldValue.sourceLanguage
                || settings.targetLanguage != oldValue.targetLanguage
            if isRunning, languageChanged || translationChanged || settings.fastSubtitleDetection != oldValue.fastSubtitleDetection {
                if languageChanged { Task { await refreshTranslatorStatus() } }
                makePipeline()
            }
        }
    }

    // Çalışma durumu
    @Published var isRunning = false
    @Published var isStarting = false
    @Published var sessionState: SessionState = .disconnected(.stopped)
    /// Nino: görüntü kaynağı oyun penceresiyken pencerenin durumu (izin, aranıyor, okunuyor).
    @Published var windowStatus: GameWindowCapture.Status = .stopped
    /// Nino: görüntü kaynağı yakalama kartıyken kartın durumu (izin, kart yok, siyah görüntü, okunuyor).
    @Published var cardStatus: CaptureCardCapture.Status = .stopped
    /// Nino: kurulum sihirbazında yakalama kartı rehberi açık (PS5 adımlarının yerine).
    @Published var cardSetupActive = false
    /// Nino: ayarlarda yakalama kartı rehberi ayrı pencerede açık.
    @Published var showCardSetup = false
    /// Nino: kullanıcının seçtiği yakalama aygıtı (nil: kendiliğinden seçilir). Bu Mac'e özgüdür, ayarlarla taşınmaz.
    @Published var preferredCardID: String? {
        didSet { defaults.set(preferredCardID, forKey: "NinoCaptureCardID") }
    }
    /// Nino: oyun penceresindeki oyun alanının ekrandaki yeri (sol üst başlangıç); altyazı penceresi buna oturur.
    @Published var gameArea: CGRect?
    /// Çeviri sürerken Mac'in boşta uykuya geçmesi engellenir (kullanıcı TV'de oynuyor, Mac'e dokunmuyor).
    var isPreventingSleep: Bool { sleepActivity != nil }
    @Published var tvClients = 0
    @Published var lastSource = ""
    @Published var lastTranslation = ""
    /// Bu ve önceki oturumlarda çevrilen son 200 altyazı (history.json); kaçırılan satır ana pencereden ve "Geçmiş"ten
    /// yeniden okunur.
    @Published var history = SubtitleHistory()
    /// Bu oturumun başladığı an; canlı altyazı alanı yalnız bu oturumun satırlarını gösterir (nil: hepsi).
    @Published private(set) var sessionStartedAt: Date?
    /// Son satırın ölçümleri (yazı tanıma, çeviri, gecikme, güven).
    @Published var lastMetrics: LineMetrics?
    @Published var showHistory = false
    /// Geçmişin yazıldığı dosya (testlerde nil: hiçbir şey yazılmaz).
    private var historyFile: URL?
    private let historyQueue = DispatchQueue(label: "history.json", qos: .utility)
    @Published var translatorStatus: TranslatorStatus = .ready
    /// Çevrimiçi çeviri (DeepL ya da yapay zekâ) şu an çeviremiyor; o satırlar cihaz üstü çeviriyle çevriliyor.
    @Published var onlineIssue: OnlineKeyState?
    /// Yazı tanıma art arda hata veriyor; değeri diskteki boş yer (GB). macOS, diskte yer kalmayınca okuma modelini
    /// diske yazamaz ve her okumayı hata ile bitirir; altyazı sessizce hiç gelmez.
    @Published var readingFailedFreeGB: Double?
    private var readFailures = 0
    /// Son PS5 karesi (Ayarlar'daki bölge önizlemesi). Her karede değiştiği için modelin kendi yayınına girmez; yalnız
    /// önizlemeyi gösteren görünüm `framePreview`'u izler, öbür ekranlar her karede yeniden çizilmez.
    let framePreview = FramePreview()
    var lastFrame: CGImage? {
        get { framePreview.image }
        set { framePreview.image = newValue }
    }
    @Published var showAbout = false
    @Published var showSettings = false
    /// Nino: "Nino'ya Sor" sohbeti (yüzen robot düğmesi ve Ayarlar'daki satır açar).
    @Published var showAssistant = false

    private let services: AppServices
    private let store: AppStore
    private let defaults: UserDefaults
    /// Çalışan okuma hattının dilleri.
    @Published private(set) var activeLanguages: (source: String, target: String)?
    private var server = SubtitleServer(port: AppIdentity.serverPort)
    private var serverStarted = false
    /// Sunucunun gerçekten dinlediği port (8787 doluysa rastgele bir port).
    @Published private(set) var serverPort: UInt16 = AppIdentity.serverPort
    private var session: StreamControlling?
    private var keeper: KeeperControlling?
    @Published private var sleepActivity: NSObjectProtocol?
    private var pipeline: SubtitlePipeline?
    /// Ek alanları (görev, telefon, bildirim) okuyup çeviren; çeviri sürerken var.
    private var regionWatcher: RegionWatcher?
    /// Oyundaki altyazının son görüldüğü yer; deneme altyazısı TV'de oraya yerleşir.
    private var lastSubtitleBox: TextBox?
    /// Hatta aynı anda tek kare girer. Durdurma ve yeni hat kapıyı sıfırlar; takılan okuma hattı yeniden kurdurur.
    private var frameGate = FrameGate()
    private var wakeObserver: NSObjectProtocol?

    // Oyun paketleri ve ortak havuz
    /// Uygulamayla gelen ve ~/Library/Application Support/CouchSubs/packs klasöründeki paketler.
    let packs = GamePackLibrary(bundled: GamePackLibrary.bundledDirectory, user: GamePackLibrary.userDirectory)
    /// Ayarlarda listelenen paketler (açılışta arka planda yüklenince dolar).
    @Published var installedPacks: [GamePackLibrary.Info] = []
    private let pool: NinoPool
    private var poolDriver: NinoPoolDriver?
    /// Nino: sunucunun çeviri havuzu (Claude çevirileri; paketten sonra, cihazın çevirisinden önce).
    private let translations: TranslationPool
    private var translationSync: Task<Void, Never>?
    private let recentLines = PoolContext()
    /// Ek alanların (görev, bildirim) paket araması: yalnız oyun paketi, havuz yok.
    private var regionPackLookup: ((String) -> PackMatch?)?
    /// Sorun Bildir: havuzla aynı rastgele kuruluş kimliği (sunucu tuzlayıp özetler).
    func reportInstallID() async -> String { await pool.installID }
    /// Oynanan oyun: PS5'in bildirdiği, kullanıcının seçtiği ya da paketten tanınan (havuza giden satırlar bu oyunla gider).
    let gameChoice: GameChoice
    private var poolTimer: Task<Void, Never>?
    private var terminateObserver: NSObjectProtocol?
    /// Bağlıyken birkaç dakikada bir PS5'e çalışan oyunu sorar (havuza giden satırlar oyunla gider). Testlerde kapalı.
    private var gameProbe: Task<Void, Never>?
    private let probesGame: Bool
    static let gameProbeInterval: Duration = .seconds(120)
    /// Paket sunucusundan yeni ve güncellenen paketler (adres yapılandırılmadıysa nil; bkz. `PackUpdater`).
    private var packUpdates: Task<Void, Never>?
    private var packUpdater: PackUpdater?

    // Dublaj
    private var dubber: Dubber?
    /// Nino: PS5'ten gelen son saniyelerin sesi (dublajda konuşanı tanımak için).
    let voiceTracker = VoiceTracker()
    /// Model indiriliyorsa ilerleme (0…1).
    @Published var dubbingDownload: Double?
    @Published var dubbingError: String?
    @Published var dubbingModelReady = DubbingModelStore.isReady

    // Bilgisayar ekranındaki altyazı penceresi (bkz. AppModel+ComputerScreen.swift)
    /// Pencerede şu an görünen satırlar (TV'dekiyle aynı yığın).
    @Published var overlayLines: [SubtitleStack.Line] = []
    /// Penceredeki ek alan çevirileri (yukarıdan aşağı).
    @Published var overlayRegions: [OverlayRegion] = []
    /// Pencerenin yeri ve genişliği ayarlanıyor: örnek yazı görünür, tıklamalar geçmez.
    @Published var overlayAdjusting = false
    var overlayStack = SubtitleStack()
    /// "Yayın penceresi" açık: altyazı bilgisayar ekranında gösterilmese de satırlar yığına gelir (bkz. StreamWindow.swift).
    @Published var streamWindowOpen = false {
        didSet {
            guard streamWindowOpen != oldValue, !streamWindowOpen, !showsOnComputer else { return }
            overlayHide()
        }
    }
    /// Yayın penceresinin zemin rengi (chroma key ile silinir).
    @Published var streamBackground = StreamBackground.green {
        didSet { defaults.set(streamBackground.rawValue, forKey: StoreKey.streamBackground) }
    }
    /// "Ekranı çevir" çevirilerinin pencerede kalacağı an (`overlayClock` saatiyle); yoksa 0.
    var overlayScreenUntil: TimeInterval = 0
    var overlayTimer: Task<Void, Never>?
    /// Yığının saati (saniye); testlerde ileri sarılır.
    var overlayClock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    init(services: AppServices = LiveServices(), store: AppStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.services = services
        self.store = store
        self.defaults = defaults
        preferredCardID = defaults.string(forKey: "NinoCaptureCardID")
        let accountId = store.load(Data.self, for: StoreKey.accountId)
        let console = store.load(RegisteredConsole.self, for: StoreKey.console)
        let tv = store.load(LGTV.self, for: StoreKey.tv)
        let tvKeySaved = store.load(String.self, for: StoreKey.tvKey) != nil
        let paired = tv != nil && tvKeySaved
        // Nino: ilk açılışta (kayıtlı ayar yok) sistemin dili Arapçaysa çeviri dili Arapça seçilir.
        let loaded = defaults.data(forKey: StoreKey.settings).flatMap { try? JSONDecoder().decode(UserSettings.self, from: $0) }
            ?? { var first = UserSettings(); first.targetLanguage = TargetLanguage.preferred(); return first }()
        let ready = Self.setupIsComplete(store: store, accountId: accountId, console: console, paired: paired,
                                         readsWindow: loaded.frameSource == .remotePlayWindow)
        self.tvKeySaved = tvKeySaved
        hasLoginPasscode = LoginPasscode.normalized(store.load(String.self, for: StoreKey.loginPasscode)) != nil
        self.accountId = accountId
        self.console = console
        self.tv = tv
        let curated = loaded.withCuratedModels()
        settings = curated
        streamBackground = StreamBackground(stored: defaults.string(forKey: StoreKey.streamBackground))
        // Pencereler açılmadan önce: açılışta açık temanın bir an görünmesi olmaz.
        curated.appearance.apply()
        let poolFile = AppFolder.support.appendingPathComponent("pool.json")
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // PS5 bağlantı günlüğü (~/Library/Logs/Nino/remoteplay.log); eşleştirme olmazsa kullanıcı bunu gönderir.
        if !testing {
            RemotePlayLog.enable()
            RemotePlayLog.write("Nino \(AppIdentity.version), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
            // Klasörler bu açılışta taşındıysa/kopyalandıysa ya da taşınamadıysa günlükte görünsün.
            AppFolders.launchNotes.forEach(RemotePlayLog.write)
            // Altyazı günlüğü (aynı klasörde altyazi.log): okunan satırlar ve akıbetleri, görüntü duraklamaları.
            SubtitleLog.enable()
            // Ağ türü (kablo/Wi-Fi) ilk oturum başlamadan bilinsin.
            _ = NetworkWatcher.shared
            let stalls = VideoStallTracker()
            RemotePlayLog.observe { line in
                HealthRecorder.shared.remotePlayLine(line)
                if let note = stalls.note(line) { SubtitleLog.write(note) }
            }
        }
        // Nino'nun kendi havuzu (NinoPool); CouchSubs'tan kalan pool.json kuyruğu bir kez ona aktarılır.
        pool = NinoPool(directory: poolFile.deletingLastPathComponent().appendingPathComponent("pool", isDirectory: true),
                        app: AppIdentity.version, platform: "mac", enabled: curated.sharePool && !testing, legacyFile: poolFile)
        translations = TranslationPool(directory: poolFile.deletingLastPathComponent().appendingPathComponent("translations", isDirectory: true),
                                       app: AppIdentity.version, platform: "mac", language: curated.targetLanguage,
                                       enabled: curated.sharePool && !testing)
        probesGame = !testing
        gameChoice = GameChoice(defaults: defaults)
        if !testing {
            historyFile = SubtitleHistory.defaultFile
            history = SubtitleHistory.load(from: SubtitleHistory.defaultFile)
        }
        // Listede olmayan model varsayılana döndüyse ayar hemen kaydedilir.
        if curated != loaded, let data = try? JSONEncoder().encode(curated) { defaults.set(data, forKey: StoreKey.settings) }
        // Yarım kalan kurulum (ör. TV uygulaması kurulurken kapatıldı) PS5 kayıtlıysa TV adımından sürer.
        // Nino: oyunu bu bilgisayarda Remote Play penceresinde oynayan PS5 eşleştirmeden kurulumu bitirmiş olabilir.
        let windowReady = curated.videoSource != .ps5 && store.load(Bool.self, for: StoreKey.setupComplete) == true
        step = ready || windowReady ? .done : (accountId != nil && console != nil ? .tv : .welcome)
        savedKeys = Set(TranslationEngine.allCases.filter { engine in
            engine.storeKey.flatMap { store.load(String.self, for: $0) }?.isEmpty == false
        })
        attachServer()
        #if !APP_STORE
        // Çeviri sürerken, kurulum ekranındayken ve indirme sürerken güncelleme beklemeye alınır.
        AppUpdater.isBusy = { [weak self] in
            guard let self else { return false }
            return self.pipeline != nil || self.step != .done || self.dubbingDownload != nil
        }
        // "Yeniden başlat": çeviri sürüyorsa yeni sürüm açılınca kendiliğinden sürsün (takılınca yeniden açılmadaki işaret).
        AppUpdater.prepareForRestart = { [weak self] in
            guard let self, self.isRunning else { return }
            SubtitleLog.write("güncelleme kuruluyor; Nino yeniden açılıyor, çeviri kendiliğinden sürecek")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.resumeKey)
            UserDefaults.standard.synchronize()
            self.stop()
        }
        #endif
        // Nino: NinoPool oyunu her satırla birlikte alır (`offer(_:game:)`; bkz. connectPacks), ayrıca bildirilmez.
        gameChoice.onChange = { [weak self] game in
            // Nino: oyun tanınınca ekran hemen yenilenir (salondaki buzlu fon, alt şeritteki "GTA 6 Aktif"). Eskiden
            // ekran bir sonraki altyazıya kadar eski halinde kalıyordu: GTA 6 açıkken fon gelmiyordu.
            self?.objectWillChange.send()
            // Bu oyunun (havuzdan otomatik) paketi sunucuda yeni çıkmış olabilir.
            if game != nil { self?.packsForGame() }
            // Nino: yeni oyunun havuzdaki çevirileri hemen iner.
            if let self, self.pipeline != nil { self.startTranslationSync() }
        }
        gameChoice.packTitles = { [weak self] in GameCatalog.packGames(self?.installedPacks ?? []) }
        // Elle seçilen oyunda satırlar yalnız o oyunun paketinde aranır, paketi yoksa hiç aranmaz (#218).
        gameChoice.packs = packs

        // Paketler ilk altyazıyı bekletmesin diye açılışta arka planda yüklenir.
        let packs = self.packs
        Task.detached(priority: .utility) { [weak self] in
            let list = packs.packs
            await MainActor.run { self?.installedPacks = list }
        }
        // Testlerde havuz hiçbir şey göndermez, paket sunucusuna da sorulmaz.
        if !testing {
            startPool()
            startPackUpdates()
        }
    }

    /// Paket sunucusunun adresi yapılandırıldıysa (Info.plist `CSPacksBaseURL`) açılışta ve günde bir bakılır; PS5'te
    /// yeni bir oyun tanınınca da (`packsForGame`). Yeni paket inince paketler yeniden okunur.
    private func startPackUpdates() {
        guard let base = PackUpdater.configuredBaseURL() else { return }
        let state = AppFolder.support.appendingPathComponent("packs-remote.json")
        let updater = PackUpdater(baseURL: base, directory: GamePackLibrary.userDirectory, stateFile: state)
        packUpdater = updater
        let packs = self.packs
        packUpdates = Task.detached(priority: .background) { [weak self] in
            var force = true
            while !Task.isCancelled {
                let result = await updater.refresh(force: force)
                force = false
                await Self.applyPackRefresh(result, packs: packs, model: self)
                try? await Task.sleep(for: .seconds(PackUpdater.refreshInterval))
            }
        }
    }

    /// PS5'te yeni bir oyun başladı: o oyunun paketi sunucuda yeni çıkmış olabilir, son bakış eskiyse hemen bakılır.
    private func packsForGame() {
        guard let updater = packUpdater else { return }
        let packs = self.packs
        Task.detached(priority: .utility) { [weak self] in
            let result = await updater.refresh(maxAge: PackUpdater.gameCheckInterval)
            await Self.applyPackRefresh(result, packs: packs, model: self)
        }
    }

    private nonisolated static func applyPackRefresh(_ result: PackUpdater.Refresh, packs: GamePackLibrary, model: AppModel?) async {
        guard result.changed else { return }
        packs.reload()
        let list = packs.packs
        await MainActor.run { model?.installedPacks = list }
        RemotePlayLog.write("Paketler güncellendi: \((result.downloaded + result.removed).joined(separator: ", "))")
    }

    /// PS5'e bağlanınca çalışan oyun okunmaya başlar, bağlantı gidince bırakılır (havuz satırı oyunsuz gider).
    private func updateGameProbe(connected: Bool) {
        guard probesGame else { return }
        guard connected, let host = console?.host else {
            gameProbe?.cancel()
            gameProbe = nil
            gameChoice.consoleReported(nil)
            return
        }
        guard gameProbe == nil else { return }
        let services = self.services
        gameProbe = Task { [weak self] in
            var last: RunningGame?
            while !Task.isCancelled {
                let game = await services.runningGame(host: host)
                // Bu arada bağlantı bittiyse oyun yazılmaz (bırakılan oyun geri gelmesin).
                guard !Task.isCancelled else { break }
                self?.gameChoice.consoleReported(game)
                if game != last, let game {
                    // Paket sunucusuna bakılması `gameChoice.onChange`te.
                    SubtitleLog.write("PS5'te çalışan oyun: \(game.name ?? "?") (\(game.titleId ?? "?"))")
                }
                last = game
                try? await Task.sleep(for: Self.gameProbeInterval)
            }
        }
    }

    /// Kurulum bitmiş mi. "Bitti" yalnız sihirbazın sonuna gelinince kaydedilir (TV adımı başarıyla geçildi ya da
    /// "TV'm yok" seçildi). Sihirbaz başlarken `false` yazılır: Samsung'da TV eşleşip uygulama kurulurken Nino
    /// kapatılırsa eşleşme kayıtlı olsa da kurulum bitmiş sayılmaz. Hiç kayıt yoksa (beta.25'ten önce kurulmuş)
    /// eskisi gibi eşleşmiş TV yeter ve "bitti" kaydedilir. Görüntü PS Remote Play penceresinden okunuyorsa PS5 eşleşmesi
    /// (hesap, PS5 kaydı) gerekmez; sihirbaz açılmaz, kayıt da değiştirilmez (PS5'e dönülürse eski durum geçerlidir).
    static func setupIsComplete(store: AppStore, accountId: Data?, console: RegisteredConsole?, paired: Bool,
                                readsWindow: Bool = false) -> Bool {
        if readsWindow { return true }
        let saved = store.load(Bool.self, for: StoreKey.setupComplete)
        let ready = accountId != nil && console != nil && (saved ?? paired)
        if saved == nil { store.save(ready, for: StoreKey.setupComplete) }
        return ready
    }

    /// Sunucunun TV sayısını, altyazı yerini ve bilgisayar ekranına giden olayları bağlar (sunucu yeniden kurulunca da).
    private func attachServer() {
        server.onClientsChanged = { [weak self] count in self?.tvClients = count }
        server.sendsToTV = showsOnTV
        server.onEvent = { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.overlayReceive(event) } }
        }
    }

    /// Havuz: satırlar diskte kuyrukta bekler, sunucu onaylayınca silinir; ağ gelince ve dakikada bir denenir.
    private func startPool() {
        let driver = NinoPoolDriver(pool: pool)
        poolDriver = driver
        driver.start()
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                                   queue: nil) { _ in driver.stop() }
    }

    /// Paketler yalnız İngilizce→Türkçede ve ayar açıkken kullanılır. Pakette olmayan İngilizce satır havuza önerilir
    /// (paketler kapalıysa da yalnız hiçbir pakette olmayanlar).
    private func connectPacks(to pipeline: SubtitlePipeline) {
        let packs = self.packs
        let pool = self.pool
        let translations = self.translations
        let store = translations.store
        let recent = recentLines
        let active = settings.gamePacks && settings.sourceLanguage == "en" && settings.targetLanguage == "tr"
        // Nino: sunucunun çeviri havuzu bütün dillerde, kaynak İngilizceyken ve ortak havuz açıkken.
        let pooled = settings.sharePool && settings.sourceLanguage == "en"
        let sense = gameChoice.sense
        // Havuz öncelikli oyunda (GTA 6) başka oyunların paketlerine bakılmaz: çeviri yalnız havuzdan (Claude). Havuzdaki
        // çeviri ortak havuz kapalıyken de kullanılır.
        let poolFirst: @Sendable () -> Bool = { translations.isPoolFirst(translations.poolGame(sense.current?.name, packs.searchScope)) }
        let english = settings.sourceLanguage == "en"
        pipeline.packLookup = !(active || pooled || english) ? nil : { text in
            let first = poolFirst()
            if active, !first, let found = packs.match(text) { return found }
            guard pooled || first, let translated = store.match(text) else { return nil }
            return PackMatch(text: translated, spoken: [SpokenLine(english: text, turkish: translated)])
        }
        pipeline.packName = { packs.searchScope }
        // Nino: havuz öncelikli oyunda (GTA 6) telefonun ekranı aranır; içindeki yazılar altyazı sayılmaz.
        // Oyun henüz tanınmadıysa (Nino telefon açıkken başladı; telefon ekranından oyun tanınmaz) son oturumdaki oyun geçerlidir.
        let lastGameKey = Self.lastGamePoolFirstKey
        let phoneGame: @Sendable () -> Bool = {
            if poolFirst() { return true }
            return sense.current == nil && UserDefaults.standard.bool(forKey: lastGameKey)
        }
        pipeline.phonePanels = english ? phoneGame : nil
        // Ek alanlar yalnız pakette aranır; havuza gitmez (arayüz ve bildirim yazıları kişisel olabilir).
        regionPackLookup = active ? { packs.match($0) } : nil
        regionWatcher?.packLookup = regionPackLookup
        guard settings.sourceLanguage == "en" else {
            pipeline.onPackMiss = nil
            return
        }
        pipeline.onPackMiss = { [weak pipeline] text in
            guard active || poolFirst() || packs.match(text) == nil else { return }
            // Paketten tanınan oyun; yoksa PS5'in bildirdiği ya da kullanıcının seçtiği oyun (`GameChoice`).
            let game = packs.searchScope ?? sense.current?.name
            Task { await pool.offer(text, game: game) }
            // Havuz öncelikli oyunda ortak havuz kapalı olsa da sorulur; çevirmen aynı isteği bekler (aynı satır iki kez
            // sorulmaz), süresinde gelmeyen çeviri de gelince ekrandakinin yerine konur.
            let poolGame = translations.poolGame(sense.current?.name, game)
            guard pooled || translations.isPoolFirst(poolGame) else { return }
            let context = recent.add(text)
            // Sunucu o an çevirir (Claude); satır hâlâ ekrandaysa cihazın çevirisinin yerine konur.
            Task {
                guard let better = await translations.translate(text, context: context, game: poolGame) else { return }
                await MainActor.run { pipeline?.upgrade(source: text, translation: better) }
            }
        }
    }

    /// Nino: oyun bilinmiyorsa (PS5 bildirmiyor, hazır paketten de tanınmadı) Remote Play karesinden tanınır: sunucuda
    /// Claude kareye bakıp oyunun adını söyler. Çeviri başladıktan ~8 sn sonra, olmazsa dakikada bir, en çok 6 kez.
    /// Tanıdıktan sonra arka planda yedek olarak yeniden bakar: 5 dk sonra bir kez doğrular (başka bir sahneden), sonra
    /// 20 dakikada bir (oyun değiştirilmiş olabilir). Altyazılar havuzdan da oyunu tanıtır; bu yalnız ek güvence.
    private var identifyTask: Task<Void, Never>?
    private var identifyTries = 0
    private var identifyChecks = 0
    private var identifyLast = Date()

    private func identifyGameIfNeeded(_ frame: CGImage) {
        // Paketten tahmin edilen oyun kesin değildir (GTA 6 satırları başka oyunun paketine benzeyebiliyor): havuz öncelikli
        // oyun bilinmiyorsa ekrandan tanıma kapsam doluyken de denenir.
        guard settings.sharePool, settings.sourceLanguage == "en", identifyTask == nil,
              packs.searchScope == nil || !translations.isPoolFirst(translations.poolGame(gameChoice.sense.current?.name, packs.searchScope)) else { return }
        let known = gameChoice.sense.current
        let wait: TimeInterval
        if known == nil {
            guard identifyTries < 6 else { return }
            wait = identifyTries == 0 ? 8 : 60
        } else if gameChoice.sense.source == .screen {
            guard identifyChecks < 12 else { return }
            wait = identifyChecks == 0 ? 5 * 60 : 20 * 60
        } else {
            return  // konsol, kullanıcı ya da hazır paket söylüyor; bakmaya gerek yok
        }
        guard Date().timeIntervalSince(identifyLast) > wait else { return }
        identifyLast = Date()
        if known == nil { identifyTries += 1 } else { identifyChecks += 1 }
        guard let jpeg = Self.smallJPEG(frame, maxWidth: 768) else { return }
        let translations = self.translations
        identifyTask = Task { [weak self] in
            let name = await translations.identify(jpeg: jpeg)
            guard let self else { return }
            self.identifyTask = nil
            guard let name else {
                SubtitleLog.write(known == nil ? "oyun ekrandan tanınamadı (deneme \(self.identifyTries))"
                                               : "oyun yeniden bakışta seçilemedi; \(known!.name) olarak kalıyor")
                return
            }
            if let known, NinoPool.gameID(known.name) == NinoPool.gameID(name) {
                SubtitleLog.write("oyun doğrulandı: \(name)")
                return
            }
            SubtitleLog.write(known == nil ? "oyun ekrandan tanındı: \(name)" : "oyun değişmiş: \(known!.name) → \(name)")
            self.gameChoice.seen(name)
            self.startTranslationSync()
        }
    }

    /// Çevirinin başındaki oyun simgeleri (◆, ✦, OCR'ın okuduğu işaretler) atılır; Türkçede yalnız metin gösterilir.
    static func withoutLeadingSymbols(_ text: String) -> String {
        String(text.drop { !$0.isLetter && !$0.isNumber && $0 != "\"" && $0 != "'" && $0 != "(" })
    }

    /// Kareyi küçültüp JPEG yapar (oyun tanıma için; ~50 KB).
    static func smallJPEG(_ image: CGImage, maxWidth: Int) -> Data? {
        let scale = min(1, Double(maxWidth) / Double(image.width))
        let width = Int(Double(image.width) * scale), height = Int(Double(image.height) * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, small, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Nino: oyunun havuzdaki çevirilerini oyun başlarken ve birkaç dakikada bir indirir.
    private func startTranslationSync() {
        translationSync?.cancel()
        guard settings.sharePool, settings.sourceLanguage == "en" else { return }
        let (translations, packs, sense) = (translations, packs, gameChoice.sense)
        translationSync = Task {
            await translations.ping(game: packs.searchScope ?? sense.current?.name)
            await translations.sync(game: packs.searchScope ?? sense.current?.name, force: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await translations.ping(game: packs.searchScope ?? sense.current?.name)
                await translations.sync(game: packs.searchScope ?? sense.current?.name)
            }
        }
    }

    // MARK: - Sihirbaz

    /// Tasarım denemesi: deneme derlemesinde `-NinoFreeNav YES` ile açılınca giriş ve eşleştirme beklenmez.
    static var freeNavigation: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NinoFreeNav")
        #else
        false
        #endif
    }

    var canAdvance: Bool {
        #if DEBUG
        // Tasarım denemesi için: open Nino.app --args -NinoFreeNav YES → giriş ve eşleştirme yapmadan her adımda Devam.
        if Self.freeNavigation, step != .done, step != .welcome || welcomeConsole != nil { return true }
        #endif
        return switch step {
        case .welcome: welcomeConsole != nil
        case .secondAccount, .test, .betterTranslation: true
        case .psnLogin: accountId != nil
        case .console: console != nil
        case .tv: hasTV || settings.output == .computer
        case .done: false
        }
    }

    /// Nino: sihirbazın ilk ekranındaki "Bu bilgisayarda PS Remote Play ile oynuyorum": PS5 eşleştirmesi, ikinci hesap ve TV
    /// adımları atlanır; görüntü Remote Play penceresinden okunur, çeviri pencerenin üstünde gösterilir.
    func useGameWindowSetup() {
        settings.gameConsole = .ps5
        settings.videoSource = .window
        step = .done
    }

    /// Nino: sihirbazın ilk ekranındaki "Xbox'ta oynuyorum": Xbox ev yayını bu bilgisayarda Greenlight ya da tarayıcıda
    /// xbox.com/play ile açılır (Microsoft hesabına orada girilir); Nino o pencereyi okur, çeviriyi üstünde gösterir.
    /// PS5 eşleştirmesi ve ikinci hesap adımları atlanır.
    func useXboxWindowSetup() {
        settings.gameConsole = .xbox
        settings.videoSource = .window
        welcomeConsole = .xbox
        // Altyazı TV'de gösterilecekse TV eşleştirilir ("TV'm yok" seçilirse bu bilgisayarda).
        step = .tv
    }

    /// Nino: sihirbazın ilk ekranındaki "Yakalama kartım var": PS5 eşleştirmesi ve ikinci hesap atlanır; görüntü karttan
    /// okunur. Altyazı bu bilgisayarda oyunun üstünde gösterilir (TV'ye göndermek sonra ayarlardan seçilir).
    func useCaptureCardSetup() {
        cardSetupActive = true
    }

    /// Kart rehberinden PS5 adımlarına geri dönülür.
    func cancelCaptureCardSetup() {
        cardSetupActive = false
    }

    /// Kart rehberi bitti. TV seçildiyse TV eşleştirilmemişse TV adımına, sonra denemeye geçilir; bilgisayar seçildiyse
    /// doğrudan denemeye. Ayarlardan açılan rehberde yalnız seçim kaydedilir.
    func finishCaptureCardSetup(toTV: Bool) {
        settings.videoSource = .card
        settings.output = toTV ? .tv : .computer
        guard cardSetupActive else { return }
        cardSetupActive = false
        step = toTV && !hasTV ? .tv : .test
    }

    /// Menü çubuğundan: oyun penceresini tam ekrana alır ya da tam ekrandan çıkarır.
    func toggleCardFullScreen() {
        (session as? CaptureCardStream)?.toggleFullScreen()
    }

    /// Oyun bu Mac'te tam ekran gösteriliyor mu (yakalama kartı, altyazı bilgisayarda, çeviri sürüyor).
    var showsCardPlayer: Bool { isRunning && usesCaptureCard && showsOnComputer }

    /// Nino: ilk ekrandaki konsol kartı: o konsolun karşılamasına geçer.
    func chooseWelcomeConsole(_ console: GameConsole) {
        welcomeConsole = console
        // PS5 yolu Remote Play ile eşleştirmedir; Xbox'tan geri dönüldüyse pencere yolu bırakılır.
        if console == .ps5 { settings.gameConsole = .ps5; settings.videoSource = .ps5 }
    }

    func advance() {
        // Nino: Xbox karşılamasından sonra PS5 adımları (ikinci hesap, PSN, eşleştirme) atlanır.
        if step == .welcome, welcomeConsole == .xbox { useXboxWindowSetup(); return }
        guard canAdvance, let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func back() {
        // Nino: konsolun karşılamasından konsol seçimine.
        if step == .welcome, welcomeConsole != nil { welcomeConsole = nil; return }
        // Nino: Xbox kısa yolundan gelen PS5 adımlarına düşmez.
        if usesXboxWindow, step == .tv { step = .welcome; return }
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Ücretsiz Gemini anahtarı kayıtlı ve çeviri Gemini ile yapılıyor ("Daha iyi çeviri" adımı tamam).
    var usesFreeGemini: Bool { settings.translationEngine == .gemini && hasKey(.gemini) }

    /// Ayarlardaki "Ücretsiz anahtar al": Gemini seçilir, anahtar alanı görünür (anahtar gelene dek ücretsiz çeviri sürer).
    func chooseFreeGemini() { settings.translationEngine = .gemini }

    /// Giriş penceresinin yönlendirmesinden hesap kimliği. Her hata kendi iletisiyle (`DetailedError`) döner ve
    /// remoteplay.log'a yazılır; genel "Giriş tamamlanmadı" yalnız son çaredir.
    func completePSNLogin(redirect: URL) async throws {
        let id: Data
        do {
            id = try await services.accountId(fromRedirect: redirect)
        } catch let error as PSNAccount.PSNError {
            RemotePlayLog.write("PSN girişi başarısız: \(error)")
            throw AppError.login(error)
        } catch {
            RemotePlayLog.write("PSN girişi beklenmedik hatayla bitti: \(error)")
            throw DetailedError(error: .invalidLogin, detail: error.localizedDescription)
        }
        RemotePlayLog.write("PSN girişi tamam")
        accountId = id
        store.save(id, for: StoreKey.accountId)
    }

    /// Giriş penceresi yönlendirme olmadan kapandı: kullanıcı kapattı (`problem` nil) ya da Sony'nin sayfası açılamadı.
    func loginWindowError(problem: String?) -> Error {
        RemotePlayLog.write("PSN giriş penceresi giriş bitmeden kapandı\(problem.map { ": \($0)" } ?? "")")
        guard let problem else { return AppError.loginWindowClosed }
        return DetailedError(error: problem.contains("429") ? .loginRateLimited : .loginPageFailed, detail: problem)
    }

    func discoverConsoles() async -> [ConsoleInfo] { await services.discoverConsoles() }

    /// PS5'e kayıt olur. Her başarısızlık kullanıcıya anlatılır (`AppError` ya da `DetailedError`); sessiz dönüş yok.
    func register(host: String, pin: String) async throws {
        let typed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { throw AppError.missingConsole }
        // Elle yazılan adres temizlenir ("192.168.1.5:9295", "http://…", virgüllü yazım); adres değilse libchiaki'ye
        // gitmeden söylenir.
        guard let host = ManualAddress.normalize(typed) else {
            RemotePlayLog.write("PS5 kaydı: geçersiz adres yazıldı: \(typed)")
            throw AppError.badAddress
        }
        // 0.0.0.0 gibi PS5'in adresi olamayacak bir adres hiçbir zaman kaydedilmez.
        guard ConsoleAddress.isUsable(host) else {
            RemotePlayLog.write("PS5 kaydı: kullanılamaz adres yazıldı: \(typed)")
            throw AppError.badAddress
        }
        guard let value = Registration.pin(from: pin) else { throw AppError.invalidPin }
        guard let accountId else { throw AppError.missingAccount }
        let registered: RegisteredConsole
        do {
            registered = try await services.register(host: host, accountId: accountId, pin: value)
        } catch let error as Registration.RegistrationError {
            throw DetailedError(error: AppError(error.kind), detail: error.detail)
        } catch {
            RemotePlayLog.write("PS5 kaydı beklenmedik hatayla bitti (\(host)): \(error)")
            throw DetailedError(error: .registrationFailed, detail: error.localizedDescription)
        }
        console = registered
        store.save(registered, for: StoreKey.console)
        // Günlükte eşleşmenin kaydedildiği de görünsün (kullanıcılar başarıyı fark etmeyip yeniden bağlanıyordu).
        RemotePlayLog.write("PS5 kaydı kaydedildi (\(registered.host)): \(registered.name)")
    }

    /// Eşleşmeden kısa süre sonra kendiliğinden sonraki adıma geçilir. Kullanıcı bu arada Geri'ye bastıysa ya da
    /// adım değiştiyse hiçbir şey yapılmaz (yalnız PS5 adımından ilerler).
    func continueAfterPairing() {
        guard step == .console, console != nil else { return }
        advance()
    }

    /// "Hesap kimliğini elle gir": Sony girişi açılamayan kullanıcılar (ör. servis sağlayıcı engelliyor) PSN hesap
    /// kimliğini base64 olarak (8 bayt, 12 karakter) yazar. Web girişiyle aynı biçimde saklanır. Geçersizse false.
    @discardableResult
    func useManualAccountId(_ value: String) -> Bool {
        guard let id = Self.accountId(fromBase64: value) else { return false }
        RemotePlayLog.write("PSN hesap kimliği elle girildi")
        accountId = id
        store.save(id, for: StoreKey.accountId)
        return true
    }

    /// Base64 PSN hesap kimliği: boşluklar atılır, çözülen değer tam 8 bayt olmalı (12 karakter).
    static func accountId(fromBase64 value: String) -> Data? {
        let trimmed = value.filter { !$0.isWhitespace }
        guard trimmed.count == 12, let data = Data(base64Encoded: trimmed), data.count == 8 else { return nil }
        return data
    }

    func discoverTVs() async -> [LGTV] { await services.discoverTVs() }

    /// Eşleşmiş bir TV var. Anahtarın varlığı saklanır; ana ekran her çizimde Anahtarlık'a sormasın.
    var hasTV: Bool { tv != nil && tvKeySaved }

    /// Sihirbazdaki "TV'm yok": TV aranmaz ve kurulmaz, altyazı bilgisayar ekranında gösterilir; sonraki adıma geçilir.
    func useComputerScreen() {
        settings.output = .computer
        advance()
    }

    /// Sihirbazdaki "İkinci hesap yok mu?": görüntü bu Mac'teki PS Remote Play penceresinden okunur. PSN girişi, PS5
    /// eşleştirmesi ve TV adımı atlanır, kurulum biter; TV eşleşmemişse altyazı bilgisayar ekranında gösterilir (TV ve
    /// daha iyi çeviri sonra Ayarlar'dan).
    func useRemotePlayWindow() {
        settings.gameConsole = .ps5
        settings.videoSource = .window
        if !hasTV { settings.output = .computer }
        step = .done
    }

    /// Görüntü PS5'ten (ikinci hesap) alınacak ama hesap ya da PS5 eşleşmesi yok: Ayarlar'da "Hesabı bağla" görünür.
    var needsPS5Link: Bool { settings.videoSource == .ps5 && (accountId == nil || console == nil) }

    /// Ayarlar › Görüntü kaynağı › "Hesabı bağla": sihirbaz ikinci hesap adımından açılır (PSN girişi, PS5 eşleştirmesi).
    func linkPS5Account() { step = .secondAccount }

    /// Seçilen Remote Play uygulaması bu Mac'te kurulu mu (Ayarlar'daki "Kurulu" / "İndir" satırları).
    func remotePlayInstalled(_ app: RemotePlayApp) -> Bool { services.remotePlayInstalled(app) }

    /// Görüntü Remote Play penceresinden okunacak ama seçilen uygulama kurulu değil: ana ekran nereden indirileceğini söyler.
    var remotePlayMissing: Bool { usesGameWindow && !usesXboxWindow && !services.remotePlayInstalled(settings.remotePlayApp) }

    /// "PS Remote Play'i indir" / "chiaki-ng'yi indir": resmi indirme sayfası tarayıcıda açılır.
    func openDownload(for app: RemotePlayApp) {
        NSWorkspace.shared.open(app == .chiaki ? RemotePlayWindowStream.chiakiDownloadURL : RemotePlayWindowStream.sonyDownloadURL)
    }

    func pair(_ tv: LGTV) async throws {
        try await startServer()
        let savedKey = store.load(String.self, for: StoreKey.tvKey)
        let pairing = try await services.pairTV(tv, key: savedKey, server: serverAddress(for: tv))
        if self.tv?.brand != tv.brand || (tv.brand != .androidTV && self.tv?.host != tv.host) {
            store.remove(StoreKey.tvAppVersion)
        }
        self.tv = tv
        store.save(tv, for: StoreKey.tv)
        // Samsung jetonla gelen bağlantıda jetonu yeniden göndermeyebilir; boş jeton saklı olanı silmez (#40).
        store.save(SamsungTokenHolder.keptToken(stored: savedKey, received: pairing.key), for: StoreKey.tvKey)
        tvKeySaved = true
        tvAppMissing = !pairing.launched
        // Daha önce "TV'm yok" seçildiyse TV bağlanınca altyazı TV'ye geçer (Nino: bilgisayarda pencere açılmaz).
        if settings.output == .computer { settings.output = .tv }
        if tv.brand == .lg {
            await refreshTVApp()
        } else {
            // Samsung girişi ya da Android onayı dakikalar sürebilir; eşleşme beklemesin.
            Task { await refreshTVApp() }
        }
    }

    // MARK: - TV uygulamasını kurma

    /// Geliştirici modu açık TV'de uygulamayı eksikse kurar, eskiyse günceller.
    /// Anahtar yoksa ve uygulama çalışıyorsa kullanıcıdan bir şey istenmez.
    func refreshTVApp() async {
        guard let tv, !refreshingTVApp else { return }
        refreshingTVApp = true
        defer { refreshingTVApp = false }
        switch tv.brand {
        case .lg: await refreshLGApp(tv)
        case .samsung: await refreshSamsungApp(tv)
        case .androidTV: await refreshAndroidApp(tv)
        }
    }

    /// Samsung ya da Android TV'ye daha önce Nino'ın kurduğu sürüm.
    private var installedAppVersion: String? { store.load(String.self, for: StoreKey.tvAppVersion) }

    private func needsInstall(_ bundled: BundledTVApp) -> Bool {
        guard let installed = installedAppVersion else { return true }
        return DevModeInstaller.isNewer(bundled.version, than: installed)
    }

    private func refreshLGApp(_ tv: LGTV) async {
        guard let bundled = services.bundledTVAppVersion else { return }
        let devModeOn = await services.isDevModeOn(host: tv.host)
        // Beklerken parola kartından kurulum başladıysa kart geri "geliştirici modu kapalı"ya dönmez.
        if tvApp == .working { return }
        guard devModeOn else {
            tvApp = tvAppMissing ? .devModeOff : .unknown
            return
        }
        guard let devKey = store.load(String.self, for: StoreKey.tvDevKey) else {
            tvApp = tvAppMissing ? .needsPassphrase(error: nil) : .unknown
            return
        }
        await install(tv: tv, devKey: devKey, bundled: bundled)
    }

    /// Samsung: geliştirici modu açıksa TV'deki Nino sürümüne bakar, yoksa ya da eskiyse imzalayıp kurar
    /// (sertifika yoksa Samsung girişi istenir). Önceden yalnız bu Mac'in kurduğu sürüm hatırlanıyordu; TV'de eski
    /// kalan uygulama (ör. 0.9.10 gelirken 0.9.7) hiç güncellenmiyordu.
    private func refreshSamsungApp(_ tv: LGTV) async {
        guard let bundled = services.bundledApp(for: .samsung) else { return }
        let remembered = !needsInstall(bundled)
        let current = TVAppState.upToDate(installedAppVersion ?? bundled.version)
        // TV 8001'de geliştirici modunu ve Host PC IP'yi söyler (Android ve iPhone uygulaması da buna bakar). Host PC IP
        // bu Mac'inki değilse TV sdb el sıkışmasında bağlantıyı keser (#343); sdb hiç denenmez, iki adres söylenir.
        // Nino: hangi adımın eksik olduğu tek tek ayırt edilir (mod kapalı, adres yanlış/sıfırlı/ters, TV yeniden
        // başlatılmamış); kart yalnız o adımı anlatır.
        let check = await services.checkSamsung(host: tv.host)
        let setup = SamsungSetupCheck(info: check.info, computer: check.computerAddress,
                                      portOpen: await services.isSamsungDevModeOn(host: tv.host))
        if setup != samsungSetup { samsungSetup = setup }
        if samsungModelYearHost != tv.host, check.info != nil {
            samsungModelYear = await services.samsungModelYear(host: tv.host)
            samsungModelYearHost = tv.host
        }
        let ignoreAddress = samsungIgnoreAddressOnce
        samsungIgnoreAddressOnce = false
        switch setup.problem {
        case .tvNotResponding, .developerModeOff, .needsRestart:
            // Geliştirici modu kapalıyken (ya da TV yeniden başlamadan) TV'ye sorulamaz; bu Mac'in kurduğu sürüme bakılır.
            tvApp = remembered ? current : .devModeOff
            return
        case .hostPcIpLoopback, .hostPcIpPadded, .hostPcIpReversed, .hostPcIpWrong:
            let tvIp = check.info?.developerIp ?? "?"
            let computer = check.computerAddress ?? "?"
            if ignoreAddress {
                // TV adresi yanlış bildirebilir; kullanıcı isterse kurulum bir kez yine de denenir.
                TVInstallLog.write("TV'deki Host PC IP (developerIP) \(tvIp), bu Mac'in adresi \(computer); kullanıcı yine de denemek istedi.")
                break
            }
            let next = remembered ? current : TVAppState.hostPcMismatch(tvIp: tvIp, computer: computer)
            if tvApp != next {
                TVInstallLog.write("TV'deki Host PC IP (developerIP) \(tvIp), bu Mac'in TV'ye giden adresi \(computer); kurulum denenmedi.")
            }
            tvApp = next
            return
        case nil:
            break
        }
        // Güncel bilinen uygulamada denetim sessiz sürer; kart ancak kurulum başlarsa değişir.
        tvApp = remembered ? current : .working
        samsungCheckRunning = true
        defer { samsungCheckRunning = false }
        do {
            let result = try await services.installSamsungApp(host: tv.host, app: bundled) { [weak self] event in
                Task { @MainActor in self?.installEvent(event) }
            }
            store.save(result.version, for: StoreKey.tvAppVersion)
            tvApp = .upToDate(result.version)
            if result.installed { await openTVAppAfterInstall(tv) }
        } catch let failure as DevModeFailure where remembered && failure.error == .unreachable {
            // TV sdb bağlantısını kabul etmedi (ör. Host PC IP değişti): çalışan uygulama "kurulamadı" diye gösterilmez.
            tvApp = current
        } catch DevModeError.unreachable where remembered {
            tvApp = current
        } catch {
            tvApp = Self.failedState(error)
        }
    }

    /// Samsung kurulumu "TV bu bilgisayarı kabul etmedi" ile durduğunda TV'nin durumuna yeniden bakar. Eksik adım
    /// belli olduysa kart onu gösterir; TV yeniden başladıysa (kurulum kapısı kapanıp açıldı) kurulum kendiliğinden
    /// yeniden denenir. Kurulum denemez, yalnız TV'ye sorar: kart üç saniyede bir çağırabilir.
    func recheckSamsungSetup() async {
        guard let tv, tv.brand == .samsung, !samsungCheckRunning, !refreshingTVApp else { return }
        guard case .failed(.unreachable, _) = tvApp else { return }
        let check = await services.checkSamsung(host: tv.host)
        let setup = SamsungSetupCheck(info: check.info, computer: check.computerAddress,
                                      portOpen: await services.isSamsungDevModeOn(host: tv.host))
        let before = samsungSetup
        if setup != before { samsungSetup = setup }
        guard case .failed(.unreachable, _) = tvApp else { return }
        if setup.problem != nil || (before?.portOpen == false && setup.portOpen) { await refreshTVApp() }
    }

    /// "Yine de dene": TV'nin bildirdiği Host PC IP bu Mac'inki değil görünse de kurulumu bir kez dener.
    func installSamsungAnyway() async {
        samsungIgnoreAddressOnce = true
        await refreshTVApp()
    }

    /// Geliştirici modu kodunu (1 2 3 4 5) TV'ye bu Mac'ten yazar. Kullanıcı önce TV'de kodun yazılacağı yeri açar.
    /// Her modelde çalışmaz; sonuç TV ekranında görülür (pencere açılır ya da açılmaz).
    func typeSamsungDevCode() async {
        guard let tv, tv.brand == .samsung, samsungCode != .sending else { return }
        samsungCode = .sending
        do {
            let savedKey = store.load(String.self, for: StoreKey.tvKey)
            let token = try await services.typeSamsungCode(tv: tv, key: savedKey)
            store.save(SamsungTokenHolder.keptToken(stored: savedKey, received: token), for: StoreKey.tvKey)
            TVInstallLog.write("Geliştirici modu kodu TV'ye kumanda bağlantısından yazıldı (\(tv.host)).")
            samsungCode = .sent
        } catch {
            TVInstallLog.write("Geliştirici modu kodu TV'ye yazılamadı (\(tv.host)): \(error)")
            samsungCode = .failed
        }
    }

    /// Kurulumun TV'yi değiştiren adımları (yalnız sürüm okumak değil).
    static func isInstallStep(_ step: String) -> Bool {
        ["signin", "certificate", "signing", "installing", "uninstalling", "play"].contains(step)
    }

    /// Kurulum hatası ve yardımcının verdiği sebep (TV'nin kurulum çıktısı, Samsung'un yanıtı); sebep de gösterilir.
    static func failedState(_ error: Error) -> TVAppState {
        guard let failure = error as? DevModeFailure else { return .failed(error as? DevModeError ?? .installFailed) }
        let reason = failure.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(failure.error, reason: reason.isEmpty ? nil : reason)
    }

    /// Android TV: ağda ADB'si açık TV'yi bulur, uygulamayı kurar ve açar.
    private func refreshAndroidApp(_ tv: LGTV) async {
        guard let bundled = services.bundledApp(for: .androidTV) else { return }
        // Nino: TV uygulaması zaten bağlı ve güncelse dokunulmaz. Eskiden her "Başlat"ta yeniden açılıyor, kullanıcı oyundayken
        // (PS5 girişinde) TV'yi Nino'nun bilgi ekranına atıyordu.
        if tvClients > 0, !needsInstall(bundled) {
            tvApp = .upToDate(installedAppVersion ?? bundled.version)
            return
        }
        var host = tv.host
        let reachable = host.isEmpty ? false : await services.isAndroidDebugOn(host: host)
        if !reachable {
            // Uygulama kuruluysa ve TV'de hata ayıklama kapalıysa yapılacak bir şey yok.
            if !needsInstall(bundled) {
                tvApp = .upToDate(installedAppVersion ?? bundled.version)
                return
            }
            guard let found = await services.scanAndroidTVs().first else {
                tvApp = .devModeOff
                return
            }
            host = found
        }
        tvApp = .working
        do {
            let version = try await services.installAndroidApp(host: host, app: bundled) { [weak self] event in
                Task { @MainActor in self?.installEvent(event) }
            }
            // TV'nin adresi bundan sonra sürüm denetimi için kullanılır.
            let located = LGTV(name: tv.name, host: host, brand: .androidTV)
            self.tv = located
            store.save(located, for: StoreKey.tv)
            store.save(version, for: StoreKey.tvAppVersion)
            tvApp = .upToDate(version)
        } catch {
            tvApp = Self.failedState(error)
        }
    }

    private func installEvent(_ event: TVInstallEvent) {
        // Kurulum bittikten sonra gelen geç olay sonucu ezmesin.
        switch tvApp {
        case .working, .signIn, .approveOnTV: break
        default: if !samsungCheckRunning { return }
        }
        switch event {
        case .signIn(let url):
            tvApp = .signIn(url)
            openInBrowser(url)
        case .approveOnTV:
            tvApp = .approveOnTV
        case .progress(let step):
            if case .signIn = tvApp {
                tvApp = .working
            } else if tvApp != .working, Self.isInstallStep(step) {
                // Sürüm denetimi güncelleme kurmaya başladı: kart "kuruluyor"a geçer.
                tvApp = .working
            }
        }
    }

    /// Seçili TV'ye uygulamayı Nino kurabilir mi (paket uygulamayla geldi mi)?
    var canInstallTVApp: Bool {
        guard let tv else { return false }
        return tv.brand == .lg ? services.bundledTVAppVersion != nil : services.bundledApp(for: tv.brand) != nil
    }

    /// Testlerde tarayıcı açılmasın diye değiştirilebilir.
    var openInBrowser: (URL) -> Void = { url in
        // Tarayıcı öne gelsin: sayfa arkada açılınca kullanıcı giriş penceresini görmüyordu. Açılmazsa kart "Sayfayı
        // yeniden aç" ve "Bağlantıyı kopyala" ile bekler; günlükte de görünür.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            if let error { TVInstallLog.write("Tarayıcı açılamadı: \(url.absoluteString): \(error.localizedDescription)") }
        }
    }

    /// Samsung'da geliştirici modunda "Host PC IP" olarak yazılacak bu Mac'in adresi.
    var computerAddress: String? {
        Self.localAddress(near: tv?.host.isEmpty == false ? tv!.host : nil)
    }

    /// Key Server'dan anahtarı alır (TV ekranındaki parolayla) ve uygulamayı kurar.
    func installTVApp(passphrase: String) async {
        guard let tv, let bundled = services.bundledTVAppVersion else { return }
        tvApp = .working
        do {
            let devKey = try await services.fetchDevKey(host: tv.host, passphrase: passphrase.trimmingCharacters(in: .whitespacesAndNewlines))
            store.save(devKey, for: StoreKey.tvDevKey)
            await install(tv: tv, devKey: devKey, bundled: bundled)
        } catch {
            tvApp = .needsPassphrase(error: error as? DevModeError ?? .installFailed)
        }
    }

    private func install(tv: LGTV, devKey: String, bundled: String) async {
        tvApp = .working
        do {
            let installed = try await services.installedTVAppVersion(host: tv.host, devKey: devKey)
            if let installed, !DevModeInstaller.isNewer(bundled, than: installed) {
                tvApp = .upToDate(installed)
                await renewDevSessionIfDue(tv: tv, devKey: devKey)
                return
            }
            try await services.installTVApp(host: tv.host, devKey: devKey)
            tvApp = .upToDate(bundled)
            tvAppMissing = false
            await renewDevSessionIfDue(tv: tv, devKey: devKey)
            await openTVAppAfterInstall(tv)
        } catch DevModeError.keyRefused {
            // Geliştirici modu yeniden açılınca TV yeni anahtar üretir; eskisi işe yaramaz.
            store.remove(StoreKey.tvDevKey)
            tvApp = .needsPassphrase(error: nil)
        } catch let failure as DevModeFailure {
            // Genel mesaj tek başına sorunu bulmaya yetmiyordu; TV'nin verdiği sebep de gösterilir.
            let reason = failure.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            tvApp = .failed(failure.error, reason: reason.isEmpty ? nil : reason)
        } catch {
            tvApp = .failed(error as? DevModeError ?? .installFailed)
        }
    }

    /// LG geliştirici modunun 1000 saatlik süresini günde en çok bir kez baştan başlatır; kullanıcı TV'den uzatmak
    /// zorunda kalmaz.
    private func renewDevSessionIfDue(tv: LGTV, devKey: String) async {
        let key = StoreKey.devSessionRenewedFor(host: tv.host)
        let last = defaults.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 20 * 3600 else { return }
        if let hours = await services.renewDevSession(host: tv.host, devKey: devKey) {
            devModeHoursLeft = hours
            defaults.set(Date(), forKey: key)
        }
    }

    private func openTVAppAfterInstall(_ tv: LGTV) async {
        if let keeper {
            keeper.reconnect()
        } else {
            _ = try? await services.pairTV(tv, key: store.load(String.self, for: StoreKey.tvKey), server: serverAddress(for: tv))
        }
    }

    /// Ana ekrandaki "TV'de test et": sunucu henüz açık değilse açılır, deneme altyazısı gönderilir.
    func testSubtitle() async {
        try? await startServer()
        // Nino: TV uygulaması bağlı değilse önce TV'de açılır (bu bilgisayarın adresiyle), en çok ~10 sn beklenir.
        if let tv, showsOnTV, tvClients == 0 {
            if tv.brand == .androidTV { await refreshAndroidApp(tv) } else { await openTVAppAfterInstall(tv) }
            for _ in 0..<20 where tvClients == 0 { try? await Task.sleep(for: .milliseconds(500)) }
        }
        sendTestSubtitle()
    }

    func sendTestSubtitle() {
        server.sendStyle(settings.style)
        // Oyunda henüz altyazı görülmediyse altyazı bölgesinin altına yakın tipik bir yer kullanılır.
        let region = settings.region
        let box = lastSubtitleBox ?? TextBox(left: 0.3, top: region.bottom - 0.1, right: 0.7, bottom: region.bottom - 0.03)
        server.sendSubtitle(String(localized: "This is a test subtitle. Can you see it on top of the game?"), durationMs: 8000, box: box)
    }

    /// Nino: PSN hesabından çıkış (yalnız hesap kimliği silinir).
    func signOutPSN() {
        store.remove(StoreKey.accountId)
        accountId = nil
    }

    /// Kurulumu baştan başlatır (kayıtlı her şeyi siler).
    func resetSetup() {
        stop()
        [StoreKey.accountId, StoreKey.console, StoreKey.tv, StoreKey.tvKey, StoreKey.tvDevKey, StoreKey.tvAppVersion,
         StoreKey.setupComplete, StoreKey.loginPasscode].forEach(store.remove)
        hasLoginPasscode = false
        accountId = nil
        console = nil
        tv = nil
        tvKeySaved = false
        tvApp = .unknown
        tvAppMissing = false
        // Nino: sıfırlanınca kurulum konsol seçiminden başlar (PS5'ten Xbox'a ya da tersine geçilebilsin).
        welcomeConsole = nil
        step = .welcome
    }

    /// Nino: Ayarlar › Bağlantı'daki konsol seçimi. Xbox'ta PS5'e doğrudan bağlanma olmadığından görüntü Xbox
    /// penceresinden okunur (Capture Card seçiliyse o kalır); PS5'e dönülünce pencere yolu PS5'in Remote Play penceresi olur.
    func switchConsole(to console: GameConsole) {
        guard settings.gameConsole != console else { return }
        settings.gameConsole = console
        if console == .xbox && settings.videoSource == .ps5 { settings.videoSource = .window }
    }

    /// Nino: "TV'den itibaren yeniden kur". PS5 hesabı (ikinci PSN hesabı) ve PS5 eşleşmesi korunur; yalnız TV bağlantısı ve
    /// TV uygulamasının kaydı silinir, sihirbaz TV adımından devam eder (ardından deneme ve daha iyi çeviri).
    func resetFromTV() {
        stop()
        [StoreKey.tv, StoreKey.tvKey, StoreKey.tvDevKey, StoreKey.tvAppVersion, StoreKey.setupComplete].forEach(store.remove)
        tv = nil
        tvKeySaved = false
        tvApp = .unknown
        tvAppMissing = false
        // "TV'm yok" seçilmişse de TV adımı yeniden sorulur.
        if settings.output == .computer { settings.output = .tv }
        step = .tv
    }

    // MARK: - Takılınca yeniden açılma

    private static let resumeKey = "ninoResumeAfterRelaunch"

    /// Yazı okuması kalıcı takıldı: çeviri açıkken kendini yeniden açar; yeni süreç çeviriyi kendiliğinden başlatır.
    private func relaunchAfterStuckReading() {
        guard isRunning else { return }
        SubtitleLog.write("yazı okuması takıldı; Nino yeniden açılıyor, çeviri kendiliğinden sürecek")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.resumeKey)
        UserDefaults.standard.synchronize()
        let path = Bundle.main.bundlePath
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 3; /usr/bin/open \"$0\"", path]
        try? relaunch.run()
        // PS5 oturumu düzgün kapatılır (yoksa yeni süreç bağlanırken PS5 "başka oturum var" diyebilir).
        stop()
        NSApplication.shared.terminate(nil)
    }

    /// Takılma yüzünden yeniden açıldıysa (son 2 dk içinde) çeviri kendiliğinden başlar.
    func resumeIfRelaunched() async {
        let at = UserDefaults.standard.double(forKey: Self.resumeKey)
        UserDefaults.standard.removeObject(forKey: Self.resumeKey)
        var resume = at > 0 && Date().timeIntervalSince1970 - at < 120
        var note = "yeniden açıldı; çeviri kendiliğinden başlıyor"
        #if DEBUG
        // Nino (kullanıcı isteği): geliştirici sürümü her açılışta çeviriyi kendiliğinden başlatır (fiş kendiliğinden
        // takılır); denemeler sırasında Nino sık yeniden açılıyor.
        if !resume, step == .done { resume = true; note = "geliştirici sürümü: çeviri kendiliğinden başlıyor" }
        #endif
        guard resume else { return }
        for _ in 0..<40 where !canStart { try? await Task.sleep(nanoseconds: 250_000_000) }
        SubtitleLog.write(note)
        await start()
    }

    // MARK: - Çeviri

    func start() async {
        // Düğmeye iki kez basılması ya da beklerken tekrar çağrılması ikinci bir oturum açmaz.
        guard !isRunning, !isStarting, canStart else { return }
        // PS5'e bağlanmak için eşleşmiş PS5 ve ikinci hesap gerekir; oyun penceresinden ya da yakalama kartından okumak için gerekmez.
        let windowSource = usesGameWindow
        let cardSource = usesCaptureCard
        if !windowSource, !cardSource, console == nil || accountId == nil { return }
        isStarting = true
        defer { isStarting = false }

        translatorStatus = await Translator.status(source: settings.sourceLanguage, target: settings.targetLanguage)
        try? await startServer()
        server.sendStyle(settings.style)

        makePipeline()
        sessionStartedAt = Date()
        lastMetrics = nil
        if dubbingActive, dubbingModelReady { makeDubber().prepare() }
        SubtitleLog.write("oturum başladı: Nino \(AppIdentity.version), \(settings.sourceLanguage)→\(settings.targetLanguage), "
            + "motor: \(onlineTranslationActive ? settings.onlineEngine.rawValue : "ücretsiz"), paketler: \(settings.gamePacks ? "açık" : "kapalı")"
            + ", ağ: \(NetworkWatcher.shared.kind)")
        HealthRecorder.shared.sessionStarted()

        let session: StreamControlling
        if windowSource {
            let xbox = settings.gameConsole == .xbox
            SubtitleLog.write("görüntü kaynağı: oyun penceresi " + (xbox ? "(Xbox: Greenlight / xbox.com/play)" : "(PS Remote Play / chiaki-ng)"))
            let window = services.makeWindowStream()
            window.target = xbox ? .xbox : .playStation
            window.onWindowStatus = { [weak self] status in self?.windowStatusChanged(status) }
            window.onGameArea = { [weak self] area in self?.gameArea = area }
            session = window
        } else if cardSource {
            SubtitleLog.write("görüntü kaynağı: yakalama kartı" + (showsOnComputer ? " (oyun bu bilgisayarda gösteriliyor)" : ""))
            let card = services.makeCardStream(showsPlayer: showsOnComputer, preferredID: preferredCardID)
            card.onCardStatus = { [weak self] status in self?.cardStatusChanged(status) }
            card.onGameArea = { [weak self] area in self?.gameArea = area }
            card.onPlayerClosed = { [weak self] in Task { @MainActor in self?.stop() } }
            session = card
        } else if let console, let accountId {
            RemotePlayLog.write("Çeviri başladı; PS5'e bağlanılıyor: \(console.name) \(console.host)")
            session = services.makeStream(console: console, accountId: accountId,
                                          loginPasscode: store.load(String.self, for: StoreKey.loginPasscode))
        } else { return }
        session.onState = { [weak self] state in Task { @MainActor in self?.sessionStateChanged(state) } }
        session.onConsoleMoved = { [weak self] moved in Task { @MainActor in self?.consoleMoved(moved) } }
        session.onLocalNetworkBlocked = { [weak self] blocked in Task { @MainActor in self?.localNetworkChanged(blocked: blocked) } }
        session.onFrame = { [weak self] frame in
            // Karenin geldiği an: canlı altyazı alanındaki gecikme buradan TV'ye gidene kadar ölçülür.
            let capturedAt = SubtitleStabilizer.uptimeMs()
            Task { @MainActor in await self?.handle(frame, capturedAt: capturedAt) }
        }
        // Nino: dublaj açıksa PS5'in sesi de alınır; altyazı süresince konuşanın sesinden kim olduğu anlaşılır.
        if dubbingActive {
            let tracker = voiceTracker
            session.wantsAudio = true
            session.onAudio = { samples in tracker.append(samples) }
        }
        #if DEBUG
        // Geliştirici sürümü: video kaydı açıkken (frames/video/KAYIT) PS5'in sesi de tam kalitede yazılır.
        session.wantsAudio = true
        session.onFullAudio = { samples in NinoDebugFrames.recordAudio(samples) }
        #endif
        session.start()
        self.session = session

        startKeeper()
        // Remote Play penceresinden okurken PS5 eşleşmesi olmayabilir; son oyun o zaman PS5 adı olmadan hatırlanır.
        gameChoice.start(console: console.map { $0.name.isEmpty ? $0.host : $0.name }) { [weak self] in
            guard let self else { return false }
            return self.settings.askGame && self.settings.sharePool
        }

        // Mac uykudan uyanınca bağlantıları hemen yenile.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.session?.reconnectNow()
                self?.keeper?.reconnect()
            }
        }
        keepAwake()
        isRunning = true
        server.sendStarted()
        if screenHotkey == nil { screenHotkey = GlobalHotkey(.translateScreen) { [weak self] in self?.translateScreen() } }
        screenHotkey?.enabled = true
        updateClickThroughHotkey()
    }

    /// Çeviri başlatılabilir mi: görüntü kaynağı hazır (PS5 kurulu ya da PS Remote Play penceresi seçili) ve altyazının
    /// gideceği bir yer var (TV eşleşmiş ya da bilgisayar ekranı seçili).
    var canStart: Bool {
        // Nino: Xbox penceresinde altyazı TV'ye de gidebilir; TV seçiliyse TV eşleşmiş olmalı.
        (usesGameWindow && !usesXboxWindow) || ((usesGameWindow || usesCaptureCard || (console != nil && accountId != nil)) && (showsOnComputer || hasTV))
    }

    /// Nino: görüntü bu bilgisayardaki Xbox yayın penceresinden (Greenlight ya da xbox.com/play) okunuyor. Oyun çoğu
    /// zaman TV'de oynanır; pencere yalnız görüntünün kaynağıdır, altyazı seçilen yere (TV ya da bu bilgisayar) gider.
    var usesXboxWindow: Bool { usesGameWindow && settings.gameConsole == .xbox }

    /// Nino: görüntü bu bilgisayardaki oyun penceresinden okunuyor (PS5 eşleştirmesi gerekmez).
    var usesGameWindow: Bool { settings.videoSource == .window }

    /// Nino: görüntü bu bilgisayara takılı yakalama kartından okunuyor (PS5 eşleştirmesi gerekmez). Altyazı TV'ye de
    /// (PS5 → kart → TV) bilgisayar ekranına da (PS5 → kart → bilgisayar → ekran) gidebilir.
    var usesCaptureCard: Bool { settings.videoSource == .card }

    /// Altyazı bilgisayar ekranında gösteriliyor mu. Oyun penceresinden okunurken oyun bu bilgisayarda oynanır; altyazı
    /// her zaman pencerenin üstündedir.
    var showsOnComputer: Bool { (usesGameWindow && !usesXboxWindow) || settings.output.showsOnComputer }

    /// Altyazı TV'ye gidiyor mu. Oyun bu bilgisayarda oynanıyorsa TV'ye gönderilmez.
    var showsOnTV: Bool { (!usesGameWindow || usesXboxWindow) && settings.output.showsOnTV }

    /// Görüntü kaynağı değişti: altyazının yeri güncellenir, çeviri sürüyorsa yeni kaynakla yeniden başlar.
    private func videoSourceChanged() {
        outputChanged()
        guard isRunning else { return }
        stop()
        Task { await start() }
    }

    private func cardStatusChanged(_ status: CaptureCardCapture.Status) {
        guard cardStatus != status else { return }
        cardStatus = status
        switch status {
        case .needsPermission: SubtitleLog.write("yakalama kartı: kamera izni yok")
        case .noCard: SubtitleLog.write("yakalama kartı: bulunamadı")
        case .blackPicture(let name): SubtitleLog.write("yakalama kartı: görüntü siyah (\(name))")
        case .capturing(let name): SubtitleLog.write("yakalama kartı: okunuyor (\(name))")
        case .stopped: break
        }
    }

    /// Yakalama kartı durumunun kullanıcıya gösterilecek metni.
    var cardStatusText: String {
        switch cardStatus {
        case .stopped: return String(localized: "Reads the capture card")
        case .needsPermission: return String(localized: "Allow Nino in System Settings › Privacy & Security › Camera, then reopen Nino.")
        case .noCard: return String(localized: "Plug in your capture card")
        case .blackPicture: return String(localized: "The picture is black. Turn the PS5 on, or turn off Settings › System › HDMI › Enable HDCP on the PS5.")
        case .capturing(let name): return String(format: String(localized: "Reading %@"), name)
        }
    }

    private func windowStatusChanged(_ status: GameWindowCapture.Status) {
        guard windowStatus != status else { return }
        windowStatus = status
        switch status {
        case .needsPermission: SubtitleLog.write("oyun penceresi: Ekran Kaydı izni yok")
        case .lookingForWindow: SubtitleLog.write("oyun penceresi: bulunamadı")
        case .capturing(let app): SubtitleLog.write("oyun penceresi: okunuyor (\(app))")
        case .stopped: break
        }
    }

    /// Oyun penceresi durumunun kullanıcıya gösterilecek metni.
    var windowStatusText: String {
        switch windowStatus {
        case .stopped:
            if settings.gameConsole == .xbox { return String(localized: "Reads the Xbox stream window") }
            // CouchSubs'tan: Remote Play uygulaması kurulu değilse ana ekran nereden indirileceğini söyler.
            if remotePlayMissing { return String(localized: "The Remote Play app isn't installed on this Mac. Download it in Settings › Picture source.") }
            return String(localized: "Reads the PS Remote Play window")
        case .needsPermission: return String(localized: "Allow Nino in System Settings › Privacy & Security › Screen Recording, then reopen Nino.")
        case .lookingForWindow: return settings.gameConsole == .xbox
            ? String(localized: "Start your Xbox in Greenlight. Press Connect Your Xbox if you need help.")
            : String(localized: "Open PS Remote Play or chiaki-ng and start playing")
        case .capturing(let app): return String(format: String(localized: "Reading %@"), app)
        }
    }

    /// TV uygulamasını başlatır ve açık tutar; TV kapalıysa açıldığında bağlanır. Altyazı TV'ye gitmiyorsa ya da TV
    /// yoksa bir şey yapmaz.
    private func startKeeper() {
        guard keeper == nil, showsOnTV, hasTV, let tv else { return }
        let server = self.server
        let keeper = services.makeKeeper(tv: tv, key: store.load(String.self, for: StoreKey.tvKey), params: ["server": serverAddress(for: tv)],
                                         appConnected: { server.connectedClients > 0 }, onMoved: { [weak self] moved in
            Task { @MainActor in self?.tvMoved(to: moved) }
        }, onKey: { [weak self] key in
            Task { @MainActor in self?.store.save(key, for: StoreKey.tvKey) }
        })
        keeper.start(interval: .seconds(5))
        self.keeper = keeper
        Task { await refreshTVApp() }
    }

    /// Çeviri sürerken bilgisayar ekranı da açık kalsın mı: görüntü bu Mac'teki Remote Play penceresinden okunuyorsa
    /// (ekran kapanınca ScreenCaptureKit kare vermez) ya da altyazı bu ekranda gösteriliyorsa. X'te bildirildi: kullanıcı
    /// TV'de oynayıp Mac'e dokunmayınca ekran kendi ayarıyla (prizdeyken çoğu zaman 10 dakika) kapanıyor, altyazı
    /// kesiliyordu. PS5'ten doğrudan okunup yalnız TV'ye gönderiliyorsa ekran kendi ayarıyla kapanabilir.
    var keepsDisplayOn: Bool {
        // Nino: oyun penceresi (PS Remote Play, chiaki-ng, Xbox yayını) ya da altyazı/oyun bu ekranda.
        usesGameWindow || showsOnComputer
    }

    /// Mac'in boşta uyuması (ve gerekiyorsa ekranın kapanması) engellenir; çeviri sürerken ayar değişince yeniden kurulur.
    private func keepAwake() {
        var options: ProcessInfo.ActivityOptions = [.userInitiated, .idleSystemSleepDisabled]
        if keepsDisplayOn { options.insert(.idleDisplaySleepDisabled) }
        let previous = sleepActivity
        sleepActivity = ProcessInfo.processInfo.beginActivity(options: options, reason: "Translating game subtitles")
        if let previous { ProcessInfo.processInfo.endActivity(previous) }
    }

    /// Altyazının yeri değişti: TV seçildiyse TV uygulaması açılır, kaldırıldıysa artık açık tutulmaz.
    private func outputChanged() {
        server.sendsToTV = showsOnTV
        if !showsOnComputer {
            // Yayın penceresi açıksa satırları kalır; yalnız saydam pencerenin yer ayarı biter.
            if streamWindowOpen { overlayAdjusting = false } else { overlayHide() }
        }
        updateClickThroughHotkey()
        guard isRunning else { return }
        keepAwake()
        if showsOnTV {
            startKeeper()
        } else {
            keeper?.stop()
            keeper = nil
        }
    }

    // MARK: - Ekranı çevir

    /// ⌥⌘T yalnız çeviri sürerken tutulur.
    private var screenHotkey: GlobalHotkey?
    /// ⌥⌘L: altyazı penceresinde "Tıklamalar geçsin"i açar/kapatır; çeviri sürerken ve altyazı bilgisayardayken tutulur.
    var clickThroughHotkey: GlobalHotkey?
    /// Süren "ekranı çevir" işi; yeniden basılınca iptal edilir.
    private var screenTask: Task<Void, Never>?
    /// TV'deki ekran çevirilerinin kalkacağı an; bu andan önce yeniden basmak onları kaldırır.
    private var screenShownUntil = Date.distantPast

    /// ⌥⌘T: oyunun şu anki karesinin tamamını bir kez okur, her yazı grubunu ayrı çevirip TV'de kendi yerine koyar.
    /// Çeviriler hazırlandıkça TV'ye gider. Çeviri sürerken ya da çeviriler TV'deyken yeniden basmak onları kaldırır.
    func translateScreen() {
        guard isRunning else { return }
        guard let frame = lastFrame else {
            // Çeviri sürüyor ama PS5'ten henüz görüntü gelmedi: tuş sessizce yok sayılmasın.
            server.sendSubtitle(String(localized: "Couldn't capture the screen: no picture from the PS5 yet."), durationMs: 4000)
            return
        }
        if let task = screenTask {
            task.cancel()
            screenTask = nil
            hideScreen()
            return
        }
        if Date() < screenShownUntil {
            hideScreen()
            return
        }
        server.sendStyle(settings.style)
        server.sendSubtitle(String(localized: "Translating the screen…"), durationMs: 2500)
        let reader = VisionReader(language: settings.sourceLanguage)
        let translator = makeTranslator()
        let server = self.server
        screenTask = Task { [weak self] in
            do {
                let reading = try await Task.detached(priority: .userInitiated) { try reader.readLines(frame, deep: false) }.value
                // Yapay zekâda ekranın bütün yazıları tek istekte gider (bkz. AITranslationCore.translateAll).
                let items = try await ScreenTranslation.translate(reading, using: translator) { shown in
                    guard !Task.isCancelled else { return }
                    let milliseconds = ScreenTranslation.displayMilliseconds(shown)
                    server.sendScreen(shown, durationMs: milliseconds)
                    self?.screenShownUntil = Date().addingTimeInterval(Double(milliseconds) / 1000)
                }
                server.clear()
                if items.isEmpty { server.sendSubtitle(String(localized: "No text found on the screen."), durationMs: 2500) }
            } catch is CancellationError {
                return
            } catch let error as TranslatorError {
                self?.translatorStatus = Self.translatorStatus(after: error)
                self?.showScreenFailure(error, translator: translator)
            } catch {
                self?.showScreenFailure(error, translator: translator)
            }
            if !Task.isCancelled { self?.screenTask = nil }
        }
    }

    // MARK: Nino: köşe yazıları

    private var cornerTask: Task<Void, Never>?
    private var cornerLastCheck = Date.distantPast
    private var cornerTexts = ["", "", ""]
    private var cornerItems: [[ScreenTranslation.Item]] = [[], [], []]
    /// Nino: son çevrilen köşe yazıları. Aynı kutu her okumada biraz farklı çıkar ("STUDIO I" / "STUDIO L"); benzeri
    /// daha önce çevrildiyse çevirmene yeniden gitmez (Gemini'nin günlük hakkı bunlarla bitiyordu).
    private var cornerMemory: [(text: String, items: [ScreenTranslation.Item])] = []
    /// Nino: bir önceki okumada görülen ama henüz çevrilmeyen yazı. Kutu belirirken ya da kaybolurken yarım okunan yazı
    /// çevrilmez; yazı iki okumada aynı (ya da çok benzer) görünürse çevrilir.
    private var cornerPending = ["", "", ""]
    private var cornerEmptyReads = [Int](repeating: 0, count: 3)
    /// Nino: menü okuması (bütün ekran) her köşe okumasında değil, iki okumada bir yapılır.
    private var menuCounter = 0
    /// Nino: harita/duraklatma ekranı görüldü; bu zamana kadar tuş ipuçları çevrilmez.
    private var menuScreenUntil = Date.distantPast
    /// Okuma hattının (başka iş parçacığında) sorduğu kopya.
    private let menuScreenFlag = UntilFlag()
    private var menuSeenAt = Date.distantPast
    private var menuBoxes: [TextBox] = []
    /// Nino: PS5'in kendi (Türkçe) ekranı görüldü; bu zamana kadar köşe yazıları çevrilmez. Ana ekranda oyun kutucuklarının
    /// adları ("RED DEAD REDEMPTION", "share factory") ipucu sanılıp çevriliyordu.
    private var systemScreenUntil = Date.distantPast
    private var promptText = ""
    private var promptItems: [ScreenTranslation.Item] = []
    private var promptTask: Task<Void, Never>?

    /// Okuma alanındaki tuş ipuçları ("Hold ✕ to aim"): değiştiğinde simgesi korunarak çevrilip kendi yerine konur.
    private func showPrompts(_ prompts: Reading) {
        // En alttaki menü şeridi köşe okuyucusunun ("alt şerit"); burada da okunursa iki kutu üst üste biniyordu.
        let hudTop = currentHudTop ?? 1
        // Eşya, silah ve tuş etiketleri ("L1 BASEBALL BAT", "FORTUNE SON MORELAND 850", "HANDLE ◆") hiç çevrilmez;
        // çeviriye de gönderilmez (sunucuyu ve günlüğü boşuna dolduruyordu).
        let prompts = Reading(lines: prompts.lines.filter { ($0.box?.top ?? 0) < hudTop && !Self.isNavigationWord($0.text) })
        // Kullanıcı isteği: altyazı alanındaki tuş ipuçları çevrilmez (yalnız altyazı ve sol üst).
        // İpucu simgesinin etrafındaki büyüyüp küçülen halka okumayı her karede biraz değiştiriyor ("Hold ◯ to…" /
        // "Hold to…"); yazı simgeler ve halka yok sayılarak karşılaştırılır, aynıysa Türkçe yerinden oynamaz.
        let promptKey = Self.promptKey(prompts.text)
        guard Self.translatePrompts, settings.translateCorners, promptKey != promptText, promptTask == nil,
              Date() > menuScreenUntil else { return }
        promptText = promptKey
        let translator = makeTranslator()
        let pooled = settings.sharePool && settings.sourceLanguage == "en"
        let translations = self.translations
        let game = packs.searchScope ?? gameChoice.sense.current?.name
        let turkishWords = settings.targetLanguage == "tr"
        // Ekrandaki altyazının yeri (yeni gösterildiyse): ipucunun Türkçesi onun üstüne binmesin.
        let subtitle = lastSubtitleBox
        promptTask = Task { [weak self] in
            let translated = prompts.text.isEmpty ? [] :
                ((try? await ScreenTranslation.translate(prompts, using: { piece in
                    if pooled {
                        if let known = translations.store.match(piece) { return known }
                        if let fresh = await translations.translate(piece, game: game) { return fresh }
                    }
                    return try await translator.translate(piece)
                })) ?? [])
            // Simgeler (□ ✕ ○) Türkçede tekrar edilmez: oyunun kendi tuş simgeleri hemen altında görünüyor.
            let previous = self?.promptItems ?? []
            // Tuş şeridi ("PHOTO STUDIO □ SELECT ✕ BACK ○"): her parçanın Türkçesi kendi sözcüğünün üstüne ortalanır.
            let items = Self.steady(Self.placeAbove(translated.flatMap { Self.splitAtIcons($0, knownWords: turkishWords) }.map { item in
                var plain = item
                plain.translation = Self.withoutIcons(item.translation)
                return plain
            }.filter { !$0.translation.isEmpty && !Self.isNavigationWord($0.source) }.map(Self.centeredPlain),
                avoiding: subtitle.map { [$0] } ?? []), previous: previous)
            guard let self else { return }
            if !prompts.text.isEmpty {
                SubtitleLog.write("ipucu: \"\(prompts.text.replacingOccurrences(of: "\n", with: " / "))\" → \(items.map(\.translation).joined(separator: " / "))")
            }
            promptItems = items
            sendOverlays()
            promptTask = nil
        }
    }

    /// Nino: tuş ipucunun ("TURBINE R3", "W-14 RIFLE") Türkçesi oyunun yazısının üstüne binmeden, hemen üstündeki boşluğa
    /// konur. TV kutuyu yukarı ve aşağı `tvPad` kadar payla çizer; Türkçe uzun gelirse kutu aşağı doğru uzayıp oyunun
    /// yazısını örtüyordu. Bu yüzden: arada pay bırakılır, kutu yana doğru genişletilir (Türkçe tek satıra sığsın; sağ
    /// yarıdaki ipucunda sola, sol yarıdakinde sağa) ve iki çeviri üst üste gelirse alttaki yukarı itilmez, üstteki daha
    /// yukarı kaydırılır.
    nonisolated static func placeAbove(_ items: [ScreenTranslation.Item], avoiding: [TextBox] = []) -> [ScreenTranslation.Item] {
        let tvPad = 0.008, gap = 0.006
        var placed: [ScreenTranslation.Item] = []
        // Alttan yukarı: en alttaki ipucu yerini önce alır, üstündekiler gerekirse daha yukarı kayar.
        for item in items.sorted(by: { $0.box.top > $1.box.top }) {
            var moved = item
            let height = max(item.box.bottom - item.box.top, item.lineHeight)
            let width = item.box.right - item.box.left
            // Türkçe genelde İngilizceden uzun: harf başına genişliğe göre gereken kadar (en çok %60 fazla) yer açılır.
            let source = max(1, item.source.count), target = item.translation.count
            let extra = min(width * 0.6, max(0, width * Double(target - source) / Double(source)))
            let rightSide = (item.box.left + item.box.right) / 2 > 0.5
            let left = rightSide ? max(0, item.box.left - extra) : item.box.left
            let right = rightSide ? item.box.right : min(1, item.box.right + extra)
            var bottom = item.box.top - 2 * tvPad - gap
            let row = bottom
            // Aynı satırdan bölünen parçalar (tuş şeridi) yan yana kalır; birbirini yukarı itmez.
            for other in placed where abs(other.box.bottom - row) > 0.005 && other.box.left < right && left < other.box.right
                && other.box.top - 2 * tvPad - gap < bottom && bottom - height < other.box.bottom + 2 * tvPad + gap {
                bottom = other.box.top - 2 * tvPad - gap
            }
            bottom = max(height + tvPad, bottom)
            // Üstünde altyazı varsa ("Press ✕ to talk" konuşmanın hemen altında) Türkçesi altyazının üstüne binmez:
            // ipucunun altına konur.
            let above = TextBox(left: left, top: max(0, bottom - height) - tvPad, right: right, bottom: bottom + tvPad)
            if avoiding.contains(where: { $0.left < above.right && above.left < $0.right && $0.top < above.bottom && above.top < $0.bottom }) {
                let top = min(1 - height, item.box.bottom + 2 * tvPad + gap)
                bottom = top + height
            }
            moved.box = TextBox(left: left, top: max(0, bottom - height), right: right, bottom: bottom)
            placed.append(moved)
        }
        return placed.sorted { $0.box.top < $1.box.top }
    }

    nonisolated static func isIcon(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .otherSymbol, .mathSymbol, .privateUse: return true
        default: return false
        }
    }

    /// Simgelerle ayrılmış parçalar ("PHOTO STUDIO", "SELECT", "BACK").
    nonisolated static func iconSegments(_ text: String) -> [(text: String, start: Double, end: Double)] {
        // Simge yaklaşık iki harf genişliğindedir; parçaların satırdaki yeri harf sayısıyla kestirilir.
        var segments: [(String, Double, Double)] = []
        var current = "", start = 0.0, position = 0.0
        func close() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let lead = Double(current.prefix(while: \.isWhitespace).count)
                segments.append((trimmed, start + lead, start + lead + Double(trimmed.count)))
            }
            current = ""
        }
        for scalar in text.unicodeScalars {
            if isIcon(scalar) {
                close()
                position += 2
                start = position
            } else {
                if current.isEmpty { start = position }
                current.unicodeScalars.append(scalar)
                position += 1
            }
        }
        close()
        return segments.map { (text: $0.0, start: $0.1 / max(1, position), end: $0.2 / max(1, position)) }
    }

    /// Bir satırda simgelerle ayrılmış birden çok tuş varsa her biri ayrı öğe olur; Türkçesi kendi İngilizcesinin üstünde,
    /// ortasına hizalı durur. Parça sayıları tutmazsa satır bölünmez.
    nonisolated static func splitAtIcons(_ item: ScreenTranslation.Item, knownWords: Bool = false) -> [ScreenTranslation.Item] {
        let source = iconSegments(item.source), target = iconSegments(item.translation)
        guard source.count >= 2, source.count == target.count else { return [item] }
        let width = item.box.right - item.box.left
        let line = item.box.bottom - item.box.top
        return zip(source, target).map { english, turkish in
            let center = item.box.left + width * (english.start + english.end) / 2
            // Kutu İngilizce sözcük kadar; Türkçe uzunsa (dar yazı tipinde harf başına ~0,42 satır yüksekliği) o kadar.
            let englishWidth = width * (english.end - english.start)
            let half = max(englishWidth, Double(turkish.text.count) * line * 0.42 * 9 / 16 + 0.01) / 2
            let left = min(max(0, center - half), 1 - 2 * half)
            var piece = item
            piece.source = english.text
            // Tek sözcüklük tuş adları ("SELECT", "BACK") yerleşik Türkçesiyle ("Seç", "Geri").
            piece.translation = (knownWords ? MenuBlock.knownTurkish(english.text) : nil) ?? turkish.text
            piece.box = TextBox(left: left, top: item.box.top, right: left + 2 * half, bottom: item.box.bottom)
            return piece
        }
    }

    /// Kareyi en çok `maxWidth` piksel genişliğe küçültür (oran korunur); zaten küçükse nil.
    nonisolated static func downscaled(_ image: CGImage, maxWidth: Int) -> CGImage? {
        guard image.width > maxWidth else { return nil }
        let height = Int(Double(image.height) * Double(maxWidth) / Double(image.width))
        guard let context = CGContext(data: nil, width: maxWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
        return context.makeImage()
    }

    /// Yazıyı verilen genişliğe (ekran oranı) sığacak satırlara böler; harf genişliği satır yüksekliğinin ~0,5'i (16:9).
    nonisolated static func wrap(_ text: String, width: Double, line: Double) -> [String] {
        let perLine = max(12, Int(width / max(0.004, line * 0.5 * 9 / 16)))
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if !current.isEmpty, current.count + 1 + word.count > perLine {
                lines.append(current)
                current = ""
            }
            current += current.isEmpty ? String(word) : " " + word
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [text] : lines
    }

    /// Kullanıcı isteği: ipucunun Türkçesi oyunun yazısının üstünde, yarı saydam (sade) ve ortalı durur; siyah kutu
    /// oyunun yazısını kapatmaz. TV sade yazıyı sola yaslar: kutu Türkçenin tahmini genişliği kadar, ortaya konur.
    nonisolated static func centeredPlain(_ item: ScreenTranslation.Item) -> ScreenTranslation.Item {
        var plain = item
        let line = item.box.bottom - item.box.top
        let width = min(0.6, Double(item.translation.count) * line * 0.5 * 9 / 16 + 0.02)
        let center = (item.box.left + item.box.right) / 2
        let left = min(max(0, center - width / 2), 1 - width)
        plain.box = TextBox(left: left, top: item.box.top, right: left + width, bottom: item.box.bottom)
        plain.plain = true
        return plain
    }

    /// Herkesin bildiği gezinme tuşları ("BACK", "SELECT", "EXIT"…) çevrilmez; ekranı boşuna kaplıyordu.
    nonisolated static func isNavigationWord(_ source: String) -> Bool {
        let words: Set<String> = ["back", "select", "exit", "close", "confirm", "cancel", "ok", "accept", "continue", "skip",
                                  "zoom", "rotate", "scroll", "navigate", "change", "toggle", "view", "rev", "buy", "equip"]
        let text = withoutIcons(source).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Kullanıcı isteği: kısa eylem etiketleri de ("THREATEN", "DEFUSE", "CLERK", "PHOTO STUDIO") çevrilmez; yalnız
        // cümle hâlindeki ipuçları ("Hold L1 to open the equipment menu", "Press ✕ to talk") çevrilir.
        // Tuş adları ("L1", "R2", "OPTIONS") sözcük sayılmaz: "L1 BASEBALL BAT" bir eşya etiketidir.
        let count = text.split(whereSeparator: \.isWhitespace).filter { token in
            token.contains(where: \.isLetter) && token.range(of: #"^[lr][123]$|^options$|^touchpad$"#, options: .regularExpression) == nil
        }.count
        // Büyük harfli kısa etiketler (eşya, silah, kıyafet: "BASEBALL BAT", "USE") da çevrilmez.
        return words.contains(text) || count <= 2 || Reading.isItemLabel(withoutIcons(source))
    }

    /// Tuş simgeleri ("□", "✕", "○", "△", "⊙") çıkarılır; "L1", "R2" gibi tuş adları kalır.
    /// Çeviri motorunun döndürdüğü HTML kodları ("&amp;", "&#39;") düz karaktere çevrilir.
    nonisolated static func withoutEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&apos;", with: "'")
    }

    nonisolated static func withoutIcons(_ text: String) -> String {
        let text = withoutEntities(text)
        let kept = text.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .otherSymbol, .mathSymbol, .privateUse: return false
            default: return true
            }
        }
        return String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Nino: aynı yazının yeri her okumada birkaç piksel oynuyordu (yazı tanımanın kutusu); Türkçe de titriyordu. Aynı
    /// çeviri yakın bir yerde yeniden gelirse eski yeri korunur.
    /// İpucunun karşılaştırma anahtarı: yalnız harfler ve rakamlar, küçük harf (simge ve halka okumaları atılır).
    nonisolated static func promptKey(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.count > 1 && $0.range(of: #"^[lr][123]$"#, options: .regularExpression) == nil }.joined(separator: " ")
    }

    nonisolated static func steady(_ items: [ScreenTranslation.Item], previous: [ScreenTranslation.Item]) -> [ScreenTranslation.Item] {
        items.map { item in
            // Aynı çeviri aynı satırda yeniden geldiyse (halka kutuyu büyüttü) ilk yeri ve boyutu aynen korunur.
            if let same = previous.first(where: { $0.translation == item.translation }), abs(same.box.top - item.box.top) < 0.06 {
                var kept = item
                kept.box = same.box
                return kept
            }
            guard let old = previous.first(where: { $0.translation == item.translation || $0.source == item.source }),
                  abs(old.box.top - item.box.top) < 0.04, abs(old.box.left - item.box.left) < 0.06,
                  abs(old.box.right - item.box.right) < 0.06 else { return item }
            var kept = item
            kept.box = TextBox(left: old.box.left, top: old.box.top, right: max(old.box.right, item.box.right),
                               bottom: old.box.top + (item.box.bottom - item.box.top))
            return kept
        }
    }

    // MARK: Telefon mesajları

    /// Gerçek mesaj bildirimi sağ alttan gelir: kartın sol ve üst kenarı en az bu kadar (kareye oranla).
    static let messageCardMinLeft = 0.55
    static let messageCardMinTop = 0.72
    private var messageText = ""
    private var messagePending = ""
    private var messageItems: [ScreenTranslation.Item] = []
    private var messageSeen = Date.distantPast
    private var messageTask: Task<Void, Never>?

    /// Nino: telefona gelen mesaj kartı (bkz. `MessageCard`). Türkçesi altyazı kutusunda değil, kartın hemen üstünde
    /// gönderenin adıyla, yarı saydam sade yazıyla durur; kart kalkınca o da kalkar.
    private func showMessage(_ card: Reading) {
        messageSeen = Date()
        if let call = MessageCard.call(card) {
            showCall(card, name: call.name, status: call.status)
            return
        }
        // Kullanıcı isteği (20 Kasım 2026): buzlu kart yalnız sağ alttan gelen gerçek mesaj bildiriminde gösterilir.
        // Telefon açıkken (son 10 sn) ya da kart ekranın ortasındaysa bu telefon uygulamasının satırlarıdır; gösterilmez
        // (altyazı olarak da çıkmaz).
        let cardBoxes = card.lines.compactMap(\.box)
        let cardTop = cardBoxes.map(\.top).min() ?? 0, cardLeft = cardBoxes.map(\.left).min() ?? 0
        guard Date().timeIntervalSince(phoneSeen) > 10, cardLeft >= Self.messageCardMinLeft, cardTop >= Self.messageCardMinTop else {
            if !messageItems.isEmpty { messageItems = []; sendOverlays() }
            return
        }
        let (name, body) = MessageCard.parts(card)
        let key = TextMatch.normalize(body)
        // Kart belirirken yarım okunabilir: aynı metin iki okumada görülünce çevrilir.
        guard key != messageText, messageTask == nil else { return }
        guard key == messagePending else { messagePending = key; return }
        messageText = key
        let translator = makeTranslator()
        let translations = self.translations
        let game = translations.poolGame(gameChoice.sense.current?.name, packs.searchScope)
        let pooled = settings.sharePool && settings.sourceLanguage == "en"
        let boxes = card.lines.compactMap(\.box)
        messageTask = Task { [weak self] in
            var turkish: String? = pooled ? translations.store.match(body) : nil
            if turkish == nil, pooled { turkish = await translations.translate(body, game: game) }
            if turkish == nil { turkish = try? await translator.translate(body) }
            guard let self else { return }
            messageTask = nil
            guard let turkish = turkish.map(Self.withoutIcons), !turkish.isEmpty else { return }
            let left = boxes.map(\.left).min() ?? 0.5, right = boxes.map(\.right).max() ?? 0.9
            let top = boxes.map(\.top).min() ?? 0.7
            // Türkçe oyunun yazısından küçük, ekranı kaplamaz.
            let line = min(boxes.dropFirst().first.map { $0.bottom - $0.top } ?? 0.03, 0.032) * 0.8
            let wrapped = Self.wrap(turkish, width: max(0.2, right - left), line: line)
            let height = line * Double(wrapped.count + 1) * 1.3
            let itemTop = max(0, top - height - 0.02)
            var item = ScreenTranslation.Item(source: body, translation: ([name] + wrapped).joined(separator: "\n"),
                                              box: TextBox(left: left, top: itemTop, right: max(right, left + 0.2), bottom: itemTop + height),
                                              lineHeight: line)
            item.plain = true
            messageItems = [item]
            SubtitleLog.write("mesaj: \(name): \(SubtitleLog.excerpt(body)) → \(turkish)")
            sendOverlays()
        }
    }

    /// Nino: telefon araması kartı: "Paradise Taxi aranıyor…" kartın hemen üstünde yarı saydam, eğik yazıyla (çeviriye
    /// gitmez). Konuşma sürerken (kartta süre) bir şey gösterilmez.
    private func showCall(_ card: Reading, name: String, status: String) {
        let key = "arama:" + name + status
        guard key != messageText else { return }
        messageText = key
        messagePending = ""
        guard !status.isEmpty else {
            if !messageItems.isEmpty { messageItems = []; sendOverlays() }
            return
        }
        let boxes = card.lines.compactMap(\.box)
        let left = boxes.map(\.left).min() ?? 0.1, right = boxes.map(\.right).max() ?? 0.4
        let top = boxes.map(\.top).min() ?? 0.8
        let line = min(boxes.first.map { $0.bottom - $0.top } ?? 0.03, 0.032) * 0.8
        let height = line * 1.3
        let itemTop = max(0, top - height - 0.035)
        var item = ScreenTranslation.Item(source: name, translation: "\(name) \(status)",
                                          box: TextBox(left: left, top: itemTop, right: max(right, left + 0.2), bottom: itemTop + height),
                                          lineHeight: line)
        item.plain = true
        item.italic = true
        messageItems = [item]
        SubtitleLog.write("arama: \(name) \(status)")
        sendOverlays()
    }

    /// Kart ekrandan kalktıysa (3 sn görülmediyse) Türkçesi de kalkar.
    private func clearStaleMessage() {
        // Harita kapandıysa kartın Türkçesi de kalkar.
        if !mapItems.isEmpty, Date() > menuScreenUntil { clearMapCard(); sendOverlays() }
        guard !messageItems.isEmpty, Date().timeIntervalSince(messageSeen) > 3 else { return }
        messageItems = []
        messageText = ""
        messagePending = ""
        sendOverlays()
    }

    /// Köşe ve ipucu çevirilerini birlikte TV'ye gönderir (ekran çevirisi tek liste ister).
    private func sendOverlays() {
        guard isRunning else { return }
        let all = cornerItems.flatMap { $0 } + promptItems + messageItems + phoneItems + mapItems
        if all.isEmpty { server.clearScreen() } else { server.sendScreen(all, durationMs: 120_000, overlay: true) }
    }

    // MARK: Telefon (GTA 6): sohbetteki mesajların Türkçesi telefonun yanında, yarı saydam

    private var phoneItems: [ScreenTranslation.Item] = []
    private var phoneKey = ""
    /// Telefonda en son okunan yazılar ve görüldüğü an: altyazı okumasında bunlar görülürse altyazı sayılmaz.
    private var phoneTexts: (texts: [String], at: Date) = ([], .distantPast)
    private var phonePending = ""
    private var phoneSeen = Date.distantPast
    private var phoneLastCheck = Date.distantPast
    private var phoneTask: Task<Void, Never>?
    /// Bu oturumda çevrilmiş mesajlar: sohbet kaydırılınca aynı mesaj yeniden çevrilmez.
    /// Diske de yazılır: Nino yeniden açılınca (takılma) telefonun Türkçeleri baştan çevrilmeden hemen gelir.
    /// Her çeviri dili ayrı dosyadadır (dil değişince eski dilin çevirisi gelmesin).
    private lazy var phoneMemoryLanguage = settings.targetLanguage
    private lazy var phoneMemory: [String: String] = (try? JSONDecoder().decode([String: String].self,
        from: Data(contentsOf: phoneMemoryFile))) ?? [:]
    private var phoneMemoryFile: URL { AppFolder.support.appendingPathComponent("phone-memory-\(phoneMemoryLanguage).json") }
    /// Örtülerin yerleştirildiği andaki telefon ekranı ve örtüler: telefon kayınca örtüler aynı kadar kaydırılır.
    private var phoneBase: (panel: TextBox, items: [ScreenTranslation.Item])?
    private var phoneTrackTask: Task<Void, Never>?
    private var phoneTrackAt = Date.distantPast
    private var phoneShift = (dx: 0.0, dy: 0.0)
    /// Telefonu takip eder (koyu temalı uygulamada her karede bulunamıyor; bkz. PhonePanel.Tracker).
    private let phoneTracker = PhonePanel.Tracker()
    /// Telefon bu kadardan az kaydıysa (elde sallanma) panel yerinde kalır.
    private static let phoneSteady = 0.05
    /// Yerleştirildiği anda her mesajın telefon ekranına göre yeri (kaydırma bununla anlaşılır).
    private var phoneAnchors: [String: Double] = [:]
    /// Bir önceki ölçümde görülen kayma: telefonun yeri küçük karede bulunur, bir nokta oynaması ekranda ~8 piksel
    /// titreme yapar. Örtüler ancak belirgin kayma iki ölçüm üst üste görülünce kaydırılır.
    private var phoneShiftSeen: (dx: Double, dy: Double)?

    /// Nino: Türkçeler balonların üstündeyken telefon elde sallanır; yazıyı yeniden okumadan (pahalı) yalnız telefonun
    /// yeri sık sık bulunur ve örtüler onunla birlikte kaydırılır, yoksa İngilizce kenardan görünürdü.
    private func trackPhone(_ frame: CGImage) {
        guard let base = phoneBase, !phoneItems.isEmpty, phoneTrackTask == nil,
              Date().timeIntervalSince(phoneTrackAt) > 0.1 else { return }
        phoneTrackAt = Date()
        phoneTrackTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { PhonePanel.find(in: frame)?.box }.value
            guard let self else { return }
            phoneTrackTask = nil
            guard let found, let current = phoneBase, current.panel == base.panel else { return }
            // Telefonun ortası ne kadar kaydı (kenar okuması bir iki nokta oynar; ortalama daha sakin).
            let dx = (found.left + found.right - base.panel.left - base.panel.right) / 2
            let dy = (found.top + found.bottom - base.panel.top - base.panel.bottom) / 2
            guard abs(dx - phoneShift.dx) > 0.009 || abs(dy - phoneShift.dy) > 0.012, abs(dx) < 0.08, abs(dy) < 0.08 else {
                phoneShiftSeen = nil
                return
            }
            // Tek ölçümlük sıçrama gürültüdür; aynı yöndeki ikinci ölçümde kaydırılır (iki ölçümün ortalamasıyla).
            guard let seen = phoneShiftSeen, abs(seen.dx - dx) < 0.008, abs(seen.dy - dy) < 0.011 else {
                phoneShiftSeen = (dx, dy)
                return
            }
            phoneShiftSeen = nil
            let settled = ((seen.dx + dx) / 2, (seen.dy + dy) / 2)
            phoneShift = settled
            phoneItems = PhoneThread.shifted(base.items, dx: settled.0, dy: settled.1)
            sendOverlays()
        }
    }

    /// Nino: telefonda bir sohbet açıksa mesajlarını okur, çevirir ve telefonun boş yanına, her mesajın hizasına yarı
    /// saydam yazıyla koyar. Eskiden bu yazılar altyazı sanılıp telefonun üstünde kocaman siyah kutuda çıkıyordu
    /// (kullanıcı: "mesajlara girince kocaman görünüyor, saydam ve sağda yazsa iyi"). Mesaj listesi çevrilmez.
    private func watchPhone(_ frame: CGImage) {
        // Tanınan oyun havuz öncelikli mi (GTA 6): bir sonraki açılışta oyun tanınana kadar bu hatırlanır.
        var phoneGame = UserDefaults.standard.bool(forKey: Self.lastGamePoolFirstKey)
        if gameChoice.sense.current != nil {
            let first = liveGamePoolFirst
            if first != phoneGame { UserDefaults.standard.set(first, forKey: Self.lastGamePoolFirstKey) }
            phoneGame = first
        }
        guard settings.translateCorners, settings.sourceLanguage == "en", phoneGame, phoneTask == nil,
              // Türkçeler yerleştikten sonra telefon seyrek okunur: bütün yazı okumaları tek sıradan geçer; telefon 0,6 sn'de
              // bir okununca altyazı ve köşe okumaları 4 sn'den uzun bekleyip "Vision takıldı" sanılıyor, Nino her 20-30 sn'de
              // kendini yeniden açıyordu (20 Kasım 2026). Kaydırınca örtüler kalkar ve hızlı okumaya dönülür.
              Date().timeIntervalSince(phoneLastCheck) > (phoneItems.isEmpty ? 0.6 : 1.5) else { return }
        // Harita/menü açıkken telefon aranmaz: haritanın aydınlık kısmı telefon sanılıp tuş listesi ("RECENTER") çevriliyordu.
        if Date() < menuScreenUntil.addingTimeInterval(8) || !mapItems.isEmpty {
            if !phoneItems.isEmpty { clearPhone() }
            return
        }
        phoneLastCheck = Date()
        let tracker = phoneTracker
        phoneTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) { () -> (PhonePanel.Panel, Reading)? in
                guard let panel = tracker.locate(in: frame) else { return nil }
                let box = panel.box
                let region = CropRegion(top: box.top, bottom: box.bottom, left: box.left, right: box.right)
                // Telefon işlemcide okunur (Neural Engine altyazı okumasına kalsın; bkz. VisionReader.cpuOnly).
                let reading = (try? VisionReader(language: "en", cpuOnly: true).readLines(RegionCropper.crop(frame, to: region), deep: false)) ?? .empty
                return (panel, reading.placed(in: box))
            }.value
            guard let self else { return }
            defer { phoneTask = nil }
            guard let (panel, reading) = found else {
                if !phoneItems.isEmpty, Date().timeIntervalSince(phoneSeen) > 1.2 { clearPhone() }
                return
            }
            // Haritanın tuş listesi ("RECENTER", "2D VIEW") telefon sanılan bölgede okunduysa bu haritadır.
            let mapKeys: Set<String> = ["recenter", "2d view", "3d view", "add marker", "set destination", "close menu"]
            if reading.lines.contains(where: { mapKeys.contains(MenuBlock.clean($0.text).lowercased()) }) {
                if !phoneItems.isEmpty { clearPhone() }
                return
            }
            // Sohbet: mesajlar balon olarak. Mesaj listesi çevrilmez. Başka uygulama (BuckMe bankası): satırları ayrı ayrı.
            // Başlığı ortalı uygulama ekranı ("Trip Details", Rydeme) sohbet sanılmasın: sohbette en az bir cümle olur.
            let threadMessages = PhoneThread.isThread(reading, panel: panel) ? PhoneThread.messages(in: reading, panel: panel) : []
            let chat = threadMessages.contains { PhoneThread.isSentence($0.text) }
            var messages = chat ? threadMessages
                : (PhoneThread.isMessageList(reading) ? [] : PhoneThread.appLines(in: reading, panel: panel))
            guard !messages.isEmpty else {
                if !phoneItems.isEmpty, Date().timeIntervalSince(phoneSeen) > 1.2 { clearPhone() }
                return
            }
            phoneSeen = Date()
            // Kaydırınca mesajların yeri değişir: anahtar yeri de içerir. Aynı okuma iki kez görülünce çevrilir
            // (kaydırma sürerken yarım okunan satırlar çevrilmez).
            // Yer telefonun ekranına göre ölçülür: el sallanınca anahtar değişmez (kaydırmayı trackPhone yapar), sohbet
            // kaydırılınca değişir.
            let key = messages.map { TextMatch.normalize($0.text) + "@\(Int(($0.box.top - panel.box.top) * 60))" }.joined(separator: "|")
            guard key != phoneKey else { return }
            // Nino: sohbet kaydırıldı ya da mesajlar değişti: eski Türkçeler hemen kalkar. Yoksa yenileri hazır olana kadar
            // (17 sn sürdüğü oldu) başka mesajların balonlarının üstünde yanlış yazı duruyordu.
            if let base = phoneBase, !phoneItems.isEmpty {
                let now = Dictionary(messages.map { (TextMatch.normalize($0.text), $0.box.top - panel.box.top) }, uniquingKeysWith: { a, _ in a })
                // Okuyucu bir mesajı arada kaçırabiliyor (6 → 5 → 6); bu kaydırma değildir. Ortak mesajlardan biri yer
                // değiştirdiyse ya da gösterilenlerin yarısından çoğu kaybolduysa sohbet kaydırılmıştır.
                let keys = base.items.filter { !$0.backdrop }.map { TextMatch.normalize($0.source) }
                let common = keys.filter { now[$0] != nil }
                let moved = common.contains { key in
                    guard let top = now[key], let anchor = phoneAnchors[key] else { return false }
                    return abs(anchor - top) > 0.02
                }
                let stale = moved || common.count * 2 < keys.count
                if stale {
                    phoneItems = []
                    phoneBase = nil
                    phoneKey = ""
                    sendOverlays()
                }
            }
            guard key == phonePending else { phonePending = key; return }
            let translator = makeTranslator()
            let translations = self.translations
            let game = translations.poolGame(gameChoice.sense.current?.name, packs.searchScope)
            let pooled = settings.sharePool
            // Bilinmeyen mesajlar aynı anda çevrilir (sırayla çevrilince kaydırmadan sonra Türkçeler çok geç geliyordu).
            if phoneMemoryLanguage != settings.targetLanguage {
                phoneMemoryLanguage = settings.targetLanguage
                phoneMemory = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: phoneMemoryFile))) ?? [:]
            }
            // Yarım okunan mesaj (son satırı ekranın dibinde kesik sanıldı) daha önce tam görüldüyse tam halinin çevirisi
            // kullanılır; yarım cümlenin çevirisi bozuk çıkıyordu ("…kilolarıma getir. Seni biraz keseceğim").
            let memory = phoneMemory
            func remembered(_ text: String) -> String? {
                let key = TextMatch.normalize(text)
                guard key.split(separator: " ").count >= 5 else { return memory[key] }
                // Sondan ya da baştan kesik okunan mesaj (üstte yarısı görünen) tam halinin çevirisini alır.
                return memory.filter { $0.key == key || $0.key.hasPrefix(key + " ") || $0.key.hasSuffix(" " + key) }
                    .max { $0.key.count < $1.key.count }?.value
            }
            // Ekranın dibinde cümlesi bitmemiş çok satırlı son mesaj, tamamı görünene kadar yarım çevrilmez.
            if chat, let last = messages.last, remembered(last.text) == nil,
               last.box.bottom > panel.box.bottom - 0.06, last.box.bottom - last.box.top > last.lineHeight * 1.8,
               !(last.text.trimmingCharacters(in: .whitespaces).last.map { ".!?…\")".contains($0) } ?? false) {
                messages.removeLast()
                guard !messages.isEmpty else { return }
            }
            // Nino: havuzun (elden geçmiş) çevirisi cihazın hafızasındakinden önce gelir; hafızada eski, kötü bir çeviri
            // kalmış olabilir (havuz o an boştu, cihaz çevirisi yazılmıştı: "drops" → "damla").
            // Ekranın üstünde baştan kesik (küçük harfle başlayan) ilk mesaj, tamamı görülmediyse yarım çevrilmez.
            if chat, let first = messages.first, messages.count > 1, remembered(first.text) == nil,
               first.text.first?.isLowercase == true {
                messages.removeFirst()
            }
            var texts = messages.map { PhoneThread.glossary($0.text) ?? translations.store.match($0.text) ?? remembered($0.text) ?? "" }
            let missing = messages.indices.filter { texts[$0].isEmpty }
            let sources = missing.map { messages[$0].text }
            // Nino: telefon mesajları da havuza bildirilir (altyazılar gibi); yoksa toplu çeviri ve elle düzeltme onları
            // hiç görmüyordu.
            if pooled || translations.isPoolFirst(game) {
                let pool = self.pool
                for text in sources { Task { await pool.offer(text, game: game) } }
            }
            // Sohbette her mesaj önceki (en çok üç) mesajla birlikte sorulur: kısaltma ve argo bağlamla doğru çevrilir.
            let contexts = missing.map { index in chat ? Array(messages[max(0, index - 3)..<index].map(\.text)) : [] }
            // Aynı anda en çok iki çeviri: cihaz üstü çeviri Neural Engine'i yazı okumayla paylaşır; altısı birden
            // çalışınca okumalar yavaşlayıp "Vision takıldı" sanılıyordu.
            var fromDevice = Set<Int>()
            let translated = await withTaskGroup(of: (Int, String?, Bool).self) { group -> [Int: String] in
                var out: [Int: String] = [:]
                var next = 0
                func add() {
                    guard next < sources.count else { return }
                    let index = next, text = sources[index], context = contexts[index]
                    next += 1
                    group.addTask {
                        var turkish: String? = translations.store.match(text)
                        if turkish == nil, pooled || translations.isPoolFirst(game) {
                            turkish = await translations.translate(text, context: context, game: game)
                        }
                        if turkish != nil { return (index, turkish, false) }
                        return (index, try? await translator.translate(text), true)
                    }
                }
                add(); add()
                for await (index, turkish, device) in group {
                    if let turkish { out[index] = turkish }
                    if device { fromDevice.insert(index) }
                    add()
                }
                return out
            }
            for (slot, index) in missing.enumerated() {
                let clean = translated[slot].map(Self.withoutIcons)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // Nino: cihazın yedek çevirisi hafızaya yazılmaz; sonraki okumada havuz yeniden sorulur (o arada havuza
                // doğru çeviri girmiş olabilir).
                if !clean.isEmpty, !fromDevice.contains(slot) { phoneMemory[TextMatch.normalize(messages[index].text)] = clean }
                texts[index] = clean
            }
            if phoneMemory.count > 600 { phoneMemory.removeAll() }
            if !missing.isEmpty, let data = try? JSONEncoder().encode(phoneMemory) { try? data.write(to: phoneMemoryFile, options: .atomic) }
            guard !Task.isCancelled else { return }
            // Kullanıcı isteği (20 Kasım 2026): Türkçe her mesaj balonunun tam üstünde, balonun rengiyle; telefonun kendi
            // yazısı gibi görünür (eskiden telefonun yanında yarı saydam yazıydı).
            // Sohbet: telefonun yanında dikey mesajlaşma paneli. Uygulama (BuckMe): her yazının hemen altında sade Türkçe
            // (kullanıcı isteği, 20 Kasım 2026; telefonun Türkçe kopyası "elle yapıştırılmış" duruyordu, kaldırıldı).
            phoneItems = chat
                ? PhoneThread.sideBubbles(for: messages, translations: texts, panel: panel, chat: true,
                                          title: PhoneThread.titleText(reading, panel: panel),
                                          color: PhonePanel.liftedSampler(for: frame, panel: panel)) { text, width, line in
                    let wrapped = Self.wrap(text, width: width, line: line)
                    return (wrapped.count, wrapped.map(\.count).max() ?? 0)
                }
                : PhoneThread.appBubbles(for: messages, translations: texts, panel: panel, color: PhonePanel.liftedSampler(for: frame, panel: panel))
            phoneTexts = (messages.map(\.text), Date())
            phoneAnchors = Dictionary(messages.map { (TextMatch.normalize($0.text), $0.box.top - panel.box.top) }, uniquingKeysWith: { a, _ in a })
            // Kullanıcı isteği: panel telefonun yanında ayrı durur; telefon elde oynadıkça panel kaymaz. Telefon az oynadıysa
            // yeni yerleşim eski telefon yerine göre kurulur (panel yerinde kalır); ancak telefon belirgin taşınınca panel de gider.
            var anchorPanel = panel.box
            // Uygulama baloncukları da sabitlenir (kullanıcı: "neden kendi kendine büyüyor, hareket ediyor").
            if let old = phoneBase {
                let dx = (panel.box.left + panel.box.right - old.panel.left - old.panel.right) / 2
                let dy = (panel.box.top + panel.box.bottom - old.panel.top - old.panel.bottom) / 2
                if abs(dx) < Self.phoneSteady, abs(dy) < Self.phoneSteady {
                    phoneItems = PhoneThread.shifted(phoneItems, dx: -dx, dy: -dy)
                    anchorPanel = old.panel
                }
            }
            // Aynı mesaj yeniden okunduysa ve yeri az oynadıysa eski kutusu korunur (yazı boyu ve yeri zıplamasın).
            if let old = phoneBase {
                let current = PhoneThread.shifted(old.items, dx: phoneShift.dx, dy: phoneShift.dy)
                // Uygulama ekranındaki Türkçeler aynıysa (aynı haber sayfası) bütün yerleşim eskisi gibi kalır; baloncuklar
                // yeniden hesaplanıp birbirine binmesin.
                let sameScreen = !chat && current.count == phoneItems.count
                    && zip(current, phoneItems).allSatisfy { $0.translation == $1.translation && abs($0.box.top - $1.box.top) < 0.06 }
                phoneItems = sameScreen ? current : phoneItems.map { item in
                    // Uygulamada (haber paragrafı) aynı yazının boyu her okumada biraz farklı ölçülür; baloncuk büyüyüp
                    // küçülmesin diye aynı yazı yakın yerdeyse eski baloncuk olduğu gibi kalır.
                    let reach = chat ? (0.012, 0.015) : (0.04, 0.06)
                    guard let same = current.first(where: { $0.source == item.source && $0.translation == item.translation }),
                          abs(same.box.left - item.box.left) < reach.0, abs(same.box.top - item.box.top) < reach.1 else { return item }
                    return same
                }
            }
            phoneBase = (anchorPanel, phoneItems)
            phoneShift = (0, 0)
            phoneShiftSeen = nil
            phoneKey = key
            phonePending = ""
            let shown = phoneItems.filter { !$0.backdrop }
            SubtitleLog.write("telefon: \(shown.count) yazı" + (shown.first.map { " (\(SubtitleLog.excerpt($0.source)) → \($0.translation))" } ?? "") + (chat ? "" : " · uygulama"))
            sendOverlays()
        }
    }

    nonisolated static let lastGamePoolFirstKey = "ninoLastGamePoolFirst"

    // MARK: Harita (GTA 6): seçili görevin kartının Türkçesi kartın altında, yarı saydam

    private var mapItems: [ScreenTranslation.Item] = []
    private var mapKey = ""
    private var mapTask: Task<Void, Never>?
    /// Nino: çeviri sürerken seçilen yeni kart; süren çeviri bitince o çevrilir.
    private var mapPending: MapCard.Found?
    /// Bu oturumda çevrilmiş kartlar (anahtar → satırlar): haritada aynı yere dönülünce Türkçesi hemen gelir.
    private var mapMemory: [String: [String]] = [:]
    /// Ekrandaki Türkçenin ait olduğu kartın başlığı ve yeri.
    private var mapShown: (title: String, top: Double) = ("", -1)
    /// Ekrandaki kartın tam metni: aynı kartın yarım okuması (alttaki satır okunamadı) onun yerine geçmez.
    private var mapShownText = ""

    /// Nino: haritada seçili görevin kartı ("BUY FLOWERS / Lucia will appreciate this / Have some flowers delivered…")
    /// çevrilir ve kartın hemen altına (yer yoksa üstüne) yarı saydam yazılır. Menünün kalanı çevrilmez.
    private func showMapCard(_ card: MapCard.Found) {
        // Nino: PS5'in kendi bildirimi ("…, Uzaktan Oynama'yı kullanarak bağlandı.") zaten Türkçe; kart değildir.
        let all = ([card.title] + card.sentences).joined(separator: " ")
        if all.contains(where: { "ğışĞİŞ".contains($0) }) || card.sentences.isEmpty { return }
        // PS5'in sağ üstteki bildirimi (oturum adı "Ceviri Altyazi" ve tuş satırı) görev kartı değildir.
        if card.title.isEmpty, card.box.left > 0.6, card.box.top < 0.32 { return }
        // Ekranın en üstündeki sekme şeridi ("JASON  LUCIA  MAP  BRIEF  PROGRESS") ve PS5 bildirimi kart değildir.
        if card.box.top < 0.1 { return }
        let fullText = TextMatch.normalize(all)
        if !card.title.isEmpty, TextMatch.normalize(card.title) == mapShown.title, mapShownText.hasPrefix(fullText), mapShownText != fullText {
            return
        }
        let key = TextMatch.normalize(([card.title] + card.sentences).joined(separator: " ")) + "@\(Int(card.box.top * 50))"
        guard key != mapKey else { return }
        mapKey = key
        // Nino: imleç başka yere geçti; eski kartın Türkçesi yeni kartın altında kalmasın (GTA 6: "LADONNA'S SOUL FOOD"
        // kartının altında "CHIHUAHUA HOTDOG"un Türkçesi duruyordu). Yenisinin çevirisi gelene kadar boş kalır.
        // Aynı kart (aynı başlık, aynı yer) biraz farklı okunduysa ("0.26 ml" / "0.26 mi") eski Türkçe yenisi gelene
        // kadar kalır; yoksa kart her yeniden okumada yanıp sönerdi.
        let sameCard = !card.title.isEmpty && TextMatch.normalize(card.title) == mapShown.title && abs(card.box.top - mapShown.top) < 0.04
        if !mapItems.isEmpty, !sameCard { mapItems = []; sendOverlays() }
        if let lines = mapMemory[key] { placeMapCard(card, lines: lines); return }
        // Çeviri sürüyorsa yeni kart beklemeye alınır (en son seçilen); süren bitince o çevrilir.
        guard mapTask == nil else { mapPending = card; return }
        mapPending = nil
        let translator = makeTranslator()
        let translations = self.translations
        let game = translations.poolGame(gameChoice.sense.current?.name, packs.searchScope)
        let pooled = settings.sharePool && settings.sourceLanguage == "en"
        mapTask = Task { [weak self] in
            let turkish: (String) async -> String = { piece in
                var result: String? = translations.store.match(piece)
                if result == nil, pooled { result = await translations.translate(piece, game: game) }
                if result == nil { result = try? await translator.translate(piece) }
                return Self.withoutIcons(result ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let line = min(max(card.lineHeight, 0.02), 0.032) * 0.85
            let width = max(0.26, card.box.right - card.box.left)
            var lines: [String] = []
            if !card.title.isEmpty {
                let title = await turkish(card.title.capitalized)
                if !title.isEmpty { lines.append(title.uppercased(with: Locale(identifier: "tr"))) }
            }
            for sentence in card.sentences {
                let text = await turkish(sentence)
                // Satırlara bölünmez (TV kutunun genişliğine göre böler); terim düzeltmesi bütün cümlede yapılır.
                if !text.isEmpty { lines.append(Self.withMapTerms(Self.withoutEntities(text))) }
            }
            guard let self else { return }
            mapTask = nil
            if !lines.isEmpty { mapMemory[key] = lines }
            if mapMemory.count > 200 { mapMemory.removeAll() }
            if let next = mapPending {
                // Çeviri sürerken imleç başka karta geçti: bu sonuç gösterilmez, en son kart çevrilir.
                mapPending = nil
                mapKey = ""
                showMapCard(next)
                return
            }
            guard mapKey == key, !lines.isEmpty, Date() < menuScreenUntil else { return }
            placeMapCard(card, lines: lines)
        }
    }

    /// Kartın Türkçesi kartın hemen altına (yer yoksa üstüne) yarı saydam yazılır.
    /// Nino: oyunun sık geçen terimlerinin yanlış çevirileri düzeltilir ("marked bills" → işaretli banknot, "lockup" → depo).
    static func withMapTerms(_ text: String) -> String {
        let fixes: [(String, String)] = [
            ("KAPALI TUTULMASI", "DEPOSU"), ("Kapalı Tutulması", "Deposu"), ("kapalı tutulması", "deposu"),
            ("işaretli faturaların", "işaretli banknotların"), ("işaretli faturalar", "işaretli banknotlar"),
            ("işaretli fatura", "işaretli banknot"), ("narkotik", "uyuşturucu"), ("NARKOTİK", "UYUŞTURUCU"),
            ("trafik ışığı papağan balığı", "stoplight papağan balığı"), ("kırmızı ışık papağan balığı", "stoplight papağan balığı"),
        ]
        return fixes.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// Nino: kartın başlığı bir dükkân ya da mekân adıysa ("RIDEOUT CUSTOMS", "ONE-EYED WILLIE'S AUTO SHOP") çevrilmez;
    /// "DIŞARIDAN GELEN GÜMRÜK" gibi saçma çıkıyordu.
    static func isPlaceName(_ title: String, description: String = "") -> Bool {
        // Açıklama bir işletmeyi anlatıyorsa ("Ammu-Nation distributor…", "Mod shop…", "dive bar…") başlık onun adıdır.
        let business = ["distributor", "shop", "store", "dive bar", " bar", "restaurant", "dealer", "club", "diner", "garage",
                        "convenience", "wholesaler", "boutique", "salon", "motel", "hotel", "bodega"]
        let about = description.lowercased()
        if business.contains(where: { about.contains($0) }) { return true }
        let words = title.uppercased().split(separator: " ").map(String.init)
        let places: Set<String> = ["CUSTOMS", "AUTO", "SHOP", "BAR", "CLUB", "MOTORS", "GARAGE", "CARE", "SPEEDWAY", "DINER",
                                   "CAFE", "GRILL", "MOTEL", "HOTEL", "STORE", "MART", "LOUNGE", "SALOON", "TACKLE", "ANCHOR",
                                   "MARINA", "AMMU-NATION", "BARBER", "TATTOO", "PAWN"]
        // "JASON'S MAILBOX", "DONNIE'S TRAILER" çevrilir (Jason'ın Posta Kutusu); yalnız işletme adları kalır.
        return words.contains(where: places.contains) || (title.uppercased().hasPrefix("THE ") && words.count <= 4)
    }

    private func placeMapCard(_ card: MapCard.Found, lines: [String]) {
        var lines = lines.map(Self.withoutEntities).map(Self.withMapTerms)
        if !card.title.isEmpty, !lines.isEmpty, Self.isPlaceName(card.title, description: card.sentences.joined(separator: " ")) {
            lines[0] = card.title
        }
        var line = min(max(card.lineHeight, 0.02), 0.032) * 0.85
        // Kullanıcı isteği: oyunun kartı gibi; kartın çerçevesiyle (yazıları değil, köşeleri) aynı genişlikte, hemen
        // altında; yer yoksa üstünde; o da yetmezse yazı küçülür.
        let frame = lastFrame.flatMap { MapCard.frame(around: card.box, in: $0) }
            ?? TextBox(left: card.box.left - 0.015, top: card.box.top - 0.02, right: card.box.right + 0.015, bottom: card.box.bottom + 0.02)
        // Kullanıcı: kutu kart kadar büyük olmak zorunda değil; yazı kadar. Kartın çerçevesi yalnız sınırdır (sol kenar,
        // en çok genişlik, altına/üstüne yerleşme).
        // Dar yazı tipi: bir harf satır yüksekliğinin yaklaşık %42'si.
        let charWidth = line * 0.42 * 9 / 16
        let longest = Double(lines.map(\.count).max() ?? 10)
        let width = min(frame.right - frame.left, longest * charWidth + 0.035)
        let wrapped = lines
        let rows = lines.enumerated().map { index, text in
            index == 0 ? 1 : max(1, Int((Double(text.count) * charWidth / (width - 0.03)).rounded(.up)))
        }.reduce(0, +)
        var height = line * Double(rows) * 1.32 + 0.022
        let below = 0.97 - (frame.bottom + 0.012), above = frame.top - 0.012 - 0.02
        var top = frame.bottom + 0.012
        if height > below {
            if height <= above || above > below {
                if height > above { line *= (above - 0.022) / (height - 0.022); height = above }
                top = frame.top - 0.012 - height
            } else {
                line *= (below - 0.022) / (height - 0.022); height = below
            }
        }
        var item = ScreenTranslation.Item(source: ([card.title] + card.sentences).joined(separator: " "),
                                          translation: wrapped.joined(separator: "\n"),
                                          box: TextBox(left: max(frame.left, card.box.left - 0.014), top: top,
                                                       right: max(frame.left, card.box.left - 0.014) + width, bottom: top + height),
                                          lineHeight: line)
        item.card = true
        mapItems = [item]
        mapShown = (TextMatch.normalize(card.title), card.box.top)
        mapShownText = TextMatch.normalize(([card.title] + card.sentences).joined(separator: " "))
        SubtitleLog.write("harita kartı: \(SubtitleLog.excerpt(item.source)) → \(lines.joined(separator: " / "))")
        sendOverlays()
    }

    private func clearMapCard() {
        mapItems = []
        mapKey = ""
        mapPending = nil
    }

    private func clearPhone() {
        phoneItems = []
        phoneBase = nil
        phoneKey = ""
        phonePending = ""
        sendOverlays()
    }

    /// Sol üst: oyunun ipucu kutusu ("HELP"); ekranın en üstünden başlar (RDR2'de ilk satır en üstte, %4'ün üstünde).
    /// Kullanıcı isteği: yalnız altyazı ve sol üstteki ipucu kutusu çevrilir; alt bant (menü, tuş listesi) kapalı,
    /// çünkü çok yazı birden kaplanınca ekran bozuk görünüyordu.
    /// En alttaki görev ve öğretici satırı ("Chase down and lasso the O'Driscoll", "… hold □ to stow …") da çevrilir;
    /// yalnız ortalanmış satırlar alınır (sağdaki menü ve tuş listeleri değil).
    /// Görev şeridi oyunun öğrenilen altyazı şeridinin altından başlar (`hudTop`); altyazısı en altta olan oyunda yoktur.
    private var cornerRegions: [CropRegion] {
        // Nino: GTA 6'nın yardım kutusu ekranın ortasına kadar iner ("… approach the / water."); son satırı kesilmesin.
        var regions = [CropRegion(top: 0.0, bottom: 0.48, left: 0.0, right: 0.40)]
        if let hudTop = currentHudTop { regions.append(CropRegion(top: hudTop, bottom: 0.995, left: 0.08, right: 0.92)) }
        return regions
    }

    /// Nino: görev şeridindeki satır altyazının yerinde ya da altyazıyla aynıysa (altyazı okuyucusu çevirdi) atlanır.
    nonisolated static func repeatsSubtitle(_ line: TextLine, box: TextBox?, text: String) -> Bool {
        if let box, let own = line.box, own.top < box.bottom + 0.01, box.top - 0.01 < own.bottom,
           own.left < box.right, box.left < own.right { return true }
        let read = TextMatch.normalize(line.text)
        guard read.count >= 6, !text.isEmpty else { return false }
        if text.contains(read) || read.contains(text) { return true }
        let words = Set(read.split(separator: " ")), shown = Set(text.split(separator: " "))
        return !words.isEmpty && Double(words.intersection(shown).count) / Double(words.count) >= 0.5
    }

    /// Alt şeritte ekranın ortasına yakın duran satır görev/öğretici yazısıdır; kenardaki menü yazıları atlanır.
    private static func isObjectiveLine(_ line: TextLine) -> Bool {
        guard let box = line.box else { return false }
        // Konuşan adıyla başlayan satır altyazıdır (ana okuyucu alır); görev kutusunda ikinci kez gösterilmez.
        if SpeakerPrefix.split(line.text) != nil { return false }
        let center = (box.left + box.right) / 2
        return center > 0.32 && center < 0.68
    }
    /// Nino: oyunların altyazı yeri öğrenilir (bkz. `SubtitleLayout`); bu çizginin altındaki yazılar altyazı sayılmaz.
    private lazy var layoutStore = SubtitleLayoutStore(file: AppFolder.support.appendingPathComponent("subtitle-layout.json"))
    /// Şu anki oyun (çeviri paketinden); bilinmiyorsa "genel".
    private var currentGame: String { packs.searchScope ?? "genel" }
    /// Okunan altyazı alanı: altyazının yeri öğrenildiyse yalnız o şerit (bkz. SubtitleLayout.readTop).
    private var readRegion: CropRegion {
        var region = settings.region
        if let top = layoutStore.current.readTop(for: currentGame), top > region.top, top < region.bottom - 0.06 { region.top = top }
        return region
    }
    private var currentHudTop: Double? { layoutStore.current.hudTop(for: currentGame) }
    /// Nino: havuz öncelikli oyunda (GTA 6) altyazının yerinde olmayan ve havuzda bilinmeyen yazı gösterilmez (tabela).
    /// Başka oyunlarda kural kapalıdır: paketi olmayan oyunda her satır "bilinmeyen"dir.
    private var currentSubtitleFloor: Double? {
        let poolGame = gameChoice.sense.current == nil ? UserDefaults.standard.bool(forKey: Self.lastGamePoolFirstKey) : liveGamePoolFirst
        return poolGame ? layoutStore.current.baselineFloor(for: currentGame) : nil
    }
    /// Nino: tuş ipuçları çevrilir; çeviri ipucunun hemen üstünde durur (simge örtülmez).
    private static let translatePrompts = true

    private static let cornerNames = ["sol üst", "görev", "menü"]
    /// Menülerin (harita, duraklatma, kıyafet dolabı) Türkçesi gösterilmez (kullanıcı isteği, 19 Kasım 2026).
    private static let translateMenus = false

    /// Köşeleri ~1,5 sn'de bir okur; yazı değiştiyse çevirip TV'de kendi yerine koyar (Ekranı çevir'deki gibi).
    private func watchCorners(_ frame: CGImage) {
        guard settings.translateCorners, cornerTask == nil, screenTask == nil,
              Date().timeIntervalSince(cornerLastCheck) > 1.5 else { return }
        cornerLastCheck = Date()
        // İpucu ve görev satırlarında simge çoğu zaman yazının başında durur ("△ Get back on the wagon").
        let reader = VisionReader(language: settings.sourceLanguage, edgeIcons: true)
        // Menü okumasında simge aranmaz: simgeler Türkçeye karışıyordu ("⊙ Mağaza", "0] Fotoğraf Stüdyosu").
        let menuReader = VisionReader(language: settings.sourceLanguage, edgeIcons: false)
        let recentMenu = Date().timeIntervalSince(menuSeenAt) < 6 ? menuBoxes : []
        var regions = cornerRegions
        while regions.count < 2 { regions.append(CropRegion(top: 1, bottom: 1, left: 0, right: 0)) }
        // Nino: menüler (duraklatma menüsü) bütün ekranda aranır; iki okumada bir.
        // Bütün ekranın okunması yazı tanımayı yoruyor: üç köşe okumasında bir (~4,5 sn) ve küçültülmüş kareyle.
        menuCounter = (menuCounter + 1) % 3
        // Menü/harita ekranı açıkken her okumada bakılır (oyun durmuştur; kart değişince Türkçesi çabuk gelsin).
        // Harita az önce açıktıysa (sekme değişirken bir okumada tanınmamış olabilir) bir süre daha her okumada bakılır;
        // yoksa sol menünün satırları ipucu kutusu sanılıp Türkçesi alttaki satırların üstüne biniyordu (GTA 6, EXPLORATION).
        let readMenu = menuCounter == 0 || Date() < menuScreenUntil.addingTimeInterval(10)
        regions.append(CropRegion(top: 0.03, bottom: 0.95, left: 0.0, right: 1.0))
        let subtitleBox = lastSubtitleBox
        let subtitleText = TextMatch.normalize(lastSource)
        cornerTask = Task { [weak self] in
            var readings = [Reading?](repeating: nil, count: regions.count)
            var menus: [MenuBlock.Group] = []
            var menuScreen = false
            var mapCard: MapCard.Found?
            for (i, region) in regions.enumerated() {
                if region.bottom <= region.top { readings[i] = .empty; continue }
                if i == 2, !readMenu { continue }
                let place = TextBox(left: region.left, top: region.top, right: region.right, bottom: region.bottom)
                let use = i == 2 ? menuReader : reader
                let reading = await Task.detached(priority: .utility) { () -> Reading in
                    var area = RegionCropper.crop(frame, to: region)
                    if i == 2, let small = Self.downscaled(area, maxWidth: 1280) { area = small }
                    return ((try? use.readLines(area, deep: false)) ?? .empty).withoutOcrNoise().placed(in: place)
                }.value
                if i == 2, MenuBlock.isMenuScreen(reading) { menuScreen = true }
                // Nino: harita ekranı da menüdür (sol liste ve tuşlar çevrilmez); yalnız seçili görevin kartı çevrilir.
                if i == 2, MapCard.isMapScreen(reading) {
                    menuScreen = true
                    mapCard = MapCard.find(in: reading)
                }
                if i == 2 {
                    menus = MenuBlock.groups(in: Reading(lines: reading.lines.map { line in
                        var cleaned = line
                        cleaned.text = MenuBlock.clean(line.text)
                        return cleaned
                    }.filter { !$0.text.isEmpty }))
                    readings[i] = Reading(lines: menus.flatMap(\.lines))
                    continue
                }
                // Sol üst: yalnız ipucu kutusu ya da görev kartı (haritadaki yer adları değil; bkz. CornerBlock).
                // Görev şeridi: altyazının bulunduğu yerdeki ya da altyazıyla aynı satır ikinci kez çevrilmez (altyazı
                // okuyucusu onu zaten çevirdi; ikinci okuma bozuk çıkıp altyazının üstüne biniyordu).
                readings[i] = i == 1 ? Reading(lines: reading.lines.filter { line in
                    Self.isObjectiveLine(line) && !Self.repeatsSubtitle(line, box: subtitleBox, text: subtitleText)
                }) : CornerBlock.tipBox(in: reading)
            }
            // Menü ekrandayken (son 6 sn'de görüldüyse) sol üst kutusu menü satırlarını ikinci kez çevirmez.
            guard let self else { return }
            var changedPrompts = false
            if menuScreen {
                // Harita/duraklatma ekranı: tuş ipuçları çevrilmez (yer adları "Chuck's Tackle & Shot" ipucu sanılıyordu).
                menuScreenUntil = Date().addingTimeInterval(5)
                menuScreenFlag.set(until: menuScreenUntil)
                if !promptItems.isEmpty { promptItems = []; promptText = ""; changedPrompts = true }
            }
            // Nino: harita/görev menüsünün sol listesi ("◆ Earn Money / OPTIONAL / …") menü tanınmadan önce de ipucu sayılmaz.
            if let corner = readings[0] {
                let texts = corner.lines.map { $0.text.trimmingCharacters(in: .whitespaces) }
                let headings = texts.contains { ["OPTIONAL", "STORY", "SIDE", "COMPLETED", "ACTIVITIES"].contains($0.uppercased()) && $0 == $0.uppercased() }
                let bullets = texts.filter { $0.hasPrefix("◆") || $0.hasPrefix("♦") }.count
                if headings || bullets >= 2 {
                    readings[0] = nil
                    if !cornerItems[0].isEmpty { cornerItems[0] = []; cornerTexts[0] = ""; cornerPending[0] = ""; changedPrompts = true }
                }
            }
            if Date() < menuScreenUntil {
                // Menü/harita ekranında sol üstteki liste ipucu kutusu değildir ("STORY / Pick Up Lucia / OPTIONAL");
                // Türkçesi listenin üstüne biniyordu.
                readings[0] = nil
                if !cornerItems[0].isEmpty { cornerItems[0] = []; cornerTexts[0] = ""; cornerPending[0] = ""; changedPrompts = true }
            }
            if readMenu {
                if let mapCard { showMapCard(mapCard) } else if !mapItems.isEmpty { clearMapCard(); changedPrompts = true }
            }
            if readMenu {
                let boxes = (readings[2]?.lines ?? []).compactMap(\.box)
                if !boxes.isEmpty { menuSeenAt = Date(); menuBoxes = boxes }
            }
            let menuArea = readMenu ? (readings[2]?.lines ?? []).compactMap(\.box) : recentMenu
            if !menuArea.isEmpty, let corner = readings[0] {
                readings[0] = Reading(lines: corner.lines.filter { line in
                    guard let box = line.box else { return true }
                    return !menuArea.contains { $0.top < box.bottom + 0.02 && box.top - 0.02 < $0.bottom }
                })
            }
            var changed = changedPrompts
            let translator = makeTranslator()
            for i in 0..<readings.count {
                guard let reading = readings[i] else { continue }
                let text = reading.text
                if text == cornerTexts[i] { cornerEmptyReads[i] = 0; continue }
                // Kullanıcı isteği: görev yazısı ekranda durdukça Türkçesi de durur. Okuma bir iki kez boş dönünce
                // (sahne geçişi, altyazı gelirken parlaklık) silinmez; ~6 sn (4 okuma) üst üste yoksa kalkar.
                if text.isEmpty, !cornerTexts[i].isEmpty {
                    cornerEmptyReads[i] += 1
                    // Menü kapanınca Türkçesi hemen kalkar (menü iki okumada bir okunur).
                    if cornerEmptyReads[i] < (i == 2 ? 1 : 4) { continue }
                }
                cornerEmptyReads[i] = 0
                if !text.isEmpty {
                    let seen = TextMatch.normalize(text), before = TextMatch.normalize(cornerPending[i])
                    cornerPending[i] = text
                    guard i == 2 || seen == before || (seen.count >= 30 && TextMatch.isSimilar(seen, before, threshold: 0.8)) else { continue }
                }
                cornerPending[i] = ""
                cornerTexts[i] = text
                changed = true
                // Kullanıcı isteği: yalnız oyunun yazıları çevrilir. Satırlarından biri zaten Türkçeyse bu PS5'in kendi
                // ekranıdır (ana ekran, menü); çevrilmez.
                let turkish = !text.isEmpty && TargetLanguage.hasLine(text, in: settings.targetLanguage)
                if turkish { systemScreenUntil = Date().addingTimeInterval(15) }
                if !text.isEmpty, turkish || Date() < systemScreenUntil {
                    if !cornerItems[i].isEmpty { SubtitleLog.write("köşe \(Self.cornerNames[i]): PS5 ekranı, çevrilmedi") }
                    cornerItems[i] = []
                    // Türkçe değilse bekleme bitince yeniden bakılsın (oyuna dönülünce çıkan ipucu kaçmasın).
                    if !turkish { cornerTexts[i] = "" }
                    continue
                }
                // Sol üst ipucu kutusu cümledir: en az üç gerçek sözcük. Duraklatma menüsünün kalıntısı ("11 Map", "Help")
                // ve okuma çöpü ("◆ KR)) SI") çevrilmez.
                if i == 0, !text.isEmpty,
                   text.split(whereSeparator: { !$0.isLetter && $0 != "'" }).filter({ $0.count >= 2 }).count < 3 {
                    if !cornerItems[i].isEmpty { cornerItems[i] = [] }
                    continue
                }
                let key = TextMatch.normalize(text)
                // Kısa yazıda tek harf anlamı değiştirir ("Follow John" / "Follow Josh"); benzerlik yalnız uzun kutuda.
                if let known = cornerMemory.last(where: { $0.text == key || (key.count >= 30 && TextMatch.isSimilar($0.text, key, threshold: 0.8)) }) {
                    cornerItems[i] = known.items
                    continue
                }
                // Nino: sol üstteki görev kutusu (i == 0, oyunun kendi yazısı) de çeviri havuzundan / Claude'dan gelir;
                // havuz yoksa ya da cevap gelmezse cihazın çevirisi. Alt şerit yalnız cihazla çevrilir.
                let pooled = i != 1 && self.settings.sharePool && self.settings.sourceLanguage == "en"
                let translations = self.translations
                let game = self.packs.searchScope ?? self.gameChoice.sense.current?.name
                if i == 2, !Self.translateMenus {
                    // Kullanıcı isteği: harita ve duraklatma menüleri çevrilmez; menü yalnız sol üst kutusunun onu
                    // çevirmemesi için tanınır.
                    cornerItems[i] = []
                    continue
                }
                if i == 2 {
                    // Menü: her satır ayrı çevrilir, Türkçesi satırın yanına (sağa yaslıda soluna) sade yazıyla konur.
                    var items: [ScreenTranslation.Item] = []
                    let turkishTarget = self.settings.targetLanguage == "tr"
                    for group in menus {
                        var texts: [String] = []
                        for line in group.lines {
                            let piece = line.text
                            var translated: String? = turkishTarget ? MenuBlock.knownTurkish(piece) : nil
                            if translated == nil, pooled {
                                translated = translations.store.match(piece)
                                if translated == nil { translated = await translations.translate(piece, game: game) }
                            }
                            if translated == nil { translated = try? await translator.translate(piece) }
                            texts.append(MenuBlock.clean(translated?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""))
                        }
                        let boxes = MenuBlock.placeColumn(group, translations: texts)
                        for (index, line) in group.lines.enumerated() {
                            let turkish = texts[index]
                            guard !turkish.isEmpty, TextMatch.normalize(turkish) != TextMatch.normalize(line.text), let box = line.box else { continue }
                            var item = ScreenTranslation.Item(source: line.text, translation: turkish, box: boxes[index],
                                                              lineHeight: box.bottom - box.top)
                            item.plain = true
                            items.append(item)
                        }
                    }
                    if Task.isCancelled { return }
                    cornerItems[i] = Self.steady(items, previous: cornerItems[i])
                    if !items.isEmpty {
                        cornerMemory.append((key, items))
                        if cornerMemory.count > 40 { cornerMemory.removeFirst() }
                    }
                    SubtitleLog.write("menü: \(items.map { "\($0.source) → \($0.translation)" }.joined(separator: " / "))")
                    continue
                }
                let translatePiece: (String) async throws -> String = { piece in
                    if pooled {
                        if let known = translations.store.match(piece) { return known }
                        if let fresh = await translations.translate(piece, game: game) { return fresh }
                    }
                    return try await translator.translate(piece)
                }
                // Görev kartı: büyük harfli başlık ("UNWANTED ATTENTION") metne karışmasın; ayrı çevrilir, üstte büyük harfle.
                var title = ""
                var body = reading
                if i == 0, reading.lines.count >= 2, let first = reading.lines.first, Reading.isItemLabel(first.text) {
                    title = ((try? await translatePiece(first.text)) ?? first.text).uppercased(with: Locale(identifier: "tr"))
                    body = Reading(lines: Array(reading.lines.dropFirst()))
                }
                cornerItems[i] = text.isEmpty ? [] :
                    ((try? await ScreenTranslation.translate(body, using: translatePiece)) ?? [])
                if !title.isEmpty, var firstItem = cornerItems[i].first {
                    firstItem.translation = title + "\n" + firstItem.translation
                    cornerItems[i][0] = firstItem
                }
                // Nino: sol üstteki görevin çevirisi görevin üstüne değil hemen altına konur (oyunun yazısı ve işareti görünür).
                if i == 0 {
                    cornerItems[i] = cornerItems[i].map { item in
                        var moved = item
                        // Bloğun tamamının altına (satırlara değmeden), simgesiz ve kutusuz, oyunun yazısı gibi.
                        // Kullanıcı isteği: Türkçe oyunun yazısından küçük (yarı saydam not gibi), ekranı kaplamaz.
                        let line = min(item.lineHeight > 0 ? item.lineHeight : 0.03, 0.032) * 0.8
                        moved.lineHeight = line
                        // Türkçe oyunun kutusu gibi: aynı genişlikte, birkaç satır, simgesiz (tek uzun satır ekranı kesiyordu).
                        let right = max(item.box.right, item.box.left + 0.2)
                        var parts = item.translation.split(separator: "\n").map { Self.withoutLeadingSymbols(String($0)) }
                        // Görev başlığı (büyük harf) kendi satırında kalır.
                        let heading = parts.count >= 2 && parts[0] == parts[0].uppercased(with: Locale(identifier: "tr"))
                            && parts[0].contains(where: \.isLetter) ? parts.removeFirst() : nil
                        let text = Self.withoutIcons(parts.joined(separator: " "))
                        let wrapped = (heading.map { [Self.withoutIcons($0)] } ?? []) + Self.wrap(text, width: right - item.box.left, line: line)
                        let lines = Double(wrapped.count)
                        let top = min(1 - line * lines * 1.3, item.box.bottom + line * 0.8 + 0.03)
                        moved.box = TextBox(left: item.box.left, top: top, right: right, bottom: top + line * lines * 1.3)
                        moved.translation = wrapped.joined(separator: "\n")
                        moved.plain = true
                        return moved
                    }
                }
                // Nino: bu arada çeviri dili değiştiyse (resetCorners) eski dildeki sonuç belleğe yazılmaz.
                if Task.isCancelled { return }
                // Nino: çeviri sürerken harita/menü açıldıysa sol üstteki liste ipucu değildir; geç gelen Türkçesi
                // haritanın sol menüsünün üstüne biniyordu (kullanıcı: "soldakilerin çevirisine gerek yok").
                if i == 0, Date() < menuScreenUntil {
                    cornerItems[0] = []; cornerTexts[0] = ""; cornerPending[0] = ""
                    continue
                }
                if !text.isEmpty, !cornerItems[i].isEmpty {
                    cornerMemory.append((key, cornerItems[i]))
                    if cornerMemory.count > 40 { cornerMemory.removeFirst() }
                }
                SubtitleLog.write("köşe \(Self.cornerNames[i]): \"\(text.replacingOccurrences(of: "\n", with: " / "))\" → \(cornerItems[i].map(\.translation).joined(separator: " / "))")
            }
            if changed { sendOverlays() }
            cornerTask = nil
        }
    }

    private func resetCorners() {
        cornerTask?.cancel()
        cornerTask = nil
        cornerTexts = ["", "", ""]
        cornerItems = [[], [], []]
        cornerMemory = []
        cornerPending = ["", "", ""]
        promptTask?.cancel()
        promptTask = nil
        promptText = ""
        promptItems = []
    }

    /// Ekran çevrilemedi: nedeni TV'de (ve bilgisayardaki altyazıda) birkaç saniye görünür, sessizce kaybolmaz.
    private func showScreenFailure(_ error: Error, translator: TextTranslator) {
        guard !Task.isCancelled else { return }
        server.clear()
        let reason = Self.screenFailureReason(error, translator: translator, engine: settings.onlineEngine, server: settings.localAIServer)
        server.sendSubtitle(String(format: String(localized: "Couldn't translate the screen: %@"), reason), durationMs: 6000)
    }

    /// Ekran çevirisinin neden olmadığı: önce çevrimiçi motorun hatası, sonra ücretsiz çevirinin durumu.
    static func screenFailureReason(_ error: Error, translator: TextTranslator, engine: TranslationEngine,
                                    server: LocalAIServer?) -> String {
        if let online = ((translator as? PoolFirstTranslator)?.engine ?? translator) as? AITranslator {
            if let failure = online.lastFailure { return TranslationCard.describe(failure, engine: engine, server: server) }
            if online.lastLineWasRateLimited {
                return String(format: String(localized: "%@ has reached its per-minute limit. Try again in a minute."), engine.displayName)
            }
        }
        switch error as? TranslatorError {
        case .needsDownload: return String(localized: "The free translation isn't downloaded yet.")
        case .unsupported: return String(localized: "The free translation doesn't work on this Mac.")
        case nil: return String(localized: "Something went wrong. Try again.")
        }
    }

    private func hideScreen() {
        screenShownUntil = .distantPast
        server.clearScreen()
        server.clear()
    }

    func tvMoved(to moved: LGTV) {
        tv = moved
        store.save(moved, for: StoreKey.tv)
    }

    /// Okuma hattını güncel dillerle (yeniden) kurar.
    private func makePipeline() {
        pipeline?.reset()
        // Eski hatta süren okuma beklenmez; yeni hat ilk karesini hemen alır.
        frameGate.reset()
        let scheduler = ReadScheduler(maxReuse: settings.fastSubtitleDetection
            ? ReadScheduler.fastMaxReuse : ReadScheduler.defaultMaxReuse)
        let pipeline = SubtitlePipeline(reader: VisionReader(language: settings.sourceLanguage),
                                        translator: makeTranslator(),
                                        server: server, scheduler: scheduler)
        pipeline.showSpeakerNames = settings.showSpeakerNames
        pipeline.onPair = { [weak self, weak pipeline] source, translation in
            self?.lastSource = source
            self?.lastTranslation = translation
            self?.addToHistory(source: source, translation: translation, origin: pipeline?.lastOrigin == "paket" ? .pack : .engine)
            if let self { self.gameChoice.noteLine(fromPack: pipeline?.lastOrigin == "paket", packs: self.packs) }
            if let box = pipeline?.lastBox, let self {
                self.lastSubtitleBox = box
                // Nino: altyazının yeri bu oyun için öğrenilir; sınır her satırda güncellenir.
                let game = self.currentGame
                let before = self.layoutStore.current.band(for: game) == nil
                self.layoutStore.record(box, game: game)
                pipeline?.hudTop = self.currentHudTop
                pipeline?.subtitleFloor = self.currentSubtitleFloor
                if before, let band = self.layoutStore.current.band(for: game) {
                    SubtitleLog.write(String(format: "altyazı yeri öğrenildi (%@): %.3f–%.3f, sınır %@", game, band.top, band.bottom,
                                             self.currentHudTop.map { String(format: "%.3f", $0) } ?? "yok"))
                }
            }
        }
        pipeline.onMetrics = { [weak self] metrics in
            self?.lastMetrics = metrics
            HealthRecorder.shared.line(translationMs: metrics.translationMs)
        }
        pipeline.onPrompts = { [weak self] prompts in self?.showPrompts(prompts) }
        // Nino (kullanıcı fikri): telefon uygulamasının sözcükleri görülünce telefon oradan da bulunur.
        pipeline.onPhoneUI = { [weak self] boxes in
            guard let self, let frame = self.lastFrame else { return }
            self.phoneTracker.adopt(around: boxes, in: frame)
        }
        pipeline.phoneTexts = { [weak self] in
            guard let self, Date().timeIntervalSince(self.phoneTexts.at) < 30 else { return [] }
            return self.phoneTexts.texts
        }
        pipeline.onMessage = { [weak self] card in self?.showMessage(card) }
        let menuFlag = menuScreenFlag
        pipeline.isMenuScreen = { menuFlag.active }
        // En alttaki öğretici/menü yazısı altyazı sanılmasın; yoksa üstündeki gerçek altyazı hiç okunmuyordu.
        pipeline.hudTop = currentHudTop
        pipeline.subtitleFloor = currentSubtitleFloor
        pipeline.targetLanguage = settings.targetLanguage
        pipeline.onAlreadyTarget = { [weak self] in self?.systemScreenUntil = Date().addingTimeInterval(15) }
        // Dil paketi bu arada indirilmiş olabilir; her çeviri sonucu durumu günceller.
        pipeline.onTranslationResult = { [weak self] error in
            self?.translatorStatus = Self.translatorStatus(after: error)
        }
        pipeline.onReadResult = { [weak self] error in self?.noteRead(error) }
        pipeline.onSpeech = { [weak self] lines in self?.speak(lines) }
        pipeline.onLog = { SubtitleLog.write($0) }
        onlineIssue = nil
        pipeline.warmUp()
        self.pipeline = pipeline
        // Ek alan okuyucusu yeni dil ve motorla, ilk ek alan karesinde yeniden kurulur.
        regionWatcher?.reset()
        regionWatcher = nil
        connectPacks(to: pipeline)
        identifyTries = 0
        identifyChecks = 0
        identifyLast = Date()
        startTranslationSync()
        activeLanguages = (settings.sourceLanguage, settings.targetLanguage)
    }

    /// Ek alanlar aynı dil, motor ve paketlerle okunur; ayrı bir okuyucu ve çevirmenle (altyazının sırasını beklemez).
    private func makeRegionWatcher(packLookup: ((String) -> PackMatch?)?) -> RegionWatcher {
        let watcher = RegionWatcher(reader: VisionReader(language: settings.sourceLanguage), translator: makeTranslator(), server: server)
        watcher.packLookup = packLookup
        watcher.onLog = { SubtitleLog.write($0) }
        return watcher
    }

    private func refreshTranslatorStatus() async {
        if onlineTranslationActive {
            translatorStatus = .ready
            return
        }
        translatorStatus = await Translator.status(source: settings.sourceLanguage, target: settings.targetLanguage)
    }

    // MARK: - Çevrimiçi çeviri (DeepL ve yapay zekâ)

    /// Nino: havuz öncelikli oyunda (sunucunun listesi, varsayılan GTA 6) çeviri yalnız havuzdan, gelmezse ücretsiz
    /// çeviriden; kullanıcının anahtarlı motoru çağrılmaz. Ortak havuz ayarı kapalı olsa da (kullanıcı kararı).
    private func makeTranslator() -> TextTranslator {
        let (source, target) = (settings.sourceLanguage, settings.targetLanguage)
        let free = Translator(source: source, target: target,
                              cache: Self.translationCache(engine: Translator.engineID, source: source, target: target))
        let (translations, packs, sense, recent) = (translations, packs, gameChoice.sense, recentLines)
        let english = source == "en"
        let translator = PoolFirstTranslator(engine: makeEngineTranslator(), free: free,
                                   poolFirst: { english && translations.isPoolFirst(translations.poolGame(sense.current?.name, packs.searchScope)) },
                                   ask: { line in
                                       // Oyun kesin değilse adı gönderilmez: sunucu satırdan ve bu kurulumun son oyunundan kendisi bulur
                                       // (paketten tahmin edilen yanlış oyun GTA 6'yı gölgelemesin).
                                       await translations.translateFirst(line, context: recent.before(line),
                                                                         game: sense.isSure || translations.poolFirst.contains(translations.poolGame(sense.current?.name, packs.searchScope))
                                                                             ? translations.poolGame(sense.current?.name, packs.searchScope) : nil)
                                   },
                                   // Oyun kesin bilinmiyorsa satır havuza da sorulur: sunucu GTA 6'yı satırdan tanır, sonraki
                                   // satırlar havuz öncelikli olur (yeniden açılışta tanıma 2 dk gecikebiliyordu).
                                   probe: { english && !sense.isSure })
        translator.log = { SubtitleLog.write($0) }
        return translator
    }

    /// Kullanıcının seçtiği çevirmen: ücretsiz, DeepL ya da yapay zekâ.
    private func makeEngineTranslator() -> TextTranslator {
        let (source, target) = (settings.sourceLanguage, settings.targetLanguage)
        // Önceki oturumların çevirileri motor ve dil çifti başına diskte durur; tekrar eden satır hemen gelir.
        let local = Translator(source: source, target: target,
                               cache: Self.translationCache(engine: Translator.engineID, source: source, target: target))
        let engine = settings.onlineEngine
        guard onlineTranslationActive, let storeKey = engine.storeKey else { return local }
        let online: TextTranslator & OnlineTranslating
        // Oynanan oyunun adı modele bağlam olarak gider, önbellek de oyuna göre ayrılır. Ad kararlı oyundur (`GameSense`:
        // PS5'in bildirdiği, kullanıcının seçtiği ya da son 20 satırın 5'i aynı paketten gelince o paketin oyunu); son
        // eşleşen paket değil, yoksa tek bir ortak satır adı başka oyuna geçirirdi (#27). Oyun bilinmiyorsa ad gitmez.
        let sense = gameChoice.sense
        let game: @Sendable () -> String? = { sense.current?.name }
        if engine == .local, let server = settings.localAIServer {
            // Yerel modelin anahtarı isteğe bağlıdır; önbellekte sunucu ve model ayrı tutulur.
            let key = store.load(String.self, for: storeKey) ?? ""
            online = AITranslator(provider: .local, key: key, model: server.model, server: server, fallback: local,
                                  cache: Self.translationCache(engine: server.engineID, source: source, target: target), target: target,
                                  game: game)
        } else if let key = store.load(String.self, for: storeKey), let provider = engine.aiProvider {
            let model = provider.model(settings.model(for: provider)).id
            online = AITranslator(provider: provider, key: key, model: model, fallback: local,
                                  cache: Self.translationCache(engine: provider.engineID(model: model), source: source, target: target),
                                  target: target, game: game)
        } else if let key = store.load(String.self, for: storeKey) {
            online = DeepLTranslator(key: key, fallback: local,
                                     cache: Self.translationCache(engine: DeepLTranslator.engineID, source: source, target: target),
                                     target: target)
        } else {
            return local
        }
        // Hizmet çeviremeyince ana ekranda uyarı çıkar; düzelince kalkar.
        online.onFailureChanged = { [weak self] state in
            Task { @MainActor in self?.onlineIssue = state }
        }
        return online
    }

    /// ~/Library/Application Support/CouchSubs/Translations içindeki kalıcı çeviri önbelleği.
    private static func translationCache(engine: String, source: String, target: String) -> TranslationCache {
        let directory = AppFolder.support
            .appendingPathComponent("Translations", isDirectory: true)
        return TranslationCache.shared(in: directory, engine: engine, source: source, target: target)
    }

    /// Çevrimiçi çeviri İngilizceden Nino'nun çeviri dillerine, seçili motor hazırsa ve o dili çevirebiliyorsa açılır.
    var onlineTranslationActive: Bool {
        settings.onlineTranslation && settings.sourceLanguage == "en"
            && TargetLanguage.choices.contains { $0.code == settings.targetLanguage }
            && (settings.onlineEngine != .deepL || TargetLanguage.deepLSupports(settings.targetLanguage))
            && isReady(settings.onlineEngine)
    }

    /// Motor kullanılabilir mi: bulut motorlarında anahtar kayıtlıdır; yerel modelde anahtar gerekmez, adres ve model adı
    /// geçerli olmalıdır. Sunucu kapalıysa satırlar ücretsiz çeviriyle gelir ve ana ekranda uyarı çıkar.
    func isReady(_ engine: TranslationEngine) -> Bool {
        engine == .local ? settings.localAIServer != nil : hasKey(engine)
    }

    /// Anahtarı kayıtlı motorlar (anahtarların kendisi arayüze hiç dönmez).
    @Published private var savedKeys: Set<TranslationEngine> = []

    func hasKey(_ engine: TranslationEngine) -> Bool { savedKeys.contains(engine) }

    /// Kayıtlı bir DeepL anahtarı var mı.
    var hasDeepLKey: Bool { hasKey(.deepL) }

    /// Anahtar denenir; geçerliyse (kotası bitmiş olsa da) Anahtarlık'a yazılır ve DeepL seçilir.
    func setDeepLKey(_ key: String) async -> OnlineKeyCheck {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let check = await services.checkOnlineKey(key)
        if check.state == .valid || check.state == .quotaExceeded { saveKey(key, for: .deepL) }
        return check
    }

    /// Kayıtlı anahtarın bu ayki kullanımı.
    func deepLUsage() async -> OnlineKeyCheck {
        guard let key = store.load(String.self, for: StoreKey.deepLKey) else { return OnlineKeyCheck(state: .invalid) }
        return await services.checkOnlineKey(key)
    }

    func removeDeepLKey() { removeKey(.deepL) }

    /// Yapay zekâ anahtarı örnek bir satırla denenir. Anahtar kabul edildiyse (bakiye bitmiş ya da model adı yanlış olsa
    /// da) Anahtarlık'a yazılır ve bu motor seçilir.
    func setAIKey(_ key: String, for provider: AIProvider) async -> Result<String, AIFailure> {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await services.testAIKey(provider: provider, key: key, model: settings.model(for: provider))
        switch result {
        case .success, .failure(.quotaExceeded), .failure(.modelRejected): saveKey(key, for: TranslationEngine(provider))
        case .failure: break
        }
        return result
    }

    /// Kayıtlı anahtar ve modelle örnek satırı çevirir (ayarlardaki "Dene").
    func testAIKey(for provider: AIProvider) async -> Result<String, AIFailure> {
        guard let storeKey = TranslationEngine(provider).storeKey, let key = store.load(String.self, for: storeKey) else {
            return .failure(.invalidKey)
        }
        return await services.testAIKey(provider: provider, key: key, model: settings.model(for: provider))
    }

    /// Ayarlardaki "Bağlantıyı dene": yerel model sunucusuna örnek satırı gönderir. `key` yazıldıysa o, yoksa kayıtlı
    /// anahtar kullanılır; yazılan anahtar sunucu kabul ettiyse Anahtarlık'a yazılır. Adres geçersizse sunucuya
    /// ulaşılamadı sayılır.
    func testLocalAI(key typed: String = "") async -> Result<String, AIFailure> {
        guard let server = settings.localAIServer else { return .failure(.unreachable) }
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = typed.isEmpty ? store.load(String.self, for: StoreKey.localAIKey) ?? "" : typed
        let result = await services.testLocalAI(server: server, key: key)
        if !typed.isEmpty {
            switch result {
            case .success, .failure(.quotaExceeded), .failure(.modelRejected): saveKey(typed, for: .local)
            case .failure: break
            }
        }
        return result
    }

    func removeKey(_ engine: TranslationEngine) {
        guard let storeKey = engine.storeKey else { return }
        store.remove(storeKey)
        savedKeys.remove(engine)
        if engine == .local {
            // Yerel modelin anahtarı isteğe bağlıdır: anahtarsız çeviri sürer, hat anahtarsız yeniden kurulur.
            if settings.translationEngine == .local, isRunning { makePipeline() }
            return
        }
        if settings.translationEngine == engine {
            settings.onlineTranslation = false
        } else {
            Task { await refreshTranslatorStatus() }
        }
    }

    private func saveKey(_ key: String, for engine: TranslationEngine) {
        guard let storeKey = engine.storeKey else { return }
        store.save(key, for: storeKey)
        savedKeys.insert(engine)
        if settings.translationEngine == engine {
            // Motor zaten seçiliydi, anahtar yeni geldi: hat yeni anahtarla kurulsun.
            if isRunning { makePipeline() }
            Task { await refreshTranslatorStatus() }
        } else {
            settings.translationEngine = engine
        }
    }

    // MARK: - PS5 giriş şifresi

    /// 4 haneyi Anahtarlık'a kaydeder; geçersizse kaydetmez ve false döner. Sonraki bağlantıda kullanılır.
    @discardableResult
    func setLoginPasscode(_ value: String) -> Bool {
        guard let pin = LoginPasscode.normalized(value) else { return false }
        store.save(pin, for: StoreKey.loginPasscode)
        hasLoginPasscode = true
        return true
    }

    func removeLoginPasscode() {
        store.remove(StoreKey.loginPasscode)
        hasLoginPasscode = false
    }

    func stop() {
        resetCorners()
        session?.stop()
        session = nil
        updateGameProbe(connected: false)
        gameChoice.stop()
        keeper?.stop()
        keeper = nil
        pipeline?.reset()
        if pipeline != nil {
            // Nino: oturumun sağlık özeti günlüğe de yazılır (kayıtları gönderen kullanıcının ekranını görmeden okunur).
            HealthRecorder.shared.sessionEnded()
            let summary = HealthReport.summary(HealthRecorder.shared.snapshot(), network: NetworkWatcher.shared.kind)
            SubtitleLog.write("sağlık: " + summary.replacingOccurrences(of: "\n", with: " · "))
            SubtitleLog.write("oturum bitti")
        }
        translationSync?.cancel()
        translationSync = nil
        pipeline = nil
        regionWatcher?.reset()
        regionWatcher = nil
        // Yeni "Başlat" eski oturumdan kalan (belki takılmış) okumayı beklemeden temiz başlar.
        frameGate.reset()
        activeLanguages = nil
        #if !APP_STORE
        // Nino: çeviri sürerken inen güncelleme şimdi kurulur (uygulama yeniden açılır).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { AppUpdater.installIfReady() }
        #endif
        screenHotkey?.enabled = false
        screenTask?.cancel()
        screenTask = nil
        if Date() < screenShownUntil { server.clearScreen() }
        screenShownUntil = .distantPast
        if let dubber {
            self.dubber = nil
            Task { await dubber.shutdown() }
        }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        if let sleepActivity { ProcessInfo.processInfo.endActivity(sleepActivity) }
        sleepActivity = nil
        isRunning = false
        onlineIssue = nil
        localNetworkBlocked = false
        sessionState = .disconnected(.stopped)
        windowStatus = .stopped
        cardStatus = .stopped
        gameArea = nil
        updateClickThroughHotkey()
        overlayHide()
    }

    private func sessionStateChanged(_ state: SessionState) {
        // Altyazı günlüğünde yalnız durumun türü (adres ve ayrıntı remoteplay.log'da).
        if state != sessionState {
            switch state {
            case .connecting:
                SubtitleLog.write("PS5: bağlanıyor")
                HealthRecorder.shared.connecting()
            case .streaming:
                SubtitleLog.write("PS5: bağlandı")
                HealthRecorder.shared.streaming()
            case .disconnected(let reason):
                SubtitleLog.write("PS5: bağlantı yok")
                // Kullanıcının durdurması kopma sayılmaz.
                // Yalnız sebebin adı (notFound("192.168…") gibi adres taşıyanların adresi özete girmez).
                let name = String(String(describing: reason).prefix { $0 != "(" })
                HealthRecorder.shared.disconnected(reason: reason == .stopped ? nil : name)
            }
        }
        sessionState = state
        // PS5 bağlandıysa yerel ağa ulaşılıyor demektir.
        if state == .streaming, localNetworkBlocked { localNetworkBlocked = false }
        updateGameProbe(connected: state == .streaming)
        // Bağlantı koptuysa TV'de eski altyazı kalmasın.
        if case .disconnected = state {
            pipeline?.reset()
            regionWatcher?.reset()
            server.clear()
            dubber?.stop()
        }
    }

    private func noteRead(_ error: Error?) {
        guard error != nil else {
            readFailures = 0
            // Her başarılı okumada yazılmasın: yayınlanan özellik her atamada bütün ekranları yeniden çizdirir.
            if readingFailedFreeGB != nil { readingFailedFreeGB = nil }
            return
        }
        readFailures += 1
        if readFailures >= 10, readingFailedFreeGB == nil { readingFailedFreeGB = Self.freeDiskGB() }
    }

    static func freeDiskGB() -> Double {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let bytes = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        return Double(bytes) / 1_000_000_000
    }

    static func translatorStatus(after error: TranslatorError?) -> TranslatorStatus {
        switch error {
        case nil: .ready
        case .needsDownload: .needsDownload
        case .unsupported: .unsupported
        }
    }

    /// Çeviri başlamamışken bağlı olmamak bir sorun değildir; nokta gri kalır.
    static func ps5Tone(_ state: SessionState, running: Bool) -> StatusTone {
        state == .streaming ? .good : running ? .warning : .idle
    }

    static func tvTone(clients: Int, running: Bool) -> StatusTone {
        clients > 0 ? .good : running ? .warning : .idle
    }

    /// Ana ekrandaki PS5 durumu (eşleşmiş PS5'in adıyla).
    var ps5StatusText: String {
        if usesGameWindow { return windowStatusText }
        if usesCaptureCard { return cardStatusText }
        return Self.statusText(sessionState, running: isRunning, pairedName: console.map { $0.name.isEmpty ? "PS5" : $0.name },
                               localNetworkBlocked: localNetworkBlocked)
    }

    /// Yerel Ağ izni uyarısı (PS5 durumu, ana ekran ve Sistem sağlığı aynı metni gösterir).
    static var localNetworkWarning: String {
        String(localized: "This Mac's local network permission may be off. Turn on Nino in System Settings › Privacy & Security › Local Network, then restart Nino.")
    }

    /// Sistem Ayarları › Gizlilik ve Güvenlik › Yerel Ağ.
    static let localNetworkSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!

    /// Oturumun bildirdiği yerel ağ izni işareti (bkz. `LocalNetworkAccess`); çeviri sürmüyorsa yok sayılır.
    func localNetworkChanged(blocked: Bool) {
        let value = blocked && isRunning
        if value != localNetworkBlocked { localNetworkBlocked = value }
        if value { SubtitleLog.write("PS5: yerel ağ izni kapalı görünüyor") }
    }

    /// Görüntü bu Mac'teki Remote Play penceresinden okunurken durumun metni.
    static func windowStatusText(_ state: SessionState, running: Bool, installed: Bool = true) -> String {
        if case .streaming = state { return String(localized: "Reading the Remote Play window") }
        if !installed { return String(localized: "The Remote Play app isn't installed on this Mac. Download it in Settings › Picture source.") }
        switch state {
        case .streaming: return String(localized: "Reading the Remote Play window")
        case .connecting: return String(localized: "Waiting for the Remote Play window. Open PS Remote Play or chiaki-ng on this Mac.")
        case .disconnected(let reason):
            guard running else { return String(localized: "Reads the Remote Play window on this Mac when you start translating.") }
            if case .other(let detail) = reason, !detail.isEmpty { return detail }
            return String(localized: "Waiting for the Remote Play window. Open PS Remote Play or chiaki-ng on this Mac.")
        }
    }

    /// PS5 durumunun kullanıcıya gösterilecek metni. `pairedName`: eşleşmiş PS5'in adı; çeviri başlamamışken eşleşmiş
    /// PS5 için "Bağlı değil" yerine "eşleşti, başlatınca bağlanır" denir (eskiden eşleştirme başarılı olsa da ana ekran
    /// "Bağlı değil" diyordu).
    /// `localNetworkBlocked`: macOS'un Yerel Ağ izni kapalı görünüyor; PS5'e ulaşılamıyorsa (bulunamadı, ağ hatası) asıl
    /// neden budur ve o söylenir. PS5'in yanıt verdiği durumlarda (kullanımda, reddetti, şifre…) işaret yok sayılır.
    static func statusText(_ state: SessionState, running: Bool, pairedName: String? = nil,
                           localNetworkBlocked: Bool = false) -> String {
        switch state {
        case .streaming: return String(localized: "Connected")
        case .connecting: return localNetworkBlocked && running ? localNetworkWarning : String(localized: "Connecting…")
        case .disconnected(let reason):
            guard running else {
                guard let pairedName else { return String(localized: "Not connected") }
                return String(format: String(localized: "Paired with %@. Connects when you start translating."), pairedName)
            }
            if localNetworkBlocked {
                switch reason {
                case .notFound, .network, .other: return localNetworkWarning
                default: break
                }
            }
            return disconnectText(reason)
        }
    }

    private static func disconnectText(_ reason: DisconnectReason) -> String {
        switch reason {
        case .consoleAsleep: return String(localized: "Turn on your PS5")
        case .inUse: return String(localized: "Remote Play is in use on another device")
        case .refused: return String(localized: "The PS5 refused the connection. Set up the PS5 again.")
        case .loginPasscode:
            return String(localized: "The PS5 asks for this account's login passcode. Enter it in Settings, or turn off this account's login passcode on the PS5.")
        // Yanlış şifre bir kez gönderilir; PS5 yeniden isterse oturum kapanır (döngü yok).
        case .loginPasscodeIncorrect:
            return String(localized: "The PS5 didn't accept the login passcode in Settings. Correct it, or turn off this account's login passcode on the PS5.")
        // Eskiden "Yeniden bağlanılıyor… (Unknown Session Request Error)" diye sonsuza kadar deneniyordu.
        case .registrationInvalid: return String(localized: "The PS5 didn't accept this pairing. Pair the PS5 again with the second account in Settings.")
        // PS5 kodu 0x80108b12: eskiden yalnız "PS5 bağlantıyı reddetti (kod …)" deniyordu.
        case .remotePlayDisabled: return String(localized: "Remote Play is turned off on the PS5. On the PS5, open Settings › System › Remote Play and turn on Enable Remote Play, then start again.")
        // Eskiden görüntü hiç gelmeyince sonsuza kadar "Yeniden bağlanılıyor… (no picture from the PS5)".
        case .noPicture: return String(localized: "No picture from the PS5. Is Remote Play turned off, or is the PS5 in rest mode? Check, then start again.")
        // Eskiden ağ hatası, bulunamayan PS5 ve diğer nedenler hep yalnız "Yeniden bağlanılıyor…" idi.
        case .notFound(let host):
            return String(format: String(localized: "PS5 not found at %@. Make sure it is on and on the same network. Reconnecting…"), host)
        case .network: return String(localized: "Can't reach the PS5. Reconnecting…")
        // Eskiden "Yeniden bağlanılıyor… (Unknown Session Request Error)" görünüyordu (GitHub #33, #202).
        case .rejected(let code?):
            return String(format: String(localized: "The PS5 rejected the connection (code %@). Another Remote Play app (PS Remote Play) may be open, or the PS5 may be in another session. Close PS Remote Play, restart the PS5, then try again."), String(format: "0x%08x", code))
        case .rejected(nil): return String(localized: "The PS5 didn't start the session. Another Remote Play app (PS Remote Play) may be open, or the PS5 may be in another session. Close PS Remote Play, restart the PS5, then try again.")
        case .other(let detail) where !detail.isEmpty: return String(format: String(localized: "Reconnecting… (%@)"), detail)
        case .other, .stopped: return String(localized: "Reconnecting…")
        }
    }

    /// PS5'in adresi değişti: sonraki açılışlar yeni adresle başlasın.
    private func consoleMoved(_ moved: RegisteredConsole) {
        guard console != nil else { return }
        // Geçersiz adres (0.0.0.0, boş) kaydedilmez: kaydedilirse PS5 bir daha bulunamıyordu.
        guard ConsoleAddress.isUsable(moved.host) else {
            RemotePlayLog.write("PS5'in yeni adresi geçersiz (\"\(moved.host)\"); kaydedilmedi")
            return
        }
        console = moved
        store.save(moved, for: StoreKey.console)
    }

    private func handle(_ frame: CGImage, capturedAt: Int) async {
        lastFrame = frame
        #if DEBUG
        NinoDebugFrames.capture(frame, region: readRegion, box: lastSubtitleBox, source: lastSource, translation: lastTranslation)
        #endif
        if isRunning { watchCorners(frame); identifyGameIfNeeded(frame); clearStaleMessage(); watchPhone(frame) }
        // Köşe okuması Vision'ın takıldığını 4-5 sn'de fark eder (kapı açılmaz); 15 sn beklemeden yeniden açılır.
        if isRunning, VisionReader.isStuck {
            SubtitleLog.write("Vision okuması takıldı (köşe okuması fark etti; takılan okuma: \(VisionReader.stuckInfo))")
            relaunchAfterStuckReading()
            return
        }
        guard pipeline != nil else { return }
        // Ek alanlar ayrı ve seyrek okunur (saniyede bir); altyazı okumasını beklemez, onu bekletmez.
        let areas = settings.activeExtraAreas
        if regionWatcher == nil, !areas.isEmpty, let pipeline { regionWatcher = makeRegionWatcher(packLookup: regionPackLookup) }
        regionWatcher?.offer(frame, areas: areas)
        // Önceki kare hâlâ işleniyorsa bu kare atlanır; okuma kareleri biriktirmez.
        var entry = frameGate.enter(now: SubtitleStabilizer.uptimeMs())
        if case .stuck(let ms) = entry {
            // Okuma bitmedi: önizleme canlıyken altyazı hiç gelmiyordu ve ancak uygulamayı kapatıp açmak düzeltiyordu.
            SubtitleLog.write("okuma \(ms) ms'dir bitmedi; okuma hattı yeniden kuruldu")
            // Apple'ın yazı tanıması takılınca (Neural Engine) aynı süreçte bir daha düzelmiyor; Nino'yu kapatıp açmak
            // düzeltiyordu. 90 sn içinde iki kez takılırsa Nino kendini yeniden açar ve çeviriye kendiliğinden döner. (Arada
            // hata verip biten kısa okumalar sayacı sıfırlamaz: takılı motor her okumayı birkaç saniyede reddediyordu.)
            // Kullanıcı: takılınca 40 sn altyazı kaçıyordu. Artık ilk takılmada yeniden açılır.
            relaunchAfterStuckReading()
            return
            entry = frameGate.enter(now: SubtitleStabilizer.uptimeMs())
        }
        guard case .enter(let token) = entry, let pipeline else { return }
        await pipeline.process(frame, region: readRegion, capturedAt: capturedAt)
        frameGate.leave(token)
    }

    // MARK: - Geçmiş

    private func addToHistory(source: String, translation: String, origin: LineMetrics.Origin) {
        history.add(source: source, translation: translation, origin: origin)
        saveHistory()
    }

    /// "Geçmiş"teki "Temizle": listeyi ve dosyayı boşaltır.
    func clearHistory() {
        history.clear()
        saveHistory()
    }

    /// Geçmiş arka planda dosyaya yazılır (küçük dosya; sırayla, en son hâli kalır).
    private func saveHistory() {
        guard let historyFile else { return }
        let history = self.history
        historyQueue.async { try? history.save(to: historyFile) }
    }

    /// Canlı altyazı alanındaki liste: bu oturumun satırları (oturum başlamadıysa hepsi).
    var sessionHistory: [SubtitleHistory.Entry] {
        sessionStartedAt.map { history.entries(since: $0) } ?? history.entries
    }

    private func startServer() async throws {
        guard !serverStarted else { return }
        do {
            serverPort = try await server.start()
        } catch {
            // 8787 başka bir uygulamada; TV'ye zaten adres bildirildiği için herhangi bir boş port olur.
            server = SubtitleServer(port: 0)
            attachServer()
            serverPort = try await server.start()
        }
        serverStarted = true
    }

    /// TV ile aynı ağdaki Mac adresi.
    private func serverAddress(for tv: LGTV) -> String {
        "http://\(Self.localAddress(near: tv.host) ?? "127.0.0.1"):\(serverPort)"
    }

    static func localAddress(near host: String?) -> String? { NetworkAddress.near(host) }
}

// MARK: - Dublaj

extension AppModel {
    @discardableResult
    private func makeDubber() -> Dubber {
        if let dubber {
            dubber.update(serverPort: serverPort)
            return dubber
        }
        let dubber = Dubber(server: server, serverPort: serverPort, settings: settings.dubbing)
        dubber.tracker = voiceTracker
        dubber.onLog = { SubtitleLog.write($0) }
        dubber.onCastChanged = { [weak self] cast in self?.settings.dubbing.cast = cast }
        dubber.onError = { [weak self] message in self?.dubbingError = message }
        self.dubber = dubber
        return dubber
    }

    private func speak(_ lines: [SpokenLine]) {
        guard dubbingActive, dubbingModelReady else { return }
        makeDubber().speak(lines)
    }

    private func dubbingSettingsChanged(from old: DubbingSettings) {
        guard let dubber else {
            if settings.dubbing.enabled, !old.enabled, isRunning, dubbingModelReady { makeDubber().prepare() }
            return
        }
        dubber.cast = settings.dubbing.cast
        if dubber.output != settings.dubbing.output {
            dubber.stop()
            dubber.output = settings.dubbing.output
        }
        if !settings.dubbing.enabled {
            self.dubber = nil
            Task { await dubber.shutdown() }
        }
    }

    /// Nino: dublaj yalnız Türkçe çeviride çalışır (sesler ve metin hazırlığı Türkçe için); Arapçada kapalıdır.
    /// Alt şerit ve Ayarlar › Çeviri: GTA 6 (havuz öncelikli oyun) için Nino'nun kendi çevirisi geçerli mi? Hedef dil
    /// havuzun çevirdiği dillerdense (şimdilik Türkçe) ve tanınan oyun havuz öncelikliyse ya da henüz oyun tanınmadıysa
    /// evet: kullanıcı varsayılanın açık olduğunu görür. Başka bir oyun tanınınca seçili motor gösterilir.
    var ninoPoolActive: Bool {
        guard translations.poolFirst.allows(language: settings.targetLanguage) else { return false }
        guard let name = gameChoice.sense.current?.name else { return true }
        return translations.isPoolFirst(translations.poolGame(name, packs.searchScope))
    }

    /// Tanınan oyunun kimliği (ör. "grand-theft-auto-vi"); tanınmadıysa nil. Salon sahnesindeki fon buna göre seçilir.
    var liveGameID: String? { NinoPool.gameID(gameChoice.sense.current?.name) }
    /// Tanınan oyun havuz öncelikli mi (şimdilik GTA 6). Yalnız görünüm içindir: sunucuya o an ulaşılamasa da
    /// (`isPoolFirst` o zaman false döner) oyun aynı oyundur, fon kalır.
    var liveGamePoolFirst: Bool {
        // Nino: oyun bu açılışta henüz tanınmadıysa (ekrandan tanıma birkaç deneme sürebiliyor) son oynanan oyunun teması
        // kalır; Nino her yeniden açıldığında GTA renkleri ve "GTA 6 açık" yazısı kayboluyordu (kullanıcı, 21 Kasım 2026).
        guard let name = gameChoice.sense.current?.name else {
            return session != nil && UserDefaults.standard.bool(forKey: Self.lastGamePoolFirstKey)
        }
        return translations.poolFirst.contains(translations.poolGame(name, packs.searchScope))
    }

    /// Nino: Türkçe dublaj şimdilik kapalı (19 Kasım 2026, kullanıcı isteği): Ayarlar'da görünmez ve açık kalmış olsa
    /// da çalışmaz. Geri açmak için bunu true yapmak yeter; kod ve ayarlar yerinde durur.
    static let dubbingAvailable = false
    var dubbingActive: Bool { Self.dubbingAvailable && settings.dubbing.enabled && TargetLanguage.isTurkish(settings.targetLanguage) }

    /// Nino: çeviri dili değişti. Eski dildeki köşe çevirileri ve ekrandaki satırlar kalkar; dublaj Türkçe dışında durur.
    private func targetLanguageChanged() {
        resetCorners()
        if isRunning { server.clearScreen() }
        overlayHide()
        lastTranslation = ""
        lastSource = ""
        if !dubbingActive, let dubber {
            self.dubber = nil
            Task { await dubber.shutdown() }
        }
    }

    /// Ses modelini indirir (ilk kullanımda bir kez, ~440 MB).
    func downloadDubbingModel() async {
        guard dubbingDownload == nil else { return }
        dubbingDownload = 0
        dubbingError = nil
        do {
            try await DubbingModelStore.download { [weak self] progress in self?.dubbingDownload = progress }
            dubbingModelReady = true
            if dubbingActive, isRunning { makeDubber().prepare() }
        } catch {
            dubbingError = error.localizedDescription
        }
        dubbingDownload = nil
    }

    /// Ayarlardaki "Dinle": sesi seçilen çıkıştan çalar.
    func previewVoice(_ voice: DubbingVoice) async {
        guard dubbingModelReady else { return }
        dubbingError = nil
        try? await startServer()
        makeDubber().preview(voice)
    }

    func assignVoice(_ voice: DubbingVoice, to name: String) {
        settings.dubbing.cast.assign(voice, to: name)
    }

    func removeDubbingModel() {
        if let dubber {
            self.dubber = nil
            Task { await dubber.shutdown() }
        }
        DubbingModelStore.remove()
        dubbingModelReady = false
    }
}

/// Son PS5 karesi; yalnız bölge önizlemesi izler.
@MainActor
final class FramePreview: ObservableObject {
    @Published var image: CGImage?
}



/// Bir zamana kadar açık kalan bayrak (iş parçacıkları arasında güvenli).
final class UntilFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var until = Date.distantPast
    func set(until date: Date) { lock.withLock { until = date } }
    var active: Bool { lock.withLock { Date() < until } }
}
