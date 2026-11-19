// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Veri klasörü kararı: %LOCALAPPDATA%\CouchSubs → %LOCALAPPDATA%\Nino taşıması. Karar testleri diske dokunmaz;
/// klasör testleri yalnız geçici bir kök klasörde çalışır (kullanıcının gerçek klasörüne hiçbir test dokunmaz).
/// </summary>
public class DataFolderTests : IDisposable
{
    private readonly string root = Path.Combine(Path.GetTempPath(), "nino-datafolder-" + Guid.NewGuid().ToString("N"));
    private string Current => Path.Combine(root, DataFolder.Name);
    private string Legacy => Path.Combine(root, DataFolder.LegacyName);

    public void Dispose()
    {
        try { Directory.Delete(root, recursive: true); } catch (DirectoryNotFoundException) { }
    }

    // --- Karar (diske dokunmaz) ---

    [Fact]
    public void OnlyLegacyFolderIsMovedToTheNewOne()
    {
        var moves = 0;
        var decision = DataFolder.Decide(currentExists: false, legacyExists: true, move: () => moves++);
        Assert.Equal(1, moves);
        Assert.False(decision.UseLegacy);
        Assert.True(decision.Moved);
        Assert.Null(decision.MoveError);
    }

    [Theory]
    [InlineData(typeof(IOException))]
    [InlineData(typeof(UnauthorizedAccessException))]
    [InlineData(typeof(InvalidOperationException))]
    public void FailedMoveKeepsUsingTheLegacyFolder(Type errorType)
    {
        var error = (Exception)Activator.CreateInstance(errorType)!;
        var decision = DataFolder.Decide(currentExists: false, legacyExists: true, move: () => throw error, currentExistsNow: () => false);
        Assert.True(decision.UseLegacy);
        Assert.False(decision.Moved);
        Assert.Same(error, decision.MoveError);
    }

    [Fact]
    public void BothFoldersUseTheNewOneWithoutMoving()
    {
        var decision = DataFolder.Decide(currentExists: true, legacyExists: true, move: () => Assert.Fail("taşınmamalı"));
        Assert.False(decision.UseLegacy);
        Assert.False(decision.Moved);
        Assert.Null(decision.MoveError);
    }

    [Fact]
    public void NeitherFolderUsesTheNewOneWithoutMoving()
    {
        var decision = DataFolder.Decide(currentExists: false, legacyExists: false, move: () => Assert.Fail("taşınmamalı"));
        Assert.False(decision.UseLegacy);
        Assert.False(decision.Moved);
    }

    [Fact]
    public void OnlyNewFolderIsUsedAsIs()
    {
        var decision = DataFolder.Decide(currentExists: true, legacyExists: false, move: () => Assert.Fail("taşınmamalı"));
        Assert.False(decision.UseLegacy);
        Assert.False(decision.Moved);
    }

    [Fact]
    public void MoveLostToAnotherInstanceUsesTheNewFolder()
    {
        // İkinci kopya aynı anda açıldı ve klasörü önce o taşıdı: bizim taşımamız "kaynak yok" diye başarısız olur.
        var decision = DataFolder.Decide(currentExists: false, legacyExists: true,
            move: () => throw new DirectoryNotFoundException(), currentExistsNow: () => true);
        Assert.False(decision.UseLegacy);
        Assert.False(decision.Moved);
        Assert.Null(decision.MoveError);
    }

    [Fact]
    public void WithoutMoveTheLegacyFolderStaysInUse()
    {
        var decision = DataFolder.Decide(currentExists: false, legacyExists: true, move: null);
        Assert.True(decision.UseLegacy);
        Assert.False(decision.Moved);
        Assert.Null(decision.MoveError);
    }

    // --- Gerçek klasörler (geçici kökte) ---

    [Fact]
    public void LegacyFolderMovesWholeWithItsContents()
    {
        Directory.CreateDirectory(Path.Combine(Legacy, "packs", "alt"));
        File.WriteAllText(Path.Combine(Legacy, "settings.json"), "{\"a\":1}");
        File.WriteAllBytes(Path.Combine(Legacy, "secure.dat"), [1, 2, 3]);
        File.WriteAllText(Path.Combine(Legacy, "packs", "alt", "oyun.json"), "paket");

        var result = DataFolder.OnDisk(root, migrate: true);

        Assert.Equal(Current, result.Path);
        Assert.Equal(DataFolder.Name, result.FolderName);
        Assert.Null(result.MoveError);
        Assert.False(Directory.Exists(Legacy));
        Assert.Equal("{\"a\":1}", File.ReadAllText(Path.Combine(Current, "settings.json")));
        Assert.Equal(new byte[] { 1, 2, 3 }, File.ReadAllBytes(Path.Combine(Current, "secure.dat")));
        Assert.Equal("paket", File.ReadAllText(Path.Combine(Current, "packs", "alt", "oyun.json")));
        // İkinci açılış: yalnız yeni klasör var, olduğu gibi kullanılır.
        Assert.Equal(Current, DataFolder.OnDisk(root, migrate: true).Path);
    }

    [Fact]
    public void BothFoldersAreLeftUntouched()
    {
        Directory.CreateDirectory(Current);
        Directory.CreateDirectory(Legacy);
        File.WriteAllText(Path.Combine(Current, "settings.json"), "yeni");
        File.WriteAllText(Path.Combine(Legacy, "settings.json"), "eski");

        var result = DataFolder.OnDisk(root, migrate: true);

        Assert.Equal(Current, result.Path);
        Assert.Equal("yeni", File.ReadAllText(Path.Combine(Current, "settings.json")));
        Assert.Equal("eski", File.ReadAllText(Path.Combine(Legacy, "settings.json")));
        Assert.Single(Directory.GetFiles(Current));
    }

    [Fact]
    public void NeitherFolderCreatesTheNewOne()
    {
        Directory.CreateDirectory(root);
        var result = DataFolder.OnDisk(root, migrate: true);
        Assert.Equal(Current, result.Path);
        Assert.True(Directory.Exists(Current));
        Assert.False(Directory.Exists(Legacy));
    }

    [Fact]
    public void WithoutMigrationNothingIsMovedOrCreated()
    {
        // Testler ve başka araçlar (Prepare çağırmayanlar): eski klasör yerinde kalır, yenisi oluşturulmaz.
        Directory.CreateDirectory(Legacy);
        File.WriteAllText(Path.Combine(Legacy, "settings.json"), "eski");

        var result = DataFolder.OnDisk(root, migrate: false);

        Assert.Equal(Legacy, result.Path);
        Assert.Equal(DataFolder.LegacyName, result.FolderName);
        Assert.False(Directory.Exists(Current));
        Assert.Equal("eski", File.ReadAllText(Path.Combine(Legacy, "settings.json")));

        Directory.Delete(Legacy, recursive: true);
        Assert.Equal(Current, DataFolder.OnDisk(root, migrate: false).Path);
        Assert.False(Directory.Exists(Current));
    }

    [Fact]
    public void BlockedMoveLeavesTheLegacyFolderWholeAndCreatesNoNewFolder()
    {
        // Taşıma engellenirse (burada: hedef adında bir dosya var) eski klasör eksiksiz kalır ve kullanılır.
        Directory.CreateDirectory(Legacy);
        File.WriteAllText(Path.Combine(Legacy, "settings.json"), "eski");
        File.WriteAllText(Current, "klasör değil");

        var result = DataFolder.OnDisk(root, migrate: true);

        Assert.Equal(Legacy, result.Path);
        Assert.Equal(DataFolder.LegacyName, result.FolderName);
        Assert.NotNull(result.MoveError);
        Assert.False(Directory.Exists(Current));
        Assert.Equal("eski", File.ReadAllText(Path.Combine(Legacy, "settings.json")));
    }

    [Fact]
    public void AnotherRunningCopyDefersTheMove()
    {
        // Açık duran başka bir kopya (eski sürüm de olabilir) eski klasörü kullanıyor olabilir: klasör altından çekilmez.
        Directory.CreateDirectory(Legacy);
        File.WriteAllText(Path.Combine(Legacy, "settings.json"), "eski");

        var result = DataFolder.OnDisk(root, migrate: true, otherCopies: () => DataFolder.OtherCopies.SameApp);

        Assert.Equal(Legacy, result.Path);
        Assert.Equal(DataFolder.LegacyName, result.FolderName);
        Assert.NotNull(result.MoveError);
        Assert.False(Directory.Exists(Current));
        Assert.Equal("eski", File.ReadAllText(Path.Combine(Legacy, "settings.json")));

        // O kopya kapanınca sonraki açılış taşır.
        var later = DataFolder.OnDisk(root, migrate: true, otherCopies: () => DataFolder.OtherCopies.None);
        Assert.Equal(Current, later.Path);
        Assert.Null(later.MoveError);
        Assert.False(Directory.Exists(Legacy));
        Assert.Equal("eski", File.ReadAllText(Path.Combine(Current, "settings.json")));
    }

    [Fact]
    public void RunningCopyIsNotAskedWhenThereIsNothingToMove()
    {
        // Yeni klasör zaten kullanılıyorsa ya da hiç veri yoksa başka kopyanın açık olması bir şeyi değiştirmez.
        Directory.CreateDirectory(Current);
        File.WriteAllText(Path.Combine(Current, "settings.json"), "yeni");
        Directory.CreateDirectory(Legacy);
        var asked = 0;

        var result = DataFolder.OnDisk(root, migrate: true, otherCopies: () => { asked++; return DataFolder.OtherCopies.SameApp; });

        Assert.Equal(Current, result.Path);
        Assert.Null(result.MoveError);
        Assert.Equal(0, asked);
        Directory.Delete(Legacy);
        Assert.Equal(Current, DataFolder.OnDisk(root, migrate: true, otherCopies: () => { asked++; return DataFolder.OtherCopies.SameApp; }).Path);
        Assert.Equal(0, asked);
    }

    [Fact]
    public void EmptyNewFolderDoesNotHideTheLegacyData()
    {
        // Yeni klasör bir nedenle boş oluşmuşsa eski veri yine taşınır; yoksa ayarlar ve giriş kaybolmuş görünürdü.
        Directory.CreateDirectory(Current);
        Directory.CreateDirectory(Legacy);
        File.WriteAllText(Path.Combine(Legacy, "settings.json"), "eski");

        var result = DataFolder.OnDisk(root, migrate: true);

        Assert.Equal(Current, result.Path);
        Assert.Null(result.MoveError);
        Assert.False(Directory.Exists(Legacy));
        Assert.Equal("eski", File.ReadAllText(Path.Combine(Current, "settings.json")));
    }

    [Fact]
    public void EmptyNewFolderIsLeftAloneWithoutMigrationOrWhileAnotherCopyRuns()
    {
        Directory.CreateDirectory(Current);
        Directory.CreateDirectory(Legacy);
        File.WriteAllText(Path.Combine(Legacy, "settings.json"), "eski");

        // Prepare çağırmayanlar (testler, araçlar) diske dokunmaz: kural gereği yeni klasör.
        Assert.Equal(Current, DataFolder.OnDisk(root, migrate: false).Path);
        Assert.True(Directory.Exists(Current));

        // Başka kopya açıkken hiçbir şey silinmez ve taşınmaz; veri eski klasörden okunur.
        var result = DataFolder.OnDisk(root, migrate: true, otherCopies: () => DataFolder.OtherCopies.SameApp);
        Assert.Equal(Legacy, result.Path);
        Assert.NotNull(result.MoveError);
        Assert.True(Directory.Exists(Current));
        Assert.Equal("eski", File.ReadAllText(Path.Combine(Legacy, "settings.json")));
    }

    [Fact]
    public void NewFolderWithAnyFileWinsOverTheLegacyOne()
    {
        // Tek dosya bile olsa yeni klasör boş sayılmaz: silinmez, eskisiyle birleştirilmez.
        Directory.CreateDirectory(Current);
        File.WriteAllText(Path.Combine(Current, "hata.log"), "kayıt");
        Directory.CreateDirectory(Legacy);
        File.WriteAllText(Path.Combine(Legacy, "settings.json"), "eski");

        var result = DataFolder.OnDisk(root, migrate: true);

        Assert.Equal(Current, result.Path);
        Assert.Equal("kayıt", File.ReadAllText(Path.Combine(Current, "hata.log")));
        Assert.False(File.Exists(Path.Combine(Current, "settings.json")));
        Assert.Equal("eski", File.ReadAllText(Path.Combine(Legacy, "settings.json")));
    }

    [Fact]
    public void VelopackLauncherSitsOneFolderAboveTheApp()
    {
        // Kısayolların açtığı başlatıcı (aynı ad, bir üst klasör) açık kopya sayılmaz.
        var install = Path.Combine(root, "NinoGameTranslator");
        Assert.Equal(Path.Combine(install, "CouchSubs.exe"), DataFolder.LauncherPath(Path.Combine(install, "current", "CouchSubs.exe")));
        Assert.Null(DataFolder.LauncherPath(null));
        Assert.Null(DataFolder.LauncherPath(""));
        Assert.Null(DataFolder.LauncherPath("CouchSubs.exe"));
    }

    // --- Asıl CouchSubs'la ortak klasör: taşınmaz, kopyalanır ---

    [Fact]
    public void SharedLegacyFolderIsCopiedInsteadOfMoved()
    {
        var moves = 0;
        var copies = 0;
        var decision = DataFolder.Decide(currentExists: false, legacyExists: true, move: () => moves++,
            legacyShared: true, copy: () => copies++);
        Assert.Equal(0, moves);
        Assert.Equal(1, copies);
        Assert.False(decision.UseLegacy);
        Assert.False(decision.Moved);
        Assert.True(decision.Copied);
        Assert.Null(decision.MoveError);
    }

    [Fact]
    public void UnsharedLegacyFolderIsStillMoved()
    {
        var copies = 0;
        var decision = DataFolder.Decide(currentExists: false, legacyExists: true, move: () => { },
            legacyShared: false, copy: () => copies++);
        Assert.Equal(0, copies);
        Assert.True(decision.Moved);
        Assert.False(decision.Copied);
    }

    [Fact]
    public void FailedCopyKeepsUsingTheLegacyFolder()
    {
        var error = new IOException("kilitli");
        var decision = DataFolder.Decide(currentExists: false, legacyExists: true, move: () => Assert.Fail("taşınmamalı"),
            currentExistsNow: () => false, legacyShared: true, copy: () => throw error);
        Assert.True(decision.UseLegacy);
        Assert.False(decision.Copied);
        Assert.Same(error, decision.MoveError);
    }

    [Fact]
    public void SharedFolderIsNeitherMovedNorCopiedWithoutMigrationOrWhenTheNewFolderExists()
    {
        var waiting = DataFolder.Decide(currentExists: false, legacyExists: true, move: () => Assert.Fail("taşınmamalı"),
            legacyShared: true, copy: null);
        Assert.True(waiting.UseLegacy);
        Assert.False(waiting.Copied);

        var existing = DataFolder.Decide(currentExists: true, legacyExists: true, move: () => Assert.Fail("taşınmamalı"),
            legacyShared: true, copy: () => Assert.Fail("kopyalanmamalı"));
        Assert.False(existing.UseLegacy);
        Assert.False(existing.Copied);
    }

    /// <summary>Asıl CouchSubs'ın veri klasörü: ayarlar, giriş, paketler ve kopyalanmaması gereken büyük ya da yabancı girdiler.</summary>
    private void FillLegacy()
    {
        Directory.CreateDirectory(Path.Combine(Legacy, "packs", "alt"));
        Directory.CreateDirectory(Path.Combine(Legacy, "adb"));
        Directory.CreateDirectory(Path.Combine(Legacy, "samsung"));
        Directory.CreateDirectory(Path.Combine(Legacy, "models", "en-tr-ct2"));
        Directory.CreateDirectory(Path.Combine(Legacy, "cuda-12.8"));
        Directory.CreateDirectory(Path.Combine(Legacy, "webview", "EBWebView"));
        Directory.CreateDirectory(Path.Combine(Legacy, "xbox-webview"));
        File.WriteAllText(Path.Combine(Legacy, "settings.json"), "{\"a\":1}");
        File.WriteAllBytes(Path.Combine(Legacy, "secure.dat"), [1, 2, 3]);
        File.WriteAllText(Path.Combine(Legacy, "history.json"), "geçmiş");
        File.WriteAllText(Path.Combine(Legacy, "packs", "alt", "oyun.json"), "paket");
        File.WriteAllText(Path.Combine(Legacy, "adb", "adbkey"), "anahtar");
        File.WriteAllText(Path.Combine(Legacy, "samsung", "author.p12"), "sertifika");
        File.WriteAllText(Path.Combine(Legacy, "models", "en-tr-ct2", "model.bin"), "büyük");
        File.WriteAllText(Path.Combine(Legacy, "cuda-12.8", "cublas64_12.dll"), "büyük");
        File.WriteAllText(Path.Combine(Legacy, "webview", "EBWebView", "Cookies"), "çerez");
        File.WriteAllText(Path.Combine(Legacy, "xbox-webview", "Local State"), "durum");
        File.WriteAllText(Path.Combine(Legacy, "hata.log"), "onların günlüğü");
        File.WriteAllText(Path.Combine(Legacy, "altyazi.log.1"), "onların günlüğü");
        File.WriteAllText(Path.Combine(Legacy, "secure.dat.tmp"), "yarım");
    }

    private static string[] Listing(string folder) =>
        [.. Directory.EnumerateFileSystemEntries(folder, "*", SearchOption.AllDirectories)
            .Select(path => Path.GetRelativePath(folder, path).Replace('\\', '/')).Order(StringComparer.Ordinal)];

    private void AssertDataCopiedAndLegacyIntact(DataFolder.Resolution result, string[] legacyBefore)
    {
        Assert.Equal(Current, result.Path);
        Assert.Equal(DataFolder.Name, result.FolderName);
        Assert.True(result.Copied);
        Assert.Null(result.MoveError);
        // Eski klasör olduğu gibi yerinde.
        Assert.Equal(legacyBefore, Listing(Legacy));
        Assert.Equal("{\"a\":1}", File.ReadAllText(Path.Combine(Legacy, "settings.json")));
        // Veri kopyalandı.
        Assert.Equal("{\"a\":1}", File.ReadAllText(Path.Combine(Current, "settings.json")));
        Assert.Equal(new byte[] { 1, 2, 3 }, File.ReadAllBytes(Path.Combine(Current, "secure.dat")));
        Assert.Equal("geçmiş", File.ReadAllText(Path.Combine(Current, "history.json")));
        Assert.Equal("paket", File.ReadAllText(Path.Combine(Current, "packs", "alt", "oyun.json")));
        Assert.Equal("anahtar", File.ReadAllText(Path.Combine(Current, "adb", "adbkey")));
        Assert.Equal("sertifika", File.ReadAllText(Path.Combine(Current, "samsung", "author.p12")));
        Assert.True(File.Exists(Path.Combine(Current, DataFolder.CopyNoteFile)));
        // Modeller, CUDA, WebView2 profilleri, günlükler ve kurulum girdileri kopyalanmadı.
        foreach (var skipped in new[] { "models", "cuda-12.8", "webview", "xbox-webview", "current", "packages" })
            Assert.False(Directory.Exists(Path.Combine(Current, skipped)), skipped);
        foreach (var skipped in new[] { "hata.log", "altyazi.log.1", "secure.dat.tmp", "Update.exe", "CouchSubs.exe" })
            Assert.False(File.Exists(Path.Combine(Current, skipped)), skipped);
        // Geçici klasör kalmadı.
        Assert.Empty(Directory.EnumerateDirectories(root, DataFolder.Name + DataFolder.CopySuffix + "*"));
    }

    [Fact]
    public void UpstreamInstallNextToTheDataFolderMeansCopy()
    {
        // Asıl CouchSubs kurulu (%LOCALAPPDATA%\CouchSubsApp): veri klasörü onun da klasörü, taşınmaz.
        FillLegacy();
        var install = Path.Combine(root, DataFolder.UpstreamInstallName);
        Directory.CreateDirectory(Path.Combine(install, "current"));
        File.WriteAllText(Path.Combine(install, "Update.exe"), "kurulum");
        File.WriteAllText(Path.Combine(install, "current", "CouchSubs.exe"), "uygulama");
        var before = Listing(Legacy);

        var result = DataFolder.OnDisk(root, migrate: true);

        AssertDataCopiedAndLegacyIntact(result, before);
        Assert.True(File.Exists(Path.Combine(install, "current", "CouchSubs.exe")));
        // Sonraki açılış: yeni klasör var, hiçbir şey yeniden kopyalanmaz.
        File.WriteAllText(Path.Combine(Current, "settings.json"), "nino");
        var again = DataFolder.OnDisk(root, migrate: true);
        Assert.Equal(Current, again.Path);
        Assert.False(again.Copied);
        Assert.Equal("nino", File.ReadAllText(Path.Combine(Current, "settings.json")));
    }

    [Fact]
    public void InstallInsideTheLegacyFolderMeansCopyAndTheInstallStays()
    {
        // Eski klasörün kendisi bir Velopack kurulum köküyse taşımak o uygulamanın kurulumunu da götürürdü.
        FillLegacy();
        Directory.CreateDirectory(Path.Combine(Legacy, "current"));
        Directory.CreateDirectory(Path.Combine(Legacy, "packages"));
        File.WriteAllText(Path.Combine(Legacy, "Update.exe"), "kurulum");
        File.WriteAllText(Path.Combine(Legacy, "CouchSubs.exe"), "başlatıcı");
        File.WriteAllText(Path.Combine(Legacy, "current", "CouchSubs.exe"), "uygulama");
        File.WriteAllText(Path.Combine(Legacy, "packages", "CouchSubsApp-1.0.0-full.nupkg"), "paket");
        var before = Listing(Legacy);

        var result = DataFolder.OnDisk(root, migrate: true);

        AssertDataCopiedAndLegacyIntact(result, before);
        Assert.Equal("uygulama", File.ReadAllText(Path.Combine(Legacy, "current", "CouchSubs.exe")));
    }

    [Theory]
    [InlineData("Update.exe", false)]
    [InlineData("current", true)]
    [InlineData("packages", true)]
    public void EachInstallMarkerAloneMeansCopy(string marker, bool isDirectory)
    {
        Directory.CreateDirectory(Legacy);
        File.WriteAllText(Path.Combine(Legacy, "settings.json"), "eski");
        if (isDirectory) Directory.CreateDirectory(Path.Combine(Legacy, marker));
        else File.WriteAllText(Path.Combine(Legacy, marker), "x");

        var result = DataFolder.OnDisk(root, migrate: true);

        Assert.True(result.Copied);
        Assert.True(Directory.Exists(Legacy));
        Assert.Equal("eski", File.ReadAllText(Path.Combine(Current, "settings.json")));
    }

    [Fact]
    public void AnotherAppRunningFromElsewhereMeansCopy()
    {
        // Kurulum işareti yok (ör. zip'ten açılmış asıl CouchSubs) ama uygulama açık: klasör altından çekilmez.
        FillLegacy();
        var before = Listing(Legacy);

        var result = DataFolder.OnDisk(root, migrate: true, otherCopies: () => DataFolder.OtherCopies.OtherApp);

        AssertDataCopiedAndLegacyIntact(result, before);
    }

    [Fact]
    public void SecondCopyOfThisAppStillDefersEvenWhenTheFolderIsShared()
    {
        FillLegacy();
        Directory.CreateDirectory(Path.Combine(root, DataFolder.UpstreamInstallName, "current"));
        var before = Listing(Legacy);

        var result = DataFolder.OnDisk(root, migrate: true, otherCopies: () => DataFolder.OtherCopies.SameApp);

        Assert.Equal(Legacy, result.Path);
        Assert.False(result.Copied);
        Assert.NotNull(result.MoveError);
        Assert.False(Directory.Exists(Current));
        Assert.Equal(before, Listing(Legacy));
    }

    [Fact]
    public void WithoutAnySignTheLegacyFolderIsStillMovedWhole()
    {
        FillLegacy();
        Directory.CreateDirectory(Path.Combine(root, "BaşkaUygulama", "current"));

        var result = DataFolder.OnDisk(root, migrate: true, otherCopies: () => DataFolder.OtherCopies.None);

        Assert.Equal(Current, result.Path);
        Assert.False(result.Copied);
        Assert.False(Directory.Exists(Legacy));
        // Taşımada her şey gelir (modeller dahil).
        Assert.Equal("büyük", File.ReadAllText(Path.Combine(Current, "models", "en-tr-ct2", "model.bin")));
        Assert.False(File.Exists(Path.Combine(Current, DataFolder.CopyNoteFile)));
    }

    [Fact]
    public void FailedCopyLeavesNoNewFolderAndIsRetriedOnTheNextStart()
    {
        // Kopya yarıda kalırsa (burada: hedef adında bir dosya var, son yeniden adlandırma olmaz) yarım klasör
        // "Nino" olmaz; eski klasör kullanılır ve eksiksiz kalır.
        FillLegacy();
        File.WriteAllText(Path.Combine(Legacy, "Update.exe"), "kurulum");
        var before = Listing(Legacy);
        File.WriteAllText(Current, "klasör değil");

        var result = DataFolder.OnDisk(root, migrate: true);

        Assert.Equal(Legacy, result.Path);
        Assert.Equal(DataFolder.LegacyName, result.FolderName);
        Assert.False(result.Copied);
        Assert.NotNull(result.MoveError);
        Assert.False(Directory.Exists(Current));
        Assert.Equal(before, Listing(Legacy));
        Assert.Empty(Directory.EnumerateDirectories(root, DataFolder.Name + DataFolder.CopySuffix + "*"));

        // Engel kalkınca sonraki açılış kopyalar.
        File.Delete(Current);
        AssertDataCopiedAndLegacyIntact(DataFolder.OnDisk(root, migrate: true), before);
    }

    [Fact]
    public void LeftoverTemporaryFolderFromAnInterruptedCopyIsRemoved()
    {
        FillLegacy();
        File.WriteAllText(Path.Combine(Legacy, "Update.exe"), "kurulum");
        var before = Listing(Legacy);
        var leftover = Path.Combine(root, DataFolder.Name + DataFolder.CopySuffix + "eski");
        Directory.CreateDirectory(leftover);
        File.WriteAllText(Path.Combine(leftover, "settings.json"), "yarım");

        AssertDataCopiedAndLegacyIntact(DataFolder.OnDisk(root, migrate: true), before);
        Assert.False(Directory.Exists(leftover));
    }

    [Fact]
    public void SharedFolderIsNotTouchedWithoutMigration()
    {
        // Prepare çağırmayanlar (testler, araçlar) ortak klasörde de diske yazmaz.
        FillLegacy();
        File.WriteAllText(Path.Combine(Legacy, "Update.exe"), "kurulum");
        var before = Listing(Legacy);

        var result = DataFolder.OnDisk(root, migrate: false);

        Assert.Equal(Legacy, result.Path);
        Assert.False(result.Copied);
        Assert.False(Directory.Exists(Current));
        Assert.Equal(before, Listing(Legacy));
    }

    [Theory]
    [InlineData("settings.json", false, false)]
    [InlineData("secure.dat", false, false)]
    [InlineData("packs", true, false)]
    [InlineData("adb", true, false)]
    [InlineData("samsung", true, false)]
    [InlineData("pool", true, false)]
    [InlineData("translations", true, false)]
    [InlineData("glossary", true, false)]
    [InlineData("current", true, true)]
    [InlineData("packages", true, true)]
    [InlineData("Models", true, true)]
    [InlineData("cuda-12.8", true, true)]
    [InlineData("webview", true, true)]
    [InlineData("xbox-webview", true, true)]
    [InlineData("Update.exe", false, true)]
    [InlineData("CouchSubs.exe", false, true)]
    [InlineData("hata.log", false, true)]
    [InlineData("remoteplay.log", false, true)]
    [InlineData("altyazi.log.1", false, true)]
    [InlineData("secure.dat.tmp", false, true)]
    public void CopySkipsOnlyInstallEntriesLargeDownloadsBrowserProfilesAndLogs(string name, bool isDirectory, bool skipped) =>
        Assert.Equal(skipped, DataFolder.SkippedInCopy(name, isDirectory));

    [Fact]
    public void RunningCopiesAreToldApartByTheirFolder()
    {
        var install = Path.Combine(root, "NinoGameTranslator");
        var self = Path.Combine(install, "current", "CouchSubs.exe");
        var launcher = Path.Combine(install, "CouchSubs.exe");
        var upstream = Path.Combine(root, DataFolder.UpstreamInstallName, "current", "CouchSubs.exe");

        Assert.Equal(DataFolder.OtherCopies.None, DataFolder.Classify(self, []));
        // Velopack başlatıcısı açık kopya sayılmaz.
        Assert.Equal(DataFolder.OtherCopies.None, DataFolder.Classify(self, [launcher]));
        // Aynı klasörden çalışan: bu uygulamanın ikinci kopyası.
        Assert.Equal(DataFolder.OtherCopies.SameApp, DataFolder.Classify(self, [self]));
        Assert.Equal(DataFolder.OtherCopies.SameApp, DataFolder.Classify(self, [upstream, self]));
        // Başka klasörden çalışan: başka uygulama (asıl CouchSubs ya da başka yere açılmış eski kopya).
        Assert.Equal(DataFolder.OtherCopies.OtherApp, DataFolder.Classify(self, [upstream]));
        Assert.Equal(DataFolder.OtherCopies.OtherApp, DataFolder.Classify(self, [launcher, upstream]));
        // Yolu okunamayan süreç ya da kendi yolumuz bilinmiyorsa temkinli davranılır: ertelenir.
        Assert.Equal(DataFolder.OtherCopies.SameApp, DataFolder.Classify(self, [upstream, null]));
        Assert.Equal(DataFolder.OtherCopies.SameApp, DataFolder.Classify(null, [upstream]));
        Assert.Equal(DataFolder.OtherCopies.None, DataFolder.Classify(null, []));
    }

    // --- Gösterilen yol ve bu süreçteki karar ---

    [Fact]
    public void DisplayedPathNamesTheFolderInUse()
    {
        Assert.Equal(@"%LOCALAPPDATA%\Nino\hata.log", DataFolder.Display(DataFolder.Name, "hata.log"));
        Assert.Equal(@"%LOCALAPPDATA%\CouchSubs\hata.log", DataFolder.Display(DataFolder.LegacyName, "hata.log"));
    }

    [Fact]
    public void EveryDefaultPathSitsInTheOneFolder()
    {
        var folder = DataFolder.Path;
        Assert.Equal(folder, DataFolder.Path);
        Assert.Equal(DataFolder.FolderName, Path.GetFileName(folder));
        Assert.Contains(DataFolder.FolderName, new[] { DataFolder.Name, DataFolder.LegacyName });
        Assert.Equal(Path.Combine(folder, "packs"), GamePackLibrary.UserDirectory);
        Assert.Equal(Path.Combine(folder, "glossary"), GlossaryStore.UserDirectory);
        Assert.Equal(Path.Combine(folder, "history.json"), SubtitleHistory.DefaultFile);
        Assert.Equal(Path.Combine(folder, "altyazi.log"), SubtitleLog.DefaultPath);
        Assert.Equal($@"%LOCALAPPDATA%\{DataFolder.FolderName}\altyazi.log", SubtitleLog.DisplayPath);
    }

    [Fact]
    public void OutsideWindowsTheFolderKeepsItsOldName()
    {
        // Linux sunucusu ve Mac'teki testler: taşıma yok, ad değişmez (linux/CouchSubs.Linux/Stores.cs ile aynı klasör).
        if (OperatingSystem.IsWindows()) return;
        Assert.Equal(DataFolder.LegacyName, DataFolder.FolderName);
        Assert.Equal(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), DataFolder.LegacyName), DataFolder.Path);
    }
}
