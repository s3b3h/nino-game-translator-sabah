// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Uygulamanın kullanıcıya özel veri klasörü; yolu yalnız burası kurar (ayarlar, secure.dat, paketler, modeller,
/// günlükler). Windows'ta <c>%LOCALAPPDATA%\Nino</c>. Eski sürümler <c>%LOCALAPPDATA%\CouchSubs</c> kullanıyordu:
/// <see cref="Prepare"/> o klasörü bir kez, bütün olarak yenisine taşır; taşınamazsa (kilitli dosya, izin) bu
/// çalıştırmada eski klasör kullanılmaya devam eder ve taşıma bir sonraki açılışta yeniden denenir. Uygulamanın başka
/// bir kopyası açıkken de taşınmaz (o kopya eski klasörü kullanıyor olabilir).
/// <para>
/// Eski klasör asıl CouchSubs uygulamasının da veri klasörüdür. O uygulamanın kurulu ya da açık olduğuna dair bir
/// işaret varsa (<see cref="OnDisk"/>) klasör taşınmaz: yalnız veri dosyaları yeni klasöre kopyalanır
/// (<see cref="CopyData"/>), eski klasör olduğu gibi kalır.
/// </para>
/// Karar süreç başına bir kez verilir ve değişmez.
/// </summary>
/// <remarks>
/// Windows dışında (Linux sunucusu, Mac'te testler) hiçbir şey taşınmaz ve oluşturulmaz; yol eskisi gibi kalır.
/// Linux uygulaması kendi klasörünü ayrıca kurar (linux/CouchSubs.Linux/Stores.cs) ve Mac'te aynı ad Mac
/// uygulamasının gerçek klasörüdür (~/Library/Application Support/CouchSubs).
/// </remarks>
public static class DataFolder
{
    /// <summary>Klasörün adı.</summary>
    public const string Name = "Nino";
    /// <summary>CouchSubs'tan kalan eski ad.</summary>
    public const string LegacyName = "CouchSubs";

    /// <param name="UseLegacy">Bu çalıştırmada eski klasör kullanılır.</param>
    /// <param name="Moved">Eski klasör bu kararla yenisine taşındı.</param>
    /// <param name="MoveError">Taşıma ya da kopyalama denendi ve başarısız oldu (tanı için).</param>
    /// <param name="Copied">Eski klasör başka bir uygulamayla ortak olduğundan taşınmadı; verisi yenisine kopyalandı.</param>
    internal sealed record Decision(bool UseLegacy, bool Moved, Exception? MoveError, bool Copied = false);

    /// <summary>Bu süreçte verilen karar: klasörün yolu, adı, varsa taşıma hatası ve verinin kopyalanıp kopyalanmadığı.</summary>
    internal sealed record Resolution(string Path, string FolderName, Exception? MoveError, bool Copied = false);

    /// <summary>Açık duran aynı adlı (CouchSubs.exe) başka süreçler.</summary>
    internal enum OtherCopies
    {
        None,
        /// <summary>Bu uygulamanın ikinci kopyası (aynı klasörden çalışıyor) ya da kim olduğu okunamayan bir süreç.</summary>
        SameApp,
        /// <summary>Başka bir yerden çalışan CouchSubs.exe: asıl CouchSubs ya da Nino'nun başka klasördeki eski kopyası.</summary>
        OtherApp,
    }

    /// <summary>Asıl CouchSubs'ın Velopack kurulum klasörü (%LOCALAPPDATA%\CouchSubsApp; paket kimliği CouchSubsApp).</summary>
    internal const string UpstreamInstallName = "CouchSubsApp";
    /// <summary>Kopyalama bitene kadar kullanılan geçici klasörün adı: "Nino" + bu ek + rastgele kimlik.</summary>
    internal const string CopySuffix = ".kopya-";
    /// <summary>Kopyalanan klasöre bırakılan kısa not.</summary>
    internal const string CopyNoteFile = "kopyalandi.txt";

    private static readonly object Gate = new();
    private static Resolution? resolved;

    /// <summary>
    /// Klasörün yolu. Karar daha verilmediyse burada taşımasız verilir (yeni klasör varsa o, yoksa eskisi varsa eskisi):
    /// taşımayı yalnız uygulamanın açılışı (<see cref="Prepare"/>) yapar, testler ve başka araçlar kullanıcının
    /// klasörüne dokunmaz.
    /// </summary>
    public static string Path => Resolve(migrate: false).Path;

    /// <summary>Kullanılan klasörün adı ("Nino"; taşınamadıysa "CouchSubs").</summary>
    public static string FolderName => Resolve(migrate: false).FolderName;

    /// <summary>Taşıma ya da kopyalama denendi ve olmadıysa nedeni; uygulama bunu hata.log'a yazar.</summary>
    public static Exception? MoveError => Resolve(migrate: false).MoveError;

    /// <summary>Eski klasör başka bir uygulamayla ortak olduğu için taşınmadı, verisi bu açılışta yeni klasöre kopyalandı.</summary>
    public static bool Copied => Resolve(migrate: false).Copied;

    /// <summary>Klasörün içindeki bir dosyanın ya da alt klasörün yolu.</summary>
    public static string In(params string[] parts) => System.IO.Path.Combine([Path, .. parts]);

    /// <summary>
    /// Kullanıcıya gösterilen yol (Dosya Gezgini'nin adres çubuğuna yazılabilir); gerçekten kullanılan klasörü gösterir.
    /// </summary>
    public static string Display(string file) => Display(FolderName, file);

    internal static string Display(string folderName, string file) => $@"%LOCALAPPDATA%\{folderName}\{file}";

    /// <summary>
    /// Uygulama açılışında, veriye dokunan her şeyden önce bir kez çağrılır: gerekiyorsa eski klasörü taşır ve kararı
    /// sabitler. Karar daha önce verildiyse (klasör zaten kullanılmaya başlandıysa) hiçbir şey taşınmaz.
    /// </summary>
    public static string Prepare() => Resolve(migrate: true).Path;

    private static Resolution Resolve(bool migrate)
    {
        lock (Gate)
        {
            if (resolved is not null) return resolved;
            var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return resolved = OperatingSystem.IsWindows()
                ? OnDisk(root, migrate, RunningCopies)
                : new Resolution(System.IO.Path.Combine(root, LegacyName), LegacyName, null);
        }
    }

    /// <summary>
    /// Kararı <paramref name="root"/> altındaki gerçek klasörlere uygular. İki klasör aynı üst klasörde olduğundan
    /// taşıma tek bir yeniden adlandırmadır: ya bütün klasör taşınır ya hiçbir şey; yarım kalmış iki klasör oluşmaz.
    /// <para>
    /// Eski klasör asıl CouchSubs'la ortaksa taşınmaz, verisi kopyalanır. Ortak sayılmasının işaretleri:
    /// eski klasörün içinde bir Velopack kurulumu (Update.exe, current\, packages\); yanında asıl CouchSubs'ın kurulumu
    /// (<see cref="UpstreamInstallName"/>); ya da başka bir klasörden çalışan açık bir CouchSubs.exe.
    /// </para>
    /// </summary>
    /// <param name="migrate">false ise diske yazılmaz: ne taşınır, ne kopyalanır, ne klasör oluşturulur.</param>
    /// <param name="otherCopies">Açık duran başka kopyalar. Bu uygulamanın ikinci kopyası açıksa hiçbir şey yapılmaz
    /// (o kopya eski klasörü kullanıyor olabilir; klasör altından çekilirse girişini kaybetmiş görünür); iş sonraki
    /// açılışa kalır. Başka bir uygulama açıksa klasör taşınmaz, kopyalanır.</param>
    internal static Resolution OnDisk(string root, bool migrate, Func<OtherCopies>? otherCopies = null)
    {
        var current = System.IO.Path.Combine(root, Name);
        var legacy = System.IO.Path.Combine(root, LegacyName);
        var shared = false;
        // Boş bir yeni klasör eski verinin önüne geçmesin (yoksa ayarlar ve giriş kaybolmuş görünürdü): boşsa yok sayılır
        // ve taşımadan önce kaldırılır. İçinde tek dosya bile varsa kural gereği yeni klasör kullanılır, eskisine dokunulmaz.
        if (migrate && Exists(legacy) && (!Exists(current) || IsEmpty(current)))
        {
            var others = otherCopies?.Invoke() ?? OtherCopies.None;
            if (others == OtherCopies.SameApp)
                return new Resolution(legacy, LegacyName, new IOException(
                    "Uygulamanın başka bir kopyası açık; veri klasörü sonraki açılışta taşınacak."));
            shared = others == OtherCopies.OtherApp || HasInstall(legacy)
                || HasInstall(System.IO.Path.Combine(root, UpstreamInstallName));
            RemoveIfEmpty(current);
        }
        var decision = Decide(Exists(current), Exists(legacy),
            migrate ? () => Directory.Move(legacy, current) : null,
            () => Exists(current),
            legacyShared: shared,
            copy: migrate ? () => CopyData(legacy, current) : null);
        if (decision.UseLegacy) return new Resolution(legacy, LegacyName, decision.MoveError);
        if (migrate)
        {
            // İkisi de yoksa yenisi oluşturulur. Oluşturulamazsa yol yine aynıdır; yazan kod kendi hatasını görür.
            try { Directory.CreateDirectory(current); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or NotSupportedException) { }
        }
        return new Resolution(current, Name, decision.MoveError, decision.Copied);
    }

    /// <summary>Klasörde bir Velopack kurulumu var mı (kurulum kökünde Update.exe, current\ ve packages\ durur).</summary>
    internal static bool HasInstall(string directory)
    {
        try
        {
            return File.Exists(System.IO.Path.Combine(directory, "Update.exe"))
                || Directory.Exists(System.IO.Path.Combine(directory, "current"))
                || Directory.Exists(System.IO.Path.Combine(directory, "packages"));
        }
        catch (Exception) { return false; }
    }

    /// <summary>
    /// Kopyalanmayan üst düzey girdiler. Başka uygulamanın kurulumu (Velopack girdileri ve .exe dosyaları) Nino'nun
    /// değildir. Modeller ve CUDA kitaplıkları yüzlerce MB'tan birkaç GB'a kadar yer tutar: açılışta kopyalamak pencereyi
    /// dakikalarca geciktirir ve diski doldurabilir; eksik modeli uygulama zaten ana ekrandaki kartla yeniden indirir.
    /// WebView2 profilleri (yalnız giriş sayfasının çerezleri; giriş anahtarları secure.dat'ta) öbür uygulama açıkken
    /// kilitlidir. Günlükler öbür uygulamanın kayıtlarıdır.
    /// </summary>
    internal static bool SkippedInCopy(string name, bool isDirectory)
    {
        static bool Is(string a, string b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
        static bool Ends(string a, string b) => a.EndsWith(b, StringComparison.OrdinalIgnoreCase);
        if (isDirectory)
            return Is(name, "current") || Is(name, "packages") || Is(name, "models") || Is(name, "webview")
                || Is(name, "xbox-webview") || name.StartsWith("cuda-", StringComparison.OrdinalIgnoreCase);
        return Ends(name, ".exe") || Ends(name, ".nupkg") || Ends(name, ".log") || Ends(name, ".log.1") || Ends(name, ".tmp");
    }

    /// <summary>
    /// Eski klasörün verisini yeni klasöre kopyalar; eski klasöre dokunmaz. Ya hep ya hiç: önce yanındaki geçici bir
    /// klasöre kopyalanır, hepsi bitince tek bir yeniden adlandırmayla yeni klasör olur. Tek dosya bile kopyalanamazsa
    /// geçici klasör silinir ve hata fırlatılır (yarım kopya yeni klasör olup sonraki açılışlarda eksik veriyle
    /// kullanılmasın); eski klasör kullanılmaya devam eder, kopya sonraki açılışta yeniden denenir.
    /// </summary>
    internal static void CopyData(string legacy, string current)
    {
        var parent = System.IO.Path.GetDirectoryName(current)!;
        // Yarıda kesilmiş (ör. bilgisayar kapanmış) önceki denemelerin artıkları.
        foreach (var stale in Directory.EnumerateDirectories(parent, System.IO.Path.GetFileName(current) + CopySuffix + "*"))
            try { Directory.Delete(stale, recursive: true); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        var temporary = current + CopySuffix + Guid.NewGuid().ToString("N");
        try
        {
            CopyTree(legacy, temporary, top: true);
            File.WriteAllText(System.IO.Path.Combine(temporary, CopyNoteFile),
                $"Bu klasörün verisi {legacy} klasöründen kopyalandı ({DateTime.Now:yyyy-MM-dd HH:mm}). O klasörü CouchSubs da " +
                "kullandığı için yerinde bırakıldı. Modeller kopyalanmadı; Nino gerektiğinde yeniden indirir.\n");
            Directory.Move(temporary, current);
        }
        catch (Exception)
        {
            try { if (Directory.Exists(temporary)) Directory.Delete(temporary, recursive: true); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            throw;
        }
    }

    private static void CopyTree(string source, string target, bool top)
    {
        Directory.CreateDirectory(target);
        foreach (var entry in new DirectoryInfo(source).EnumerateFileSystemInfos())
        {
            var isDirectory = entry is DirectoryInfo;
            if (top && SkippedInCopy(entry.Name, isDirectory)) continue;
            // Bağlantılar (junction, simgesel bağ) izlenmez: döngüye ya da başka bir sürücüye gidebilir.
            if ((entry.Attributes & FileAttributes.ReparsePoint) != 0) continue;
            var destination = System.IO.Path.Combine(target, entry.Name);
            if (isDirectory) CopyTree(entry.FullName, destination, top: false);
            else File.Copy(entry.FullName, destination);
        }
    }

    private static bool IsEmpty(string directory)
    {
        try { return !Directory.EnumerateFileSystemEntries(directory).Any(); }
        catch (Exception) { return false; }
    }

    /// <summary>Yalnız boş klasörü siler: Directory.Delete (recursive: false) içinde bir şey varsa hata verir.</summary>
    private static void RemoveIfEmpty(string directory)
    {
        try { if (Exists(directory)) Directory.Delete(directory, recursive: false); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>
    /// Bu oturumda açık duran aynı adlı başka süreçler (eski sürümler ve asıl CouchSubs da aynı adı taşır). Süreç listesi
    /// hiç alınamazsa "yok" sayılır: taşıma yine tek bir yeniden adlandırmadır ve açık dosya varsa Windows izin vermez.
    /// </summary>
    private static OtherCopies RunningCopies()
    {
        try
        {
            using var self = System.Diagnostics.Process.GetCurrentProcess();
            var same = System.Diagnostics.Process.GetProcessesByName(self.ProcessName);
            try
            {
                var paths = new List<string?>();
                foreach (var other in same)
                {
                    try
                    {
                        if (other.Id == self.Id || other.SessionId != self.SessionId) continue;
                        paths.Add(other.MainModule?.FileName);
                    }
                    catch (Exception)
                    {
                        // Bilgisi okunamayan süreç (kapanıyor ya da yönetici olarak açılmış).
                        paths.Add(null);
                    }
                }
                return Classify(Environment.ProcessPath, paths);
            }
            finally
            {
                foreach (var other in same) other.Dispose();
            }
        }
        catch (Exception)
        {
            return OtherCopies.None;
        }
    }

    /// <summary>
    /// Açık duran aynı adlı süreçleri yollarına göre ayırır. Bu uygulamayla aynı klasörden çalışan ya da yolu okunamayan
    /// süreç bu uygulamanın kopyası sayılır (temkinli: taşıma ve kopya ertelenir). Başka klasörden çalışan başka bir
    /// uygulamadır. Velopack'in başlatıcısı (<see cref="LauncherPath"/>) sayılmaz.
    /// </summary>
    internal static OtherCopies Classify(string? self, IEnumerable<string?> others)
    {
        var launcher = LauncherPath(self);
        var folder = string.IsNullOrEmpty(self) ? null : System.IO.Path.GetDirectoryName(self);
        var result = OtherCopies.None;
        foreach (var other in others)
        {
            if (string.IsNullOrEmpty(other) || string.IsNullOrEmpty(folder)) return OtherCopies.SameApp;
            if (launcher is not null && string.Equals(other, launcher, StringComparison.OrdinalIgnoreCase)) continue;
            if (string.Equals(System.IO.Path.GetDirectoryName(other), folder, StringComparison.OrdinalIgnoreCase))
                return OtherCopies.SameApp;
            result = OtherCopies.OtherApp;
        }
        return result;
    }

    /// <summary>
    /// Velopack kurulumunda kısayolların açtığı başlatıcı: uygulamayla aynı adı taşır ve bir üst klasörde durur
    /// (…\NinoGameTranslator\CouchSubs.exe → …\current\CouchSubs.exe). Update.exe'yi başlatıp hemen çıkar ama o an hâlâ
    /// kapanıyor olabilir; veriye dokunmadığından açık kopya sayılmaz (yoksa kısayoldan açılışta taşıma ertelenirdi).
    /// </summary>
    internal static string? LauncherPath(string? executable)
    {
        if (string.IsNullOrEmpty(executable)) return null;
        var parent = System.IO.Path.GetDirectoryName(System.IO.Path.GetDirectoryName(executable));
        return string.IsNullOrEmpty(parent) ? null : System.IO.Path.Combine(parent, System.IO.Path.GetFileName(executable));
    }

    private static bool Exists(string directory)
    {
        try { return Directory.Exists(directory); }
        catch (Exception) { return false; }
    }

    /// <summary>
    /// Hangi klasörün kullanılacağına karar verir (diske dokunmaz; taşıma <paramref name="move"/> ile yapılır).
    /// <list type="bullet">
    /// <item>Yeni klasör varsa o kullanılır; eskisi de dursa bile birleştirilmez, eskisine dokunulmaz. (Yeni klasör
    /// bomboşsa <see cref="OnDisk"/> onu yok sayar.)</item>
    /// <item>İkisi de yoksa yenisi kullanılır.</item>
    /// <item>Yalnız eskisi varsa taşınır. Taşıma hangi nedenle olursa olsun başarısızsa eski klasör kullanılır; yeni
    /// klasör oluşturulmaz (yoksa sonraki açılış boş yeni klasörü seçer ve ayarlar kaybolmuş görünürdü).</item>
    /// <item>Taşıma, aynı anda açılan ikinci bir kopya klasörü önce taşıdığı için başarısız olduysa yeni klasör
    /// kullanılır (<paramref name="currentExistsNow"/>).</item>
    /// <item>Eski klasör başka bir uygulamayla ortaksa (<paramref name="legacyShared"/>) taşınmaz: verisi kopyalanır,
    /// eski klasör olduğu gibi kalır. Kopya başarısızsa eski klasör kullanılır.</item>
    /// </list>
    /// </summary>
    /// <param name="move">Eski klasörü yenisine taşır; hata fırlatabilir. null ise taşıma denenmez (eski klasör kalır).</param>
    /// <param name="currentExistsNow">Başarısız taşımadan ya da kopyadan sonra yeni klasör var mı.</param>
    /// <param name="legacyShared">Eski klasörü başka bir uygulama (asıl CouchSubs) da kullanıyor: taşınmaz,
    /// <paramref name="copy"/> ile verisi kopyalanır ve eski klasör yerinde kalır.</param>
    /// <param name="copy">Eski klasörün verisini yenisine kopyalar (ya hep ya hiç); hata fırlatabilir. null ise
    /// kopyalama denenmez (eski klasör kullanılır).</param>
    internal static Decision Decide(bool currentExists, bool legacyExists, Action? move, Func<bool>? currentExistsNow = null,
                                    bool legacyShared = false, Action? copy = null)
    {
        if (currentExists || !legacyExists) return new Decision(UseLegacy: false, Moved: false, MoveError: null);
        var transfer = legacyShared ? copy : move;
        if (transfer is null) return new Decision(UseLegacy: true, Moved: false, MoveError: null);
        try
        {
            transfer();
            return new Decision(UseLegacy: false, Moved: !legacyShared, MoveError: null, Copied: legacyShared);
        }
        catch (Exception error)
        {
            var doneByAnother = currentExistsNow?.Invoke() == true;
            return new Decision(UseLegacy: !doneByAnother, Moved: false, MoveError: doneByAnother ? null : error);
        }
    }
}
