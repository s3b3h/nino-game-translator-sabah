// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import ImageIO
import CouchSubsCore
import Foundation
import Combine
import RemotePlay

/// Telefon uygulamasının bütün durumu: kurulum (PSN girişi, PS5 eşleştirme, altyazının yeri), çeviri (PS5 görüntüsü →
/// yazı tanıma → çeviri → TV ya da telefon ekranı) ve ayarlar. Okuma hattı, çevirmenler, ayarlar ve TV denetimi Mac
/// uygulamasıyla ortak (CouchSubsCore, RemotePlay); burada yalnız telefona özgü akış var.
@MainActor
final class PhoneModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, psnLogin, console, output, done
    }

    @Published var step: Step {
        didSet { if step == .done, oldValue != .done { store.save(true, for: StoreKey.setupComplete) } }
    }
    @Published var accountId: Data?
    /// Okunan konsol: PlayStation (varsayılan) ya da Xbox (Beta). `platformChosen` false ise kurulumda sorulur.
    @Published private(set) var platform: ConsolePlatform
    @Published var platformChosen: Bool
    /// Seçilen Xbox ve Microsoft girişi (jeton Anahtar Zinciri'nde).
    @Published private(set) var xboxConsole: XboxConsole?
    @Published private(set) var xboxSignedIn: Bool
    let xboxAuth: XboxAuth
    private let tokenSink: XboxTokenSink
    @Published var console: RegisteredConsole?
    @Published var tv: LGTV?
    @Published private(set) var tvKeySaved: Bool
    /// İkinci hesabın PS5 giriş şifresi Anahtarlık'ta kayıtlı.
    @Published private(set) var hasLoginPasscode: Bool
    /// Son eşleşmede TV uygulaması açılamadı: büyük olasılıkla TV'de kurulu değil; telefon kurabilir (TV uygulamasını kur).
    @Published var tvAppMissing = false
    /// TV'deki uygulama telefondaki paketten eski: ana ekranda "TV uygulamasını güncelle".
    @Published private(set) var tvAppUpdate: TVAppUpdate?
    /// Bu telefonun TV uygulamasını kurduğu ya da sürümünü okuduğu son TV.
    @Published private(set) var installedTVApp: InstalledTVApp?
    private var tvAppCheckedAt: Date?
    private var checkingTVApp = false

    @Published var settings: UserSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: StoreKey.settings) }
            server.sendStyle(settings.style)
            if settings.output != oldValue.output { outputChanged() }
            if settings.gamePacks != oldValue.gamePacks, let pipeline { connectPacks(to: pipeline) }
            if settings.targetLanguage != oldValue.targetLanguage {
                let (translations, target) = (translations, settings.targetLanguage)
                Task { await translations.setLanguage(target) }
                targetLanguageChanged()
            }
            pipeline?.showSpeakerNames = settings.showSpeakerNames
            if settings.sharePool != oldValue.sharePool {
                let (pool, enabled, translations) = (pool, settings.sharePool, translations)
                Task { await pool.setEnabled(enabled); await translations.setEnabled(enabled) }
                if let pipeline { connectPacks(to: pipeline) }
            }
            let translationChanged = settings.onlineTranslation != oldValue.onlineTranslation
                || settings.targetLanguage != oldValue.targetLanguage
                || settings.onlineEngine != oldValue.onlineEngine || settings.geminiModel != oldValue.geminiModel
                || settings.openAIModel != oldValue.openAIModel || settings.claudeModel != oldValue.claudeModel
            if translationChanged { Task { await refreshTranslatorStatus() } }
            if isRunning, translationChanged || settings.fastSubtitleDetection != oldValue.fastSubtitleDetection {
                makePipeline()
            }
        }
    }

    // Çalışma durumu
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    /// Nino: PS5'siz önizleme ("PS5'siz Deneyin"): örnek altyazılar akar; ağa ve PS5'e dokunmaz (App İnceleme ve meraklılar için).
    @Published private(set) var isDemo = false
    /// Demo oturumunda şu an gösterilen örnek satır (İngilizcesi ve çevirisi).
    @Published private(set) var demoLine: DemoSamples.Line?
    private var demoTask: Task<Void, Never>?
    @Published private(set) var sessionState: SessionState = .disconnected(.stopped)
    @Published private(set) var tvClients = 0
    @Published private(set) var lastSource = ""
    @Published private(set) var lastTranslation = ""
    /// Bu ve önceki oturumlarda çevrilen son 200 altyazı (history.json; "Geçmiş" ekranı).
    @Published private(set) var history = SubtitleHistory()
    /// Son satırın ölçümleri (yazı tanıma, çeviri, gecikme, güven).
    @Published private(set) var lastMetrics: LineMetrics?
    /// Son PS5 karesi (Ayarlar'daki bölge önizlemesi); yalnız önizleme izler.
    let framePreview = PhoneFramePreview()
    /// Geçmişin yazıldığı dosya (testlerde nil: hiçbir şey yazılmaz).
    private var historyFile: URL?
    private let historyQueue = DispatchQueue(label: "history.json", qos: .utility)
    @Published private(set) var translatorStatus: TranslatorStatus = .ready
    @Published private(set) var onlineIssue: OnlineKeyState?
    /// Son altyazı oyun paketinden mi geldi (ana ekrandaki "paket kullanılıyor" göstergesi).
    @Published private(set) var lastFromPack = false
    /// Bu oturumda çevrilen satırlar (en yenisi başta), nereden geldikleriyle.
    @Published private(set) var recentLines: [RecentLine] = []
    /// Bu oturumdaki satır sayısı ve paketten gelenler ("Hazır çeviriden 47 / 50").
    @Published private(set) var sessionLines = 0
    @Published private(set) var sessionPackLines = 0
    /// Çevirinin başladığı an (çalışma ekranındaki süre).
    @Published private(set) var runningSince: Date?

    struct RecentLine: Identifiable, Equatable {
        let id: Int
        let source: String
        let translation: String
        let fromPack: Bool
    }

    /// Son oturumun süresi (saniye; ana ekrandaki "Son oturum").
    var lastSessionSeconds: Int? {
        let value = defaults.integer(forKey: "lastSessionSeconds")
        return value > 0 ? value : nil
    }
    /// Telefon ekranında şu an görünen satırlar (TV uygulamasıyla aynı yığın kuralları).
    @Published private(set) var phoneLines: [SubtitleStack.Line] = []
    /// Telefon ekranındaki ek alan çevirileri (görev, telefon, bildirim); TV'deki gibi kendi yerlerinde küçük kutular.
    @Published private(set) var phoneRegions: [PhoneRegion] = []

    /// "Ekranı çevir" sonuçları (telefon ekranında yazının kendi yerinde); boşken görünür bir şey yok.
    @Published private(set) var screenItems: [ScreenTranslation.Item] = []
    /// "Ekranı çevir" düğmesinin durumu: çeviri sürüyor ya da sonuçlar ekranda.
    @Published private(set) var screenState: ScreenState = .idle

    enum ScreenState: Equatable { case idle, working, shown }

    struct PhoneRegion: Identifiable, Equatable {
        let id: String
        let text: String
        let box: TextBox?
    }
    @Published private(set) var installedPacks: [GamePackLibrary.Info] = []
    /// Paketler ekranında kapatılan paketlerin kimlikleri (Android'deki gibi karoya dokunarak; UserDefaults'ta).
    @Published private(set) var disabledPacks: Set<String> = []
    /// Son satırı veren paketin başlığı (Paketler ekranındaki "Oynanıyor"); çeviri durunca silinir.
    @Published private(set) var packInUse: String?

    /// Kurulumda "Şimdilik geç" (PSN girişi ve PS5 eşleme atlandı; eşleme sonra Profil ya da Ayarlar'dan).
    static let setupSkippedKey = "setupSkipped"
    static let disabledPacksKey = "disabledPacks"
    /// Profil'deki "PS5 bağlantısı koptuğunda bildir" tercihi (varsayılan açık, Android ile aynı).
    static let notifyDisconnectKey = "notifyDisconnect"

    /// Çeviri sürerken ekran kararmasın (iOS uygulamayı askıya alınca bağlantı da durur). Uygulama UIKit'e bağlar.
    var keepScreenAwake: (Bool) -> Void = { _ in }
    /// Ölçüm olayları (Firebase Analytics, Meta); uygulama `AppModel.analytics`'e bağlar.
    var onAnalytics: (AnalyticsEvent) -> Void = { _ in }
    /// PS5 bağlantısı kendiliğinden koptu (kullanıcı durdurmadı). Uygulama, etkin değilken yerel bildirim gösterir;
    /// testlerde boş.
    var onConnectionLost: () -> Void = {}
    /// PS5'te yeni bir oyun tanındı (paket sunucusuna o oyun için bakılır).
    var onGameStarted: () -> Void = {}
    /// Çeviri başlarken bildirim izni istenir (tercih açıksa; iOS yalnız ilk seferde sorar). Testlerde boş.
    var requestNotificationPermission: () -> Void = {}
    private var startedAt: Date?

    private let services: PhoneServices
    private let store: AppStore
    private let defaults: UserDefaults
    private var server = SubtitleServer(port: AppIdentity.serverPort)
    private var serverStarted = false
    @Published private(set) var serverPort: UInt16 = AppIdentity.serverPort
    private var session: StreamControlling?
    private var keeper: KeeperControlling?
    private var pipeline: SubtitlePipeline?
    /// Ek alanları (görev, telefon, bildirim) okuyup çeviren; çeviri sürerken ve ek alan varken var (Mac ile aynı).
    private var regionWatcher: RegionWatcher?
    /// Hatta aynı anda tek kare girer. Durdurma ve yeni hat kapıyı sıfırlar; takılan okuma hattı yeniden kurdurur (Mac ile aynı).
    private var frameGate = FrameGate()
    private var savedKeys: Set<TranslationEngine> = []
    private var stack = SubtitleStack()
    private var stackTimer: Task<Void, Never>?
    /// Süren "ekranı çevir" işi ve sonuçların kalkma zamanlayıcısı.
    private var screenTask: Task<Void, Never>?
    private var screenExpiry: Task<Void, Never>?
    /// Yığının saati (saniye); testlerde ileri sarılır.
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    /// Oyun paketleri: uygulamayla gelenler ve sunucudan indirilen güncel sürümleri (ücretsiz, herkese).
    let packs: GamePackLibrary
    private let pool: NinoPool
    /// Nino: sunucunun çeviri havuzu (Claude çevirileri; paketten sonra, cihazın çevirisinden önce).
    private let translations: TranslationPool
    private var translationSync: Task<Void, Never>?
    private let poolContext = PoolContext()
    /// Ek alanların (görev, bildirim) paket araması: yalnız oyun paketi, havuz yok.
    private var regionPackLookup: ((String) -> PackMatch?)?
    /// Sorun Bildir: havuzla aynı rastgele kuruluş kimliği (sunucu tuzlayıp özetler).
    func reportInstallID() async -> String { await pool.installID }
    /// Oynanan oyun: PS5'in bildirdiği, kullanıcının seçtiği ya da paketten tanınan (havuza giden satırlar bu oyunla gider).
    let gameChoice: GameChoice
    /// Nino: tanınan oyun havuz öncelikli mi (şimdilik GTA 6). Ana ekrandaki sahnenin fonu buna göre seçilir (Mac'teki
    /// `liveGamePoolFirst` ile aynı).
    var liveGamePoolFirst: Bool {
        guard let name = gameChoice.sense.current?.name else { return false }
        return translations.isPoolFirst(translations.poolGame(name, packs.searchScope))
    }
    /// Nino: Ayarlar'daki "GTA 6" kartı (Mac'teki `ninoPoolActive` ile aynı). Hedef dil havuzun çevirdiği dillerdense
    /// (şimdilik Türkçe) ve tanınan oyun havuz öncelikliyse ya da henüz oyun tanınmadıysa evet; başka bir oyun tanınınca
    /// kart kalkar ve seçili motor geçerlidir.
    var ninoPoolActive: Bool {
        guard translations.poolFirst.allows(language: settings.targetLanguage) else { return false }
        guard let name = gameChoice.sense.current?.name else { return true }
        return translations.isPoolFirst(translations.poolGame(name, packs.searchScope))
    }

    // MARK: - Cihaz bilgileri

    /// Nino: "Cihaz bilgileri" (Ayarlar'ın altındaki kart; Sorun Bildir ve Nino'ya Sor bildirimlerine eklenir). Yalnız
    /// sürüm, model, marka ve durum: cihazın, TV'nin ya da konsolun adı, hesap adı ve IP adresi hiçbir satıra girmez.
    var deviceInfoRows: [DeviceInfo.Row] {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return DeviceInfo.rows(app: build.isEmpty ? AppIdentity.version : "\(AppIdentity.version) (\(build))",
                               tv: deviceInfoTV, console: deviceInfoConsole, status: deviceInfoStatus)
    }

    var deviceInfoSummary: String { DeviceInfo.summary(deviceInfoRows) }

    /// TV'nin markası ve (biliniyorsa) TV uygulamasının sürümü. Telefon TV'nin modelini saklamaz; adı (`tv.name`) bilerek
    /// kullanılmaz, kullanıcının verdiği ad olabilir.
    private var deviceInfoTV: String? {
        guard let brand = installedTVApp?.brand ?? (hasTV ? tv?.brand : nil) else { return nil }
        let name = switch brand {
        case .lg: "LG"
        case .samsung: "Samsung"
        case .androidTV: "Android TV"
        }
        guard let version = installedTVApp?.version, !version.isEmpty else { return name }
        return "\(name) · TV uygulaması \(version)"
    }

    /// Konsol ve bağlantı yolu; eşlenmemişse nil. Konsolun adı kullanılmaz (Xbox'ta yalnız türü, ör. "XboxSeriesX").
    private var deviceInfoConsole: String? {
        if isXbox {
            guard let xboxConsole else { return nil }
            return xboxConsole.model.isEmpty ? "Xbox" : "Xbox · \(xboxConsole.model)"
        }
        return console == nil ? nil : "PS5 · Remote Play"
    }

    /// Çeviri sürerken bağlantının durumu; sürmüyorsa nil. Adres ya da serbest metin taşıyan nedenler (`notFound` adresi,
    /// Xbox'ın hata metni) burada sabit metne çevrilir; `ps5StatusText` yalnız içine değer girmeyen nedenlerde kullanılır.
    private var deviceInfoStatus: String? {
        guard isRunning else { return nil }
        switch sessionState {
        case .streaming: return String(localized: "Connected")
        case .connecting: return String(localized: "Connecting…")
        case .disconnected(let reason):
            switch reason {
            case .rejected(let code?): return String(format: "0x%08x", code)
            case .notFound, .network: return String(localized: "Can't reach the PS5. Reconnecting…")
            case .other, .stopped: return String(localized: "Reconnecting…")
            case .consoleAsleep, .inUse, .refused, .loginPasscode, .loginPasscodeIncorrect, .registrationInvalid,
                 .remotePlayDisabled, .noPicture, .rejected(nil):
                return ps5StatusText
            }
        }
    }

    /// Bağlıyken birkaç dakikada bir PS5'e çalışan oyunu sorar (havuza giden satırlar oyunla gider). Testlerde kapalı.
    private var gameProbe: Task<Void, Never>?
    private let probesGame: Bool
    static let gameProbeInterval: Duration = .seconds(120)

    init(services: PhoneServices = LivePhoneServices(), store: AppStore = KeychainStore(), defaults: UserDefaults = .standard,
         packs: GamePackLibrary = GamePackLibrary(bundled: nil, user: nil)) {
        self.services = services
        self.store = store
        self.defaults = defaults
        self.packs = packs
        let accountId = store.load(Data.self, for: StoreKey.accountId)
        let console = store.load(RegisteredConsole.self, for: StoreKey.console)
        let tv = store.load(LGTV.self, for: StoreKey.tv)
        let tvKeySaved = store.load(String.self, for: StoreKey.tvKey) != nil
        self.accountId = accountId
        self.console = console
        self.tv = tv
        self.tvKeySaved = tvKeySaved
        hasLoginPasscode = LoginPasscode.normalized(store.load(String.self, for: StoreKey.loginPasscode)) != nil
        let savedPlatform = defaults.string(forKey: XboxStoreKey.platform).flatMap(ConsolePlatform.init(rawValue:))
        platform = savedPlatform ?? .playstation
        // PS5'i önceden eşlenmiş kurulumlar PlayStation sayılır, yeniden sorulmaz.
        platformChosen = savedPlatform != nil || accountId != nil || console != nil
        xboxConsole = store.load(XboxConsole.self, for: XboxStoreKey.console)
        let xboxToken = XboxUserToken.parse(store.load(String.self, for: XboxStoreKey.userToken))
        xboxSignedIn = xboxToken != nil
        let tokenSink = XboxTokenSink()
        self.tokenSink = tokenSink
        xboxAuth = XboxAuth(userToken: xboxToken, onUserToken: { token in tokenSink.handler?(token) })
        let loaded = defaults.data(forKey: StoreKey.settings).flatMap { try? JSONDecoder().decode(UserSettings.self, from: $0) }
        // Nino: ilk açılışta (kayıtlı ayar yok) telefonun dili Arapçaysa çeviri dili Arapça seçilir; değilse Türkçe.
        let curated = (loaded ?? { var first = UserSettings(); first.targetLanguage = TargetLanguage.preferred(); return first }())
            .withCuratedModels()
        settings = curated
        // "Şimdilik geç" ile PSN ve PS5 atlandıysa PS5'siz ana ekrana gidilir; altyazı hedefi seçilmediyse oradan sürer.
        let skipped = defaults.bool(forKey: Self.setupSkippedKey)
        let done = (skipped || accountId != nil && console != nil) && store.load(Bool.self, for: StoreKey.setupComplete) == true
        let xboxReady = savedPlatform == .xbox && xboxToken != nil && store.load(XboxConsole.self, for: XboxStoreKey.console) != nil
        let doneAny = (done || xboxReady && store.load(Bool.self, for: StoreKey.setupComplete) == true)
        step = doneAny ? .done : skipped ? .output : .welcome
        disabledPacks = Set(defaults.stringArray(forKey: Self.disabledPacksKey) ?? [])
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !testing {
            RemotePlayLog.enable()
            RemotePlayLog.write("Nino iOS \(AppIdentity.version)")
        }
        let poolFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppIdentity.name, isDirectory: true).appendingPathComponent("pool.json")
        // Nino'nun kendi havuzu; CouchSubs'tan kalan pool.json kuyruğu bir kez ona aktarılır.
        pool = NinoPool(directory: poolFile.deletingLastPathComponent().appendingPathComponent("pool", isDirectory: true),
                        app: AppIdentity.version, platform: "ios", enabled: curated.sharePool && !testing, legacyFile: poolFile)
        translations = TranslationPool(directory: poolFile.deletingLastPathComponent().appendingPathComponent("translations", isDirectory: true),
                                       app: AppIdentity.version, platform: "ios", language: curated.targetLanguage,
                                       enabled: curated.sharePool && !testing)
        probesGame = !testing
        gameChoice = GameChoice(defaults: defaults)
        savedKeys = Set(TranslationEngine.allCases.filter { engine in
            engine.storeKey.flatMap { store.load(String.self, for: $0) }?.isEmpty == false
        })
        installedTVApp = defaults.data(forKey: StoreKey.tvAppInstalled).flatMap { try? JSONDecoder().decode(InstalledTVApp.self, from: $0) }
        attachServer()
        reloadPackList()
        // Nino: NinoPool oyunu her satırla birlikte alır (paket kimliği, `offer(_:game:)`); ayrıca ayarlanmaz.
        gameChoice.onChange = { [weak self] game in
            // Nino: ana ekrandaki sahnenin fonu oyuna göre değişir (`liveGamePoolFirst`); ekran hemen yenilensin.
            self?.objectWillChange.send()
            // Bu oyunun (havuzdan otomatik) paketi sunucuda yeni çıkmış olabilir.
            if game != nil { self?.onGameStarted() }
            // Nino: yeni oyunun havuzdaki çevirileri hemen iner.
            if let self, self.pipeline != nil { self.startTranslationSync() }
        }
        gameChoice.packTitles = { [weak self] in GameCatalog.packGames(self?.installedPacks ?? []) }
        // Elle seçilen oyunda satırlar yalnız o oyunun paketinde aranır, paketi yoksa hiç aranmaz (#218).
        gameChoice.packs = packs
        // Kullanıcı jetonu her yenilendiğinde Anahtar Zinciri'ne yazılır (Windows'taki DPAPI, Android'deki Keystore).
        tokenSink.handler = { [weak self, store] token in
            if let token { store.save(token.serialize(), for: XboxStoreKey.userToken) } else { store.remove(XboxStoreKey.userToken) }
            Task { @MainActor in self?.xboxSignedIn = token != nil }
        }
    }

    // MARK: - Xbox (Beta)

    func choosePlatform(_ value: ConsolePlatform) {
        platform = value
        platformChosen = true
        defaults.set(value.rawValue, forKey: XboxStoreKey.platform)
    }

    func chooseXbox(_ console: XboxConsole) {
        xboxConsole = console
        store.save(console, for: XboxStoreKey.console)
    }

    func signOutXbox() {
        Task { await xboxAuth.signOut() }
        xboxSignedIn = false
    }

    var isXbox: Bool { platform == .xbox }

    /// Ayarlardaki paket listesi; paketler güncellenince yeniden okunur.
    func reloadPackList() {
        let packs = self.packs
        Task { [weak self] in
            let list = await Task.detached(priority: .utility) { packs.packs }.value
            self?.installedPacks = list
        }
    }

    private func attachServer() {
        server.onClientsChanged = { [weak self] count in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let connected = self.tvClients == 0 && count > 0
                    self.tvClients = count
                    // TV uygulaması her bağlandığında sürümüne bakılır (eskiyse ana ekranda güncelleme önerilir).
                    if connected { Task { await self.checkTVApp() } }
                }
            }
        }
        server.sendsToTV = settings.output.showsOnTV
        server.onEvent = { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.phoneReceive(event) } }
        }
    }

    // MARK: - Kurulum

    var canAdvance: Bool {
        switch step {
        case .welcome: true
        case .psnLogin: isXbox ? xboxSignedIn : accountId != nil
        case .console: isXbox ? xboxConsole != nil : console != nil
        case .output: hasTV || settings.output == .computer
        case .done: false
        }
    }

    func advance() {
        guard canAdvance, let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    /// Kurulumda "Şimdilik geç": PSN girişi ve PS5 eşleme atlanır, altyazı hedefinden sonra PS5'siz ana ekrana geçilir.
    func skipSetup() {
        defaults.set(true, forKey: Self.setupSkippedKey)
        step = .output
    }

    var notifiesDisconnect: Bool { defaults.object(forKey: Self.notifyDisconnectKey) as? Bool ?? true }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    var hasTV: Bool { tv != nil && tvKeySaved }

    func completePSNLogin(redirect: URL) async throws {
        do {
            let id = try await services.accountId(fromRedirect: redirect)
            accountId = id
            store.save(id, for: StoreKey.accountId)
            RemotePlayLog.write("PSN girişi tamam")
        } catch let error as PSNAccount.PSNError {
            RemotePlayLog.write("PSN girişi başarısız: \(error)")
            throw PhoneFailure(error: PhoneError(error), detail: nil)
        } catch {
            throw PhoneFailure(error: .invalidLogin, detail: error.localizedDescription)
        }
    }

    func discoverConsoles() async -> [ConsoleInfo] { await services.discoverConsoles() }

    /// PS5'e ikinci hesapla kayıt olur (PS5'teki 8 haneli kodla).
    func register(host: String, pin: String) async throws {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw PhoneError.missingConsole }
        guard let value = Registration.pin(from: pin) else { throw PhoneError.invalidPin }
        guard let accountId else { throw PhoneError.missingAccount }
        do {
            let registered = try await services.register(host: host, accountId: accountId, pin: value)
            console = registered
            store.save(registered, for: StoreKey.console)
        } catch let error as Registration.RegistrationError {
            throw PhoneFailure(error: PhoneError(error.kind), detail: error.detail)
        } catch {
            throw PhoneFailure(error: .registrationFailed, detail: error.localizedDescription)
        }
    }

    func discoverTVs() async -> [LGTV] { await services.discoverTVs() }

    /// TV ile eşleşir ve TV uygulamasını telefonun adresiyle açmayı dener.
    func pair(_ tv: LGTV) async throws {
        try await startServer()
        let savedKey = store.load(String.self, for: StoreKey.tvKey)
        let pairing = try await services.pairTV(tv, key: savedKey, server: serverAddress(for: tv))
        self.tv = tv
        store.save(tv, for: StoreKey.tv)
        // Samsung jetonla gelen bağlantıda jetonu yeniden göndermeyebilir; boş jeton saklı olanı silmez (#40).
        store.save(SamsungTokenHolder.keptToken(stored: savedKey, received: pairing.key), for: StoreKey.tvKey)
        tvKeySaved = true
        tvAppMissing = !pairing.launched
        if settings.output == .computer { settings.output = .tv }
        onAnalytics(.tvConnected(brand: tv.brand.rawValue))
    }

    /// "TV'm yok": altyazı bu telefonun ekranında gösterilir.
    func usePhoneScreen() {
        settings.output = .computer
        advance()
    }

    /// Kurulumu baştan başlatır (kayıtlı her şeyi siler).
    func resetSetup() {
        stop()
        [StoreKey.accountId, StoreKey.console, StoreKey.tv, StoreKey.tvKey, StoreKey.setupComplete, StoreKey.loginPasscode]
            .forEach(store.remove)
        hasLoginPasscode = false
        accountId = nil
        console = nil
        store.remove(XboxStoreKey.console)
        xboxConsole = nil
        signOutXbox()
        defaults.removeObject(forKey: XboxStoreKey.platform)
        platform = .playstation
        platformChosen = false
        tv = nil
        tvKeySaved = false
        tvAppMissing = false
        defaults.removeObject(forKey: Self.setupSkippedKey)
        step = .welcome
    }

    // MARK: - Çeviri

    var canStart: Bool {
        let paired = isXbox ? xboxConsole != nil && xboxSignedIn : console != nil && accountId != nil
        return paired && (settings.output.showsOnComputer || hasTV)
    }

    func start() async {
        stopDemo()
        guard !isRunning, !isStarting, canStart else { return }
        let xbox = isXbox ? xboxConsole : nil
        guard xbox != nil || console != nil && accountId != nil else { return }
        isStarting = true
        defer { isStarting = false }
        await refreshTranslatorStatus()
        try? await startServer()
        server.sendStyle(settings.style)
        makePipeline()
        let session: StreamControlling
        let consoleName: String
        if let xbox {
            RemotePlayLog.write("Çeviri başladı; Xbox'a bağlanılıyor (Beta): \(xbox.name)")
            session = XboxStreamSession(auth: xboxAuth, console: xbox, playAudio: settings.xboxAudioOnDevice,
                                        describe: XboxText.session)
            consoleName = xbox.name.isEmpty ? "Xbox" : xbox.name
        } else if let console, let accountId {
            RemotePlayLog.write("Çeviri başladı; PS5'e bağlanılıyor: \(console.name) \(console.host)")
            session = services.makeStream(console: console, accountId: accountId,
                                          loginPasscode: store.load(String.self, for: StoreKey.loginPasscode))
            consoleName = console.name.isEmpty ? console.host : console.name
        } else { return }
        session.onState = { [weak self] state in Task { @MainActor in self?.sessionStateChanged(state) } }
        session.onConsoleMoved = { [weak self] moved in Task { @MainActor in self?.consoleMoved(moved) } }
        session.onFrame = { [weak self] frame in
            // Karenin geldiği an: gecikme buradan TV'ye gidene kadar ölçülür.
            let capturedAt = SubtitleStabilizer.uptimeMs()
            Task { @MainActor in await self?.handle(frame, capturedAt: capturedAt) }
        }
        session.start()
        self.session = session
        startKeeper()
        gameChoice.start(console: consoleName) { [weak self] in
            guard let self else { return false }
            return self.settings.askGame && self.settings.sharePool
        }
        isRunning = true
        server.sendStarted()
        identifyTries = 0
        identifyChecks = 0
        identifyLast = Date()
        startedAt = Date()
        runningSince = startedAt
        recentLines = []
        lastMetrics = nil
        sessionLines = 0
        sessionPackLines = 0
        packInUse = nil
        keepScreenAwake(true)
        if notifiesDisconnect { requestNotificationPermission() }
        onAnalytics(.sessionStart(output: settings.output.rawValue))
    }

    /// Demo oturumunu başlatır: birkaç saniyede bir örnek satır gösterir. Gerçek oturum açıksa bir şey yapmaz.
    func startDemo() {
        guard !isRunning, !isStarting, !isDemo else { return }
        isDemo = true
        demoLine = nil
        keepScreenAwake(true)
        let target = settings.targetLanguage
        demoTask = Task { [weak self] in
            var index = 0
            try? await Task.sleep(nanoseconds: 700_000_000)
            while !Task.isCancelled {
                let line = DemoSamples.line(index, target: target)
                self?.demoLine = line
                index += 1
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                if Task.isCancelled { break }
                self?.demoLine = nil
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
    }

    /// Demo biter; ekran eski haline döner.
    func stopDemo() {
        demoTask?.cancel()
        demoTask = nil
        guard isDemo else { return }
        isDemo = false
        demoLine = nil
        keepScreenAwake(false)
    }

    func stop() {
        if let startedAt {
            let seconds = Int(Date().timeIntervalSince(startedAt))
            onAnalytics(.sessionStop(seconds: seconds))
            defaults.set(seconds, forKey: "lastSessionSeconds")
            self.startedAt = nil
        }
        runningSince = nil
        packInUse = nil
        gameChoice.stop()
        session?.stop()
        session = nil
        updateGameProbe(connected: false)
        keeper?.stop()
        keeper = nil
        pipeline?.reset()
        translationSync?.cancel()
        translationSync = nil
        pipeline = nil
        regionWatcher?.reset()
        regionWatcher = nil
        // Yeni "Başlat" eski oturumdan kalan (belki takılmış) okumayı beklemeden temiz başlar.
        frameGate.reset()
        isRunning = false
        onlineIssue = nil
        sessionState = .disconnected(.stopped)
        phoneHide()
        keepScreenAwake(false)
    }

    /// Uygulama yeniden öne gelince (iOS arka planda bağlantıları keser) PS5 ve TV bağlantıları hemen yenilenir.
    /// Arka plana gitmeden yalnız etkin olmaktan çıkıp dönünce (Denetim Merkezi, bildirim, izin penceresi) çalışan PS5
    /// oturumu kapatılıp açılmaz: eskiden her dönüşte kapatılıyor, PS5'te ikinci hesap girip çıkıyordu.
    func becameActive(afterBackground: Bool = true) {
        guard isRunning else { return }
        if afterBackground || !Self.isLive(sessionState) { session?.reconnectNow() }
        keeper?.reconnect()
    }

    /// Bağlı ya da bağlanıyor; yeniden bağlanmaya gerek yok.
    private static func isLive(_ state: SessionState) -> Bool {
        if case .disconnected = state { return false }
        return true
    }

    private func startKeeper() {
        guard keeper == nil, settings.output.showsOnTV, hasTV, let tv else { return }
        let server = self.server
        let keeper = services.makeKeeper(tv: tv, key: store.load(String.self, for: StoreKey.tvKey), params: ["server": serverAddress(for: tv)],
                                         appConnected: { server.connectedClients > 0 }, onMoved: { [weak self] moved in
            Task { @MainActor in self?.tvMoved(to: moved) }
        }, onKey: { [weak self] key in
            Task { @MainActor in self?.store.save(key, for: StoreKey.tvKey) }
        })
        keeper.start(interval: .seconds(5))
        self.keeper = keeper
    }

    private func outputChanged() {
        server.sendsToTV = settings.output.showsOnTV
        if !settings.output.showsOnComputer { phoneHide() }
        guard isRunning else { return }
        if settings.output.showsOnTV {
            startKeeper()
        } else {
            keeper?.stop()
            keeper = nil
        }
    }

    private func tvMoved(to moved: LGTV) {
        tv = moved
        store.save(moved, for: StoreKey.tv)
    }

    private func consoleMoved(_ moved: RegisteredConsole) {
        guard console != nil else { return }
        console = moved
        store.save(moved, for: StoreKey.console)
    }

    /// PS5'e bağlanınca çalışan oyun okunmaya başlar, bağlantı gidince bırakılır (havuz satırı oyunsuz gider).
    private func updateGameProbe(connected: Bool) {
        guard probesGame else { return }
        guard connected, !isXbox, let host = console?.host else {
            gameProbe?.cancel()
            gameProbe = nil
            gameChoice.consoleReported(nil)
            return
        }
        guard gameProbe == nil else { return }
        let services = self.services
        gameProbe = Task { [weak self] in
            while !Task.isCancelled {
                let game = await services.runningGame(host: host)
                // Bu arada bağlantı bittiyse oyun yazılmaz (bırakılan oyun geri gelmesin).
                guard !Task.isCancelled else { break }
                // Yeni oyunda paket sunucusuna bakılması `gameChoice.onChange`te (Android'deki gibi).
                self?.gameChoice.consoleReported(game)
                try? await Task.sleep(for: Self.gameProbeInterval)
            }
        }
    }

    private func sessionStateChanged(_ state: SessionState) {
        let wasStreaming = sessionState == .streaming
        sessionState = state
        // Akış sürerken kendiliğinden koptu (kullanıcı durdurmadı): tercih açıksa bildirim (uygulama etkin değilse).
        if wasStreaming, isRunning, case .disconnected(let reason) = state, reason != .stopped, notifiesDisconnect {
            onConnectionLost()
        }
        updateGameProbe(connected: state == .streaming)
        if case .disconnected = state {
            pipeline?.reset()
            regionWatcher?.reset()
            server.clear()
        }
    }

    private func makePipeline() {
        pipeline?.reset()
        // Eski hatta süren okuma beklenmez; yeni hat ilk karesini hemen alır.
        frameGate.reset()
        let scheduler = ReadScheduler(maxReuse: settings.fastSubtitleDetection
            ? ReadScheduler.fastMaxReuse : ReadScheduler.defaultMaxReuse)
        let pipeline = SubtitlePipeline(reader: VisionReader(language: settings.sourceLanguage), translator: makeTranslator(),
                                        server: server, scheduler: scheduler)
        pipeline.showSpeakerNames = settings.showSpeakerNames
        pipeline.onPair = { [weak self, weak pipeline] source, translation in
            self?.lastSource = source
            self?.lastTranslation = translation
            let fromPack = pipeline?.lastOrigin == "paket"
            if fromPack, let title = self?.packs.scopeTitle { self?.packInUse = title }
            if let self { self.gameChoice.noteLine(fromPack: fromPack, packs: self.packs) }
            self?.addToHistory(source: source, translation: translation, origin: fromPack ? .pack : .engine)
            self?.noteLine(source: source, translation: translation, fromPack: fromPack)
        }
        pipeline.onMetrics = { [weak self] metrics in self?.lastMetrics = metrics }
        // Nino: zaten Türkçe olan satır (PS5 menüsü) çevirmene gitmez.
        pipeline.targetLanguage = settings.targetLanguage
        pipeline.onTranslationResult = { [weak self] error in
            let status: TranslatorStatus = switch error {
            case nil: .ready
            case .needsDownload: .needsDownload
            case .unsupported: .unsupported
            }
            self?.translatorStatus = status
        }
        // Ek alan okuyucusu yeni dil ve motorla, ilk ek alan karesinde yeniden kurulur.
        regionWatcher?.reset()
        regionWatcher = nil
        connectPacks(to: pipeline)
        startTranslationSync()
        onlineIssue = nil
        pipeline.warmUp()
        self.pipeline = pipeline
    }

    /// Ek alanlar aynı dil, motor ve paketlerle okunur; ayrı bir okuyucu ve çevirmenle (altyazının sırasını beklemez).
    private func makeRegionWatcher(packLookup: ((String) -> PackMatch?)?) -> RegionWatcher {
        let watcher = RegionWatcher(reader: VisionReader(language: settings.sourceLanguage), translator: makeTranslator(), server: server)
        watcher.packLookup = packLookup
        watcher.onLog = { SubtitleLog.write($0) }
        return watcher
    }

    private func handle(_ frame: CGImage, capturedAt: Int) async {
        framePreview.image = frame
        guard let current = pipeline else { return }
        identifyGameIfNeeded(frame)
        // Ek alanlar ayrı ve seyrek okunur (saniyede bir); altyazı okumasını beklemez, onu bekletmez.
        let areas = settings.activeExtraAreas
        if regionWatcher == nil, !areas.isEmpty { regionWatcher = makeRegionWatcher(packLookup: regionPackLookup) }
        regionWatcher?.offer(frame, areas: areas)
        // Önceki kare hâlâ işleniyorsa bu kare atlanır. Tek okuma bitmezse çeviri tamamen duruyor, "Durdur / Başlat"
        // düzeltmiyordu (Mac'te görüldü, 2026-11-13); takılan okuma hattı yeniden kurdurur.
        var entry = frameGate.enter(now: SubtitleStabilizer.uptimeMs())
        if case .stuck(let ms) = entry {
            SubtitleLog.write("okuma \(ms) ms'dir bitmedi; okuma hattı yeniden kuruldu")
            makePipeline()
            entry = frameGate.enter(now: SubtitleStabilizer.uptimeMs())
        }
        guard case .enter(let token) = entry, let pipeline else { return }
        await pipeline.process(frame, region: settings.region, capturedAt: capturedAt)
        frameGate.leave(token)
    }

    // MARK: - Oyunu ekrandan tanıma (Mac'teki ile aynı)

    /// Claude kareye bakıp oyunun adını söyler: başlangıçtan ~8 sn sonra, olmazsa dakikada bir, en çok 6 kez. Tanıdıktan
    /// sonra 5 dk sonra bir kez doğrular, sonra 20 dakikada bir bakar (oyun değişmiş olabilir).
    private var identifyTask: Task<Void, Never>?
    private var identifyTries = 0
    private var identifyChecks = 0
    private var identifyLast = Date()

    private func identifyGameIfNeeded(_ frame: CGImage) {
        // Paketten tahmin edilen oyun kesin değildir: havuz öncelikli oyun bilinmiyorsa ekrandan tanıma yine denenir.
        guard isRunning, settings.sharePool, settings.sourceLanguage == "en", identifyTask == nil,
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
            return
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
            guard let name else { return }
            if let known, NinoPool.gameID(known.name) == NinoPool.gameID(name) { return }
            SubtitleLog.write("oyun ekrandan tanındı: \(name)")
            self.gameChoice.seen(name)
            self.startTranslationSync()
        }
    }

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

    // MARK: - Geçmiş

    /// Açılışta kayıtlı geçmiş okunur (uygulama çağırır; testlerde çağrılmaz, dosyaya yazılmaz).
    func loadHistory(from file: URL = SubtitleHistory.defaultFile) {
        historyFile = file
        history = SubtitleHistory.load(from: file)
    }

    private func addToHistory(source: String, translation: String, origin: LineMetrics.Origin) {
        history.add(source: source, translation: translation, origin: origin)
        saveHistory()
    }

    /// "Geçmiş"teki "Temizle".
    func clearHistory() {
        history.clear()
        saveHistory()
    }

    private func saveHistory() {
        guard let historyFile else { return }
        let history = self.history
        historyQueue.async { try? history.save(to: historyFile) }
    }

    private func noteLine(source: String, translation: String, fromPack: Bool) {
        lastFromPack = fromPack
        sessionLines += 1
        if fromPack {
            sessionPackLines += 1
            onAnalytics(.packHit(packId: nil))
        }
        recentLines.insert(RecentLine(id: sessionLines, source: source, translation: translation, fromPack: fromPack), at: 0)
        if recentLines.count > 30 { recentLines.removeLast() }
    }

    /// Okuma hattı oyun paketlerine bakıyor mu: ayar açık ve İngilizce→Türkçe (paketler herkese ücretsiz).
    var packsActive: Bool {
        settings.gamePacks && settings.sourceLanguage == "en" && settings.targetLanguage == "tr"
    }

    /// Paketler ekranında karoya dokunma: paket açılır ya da kapanır (okuma hattı hemen yeni listeyle eşleşir).
    func togglePack(_ id: String) {
        if disabledPacks.contains(id) { disabledPacks.remove(id) } else { disabledPacks.insert(id) }
        defaults.set(disabledPacks.sorted(), forKey: Self.disabledPacksKey)
        if let pipeline { connectPacks(to: pipeline) }
    }

    /// Paketler güncellendi: okuma hattı yeni listeyle eşleşir.
    func packsChanged() {
        if let pipeline { connectPacks(to: pipeline) }
        reloadPackList()
    }

    /// Paketler yalnız İngilizce→Türkçede ve ayar açıkken kullanılır; pakette olmayan satır ortak havuza önerilir.
    private func connectPacks(to pipeline: SubtitlePipeline) {
        let packs = self.packs
        let pool = self.pool
        let translations = self.translations
        let store = translations.store
        let recent = poolContext
        let active = packsActive
        let disabled = disabledPacks
        // Nino: sunucunun çeviri havuzu bütün dillerde, kaynak İngilizceyken ve ortak havuz açıkken.
        let pooled = settings.sharePool && settings.sourceLanguage == "en"
        // Kapatılan paket: paketler tek sözlükte birleştiği için eşleşmeyi veren paket, bulanık aramanın kapsamından
        // (son tam eşleşmenin paketi) okunur; o paket kapalıysa satır motorla çevrilir.
        let packLookup: ((String) -> PackMatch?)? = !active ? nil : disabled.isEmpty ? { packs.match($0) } : { text in
            guard let found = packs.match(text) else { return nil }
            return packs.searchScope.map(disabled.contains) == true ? nil : found
        }
        let sense = gameChoice.sense
        // Havuz öncelikli oyunda (GTA 6) başka oyunların paketlerine bakılmaz: çeviri yalnız havuzdan (Claude). Havuzdaki
        // çeviri ortak havuz kapalıyken de kullanılır.
        let poolFirst: @Sendable () -> Bool = { translations.isPoolFirst(translations.poolGame(sense.current?.name, packs.searchScope)) }
        let english = settings.sourceLanguage == "en"
        pipeline.packLookup = packLookup == nil && !pooled && !english ? nil : { text in
            let first = poolFirst()
            if !first, let found = packLookup?(text) { return found }
            guard pooled || first, let translated = store.match(text) else { return nil }
            return PackMatch(text: translated, spoken: [SpokenLine(english: text, turkish: translated)])
        }
        // Ek alanlar yalnız pakette aranır; havuza gitmez (arayüz ve bildirim yazıları kişisel olabilir).
        regionPackLookup = packLookup
        regionWatcher?.packLookup = regionPackLookup
        guard settings.sourceLanguage == "en" else {
            pipeline.onPackMiss = nil
            return
        }
        pipeline.onPackMiss = { [weak pipeline] text in
            // Kapalı paketteki satır da havuza önerilmez (zaten çevrili).
            guard (active && disabled.isEmpty) || poolFirst() || packs.match(text) == nil else { return }
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

    /// Havuz kuyruğu: uygulama arka plana geçerken gönderilir (iOS sonra uygulamayı askıya alabilir).
    func flushPool() async { await pool.flush(force: true) }

    func refreshTranslatorStatus() async {
        if onlineTranslationActive {
            translatorStatus = .ready
            return
        }
        translatorStatus = await Translator.status(source: settings.sourceLanguage, target: settings.targetLanguage)
    }

    /// Nino: havuz öncelikli oyunda (sunucunun listesi, varsayılan GTA 6) çeviri yalnız havuzdan, gelmezse ücretsiz
    /// çeviriden; kullanıcının anahtarlı motoru çağrılmaz. Ortak havuz ayarı kapalı olsa da (kullanıcı kararı).
    private func makeTranslator() -> TextTranslator {
        let (source, target) = (settings.sourceLanguage, settings.targetLanguage)
        let free = Translator(source: source, target: target,
                              cache: Self.translationCache(engine: Translator.engineID, source: source, target: target))
        let (translations, packs, sense, recent) = (translations, packs, gameChoice.sense, poolContext)
        let english = source == "en"
        let translator = PoolFirstTranslator(engine: makeEngineTranslator(), free: free,
                                   poolFirst: { english && translations.isPoolFirst(translations.poolGame(sense.current?.name, packs.searchScope)) },
                                   ask: { line in
                                       await translations.translateFirst(line, context: recent.before(line),
                                                                         game: translations.poolGame(sense.current?.name, packs.searchScope))
                                   })
        translator.log = { SubtitleLog.write($0) }
        return translator
    }

    /// Kullanıcının seçtiği çevirmen: ücretsiz, DeepL ya da yapay zekâ.
    private func makeEngineTranslator() -> TextTranslator {
        let (source, target) = (settings.sourceLanguage, settings.targetLanguage)
        let local = Translator(source: source, target: target,
                               cache: Self.translationCache(engine: Translator.engineID, source: source, target: target))
        let engine = settings.onlineEngine
        guard onlineTranslationActive, let storeKey = engine.storeKey, let key = store.load(String.self, for: storeKey) else { return local }
        let online: TextTranslator & OnlineTranslating
        if let provider = engine.aiProvider {
            let model = provider.model(settings.model(for: provider)).id
            // Oynanan oyunun adı modele bağlam olarak gider; önbellek de oyuna göre ayrılır (Mac ile aynı). Ad kararlı
            // oyundur (`GameSense.current`), son eşleşen paket değil: tek bir ortak satır adı başka oyuna geçirmez (#27).
            let sense = gameChoice.sense
            online = AITranslator(provider: provider, key: key, model: model, fallback: local,
                                  cache: Self.translationCache(engine: provider.engineID(model: model), source: source, target: target),
                                  target: target, game: { sense.current?.name })
        } else {
            online = DeepLTranslator(key: key, fallback: local,
                                     cache: Self.translationCache(engine: DeepLTranslator.engineID, source: source, target: target),
                                     target: target)
        }
        online.onFailureChanged = { [weak self] state in Task { @MainActor in self?.onlineIssue = state } }
        return online
    }

    private static func translationCache(engine: String, source: String, target: String) -> TranslationCache {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppIdentity.name, isDirectory: true).appendingPathComponent("Translations", isDirectory: true)
        return TranslationCache.shared(in: directory, engine: engine, source: source, target: target)
    }

    // MARK: - Çevrimiçi çeviri anahtarları (Anahtarlık)

    var onlineTranslationActive: Bool {
        // Nino: çevrimiçi motorlar listedeki dillere çevirir (istemler hedef dile göre); DeepL yalnız desteklediklerine.
        settings.onlineTranslation && settings.sourceLanguage == "en"
            && TargetLanguage.choices.contains { $0.code == settings.targetLanguage }
            && (settings.onlineEngine != .deepL || TargetLanguage.deepLSupports(settings.targetLanguage))
            && hasKey(settings.onlineEngine)
    }

    func hasKey(_ engine: TranslationEngine) -> Bool { savedKeys.contains(engine) }

    /// PS5 giriş şifresi: yalnız 4 hane Anahtarlık'a kaydedilir; geçersizse false. Sonraki bağlantıda kullanılır.
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

    /// Anahtar denenir; kabul edildiyse Anahtarlık'a yazılır ve motor seçilir. Dönen metin kullanıcıya gösterilir.
    func saveKey(_ key: String, for engine: TranslationEngine) async -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let storeKey = engine.storeKey else { return false }
        let accepted: Bool
        if let provider = engine.aiProvider {
            switch await services.testAIKey(provider: provider, key: key, model: settings.model(for: provider)) {
            case .success, .failure(.quotaExceeded), .failure(.modelRejected): accepted = true
            case .failure: accepted = false
            }
        } else {
            let state = await services.checkDeepLKey(key).state
            accepted = state == .valid || state == .quotaExceeded
        }
        guard accepted else { return false }
        store.save(key, for: storeKey)
        savedKeys.insert(engine)
        if settings.translationEngine == engine {
            if isRunning { makePipeline() }
            await refreshTranslatorStatus()
        } else {
            settings.translationEngine = engine
        }
        return true
    }

    func removeKey(_ engine: TranslationEngine) {
        guard let storeKey = engine.storeKey else { return }
        store.remove(storeKey)
        savedKeys.remove(engine)
        if settings.translationEngine == engine { settings.onlineTranslation = false }
    }

    // MARK: - Telefon ekranındaki altyazı

    /// Sunucunun TV'ye gönderdiği olayların aynısı telefon ekranına da gelir (TV kurulu olmasa da).
    func phoneReceive(_ event: SubtitleEvent) {
        guard settings.output.showsOnComputer else { return }
        let now = clock()
        switch event {
        case .subtitle(let text, let durationMs, let paragraphs, let replaces):
            // Aynı cümlenin uzamış ya da düzelmiş okuması öncekinin yerine geçer (Mac'teki pencere ve TV gibi).
            stack.stackPrevious = settings.style.stackPrevious
            stack.show(text, durationMs: durationMs, paragraphs: paragraphs, replaces: replaces, now: now)
        case .clear:
            stack.clear(now: now)
        // "Ekranı çevir" sonuçları yazının yerinde gösterilir (`screenItems`); satır yığınına girmez.
        case .screen, .screenClear:
            return
        // Ek alanın çevirisi telefon ekranında da kendi yerinde küçük kutuda görünür (boş metin kutuyu kaldırır).
        case .region(let id, let text, let box):
            var regions = phoneRegions.filter { $0.id != id }
            if !text.isEmpty { regions.append(PhoneRegion(id: id, text: text, box: box)) }
            if regions != phoneRegions { phoneRegions = regions }
            return
        case .regionClear:
            if !phoneRegions.isEmpty { phoneRegions = [] }
            return
        }
        phoneRefresh()
    }

    private func phoneRefresh() {
        let now = clock()
        let lines = stack.lines(at: now)
        if lines != phoneLines { phoneLines = lines }
        stackTimer?.cancel()
        stackTimer = nil
        guard let next = stack.nextChange(after: now) else { return }
        let wait = max(0.01, next - now)
        stackTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.phoneRefresh()
        }
    }

    private func phoneHide() {
        stack.hide()
        stackTimer?.cancel()
        stackTimer = nil
        if !phoneLines.isEmpty { phoneLines = [] }
        if !phoneRegions.isEmpty { phoneRegions = [] }
        hideScreen()
    }

    // MARK: - Ekranı çevir

    /// "Ekranı çevir": PS5'in şu anki karesinin tamamı bir kez okunur, yazı grupları (menü, görev paneli, bilgi kutusu...)
    /// tek istekte çevrilir; sonuçlar telefonda ve TV'de yazının kendi yerinde görünür. Çeviri sürerken ya da sonuçlar
    /// ekrandayken yeniden dokunmak onları kaldırır (Mac ⌥⌘T ile aynı).
    func translateScreen() {
        guard isRunning else { return }
        if screenState != .idle {
            hideScreen()
            return
        }
        guard let frame = framePreview.image else {
            server.sendSubtitle(String(localized: "Couldn't capture the screen: no picture from the PS5 yet."), durationMs: 4000)
            return
        }
        screenState = .working
        server.sendStyle(settings.style)
        server.sendSubtitle(String(localized: "Translating the screen…"), durationMs: 2500)
        let reader = VisionReader(language: settings.sourceLanguage)
        let translator = makeTranslator()
        let server = self.server
        screenTask = Task { [weak self] in
            do {
                let reading = try await Task.detached(priority: .userInitiated) { try reader.readLines(frame, deep: false) }.value
                let items = try await ScreenTranslation.translate(reading, using: translator) { shown in
                    guard !Task.isCancelled else { return }
                    let milliseconds = ScreenTranslation.displayMilliseconds(shown)
                    server.sendScreen(shown, durationMs: milliseconds)
                    self?.showScreen(shown, milliseconds: milliseconds)
                }
                guard !Task.isCancelled else { return }
                server.clear()
                if items.isEmpty {
                    self?.screenState = .idle
                    server.sendSubtitle(String(localized: "No text found on the screen."), durationMs: 2500)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.showScreenFailure(error, translator: translator)
            }
            self?.screenTask = nil
        }
    }

    private func showScreen(_ items: [ScreenTranslation.Item], milliseconds: Int) {
        if settings.output.showsOnComputer { screenItems = items }
        screenState = .shown
        screenExpiry?.cancel()
        screenExpiry = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled else { return }
            self?.hideScreen()
        }
    }

    /// Çeviriyi durdurur, sonuçları telefondan ve TV'den kaldırır.
    func hideScreen() {
        guard screenState != .idle || !screenItems.isEmpty else { return }
        screenTask?.cancel()
        screenTask = nil
        screenExpiry?.cancel()
        screenExpiry = nil
        screenItems = []
        screenState = .idle
        server.clearScreen()
        server.clear()
    }

    /// Ekran çevrilemedi: nedeni telefonda ve TV'de birkaç saniye görünür.
    private func showScreenFailure(_ error: Error, translator: TextTranslator) {
        guard !Task.isCancelled else { return }
        screenState = .idle
        server.clear()
        let reason: String
        if let online = ((translator as? PoolFirstTranslator)?.engine ?? translator) as? AITranslator, online.lastLineWasRateLimited {
            reason = String(format: String(localized: "%@ has reached its per-minute limit. Try again in a minute."), settings.translationEngine.displayName)
        } else {
            switch error as? TranslatorError {
            case .needsDownload: reason = String(localized: "The free translation isn't downloaded yet.")
            case .unsupported: reason = String(localized: "The free translation doesn't work on this phone.")
            case nil: reason = String(localized: "Something went wrong. Try again.")
            }
        }
        server.sendSubtitle(String(format: String(localized: "Couldn't translate the screen: %@"), reason), durationMs: 6000)
    }

    /// Nino: çeviri dili değişti. Eski dildeki satırlar ekrandan ve son satırlar listesinden kalkar.
    private func targetLanguageChanged() {
        phoneHide()
        recentLines = []
        lastSource = ""
        lastTranslation = ""
        if isRunning { server.clear() }
    }

    /// Deneme altyazısı: TV'de ya da telefon ekranında yazının nasıl göründüğü.
    func sendTestSubtitle() {
        Task {
            try? await startServer()
            server.sendStyle(settings.style)
            server.sendSubtitle(String(localized: "This is a test subtitle. Can you see it on top of the game?"), durationMs: 8000)
        }
    }

    // MARK: - Durum metinleri

    var ps5StatusText: String {
        switch sessionState {
        case .streaming: return String(localized: "Connected")
        case .connecting: return String(localized: "Connecting…")
        case .disconnected(let reason):
            guard isRunning else { return String(localized: "Not connected") }
            switch reason {
            case .consoleAsleep: return String(localized: "Turn on your PS5")
            case .inUse: return String(localized: "Remote Play is in use on another device")
            case .refused: return String(localized: "The PS5 refused the connection. Set up the PS5 again.")
            case .loginPasscode:
                return String(localized: "The PS5 asks for this account's login passcode. Enter it in Settings, or turn off this account's login passcode on the PS5.")
            case .loginPasscodeIncorrect:
                return String(localized: "The PS5 didn't accept the login passcode in Settings. Correct it, or turn off this account's login passcode on the PS5.")
            case .registrationInvalid: return String(localized: "The PS5 didn't accept this pairing. Pair the PS5 again with the second account in Settings.")
            case .remotePlayDisabled: return String(localized: "Remote Play is turned off on the PS5. On the PS5, open Settings › System › Remote Play and turn on Enable Remote Play, then start again.")
            case .noPicture: return String(localized: "No picture from the PS5. Is Remote Play turned off, or is the PS5 in rest mode? Check, then start again.")
            case .notFound(let host):
                return String(format: String(localized: "PS5 not found at %@. Make sure it is on and on the same network. Reconnecting…"), host)
            case .network: return String(localized: "Can't reach the PS5. Reconnecting…")
            // Eskiden "Yeniden bağlanılıyor…" ile anlamsız libchiaki metni (Unknown Session Request Error) vardı.
            case .rejected(let code?):
                return String(format: String(localized: "The PS5 rejected the connection (code %@). Another Remote Play app (PS Remote Play) may be open, or the PS5 may be in another session. Close PS Remote Play, restart the PS5, then try again."), String(format: "0x%08x", code))
            case .rejected(nil): return String(localized: "The PS5 didn't start the session. Another Remote Play app (PS Remote Play) may be open, or the PS5 may be in another session. Close PS Remote Play, restart the PS5, then try again.")
            case .other(let detail) where isXbox: return detail
            case .other, .stopped: return String(localized: "Reconnecting…")
            }
        }
    }

    var tvStatusText: String {
        tvClients > 0 ? String(localized: "Connected") : String(localized: "Waiting for the TV app")
    }

    // MARK: - TV uygulamasının sürümü

    /// TV'deki CouchSubs sürümünü sessizce okur (Samsung sdb, Android TV adb, LG ssh; geliştirici modu kapalıysa
    /// sorulamaz); telefondaki paketten eskiyse `tvAppUpdate` dolar. Uygulama açılınca ve TV her bağlandığında çağrılır.
    func checkTVApp(force: Bool = false) async {
        guard !checkingTVApp else { return }
        if !force, let last = tvAppCheckedAt, Date().timeIntervalSince(last) < 60 { return }
        let target: (TVBrand, String, UInt16?)
        if let installed = installedTVApp {
            target = (installed.brand, installed.host, installed.port)
        } else if let tv, !tv.host.isEmpty {
            target = (tv.brand, tv.host, nil)
        } else {
            return
        }
        guard let bundled = TVPackages.version(for: target.0) else { return }
        checkingTVApp = true
        tvAppCheckedAt = Date()
        defer { checkingTVApp = false }
        guard let version = await TVAppVersionCheck.installedVersion(brand: target.0, host: target.1, port: target.2) else { return }
        if Versions.isNewer(bundled, than: version) {
            tvAppUpdate = TVAppUpdate(brand: target.0, host: target.1, port: target.2, installed: version, bundled: bundled)
        } else {
            tvAppUpdate = nil
        }
        saveInstalledTVApp(InstalledTVApp(brand: target.0, host: target.1, port: target.2, version: version))
    }

    /// Telefondan kurulum ya da sürüm denetimi bitti: TV hatırlanır. Android TV onaysız eşlendiği için altyazı hedefi olur.
    func tvAppInstalled(brand: TVBrand, host: String, port: UInt16?, version: String) async {
        saveInstalledTVApp(InstalledTVApp(brand: brand, host: host, port: port, version: version))
        if tvAppUpdate?.brand == brand, !Versions.isNewer(tvAppUpdate?.bundled ?? "", than: version) { tvAppUpdate = nil }
        tvAppMissing = false
        // Kurulan TV altyazı hedefi olur (Android'deki TvAppUpdate.installed gibi); yoksa kurulumun 3. adımında "Devam"
        // kapalı kalıyor, uygulama her açılışta yine o adımdan başlıyordu (#113).
        if !(tv?.brand == brand && tv?.host == host && hasTV) {
            let name = switch brand {
            case .androidTV: "Android TV"
            case .lg: "LG TV"
            case .samsung: "Samsung TV"
            }
            try? await pair(LGTV(name: name, host: host, brand: brand))
        }
        if hasTV, tv?.host == host, step == .output {
            store.save(true, for: StoreKey.setupComplete)
        }
    }

    private func saveInstalledTVApp(_ value: InstalledTVApp) {
        installedTVApp = value
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: StoreKey.tvAppInstalled) }
    }

    // MARK: - Sunucu

    private func startServer() async throws {
        guard !serverStarted else { return }
        do {
            serverPort = try await server.start()
        } catch {
            server = SubtitleServer(port: 0)
            attachServer()
            serverPort = try await server.start()
        }
        serverStarted = true
    }

    /// TV ile aynı ağdaki telefon adresi.
    func serverAddress(for tv: LGTV) -> String {
        "http://\(NetworkAddress.near(tv.host.isEmpty ? "192.168.1.1" : tv.host) ?? "127.0.0.1"):\(serverPort)"
    }
}

/// Son PS5 karesi; yalnız bölge önizlemesi izler (her karede bütün ekranlar yeniden çizilmesin).
@MainActor
final class PhoneFramePreview: ObservableObject {
    @Published var image: CGImage?
}
