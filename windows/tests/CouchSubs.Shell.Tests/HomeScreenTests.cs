// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Text;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.Shell.Tests;

/// <summary>Nino: ana ekranın TV'sindeki toplam indirme ve alt şeritteki çeviri kaynağı yazısı.</summary>
public sealed class HomeScreenTests : IDisposable
{
    /// <summary>Ayar isteğine verilen cevabı döner; null ise sunucuya ulaşılamıyor.</summary>
    private sealed class Server : HttpMessageHandler
    {
        public string? Reply;

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            Task.FromResult(Reply is null || request.RequestUri!.AbsolutePath != "/v1/config"
                ? new HttpResponseMessage(HttpStatusCode.NotFound)
                : new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(Reply, Encoding.UTF8, "application/json") });
    }

    private readonly DirectoryInfo directory = Directory.CreateTempSubdirectory("nino-home-");
    private readonly Server server = new();
    private DateTimeOffset now = DateTimeOffset.FromUnixTimeSeconds(1_763_300_000);
    private readonly List<TranslationPool> pools = [];

    public void Dispose()
    {
        foreach (var pool in pools) pool.Dispose();
        directory.Delete(recursive: true);
    }

    private TranslationPool Pool()
    {
        var pool = new TranslationPool(directory.FullName, new Uri("https://pool.invalid/"), "0.0.0", "windows", "tr", handler: server, clock: () => now);
        pools.Add(pool);
        return pool;
    }

    /// Sayı sunucunun ayarıyla gelir, değişince ekran haberdar edilir; alınamazsa son bilinen kalır, hiç alınamadıysa yoktur.
    [Fact]
    public async Task DownloadTotalComesFromThePoolConfigAndSurvivesFailures()
    {
        var controller = AppControllerTests.Make(new FakeServices { Translations = Pool() });
        var changed = new List<string?>();
        controller.PropertyChanged += (_, e) => changed.Add(e.PropertyName);

        // Sunucuya ulaşılamıyor ve daha önce hiç alınmadı: gösterge yok.
        await controller.RefreshDownloadsAsync();
        Assert.Null(controller.DownloadTotal);
        Assert.DoesNotContain(nameof(AppController.DownloadTotal), changed);

        now += TimeSpan.FromMinutes(11);
        server.Reply = """{"translate":{"enabled":true},"downloads":3439}""";
        await controller.RefreshDownloadsAsync();
        Assert.Equal(3439, controller.DownloadTotal);
        Assert.Contains(nameof(AppController.DownloadTotal), changed);

        // Sonra internet gitti: son bilinen sayı kalır, boşuna bildirim yapılmaz.
        changed.Clear();
        now += TimeSpan.FromMinutes(11);
        server.Reply = null;
        await controller.RefreshDownloadsAsync();
        Assert.Equal(3439, controller.DownloadTotal);
        Assert.DoesNotContain(nameof(AppController.DownloadTotal), changed);

        // Uygulama yeniden açıldı, sunucu yine yok: saklanan sayı.
        Assert.Equal(3439, AppControllerTests.Make(new FakeServices { Translations = Pool() }).DownloadTotal);
        // Havuzsuz derlemede gösterge hiç yoktur.
        var without = AppControllerTests.Make();
        await without.RefreshDownloadsAsync();
        Assert.Null(without.DownloadTotal);
    }

    /// Alt şerit: yalnız GTA 6 TANININCA "Nino · GTA 6 active"; oyun tanınmadan önce ve başka oyunda seçili motor.
    [Fact]
    public void TranslationSourceShowsNinoOnlyOnceGta6IsRecognised()
    {
        var controller = AppControllerTests.Make(new FakeServices { Translations = Pool() });
        var changed = new List<string?>();
        controller.PropertyChanged += (_, e) => changed.Add(e.PropertyName);
        var engine = controller.Settings.Engine == TranslationEngine.Free ? "Free" : controller.Settings.Engine.DisplayName();

        // Oyun henüz tanınmadı: kullanıcının seçtiği motor.
        Assert.Equal(engine, controller.TranslationSourceText);

        controller.ChooseGame("Grand Theft Auto VI");
        Assert.Equal("Nino · GTA 6 active", controller.TranslationSourceText);
        Assert.Contains(nameof(AppController.TranslationSourceText), changed);

        // Oyun değişti: yazı kendiliğinden motora döner.
        changed.Clear();
        controller.ChooseGame("Red Dead Redemption 2");
        Assert.Equal(engine, controller.TranslationSourceText);
        Assert.Contains(nameof(AppController.TranslationSourceText), changed);

        // Havuz bu dilde çevirmiyorsa GTA 6'da da seçili motor görünür.
        var german = AppControllerTests.Make(new FakeServices { Translations = Pool() });
        german.Settings = german.Settings with { TargetLanguage = "de" };
        german.ChooseGame("Grand Theft Auto VI");
        Assert.NotEqual("Nino · GTA 6 active", german.TranslationSourceText);
    }
}
