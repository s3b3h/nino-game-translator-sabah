// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Net;
using System.Text;
using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>Nino: ana ekrandaki "Toplam indirme" sayısı (Mac: DownloadCounterTests).</summary>
public sealed class DownloadCounterTests : IDisposable
{
    /// <summary>Ayar isteğine verilen cevabı döner; null ise sunucuya ulaşılamıyor (503).</summary>
    private sealed class Server : HttpMessageHandler
    {
        public string? Reply;
        public int Asked;

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath != "/v1/config") return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
            Asked++;
            return Task.FromResult(Reply is null
                ? new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)
                : new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(Reply, Encoding.UTF8, "application/json") });
        }
    }

    private readonly string directory = Path.Combine(Path.GetTempPath(), "nino-downloads-" + Guid.NewGuid());
    private readonly Server server = new();
    private readonly List<TranslationPool> pools = [];

    public void Dispose()
    {
        foreach (var pool in pools) pool.Dispose();
        try { Directory.Delete(directory, true); } catch (IOException) { }
    }

    private TranslationPool Pool(Uri? endpoint)
    {
        var pool = new TranslationPool(directory, endpoint, "0.2.1", "windows", "tr", handler: server);
        pools.Add(pool);
        return pool;
    }

    [Fact]
    public void ParsesTheServerReply()
    {
        Assert.Equal(3439, DownloadCounter.Parse("""{"ok":true,"downloads":3439}"""));
        Assert.Null(DownloadCounter.Parse("""{"ok":true}"""));
        Assert.Null(DownloadCounter.Parse("""{"downloads":0}"""));
        Assert.Null(DownloadCounter.Parse("bozuk"));
        // Sayı olmayan ya da kesirli/eksi değer sayılmaz; cevap hiç yoksa da.
        Assert.Null(DownloadCounter.Parse("""{"downloads":"3439"}"""));
        Assert.Null(DownloadCounter.Parse("""{"downloads":-5}"""));
        Assert.Null(DownloadCounter.Parse("""{"downloads":12.5}"""));
        Assert.Null(DownloadCounter.Parse("""[3439]"""));
        Assert.Null(DownloadCounter.Parse(null));
    }

    /// Sayı alınamazsa son bilinen sayı kalır; yeniden açılışta da oradan başlar. Üstüne ekleme yapılmaz.
    [Fact]
    public async Task KeepsTheLastKnownTotalWhenTheServerCannotBeReached()
    {
        var pool = Pool(new Uri("http://localhost:8787/"));
        // Hiç alınamadı: gösterge görünmez.
        Assert.Null(pool.Downloads.Total);

        server.Reply = """{"translate":{"enabled":true},"downloads":3439}""";
        await pool.RefreshConfigAsync(force: true);
        Assert.Equal(3439, pool.Downloads.Total);

        // Sunucuya ulaşılamıyor.
        server.Reply = null;
        await pool.RefreshConfigAsync(force: true);
        Assert.Equal(3439, pool.Downloads.Total);

        // Cevap geldi ama sayı yok (eski sunucu) ya da bozuk.
        server.Reply = """{"translate":{"enabled":true}}""";
        await pool.RefreshConfigAsync(force: true);
        Assert.Equal(3439, pool.Downloads.Total);
        server.Reply = "bozuk";
        await pool.RefreshConfigAsync(force: true);
        Assert.Equal(3439, pool.Downloads.Total);
        Assert.Equal(4, server.Asked);

        // Yeniden açılış, sunucu yok: saklanan sayı.
        Assert.Equal(3439, Pool(endpoint: null).Downloads.Total);
        Assert.Equal(3439, new DownloadCounter(Path.Combine(directory, DownloadCounter.FileName)).Total);
    }

    /// Sayı ayar cevabının geri kalanından bağımsızdır: çeviri bölümü olmasa da alınır; yeni sayı eskisinin yerine geçer.
    [Fact]
    public async Task TheTotalDoesNotDependOnTheRestOfTheReply()
    {
        var pool = Pool(new Uri("http://localhost:8787/"));
        server.Reply = """{"ok":true,"downloads":3439}""";
        await pool.RefreshConfigAsync(force: true);
        Assert.Equal(3439, pool.Downloads.Total);
        // Çeviri ayarı varsayılanda kalır.
        Assert.True(pool.CurrentConfig.Enabled);

        server.Reply = """{"translate":{"enabled":true},"poolFirst":{"games":["grand-theft-auto-vi"]},"downloads":3502}""";
        await pool.RefreshConfigAsync(force: true);
        Assert.Equal(3502, pool.Downloads.Total);
        Assert.Equal("3502", File.ReadAllText(Path.Combine(directory, DownloadCounter.FileName)));
    }

    /// Ayar en çok 10 dakikada bir sorulur: ana ekranın yenilemesi ayrı istek üretmez.
    [Fact]
    public async Task AsksTheServerAtMostOncePerInterval()
    {
        var pool = Pool(new Uri("http://localhost:8787/"));
        server.Reply = """{"translate":{"enabled":true},"downloads":3439}""";
        await pool.RefreshConfigAsync();
        await pool.RefreshConfigAsync();
        Assert.Equal(1, server.Asked);
    }

    [Fact]
    public void BrokenOrMissingFileMeansNoTotal()
    {
        Directory.CreateDirectory(directory);
        var file = Path.Combine(directory, DownloadCounter.FileName);
        Assert.Null(new DownloadCounter(file).Total);
        File.WriteAllText(file, "bozuk");
        Assert.Null(new DownloadCounter(file).Total);
        File.WriteAllText(file, "0");
        Assert.Null(new DownloadCounter(file).Total);
        // Dosyasız sayaç saklamaz ama sayıyı tutar.
        var unsaved = new DownloadCounter(null);
        Assert.True(unsaved.Record("""{"downloads":7}"""));
        Assert.False(unsaved.Record("""{"downloads":7}"""));
        Assert.False(unsaved.Record(null));
        Assert.Equal(7, unsaved.Total);
    }

    /// Binlik ayırıcı yerel biçimde; sayıya hiçbir şey eklenmez.
    [Fact]
    public void FormatsWithTheLocalGroupingSeparator()
    {
        Assert.Equal("3.439", DownloadCounter.Format(3439, CultureInfo.GetCultureInfo("tr-TR")));
        Assert.Equal("3,439", DownloadCounter.Format(3439, CultureInfo.GetCultureInfo("en-US")));
        Assert.Equal("999", DownloadCounter.Format(999, CultureInfo.GetCultureInfo("tr-TR")));
    }

    /// Bekleme ekranının ve göstergenin metinleri bütün arayüz dillerinde var (ortak katalog); başlık büyük harfle yazılır.
    [Fact]
    public void StandbyTextsAreTranslatedInEveryLanguage()
    {
        string[] languages = ["ar", "bn", "en", "fil", "hi", "id", "ms", "nl", "th", "tr", "ur", "vi"];
        foreach (var key in new[] { "Total downloads", "Drag the plug to the socket to start" })
            foreach (var language in languages)
                Assert.DoesNotContain(key, Localizer.MissingTranslations(language));
        var tr = Localizer.ForLanguage("tr");
        Assert.Equal("Toplam İndirme", tr["Total downloads"]);
        Assert.Equal("Çalıştırmak için fişi prize sürükleyiniz", tr["Drag the plug to the socket to start"]);
        // Türkçe büyük harf: i → İ (dilden bağımsız çeviri "INDIRME" yazardı).
        Assert.Equal("TOPLAM İNDİRME", tr.Upper(tr["Total downloads"]));
        Assert.Equal("ÇALIŞTIRMAK İÇİN FİŞİ PRİZE SÜRÜKLEYİNİZ", tr.Upper(tr["Drag the plug to the socket to start"]));
        Assert.Equal("TOTAL DOWNLOADS", Localizer.ForLanguage("en").Upper("Total downloads"));
        var ar = Localizer.ForLanguage("ar");
        Assert.Equal("إجمالي التنزيلات", ar.Upper(ar["Total downloads"]));
    }
}
