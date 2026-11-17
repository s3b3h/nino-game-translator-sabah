// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Text;
using System.Text.Json;
using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

public class ProblemReportTests
{
    private static ProblemReport.Payload Sample(string? contact = "@nino", string? log = "satır 1\nsatır 2", int images = 1) =>
        ProblemReport.Build("install-12345", "0.1.0-beta.40", "tr", "  Altyazı gelmedi.  ", contact, log,
            Enumerable.Range(0, images).Select(i => new byte[] { 0xFF, 0xD8, (byte)i, 0xFF, 0xD9 }));

    [Fact]
    public void JsonHasTheServerShape()
    {
        using var json = JsonDocument.Parse(ProblemReport.ToJson(Sample()));
        var root = json.RootElement;
        Assert.Equal(1, root.GetProperty("v").GetInt32());
        Assert.Equal("install-12345", root.GetProperty("install").GetString());
        Assert.Equal("0.1.0-beta.40", root.GetProperty("app").GetString());
        Assert.Equal("windows", root.GetProperty("platform").GetString());
        Assert.Equal("tr", root.GetProperty("language").GetString());
        Assert.Equal("Altyazı gelmedi.", root.GetProperty("text").GetString());
        Assert.Equal("@nino", root.GetProperty("contact").GetString());
        Assert.Equal("satır 1\nsatır 2", root.GetProperty("log").GetString());
        var image = Assert.Single(root.GetProperty("images").EnumerateArray());
        Assert.Equal("image/jpeg", image.GetProperty("mime").GetString());
        Assert.Equal(new byte[] { 0xFF, 0xD8, 0, 0xFF, 0xD9 }, Convert.FromBase64String(image.GetProperty("data").GetString()!));
    }

    [Fact]
    public void EmptyContactAndLogAreLeftOutButImagesStayAnArray()
    {
        var text = ProblemReport.ToJson(Sample(contact: "  ", log: null, images: 0));
        using var json = JsonDocument.Parse(text);
        Assert.False(json.RootElement.TryGetProperty("contact", out _));
        Assert.False(json.RootElement.TryGetProperty("log", out _));
        Assert.Equal(JsonValueKind.Array, json.RootElement.GetProperty("images").ValueKind);
        Assert.Equal(0, json.RootElement.GetProperty("images").GetArrayLength());
    }

    [Fact]
    public void JsonDoesNotEscapeBase64OrTurkish()
    {
        var payload = ProblemReport.Build("install-12345", "1", "tr", "Çalışmıyor", null, null, [[0xFB, 0xEF, 0xBE]]);
        var text = ProblemReport.ToJson(payload);
        Assert.Contains("Çalışmıyor", text);
        Assert.Contains("++++", text);
        Assert.DoesNotContain("\\u", text);
    }

    [Fact]
    public void FieldsAreClippedAndAtMostThreeImages()
    {
        var payload = ProblemReport.Build("install-12345", new string('9', 80), "tr", new string('a', 5000), new string('b', 300),
            new string('c', 70000), Enumerable.Range(0, 5).Select(_ => new byte[] { 1 }));
        Assert.Equal(ProblemReport.MaxText, payload.Text.Length);
        Assert.Equal(ProblemReport.MaxContact, payload.Contact!.Length);
        Assert.Equal(ProblemReport.MaxLog, payload.Log!.Length);
        Assert.Equal(40, payload.App.Length);
        Assert.Equal(ProblemReport.MaxImages, payload.Images.Count);
    }

    [Fact]
    public void LargestReportFitsTheBodyLimit()
    {
        // Üç fotoğraf hedef sınırda, tam günlük (Arapça: karakter başına 2 bayt) ve tam açıklama.
        var images = Enumerable.Range(0, 3).Select(_ => new byte[ProblemReport.TargetImageBytes]);
        var payload = ProblemReport.Build("install-12345", "0.1.0", "ar", new string('ş', 5000), new string('x', 200),
            new string('ع', 60000), images);
        var bytes = Encoding.UTF8.GetByteCount(ProblemReport.ToJson(payload));
        Assert.True(bytes <= ProblemReport.MaxBodyBytes, $"{bytes} bayt");
        Assert.True(ProblemReport.TargetImageBytes <= ProblemReport.ServerMaxImageBytes);
    }

    [Theory]
    [InlineData("", false)]
    [InlineData("   \n ", false)]
    [InlineData("a", true)]
    public void SendNeedsText(string text, bool expected) => Assert.Equal(expected, ProblemReport.CanSend(text));

    [Fact]
    public void EndpointIsUnderThePool()
    {
        Assert.Equal("https://nino-pool.y-demirbag2506.workers.dev/v1/reports", ProblemReport.Endpoint(NinoPool.LiveEndpoint)!.AbsoluteUri);
        Assert.Null(ProblemReport.Endpoint(null));
    }

    // --- Günlük gizleme ---

    [Theory]
    [InlineData("Authorization: Bearer abcdefgh12345678", "abcdefgh12345678")]
    [InlineData("istek key=d41d8cd98f00 bitti", "d41d8cd98f00")]
    [InlineData("{\"api_key\":\"s3cr3tvalue\"}", "s3cr3tvalue")]
    [InlineData("token: abc.def.ghi", "abc.def.ghi")]
    [InlineData("oauth id_token=abc123 tamam", "abc123")]
    [InlineData("auth_token: xyz789", "xyz789")]
    [InlineData("deepl_key=abc", "=abc")]
    [InlineData("gemini AIzaSyA1234567890abcdefghijklmnopq hata", "AIzaSyA1234567890abcdefghijklmnopq")]
    [InlineData("openai sk-proj-ABCDEF1234567890xyz", "sk-proj-ABCDEF1234567890xyz")]
    [InlineData("anthropic sk-ant-api03-ABCDEFGHIJ0123456789", "sk-ant-api03-ABCDEFGHIJ0123456789")]
    [InlineData("deepl 0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b:fx tamam", "0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b")]
    [InlineData("rp kayıt 00112233445566778899aabbccddeeff00", "00112233445566778899aabbccddeeff00")]
    [InlineData("çerez eyJhbGciOiJIUzI1NiJ9eyJzdWIiOiIxMjM0NTY3ODkwIn0abc tamam", "eyJhbGciOiJIUzI1NiJ9eyJzdWIiOiIxMjM0NTY3ODkwIn0abc")]
    public void SecretsAreHidden(string line, string secret)
    {
        var scrubbed = ProblemReport.Scrub(line);
        Assert.DoesNotContain(secret, scrubbed);
        Assert.Contains("[gizlendi]", scrubbed);
    }

    [Fact]
    public void BearerKeepsTheScheme() =>
        Assert.Equal("Authorization: Bearer [gizlendi]", ProblemReport.Scrub("Authorization: Bearer abcdefgh12345678"));

    [Theory]
    [InlineData("12:04:31 okundu \"Where is the key?\" → \"Anahtar nerede?\"")]
    [InlineData(@"C:\Users\nino\AppData\Local\CouchSubs\models\opus-mt-en-tr\model.bin yüklendi")]
    [InlineData("System.Net.Http.HttpRequestException: CouchSubs.RemotePlay.SessionController.ConnectAsync")]
    [InlineData("2026-11-18T12:04:31.123Z PS5 192.168.0.12 bağlandı, 1920x1080 60 fps")]
    [InlineData("hotkey=F8 basıldı")]
    public void OrdinaryLinesStayTheSame(string line) => Assert.Equal(line, ProblemReport.Scrub(line));

    [Fact]
    public void CutKeepsWholeLines()
    {
        var text = string.Join("\n", Enumerable.Range(0, 100).Select(i => $"satır {i:000}"));
        var cut = ProblemReport.CutToLastChars(text, 25);
        Assert.True(cut.Length <= 25);
        Assert.StartsWith("satır", cut);
        Assert.EndsWith("satır 099", cut);
    }

    [Fact]
    public void CollectLogsJoinsTailsScrubsAndLimits()
    {
        var folder = Directory.CreateTempSubdirectory("nino-report-").FullName;
        try
        {
            var first = Path.Combine(folder, "hata.log");
            var second = Path.Combine(folder, "altyazi.log");
            File.WriteAllText(first, "eski\nkey=gizlideger123\n");
            File.WriteAllText(second, string.Join("\n", Enumerable.Range(0, 5000).Select(i => $"okundu {i}")));
            var log = ProblemReport.CollectLogs([(first, 1000), (second, 2000), (Path.Combine(folder, "yok.log"), 1000)], max: 2500)!;
            Assert.True(log.Length <= 2500);
            Assert.DoesNotContain("gizlideger123", log);
            Assert.Contains("— hata.log —", log);
            Assert.Contains("— altyazi.log —", log);
            Assert.DoesNotContain("yok.log", log);
            Assert.EndsWith("okundu 4999", log);
            Assert.DoesNotContain("okundu 100\n", log);
        }
        finally { Directory.Delete(folder, recursive: true); }
    }

    [Fact]
    public void NoLogFilesMeansNoLog() =>
        Assert.Null(ProblemReport.CollectLogs([(Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".log"), 1000)]));

    // --- Kuruluş kimliği ---

    [Fact]
    public void InstallIdPrefersThePoolAndOtherwiseKeepsOneId()
    {
        var file = Path.Combine(Path.GetTempPath(), "nino-report-" + Guid.NewGuid(), "report-install.txt");
        try
        {
            Assert.Equal("pool-install-id", ProblemReport.InstallId("pool-install-id", file));
            var made = ProblemReport.InstallId(null, file);
            Assert.InRange(made.Length, 8, 64);
            Assert.Equal(made, ProblemReport.InstallId(null, file));
            Assert.Equal(made, ProblemReport.InstallId("short", file));
        }
        finally { if (Directory.Exists(Path.GetDirectoryName(file))) Directory.Delete(Path.GetDirectoryName(file)!, true); }
    }

    // --- Fotoğraf ---

    [Theory]
    [InlineData(3840, 2160, 1600, 900)]
    [InlineData(1080, 2400, 720, 1600)]
    [InlineData(800, 600, 800, 600)]
    [InlineData(1600, 1600, 1600, 1600)]
    public void FitSizeKeepsTheLongestSideUnder1600(int w, int h, int ew, int eh) =>
        Assert.Equal((ew, eh), ProblemReport.FitSize(w, h));

    [Fact]
    public void FitJpegLowersQualityThenSizeUntilItFits()
    {
        var tried = new List<(int, int)>();
        // Sahte kodlayıcı: bayt sayısı kenar × kalite ile büyür.
        byte[] Encode(int side, int quality) { tried.Add((side, quality)); return new byte[side * quality * 10]; }
        var bytes = ProblemReport.FitJpeg(Encode, maxBytes: 1024 * 55 * 10);
        Assert.NotNull(bytes);
        Assert.True(bytes!.Length <= 1024 * 55 * 10);
        Assert.Equal((1600, 70), tried[0]);
        Assert.Equal((1600, 55), tried[1]);
        Assert.Equal((1280, 40), tried[^1]);
    }

    [Fact]
    public void FitJpegGivesUpWhenNothingFits() =>
        Assert.Null(ProblemReport.FitJpeg((_, _) => new byte[10], maxBytes: 5));

    // --- Gönderim (ağa çıkmaz; sahte işleyici) ---

    private sealed class FakeHandler(Func<HttpRequestMessage, HttpResponseMessage> reply) : HttpMessageHandler
    {
        public HttpRequestMessage? Request { get; private set; }
        public string? Body { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Request = request;
            Body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
            return reply(request);
        }
    }

    private static readonly Uri Url = new("https://pool.test/v1/reports");

    [Fact]
    public async Task SendPostsJsonAndReadsTheId()
    {
        var handler = new FakeHandler(_ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"ok\":true,\"id\":\"r-1\"}") });
        var result = await ProblemReport.SendAsync(new HttpClient(handler), Url, Sample());
        Assert.Equal(ProblemReport.Outcome.Sent, result.Outcome);
        Assert.Equal("r-1", result.Id);
        Assert.Equal(HttpMethod.Post, handler.Request!.Method);
        Assert.Equal(Url, handler.Request.RequestUri);
        Assert.Equal("application/json", handler.Request.Content!.Headers.ContentType!.MediaType);
        using var json = JsonDocument.Parse(handler.Body!);
        Assert.Equal("Altyazı gelmedi.", json.RootElement.GetProperty("text").GetString());
    }

    [Theory]
    [InlineData(HttpStatusCode.TooManyRequests, ProblemReport.Outcome.RateLimited)]
    [InlineData(HttpStatusCode.RequestEntityTooLarge, ProblemReport.Outcome.TooLarge)]
    [InlineData(HttpStatusCode.BadRequest, ProblemReport.Outcome.Rejected)]
    [InlineData(HttpStatusCode.InternalServerError, ProblemReport.Outcome.Failed)]
    public async Task ServerErrorsMapToOutcomes(HttpStatusCode status, ProblemReport.Outcome expected)
    {
        var handler = new FakeHandler(_ =>
        {
            var response = new HttpResponseMessage(status) { Content = new StringContent("{\"ok\":false}") };
            if (status == HttpStatusCode.TooManyRequests) response.Headers.RetryAfter = new(TimeSpan.FromHours(1));
            return response;
        });
        var result = await ProblemReport.SendAsync(new HttpClient(handler), Url, Sample());
        Assert.Equal(expected, result.Outcome);
        if (expected == ProblemReport.Outcome.RateLimited) Assert.Equal(TimeSpan.FromHours(1), result.RetryAfter);
    }

    [Fact]
    public async Task NetworkErrorIsAFailureNotAnException()
    {
        var handler = new FakeHandler(_ => throw new HttpRequestException("ağ yok"));
        var result = await ProblemReport.SendAsync(new HttpClient(handler), Url, Sample());
        Assert.Equal(ProblemReport.Outcome.Failed, result.Outcome);
    }
}
