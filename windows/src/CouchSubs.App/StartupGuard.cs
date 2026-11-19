// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;

namespace CouchSubs.App;

/// <summary>
/// Açılış hatalarını sessizce kapanmak yerine gösterir. Bu sınıf yalnız .NET'in kendi türlerini kullanır: uygulamanın
/// başka bir DLL'i eksik olsa da yüklenip çalışabilmeli. Tek ayrıcalık veri klasörünün hazırlanmasıdır
/// (<see cref="PrepareDataFolder"/>): Core'a dokunan iki yöntem ayrı tutulur ve DLL yoksa hata yakalanır.
/// </summary>
internal static class StartupGuard
{
    static bool Turkish => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "tr";

    internal static string LogPath => Path.Combine(preparedFolder ?? FolderWithoutCore(), "hata.log");

    static string? preparedFolder;

    /// <summary>Nino'nun sorun bildirme sayfası. İleti kutusunda bağlantı tıklanamaz; adres açıkça yazılır.</summary>
    internal const string IssuesUrl = "https://github.com/yunusdemirbag/nino-game-translator/issues";

    /// <summary>Hata iletilerinin son satırı: günlüğün yeri ve sorunun nereye bildirileceği.</summary>
    static string ReportHint => Turkish
        ? $"Ayrıntılar {LogPath} dosyasında. Sorunu bu dosyayla birlikte Nino'nun GitHub sayfasından bildirebilirsiniz:\n{IssuesUrl}"
        : $"Details are in {LogPath}. Please report it with that file on Nino's GitHub page:\n{IssuesUrl}";

    /// <summary>
    /// Veri klasörünü hazırlar: eski %LOCALAPPDATA%\CouchSubs klasörü varsa %LOCALAPPDATA%\Nino'ya taşınır; asıl CouchSubs
    /// da o klasörü kullanıyorsa taşınmaz, verisi kopyalanır (kural ve taşıma CouchSubs.Core.DataFolder'da). Program.Main'de, veriye dokunan her şeyden ve ilk günlük satırından önce
    /// çağrılır. Core DLL'i yüklenemiyorsa hata vermez; o durumda günlük <see cref="FolderWithoutCore"/> klasörüne yazılır.
    /// </summary>
    internal static void PrepareDataFolder()
    {
        try
        {
            preparedFolder = PrepareInCore();
            LogMoveError();
        }
        catch (Exception error)
        {
            // Eksik ya da bozuk DLL: nedeni App.OnStartup gösterir. Burada hata çıkarsa o ileti hiç görünmezdi.
            Log("Veri klasörü hazırlanamadı", error);
        }
    }

    // Core'un türlerine dokunan kod ayrı yöntemlerde durur: DLL eksikse hata bu yöntemler derlenirken çıkar ve yukarıda yakalanır.
    [MethodImpl(MethodImplOptions.NoInlining)]
    static string PrepareInCore() => CouchSubs.Core.DataFolder.Prepare();

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void LogMoveError()
    {
        if (CouchSubs.Core.DataFolder.MoveError is { } error)
            Log($"Veri klasörü {CouchSubs.Core.DataFolder.Name} adına taşınamadı; bu açılışta eski klasör kullanılıyor: {preparedFolder}", error);
        // Destek için: modellerin neden yeniden indirildiği günlükten anlaşılsın.
        if (CouchSubs.Core.DataFolder.Copied)
            Log($"Eski veri klasörünü ({CouchSubs.Core.DataFolder.LegacyName}) başka bir uygulama da kullandığı için taşınmadı; " +
                $"veriler {preparedFolder} klasörüne kopyalandı. Modeller kopyalanmaz, gerektiğinde yeniden indirilir.", null);
    }

    /// <summary>
    /// Core olmadan günlüğün klasörü; hiçbir şey taşımaz: yeni klasör varsa o, yoksa eskisi varsa eskisi (yalnız eskisi
    /// varken yenisi oluşturulmaz; yoksa sonraki açılış boş yeni klasörü seçerdi). Adlar derleme zamanı sabitidir,
    /// çalışırken Core DLL'ine gerek duymaz.
    /// </summary>
    static string FolderWithoutCore()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var current = Path.Combine(root, CouchSubs.Core.DataFolder.Name);
        var legacy = Path.Combine(root, CouchSubs.Core.DataFolder.LegacyName);
        return !Directory.Exists(current) && Directory.Exists(legacy) ? legacy : current;
    }

    /// <summary>
    /// deps.json'da listelenen ama klasörde olmayan DLL'ler. Antivirüs bir dosyayı karantinaya alınca .NET açılışta
    /// FileNotFoundException verir ve pencere hiç açılmaz.
    /// </summary>
    public static IReadOnlyList<string> MissingFiles(string folder)
    {
        var deps = Path.Combine(folder, "CouchSubs.deps.json");
        if (!File.Exists(deps)) return [];
        try
        {
            using var json = JsonDocument.Parse(File.ReadAllText(deps));
            var names = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var target in json.RootElement.GetProperty("targets").EnumerateObject())
                foreach (var library in target.Value.EnumerateObject())
                    if (library.Value.TryGetProperty("runtime", out var runtime))
                        foreach (var file in runtime.EnumerateObject())
                            names.Add(Path.GetFileName(file.Name));
            return [.. names.Where(name => !File.Exists(Path.Combine(folder, name)))];
        }
        catch (Exception error) when (error is JsonException or KeyNotFoundException or InvalidOperationException or IOException)
        {
            return [];
        }
    }

    public static string MissingMessage(IReadOnlyList<string> files)
    {
        var list = string.Join("\n", files.Take(8).Select(f => "  • " + f)) + (files.Count > 8 ? "\n  • …" : "");
        return Turkish
            ? $"Nino açılamadı: program klasöründe şu dosyalar yok:\n\n{list}\n\n" +
              "Bunun en sık nedeni antivirüs programının dosyayı karantinaya almasıdır. Windows Güvenliği › Virüs ve tehdit " +
              "koruması › Koruma geçmişi'nden dosyayı geri yükleyin ya da Nino-windows-x64.zip'i yeniden indirip " +
              "\"Tümünü ayıkla\" ile bir klasöre çıkarın. Programı zip'in içinden çalıştırmayın."
            : $"Nino could not start: these files are missing from its folder:\n\n{list}\n\n" +
              "This usually means an antivirus moved them to quarantine. Restore them from Windows Security › Virus & threat " +
              "protection › Protection history, or download Nino-windows-x64.zip again and use \"Extract all\". " +
              "Do not run the app from inside the zip.";
    }

    public static string ErrorMessage(Exception error) =>
        (Turkish
            ? "Nino beklenmeyen bir hatayla karşılaştı:\n\n"
            : "Nino ran into an unexpected error:\n\n") +
        $"{error.GetType().Name}: {error.Message}\n\n" +
        ReportHint;

    /// <summary>Hatayı kaydeder, gösterir ve uygulamayı kapatır. Ekran görüntüsü kipinde pencere yerine errors.txt yazılır.</summary>
    public static void Fail(Application app, string message, Exception? error, string? renderFolder)
    {
        Log(message, error);
        if (renderFolder is null)
        {
            MessageBox.Show(message, "Nino", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        else
        {
            Directory.CreateDirectory(renderFolder);
            File.AppendAllText(Path.Combine(renderFolder, "errors.txt"), message + "\n" + error + "\n");
        }
        app.Shutdown(3);
    }

    /// <summary>Bilgisayar ekranındaki altyazı penceresi açılamadı ya da çizilemedi; çeviri sürer.</summary>
    public static string OverlayFailedMessage(Exception error) =>
        (Turkish
            ? "Bilgisayar ekranındaki altyazı penceresi açılamadı. Çeviri sürüyor ama altyazılar bu pencerede görünmeyecek; " +
              "Nino'yu yeniden açınca pencere yeniden denenir.\n\n"
            : "The subtitle window on this computer's screen could not be shown. Translation continues, but subtitles won't " +
              "appear in that window until you reopen Nino.\n\n") +
        $"{error.GetType().Name}: {error.Message}\n\n" +
        ReportHint;

    /// <summary>Arka plandaki bir hata uygulamayı kapatıyor; hiç değilse nedeni görünsün.</summary>
    static string ClosingMessage(Exception? error) =>
        (Turkish
            ? "Nino bir hata yüzünden kapanmak zorunda kaldı:\n\n"
            : "Nino has to close because of an error:\n\n") +
        (error is null ? "" : $"{error.GetType().Name}: {error.Message}\n\n") +
        ReportHint;

    /// <summary>
    /// Açılıştan sonraki yakalanmamış hataları da sessiz kalmadan gösterir. Uygulama kapanmaz: kullanıcı yaptığı işi
    /// (ör. az önce bitirdiği PSN girişini) kaybetmesin ve çeviri sürsün.
    /// </summary>
    public static void Watch(Application app)
    {
        app.DispatcherUnhandledException += (_, e) =>
        {
            Log("DispatcherUnhandledException", e.Exception);
            // İleti burada, hatanın içinde açılmaz: düzen ya da çizim sırasında çıkan hatada MessageBox kendisi hata verir
            // (iletiler askıdayken pencere açılamaz) ve o ikinci hata uygulamayı kapatırdı. Her karede yinelenen bir hata
            // da iç içe yüzlerce pencere açıp yığını taşırırdı. İleti sonra, tek seferde gösterilir.
            e.Handled = true;
            Show(app, ErrorMessage(e.Exception));
        };
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            var error = e.ExceptionObject as Exception;
            Log(e.IsTerminating ? "UnhandledException (uygulama kapanıyor)" : "UnhandledException", error);
            // Arka plan iş parçacığındaki hata süreci kapatır; uygulama sessizce kaybolmasın.
            if (e.IsTerminating) ShowNow(ClosingMessage(error));
        };
        // Beklenmeyen görev hataları da kayda geçer (gözlenmemiş görev uygulamayı kapatmaz ama sorunun izi kalsın).
        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            Log("UnobservedTaskException", e.Exception);
            e.SetObserved();
        };
    }

    static readonly object LogGate = new();
    static int showing;
    static string? lastShown;
    static DateTime lastShownAt;

    /// <summary>
    /// Hata iletisini arayüz boşalınca gösterir. Aynı anda tek ileti açılır; aynı ileti yarım dakika içinde yinelenirse
    /// yalnız kayda geçer (her karede yinelenen hata kullanıcıyı ileti yağmuruna tutmasın).
    /// </summary>
    public static void Show(Application? app, string message)
    {
        if (app is null) return;
        try
        {
            app.Dispatcher.InvokeAsync(() =>
            {
                if (showing > 0) return;
                if (message == lastShown && DateTime.UtcNow - lastShownAt < TimeSpan.FromSeconds(30)) return;
                showing++;
                try
                {
                    ShowNow(message);
                }
                finally
                {
                    showing--;
                    lastShown = message;
                    lastShownAt = DateTime.UtcNow;
                }
            }, DispatcherPriority.Background);
        }
        catch (Exception error)
        {
            Log("Hata iletisi sıraya alınamadı", error);
        }
    }

    static void ShowNow(string message)
    {
        try
        {
            MessageBox.Show(message, "Nino", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        catch (Exception error)
        {
            Log("Hata iletisi gösterilemedi", error);
        }
    }

    /// <summary>Veri klasöründeki (%LOCALAPPDATA%\Nino) hata.log dosyasına yazar; yazılamazsa sessizce geçer.</summary>
    internal static void Log(string message, Exception? error)
    {
        try
        {
            // Arka plan iş parçacıkları da yazar; aynı anda yazılan satırlar birbirini silmesin.
            lock (LogGate)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
                File.AppendAllText(LogPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}\n{error}\n\n");
            }
        }
        catch (Exception)
        {
            // Kayıt yazılamasa da mesaj gösterilir; hata işleyicisinin içinden yeni hata çıkmamalı.
        }
    }
}
