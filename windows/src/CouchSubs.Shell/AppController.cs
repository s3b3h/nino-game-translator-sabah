// SPDX-License-Identifier: AGPL-3.0-only

using System.ComponentModel;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.CompilerServices;
using CouchSubs.Core;
using CouchSubs.Core.Dubbing;
using CouchSubs.Core.LgTv;
using CouchSubs.RemotePlay;

namespace CouchSubs.Shell;

/// <summary>
/// Uygulamanın durumu ve akışı (Mac'teki AppModel'in karşılığı): kurulum sihirbazı, çeviriyi
/// başlatma/durdurma, PS5 ve TV durumları. Arayüz bu nesneye bağlanır; olaylar <c>post</c> ile
/// arayüz iş parçacığına aktarılır.
/// </summary>
public sealed class AppController : INotifyPropertyChanged, IDisposable
{
    public const string TvAppId = "com.couchsubs.tv";
    public const int DefaultServerPort = 8787;

    private readonly IAppServices services;
    private readonly IAppStore store;
    private readonly ISettingsStore settingsStore;
    private readonly ISleepGuard sleep;
    private readonly Localizer text;
    private readonly Action<Action> post;

    private OnboardingStep step;
    private byte[]? accountId;
    private RegisteredConsole? console;
    private GameConsoleKind consoleKind;
    private bool consoleKindLocked;
    private string? xboxToken;
    private XboxConsole? xboxConsole;
    private int xboxGeneration;
    private bool xboxNameChecked;
    private LgTv? tv;
    private TvAppState tvApp = TvAppState.Unknown;
    /// <summary>Son eşleşmede TV uygulaması açılamadı.</summary>
    private bool tvAppMissing;
    /// <summary>TV uygulaması denetimi sürüyor (bekleme ekranı ve çeviri başlangıcı aynı anda çağırabilir).</summary>
    private bool refreshingTvApp;
    private int? devModeHoursLeft;
    private UserSettings settings;
    private bool isRunning;
    private bool isStarting;
    private SessionState sessionState = SessionState.Disconnected(DisconnectKind.Stopped);
    private int tvClients;
    private string lastSource = "";
    private string lastTranslation = "";
    private TranslatorStatus translatorStatus = TranslatorStatus.Ready;
    private OnlineKeyState? onlineIssue;
    private bool ocrMissing;
    private Frame? lastFrame;
    private bool modelDownloading;
    private double modelProgress;
    private string? modelError;
    private Task? modelDownload;

    private SubtitleServer server = new(DefaultServerPort);
    private bool serverStarted;
    private IStreamSession? session;
    private IKeeper? keeper;
    private SubtitlePipeline? pipeline;
    /// <summary>Hattın yazı okuyucusu; ek bölgelerin tek seferlik okuması da bunu kullanır.</summary>
    private ITextReader? activeReader;
    private int extraBusy;
    private bool subtitlesPaused;
    /// <summary>Oyundaki altyazının son görüldüğü yer; deneme altyazısı TV'de oraya yerleşir.</summary>
    private TextBox? lastSubtitleBox;
    /// <summary>Hatta aynı anda tek kare girer; durdurma ve yeni hat kapıyı sıfırlar, takılan okuma hattı yeniden kurdurur.</summary>
    private readonly FrameGate frameGate = new();
    private Dubber? dubber;
    private string? updateVersion;
    private bool updating;
    private double updateProgress;
    private string? updateError;
    private bool dubbingDownloading;
    private double dubbingProgress;
    private string? dubbingError;
    private IReadOnlyList<GamePackLibrary.Info> installedPacks = [];
    private Timer? poolTimer;
    /// <summary>Bağlıyken iki dakikada bir PS5'e çalışan oyunu sorar (havuza giden satırlar oyunla gider).</summary>
    private CancellationTokenSource? gameProbe;
    public static readonly TimeSpan GameProbeInterval = TimeSpan.FromMinutes(2);
    /// <summary>
    /// Oynanan oyun: PS5'in bildirdiği, kullanıcının seçtiği ya da paketten tanınan (havuza giden satırlar bu oyunla gider;
    /// Mac ve iPhone'daki GameChoice ile aynı davranış).
    /// </summary>
    private readonly GameSense gameSense = new();
    /// <summary>Nino: oyunu Remote Play karesinden tanıma zamanlaması (Mac identifyGameIfNeeded).</summary>
    private readonly ScreenIdentifySchedule identifySchedule = new();
    private RunningGame? publishedGame;
    private string? playedGame;
    private bool askingGame;
    private CancellationTokenSource? gameAsk;
    /// <summary>Nino: oyunun havuzdaki çevirilerini indiren döngü (çeviri sürerken).</summary>
    private CancellationTokenSource? translationSync;
    /// <summary>Nino: havuza sorulan satırın bağlamı (önceki birkaç satır).</summary>
    private readonly PoolContext recentLines = new();
    private Timer? packTimer;
    private string metricsText = "";
    /// <summary>Çevrilen satırların geçmişi (arayüz iş parçacığında değişir).</summary>
    private readonly SubtitleHistory history;
    /// <summary>Geçmiş dosyaya sırayla yazılır; yazmalar üst üste binmez.</summary>
    private Task historySave = Task.CompletedTask;

    public event PropertyChangedEventHandler? PropertyChanged;

    public AppController(IAppServices services, IAppStore store, ISettingsStore settingsStore, ISleepGuard sleep, Localizer text, Action<Action> post)
    {
        this.services = services;
        this.store = store;
        this.settingsStore = settingsStore;
        this.sleep = sleep;
        this.text = text;
        this.post = post;
        if (services.Xbox is { } xbox) xbox.TokenUpdated += OnXboxTokenUpdated;
        accountId = store.Load<byte[]>(StoreKeys.AccountId);
        console = store.Load<RegisteredConsole>(StoreKeys.Console);
        consoleKind = store.Load<GameConsoleKind?>(StoreKeys.ConsoleKind) ?? GameConsoleKind.PlayStation;
        consoleKindLocked = store.Load<bool?>(StoreKeys.ConsoleKindLocked) ?? false;
        xboxToken = store.Load<string>(StoreKeys.XboxToken);
        xboxConsole = store.Load<XboxConsole>(StoreKeys.XboxConsole);
        tv = store.Load<LgTv>(StoreKeys.Tv);
        var loaded = settingsStore.Load();
        settings = loaded.WithCuratedModels() with
        {
            CpuTranslationThreads = CpuThreadOptions.Normalize(loaded.CpuTranslationThreads, Environment.ProcessorCount),
        };
        // Nino: TV'si olanlarda altyazı yalnız TV'de; bilgisayarda en önde duran pencere açılmaz (Mac ile aynı).
        // Capture Card'da "ikisi de" oyunun bu bilgisayarda da gösterilmesidir; korunur.
        if (settings.Output == SubtitleOutput.Both && settings.VideoSource != VideoSource.Card) settings = settings with { Output = SubtitleOutput.Tv };
        services.Translation.SelectCpuThreads(settings.CpuTranslationThreads);
        services.Translation.SelectDevice(settings.TranslationDevice);
        // Listede olmayan model varsayılana döndüyse ayar hemen kaydedilir.
        if (settings != loaded) settingsStore.Save(settings);
        var paired = tv is not null && store.Load<string>(StoreKeys.TvKey) is not null;
        // Remote Play penceresinden okurken PS5 eşleşmesi gerekmez.
        var consoleReady = consoleKind == GameConsoleKind.Xbox ? xboxToken is not null && xboxConsole is not null : accountId is not null && console is not null;
        var ready = (!IsXbox && (settings.FrameSource is FrameSource.RemotePlayWindow or FrameSource.CaptureWindow))
                    || SetupIsComplete(store, consoleReady, paired);
        // Yarım kalan kurulum (ör. TV uygulaması kurulurken kapatıldı) PS5 kayıtlıysa TV adımından sürer.
        // Nino: oyunu bu bilgisayarda Remote Play penceresinde oynayan PS5 eşleştirmeden kurulumu bitirmiş olabilir.
        // Yakalama kartı kullanan da öyle (PS5'e bağlanılmaz).
        var windowReady = settings.VideoSource != VideoSource.Ps5 && store.Load<bool?>(StoreKeys.SetupComplete) == true;
        step = ready || windowReady ? OnboardingStep.Done : consoleReady ? OnboardingStep.Tv : OnboardingStep.Welcome;
        AttachServer();
        StartPacksAndPool();
        services.Translation.EngineFailure += OnEngineFailure;
        services.Translation.GpuFallback += OnGpuFallback;
        history = services.HistoryFile is { } file ? SubtitleHistory.Load(file) : new SubtitleHistory();
    }

    /// <summary>
    /// Kurulum bitmiş mi. "Bitti" yalnız sihirbazın sonuna gelinince kaydedilir (TV adımı başarıyla geçildi ya da
    /// "TV'm yok" seçildi). Sihirbaz başlarken false yazılır: Samsung'da TV eşleşip uygulama kurulurken CouchSubs
    /// kapatılırsa eşleşme kayıtlı olsa da kurulum bitmiş sayılmaz. Hiç kayıt yoksa (beta.25'ten önce kurulmuş)
    /// eskisi gibi eşleşmiş TV yeter ve "bitti" kaydedilir.
    /// </summary>
    internal static bool SetupIsComplete(IAppStore store, bool consoleReady, bool paired)
    {
        var saved = store.Load<bool?>(StoreKeys.SetupComplete);
        var ready = consoleReady && (saved ?? paired);
        if (saved is null) store.Save(StoreKeys.SetupComplete, ready);
        return ready;
    }

    /// <summary>Ücretsiz çeviri motoru açılamadı (arka planda, ısınma sırasında da olabilir): ana ekran uyarısı çıksın.</summary>
    private void OnEngineFailure() => post(RefreshTranslatorStatus);

    private void OnGpuFallback() => post(() => GpuFallbackWarning = true);

    /// <summary>Sunucunun TV sayısını, altyazı yerini ve bilgisayar ekranına giden olayları bağlar (sunucu yeniden kurulunca da).</summary>
    private void AttachServer()
    {
        server.ClientsChanged += OnClientsChanged;
        server.EventSent += OnSubtitleEvent;
        server.SendsToTv = settings.Output.ShowsOnTv();
    }

    private void DetachServer()
    {
        server.ClientsChanged -= OnClientsChanged;
        server.EventSent -= OnSubtitleEvent;
    }

    // --- Durum ---

    public OnboardingStep Step
    {
        get => step;
        set
        {
            // Eşleştirme adımındaki güvenlik duvarı önerisi başka adıma taşınmaz.
            if (!Set(ref step, value, [nameof(CanAdvance), nameof(StepNumber)])) return;
            ClearFirewallPrompt();
            // Sihirbaz bitince ana ekran TV'siz de açılsın.
            if (value == OnboardingStep.Done) store.Save(StoreKeys.SetupComplete, true);
        }
    }
    public int StepCount => (int)OnboardingStep.Done - (consoleKind == GameConsoleKind.Xbox ? 1 : 0);
    public int StepNumber => Math.Min((int)step + 1 - (consoleKind == GameConsoleKind.Xbox && step > OnboardingStep.SecondAccount ? 1 : 0), StepCount);
    public GameConsoleKind ConsoleKind => consoleKind;
    public bool ConsoleKindLocked => consoleKindLocked;
    public bool IsXbox => consoleKind == GameConsoleKind.Xbox;
    /// <summary>Nino havuzunun kuruluşa özgü rastgele kimliği (Sorun Bildir de onu kullanır); havuz yoksa null.</summary>
    public string? PoolInstallId => services.Pool?.InstallId;
    public string ConsoleTitle => IsXbox ? "Xbox" : settings.FrameSource == FrameSource.CaptureWindow ? text["Selected window"] : "PS5";
    public bool HasXboxAccount => xboxToken is not null;
    public XboxConsole? SelectedXboxConsole => xboxConsole;
    public void SelectConsoleKind(GameConsoleKind kind)
    {
        if (step != OnboardingStep.Welcome || consoleKindLocked || kind == consoleKind || kind == GameConsoleKind.Xbox && services.Xbox is null) return;
        consoleKind = kind;
        store.Save(StoreKeys.ConsoleKind, kind);
        Changed(nameof(ConsoleKind), nameof(IsXbox), nameof(ConsoleTitle), nameof(StepCount), nameof(StepNumber), nameof(CanStart), nameof(CanAdvance), nameof(Ps5StatusText));
    }
    public async Task<XboxLoginChallenge> BeginXboxLoginAsync()
    {
        var login = await (services.Xbox ?? throw new InvalidOperationException(text["Xbox streaming isn't available in this version."])).BeginLoginAsync();
        OpenInBrowser(login.Url);
        return login;
    }
    public async Task CompleteXboxLoginAsync()
    {
        xboxToken = await (services.Xbox ?? throw new InvalidOperationException(text["Xbox streaming isn't available in this version."])).CompleteLoginAsync();
        store.Save(StoreKeys.XboxToken, xboxToken);
        Changed(nameof(HasXboxAccount), nameof(CanAdvance), nameof(CanStart));
    }
    private void OnXboxTokenUpdated(string token)
    {
        var generation = xboxGeneration;
        post(() =>
        {
            if (generation != xboxGeneration || !IsXbox || token == xboxToken) return;
            xboxToken = token;
            store.Save(StoreKeys.XboxToken, token);
        });
    }
    public async Task<IReadOnlyList<XboxConsole>> DiscoverXboxConsolesAsync()
    {
        var found = await (services.Xbox ?? throw new InvalidOperationException(text["Xbox streaming isn't available in this version."])).DiscoverAsync(xboxToken ?? throw new InvalidOperationException(text["Microsoft sign-in isn't finished."]));
        RenameSelectedXbox(found);
        return found;
    }

    /// <summary>
    /// Kayıtlı Xbox'ın adı listedekiyle değiştirilir: eski sürümler köprünün UTF-8 çıktısını yanlış kodlamayla okuyup
    /// "Oturma Odası"nı "Oturma OdasA+" diye kaydediyordu (#223). Konsol yeniden seçilmeden ad düzelir.
    /// </summary>
    private void RenameSelectedXbox(IReadOnlyList<XboxConsole> found)
    {
        if (xboxConsole is not { } saved || found.FirstOrDefault(item => item.Id == saved.Id) is not { } current || current.Name == saved.Name) return;
        xboxConsole = saved with { Name = current.Name };
        store.Save(StoreKeys.XboxConsole, xboxConsole);
        Changed(nameof(SelectedXboxConsole), nameof(Ps5StatusText));
    }

    /// <summary>
    /// Xbox görüntüsü ilk kez gelince liste arka planda bir kez sorulur; yalnız kayıtlı adı tazeler, hata yok sayılır.
    /// Görüntü gelene kadar beklenir: köprüye o sırada yayının yenilediği jeton yüklüdür, iki istek çakışmaz.
    /// </summary>
    private async Task RefreshXboxNameAsync()
    {
        if (services.Xbox is not { } xbox || xboxToken is not { } token) return;
        var generation = xboxGeneration;
        try
        {
            var found = await xbox.DiscoverAsync(token);
            post(() => { if (generation == xboxGeneration) RenameSelectedXbox(found); });
        }
        catch (Exception) { /* Ad tazelemesi isteğe bağlıdır; yayın kendi hatasını gösterir. */ }
    }
    public void SelectXboxConsole(XboxConsole selected)
    {
        if (!selected.StreamingEnabled) return;
        xboxConsole = selected;
        store.Save(StoreKeys.XboxConsole, selected);
        Changed(nameof(SelectedXboxConsole), nameof(CanAdvance), nameof(CanStart), nameof(Ps5StatusText));
    }
    public bool HasAccount => accountId is not null;
    public RegisteredConsole? Console => console;
    public LgTv? Tv => tv;
    public bool IsRunning { get => isRunning; private set => Set(ref isRunning, value, [nameof(Ps5StatusText), nameof(Ps5Tone), nameof(TvTone), nameof(ShowsCardPlayer), nameof(ShowsMainAccountTip)]); }
    public bool IsStarting { get => isStarting; private set => Set(ref isStarting, value); }
    public SessionState SessionState { get => sessionState; private set => Set(ref sessionState, value, [nameof(Ps5StatusText), nameof(Ps5Tone)]); }
    /// <summary>
    /// Görüntü kaynağının durumu. Nino'nun kaynakları (oyun penceresi, yakalama kartı) önce gelir; seçili değilse
    /// CouchSubs'ın kaynakları (Xbox yayını, Remote Play penceresi, seçilen pencere, PS5).
    /// </summary>
    public string Ps5StatusText => UsesGameWindow ? WindowStatusText : UsesCaptureCard ? CardStatusText
        : IsXbox ? XboxStatusText()
        : settings.FrameSource == FrameSource.RemotePlayWindow
            ? RemotePlayWindowStatusText(sessionState, isRunning, text, installed: !RemotePlayMissing)
            : settings.FrameSource == FrameSource.CaptureWindow
                ? CaptureWindowStatusText(sessionState, isRunning, text, settings.CaptureWindow)
                : StatusText(sessionState, isRunning, text, console is null ? null : string.IsNullOrEmpty(console.Name) ? "PS5" : console.Name);
    private string XboxStatusText() => sessionState.Phase switch
    {
        SessionPhase.Streaming => text["Connected"],
        SessionPhase.Connecting => text["Connecting…"],
        _ when !isRunning => xboxConsole is null ? text["Not connected"] : text.Format("%@ is ready. It connects when you start translating.", xboxConsole.Name),
        // Denemeler bitti ya da konsol yayını reddetti: oturum durdu, yeniden denenmiyor.
        _ when sessionState.Reason is { Kind: DisconnectKind.Refused, Detail.Length: > 0 } stopped => stopped.Detail,
        _ when !string.IsNullOrWhiteSpace(sessionState.Reason?.Detail) => text.Format("Retrying the Xbox connection: %@", sessionState.Reason.Detail),
        _ => text["Retrying the Xbox connection…"],
    };
    /// <summary>Nino: kart bağlı ama görüntü siyahsa (HDCP) nokta yeşil değil, sarıdır.</summary>
    public StatusTone Ps5Tone => UsesCaptureCard && cardStatus.State == CaptureCardState.BlackPicture ? StatusTone.Warning : Ps5ToneFor(sessionState, isRunning);
    public int TvClients { get => tvClients; private set => Set(ref tvClients, value, [nameof(TvTone), nameof(TvStatusText)]); }
    public StatusTone TvTone => HasTv ? TvToneFor(tvClients, isRunning) : StatusTone.Idle;
    public string TvStatusText => !HasTv ? text["Not set up"] : tvClients > 0 ? text["Connected"] : text["Waiting for the TV app"];
    /// <summary>Eşleşmiş bir TV var.</summary>
    public bool HasTv => tv is not null && store.Load<string>(StoreKeys.TvKey) is not null;
    /// <summary>Ana ekranda TV durumu gösterilir mi (altyazı yalnız bilgisayar ekranındaysa gösterilmez).</summary>
    public bool ShowsOnTv => (!UsesGameWindow || UsesXboxWindow) && settings.Output.ShowsOnTv();
    /// <summary>Oyun bu bilgisayardaki Remote Play penceresindeyse altyazı her zaman o pencerenin üstündedir.</summary>
    public bool ShowsOnComputer => (UsesGameWindow && !UsesXboxWindow) || settings.Output.ShowsOnComputer();
    /// <summary>
    /// Nino: görüntü bu bilgisayardaki Xbox yayın penceresinden okunuyor. Oyun çoğu zaman TV'de oynanır; pencere yalnız
    /// görüntünün kaynağıdır, altyazı seçilen yere (TV ya da bu bilgisayar) gider.
    /// </summary>
    public bool UsesXboxWindow => UsesGameWindow && settings.GameConsole == GameConsole.Xbox;
    /// <summary>Nino: görüntü bu bilgisayardaki oyun penceresinden okunuyor (PS5 eşleştirmesi gerekmez).</summary>
    public bool UsesGameWindow => settings.VideoSource == VideoSource.Window;
    /// <summary>
    /// Nino: görüntü bu bilgisayara takılı yakalama kartından okunuyor (PS5 eşleştirmesi gerekmez). Altyazı TV'ye de
    /// (PS5 → kart → TV, geçişli kart) bilgisayar ekranına da (PS5 → kart → bilgisayar → ekran) gidebilir.
    /// </summary>
    public bool UsesCaptureCard => settings.VideoSource == VideoSource.Card;
    /// <summary>Kartın durumu (yalnız <see cref="UsesCaptureCard"/> iken anlamlı).</summary>
    public CaptureCardStatus CardStatus { get => cardStatus; private set => Set(ref cardStatus, value, [nameof(Ps5StatusText), nameof(CardStatusText), nameof(Ps5Tone)]); }
    public string CardStatusText => CardStatusTextFor(cardStatus, text);
    /// <summary>Oyun bu bilgisayarda tam ekran gösteriliyor (yakalama kartı, altyazı bilgisayarda, çeviri sürüyor).</summary>
    public bool ShowsCardPlayer => isRunning && UsesCaptureCard && ShowsOnComputer;
    /// <summary>Kurulum sihirbazında yakalama kartı rehberi açık (PS5 adımlarının yerine).</summary>
    public bool CardSetupActive { get => cardSetupActive; private set => Set(ref cardSetupActive, value); }
    /// <summary>Kullanıcının seçtiği yakalama aygıtı (null: kendiliğinden seçilir). Bu bilgisayara özgüdür.</summary>
    public string? PreferredCardId
    {
        get => store.Load<string>(StoreKeys.CaptureCardId);
        set
        {
            if (value == PreferredCardId) return;
            if (value is null) store.Remove(StoreKeys.CaptureCardId);
            else store.Save(StoreKeys.CaptureCardId, value);
            Changed(nameof(PreferredCardId));
        }
    }
    private CaptureCardStatus cardStatus = CaptureCardStatus.Stopped;
    private bool cardSetupActive;

    public static string CardStatusTextFor(CaptureCardStatus status, Localizer text) => status.State switch
    {
        CaptureCardState.NeedsPermission => text["Allow camera access in Windows Settings › Privacy & security › Camera, then try again."],
        CaptureCardState.NoCard => text["Plug in your capture card"],
        CaptureCardState.BlackPicture => text["The picture is black. Turn the PS5 on, or turn off Settings › System › HDMI › Enable HDCP on the PS5."],
        CaptureCardState.Capturing => text.Format("Reading %@", status.Name ?? text["Capture card"]),
        _ => text["Reads the capture card"],
    };

    /// <summary>Oyun penceresinin durumu (yalnız <see cref="UsesGameWindow"/> iken anlamlı).</summary>
    public GameWindowStatus WindowStatus { get => windowStatus; private set => Set(ref windowStatus, value, [nameof(Ps5StatusText), nameof(WindowStatusText)]); }
    /// <summary>Okunan uygulamanın adı (PS Remote Play, chiaki-ng).</summary>
    public string? WindowApp { get => windowApp; private set => Set(ref windowApp, value, [nameof(Ps5StatusText), nameof(WindowStatusText)]); }
    /// <summary>Oyun alanının ekrandaki yeri (ekran pikseliyle); altyazı penceresi buna oturur.</summary>
    public ScreenArea? GameArea { get => gameArea; private set => Set(ref gameArea, value); }
    public string WindowStatusText => WindowStatusTextFor(windowStatus, windowApp, isRunning, text, settings.GameConsole);
    private GameWindowStatus windowStatus = GameWindowStatus.Stopped;
    private string? windowApp;
    private ScreenArea? gameArea;

    public static string WindowStatusTextFor(GameWindowStatus status, string? app, bool running, Localizer text,
                                             GameConsole console = GameConsole.Ps5) => console == GameConsole.Xbox ? status switch
    {
        // Nino: Xbox yayın penceresi (Xbox uygulaması, Greenlight ya da xbox.com/play).
        GameWindowStatus.Capturing => text.Format("Reading %@", app ?? "Xbox"),
        GameWindowStatus.LookingForWindow => text["Start Remote play in the Xbox app, Greenlight or xbox.com/play"],
        _ => running ? text["Start Remote play in the Xbox app, Greenlight or xbox.com/play"] : text["Reads the Xbox stream window"],
    } : status switch
    {
        GameWindowStatus.Capturing => text.Format("Reading %@", app ?? "PS Remote Play"),
        GameWindowStatus.LookingForWindow => text["Open PS Remote Play or chiaki-ng and start playing"],
        _ => running ? text["Open PS Remote Play or chiaki-ng and start playing"] : text["Reads the PS Remote Play window"],
    };
    /// <summary>Altyazı TV'ye de gidecek ama TV eşleşmedi: ana ekranda "TV bağla" düğmesi çıkar.</summary>
    public bool NeedsTv => ShowsOnTv && !HasTv;
    /// <summary>Çeviri başlatılabilir mi: PS5 kurulu ve altyazının gideceği bir yer var (TV eşleşmiş ya da bilgisayar ekranı seçili).</summary>
    /// <summary>
    /// Görüntü kaynağı hazır ve altyazının gideceği bir yer var. Nino: PS5 oyun penceresinde altyazı her zaman o
    /// pencerenin üstündedir; Xbox penceresi ve yakalama kartı için de PS5 eşleştirmesi gerekmez.
    /// </summary>
    public bool CanStart => (UsesGameWindow && !UsesXboxWindow)
        || ((UsesGameWindow || UsesCaptureCard
             || (IsXbox ? xboxToken is not null && xboxConsole is not null
                 : settings.FrameSource == FrameSource.RemotePlayWindow
                   || settings.FrameSource == FrameSource.CaptureWindow && settings.CaptureWindow is
                      { ProcessName.Length: > 0, Title.Length: > 0 }
                   || settings.FrameSource == FrameSource.Ps5 && console is not null && accountId is not null))
            && (ShowsOnComputer || HasTv));
    public string LastSource { get => lastSource; private set => Set(ref lastSource, value); }
    public string LastTranslation { get => lastTranslation; private set => Set(ref lastTranslation, value, [nameof(ShowsMainAccountTip)]); }
    /// <summary>PS5'ten (ikinci hesap) çeviri başladı, ilk altyazı gelmedi: "kolu açınca ana hesabı seçin" ipucu görünür (GitHub #231).</summary>
    public bool ShowsMainAccountTip => isRunning && !IsXbox && settings.VideoSource == VideoSource.Ps5 && settings.FrameSource == FrameSource.Ps5 && lastTranslation.Length == 0;
    /// <summary>TV'ye giden son satırın ölçümleri tek satırda ("OCR 40 ms · Çeviri 300 ms · Gecikme 520 ms"); satır gelene kadar boş.</summary>
    public string MetricsText { get => metricsText; private set => Set(ref metricsText, value); }
    /// <summary>Çevrilen satırlar, en yenisi başta (bu ve önceki oturumlar). Değişince bu özellik bildirilir.</summary>
    public IReadOnlyList<SubtitleHistory.Entry> History => [.. history.Entries];
    public TranslatorStatus TranslatorStatus { get => translatorStatus; private set => Set(ref translatorStatus, value); }
    private bool gpuFallbackWarning;
    /// <summary>CUDA kullanılamadığı için ücretsiz çeviri CPU'da çalışıyor.</summary>
    public bool GpuFallbackWarning { get => gpuFallbackWarning; private set => Set(ref gpuFallbackWarning, value); }
    /// <summary>Çevrimiçi çeviri (DeepL ya da yapay zekâ) şu an çeviremiyor; o satırlar cihaz üstü modelle çevriliyor.</summary>
    public OnlineKeyState? OnlineIssue { get => onlineIssue; private set => Set(ref onlineIssue, value); }
    /// <summary>Bilgisayarda yazı tanıma dili yok; ayarlardan eklenmesi gerekir.</summary>
    public bool OcrMissing { get => ocrMissing; private set => Set(ref ocrMissing, value); }
    /// <summary>Canlı altyazı çevirisi duraklatıldı (Num 0); ek bölge ve serbest alan çevirileri çalışmaya devam eder.</summary>
    public bool SubtitlesPaused { get => subtitlesPaused; private set => Set(ref subtitlesPaused, value); }
    public Frame? LastFrame { get => lastFrame; private set => Set(ref lastFrame, value); }
    public string? ActiveSourceLanguage { get; private set; }
    /// <summary>Sunucunun gerçekten dinlediği port (8787 doluysa rastgele bir port).</summary>
    public int ServerPort { get; private set; } = DefaultServerPort;

    /// <summary>Bu oyun dilinden hedef dile çeviri modeli var mı (ayarlarda listelenecek diller).</summary>
    public bool SupportsLanguage(string source) => services.Translation.IsSupported(source, settings.TargetLanguage);

    /// <summary>
    /// Ücretsiz model kurulu mu. Nino: ücretsiz modeli olmayan dilde (Tayca, Urduca…) indirilecek bir şey yoktur, kurulu
    /// sayılır; kurulum takılmaz, çeviriyi yapay zekâ motoru yapar (ana ekran bunu söyler).
    /// </summary>
    public bool ModelInstalled => !HasFreeModel || services.Translation.IsInstalled(settings.SourceLanguage, settings.TargetLanguage);

    /// <summary>Nino: seçili dilin ücretsiz (cihaz üstü) modeli var mı.</summary>
    public bool HasFreeModel => services.Translation.IsSupported(settings.SourceLanguage, settings.TargetLanguage);
    public bool ModelDownloading { get => modelDownloading; private set => Set(ref modelDownloading, value); }
    public double ModelProgress { get => modelProgress; private set => Set(ref modelProgress, value); }
    public string? ModelError { get => modelError; private set => Set(ref modelError, value); }

    public UserSettings Settings
    {
        get => settings;
        set
        {
            value = value with { CpuTranslationThreads = CpuThreadOptions.Normalize(value.CpuTranslationThreads, Environment.ProcessorCount) };
            var old = settings;
            // Nino: iki görüntü kaynağı seçimi tek seçim gibi davranır. Nino'nun kaynağı (oyun penceresi, yakalama kartı) önce
            // gelir; kullanıcı CouchSubs'tan gelen Remote Play penceresini ya da OBS projektörünü seçince Nino'nunki bırakılır
            // (yoksa kart seçiliyken OBS projektörü hiç okunmazdı). Nino'nun kaynağı seçilince de öbürü PS5'e döner.
            if (old.FrameSource != value.FrameSource && value.FrameSource != FrameSource.Ps5 && value.VideoSource != VideoSource.Ps5)
                value = value with { VideoSource = VideoSource.Ps5 };
            else if (old.VideoSource != value.VideoSource && value.VideoSource != VideoSource.Ps5 && value.FrameSource != FrameSource.Ps5)
                value = value with { FrameSource = FrameSource.Ps5 };
            // Nino: PS5 yoluna dönülünce altyazı TV'ye gider (PS5'te yer seçimi gösterilmez); pencere ya da OBS okunuyorsa değil.
            if (old.VideoSource != value.VideoSource && value.VideoSource == VideoSource.Ps5 && value.FrameSource == FrameSource.Ps5
                && value.Output != SubtitleOutput.Tv)
                value = value with { Output = SubtitleOutput.Tv };
            if (!Set(ref settings, value, [nameof(UsesFreeGemini)])) return;
            settingsStore.Save(value);
            server.SendStyle(value.Style);
            if (old.Output != value.Output) OutputChanged();
            // Nino: yakalama kartında altyazının yeri oyunun bu bilgisayarda gösterilip gösterilmeyeceğini de belirler.
            if (old.Output != value.Output && old.VideoSource == value.VideoSource && UsesCaptureCard && isRunning)
            {
                Stop();
                _ = StartAsync();
            }
            if (old.VideoSource != value.VideoSource) VideoSourceChanged();
            if (old.Dubbing != value.Dubbing) DubbingSettingsChanged(old.Dubbing);
            // Nino: çeviri dili Türkçe dışına geçince açık dublaj durur.
            if (old.TargetLanguage != value.TargetLanguage && !DubbingActive) StopDubber();
            // Nino: havuz o dilin çevirilerini yükler (hat yeniden kurulmadan önce).
            if (old.TargetLanguage != value.TargetLanguage) services.Translations?.SetLanguage(value.TargetLanguage);
            if (old.GamePacks != value.GamePacks && pipeline is not null) ConnectPacks(pipeline);
            if (pipeline is not null) pipeline.ShowSpeakerNames = value.ShowSpeakerNames;
            if ((old.MisreadWaitMs != value.MisreadWaitMs || old.PartialWaitMs != value.PartialWaitMs) && pipeline is not null) ApplyWaits(pipeline);
            if (old.SharePool != value.SharePool)
            {
                services.Pool?.SetEnabled(value.SharePool);
                services.Translations?.SetEnabled(value.SharePool);
                if (pipeline is not null)
                {
                    ConnectPacks(pipeline);
                    StartTranslationSync();
                }
            }
            if (old.TranslationDevice != value.TranslationDevice)
            {
                GpuFallbackWarning = false;
                services.Translation.SelectDevice(value.TranslationDevice);
            }
            if (old.CpuTranslationThreads != value.CpuTranslationThreads)
                services.Translation.SelectCpuThreads(value.CpuTranslationThreads);
            UpdateRegionWatcher();
            if (old.FrameSource != value.FrameSource || old.CaptureWindow != value.CaptureWindow)
                Changed(nameof(CanStart), nameof(Ps5StatusText), nameof(ConsoleTitle));
            var windowAppChanged = value.FrameSource == FrameSource.RemotePlayWindow && old.RemotePlayApp != value.RemotePlayApp;
            var captureWindowChanged = value.FrameSource == FrameSource.CaptureWindow && old.CaptureWindow != value.CaptureWindow;
            var xboxFrameRateChanged = IsXbox && old.XboxLegacyFrameRate != value.XboxLegacyFrameRate;
            if (isRunning && (old.FrameSource != value.FrameSource || windowAppChanged || captureWindowChanged || xboxFrameRateChanged))
            {
                // Görüntü kaynağı ya da Xbox kare aralığı değişti: akış yeni seçimle yeniden başlar.
                Stop();
                _ = StartAsync().ContinueWith(task => RemotePlayLog.Note($"Çeviri yeniden başlatılamadı: {task.Exception?.GetBaseException().Message}"),
                                              TaskContinuationOptions.OnlyOnFaulted);
            }
            var translationChanged = old.OnlineTranslation != value.OnlineTranslation || old.OnlineEngine != value.OnlineEngine
                                     || old.GeminiModel != value.GeminiModel || old.OpenAiModel != value.OpenAiModel
                                     || old.ClaudeModel != value.ClaudeModel
                                     || old.LocalAiBaseUrl != value.LocalAiBaseUrl || old.LocalAiModel != value.LocalAiModel
                                     || old.TranslationDevice != value.TranslationDevice
                                     || old.CpuTranslationThreads != value.CpuTranslationThreads;
            // Nino: dil değişince ücretsiz modelin durumu da değişir (ör. Taycanın modeli yok, Hintçenin indirilmemiş).
            var languageChanged = old.SourceLanguage != value.SourceLanguage || old.TargetLanguage != value.TargetLanguage;
            if (languageChanged) Changed(nameof(ModelInstalled), nameof(HasFreeModel), nameof(CanAdvance));
            if ((translationChanged || languageChanged) && !isRunning) RefreshTranslatorStatus();
            if (isRunning && (languageChanged || translationChanged || old.FastSubtitleDetection != value.FastSubtitleDetection))
            {
                RefreshTranslatorStatus();
                MakePipeline();
            }
        }
    }

    // --- Sihirbaz ---

    public bool CanAdvance => step switch
    {
        OnboardingStep.Welcome or OnboardingStep.SecondAccount or OnboardingStep.Test or OnboardingStep.BetterTranslation => true,
        OnboardingStep.PsnLogin => IsXbox ? xboxToken is not null : accountId is not null,
        OnboardingStep.Console => IsXbox ? xboxConsole is not null : console is not null,
        OnboardingStep.Tv => HasTv || settings.Output == SubtitleOutput.Computer,
        OnboardingStep.Translation => ModelInstalled,
        _ => false,
    };

    public void Advance()
    {
        if (!CanAdvance || step == OnboardingStep.Done) return;
        // Model büyük; kullanıcı diğer adımlarla uğraşırken arka planda iner.
        if (step == OnboardingStep.Welcome)
        {
            StartModelDownload();
            consoleKindLocked = true;
            store.Save(StoreKeys.ConsoleKindLocked, true);
            Changed(nameof(ConsoleKindLocked));
            // Nino: karşılamadan "Devam" PS5 (ya da Xbox yayını) yoludur; önceden seçilmiş pencere ya da kart kaynağı bırakılır.
            if (settings.VideoSource != VideoSource.Ps5) Settings = settings with { VideoSource = VideoSource.Ps5 };
        }
        Step = step == OnboardingStep.Welcome && IsXbox ? OnboardingStep.PsnLogin : step + 1;
    }

    public void Back()
    {
        // Nino: kısa yoldan gelen (PS5 ve TV adımları atlanmış) kullanıcı geri dönünce karşılamaya döner.
        if (UsesGameWindow && !UsesXboxWindow && step == OnboardingStep.Translation) Step = OnboardingStep.Welcome;
        // Nino: Xbox kısa yolundan gelen PS5 adımlarına düşmez.
        else if (UsesXboxWindow && step == OnboardingStep.Tv) Step = OnboardingStep.Welcome;
        // Nino: kart rehberinden gelen PS5 adımlarına düşmez; rehbere döner.
        else if (UsesCaptureCard && (step == OnboardingStep.Tv || (step == OnboardingStep.Test && !ShowsOnTv)))
        {
            Step = OnboardingStep.Welcome;
            CardSetupActive = true;
        }
        else if (step > OnboardingStep.Welcome) Step = step == OnboardingStep.PsnLogin && IsXbox ? OnboardingStep.Welcome : step - 1;
    }

    /// <summary>Ücretsiz Gemini anahtarı kayıtlı ve çeviri Gemini ile yapılıyor ("Daha iyi çeviri" adımı tamam).</summary>
    public bool UsesFreeGemini => settings.Engine == TranslationEngine.Gemini && HasKey(TranslationEngine.Gemini);

    /// <summary>Ayarlardaki "Ücretsiz anahtar al": Gemini seçilir, anahtar alanı görünür (anahtar gelene dek ücretsiz çeviri sürer).</summary>
    public void ChooseFreeGemini() => Settings = settings.WithEngine(TranslationEngine.Gemini);

    /// <summary>Giriş penceresinin yönlendirmesinden hesap kimliği. Her başarısızlık kendi iletisiyle
    /// <see cref="AppException"/> olur ve günlüğe yazılır; genel "Giriş tamamlanmadı" yalnız son çaredir.</summary>
    public async Task CompletePsnLoginAsync(Uri redirect)
    {
        byte[] id;
        try
        {
            id = await services.AccountIdFromRedirectAsync(redirect);
        }
        catch (PsnAccountException error)
        {
            RemotePlayLog.Note($"PSN girişi başarısız: {error.Failure} HTTP {error.StatusCode?.ToString() ?? "-"} {error.Detail}");
            throw LoginError(error);
        }
        catch (Exception error) when (error is not AppException)
        {
            RemotePlayLog.Note($"PSN girişi beklenmedik hatayla bitti: {error}");
            throw new AppException(AppError.InvalidLogin, WithLogHint($"{AppException.Describe(AppError.InvalidLogin, text)} ({error.Message})"));
        }
        RemotePlayLog.Note("PSN girişi tamam");
        accountId = id;
        store.Save(StoreKeys.AccountId, id);
        Changed(nameof(HasAccount), nameof(CanAdvance));
    }

    /// <summary>Sony'nin giriş sayfası sistem tarayıcısında açılır. Uygulama içi pencerede Sony "Can't connect to the
    /// server" derse giriş bu yoldan yapılır; kullanıcı yönlendirme adresini kopyalayıp <see cref="CompletePsnLoginAsync"/>'e verir.</summary>
    public void OpenPsnLoginInBrowser()
    {
        RemotePlayLog.Note("PSN girişi tarayıcıda açılıyor");
        OpenInBrowser(PsnAccount.AuthorizeUrl);
    }

    public Task<IReadOnlyList<ConsoleInfo>> DiscoverConsolesAsync() => services.DiscoverConsolesAsync();

    /// <summary>PS5'e kayıt olur. Her başarısızlık <see cref="AppException"/> ile anlatılır; sessiz dönüş yok.</summary>
    public async Task RegisterAsync(string host, string pin)
    {
        host = host.Trim();
        if (host.Length == 0) throw Error(AppError.MissingConsole);
        if (Registration.ParsePin(pin) is not { } value) throw Error(AppError.InvalidPin);
        if (accountId is null) throw Error(AppError.MissingAccount);
        RegisteredConsole registered;
        try
        {
            registered = await services.RegisterAsync(host, accountId, value);
        }
        catch (RegistrationException error)
        {
            // PS5 kendi kodunu bildirdiyse yanıt bize ulaşmıştır, güvenlik duvarı sebep değildir.
            if (error.Reason is null && error.Failure is not (RegistrationFailure.WrongAccount or RegistrationFailure.BadAddress))
                await OfferFirewallAsync();
            throw RegistrationError(error);
        }
        catch (Exception error) when (error is not AppException)
        {
            // Beklenmedik hata da (ör. yerel kütüphane yüklenemedi) iletiye dönüşür ve günlüğe yazılır.
            RemotePlayLog.Note($"PS5 kaydı beklenmedik hatayla bitti ({host}): {error}");
            await OfferFirewallAsync();
            throw new AppException(AppError.RegistrationFailed, WithLogHint($"{AppException.Describe(AppError.RegistrationFailed, text)} ({error.Message})"));
        }
        ClearFirewallPrompt();
        console = registered;
        store.Save(StoreKeys.Console, registered);
        // Günlükte eşleşmenin kaydedildiği de görünsün (kullanıcılar başarıyı fark etmeyip yeniden bağlanıyordu).
        RemotePlayLog.Note($"PS5 kaydı kaydedildi ({registered.Host}): {registered.Name}");
        Changed(nameof(Console), nameof(CanAdvance), nameof(Ps5StatusText), nameof(PairedText));
    }

    /// <summary>PS5 adımında, eşleşme bitince Bağlan düğmesinin altında gösterilen başarı iletisi; eşleşme yoksa boş.</summary>
    public string PairedText => console is null
        ? ""
        : text.Format("PS5 paired: %@ (%@). Press Continue.", string.IsNullOrEmpty(console.Name) ? "PS5" : console.Name, console.Host);

    /// <summary>
    /// Eşleşmeden kısa süre sonra kendiliğinden sonraki adıma geçilir. Kullanıcı bu arada Geri'ye bastıysa ya da
    /// adım değiştiyse hiçbir şey yapılmaz (yalnız PS5 adımından ilerler).
    /// </summary>
    public void ContinueAfterPairing()
    {
        if (step == OnboardingStep.Console && console is not null) Advance();
    }

    /// <summary>
    /// "Hesap kimliğini elle gir": Sony girişi açılamayan kullanıcılar (ör. servis sağlayıcı engelliyor) PSN hesap
    /// kimliğini base64 olarak (8 bayt, 12 karakter) yazar. Web girişiyle aynı biçimde saklanır. Geçersizse false.
    /// </summary>
    public bool UseManualAccountId(string value)
    {
        if (ParseAccountId(value) is not { } id) return false;
        RemotePlayLog.Note("PSN hesap kimliği elle girildi");
        accountId = id;
        store.Save(StoreKeys.AccountId, id);
        Changed(nameof(HasAccount), nameof(CanAdvance));
        return true;
    }

    /// <summary>Base64 PSN hesap kimliği: boşluklar atılır, çözülen değer tam 8 bayt olmalı (12 karakter).</summary>
    public static byte[]? ParseAccountId(string? value)
    {
        var trimmed = string.Concat((value ?? "").Where(c => !char.IsWhiteSpace(c)));
        if (trimmed.Length != 12) return null;
        try
        {
            var bytes = Convert.FromBase64String(trimmed);
            return bytes.Length == 8 ? bytes : null;
        }
        catch (FormatException)
        {
            return null;
        }
    }

    /// <summary>Kullanıcıya gösterilen hata; destek bildirimleri teşhis edilebilsin diye PS5'in kodu da yazılır.</summary>
    private AppException RegistrationError(RegistrationException error)
    {
        var kind = error.Failure switch
        {
            RegistrationFailure.WrongAccount => AppError.WrongAccount,
            RegistrationFailure.NoAnswer => AppError.ConsoleNoAnswer,
            RegistrationFailure.InUse => AppError.ConsoleInUse,
            RegistrationFailure.ConsoleCrashed => AppError.ConsoleCrashed,
            RegistrationFailure.VersionMismatch => AppError.ConsoleVersion,
            RegistrationFailure.WrongCode => AppError.WrongCode,
            // İptal yalnız cs_register'ın süresi dolunca olur: PS5 yanıt vermemiştir.
            RegistrationFailure.NoReply or RegistrationFailure.Canceled => AppError.ConsoleNoReply,
            RegistrationFailure.BadAddress => AppError.BadAddress,
            _ => AppError.RegistrationFailed,
        };
        var message = AppException.Describe(kind, text);
        return new AppException(kind, WithLogHint(string.IsNullOrEmpty(error.Detail) ? message : $"{message} ({error.Detail})"));
    }

    /// <summary>PSN girişinin hatası: Sony'nin bildirdiği hata ya da HTTP kodu iletiye eklenir.</summary>
    private AppException LoginError(PsnAccountException error)
    {
        var kind = error.Failure switch
        {
            PsnLoginFailure.Refused => AppError.LoginRefused,
            PsnLoginFailure.RateLimited => AppError.LoginRateLimited,
            PsnLoginFailure.Http => AppError.LoginServer,
            PsnLoginFailure.Network => AppError.LoginNetwork,
            PsnLoginFailure.BadResponse => AppError.LoginBadResponse,
            _ => AppError.InvalidLogin,
        };
        var message = AppException.Describe(kind, text);
        var detail = string.Join(", ", new[] { error.StatusCode is { } status ? $"HTTP {status}" : null, error.Detail }.Where(part => !string.IsNullOrEmpty(part)));
        return new AppException(kind, WithLogHint(detail.Length == 0 ? message : $"{message} ({detail})"));
    }

    /// <summary>Giriş penceresi yönlendirme olmadan kapandı (kullanıcı kapattı ya da sayfa açılamadı).</summary>
    /// <param name="problem">Pencerenin gördüğü sorun (ör. "HTTP 429", WebView2 hatası); yoksa null.</param>
    public AppException LoginWindowError(string? problem)
    {
        RemotePlayLog.Note($"PSN giriş penceresi giriş bitmeden kapandı{(problem is null ? "" : $": {problem}")}");
        if (problem is null) return Error(AppError.LoginWindowClosed);
        var kind = problem.Contains("429", StringComparison.Ordinal) ? AppError.LoginRateLimited : AppError.LoginPageFailed;
        return new AppException(kind, WithLogHint($"{AppException.Describe(kind, text)} ({problem})"));
    }

    /// <summary>Eşleştirme olmazsa kullanıcı remoteplay.log'u gönderebilsin diye yolu iletinin sonuna eklenir.</summary>
    private string WithLogHint(string message) =>
        $"{message} {text.Format("If this keeps happening, send us this file: %@", RemotePlayLog.DisplayPath)}";

    public Task<IReadOnlyList<LgTv>> DiscoverTvsAsync() => services.DiscoverTvsAsync();

    /// <summary>
    /// Sihirbazdaki "TV'm yok": TV aranmaz ve kurulmaz, altyazı bilgisayar ekranında gösterilir; sonraki adıma geçilir.
    /// </summary>
    /// <summary>
    /// Nino: sihirbazın ilk ekranındaki "Bu bilgisayarda PS Remote Play ile oynuyorum": ikinci hesap, PS5 eşleştirmesi ve
    /// TV adımları atlanır; çeviri modeli adımından sürer. Görüntü Remote Play penceresinden okunur.
    /// </summary>
    public void UseGameWindowSetup()
    {
        Settings = settings with { VideoSource = VideoSource.Window, GameConsole = GameConsole.Ps5, Output = SubtitleOutput.Computer };
        Step = OnboardingStep.Translation;
        StartModelDownload();
    }

    /// <summary>
    /// Nino: sihirbazın ilk ekranındaki "Xbox'ta oynuyorum": Xbox bu bilgisayarda Xbox uygulamasının "Uzaktan oynat"ı,
    /// Greenlight ya da xbox.com/play ile açılır; Nino o pencereyi okur. İkinci hesap ve PS5 adımları atlanır; altyazı TV'de
    /// gösterilecekse TV eşleştirilir ("TV'm yok" seçilirse bu bilgisayarda, pencerenin üstünde).
    /// </summary>
    public void UseXboxWindowSetup()
    {
        Settings = settings with { VideoSource = VideoSource.Window, GameConsole = GameConsole.Xbox, Output = SubtitleOutput.Tv };
        Step = OnboardingStep.Tv;
        StartModelDownload();
    }

    /// <summary>
    /// Nino: sihirbazın ilk ekranındaki "Yakalama kartım var": ikinci hesap ve PS5 eşleştirmesi yerine kart rehberi açılır.
    /// Çeviri modeli bu arada arka planda iner.
    /// </summary>
    public void UseCaptureCardSetup()
    {
        CardSetupActive = true;
        StartModelDownload();
    }

    /// <summary>Kart rehberinden karşılamaya dönülür.</summary>
    public void CancelCaptureCardSetup() => CardSetupActive = false;

    /// <summary>
    /// Kart rehberi bitti. TV seçildiyse TV eşleşmemişse TV adımına, değilse denemeye; bilgisayar seçildiyse doğrudan
    /// denemeye geçilir (model inmemişse önce model adımı). Ayarlardan açılan rehberde yalnız seçim kaydedilir.
    /// </summary>
    public void FinishCaptureCardSetup(bool toTv)
    {
        Settings = settings with { VideoSource = VideoSource.Card, Output = toTv ? SubtitleOutput.Tv : SubtitleOutput.Computer };
        if (!cardSetupActive) return;
        CardSetupActive = false;
        Step = toTv && !HasTv ? OnboardingStep.Tv : ModelInstalled ? OnboardingStep.Test : OnboardingStep.Translation;
    }

    /// <summary>Oyunu gösteren pencereyi tam ekrana alır ya da tam ekrandan çıkarır.</summary>
    public void ToggleCardFullScreen() => (session as ICaptureCardStream)?.ToggleFullScreen();

    public void UseComputerScreen()
    {
        Settings = settings with { Output = SubtitleOutput.Computer };
        Advance();
    }

    /// <summary>
    /// Sihirbazdaki "İkinci hesap yok mu?": görüntü bu bilgisayardaki Remote Play penceresinden okunur. PSN girişi, PS5
    /// eşleştirmesi ve TV adımı atlanır, kurulum biter; TV eşleşmemişse altyazı bilgisayar ekranında gösterilir (TV ve
    /// daha iyi çeviri sonra Ayarlar'dan).
    /// </summary>
    public void UseRemotePlayWindow()
    {
        Settings = settings with { FrameSource = FrameSource.RemotePlayWindow, Output = HasTv ? settings.Output : SubtitleOutput.Computer };
        Step = OnboardingStep.Done;
    }

    /// <summary>OBS veya oyun penceresi kullanıcı tarafından sonradan seçilir; PSN eşleştirmesine gerek yoktur.</summary>
    public void UseCaptureWindow()
    {
        Settings = settings with { FrameSource = FrameSource.CaptureWindow, Output = HasTv ? settings.Output : SubtitleOutput.Computer };
        Step = OnboardingStep.Done;
    }

    public IReadOnlyList<WindowCaptureTarget> AvailableCaptureWindows() => services.CaptureWindows();

    /// <summary>Görüntü PS5'ten (ikinci hesap) alınacak ama hesap ya da PS5 eşleşmesi yok: Ayarlar'da "Hesabı bağla" görünür.</summary>
    public bool NeedsPs5Link => settings.FrameSource == FrameSource.Ps5 && (accountId is null || console is null);

    /// <summary>Ayarlar › Görüntü kaynağı › "Hesabı bağla": sihirbaz ikinci hesap adımından açılır (PSN girişi, PS5 eşleştirmesi).</summary>
    public void LinkPs5Account() => Step = OnboardingStep.SecondAccount;

    /// <summary>Seçilen Remote Play uygulaması bu bilgisayarda kurulu mu (Ayarlar'daki "Kurulu" / "İndir" satırları).</summary>
    public bool RemotePlayInstalled(RemotePlayApp app) => services.RemotePlayInstalled(app);

    /// <summary>Görüntü Remote Play penceresinden okunacak ama seçilen uygulama kurulu değil: ana ekran nereden indirileceğini söyler.</summary>
    public bool RemotePlayMissing => settings.FrameSource == FrameSource.RemotePlayWindow && !services.RemotePlayInstalled(settings.RemotePlayApp);

    /// <summary>Resmi indirme sayfaları: Sony PS Remote Play ve chiaki-ng'nin son sürümü.</summary>
    public const string SonyRemotePlayDownload = "https://remoteplay.dl.playstation.net/remoteplay/";
    public const string ChiakiDownload = "https://github.com/chiaki-ng/chiaki-ng/releases/latest";

    public async Task PairAsync(LgTv target)
    {
        await StartServerAsync();
        var savedKey = store.Load<string>(StoreKeys.TvKey);
        var pairing = await services.PairTvAsync(target, savedKey, ServerAddress(target));
        if (tv?.Brand != target.Brand || (target.Brand != TvBrand.AndroidTv && tv?.Host != target.Host))
            store.Remove(StoreKeys.TvAppVersion);
        tv = target;
        store.Save(StoreKeys.Tv, target);
        // Samsung jetonla gelen bağlantıda jetonu yeniden göndermeyebilir; boş jeton saklı olanı silmez (#40).
        store.Save(StoreKeys.TvKey, SamsungTokenHolder.KeptToken(savedKey, pairing.Key));
        tvAppMissing = !pairing.Launched;
        // Daha önce "TV'm yok" seçildiyse TV bağlanınca altyazı TV'ye gider.
        if (settings.Output == SubtitleOutput.Computer) Settings = settings with { Output = SubtitleOutput.Tv };
        Changed(nameof(Tv), nameof(CanAdvance), nameof(CanInstallTvApp), nameof(HasTv), nameof(NeedsTv), nameof(CanStart),
            nameof(TvStatusText), nameof(TvTone));
        if (target.Brand == TvBrand.Lg) await RefreshTvAppAsync();
        // Samsung girişi ya da Android onayı dakikalar sürebilir; eşleşme beklemesin.
        else _ = RefreshTvAppAsync();
    }

    // --- TV uygulamasını kurma ---

    public TvAppState TvApp
    {
        get => tvApp;
        private set
        {
            tvApp = value;
            Changed(nameof(TvApp));
        }
    }

    /// <summary>LG geliştirici modunun kalan süresi (saat); CouchSubs uzattıktan sonra bilinir.</summary>
    public int? DevModeHoursLeft
    {
        get => devModeHoursLeft;
        private set
        {
            devModeHoursLeft = value;
            Changed(nameof(DevModeHoursLeft));
        }
    }

    /// <summary>Seçili TV'ye uygulamayı CouchSubs kurabilir mi (paket uygulamayla geldi mi)?</summary>
    public bool CanInstallTvApp => tv is { } target &&
        (target.Brand == TvBrand.Lg ? services.BundledTvAppVersion is not null : services.BundledApp(target.Brand) is not null);

    /// <summary>Samsung'un sertifika sayfasını tarayıcıda açar (arayüz atar; testlerde boş kalır).</summary>
    public Action<Uri> OpenInBrowser { get; set; } = _ => { };

    /// <summary>Samsung'da geliştirici modunda "Host PC IP" olarak yazılacak bu bilgisayarın adresi.</summary>
    public string? ComputerAddress => LocalAddress(tv is { Host.Length: > 0 } target ? target.Host : null);

    /// <summary>
    /// Geliştirici modu açık TV'de uygulamayı eksikse kurar, eskiyse günceller.
    /// Anahtar yoksa ve uygulama çalışıyorsa kullanıcıdan bir şey istenmez.
    /// </summary>
    public async Task RefreshTvAppAsync()
    {
        if (tv is not { } target || refreshingTvApp) return;
        refreshingTvApp = true;
        try
        {
            switch (target.Brand)
            {
                case TvBrand.Lg: await RefreshLgAppAsync(target); break;
                case TvBrand.Samsung: await RefreshSamsungAppAsync(target); break;
                case TvBrand.AndroidTv: await RefreshAndroidAppAsync(target); break;
            }
        }
        finally
        {
            refreshingTvApp = false;
        }
    }

    private string? InstalledAppVersion => store.Load<string>(StoreKeys.TvAppVersion);

    private bool NeedsInstall(BundledTvApp bundled) =>
        InstalledAppVersion is not { } installed || DevModeInstaller.IsNewer(bundled.Version, installed);

    private async Task RefreshLgAppAsync(LgTv target)
    {
        if (services.BundledTvAppVersion is not { } bundled) return;
        var devModeOn = await services.IsDevModeOnAsync(target.Host);
        // Beklerken parola alanından kurulum başladıysa kart geri "geliştirici modu kapalı"ya dönmez.
        if (TvApp.Kind == TvAppKind.Working) return;
        if (!devModeOn)
        {
            TvApp = tvAppMissing ? new TvAppState(TvAppKind.DevModeOff) : TvAppState.Unknown;
            return;
        }
        if (store.Load<string>(StoreKeys.TvDevKey) is not { } devKey)
        {
            TvApp = tvAppMissing ? new TvAppState(TvAppKind.NeedsPassphrase) : TvAppState.Unknown;
            return;
        }
        await InstallTvAppAsync(target, devKey, bundled);
    }

    /// <summary>
    /// Kurulum hatasında TV'nin verdiği sebep de gösterilir; genel mesaj tek başına sorunu bulmaya yetmiyordu. Samsung'da
    /// her hatanın ayrıntısı (Samsung'un yanıtı, sdb hatası, TV'nin kurulum çıktısı) gösterilir: hiçbiri sessiz kalmasın.
    /// </summary>
    private static TvAppState FailedState(DevModeException error, bool alwaysShowDetail = false) =>
        new(TvAppKind.Failed, Error: error.Error,
            Reason: (alwaysShowDetail || error.Error is DevModeError.InstallFailed or DevModeError.NotEnoughSpace) &&
                    !string.IsNullOrWhiteSpace(error.Detail)
                ? error.Detail.Trim() : null);

    /// <summary>Samsung kurulumu ya da sürüm denetimi sürüyor: olaylar (giriş, kurulum adımı) kartı değiştirebilir.</summary>
    private bool samsungCheckRunning;

    /// <summary>
    /// Samsung: geliştirici modu açıksa TV'deki CouchSubs sürümüne bakar, yoksa ya da eskiyse imzalayıp kurar
    /// (sertifika yoksa Samsung girişi istenir). Önceden yalnız bu bilgisayarın kurduğu sürüm hatırlanıyordu; TV'de eski
    /// kalan uygulama (ör. 0.9.10 gelirken 0.9.7) hiç güncellenmiyordu.
    /// </summary>
    private async Task RefreshSamsungAppAsync(LgTv target)
    {
        if (services.BundledApp(TvBrand.Samsung) is not { } bundled) return;
        var remembered = !NeedsInstall(bundled);
        // TV 8001'de geliştirici modunu ve Host PC IP'yi söyler (Android ve iPhone uygulaması da buna bakar). Host PC IP
        // bu bilgisayarınki değilse TV 26101'de sdb el sıkışmasında bağlantıyı keser ve önceden yalnız genel "TV bu
        // bilgisayarı kabul etmedi" görünüyordu (#343); bu durumda sdb hiç denenmez, iki adres de söylenir.
        var check = await services.CheckSamsungAsync(target.Host);
        var devModeOn = check.Info?.DeveloperMode != false && await services.IsSamsungDevModeOnAsync(target.Host);
        if (!devModeOn)
        {
            // Geliştirici modu kapalıyken TV'ye sorulamaz; bu bilgisayarın kurduğu sürüme bakılır.
            TvApp = remembered ? new TvAppState(TvAppKind.UpToDate, InstalledAppVersion ?? bundled.Version) : new TvAppState(TvAppKind.DevModeOff);
            return;
        }
        if (SamsungMessages.HostPcIpMismatch(check.Info?.DeveloperIp, check.ComputerAddress))
        {
            // Çalışan uygulama "kurulamadı" diye gösterilmez (Unreachable'daki gibi); güncelleme Host PC IP düzelince gelir.
            TvApp = remembered
                ? new TvAppState(TvAppKind.UpToDate, InstalledAppVersion ?? bundled.Version)
                : new TvAppState(TvAppKind.Failed, Error: DevModeError.HostPcMismatch, HostPcIp: check.Info!.DeveloperIp,
                    ComputerAddress: check.ComputerAddress);
            return;
        }
        // Güncel bilinen uygulamada denetim sessiz sürer; kart ancak kurulum başlarsa değişir.
        TvApp = remembered ? new TvAppState(TvAppKind.UpToDate, InstalledAppVersion ?? bundled.Version) : new TvAppState(TvAppKind.Working);
        samsungCheckRunning = true;
        try
        {
            var (version, installed) = await services.InstallSamsungAppAsync(target.Host, bundled, e => post(() => InstallEvent(e)));
            version = string.IsNullOrWhiteSpace(version) ? bundled.Version : version;
            store.Save(StoreKeys.TvAppVersion, version);
            TvApp = new TvAppState(TvAppKind.UpToDate, version);
            if (installed) await OpenTvAppAfterInstallAsync(target);
        }
        catch (DevModeException error) when (remembered && error.Error == DevModeError.Unreachable)
        {
            // TV sdb bağlantısını kabul etmedi (ör. Host PC IP değişti): çalışan uygulama "kurulamadı" diye gösterilmez.
            TvApp = new TvAppState(TvAppKind.UpToDate, InstalledAppVersion ?? bundled.Version);
        }
        catch (DevModeException error)
        {
            TvApp = FailedState(error, alwaysShowDetail: true);
        }
        finally
        {
            samsungCheckRunning = false;
        }
    }

    /// <summary>Kurulumun TV'yi değiştiren adımları (yalnız sürüm okumak değil).</summary>
    private static bool IsInstallStep(string? step) =>
        step is "signin" or "certificate" or "signing" or "installing" or "uninstalling";

    /// <summary>Android TV: ağda ADB'si açık TV'yi bulur, uygulamayı kurar ve açar.</summary>
    private async Task RefreshAndroidAppAsync(LgTv target)
    {
        if (services.BundledApp(TvBrand.AndroidTv) is not { } bundled) return;
        var host = target.Host;
        if (host.Length == 0 || !await services.IsAndroidDebugOnAsync(host))
        {
            // Uygulama kuruluysa ve TV'de hata ayıklama kapalıysa yapılacak bir şey yok.
            if (!NeedsInstall(bundled))
            {
                TvApp = new TvAppState(TvAppKind.UpToDate, InstalledAppVersion ?? bundled.Version);
                return;
            }
            if ((await services.ScanAndroidTvsAsync()).FirstOrDefault() is not { } found)
            {
                TvApp = new TvAppState(TvAppKind.DevModeOff);
                return;
            }
            host = found;
        }
        TvApp = new TvAppState(TvAppKind.Working);
        try
        {
            var version = await services.InstallAndroidAppAsync(host, bundled, e => post(() => InstallEvent(e)));
            // TV'nin adresi bundan sonra sürüm denetimi için kullanılır.
            var located = target with { Host = host };
            tv = located;
            store.Save(StoreKeys.Tv, located);
            store.Save(StoreKeys.TvAppVersion, version);
            Changed(nameof(Tv));
            TvApp = new TvAppState(TvAppKind.UpToDate, version);
        }
        catch (DevModeException error)
        {
            TvApp = FailedState(error);
        }
    }

    private void InstallEvent(TvInstallEvent e)
    {
        // Kurulum bittikten sonra gelen geç olay sonucu ezmesin.
        if (!samsungCheckRunning && TvApp.Kind is not (TvAppKind.Working or TvAppKind.SignIn or TvAppKind.ApproveOnTv)) return;
        switch (e.Kind)
        {
            case TvInstallEventKind.SignIn when e.Url is { } url:
                TvApp = new TvAppState(TvAppKind.SignIn, Url: url);
                OpenInBrowser(url);
                break;
            case TvInstallEventKind.ApproveOnTv:
                TvApp = new TvAppState(TvAppKind.ApproveOnTv);
                break;
            case TvInstallEventKind.Progress when TvApp.Kind == TvAppKind.SignIn:
                TvApp = new TvAppState(TvAppKind.Working);
                break;
            // Sürüm denetimi güncelleme kurmaya başladı: kart "kuruluyor"a geçer.
            case TvInstallEventKind.Progress when TvApp.Kind != TvAppKind.Working && IsInstallStep(e.Step):
                TvApp = new TvAppState(TvAppKind.Working);
                break;
        }
    }

    /// <summary>Key Server'dan anahtarı alır (TV ekranındaki parolayla) ve uygulamayı kurar.</summary>
    public async Task InstallTvAppAsync(string passphrase)
    {
        if (tv is not { } target || services.BundledTvAppVersion is not { } bundled) return;
        TvApp = new TvAppState(TvAppKind.Working);
        try
        {
            var devKey = await services.FetchDevKeyAsync(target.Host, passphrase.Trim());
            store.Save(StoreKeys.TvDevKey, devKey);
            await InstallTvAppAsync(target, devKey, bundled);
        }
        catch (DevModeException error)
        {
            TvApp = new TvAppState(TvAppKind.NeedsPassphrase, Error: error.Error);
        }
    }

    private async Task InstallTvAppAsync(LgTv target, string devKey, string bundled)
    {
        TvApp = new TvAppState(TvAppKind.Working);
        try
        {
            var installed = await services.InstalledTvAppVersionAsync(target.Host, devKey);
            if (installed is not null && !DevModeInstaller.IsNewer(bundled, installed))
            {
                TvApp = new TvAppState(TvAppKind.UpToDate, installed);
                await RenewDevSessionIfDueAsync(target, devKey);
                return;
            }
            await services.InstallTvAppAsync(target.Host, devKey);
            TvApp = new TvAppState(TvAppKind.UpToDate, bundled);
            tvAppMissing = false;
            await RenewDevSessionIfDueAsync(target, devKey);
            await OpenTvAppAfterInstallAsync(target);
        }
        catch (DevModeException error) when (error.Error == DevModeError.KeyRefused)
        {
            // Geliştirici modu yeniden açılınca TV yeni anahtar üretir; eskisi işe yaramaz.
            store.Remove(StoreKeys.TvDevKey);
            TvApp = new TvAppState(TvAppKind.NeedsPassphrase);
        }
        catch (DevModeException error)
        {
            TvApp = FailedState(error);
        }
    }

    /// <summary>
    /// LG geliştirici modunun 1000 saatlik süresini günde en çok bir kez baştan başlatır; kullanıcı TV'den uzatmak
    /// zorunda kalmaz.
    /// </summary>
    private async Task RenewDevSessionIfDueAsync(LgTv target, string devKey)
    {
        // Süre TV başına tutulur: ikinci TV'nin uzatması birincinin kaydıyla atlanmaz.
        var key = StoreKeys.DevSessionRenewedFor(target.Host);
        var last = store.Load<DateTimeOffset?>(key) ?? DateTimeOffset.MinValue;
        if (DateTimeOffset.UtcNow - last < TimeSpan.FromHours(20)) return;
        if (await services.RenewDevSessionAsync(target.Host, devKey) is { } hours)
        {
            DevModeHoursLeft = hours;
            store.Save(key, (DateTimeOffset?)DateTimeOffset.UtcNow);
        }
    }

    private async Task OpenTvAppAfterInstallAsync(LgTv target)
    {
        if (keeper is not null)
        {
            keeper.Reconnect();
            return;
        }
        try { await services.PairTvAsync(target, store.Load<string>(StoreKeys.TvKey), ServerAddress(target)); }
        catch (Exception) { /* TV uygulaması kuruldu; açılmadıysa kullanıcı açabilir */ }
    }

    /// <summary>TV ağda yeni bir adreste bulundu.</summary>
    public void TvMoved(LgTv moved)
    {
        tv = moved;
        store.Save(StoreKeys.Tv, moved);
        Changed(nameof(Tv));
    }

    public void StartModelDownload()
    {
        if (ModelInstalled || modelDownload is { IsCompleted: false }) return;
        ModelDownloading = true;
        ModelError = null;
        var download = services.Translation.DownloadAsync(settings.SourceLanguage, settings.TargetLanguage, new ImmediateProgress(value => post(() => ModelProgress = value)), CancellationToken.None);
        modelDownload = FinishDownload(download);
    }

    private async Task FinishDownload(Task download)
    {
        try
        {
            await download;
            post(() => ModelProgress = 1);
        }
        catch (Exception error)
        {
            post(() => ModelError = error.Message);
        }
        finally
        {
            post(() =>
            {
                ModelDownloading = false;
                Changed(nameof(ModelInstalled), nameof(CanAdvance));
                RefreshTranslatorStatus();
                // Çeviri sürerken model indiyse hat yeni çevirmenle kurulur.
                if (isRunning && TranslatorStatus == TranslatorStatus.Ready) MakePipeline();
            });
        }
    }

    public Task WaitForModelAsync() => modelDownload ?? Task.CompletedTask;

    public void SendTestSubtitle()
    {
        server.SendStyle(settings.Style);
        // Oyunda henüz altyazı görülmediyse altyazı bölgesinin altına yakın tipik bir yer kullanılır.
        var region = settings.Region;
        var box = lastSubtitleBox ?? new TextBox(0.3, region.Bottom - 0.1, 0.7, region.Bottom - 0.03);
        server.SendSubtitle(text["This is a test subtitle. Can you see it on top of the game?"], 8000, box);
    }

    /// <summary>
    /// Ana ekrandaki "TV'de dene": çeviri başlamadıysa altyazı sunucusu da açılır (TV uygulaması ona bağlanabilsin),
    /// sonra deneme altyazısı gönderilir. Port açılamazsa yalnız bilgisayar ekranındaki pencereye gider.
    /// </summary>
    public async Task SendTestSubtitleAsync()
    {
        try { await StartServerAsync(); } catch (SocketException) { }
        SendTestSubtitle();
    }

    /// <summary>
    /// Num 0: canlı altyazı çevirisini duraklatır ya da sürdürür. Alan çevirirken sürekli çeviri de TV'de görünüp
    /// karışmasın diye kullanılır. TV'de kısa bir bildirim çıkar. Çeviri sürmüyorsa bir şey yapmaz.
    /// </summary>
    public void ToggleSubtitles()
    {
        if (!isRunning) return;
        var pause = !subtitlesPaused;
        SubtitlesPaused = pause;
        if (pause)
        {
            pipeline?.Reset();
            server.Clear();
        }
        // Duraklatınca ek bölgeler de okunmaz, kutuları kalkar.
        UpdateRegionWatcher();
        server.SendStyle(settings.Style);
        server.SendSubtitle(text[pause ? "Subtitle translation paused" : "Subtitle translation resumed"], 1800);
    }

    /// <summary>Num 8: ayar ekranı, oyunun şu anki görüntüsünü yeniden alsın.</summary>
    public event Action? SnapshotRequested;

    public void RequestSnapshot() => SnapshotRequested?.Invoke();

    /// <summary>Çeviri bilgisayarda da gösterilecekse (metin, kalma süresi ms) ile çağrılır.</summary>
    public event Action<string, int>? PcResultReady;

    /// <summary>
    /// 1, 2 ya da 3 numaralı ek bölgeyi şimdi bir kez okuyup çevirir; sonuç ayardaki yere (TV, bilgisayar ya da ikisi) gider
    /// (görev paneli gibi yazılar için). Çeviri sürmüyorsa, bölge kapalıysa ya da önceki istek bitmediyse hiçbir şey yapılmaz.
    /// </summary>
    public async Task<ExtraRegionOutcome> TranslateExtraRegionAsync(int slot)
    {
        if (settings.ExtraRegion(slot) is not { } region) return ExtraRegionOutcome.NotConfigured;
        if (lastFrame is not { } frame) return ExtraRegionOutcome.NotRunning;
        var target = settings.ExtraTarget(slot);
        return (await RunRegionAsync(frame, region, target != ResultTarget.Pc, target != ResultTarget.Tv)).Outcome;
    }

    /// <summary>
    /// Serbest alan (Num 5): verilen karedeki alanı bir kez okuyup çevirir. Sonuç, ayardaki hedefe göre TV'ye de gönderilir;
    /// bilgisayarda gösterilmek üzere her durumda döner (serbest alan penceresi kendisi gösterir).
    /// </summary>
    public Task<(ExtraRegionOutcome Outcome, RegionTranslation.Result? Result)> TranslateAreaAsync(Frame frame, CropRegion region) =>
        RunRegionAsync(frame, region, settings.FreeAreaTarget != ResultTarget.Pc, false);

    private async Task<(ExtraRegionOutcome Outcome, RegionTranslation.Result? Result)> RunRegionAsync(Frame frame, CropRegion region, bool toTv, bool toPcPopup)
    {
        var reader = activeReader;
        if (!isRunning || reader is null) return (ExtraRegionOutcome.NotRunning, null);
        // Tuşa üst üste basılınca ikinci bir okuma başlamaz.
        if (Interlocked.Exchange(ref extraBusy, 1) == 1) return (ExtraRegionOutcome.Busy, null);
        try
        {
            RegionTranslation.Result? result;
            try
            {
                result = await RegionTranslation.TranslateOnceAsync(frame, region, reader, MakeTranslator());
            }
            catch (TranslatorException error)
            {
                post(() => TranslatorStatus = error.Status);
                return (ExtraRegionOutcome.TranslatorUnavailable, null);
            }
            catch
            {
                return (ExtraRegionOutcome.Failed, null);
            }
            if (result is null)
            {
                var message = text["No text found in this area."];
                if (toTv)
                {
                    server.SendStyle(settings.Style);
                    server.SendSubtitle(message, 2500, new TextBox(region.Left, region.Top, region.Right, region.Bottom));
                }
                if (toPcPopup) post(() => PcResultReady?.Invoke(message, 2500));
                return (ExtraRegionOutcome.NoText, null);
            }
            var milliseconds = RegionTranslation.DisplayMilliseconds(result.Translation);
            if (toTv)
            {
                server.SendStyle(settings.Style);
                server.SendSubtitle(result.Translation, milliseconds, result.Box, paragraphs: result.Structured);
            }
            post(() =>
            {
                LastSource = result.Source;
                LastTranslation = result.Translation;
                if (toPcPopup) PcResultReady?.Invoke(result.Translation, milliseconds);
            });
            return (ExtraRegionOutcome.Shown, result);
        }
        finally
        {
            Volatile.Write(ref extraBusy, 0);
        }
    }

    /// <summary>Süren "ekranı çevir" işi; yeniden basılınca iptal edilir.</summary>
    private CancellationTokenSource? screenWork;
    /// <summary>TV'deki ekran çevirilerinin kalkacağı an; bu andan önce yeniden basmak onları kaldırır.</summary>
    private DateTime screenShownUntil;

    /// <summary>
    /// Num 9: oyunun şu anki karesinin tamamını bir kez okur, her yazı grubunu ayrı çevirip TV'de kendi yerine koyar.
    /// Çeviriler hazırlandıkça TV'ye gider. Çeviri sürerken ya da çeviriler TV'deyken yeniden basmak onları kaldırır.
    /// </summary>
    public async Task<ScreenOutcome> TranslateScreenAsync()
    {
        var reader = activeReader;
        if (!isRunning || reader is null) return ScreenOutcome.NotRunning;
        if (lastFrame is not { } frame)
        {
            // Çeviri sürüyor ama PS5'ten henüz görüntü gelmedi: tuş sessizce yok sayılmasın.
            server.SendSubtitle(text["Couldn't capture the screen: no picture from the PS5 yet."], 4000);
            return ScreenOutcome.NotRunning;
        }
        if (screenWork is { } running)
        {
            running.Cancel();
            screenWork = null;
            HideScreen();
            return ScreenOutcome.Cleared;
        }
        if (DateTime.UtcNow < screenShownUntil)
        {
            HideScreen();
            return ScreenOutcome.Cleared;
        }

        using var work = new CancellationTokenSource();
        screenWork = work;
        server.SendStyle(settings.Style);
        server.SendSubtitle(text["Translating the screen…"], 2500);
        ITextTranslator? translator = null;
        try
        {
            translator = MakeTranslator();
            // Yapay zekâda ekranın bütün yazıları tek istekte gider (bkz. AiTranslator.TranslateAllAsync).
            var items = await ScreenTranslation.TranslateAsync(frame, reader, translator, shown =>
            {
                if (work.IsCancellationRequested) return;
                server.SendScreen(shown, ScreenTranslation.DisplayMilliseconds(shown));
                screenShownUntil = DateTime.UtcNow.AddMilliseconds(ScreenTranslation.DisplayMilliseconds(shown));
            }, work.Token);
            server.Clear();
            if (items.Count == 0)
            {
                server.SendSubtitle(text["No text found on the screen."], 2500);
                return ScreenOutcome.NoText;
            }
            return ScreenOutcome.Shown;
        }
        catch (OperationCanceledException)
        {
            return ScreenOutcome.Cleared;
        }
        catch (TranslatorException error)
        {
            post(() => TranslatorStatus = error.Status);
            ShowScreenFailure(error, translator);
            return ScreenOutcome.TranslatorUnavailable;
        }
        catch (Exception error)
        {
            RemotePlayLog.Note($"Ekran çevrilemedi: {error.GetType().Name}: {error.Message}");
            ShowScreenFailure(error, translator);
            return ScreenOutcome.Failed;
        }
        finally
        {
            if (screenWork == work) screenWork = null;
        }
    }

    /// <summary>Ekran çevrilemedi: nedeni TV'de (ve bilgisayardaki altyazıda) birkaç saniye görünür, sessizce kaybolmaz.</summary>
    private void ShowScreenFailure(Exception error, ITextTranslator? translator)
    {
        server.Clear();
        var reason = ScreenFailureReason(error, translator, settings.OnlineEngine, text, settings.LocalAiServer);
        server.SendSubtitle(text.Format("Couldn't translate the screen: %@", reason), 6000);
    }

    /// <summary>Ekran çevirisinin neden olmadığı: önce çevrimiçi motorun hatası, sonra ücretsiz çevirinin durumu.</summary>
    public static string ScreenFailureReason(Exception error, ITextTranslator? translator, TranslationEngine engine, Localizer text,
                                             LocalAiServer? server = null)
    {
        if (translator is IOnlineTranslator online)
        {
            if (online.LastError is { } failure) return failure.Describe(engine, text, server);
            if (online.LastLineWasRateLimited)
                return text.Format("%@ has reached its per-minute limit. Try again in a minute.", engine.DisplayName());
        }
        return (error as TranslatorException)?.Status switch
        {
            TranslatorStatus.NeedsDownload => text["The free translation isn't downloaded yet."],
            TranslatorStatus.EngineFailed => text["The free translation couldn't be started."],
            _ => text["Something went wrong. Try again."],
        };
    }

    private void HideScreen()
    {
        screenShownUntil = default;
        server.ClearScreen();
        server.Clear();
    }

    /// <summary>Kurulumu baştan başlatır (kayıtlı her şeyi siler).</summary>
    /// <summary>
    /// Nino: Ayarlar › Bağlantı'daki konsol seçimi (Mac ile aynı). Xbox'ta PS5'e doğrudan bağlanma olmadığından görüntü
    /// Xbox penceresinden okunur (Capture Card seçiliyse o kalır).
    /// </summary>
    public void SwitchConsole(GameConsole console)
    {
        if (settings.GameConsole == console) return;
        var source = console == GameConsole.Xbox && settings.VideoSource == VideoSource.Ps5 ? VideoSource.Window : settings.VideoSource;
        Settings = settings with { GameConsole = console, VideoSource = source };
    }

    public void ResetSetup()
    {
        Stop();
        xboxGeneration++;
        services.Xbox?.Clear();
        foreach (var key in new[] { StoreKeys.AccountId, StoreKeys.Console, StoreKeys.ConsoleKind, StoreKeys.ConsoleKindLocked, StoreKeys.XboxToken, StoreKeys.XboxConsole,
                     StoreKeys.Tv, StoreKeys.TvKey, StoreKeys.TvDevKey, StoreKeys.TvAppVersion, StoreKeys.SetupComplete, StoreKeys.LoginPasscode }) store.Remove(key);
        accountId = null;
        console = null;
        consoleKind = GameConsoleKind.PlayStation;
        consoleKindLocked = false;
        xboxToken = null;
        xboxConsole = null;
        tv = null;
        tvAppMissing = false;
        TvApp = TvAppState.Unknown;
        CardSetupActive = false;
        Step = OnboardingStep.Welcome;
        Changed(nameof(HasAccount), nameof(Console), nameof(ConsoleKind), nameof(ConsoleKindLocked), nameof(IsXbox), nameof(ConsoleTitle), nameof(HasXboxAccount),
            nameof(SelectedXboxConsole), nameof(StepCount), nameof(StepNumber), nameof(Ps5StatusText), nameof(Tv), nameof(HasTv), nameof(NeedsTv), nameof(CanStart), nameof(HasLoginPasscode));
    }

    /// <summary>İkinci hesabın PS5 giriş şifresi şifreli depoda kayıtlı mı (şifrenin kendisi arayüze dönmez).</summary>
    public bool HasLoginPasscode => LoginPasscode.Normalized(store.Load<string>(StoreKeys.LoginPasscode)) is not null;

    /// <summary>Yalnız 4 hane şifreli depoya yazılır; geçersizse false. Sonraki bağlantıda kullanılır.</summary>
    public bool SetLoginPasscode(string value)
    {
        if (LoginPasscode.Normalized(value) is not { } pin) return false;
        store.Save(StoreKeys.LoginPasscode, pin);
        Changed(nameof(HasLoginPasscode));
        return true;
    }

    public void RemoveLoginPasscode()
    {
        store.Remove(StoreKeys.LoginPasscode);
        Changed(nameof(HasLoginPasscode));
    }

    /// <summary>
    /// Nino: "TV'den itibaren yeniden kur" (Mac ile aynı). PS5 hesabı ve PS5 eşleşmesi korunur; yalnız TV bağlantısı ve TV
    /// uygulamasının kaydı silinir, sihirbaz TV adımından devam eder.
    /// </summary>
    public void ResetFromTv()
    {
        Stop();
        foreach (var key in new[] { StoreKeys.Tv, StoreKeys.TvKey, StoreKeys.TvDevKey, StoreKeys.TvAppVersion, StoreKeys.SetupComplete })
            store.Remove(key);
        tv = null;
        tvAppMissing = false;
        TvApp = TvAppState.Unknown;
        // "TV'm yok" seçilmişse de TV adımı yeniden sorulur.
        if (settings.Output == SubtitleOutput.Computer) Settings = settings with { Output = SubtitleOutput.Tv };
        Step = OnboardingStep.Tv;
        Changed(nameof(Tv), nameof(HasTv), nameof(NeedsTv), nameof(CanStart));
    }

    // --- Çeviri ---

    public async Task StartAsync()
    {
        // Düğmeye iki kez basılması ya da beklerken tekrar çağrılması ikinci bir oturum açmaz.
        if (isRunning || isStarting || !CanStart) return;
        // Nino: oyun penceresi ve yakalama kartı (önce gelir; PS5 hesabı gerekmez).
        var windowSource = UsesGameWindow ? services.MakeWindowStream(settings.GameConsole) : null;
        if (UsesGameWindow && windowSource is null) return;
        var cardSource = UsesCaptureCard ? services.MakeCardStream(ShowsOnComputer, PreferredCardId) : null;
        if (UsesCaptureCard && cardSource is null) return;
        var ninoSource = windowSource is not null || cardSource is not null;
        // PS5 için hesap gerekir; Remote Play, açıkça seçilen OBS/oyun penceresi ve Xbox için gerekmez.
        var readsWindow = !ninoSource && !IsXbox && settings.FrameSource == FrameSource.RemotePlayWindow;
        var readsCapture = !ninoSource && !IsXbox && settings.FrameSource == FrameSource.CaptureWindow;
        if (!ninoSource && !IsXbox && !readsWindow && !readsCapture && (console is null || accountId is null)) return;
        IsStarting = true;
        try
        {
            // Uygulama başlatırken kapanırsa günlükte hangi adımda kaldığı görünsün.
            RemotePlayLog.Note($"Çeviri hazırlanıyor; altyazı: {settings.Output}, TV: {(tv is null ? "yok" : tv.Brand.ToString())}");
            RefreshTranslatorStatus();
            try { await StartServerAsync(); } catch { /* port açılamadıysa TV durumu "bekleniyor" kalır */ }
            server.SendStyle(settings.Style);
            SubtitlesPaused = false;
            MetricsText = "";
            MakePipeline();
            if (DubbingActive && DubbingInstalled) MakeDubber()?.Prepare();
            SubtitleLog.Write($"oturum başladı: {settings.SourceLanguage}→{settings.TargetLanguage}, "
                + $"motor: {(OnlineTranslationActive ? settings.OnlineEngine.ToString() : "ücretsiz")}, paketler: {(settings.GamePacks ? "açık" : "kapalı")}, "
                + $"görüntü: {(windowSource is not null ? "oyun penceresi" : cardSource is not null ? "yakalama kartı" : IsXbox ? "Xbox" : readsWindow ? "Remote Play penceresi" : readsCapture ? "seçilen pencere" : "PS5")}"
                + $", ağ: {NetworkKinds.Detect().ToString().ToLowerInvariant()}");
            HealthRecorder.Shared.SessionStarted();

            IStreamSession stream;
            if (windowSource is not null)
            {
                SubtitleLog.Write("görüntü kaynağı: oyun penceresi (PS Remote Play / chiaki-ng)");
                // Eski oturumun geç gelen olayları yeni oturumu bozmasın: yalnız şu anki kaynak dinlenir.
                windowSource.WindowStatusChanged += (status, app) => post(() =>
                {
                    if (ReferenceEquals(session, windowSource)) WindowStatusChanged(status, app);
                });
                windowSource.GameAreaChanged += area => post(() =>
                {
                    if (ReferenceEquals(session, windowSource)) GameArea = area;
                });
                stream = windowSource;
            }
            else if (cardSource is not null)
            {
                SubtitleLog.Write("görüntü kaynağı: yakalama kartı" + (ShowsOnComputer ? " (oyun bu bilgisayarda gösteriliyor)" : ""));
                cardSource.CardStatusChanged += status => post(() =>
                {
                    if (ReferenceEquals(session, cardSource)) CardStatusChanged(status);
                });
                cardSource.GameAreaChanged += area => post(() =>
                {
                    if (ReferenceEquals(session, cardSource)) GameArea = area;
                });
                // Oyun penceresini kapatmak çeviriyi durdurur.
                cardSource.PlayerClosed += () => post(() =>
                {
                    if (ReferenceEquals(session, cardSource)) Stop();
                });
                stream = cardSource;
            }
            else if (IsXbox)
            {
                RemotePlayLog.Note($"Çeviri başladı; {ConsoleTitle} bağlantısı açılıyor.");
                stream = (services.Xbox ?? throw new InvalidOperationException(text["Xbox streaming isn't available in this version."])).MakeStream(xboxConsole!, xboxToken!, settings.XboxLegacyFrameRate);
                xboxNameChecked = false;
            }
            else if (readsWindow)
            {
                RemotePlayLog.Note($"Çeviri başladı; görüntü bu bilgisayardaki Remote Play penceresinden ({settings.RemotePlayApp})");
                stream = services.MakeWindowStream(settings.RemotePlayApp);
            }
            else if (readsCapture)
            {
                var target = settings.CaptureWindow ?? throw new InvalidOperationException("A capture window must be selected.");
                RemotePlayLog.Note($"Çeviri başladı; seçilen pencere: {target.ProcessName} / {target.Title}");
                stream = services.MakeCaptureWindowStream(target);
            }
            else
            {
                RemotePlayLog.Note($"Çeviri başladı; PS5'e bağlanılıyor: {console!.Name} {console.Host}");
                stream = services.MakeStream(console, accountId!, store.Load<string>(StoreKeys.LoginPasscode));
            }
            var current = stream;
            stream.StateChanged += state => post(() =>
            {
                if (ReferenceEquals(session, current)) SessionStateChanged(state);
            });
            stream.ConsoleMoved += moved => post(() => ConsoleMoved(moved));
            stream.FrameReceived += HandleFrame;
            stream.Start();
            session = stream;

            StartKeeper();
            StartGameSense();

            sleep.Begin(KeepsDisplayOn);
            IsRunning = true;
            // Nino: TV kısa bir "Çeviri başladı" balonu gösterir (geç bağlanan TV 20 sn içinde yine görür).
            server.SendStarted();
            UpdateTroubleClocks();
        }
        catch (Exception error)
        {
            // Yarım kalan başlatma geride çalışan bir PS5 oturumu bırakmasın; düğme yeniden "Başlat" olur.
            RemotePlayLog.Note($"Çeviri başlatılamadı: {error.GetType().Name}: {error.Message}");
            Stop();
            throw;
        }
        finally
        {
            IsStarting = false;
        }
    }

    /// <summary>
    /// TV uygulamasını başlatır ve açık tutar; TV kapalıysa açıldığında bağlanır. Altyazı TV'ye gitmiyorsa ya da TV
    /// yoksa bir şey yapmaz.
    /// </summary>
    private void StartKeeper()
    {
        if (keeper is not null || !ShowsOnTv || !HasTv || tv is not { } target) return;
        var running = server;
        var tvKeeper = services.MakeKeeper(target, store.Load<string>(StoreKeys.TvKey), new Dictionary<string, string> { ["server"] = ServerAddress(target) },
            () => running.ConnectedClients > 0, moved => post(() => TvMoved(moved)), key => post(() => store.Save(StoreKeys.TvKey, key)));
        tvKeeper.Start(TimeSpan.FromSeconds(5));
        keeper = tvKeeper;
        _ = RefreshTvAppAsync();
    }

    /// <summary>Altyazının yeri değişti: TV seçildiyse TV uygulaması açılır, kaldırıldıysa artık açık tutulmaz.</summary>
    /// <summary>
    /// Çeviri sürerken bilgisayar ekranı da açık kalsın mı: görüntü bu bilgisayardaki Remote Play ya da seçilen pencereden
    /// okunuyorsa (ekran kapanınca yakalama kare vermez) ya da altyazı bu ekranda gösteriliyorsa. PS5'ten ya da Xbox'tan
    /// doğrudan okunup yalnız TV'ye gönderiliyorsa ekran kendi ayarıyla kapanabilir.
    /// </summary>
    private bool KeepsDisplayOn =>
        (!IsXbox && settings.FrameSource is FrameSource.RemotePlayWindow or FrameSource.CaptureWindow) || ShowsOnComputer;

    private void OutputChanged()
    {
        server.SendsToTv = ShowsOnTv;
        if (!ShowsOnComputer)
        {
            OverlayAdjusting = false;
            OverlayHidden?.Invoke();
        }
        Changed(nameof(ShowsOnTv), nameof(ShowsOnComputer), nameof(NeedsTv), nameof(CanStart), nameof(CanAdvance), nameof(ShowsCardPlayer));
        UpdateTroubleClocks();
        if (!isRunning) return;
        sleep.Begin(KeepsDisplayOn);
        if (ShowsOnTv) StartKeeper();
        else
        {
            keeper?.Stop();
            keeper = null;
        }
    }

    // --- Bilgisayar ekranındaki altyazı penceresi ---

    /// <summary>
    /// TV'ye giden altyazı ve temizleme olaylarının aynısı (arayüz iş parçacığında); bilgisayar ekranındaki pencere bunları
    /// TV uygulamasıyla aynı yığınla (<see cref="SubtitleStack"/>) gösterir. Altyazı bilgisayarda gösterilmiyorsa gelmez.
    /// </summary>
    public event Action<SubtitleEvent>? OverlayEvent;
    /// <summary>Penceredeki her şey hemen kalksın (çeviri durdu ya da altyazı artık bilgisayarda değil).</summary>
    public event Action? OverlayHidden;

    private bool overlayAdjusting;

    /// <summary>Pencerenin yeri ve genişliği ayarlanıyor: örnek yazı görünür, tıklamalar geçmez.</summary>
    public bool OverlayAdjusting { get => overlayAdjusting; set => Set(ref overlayAdjusting, value); }

    private bool hotkeysPaused;

    /// <summary>
    /// Ayarlar'da yeni kısayol bekleniyor: genel kısayollar bırakılır, böylece basılan tuş (çeviri sürerken bile) işi
    /// çalıştırmadan seçim kutusuna ulaşır.
    /// </summary>
    public bool HotkeysPaused { get => hotkeysPaused; set => Set(ref hotkeysPaused, value); }

    /// <summary>Num 7 ve ana ekrandaki seçenek: altyazı penceresinde tıklamaların geçmesini açar/kapatır.</summary>
    public void ToggleClickThrough() => Settings = settings with { OverlayClickThrough = !settings.OverlayClickThrough };

    /// <summary>Taşınan ya da genişletilen pencerenin yeri kaydedilir.</summary>
    public void SaveOverlayBounds(OverlayBounds bounds) => Settings = settings with { Overlay = bounds };

    private void OnSubtitleEvent(SubtitleEvent e)
    {
        post(() => StreamEvent?.Invoke(e));
        if (!ShowsOnComputer) return;
        post(() => OverlayEvent?.Invoke(e));
    }

    // --- Yayın penceresi (yayın programlarının pencere yakalamayla aldığı düz zeminli altyazı) ---

    /// <summary>
    /// <see cref="OverlayEvent"/> ile aynı olaylar, ama altyazı yalnız TV'de gösterilse de gelir: yayın penceresi açıkken
    /// yayındaki altyazı ekrandaki seçimden bağımsızdır.
    /// </summary>
    public event Action<SubtitleEvent>? StreamEvent;
    /// <summary>Yayın penceresindeki her şey hemen kalksın (çeviri durdu).</summary>
    public event Action? StreamHidden;

    /// <summary>Yayın penceresinin zemin rengi (chroma key ile silinir).</summary>
    public StreamBackground StreamBackground
    {
        get => StreamBackgrounds.FromStored(store.Load<string>(StoreKeys.StreamBackground));
        set
        {
            if (value == StreamBackground) return;
            store.Save(StoreKeys.StreamBackground, value.StoredName());
            Changed(nameof(StreamBackground));
        }
    }

    /// <summary>Bilgisayarın ağ adresiyle OBS sayfası; localhost'u kabul etmeyen yayın programları (TikTok LIVE Studio) için.</summary>
    public string? NetworkObsAddress => LocalAddress(null) is { } address ? $"http://{address}:{ServerPort}/obs" : null;

    public void Stop()
    {
        session?.Stop();
        session?.Dispose();
        session = null;
        UpdateGameProbe(connected: false);
        StopGameSense();
        StopTranslationSync();
        services.Translations?.Save();
        keeper?.Stop();
        keeper = null;
        pipeline?.Reset();
        if (pipeline is not null)
        {
            // Nino: oturumun sağlık özeti günlüğe de yazılır (kayıtları gönderenin ekranını görmeden okunur).
            HealthRecorder.Shared.SessionEnded();
            SubtitleLog.Write("sağlık: " + HealthReport.Summary(HealthRecorder.Shared.Snapshot(), NetworkKinds.Detect()).Replace("\n", " · "));
            SubtitleLog.Write("oturum bitti");
        }
        pipeline = null;
        UpdateRegionWatcher();
        // Yeni "Başlat" eski oturumdan kalan (belki takılmış) okumayı beklemeden temiz başlar.
        frameGate.Reset();
        activeReader = null;
        screenWork?.Cancel();
        screenWork = null;
        if (DateTime.UtcNow < screenShownUntil) server.ClearScreen();
        screenShownUntil = default;
        SubtitlesPaused = false;
        ActiveSourceLanguage = null;
        OnlineIssue = null;
        StopDubber();
        if (isRunning) sleep.End();
        IsRunning = false;
        // Nino: çeviri sürerken bulunan güncelleme şimdi kurulur (uygulama yeniden açılır). Uygulama kapanırken
        // başlatılmaz: indirme kapanan uygulamada yarıda kalırdı; bekleyen güncelleme sonraki açılışta kurulur.
        if (autoInstallPending && !closing && UpdateVersion is { } pendingVersion && CanAutoInstall(pendingVersion))
        {
            autoInstallPending = false;
            post(() => _ = InstallUpdateAsync(automatic: true));
        }
        SessionState = SessionState.Disconnected(DisconnectKind.Stopped);
        WindowStatus = GameWindowStatus.Stopped;
        WindowApp = null;
        CardStatus = CaptureCardStatus.Stopped;
        GameArea = null;
        UpdateTroubleClocks();
        firewallRuleSeen = false;
        ClearFirewallPrompt();
        OverlayHidden?.Invoke();
        StreamHidden?.Invoke();
    }

    /// <summary>Bilgisayar uykudan uyanınca bağlantıları hemen yenile.</summary>
    public void SystemResumed()
    {
        session?.ReconnectNow();
        keeper?.Reconnect();
    }

    /// <summary>Çeviri başlamamışken bağlı olmamak bir sorun değildir; nokta gri kalır.</summary>
    public static StatusTone Ps5ToneFor(SessionState state, bool running) =>
        state.Phase == SessionPhase.Streaming ? StatusTone.Good : running ? StatusTone.Warning : StatusTone.Idle;

    public static StatusTone TvToneFor(int clients, bool running) =>
        clients > 0 ? StatusTone.Good : running ? StatusTone.Warning : StatusTone.Idle;

    /// <summary>PS5 durumunun kullanıcıya gösterilecek metni.</summary>
    /// <param name="pairedName">Eşleşmiş PS5'in adı. Çeviri başlamamışken eşleşmiş PS5 için "Bağlı değil" yerine "eşleşti,
    /// başlatınca bağlanır" denir: eskiden eşleştirme başarılı olsa da ana ekran "Bağlı değil" diyordu.</param>
    /// <summary>Görüntü bu bilgisayardaki Remote Play penceresinden okunurken durumun metni.</summary>
    public static string CaptureWindowStatusText(SessionState state, bool running, Localizer text, WindowCaptureTarget? target)
    {
        if (target is not { ProcessName.Length: > 0, Title.Length: > 0 })
            return text["Choose an OBS or game window in Settings › Picture source."];
        if (state.Phase == SessionPhase.Streaming) return text["Reading the selected window"];
        if (!running) return text.Format("Ready to read %@ when translation starts.", target.Title);
        return state.Reason?.Detail is { Length: > 0 } detail
            ? detail
            : text.Format("Waiting for the selected window: %@", target.Title);
    }

    public static string RemotePlayWindowStatusText(SessionState state, bool running, Localizer text, bool installed = true)
    {
        const string waiting = "Waiting for the Remote Play window. Open PS Remote Play or chiaki-ng on this PC.";
        if (state.Phase != SessionPhase.Streaming && !installed)
            return text["The Remote Play app isn't installed on this PC. Download it in Settings › Picture source."];
        switch (state.Phase)
        {
            case SessionPhase.Streaming: return text["Reading the Remote Play window"];
            case SessionPhase.Connecting: return text[waiting];
        }
        if (!running) return text["Reads the Remote Play window on this PC when you start translating."];
        return state.Reason?.Detail is { Length: > 0 } detail ? detail : text[waiting];
    }

    /// <summary>Görüntü kaynağı değişti: altyazının yeri güncellenir; çeviri sürüyorsa yeni kaynakla yeniden başlar.</summary>
    private void VideoSourceChanged()
    {
        OutputChanged();
        Changed(nameof(UsesGameWindow), nameof(UsesCaptureCard), nameof(CanStart), nameof(Ps5StatusText), nameof(WindowStatusText),
                nameof(CardStatusText), nameof(ShowsCardPlayer));
        if (!isRunning) return;
        Stop();
        _ = StartAsync();
    }

    private void CardStatusChanged(CaptureCardStatus status)
    {
        if (status == cardStatus) return;
        CardStatus = status;
        SubtitleLog.Write(status.State switch
        {
            CaptureCardState.NeedsPermission => "yakalama kartı: kamera izni yok",
            CaptureCardState.NoCard => "yakalama kartı: bulunamadı",
            CaptureCardState.BlackPicture => $"yakalama kartı: görüntü siyah ({status.Name})",
            CaptureCardState.Capturing => $"yakalama kartı: okunuyor ({status.Name})",
            _ => "yakalama kartı: durdu",
        });
    }

    private void WindowStatusChanged(GameWindowStatus status, string? app)
    {
        if (status == windowStatus && app == windowApp) return;
        WindowStatus = status;
        WindowApp = app;
        SubtitleLog.Write(status switch
        {
            GameWindowStatus.Capturing => $"oyun penceresi: okunuyor ({app})",
            GameWindowStatus.LookingForWindow => "oyun penceresi: bulunamadı",
            _ => "oyun penceresi: durdu",
        });
    }

    public static string StatusText(SessionState state, bool running, Localizer text, string? pairedName = null)
    {
        switch (state.Phase)
        {
            case SessionPhase.Streaming: return text["Connected"];
            case SessionPhase.Connecting: return text["Connecting…"];
        }
        if (!running)
            return pairedName is null ? text["Not connected"] : text.Format("Paired with %@. Connects when you start translating.", pairedName);
        var detail = state.Reason?.Detail;
        return state.Reason?.Kind switch
        {
            DisconnectKind.ConsoleAsleep => text["Turn on your PS5"],
            DisconnectKind.InUse => text["Remote Play is in use on another device"],
            DisconnectKind.Refused => text["The PS5 refused the connection. Set up the PS5 again."],
            DisconnectKind.LoginPasscode => text["The PS5 asks for this account's login passcode. Enter it in Settings, or turn off this account's login passcode on the PS5."],
            // Yanlış şifre bir kez gönderilir; PS5 yeniden isterse oturum kapanır (döngü yok).
            DisconnectKind.LoginPasscodeIncorrect => text["The PS5 didn't accept the login passcode in Settings. Correct it, or turn off this account's login passcode on the PS5."],
            // Eskiden "Yeniden bağlanılıyor… (Unknown Session Request Error)" diye sonsuza kadar deneniyordu.
            DisconnectKind.RegistrationInvalid => text["The PS5 didn't accept this pairing. Pair the PS5 again with the second account in Settings."],
            // PS5 kodu 0x80108b12: eskiden yalnız "PS5 bağlantıyı reddetti (kod …)" deniyordu.
            DisconnectKind.RemotePlayDisabled => text["Remote Play is turned off on the PS5. On the PS5, open Settings › System › Remote Play and turn on Enable Remote Play, then start again."],
            // Eskiden ağ hatası, bulunamayan PS5 ve diğer nedenler hep yalnız "Yeniden bağlanılıyor…" idi.
            DisconnectKind.NotFound => text.Format("PS5 not found at %@. Make sure it is on and on the same network. Reconnecting…", detail ?? "?"),
            DisconnectKind.Network => text["Can't reach the PS5. Reconnecting…"],
            // Eskiden "Yeniden bağlanılıyor… (Unknown Session Request Error)" görünüyordu (GitHub #33, #202).
            DisconnectKind.Rejected when !string.IsNullOrEmpty(detail) => text.Format("The PS5 rejected the connection (code %@). Another Remote Play app (PS Remote Play) may be open, or the PS5 may be in another session. Close PS Remote Play, restart the PS5, then try again.", detail),
            DisconnectKind.Rejected => text["The PS5 didn't start the session. Another Remote Play app (PS Remote Play) may be open, or the PS5 may be in another session. Close PS Remote Play, restart the PS5, then try again."],
            DisconnectKind.Other when !string.IsNullOrEmpty(detail) => text.Format("Reconnecting… (%@)", detail),
            _ => text["Reconnecting…"],
        };
    }

    public void Dispose()
    {
        // Kapanışta Stop() bekleyen güncellemenin kurulumunu başlatmasın (bkz. Stop).
        closing = true;
        services.Translation.EngineFailure -= OnEngineFailure;
        services.Translation.GpuFallback -= OnGpuFallback;
        if (services.Xbox is { } xbox) xbox.TokenUpdated -= OnXboxTokenUpdated;
        Stop();
        if (services.Xbox is IDisposable disposableXbox) disposableXbox.Dispose();
        server.Dispose();
        poolTimer?.Dispose();
        packTimer?.Dispose();
        // Havuzdaki satırlar zaten diskte; kapanışta ağ beklenmez, açılışta gönderilir.
        services.Pool?.Dispose();
        services.Translations?.Dispose();
    }

    // --- Oyun paketleri ve ortak havuz ---

    /// <summary>Ayarlarda listelenen paketler (açılışta arka planda yüklenince dolar).</summary>
    public IReadOnlyList<GamePackLibrary.Info> InstalledPacks { get => installedPacks; private set => Set(ref installedPacks, value); }

    public void ReloadGamePacks()
    {
        if (services.GamePacks is not { } packs) return;
        packs.Reload();
        InstalledPacks = packs.Packs;
    }

    /// <summary>Oynanan oyunun adı (bilinmiyorsa null): ana ekrandaki "Oynanan oyun: X · Değiştir".</summary>
    public string? PlayedGame { get => playedGame; private set => Set(ref playedGame, value, [nameof(LiveGamePoolFirst), nameof(TranslationSourceText)]); }

    /// <summary>
    /// Nino: "Cihaz bilgileri" satırları (Sistem sağlığı'ndaki kart; Sorun Bildir ve Nino'ya Sor bildirimlerine özeti
    /// eklenir). Kişiyi tanıtan hiçbir şey içermez (bkz. <see cref="DeviceReport"/>). <paramref name="app"/> uygulamanın
    /// sürümüdür (<see cref="AppVersion.Current"/>).
    /// </summary>
    public IReadOnlyList<DeviceInfo.Row> DeviceRows(string app) => DeviceInfo.Rows(app,
        tv: DeviceReport.Tv(tv, tvApp.Version ?? InstalledAppVersion, tvClients > 0),
        console: DeviceReport.Console(settings, consoleKind, xboxConsole),
        status: DeviceReport.Status(isRunning, settings, consoleKind, sessionState, windowStatus, cardStatus.State,
            HealthRecorder.Shared.Snapshot().LastDisconnect));

    /// <summary>Sunucuya giden tek satırlık özet (<see cref="DeviceInfo.Summary"/>).</summary>
    public string DeviceSummary(string app) => DeviceInfo.Summary(DeviceRows(app));

    /// <summary>
    /// Nino: tanınan oyun havuz öncelikli mi (şimdilik GTA 6). Ana ekrandaki salon sahnesinde TV'nin fonu buna göre seçilir
    /// (Mac'teki liveGamePoolFirst). Oyun tanınmadıysa false: yalnız paketten ya da sunucudan tahmin edilen oyun saymaz.
    /// </summary>
    public bool LiveGamePoolFirst => gameSense.Current?.Name is not null && services.Translations?.IsPoolFirst(PoolFirstGame()) == true;

    /// <summary>
    /// Nino: alt şeritteki çeviri kaynağı yazısı; o an GERÇEKTEN kullanılan çeviriyi söyler (Mac'teki alt şeritle aynı
    /// kural). GTA 6 tanınınca (ve havuz o dilde çeviriyorsa) "Nino · GTA 6 Aktif"; oyun tanınmadan önce ya da başka
    /// oyunda kullanıcının seçtiği motor (Ücretsiz, Gemini…). Oyun değişince kendiliğinden güncellenir.
    /// </summary>
    public string TranslationSourceText => LiveGamePoolFirst ? text["Nino · GTA 6 active"]
        : settings.Engine == TranslationEngine.Free ? text["Free"] : settings.Engine.DisplayName();

    /// <summary>
    /// Nino: toplam indirme sayısı (ana ekrandaki TV'nin sağ üstü); son bilinen sayı, hiç alınamadıysa null (gösterge
    /// görünmez). Bkz. <see cref="DownloadCounter"/>.
    /// </summary>
    public int? DownloadTotal => services.Translations?.Downloads.Total;

    /// <summary>
    /// Toplam indirmeyi yeniler: sunucunun ayarını sorar (çeviri havuzunun zaten sorduğu <c>/v1/config</c>; en çok 10
    /// dakikada bir, ayrı istek yok). Alınamazsa eldeki sayı kalır. Ana ekran açılışta ve aralıklarla çağırır.
    /// </summary>
    public async Task RefreshDownloadsAsync()
    {
        if (services.Translations is not { } translations) return;
        var before = translations.Downloads.Total;
        await translations.RefreshConfigAsync();
        if (translations.Downloads.Total != before) Changed(nameof(DownloadTotal));
    }

    /// <summary>"Hangi oyunu oynuyorsunuz?" kartı açık.</summary>
    public bool AskingGame { get => askingGame; private set => Set(ref askingGame, value); }

    /// <summary>Bu PS5'te son seçilen oyun.</summary>
    public string? LastPlayedGame =>
        GameConsoleName is { } name && store.Load<Dictionary<string, string>>(StoreKeys.LastGames) is { } saved ? saved.GetValueOrDefault(name) : null;

    private string? GameConsoleName => console is null ? null : string.IsNullOrEmpty(console.Name) ? console.Host : console.Name;

    /// <summary>Kartın önerileri: son oynanan, kurulu paketlerin oyunları ve popüler oyunlar.</summary>
    public IReadOnlyList<string> GameSuggestions(string query) =>
        GameCatalog.Suggestions(query, GameCatalog.PackGames(installedPacks), LastPlayedGame);

    /// <summary>Kullanıcı bir oyun seçti ya da adını yazdı; seçim PS5'in adıyla saklanır.</summary>
    public void ChooseGame(string name)
    {
        if (RunningGame.Named(name)?.Name is not { } clean) return;
        gameSense.Choose(clean);
        if (GameConsoleName is { } consoleName)
        {
            var saved = store.Load<Dictionary<string, string>>(StoreKeys.LastGames) ?? new Dictionary<string, string>();
            saved[consoleName] = clean;
            store.Save(StoreKeys.LastGames, saved);
        }
        AskingGame = false;
        PublishGame();
    }

    /// <summary>"Değiştir": kart elle açılır.</summary>
    public void AskGame()
    {
        gameSense.MarkAsked();
        AskingGame = true;
    }

    /// <summary>"Sorma": bu oturumda bir daha sorulmaz.</summary>
    public void DismissGame()
    {
        gameSense.MarkAsked();
        AskingGame = false;
    }

    /// <summary>Oyun değiştiyse havuza bildirilir; yeni oyunun (havuzdan otomatik) paketi sunucuda yeni çıkmış olabilir.</summary>
    private void PublishGame()
    {
        // Elle seçilen oyunda satırlar yalnız o oyunun paketinde aranır, paketi yoksa hiç aranmaz (#218).
        services.GamePacks?.LimitToGame(gameSense.PackLimit);
        var current = gameSense.Current;
        PlayedGame = current?.Name;
        if (current == publishedGame) return;
        publishedGame = current;
        // Nino: yeni oyunun havuzdaki çevirileri hemen iner.
        if (pipeline is not null) StartTranslationSync();
        // Nino: NinoPool oyunu her satırla ayrıca alır (OfferToPool).
        if (current is not null && services.PackUpdates is { } packUpdater) _ = RefreshPacksAsync(packUpdater, maxAge: PackUpdater.GameCheckInterval);
    }

    /// <summary>Çeviri başladı: oyun penceresi sıfırlanır, iki dakika sonra oyun hâlâ bilinmiyorsa kart açılır.</summary>
    private void StartGameSense()
    {
        gameSense.StartSession();
        identifySchedule.Reset();
        publishedGame = null;
        AskingGame = false;
        PublishGame();
        gameAsk?.Cancel();
        gameAsk?.Dispose();
        var cancel = new CancellationTokenSource();
        gameAsk = cancel;
        var token = cancel.Token;
        var started = DateTime.UtcNow;
        _ = Task.Run(async () =>
        {
            while (!token.IsCancellationRequested)
            {
                try { await Task.Delay(TimeSpan.FromSeconds(15), token).ConfigureAwait(false); }
                catch (OperationCanceledException) { return; }
                if (!gameSense.ShouldAsk(DateTime.UtcNow - started, settings.AskGame && settings.SharePool)) continue;
                gameSense.MarkAsked();
                post(() => { if (!token.IsCancellationRequested) AskingGame = true; });
                return;
            }
        }, CancellationToken.None);
    }

    /// <summary>
    /// Nino: oyun bilinmiyorsa (PS5 bildirmiyor, paketten de tanınmadı) Remote Play karesinden tanınır: sunucuda Claude
    /// kareye bakıp oyunun adını söyler. Zamanlama <see cref="ScreenIdentifySchedule"/>'da. Ekrandan tanınan oyun en düşük
    /// önceliktir (konsol, kullanıcı ve paket önce gelir). Başka bir oyun söylenirse ona geçilir; tanınamazsa eskisi kalır.
    /// UI iş parçacığında çağrılır.
    /// </summary>
    private void IdentifyGameIfNeeded(Frame frame)
    {
        // Paketten tahmin edilen oyun kesin değildir: havuz öncelikli oyun bilinmiyorsa ekrandan tanıma yine denenir.
        if (!IsRunning || !settings.SharePool || settings.SourceLanguage != "en"
            || (services.GamePacks?.SearchScope is not null && PoolFirstActive)) return;
        if (services.Translations is not { IsEnabled: true } translations) return;
        var known = gameSense.Current;
        if (!identifySchedule.TryBegin(known is not null, gameSense.Source)) return;
        var tries = identifySchedule.Tries;
        _ = Task.Run(async () =>
        {
            string? name = null;
            try
            {
                if (services.SmallJpeg(frame, 768, 60) is { } jpeg) name = await translations.IdentifyAsync(jpeg).ConfigureAwait(false);
            }
            catch (Exception error)
            {
                SubtitleLog.Write($"oyun ekrandan tanınamadı: {error.GetType().Name}");
            }
            finally
            {
                identifySchedule.Finish();
            }
            post(() =>
            {
                if (!IsRunning) return;
                if (name is null)
                {
                    SubtitleLog.Write(known is null ? $"oyun ekrandan tanınamadı (deneme {tries})"
                                                    : $"oyun yeniden bakışta seçilemedi; {known.Name} olarak kalıyor");
                    return;
                }
                if (known is not null && NinoPool.GameId(known.Name) == NinoPool.GameId(name))
                {
                    SubtitleLog.Write($"oyun doğrulandı: {name}");
                    return;
                }
                SubtitleLog.Write(known is null ? $"oyun ekrandan tanındı: {name}" : $"oyun değişmiş: {known.Name} → {name}");
                gameSense.SetSeen(name);
                AskingGame = false;
                PublishGame();
            });
        }, CancellationToken.None);
    }

    private void StopGameSense()
    {
        gameAsk?.Cancel();
        gameAsk?.Dispose();
        gameAsk = null;
        AskingGame = false;
    }

    /// <summary>Paketler yalnız İngilizce→Türkçede ve ayar açıkken kullanılır.</summary>
    private bool PacksActive => settings.GamePacks && settings.SourceLanguage == "en" && settings.TargetLanguage == "tr" && services.GamePacks is not null;

    private void StartPacksAndPool()
    {
        // Paketler ilk altyazıyı bekletmesin diye açılışta arka planda yüklenir.
        if (services.GamePacks is { } packs)
            _ = Task.Run(() =>
            {
                packs.WarmUp();
                post(() => InstalledPacks = packs.Packs);
            });
        StartPackUpdates();
        if (services.Translations is { } translations)
        {
            translations.SetLanguage(settings.TargetLanguage);
            translations.SetEnabled(settings.SharePool);
        }
        if (services.Pool is not { } pool) return;
        pool.SetEnabled(settings.SharePool);
        // Dakikada bir ve ağ gelince denenir; sunucu onaylayana kadar satırlar diskte bekler.
        pool.StartBackground();
    }

    /// <summary>
    /// Paket sunucusu yapılandırıldıysa açılışta ve günde bir bakılır; PS5'te yeni bir oyun tanınınca da
    /// (<see cref="PackUpdater.GameCheckInterval"/>). Yeni paket inince paketler yeniden okunur.
    /// </summary>
    private void StartPackUpdates()
    {
        if (services.PackUpdates is not { } updater) return;
        var first = true;
        packTimer = new Timer(_ =>
        {
            _ = RefreshPacksAsync(updater, force: first);
            first = false;
        }, null, TimeSpan.Zero, PackUpdater.RefreshInterval);
    }

    private async Task RefreshPacksAsync(PackUpdater updater, bool force = false, TimeSpan? maxAge = null)
    {
        try
        {
            var result = await updater.RefreshAsync(force, maxAge: maxAge).ConfigureAwait(false);
            if (!result.Changed || services.GamePacks is not { } packs) return;
            packs.Reload();
            post(() => InstalledPacks = packs.Packs);
            SubtitleLog.Write("paketler güncellendi: " + string.Join(", ", result.Downloaded.Concat(result.Removed)));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or HttpRequestException)
        {
            // Sonraki bakışta yeniden denenir.
        }
    }

    /// <summary>PS5'e bağlanınca çalışan oyun okunmaya başlar, bağlantı gidince bırakılır (havuz satırı oyunsuz gider).</summary>
    private void UpdateGameProbe(bool connected)
    {
        if (services.Pool is null) return;
        if (!connected || console?.Host is not { } host)
        {
            gameProbe?.Cancel();
            gameProbe?.Dispose();
            gameProbe = null;
            gameSense.SetConsole(null);
            PublishGame();
            return;
        }
        if (gameProbe is not null) return;
        var cancel = new CancellationTokenSource();
        gameProbe = cancel;
        var token = cancel.Token;
        _ = Task.Run(async () =>
        {
            RunningGame? last = null;
            while (!token.IsCancellationRequested)
            {
                RunningGame? game;
                try { game = await services.RunningGameAsync(host).ConfigureAwait(false); }
                catch (Exception) { game = null; }
                // Bu arada bağlantı bittiyse oyun yazılmaz (bırakılan oyun geri gelmesin).
                if (token.IsCancellationRequested) break;
                gameSense.SetConsole(game);
                // Paket sunucusuna bakılması PublishGame'de.
                post(() => { if (!token.IsCancellationRequested) PublishGame(); });
                if (game is not null && game != last) SubtitleLog.Write($"PS5'te çalışan oyun: {game.Name ?? "?"} ({game.TitleId ?? "?"})");
                last = game;
                try { await Task.Delay(GameProbeInterval, token).ConfigureAwait(false); }
                catch (OperationCanceledException) { break; }
            }
        }, CancellationToken.None);
    }

    /// <summary>Nino: sunucunun çeviri havuzu bütün dillerde, kaynak İngilizceyken ve ortak havuz açıkken.</summary>
    private bool PoolTranslationsActive => settings.SharePool && settings.SourceLanguage == "en" && services.Translations is not null;

    /// <summary>Önce oyun paketi (yalnız İngilizce→Türkçe), sonra havuzdaki çeviri; ikisinde de yoksa motor çevirir.</summary>
    private void ConnectPacks(SubtitlePipeline target)
    {
        var active = PacksActive;
        // Havuzdaki çeviriler ortak havuz açıkken; havuz öncelikli oyunda (GTA 6) ayar kapalı olsa da.
        var store = settings.SourceLanguage == "en" ? services.Translations?.Store : null;
        target.PackLookup = active || store is not null ? text =>
        {
            var first = PoolFirstActive;
            // Havuz öncelikli oyunda (GTA 6) başka oyunların paketlerine bakılmaz: çeviri yalnız havuzdan (Claude).
            if (active && !first && services.FindInPacks(text) is { } found) return found;
            var pooled = PoolTranslationsActive || first ? store : null;
            // Havuzdaki çeviri sunucuda yapıldı; Türkçe düzeltmeleri (motorun içinde) ona uygulanmaz.
            return pooled?.Match(text) is { } translated ? new PackMatch(translated, [new SpokenLine(text, translated)]) : null;
        } : null;
    }

    /// <summary>Nino: oyunun havuzdaki çevirilerini oturum başlarken ve oyun değişince hemen, sonra dakikada bir indirir.</summary>
    private void StartTranslationSync()
    {
        StopTranslationSync();
        if (!PoolTranslationsActive || services.Translations is not { } translations) return;
        var cancel = new CancellationTokenSource();
        translationSync = cancel;
        var token = cancel.Token;
        _ = Task.Run(async () =>
        {
            await translations.SyncAsync(PoolGame(), force: true, token).ConfigureAwait(false);
            while (!token.IsCancellationRequested)
            {
                // Sunucuya "buradayım" (dakikada bir; ortak havuz kapalıysa gönderilmez).
                await translations.PingAsync(PoolGame(), token).ConfigureAwait(false);
                try { await Task.Delay(TimeSpan.FromSeconds(60), token).ConfigureAwait(false); }
                catch (OperationCanceledException) { return; }
                await translations.SyncAsync(PoolGame(), token: token).ConfigureAwait(false);
            }
        }, CancellationToken.None);
    }

    private void StopTranslationSync()
    {
        translationSync?.Cancel();
        translationSync = null;
    }

    /// <summary>Paketten tanınan oyun; yoksa PS5'in bildirdiği ya da kullanıcının seçtiği oyun.</summary>
    private string? PoolGame() => services.GamePacks?.SearchScope ?? gameSense.Current?.Name;

    /// <summary>Gelişmiş ayarlardaki bekleme süreleri (0–2 sn).</summary>
    private void ApplyWaits(SubtitlePipeline target)
    {
        target.PackWait = Math.Clamp(settings.MisreadWaitMs, 0, 2000);
        target.CleanWait = Math.Clamp(settings.PartialWaitMs, 0, 2000);
    }

    /// <summary>
    /// Pakette olmayan İngilizce satır havuza önerilir (paketler kapalıysa da yalnız hiçbir pakette olmayanlar). Nino: ortak
    /// havuz açıksa sunucuya da sorulur; sunucu o an çevirir (Claude), satır hâlâ ekrandaysa cihazın çevirisinin yerine konur.
    /// </summary>
    private void OfferToPool(SubtitlePipeline target, string text)
    {
        if (settings.SourceLanguage != "en") return;
        if (!PacksActive && !PoolFirstActive && services.FindInPacks(text) is not null) return;
        services.Pool?.Offer(text, services.GamePacks?.SearchScope);
        // Havuz öncelikli oyunda ortak havuz kapalı olsa da sorulur; çevirmen aynı isteği bekler (aynı satır iki kez
        // sorulmaz), süresinde gelmeyen çeviri de gelince ekrandakinin yerine konur.
        if (!(PoolTranslationsActive || PoolFirstActive) || services.Translations is not { } translations) return;
        var context = recentLines.Add(text);
        var game = PoolFirstActive ? PoolFirstGame() : PoolGame();
        _ = Task.Run(async () =>
        {
            if (await translations.TranslateAsync(text, context, game).ConfigureAwait(false) is { } better) target.Upgrade(text, better);
        }, CancellationToken.None);
    }

    // --- İç işleyiş ---

    /// <summary>Okuma hattını güncel dillerle (yeniden) kurar.</summary>
    private void MakePipeline()
    {
        pipeline?.Reset();
        pipeline = null;
        // Ek bölge okuyucusu da yeni dil ve motorla yeniden kurulur.
        regionWatcher?.Reset();
        regionWatcher = null;
        // Eski hatta süren okuma beklenmez; yeni hat ilk karesini hemen alır.
        frameGate.Reset();
        ActiveSourceLanguage = settings.SourceLanguage;
        var reader = services.MakeReader(settings.SourceLanguage);
        activeReader = reader;
        OcrMissing = reader is null || !services.HasOcrLanguage(settings.SourceLanguage);
        if (reader is null) return;
        var scheduler = new ReadScheduler(maxReuse: settings.FastSubtitleDetection
            ? ReadScheduler.FastMaxReuse : ReadScheduler.DefaultMaxReuse);
        var built = new SubtitlePipeline(reader, MakeTranslator(), server, scheduler) { ShowSpeakerNames = settings.ShowSpeakerNames };
        built.MetricsReady += metrics =>
        {
            HealthRecorder.Shared.Line(metrics.TranslationMs);
            post(() => MetricsText = metrics.Summary(text));
        };
        built.PairShown += (source, translation) =>
        {
            var box = built.LastBox;
            var origin = built.LastOrigin == "paket" ? LineOrigin.Pack : LineOrigin.Engine;
            // Satır yalnız tek bir pakette bulunduysa o pakete bir oy: son 20 satırın 5'i aynı paketten gelince oyun odur.
            var hit = services.GamePacks?.TakeDistinctiveHit();
            var recognised = gameSense.NoteLine(origin == LineOrigin.Pack ? hit?.Id : null, origin == LineOrigin.Pack ? hit?.Title : null);
            post(() =>
            {
                if (recognised)
                {
                    AskingGame = false;
                    PublishGame();
                }
                LastSource = source;
                LastTranslation = translation;
                if (box is not null) lastSubtitleBox = box;
                AddToHistory(source, translation, origin);
            });
        };
        // Model bu arada inmiş olabilir; her çeviri sonucu durumu günceller.
        built.TranslationResult += error => post(() => TranslatorStatus = error ?? TranslatorStatus.Ready);
        built.SpeechReady += lines => post(() => Speak(lines));
        built.PackMissed += text => OfferToPool(built, text);
        built.Log = SubtitleLog.Write;
        built.PackName = () => services.GamePacks?.SearchScope;
        ConnectPacks(built);
        ApplyWaits(built);
        OnlineIssue = null;
        pipeline = built;
        UpdateRegionWatcher();
        StartTranslationSync();
    }

    /// <summary>Sürekli okunan ek bölgeleri okuyup çeviren; çeviri sürerken ve en az bir bölge sürekli okunurken var.</summary>
    private RegionWatcher? regionWatcher;

    /// <summary>
    /// Ek bölge okuyucusu gerekiyorsa kurulur, gerekmiyorsa kaldırılır (kutuları TV'den kalkar). Kendi yazı tanıma motoru
    /// vardır: aynı motor iki okumayı birden yapamaz, ek bölge okuması altyazıyı bekletmesin. Paketler altyazıyla aynıdır;
    /// ek bölge satırları havuza önerilmez.
    /// </summary>
    private void UpdateRegionWatcher()
    {
        if (pipeline is null || subtitlesPaused || settings.WatchedAreas().Count == 0)
        {
            regionWatcher?.Reset();
            regionWatcher = null;
            return;
        }
        if (regionWatcher is null)
        {
            if (services.MakeReader(settings.SourceLanguage) is not { } reader) return;
            regionWatcher = new RegionWatcher(reader, MakeTranslator(), server) { Log = SubtitleLog.Write };
        }
        regionWatcher.PackLookup = PacksActive ? services.FindInPacks : null;
    }

    // --- Geçmiş ---

    /// <summary>Gösterilen satır geçmişe eklenir (arayüz iş parçacığında) ve dosyaya yazılır.</summary>
    private void AddToHistory(string source, string translation, LineOrigin origin)
    {
        if (!history.Add(source, translation, origin)) return;
        Changed(nameof(History));
        SaveHistory();
    }

    /// <summary>Geçmişi siler (dosyadaki de boşalır).</summary>
    public void ClearHistory()
    {
        history.Clear();
        Changed(nameof(History));
        SaveHistory();
    }

    /// <summary>Bekleyen geçmiş yazmalarının bitmesini bekler (testler ve kapanış için).</summary>
    public Task WaitForHistoryAsync() => historySave;

    /// <summary>
    /// Geçmişin kopyası arayüzü bekletmeden, önceki yazmanın ardından dosyaya yazılır. Yazılamazsa (dosya kilitli) bir
    /// sonraki satırda yeniden denenir.
    /// </summary>
    private void SaveHistory()
    {
        if (services.HistoryFile is not { } file) return;
        var copy = history.Copy();
        historySave = historySave.ContinueWith(_ =>
        {
            try { copy.Save(file); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }, CancellationToken.None, TaskContinuationOptions.None, TaskScheduler.Default);
    }

    /// <summary>Nino: Arapça hedefte Arap harfli satır (PS5'in Arapça menüsü) çevirmene gitmez.</summary>
    private ITextTranslator MakeTranslator() => new TargetScriptGuard(MakePoolFirst(MakeBaseTranslator()), settings.TargetLanguage);

    /// <summary>
    /// Nino: havuz öncelikli oyunda (sunucunun listesi, varsayılan GTA 6) çeviri yalnız havuzdan, gelmezse ücretsiz
    /// yerel çeviriden; kullanıcının anahtarlı motoru çağrılmaz. Ortak havuz ayarı kapalı olsa da (kullanıcı kararı).
    /// </summary>
    private ITextTranslator MakePoolFirst(ITextTranslator engine)
    {
        if (services.Translations is not { } translations) return engine;
        return new PoolFirstTranslator(engine, MakeLocalTranslator(), () => PoolFirstActive,
            (line, token) => translations.TranslateFirstAsync(line, recentLines.Before(line), PoolFirstGame(), token))
        {
            Log = SubtitleLog.Write,
        };
    }

    /// <summary>Oynanan oyun havuz öncelikli mi (kaynak İngilizce, sunucu açık, oyun listede).</summary>
    private bool PoolFirstActive => settings.SourceLanguage == "en" && services.Translations?.IsPoolFirst(PoolFirstGame()) == true;

    /// Nino: havuza sorulacak oyun; paketten tahmin edilen oyun (benzer satırlı başka oyunun paketi) PS5'ten, kullanıcıdan
    /// ya da ekrandan bilinen havuz öncelikli oyunun (GTA 6) önüne geçmez.
    private string? PoolFirstGame()
    {
        var known = gameSense.Current?.Name;
        var scope = services.GamePacks?.SearchScope;
        var first = services.Translations?.CurrentPoolFirst;
        if (first is not null && first.Contains(known)) return known;
        if (first is not null && first.Contains(scope)) return scope;
        return scope ?? known;
    }

    private ITextTranslator MakeBaseTranslator()
    {
        var local = MakeLocalTranslator();
        // Açılamayan ücretsiz motor yedek olamaz; çevrimiçi motor çeviremeyince satır yeniden denenir.
        var fallback = local is UnavailableTranslator || services.Translation.EngineFailed ? null : local;
        var engine = settings.OnlineEngine;
        if (!OnlineTranslationActive || engine.StoreKey() is not { } storeKey) return local;
        // Oynanan oyunun adı modele bağlam olarak gider, önbellek de oyuna göre ayrılır. Ad kararlı oyundur (GameSense:
        // PS5'in bildirdiği, kullanıcının seçtiği ya da son 20 satırın 5'i aynı paketten gelince o paketin oyunu); son
        // eşleşen paket değil, yoksa tek bir ortak satır adı başka oyuna geçirirdi (#27). Oyun bilinmiyorsa ad gitmez.
        Func<string?> game = () => gameSense.Current?.Name;
        ITextTranslator? online;
        if (engine == TranslationEngine.Local && settings.LocalAiServer is { } server)
        {
            // Yerel modelin anahtarı isteğe bağlıdır; önbellekte sunucu ve model ayrı tutulur.
            online = services.MakeLocalAiTranslator(server, store.Load<string>(storeKey) ?? "", fallback, game, settings.TargetLanguage);
        }
        else
        {
            if (store.Load<string>(storeKey) is not { Length: > 0 } key) return local;
            online = engine.Provider() is { } provider
                ? services.MakeAiTranslator(provider, key, provider.Model(settings.ModelFor(provider)).Id, fallback, game, settings.TargetLanguage)
                : services.MakeOnlineTranslator(key, fallback, settings.TargetLanguage);
        }
        if (online is null) return local;
        // Hizmet çeviremeyince ana ekranda uyarı çıkar; düzelince kalkar.
        if (online is IOnlineTranslator reporting) reporting.FailureChanged += state => post(() => OnlineIssue = state);
        return online;
    }

    private ITextTranslator MakeLocalTranslator()
    {
        var translation = services.Translation;
        var (source, target) = (settings.SourceLanguage, settings.TargetLanguage);
        if (!translation.IsSupported(source, target)) return new UnavailableTranslator(TranslatorStatus.Unsupported);
        if (!translation.IsInstalled(source, target)) return new UnavailableTranslator(TranslatorStatus.NeedsDownload);
        if (translation.EngineFailed) return new UnavailableTranslator(TranslatorStatus.EngineFailed);
        try
        {
            return translation.Create(source, target);
        }
        catch (Exception error)
        {
            // Çeviriyi başlatma, motor açılamadı diye yarıda kalmasın: oyun paketleri ve çevrimiçi motorlar çalışır,
            // ana ekranda uyarı çıkar.
            RemotePlayLog.Note($"Ücretsiz çeviri motoru açılamadı: {error.GetType().Name}: {error.Message}");
            if (!OnlineTranslationActive) post(() => TranslatorStatus = TranslatorStatus.EngineFailed);
            return new UnavailableTranslator(TranslatorStatus.EngineFailed);
        }
    }

    /// <summary>Çevrimiçi çeviri İngilizceden listedeki dillere, seçili motor hazırsa (DeepL yalnız desteklediği dillerde) açılır.</summary>
    public bool OnlineTranslationActive =>
        settings.OnlineTranslation && settings.SourceLanguage == "en" && TargetLanguage.IsSupported(settings.TargetLanguage)
        && (settings.OnlineEngine != TranslationEngine.DeepL || TargetLanguage.DeepLSupports(settings.TargetLanguage))
        && IsReady(settings.OnlineEngine);

    /// <summary>
    /// Motor kullanılabilir mi: bulut motorlarında anahtar kayıtlıdır; yerel modelde anahtar gerekmez, adres ve model adı
    /// geçerli olmalıdır. Sunucu kapalıysa satırlar ücretsiz çeviriyle gelir ve ana ekranda uyarı çıkar.
    /// </summary>
    public bool IsReady(TranslationEngine engine) =>
        engine == TranslationEngine.Local ? settings.LocalAiServer is not null : HasKey(engine);

    /// <summary>Bu motorun anahtarı kayıtlı mı (anahtarın kendisi arayüze hiç dönmez).</summary>
    public bool HasKey(TranslationEngine engine) => engine.StoreKey() is { } storeKey && store.Load<string>(storeKey) is { Length: > 0 };

    /// <summary>Kayıtlı bir DeepL anahtarı var mı.</summary>
    public bool HasDeepLKey => HasKey(TranslationEngine.DeepL);

    /// <summary>Anahtar denenir; geçerliyse (kotası bitmiş olsa da) şifreli depoya yazılır ve DeepL seçilir.</summary>
    public async Task<OnlineKeyCheck> SetDeepLKeyAsync(string key)
    {
        key = key.Trim();
        var check = await services.CheckOnlineKeyAsync(key);
        if (check.State is OnlineKeyState.Valid or OnlineKeyState.QuotaExceeded) SaveKey(TranslationEngine.DeepL, key);
        return check;
    }

    /// <summary>Kayıtlı anahtarın bu ayki kullanımı.</summary>
    public Task<OnlineKeyCheck> CheckDeepLKeyAsync() =>
        store.Load<string>(StoreKeys.DeepLKey) is { Length: > 0 } key ? services.CheckOnlineKeyAsync(key)
            : Task.FromResult(new OnlineKeyCheck(OnlineKeyState.Invalid));

    public void RemoveDeepLKey() => RemoveKey(TranslationEngine.DeepL);

    /// <summary>
    /// Yapay zekâ anahtarı örnek bir satırla denenir. Anahtar kabul edildiyse (bakiye bitmiş ya da model adı yanlış olsa
    /// da) şifreli depoya yazılır ve bu motor seçilir.
    /// </summary>
    public async Task<AiTestResult> SetAiKeyAsync(AiProvider provider, string key)
    {
        key = key.Trim();
        var result = await services.TestAiKeyAsync(provider, key, provider.Model(settings.ModelFor(provider)).Id);
        if (result.State is OnlineKeyState.Valid or OnlineKeyState.QuotaExceeded or OnlineKeyState.ModelRejected)
            SaveKey(provider.Engine(), key);
        return result;
    }

    /// <summary>Kayıtlı anahtar ve modelle örnek satırı çevirir (ayarlardaki "Dene").</summary>
    public Task<AiTestResult> TestAiKeyAsync(AiProvider provider) =>
        provider.Engine().StoreKey() is { } storeKey && store.Load<string>(storeKey) is { Length: > 0 } key
            ? services.TestAiKeyAsync(provider, key, provider.Model(settings.ModelFor(provider)).Id)
            : Task.FromResult(new AiTestResult(OnlineKeyState.Invalid));

    /// <summary>
    /// Ayarlardaki "Bağlantıyı dene": yerel model sunucusuna örnek satırı gönderir. <paramref name="typed"/> yazıldıysa o,
    /// yoksa kayıtlı anahtar kullanılır; yazılan anahtar sunucu kabul ettiyse şifreli depoya yazılır. Adres geçersizse
    /// sunucuya ulaşılamadı sayılır.
    /// </summary>
    public async Task<AiTestResult> TestLocalAiAsync(string typed = "")
    {
        if (settings.LocalAiServer is not { } server) return new AiTestResult(OnlineKeyState.Unreachable);
        typed = typed.Trim();
        var key = typed.Length > 0 ? typed : store.Load<string>(StoreKeys.LocalAiKey) ?? "";
        var result = await services.TestLocalAiAsync(server, key);
        if (typed.Length > 0 && result.State is OnlineKeyState.Valid or OnlineKeyState.QuotaExceeded or OnlineKeyState.ModelRejected)
            SaveKey(TranslationEngine.Local, typed);
        return result;
    }

    public void RemoveKey(TranslationEngine engine)
    {
        if (engine.StoreKey() is not { } storeKey) return;
        store.Remove(storeKey);
        if (engine == TranslationEngine.Local)
        {
            // Yerel modelin anahtarı isteğe bağlıdır: anahtarsız çeviri sürer, hat anahtarsız yeniden kurulur.
            if (settings.Engine == engine && isRunning) MakePipeline();
            return;
        }
        Changed(nameof(HasDeepLKey), nameof(UsesFreeGemini));
        if (settings.Engine == engine) Settings = settings.WithEngine(TranslationEngine.Free);
        RefreshTranslatorStatus();
    }

    private void SaveKey(TranslationEngine engine, string key)
    {
        if (engine.StoreKey() is not { } storeKey) return;
        store.Save(storeKey, key);
        Changed(nameof(HasDeepLKey));
        // Motor zaten seçiliydi, anahtar yeni geldi: hat yeni anahtarla kurulsun.
        if (settings.Engine == engine && isRunning) MakePipeline();
        else Settings = settings.WithEngine(engine);
        Changed(nameof(UsesFreeGemini));
        RefreshTranslatorStatus();
    }

    private void RefreshTranslatorStatus()
    {
        var translation = services.Translation;
        TranslatorStatus = OnlineTranslationActive ? TranslatorStatus.Ready
            : !translation.IsSupported(settings.SourceLanguage, settings.TargetLanguage) ? TranslatorStatus.Unsupported
            : !translation.IsInstalled(settings.SourceLanguage, settings.TargetLanguage) ? TranslatorStatus.NeedsDownload
            : translation.EngineFailed ? TranslatorStatus.EngineFailed
            : TranslatorStatus.Ready;
    }

    /// <summary>PS5'in adresi değişti: sonraki açılışlar yeni adresle başlasın.</summary>
    private void ConsoleMoved(RegisteredConsole moved)
    {
        if (console is null) return;
        console = moved;
        store.Save(StoreKeys.Console, moved);
        Changed(nameof(Console), nameof(Ps5StatusText));
    }

    private void SessionStateChanged(SessionState state)
    {
        // Altyazı günlüğünde yalnız durumun türü (adres ve ayrıntı remoteplay.log'da).
        // Nino: oyun penceresi durumu ayrıca yazılır (bkz. WindowStatusChanged); PS5 bağlantısı sayılmaz.
        if (state.Phase != SessionState.Phase && settings.VideoSource == VideoSource.Ps5)
        {
            SubtitleLog.Write(state.Phase switch
            {
                SessionPhase.Connecting => $"{ConsoleTitle}: bağlanıyor",
                SessionPhase.Streaming => $"{ConsoleTitle}: bağlandı",
                _ => $"{ConsoleTitle}: bağlantı yok",
            });
            switch (state.Phase)
            {
                case SessionPhase.Connecting: HealthRecorder.Shared.Connecting(); break;
                case SessionPhase.Streaming: HealthRecorder.Shared.Streaming(); break;
                default:
                    // Kullanıcının durdurması kopma sayılmaz.
                    var kind = state.Reason?.Kind ?? DisconnectKind.Stopped;
                    HealthRecorder.Shared.Disconnected(kind == DisconnectKind.Stopped ? null : kind.ToString());
                    break;
            }
        }
        SessionState = state;
        UpdateTroubleClocks();
        if (!IsXbox) UpdateGameProbe(state.Phase == SessionPhase.Streaming);
        else if (state.Phase == SessionPhase.Streaming && !xboxNameChecked)
        {
            xboxNameChecked = true;
            _ = RefreshXboxNameAsync();
        }
        // Bağlantı koptuysa TV'de eski altyazı kalmasın.
        if (state.Phase == SessionPhase.Disconnected)
        {
            pipeline?.Reset();
            regionWatcher?.Reset();
            server.Clear();
            dubber?.Stop();
        }
    }

    /// <summary>
    /// Kare iş parçacığında çağrılır. async void olduğu için buradan hiçbir hata kaçmamalı: kaçan hata eşzamanlama
    /// bağlamı olmayan iş parçacığında süreci kapatırdı.
    /// </summary>
    private async void HandleFrame(Frame frame)
    {
        // Gecikme karenin geldiği andan ölçülür (hattın varsayılan saatiyle aynı saat).
        var arrived = Environment.TickCount64;
        try
        {
            post(() =>
            {
                LastFrame = frame;
                IdentifyGameIfNeeded(frame);
            });
            // Duraklatıldıysa kare yalnız ek bölgeler ve serbest alan için saklanır; altyazı okunmaz.
            if (subtitlesPaused) return;
            // Önceki kare hâlâ işleniyorsa bu kare atlanır; okuma kareleri biriktirmez.
            var current = pipeline;
            if (current is null) return;
            // Ek bölgeler ayrı ve seyrek okunur (saniyede bir, kendi okuyucusuyla); altyazı okumasını beklemez, onu bekletmez.
            regionWatcher?.Offer(frame, settings.WatchedAreas());
            var entry = frameGate.TryEnter(Environment.TickCount64);
            if (entry.Kind == FrameGate.EntryKind.Stuck)
            {
                // Okuma bitmedi: önizleme canlıyken altyazı hiç gelmiyordu ve ancak uygulamayı kapatıp açmak düzeltiyordu.
                SubtitleLog.Write($"okuma {entry.Ms} ms'dir bitmedi; okuma hattı yeniden kuruldu");
                post(MakePipeline);
                return;
            }
            if (entry.Kind != FrameGate.EntryKind.Enter) return;
            try
            {
                await current.ProcessAsync(frame, settings.Region, arrived);
            }
            finally
            {
                frameGate.Leave(entry.Token);
            }
        }
        catch
        {
            // Tek bir karenin okunamaması akışı durdurmaz.
        }
    }

    private async Task StartServerAsync()
    {
        if (serverStarted) return;
        try
        {
            ServerPort = await server.StartAsync();
        }
        catch (SocketException)
        {
            // 8787 başka bir uygulamada; TV'ye adres her seferinde bildirildiği için herhangi bir boş port olur.
            DetachServer();
            server = new SubtitleServer(0);
            AttachServer();
            ServerPort = await server.StartAsync();
        }
        serverStarted = true;
    }

    private void OnClientsChanged(int count) => post(() =>
    {
        TvClients = count;
        UpdateTroubleClocks();
    });

    /// <summary>TV ile aynı ağdaki bilgisayar adresi.</summary>
    private string ServerAddress(LgTv target) => $"http://{LocalAddress(target.Host) ?? "127.0.0.1"}:{ServerPort}";

    /// <summary>
    /// <paramref name="near"/> adresine (TV) ulaşan bu bilgisayar adresi; TV adresi bilinmiyorsa (null ya da geçersiz)
    /// Wi-Fi/Ethernet adresi. TV adresi biliniyorsa işletim sisteminin TV'ye çıkacağı bağdaştırıcının adresi önce gelir
    /// (birden çok bağdaştırıcıda doğru kaynak adres, #343). VPN ve sanal bağdaştırıcılar ancak başka adres yoksa seçilir
    /// (<see cref="LocalNetwork.ChooseComputerAddress(IReadOnlyList{LocalNetwork.AdapterAddress}, IPAddress?, IPAddress?)"/>).
    /// </summary>
    public static string? LocalAddress(string? near)
    {
        IPAddress? target = IPAddress.TryParse(near, out var parsed) && parsed.AddressFamily == AddressFamily.InterNetwork ? parsed : null;
        var route = target is null ? null : LocalNetwork.RouteSourceAddress(target);
        return LocalNetwork.ChooseComputerAddress(LocalNetwork.Ipv4Adapters(), target, route);
    }

    // --- Windows Güvenlik Duvarı ---

    /// <summary>PS5 bu kadar süre "Yeniden bağlanıyor…" kalırsa güvenlik duvarı kuralına bakılır.</summary>
    public static readonly TimeSpan Ps5TroubleDelay = TimeSpan.FromSeconds(20);
    /// <summary>TV uygulaması bu kadar süre bağlanmazsa güvenlik duvarı kuralına bakılır.</summary>
    public static readonly TimeSpan TvWaitDelay = TimeSpan.FromSeconds(60);

    private FirewallPrompt firewallPrompt;
    /// <summary>Bu çeviri oturumunda kural bulundu; her denetimde kurallar yeniden taranmaz.</summary>
    private bool firewallRuleSeen;
    private bool checkingFirewall;
    private DateTime? ps5TroubleSince;
    private DateTime? tvWaitingSince;

    /// <summary>Güvenlik duvarı kartı ya da eşleştirme adımındaki düğme; yalnız kural eksikken önerilir.</summary>
    public FirewallPrompt FirewallPrompt { get => firewallPrompt; private set => Set(ref firewallPrompt, value); }

    /// <summary>Zaman (testlerde ileri sarılır).</summary>
    public Func<DateTime> Clock { get; set; } = () => DateTime.UtcNow;

    /// <summary>
    /// Ana ekran birkaç saniyede bir çağırır: PS5 20 saniyedir yeniden bağlanıyorsa ya da TV 60 saniyedir bağlanmadıysa ve
    /// güvenlik duvarında CouchSubs'a izin yoksa kart önerilir. İkisi de bağlanınca kart kalkar.
    /// </summary>
    public async Task CheckConnectionsAsync()
    {
        UpdateTroubleClocks();
        if (!isRunning || services.Firewall is not { } firewall) return;
        if (ps5TroubleSince is null && tvWaitingSince is null)
        {
            ClearFirewallPrompt();
            return;
        }
        var now = Clock();
        var stuck = now - ps5TroubleSince >= Ps5TroubleDelay || now - tvWaitingSince >= TvWaitDelay;
        if (!stuck || firewallPrompt != FirewallPrompt.None || firewallRuleSeen || checkingFirewall) return;
        checkingFirewall = true;
        try
        {
            var prompt = await FirewallProblemAsync(firewall);
            if (!isRunning) return;
            if (prompt == FirewallPrompt.None) firewallRuleSeen = true;
            else FirewallPrompt = prompt;
        }
        finally
        {
            checkingFirewall = false;
        }
    }

    /// <summary>
    /// Kuralı yönetici izniyle ekler. Çeviri sürüyorsa PS5 ve TV hemen yeniden denenir; eşleştirmede kullanıcı yeni
    /// kodla yeniden bağlanır.
    /// </summary>
    public async Task<bool> AllowThroughFirewallAsync()
    {
        if (services.Firewall is not { } firewall || firewallPrompt == FirewallPrompt.Working) return false;
        FirewallPrompt = FirewallPrompt.Working;
        bool added;
        try { added = await firewall.AddRuleAsync(); }
        catch (Exception) { added = false; }
        FirewallPrompt = added ? FirewallPrompt.Allowed : FirewallPrompt.Failed;
        if (!added) return false;
        firewallRuleSeen = true;
        if (isRunning)
        {
            session?.ReconnectNow();
            keeper?.Reconnect();
        }
        return true;
    }

    /// <summary>Ayarlar: güvenlik duvarı desteklenmiyorsa null; yoksa (kural var mı, ağ "Ortak" mı).</summary>
    public async Task<(bool HasRule, bool PublicNetwork)?> GetFirewallStateAsync()
    {
        if (services.Firewall is not { } firewall) return null;
        var hasRule = await HasFirewallRuleAsync(firewall);
        bool publicNetwork;
        try { publicNetwork = await Task.Run(firewall.HasPublicNetwork); }
        catch (Exception) { publicNetwork = false; }
        return (hasRule, publicNetwork);
    }

    /// <summary>Eşleştirme başarısız oldu: kural eksikse düğme önerilir.</summary>
    private async Task OfferFirewallAsync()
    {
        if (services.Firewall is not { } firewall || firewallPrompt == FirewallPrompt.Working) return;
        FirewallPrompt = await FirewallProblemAsync(firewall);
    }

    /// <summary>
    /// Bağlantı takıldığında gösterilecek kart. İzin yalnız Özel ağda geçerlidir: kural olsa da bilgisayarın ağı "Ortak"
    /// ise TV ve PS5 yine engellenir. Eskiden kural varsa hiçbir şey gösterilmiyor, kullanıcı sebebini göremiyordu.
    /// </summary>
    private static async Task<FirewallPrompt> FirewallProblemAsync(IFirewall firewall)
    {
        if (!await HasFirewallRuleAsync(firewall)) return FirewallPrompt.Offer;
        try { return await Task.Run(firewall.HasPublicNetwork) ? FirewallPrompt.PublicNetwork : FirewallPrompt.None; }
        catch (Exception) { return FirewallPrompt.None; }
    }

    /// <summary>Kurallar arka planda taranır; okunamayan izin verilmiş gibi gösterilmez.</summary>
    private static async Task<bool> HasFirewallRuleAsync(IFirewall firewall)
    {
        try { return await Task.Run(firewall.HasRule); }
        catch (Exception) { return false; }
    }

    private void ClearFirewallPrompt()
    {
        if (firewallPrompt != FirewallPrompt.Working) FirewallPrompt = FirewallPrompt.None;
    }

    /// <summary>
    /// PS5'in ve TV'nin ne zamandan beri bağlanamadığı. PS5 uykudaysa, başka cihazdaysa ya da bağlantıyı reddettiyse
    /// sorun güvenlik duvarı değildir; sayılmaz.
    /// </summary>
    private void UpdateTroubleClocks()
    {
        var now = Clock();
        // Nino: oyun penceresinden ya da yakalama kartından okunurken PS5'e bağlanılmaz; güvenlik duvarı önerisi çıkmaz.
        var ps5Trouble = !IsXbox && isRunning && settings.VideoSource == VideoSource.Ps5 && sessionState.Phase != SessionPhase.Streaming && sessionState.Reason?.Kind is not
            (DisconnectKind.ConsoleAsleep or DisconnectKind.InUse or DisconnectKind.Refused or DisconnectKind.LoginPasscode
             or DisconnectKind.LoginPasscodeIncorrect or DisconnectKind.RegistrationInvalid or DisconnectKind.Rejected
             or DisconnectKind.RemotePlayDisabled);
        ps5TroubleSince = ps5Trouble ? ps5TroubleSince ?? now : null;
        // Altyazı TV'ye gitmiyorsa ya da TV yoksa TV beklenmez.
        tvWaitingSince = isRunning && ShowsOnTv && HasTv && tvClients == 0 ? tvWaitingSince ?? now : null;
    }

    // --- Uygulama güncellemesi ---

    /// <summary>GitHub'da daha yeni sürüm varsa numarası.</summary>
    public string? UpdateVersion { get => updateVersion; private set => Set(ref updateVersion, value); }
    public bool Updating { get => updating; private set => Set(ref updating, value); }
    public double UpdateProgress { get => updateProgress; private set => Set(ref updateProgress, value); }
    public string? UpdateError { get => updateError; private set => Set(ref updateError, value); }
    /// <summary>Kurulum dosyasıyla kurulduysa tek tıkla güncellenir; değilse sürüm sayfası açılır.</summary>
    public bool CanUpdateItself => services.Updater?.CanUpdateItself == true;

    /// <summary>Sürüm başına kendiliğinden kurulum denemeleri (yeniden başlatma döngüsüne girmesin).</summary>
    private AutoUpdateLog AutoUpdates => autoUpdates ??= new AutoUpdateLog(services.AutoUpdateFile);
    private AutoUpdateLog? autoUpdates;
    /// <summary>Bu açılışta yarıda kalan kendiliğinden indirmeler; üç saatlik denetim sonsuza dek yeniden denemesin.</summary>
    private int autoDownloadFailures;
    private const int MaxAutoDownloadFailures = 3;
    /// <summary>Uygulama kapanıyor (<see cref="Dispose"/>): yeni kurulum başlatılmaz.</summary>
    private bool closing;

    private bool CanAutoInstall(string version) =>
        !AutoUpdates.Exhausted(version) && autoDownloadFailures < MaxAutoDownloadFailures;

    /// <summary>Nino: yeni sürüm sorulmadan kurulur; çeviri sürüyorsa oyun bölünmesin diye çeviri durunca.</summary>
    private bool autoInstallPending;
    private bool updateLoopStarted;

    /// <summary>Açılışta ve sonra üç saatte bir; ağ yoksa sessizce geçer. Yeni sürüm bulunursa kendiliğinden kurulur.</summary>
    public async Task CheckForUpdateAsync()
    {
        if (services.Updater is not { } updater) return;
        try { UpdateVersion = await updater.CheckAsync(); }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or IOException or InvalidOperationException) { }
        // Deneme, kurulum gerçekten başlarken sayılır (InstallUpdateAsync): yarıda kalan indirme sonraki açılışta ya da üç
        // saat sonra yeniden denenir. Kurulum başladığı hâlde sürüm değişmediyse sürüm başına AutoUpdateLog.MaxAttempts
        // denemeden sonra yalnız düğme kalır, döngüye girmez.
        if (!closing && UpdateVersion is { } version && updater.CanUpdateItself && CanAutoInstall(version))
        {
            if (IsRunning) autoInstallPending = true;
            else await InstallUpdateAsync(automatic: true);
        }
        if (!updateLoopStarted)
        {
            updateLoopStarted = true;
            _ = Task.Run(async () =>
            {
                while (true)
                {
                    await Task.Delay(TimeSpan.FromHours(3));
                    post(() => _ = CheckForUpdateAsync());
                }
            });
        }
    }

    /// <summary>"Güncelle" düğmesi.</summary>
    public Task InstallUpdateAsync() => InstallUpdateAsync(automatic: false);

    private async Task InstallUpdateAsync(bool automatic)
    {
        if (services.Updater is not { } updater || updating || (automatic && closing)) return;
        if (!updater.CanUpdateItself)
        {
            OpenInBrowser(updater.DownloadPage);
            return;
        }
        // Aşağıdaki Stop() bekleyen kendiliğinden kurulumu ikinci kez sıraya almasın.
        autoInstallPending = false;
        Updating = true;
        UpdateError = null;
        var version = UpdateVersion;
        var applying = false;
        try
        {
            // Çeviri sürüyorsa önce durur; uygulama güncellenip yeniden açılır.
            Stop();
            await updater.InstallAsync(new ImmediateProgress(value => post(() => UpdateProgress = value)), () =>
            {
                // İndirme bitti, kurulum başlıyor: deneme şimdi sayılır. Sayaç yazılamıyorsa kendiliğinden kurulmaz
                // (kurulum sürümü değiştirmezse her açılışta yeniden başlar ve bunu durduracak kayıt olmazdı).
                applying = true;
                if (version is not null && !AutoUpdates.Record(version) && automatic)
                    throw new IOException("Güncelleme denemesi kaydedilemedi; kurulum kendiliğinden başlatılmadı.");
            });
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or IOException or InvalidOperationException
                                          or UnauthorizedAccessException)
        {
            UpdateError = error.Message;
            if (automatic && !applying) autoDownloadFailures++;
        }
        finally
        {
            Updating = false;
        }
    }

    // --- Türkçe dublaj ---

    /// <summary>Bu derlemede dublaj var mı (ses motoru uygulamayla geliyor mu).</summary>
    public bool DubbingAvailable => services.Dubbing is not null || services.FastDubbing is not null;
    public bool FastDubbingAvailable => services.FastDubbing is not null;
    /// <summary>Ayarlarda seçili motor; hızlı ses yoksa doğal sese düşer.</summary>
    private IDubbingModel? ActiveDubbing =>
        settings.Dubbing.Engine == DubbingEngine.Fast && services.FastDubbing is { } fast ? fast : services.Dubbing;
    public bool DubbingInstalled => ActiveDubbing?.IsInstalled == true;
    public long DubbingDownloadBytes => services.Dubbing?.DownloadBytes ?? 0;
    public bool DubbingDownloading { get => dubbingDownloading; private set => Set(ref dubbingDownloading, value); }
    public double DubbingProgress { get => dubbingProgress; private set => Set(ref dubbingProgress, value); }
    public string? DubbingError { get => dubbingError; private set => Set(ref dubbingError, value); }

    /// <summary>Ses modelini indirir (ilk kullanımda bir kez, ~440 MB).</summary>
    public async Task DownloadDubbingAsync()
    {
        if (services.Dubbing is not { } model || dubbingDownloading || model.IsInstalled) return;
        DubbingDownloading = true;
        DubbingError = null;
        try
        {
            await Task.Run(() => model.DownloadAsync(new ImmediateProgress(value => post(() => DubbingProgress = value)), CancellationToken.None));
            if (DubbingActive && isRunning) MakeDubber()?.Prepare();
        }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidDataException or TaskCanceledException
                                          or UnauthorizedAccessException)
        {
            DubbingError = error.Message;
        }
        finally
        {
            DubbingDownloading = false;
            Changed(nameof(DubbingInstalled));
        }
    }

    /// <summary>Ayarlardaki "Dinle": sesi bilgisayardan çalar.</summary>
    public async Task PreviewVoiceAsync(DubbingVoice voice)
    {
        if (!DubbingInstalled) return;
        DubbingError = null;
        try { await StartServerAsync(); } catch (SocketException) { return; }
        MakeDubber()?.Preview(voice);
    }

    public void AssignVoice(DubbingVoice voice, string name)
    {
        var cast = settings.Dubbing.Cast.Copy();
        cast.Assign(voice, name);
        Settings = settings with { Dubbing = settings.Dubbing with { Cast = cast } };
    }

    private Dubber? MakeDubber()
    {
        if (dubber is not null) return dubber;
        if (ActiveDubbing is not { } model || services.Audio is not { } audio) return null;
        var made = new Dubber(model, audio, () => server, () => ServerPort, post)
        {
            Cast = settings.Dubbing.Cast.Copy(),
            Output = settings.Dubbing.Output,
        };
        made.CastChanged += cast => Settings = settings with { Dubbing = settings.Dubbing with { Cast = cast } };
        made.Failed += message => DubbingError = message;
        dubber = made;
        return made;
    }

    /// <summary>Nino: dublaj yalnız Türkçe çeviride çalışır (sesler ve metin hazırlığı Türkçe için); Arapçada kapalıdır.</summary>
    public bool DubbingActive => settings.Dubbing.Enabled && TargetLanguage.IsTurkish(settings.TargetLanguage);

    private void Speak(IReadOnlyList<SpokenLine> lines)
    {
        if (!DubbingActive || !DubbingInstalled) return;
        MakeDubber()?.Speak(lines);
    }

    private void DubbingSettingsChanged(DubbingSettings old)
    {
        var now = settings.Dubbing;
        if (now.Engine != old.Engine)
        {
            // Motor değişti: eski dublaj kapanır, yenisi hazırlanır.
            StopDubber();
            Changed(nameof(DubbingInstalled));
            if (now.Enabled && isRunning && DubbingInstalled) MakeDubber()?.Prepare();
            return;
        }
        if (dubber is null)
        {
            if (now.Enabled && !old.Enabled && isRunning && DubbingInstalled) MakeDubber()?.Prepare();
            return;
        }
        // Dublajın kendi atadığı ses (CastChanged) zaten dublajda; kullanıcının seçimi kopyalanır.
        if (!ReferenceEquals(now.Cast, old.Cast)) dubber.Cast = now.Cast.Copy();
        if (now.Output != old.Output)
        {
            dubber.Stop();
            dubber.Output = now.Output;
        }
        if (!now.Enabled) StopDubber();
    }

    private void StopDubber()
    {
        if (dubber is not { } stopping) return;
        dubber = null;
        _ = stopping.DisposeAsync().AsTask();
    }

    private AppException Error(AppError error) => new(error, AppException.Describe(error, text));

    /// <summary>Değer değiştiyse yazar ve özelliği (ve ona bağlı olanları) bildirir.</summary>
    private bool Set<T>(ref T field, T value, string[]? also = null, [CallerMemberName] string name = "")
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        Changed([name, .. also ?? []]);
        return true;
    }

    private void Changed(params string[] names)
    {
        foreach (var name in names) PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    /// <summary>Model eksikken ya da dil desteklenmezken kullanılan çevirmen: nedeni bildirir.</summary>
    private sealed class UnavailableTranslator(TranslatorStatus status) : ITextTranslator
    {
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default) => throw new TranslatorException(status);
    }

    /// <summary>İlerlemeyi bağlama yakalamadan doğrudan iletir (post zaten arayüze aktarır).</summary>
    private sealed class ImmediateProgress(Action<double> report) : IProgress<double>
    {
        public void Report(double value) => report(value);
    }
}

/// <summary>Ek bölgenin tek seferlik çevirisinin sonucu.</summary>
public enum ExtraRegionOutcome { Shown, NoText, NotConfigured, NotRunning, Busy, TranslatorUnavailable, Failed }

/// <summary>"Ekranı çevir"in sonucu; <see cref="Cleared"/>: TV'deki çeviriler kaldırıldı ya da süren iş iptal edildi.</summary>
public enum ScreenOutcome { Shown, NoText, Cleared, NotRunning, TranslatorUnavailable, Failed }
