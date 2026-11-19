// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Shell;

namespace CouchSubs.Shell.Tests;

/// <summary>Gerçeği Velopack: indirir, sonra kurup uygulamayı yeniden başlatır. Burada kurulum yalnız sayılır.</summary>
internal sealed class FakeUpdater : IUpdater
{
    public bool CanUpdateItself { get; set; } = true;
    public Uri DownloadPage { get; } = new("https://example.test/releases/latest");
    public string? Version { get; set; } = "9.9.9";
    /// <summary>İndirme bu hatayla yarıda kalır (kurulum başlamaz).</summary>
    public Exception? DownloadError { get; set; }
    /// <summary>Verilirse indirme bu görev bitene kadar sürer.</summary>
    public Task? DownloadGate { get; set; }
    public int Downloads { get; private set; }
    public int Applied { get; private set; }

    public Task<string?> CheckAsync() => Task.FromResult(Version);

    public async Task InstallAsync(IProgress<double> progress, Action? beforeApply = null)
    {
        Downloads++;
        if (DownloadGate is { } gate) await gate;
        if (DownloadError is { } error) throw error;
        beforeApply?.Invoke();
        Applied++;
    }
}

public class AutoUpdateTests : IDisposable
{
    private readonly string file = Path.Combine(Path.GetTempPath(), "nino-auto-update-test-" + Guid.NewGuid().ToString("N") + ".txt");

    public void Dispose()
    {
        try { File.Delete(file); } catch (IOException) { }
    }

    /// <summary>Kurulumu bitmiş bir uygulama; aynı dosyayı paylaşan yeni denetleyici "yeniden açılış" demektir.</summary>
    private AppController Open(FakeUpdater updater) =>
        AppControllerRunTests.Ready(new FakeServices { Updater = updater, AutoUpdateFile = file }).Controller;

    [Fact]
    public async Task NewVersionInstallsItselfWhenIdle()
    {
        var updater = new FakeUpdater();
        var controller = Open(updater);
        await controller.CheckForUpdateAsync();
        Assert.Equal("9.9.9", controller.UpdateVersion);
        Assert.Equal(1, updater.Applied);
        Assert.Null(controller.UpdateError);
        Assert.False(controller.Updating);
        controller.Dispose();
    }

    [Fact]
    public async Task FailedDownloadDoesNotUseUpTheAutomaticInstall()
    {
        // İndirme yarıda kaldı (ağ koptu): o sürüm sonraki açılışta yine kendiliğinden kurulur.
        var updater = new FakeUpdater { DownloadError = new HttpRequestException("bağlantı koptu") };
        var controller = Open(updater);
        await controller.CheckForUpdateAsync();
        Assert.Equal(0, updater.Applied);
        Assert.Equal("bağlantı koptu", controller.UpdateError);
        Assert.False(File.Exists(file));
        Assert.Equal(0, new AutoUpdateLog(file).Attempts("9.9.9"));
        controller.Dispose();

        updater.DownloadError = null;
        var reopened = Open(updater);
        await reopened.CheckForUpdateAsync();
        Assert.Equal(1, updater.Applied);
        Assert.Equal(1, new AutoUpdateLog(file).Attempts("9.9.9"));
        reopened.Dispose();
    }

    [Fact]
    public async Task FailedDownloadIsRetriedInTheSameRunButNotForever()
    {
        // Üç saatlik denetim yeniden dener; sürekli başarısız indirme bu açılışta üç denemeden sonra bırakılır.
        var updater = new FakeUpdater { DownloadError = new HttpRequestException("bağlantı koptu") };
        var controller = Open(updater);
        for (var i = 0; i < 6; i++) await controller.CheckForUpdateAsync();
        Assert.Equal(3, updater.Downloads);
        Assert.Equal(0, updater.Applied);
        // Düğme çalışmaya devam eder.
        updater.DownloadError = null;
        await controller.InstallUpdateAsync();
        Assert.Equal(1, updater.Applied);
        controller.Dispose();
    }

    [Fact]
    public async Task InstallThatDoesNotChangeTheVersionStopsAfterAFewAttempts()
    {
        // Kurulum başlıyor ama yeniden açılan uygulama hâlâ eski sürüm: sonsuz yeniden başlatma döngüsü olmamalı.
        var updater = new FakeUpdater();
        for (var restart = 0; restart < AutoUpdateLog.MaxAttempts + 3; restart++)
        {
            var controller = Open(updater);
            await controller.CheckForUpdateAsync();
            controller.Dispose();
        }
        Assert.Equal(AutoUpdateLog.MaxAttempts, updater.Applied);
        Assert.Equal(AutoUpdateLog.MaxAttempts, updater.Downloads);

        // Düğme kalır ve çalışır.
        var last = Open(updater);
        await last.CheckForUpdateAsync();
        Assert.Equal("9.9.9", last.UpdateVersion);
        await last.InstallUpdateAsync();
        Assert.Equal(AutoUpdateLog.MaxAttempts + 1, updater.Applied);
        last.Dispose();

        // Daha yeni bir sürüm çıkınca sayaç baştan başlar.
        updater.Version = "10.0.0";
        var newer = Open(updater);
        await newer.CheckForUpdateAsync();
        Assert.Equal(AutoUpdateLog.MaxAttempts + 2, updater.Applied);
        newer.Dispose();
    }

    [Fact]
    public async Task UpdateFoundWhileTranslatingWaitsForStop()
    {
        var updater = new FakeUpdater();
        var controller = Open(updater);
        await controller.StartAsync();
        Assert.True(controller.IsRunning);
        await controller.CheckForUpdateAsync();
        Assert.Equal(0, updater.Downloads);
        Assert.True(controller.IsRunning);

        controller.Stop();
        Assert.Equal(1, updater.Downloads);
        Assert.Equal(1, updater.Applied);
        controller.Dispose();
    }

    [Fact]
    public async Task ClosingWhileTranslatingDoesNotStartTheInstall()
    {
        // Pencere kapanırken (Dispose → Stop) kurulum başlatılmaz: indirme kapanan uygulamada yarıda kalırdı.
        var updater = new FakeUpdater();
        var controller = Open(updater);
        await controller.StartAsync();
        await controller.CheckForUpdateAsync();
        controller.Dispose();
        Assert.Equal(0, updater.Downloads);
        Assert.Equal(0, updater.Applied);
        Assert.False(File.Exists(file));

        // Bekleyen güncelleme sonraki açılışta kurulur.
        var reopened = Open(updater);
        await reopened.CheckForUpdateAsync();
        Assert.Equal(1, updater.Applied);
        reopened.Dispose();
    }

    [Fact]
    public async Task ClosingDuringTheDownloadDoesNotCountAsAnAttempt()
    {
        // Kullanıcı indirme sürerken uygulamayı kapattı: süreç ölür, kurulum hiç başlamaz, hak tükenmez.
        var gate = new TaskCompletionSource();
        var updater = new FakeUpdater { DownloadGate = gate.Task };
        var controller = Open(updater);
        var check = controller.CheckForUpdateAsync();
        Assert.True(controller.Updating);
        controller.Dispose();
        Assert.Equal(1, updater.Downloads);
        Assert.Equal(0, new AutoUpdateLog(file).Attempts("9.9.9"));

        updater.DownloadGate = null;
        var reopened = Open(updater);
        await reopened.CheckForUpdateAsync();
        Assert.Equal(1, updater.Applied);
        reopened.Dispose();
        gate.SetResult();
        await check;
    }

    [Fact]
    public async Task UpdateButtonWhileTranslatingInstallsOnlyOnce()
    {
        // Düğmenin kendi Stop() çağrısı bekleyen kendiliğinden kurulumu ikinci kez sıraya almaz.
        var updater = new FakeUpdater();
        var controller = Open(updater);
        await controller.StartAsync();
        await controller.CheckForUpdateAsync();
        await controller.InstallUpdateAsync();
        Assert.False(controller.IsRunning);
        Assert.Equal(1, updater.Downloads);
        Assert.Equal(1, updater.Applied);
        controller.Stop();
        Assert.Equal(1, updater.Downloads);
        controller.Dispose();
    }

    [Fact]
    public async Task ZipCopyOnlyOpensTheDownloadPage()
    {
        var updater = new FakeUpdater { CanUpdateItself = false };
        var controller = Open(updater);
        Uri? opened = null;
        controller.OpenInBrowser = uri => opened = uri;
        await controller.CheckForUpdateAsync();
        Assert.Equal(0, updater.Downloads);
        Assert.Null(opened);
        await controller.InstallUpdateAsync();
        Assert.Equal(updater.DownloadPage, opened);
        Assert.Equal(0, updater.Downloads);
        controller.Dispose();
    }

    [Fact]
    public async Task UnwritableAttemptFileBlocksOnlyTheAutomaticInstall()
    {
        // Sayaç yazılamıyorsa (burada: dosyanın yerinde bir klasör var) kendiliğinden kurulmaz; yoksa sürümü
        // değiştirmeyen kurulum her açılışta yeniden başlardı. Düğme yine kurar.
        Directory.CreateDirectory(file);
        try
        {
            var updater = new FakeUpdater();
            var controller = Open(updater);
            await controller.CheckForUpdateAsync();
            Assert.Equal(1, updater.Downloads);
            Assert.Equal(0, updater.Applied);
            Assert.NotNull(controller.UpdateError);
            await controller.InstallUpdateAsync();
            Assert.Equal(1, updater.Applied);
            controller.Dispose();
        }
        finally
        {
            Directory.Delete(file);
        }
    }

    // --- Sayaç dosyası ---

    [Fact]
    public void AttemptsAreCountedPerVersionAndSurviveARestart()
    {
        var log = new AutoUpdateLog(file);
        Assert.Equal(0, log.Attempts("1.2.3"));
        Assert.False(log.Exhausted("1.2.3"));
        Assert.True(log.Record("1.2.3"));
        Assert.Equal(1, new AutoUpdateLog(file).Attempts("1.2.3"));
        Assert.True(log.Record("1.2.3"));
        Assert.Equal(AutoUpdateLog.MaxAttempts, new AutoUpdateLog(file).Attempts("1.2.3"));
        Assert.True(new AutoUpdateLog(file).Exhausted("1.2.3"));
        // Başka sürüm baştan sayılır.
        Assert.Equal(0, new AutoUpdateLog(file).Attempts("1.2.4"));
        Assert.True(log.Record("1.2.4"));
        Assert.Equal(1, new AutoUpdateLog(file).Attempts("1.2.4"));
        Assert.Equal(0, new AutoUpdateLog(file).Attempts("1.2.3"));
    }

    [Fact]
    public void OldFormatFileCountsAsOneAttempt()
    {
        // Önceki sürümler dosyaya yalnız sürümü yazardı (kurulumdan önce).
        File.WriteAllText(file, "1.2.3");
        var log = new AutoUpdateLog(file);
        Assert.Equal(1, log.Attempts("1.2.3"));
        Assert.False(log.Exhausted("1.2.3"));
        Assert.Equal(0, log.Attempts("1.2.4"));
    }

    [Fact]
    public void WithoutAFileAttemptsAreKeptInMemory()
    {
        var log = new AutoUpdateLog(null);
        Assert.True(log.Record("1.2.3"));
        Assert.True(log.Record("1.2.3"));
        Assert.True(log.Exhausted("1.2.3"));
        Assert.False(log.Exhausted("1.2.4"));
    }
}
