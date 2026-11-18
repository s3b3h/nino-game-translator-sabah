// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Text;
using System.Text.Json;
using CouchSubs.Core;
using CouchSubs.Core.Dubbing;

namespace CouchSubs.Core.Tests;

/// <summary>Nino çeviri havuzu istemcisi (Mac: TranslationPoolTests).</summary>
public sealed class TranslationPoolTests : IDisposable
{
    private sealed class FakeServer : HttpMessageHandler
    {
        public sealed record Seen(HttpMethod Method, string Path, string Query, string? Body, string UserAgent);

        public readonly List<Seen> Requests = [];
        public string Config = """{"translate":{"enabled":true,"deadlineMs":900,"syncSeconds":180,"contextLines":4,"maxLines":12}}""";
        public Func<Seen, (int Code, string Body)> Translate = _ => (200, """{"ok":true,"translations":[{"text":"Kapıyı tut.","tier":"instant"}]}""");
        public Func<Seen, (int Code, string Body)> Translations = _ => (200, """{"ok":true,"now":1,"items":[],"next":null}""");
        public Func<Seen, (int Code, string Body)> Identify = _ => (200, """{"ok":true,"game":"Grand Theft Auto VI","id":"grand-theft-auto-vi","confidence":0.92}""");
        public TaskCompletionSource? Hold;

        public IEnumerable<Seen> At(string path) { lock (Requests) return Requests.Where(r => r.Path == path).ToList(); }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
            var seen = new Seen(request.Method, request.RequestUri!.AbsolutePath, Uri.UnescapeDataString(request.RequestUri.Query.TrimStart('?')),
                body, request.Headers.UserAgent.ToString());
            lock (Requests) Requests.Add(seen);
            var (code, text) = seen.Path switch
            {
                "/v1/config" => (200, Config),
                "/v1/translate" => Translate(seen),
                "/v1/translations" => Translations(seen),
                "/v1/ping" => (204, ""),
                "/v1/identify" => Identify(seen),
                _ => (404, ""),
            };
            if (seen.Path == "/v1/translate" && Hold is { } hold) await hold.Task;
            return new HttpResponseMessage((HttpStatusCode)code) { Content = new StringContent(text, Encoding.UTF8, "application/json") };
        }
    }

    private readonly string directory = Path.Combine(Path.GetTempPath(), "ninotranslations-" + Guid.NewGuid());
    private readonly FakeServer server = new();
    private DateTimeOffset now = DateTimeOffset.FromUnixTimeSeconds(1_763_300_000);
    private readonly List<TranslationPool> pools = [];
    private static readonly Uri Endpoint = new("http://localhost:8787/");

    public void Dispose()
    {
        foreach (var pool in pools) pool.Dispose();
        try { Directory.Delete(directory, true); } catch (IOException) { }
    }

    private TranslationPool Make(string language = "tr", bool enabled = true) =>
        Make(language, enabled, server);

    private TranslationPool Make(string language, bool enabled, FakeServer handler)
    {
        var pool = new TranslationPool(directory, Endpoint, "0.2.1", "windows", language, enabled, handler: handler, clock: () => now);
        pools.Add(pool);
        return pool;
    }

    [Fact]
    public async Task TranslatesOnceAndRemembers()
    {
        var pool = Make();
        var context = new[] { "a", "Who goes there?", "Open up!", "Now!", "Who's asking?" };
        Assert.Equal("Kapıyı tut.", await pool.TranslateAsync("Hold the gate.", context, "Red Dead Redemption 2"));
        Assert.Equal("Kapıyı tut.", await pool.TranslateAsync("Hold the gate.", context, "Red Dead Redemption 2"));
        Assert.Equal("Kapıyı tut.", pool.Store.Match("hold the GATE"));
        var post = Assert.Single(server.At("/v1/translate"));
        Assert.Equal(HttpMethod.Post, post.Method);
        Assert.StartsWith("nino-pool/1 (windows; 0.2.1)", post.UserAgent);
        using var json = JsonDocument.Parse(post.Body!);
        var root = json.RootElement;
        Assert.Equal(1, root.GetProperty("v").GetInt32());
        Assert.Equal("windows", root.GetProperty("platform").GetString());
        Assert.Equal("tr", root.GetProperty("lang").GetString());
        Assert.Equal("red-dead-redemption-2", root.GetProperty("game").GetString());
        Assert.Equal(pool.InstallIdentifier, root.GetProperty("install").GetString());
        Assert.Equal(["Hold the gate."], root.GetProperty("lines").EnumerateArray().Select(e => e.GetString()!));
        // Bağlam: sunucunun istediği kadar (contextLines 4) son satır.
        Assert.Equal(["Who goes there?", "Open up!", "Now!", "Who's asking?"], root.GetProperty("context").EnumerateArray().Select(e => e.GetString()!));
        // Kurulum kimliği klasörde kalır.
        Assert.Equal(pool.InstallIdentifier, Make().InstallIdentifier);
    }

    [Fact]
    public async Task SameLineIsAskedOnceWhileInFlight()
    {
        server.Hold = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var pool = Make();
        await pool.RefreshConfigAsync(force: true);
        var first = pool.TranslateAsync("Hold the gate.");
        var second = pool.TranslateAsync("Hold the gate.");
        while (!server.At("/v1/translate").Any()) await Task.Delay(5);
        server.Hold.SetResult();
        Assert.Equal(new string?[] { "Kapıyı tut.", "Kapıyı tut." }, await Task.WhenAll(first, second));
        Assert.Single(server.At("/v1/translate"));
    }

    [Fact]
    public async Task FailedOrLimitedAnswerReturnsNull()
    {
        server.Translate = _ => (200, """{"ok":true,"limited":true,"translations":[{"text":null,"tier":"limited"}]}""");
        var pool = Make();
        Assert.Null(await pool.TranslateAsync("Hold the gate."));
        server.Translate = _ => (500, "");
        Assert.Null(await pool.TranslateAsync("Hold the gate."));
        Assert.Equal(0, pool.Store.Count);
    }

    [Fact]
    public async Task NoiseIsNotSent()
    {
        var pool = Make();
        Assert.Null(await pool.TranslateAsync("%%% ### !!!"));
        Assert.Null(await pool.TranslateAsync("1234"));
        Assert.Null(await pool.TranslateAsync(""));
        Assert.Empty(server.At("/v1/translate"));
    }

    [Fact]
    public async Task DisabledSendsNothing()
    {
        // Önceden inmiş çeviriler de kullanılmaz.
        server.Translations = _ => (200, """{"ok":true,"items":[["0123456789abcdef","Merhaba",10,"instant"]],"next":null}""");
        var first = Make();
        await first.SyncAsync("game", force: true);
        first.Dispose();
        pools.Remove(first);
        server.Requests.Clear();

        var pool = Make(enabled: false);
        Assert.Equal(0, pool.Store.Count);
        Assert.Null(await pool.TranslateAsync("Hold the gate."));
        Assert.Equal(0, await pool.SyncAsync("game", force: true));
        await pool.PingAsync("game");
        Assert.DoesNotContain(server.Requests, r => r.Path is "/v1/translate" or "/v1/translations" or "/v1/ping");
        Assert.False(pool.IsActive);
        // Açılınca diskteki çeviriler geri gelir; kapanınca yine boşalır.
        pool.SetEnabled(true);
        Assert.Equal(1, pool.Store.Count);
        pool.SetEnabled(false);
        Assert.Equal(0, pool.Store.Count);
    }

    [Fact]
    public async Task ServerCanTurnItOff()
    {
        server.Config = """{"translate":{"enabled":false,"deadlineMs":900,"syncSeconds":180,"contextLines":4,"maxLines":12}}""";
        var pool = Make();
        Assert.Null(await pool.TranslateAsync("Hold the gate."));
        Assert.Equal(0, await pool.SyncAsync(null, force: true));
        Assert.False(pool.IsActive);
        Assert.Empty(server.At("/v1/translate"));
        Assert.Empty(server.At("/v1/translations"));
        // Ayar en çok 10 dakikada bir sorulur.
        Assert.Single(server.At("/v1/config"));
    }

    [Fact]
    public async Task SyncPagesPersistsAndKeepsCursor()
    {
        server.Translations = seen => seen.Query.Contains("after=k2")
            ? (200, """{"ok":true,"now":30,"items":[["00000000000000a3","Üç",30,"review"],["bad"],[1,2,3]],"next":null}""")
            : (200, """{"ok":true,"now":30,"items":[["00000000000000a1","Bir",10,"instant"],["00000000000000a2","İki",20,"instant"]],"next":{"since":20,"after":"k2"}}""");
        var pool = Make();
        Assert.Equal(3, await pool.SyncAsync("Ghost of Yōtei", force: true));
        var pages = server.At("/v1/translations").ToList();
        Assert.Equal(2, pages.Count);
        Assert.Contains("lang=tr", pages[0].Query);
        Assert.Contains("since=0", pages[0].Query);
        Assert.Contains("game=ghost-of-y-tei", pages[0].Query);
        Assert.DoesNotContain("after=", pages[0].Query);
        Assert.Contains("since=20", pages[1].Query);
        Assert.Contains("after=k2", pages[1].Query);
        Assert.StartsWith("nino-pool/1 (windows; 0.2.1)", pages[0].UserAgent);
        Assert.True(File.Exists(Path.Combine(directory, "translations-tr.json")));

        // Süre dolmadan yeniden sorulmaz; dolunca kalınan yerden.
        server.Translations = _ => (200, """{"ok":true,"items":[],"next":null}""");
        Assert.Equal(0, await pool.SyncAsync("Ghost of Yōtei"));
        Assert.Equal(2, server.At("/v1/translations").Count());
        now += TimeSpan.FromSeconds(181);
        await pool.SyncAsync("Ghost of Yōtei");
        var third = server.At("/v1/translations").Last();
        Assert.Contains("since=30", third.Query);
        Assert.DoesNotContain("after=", third.Query);

        // Yeni açılışta diskten gelir; imleç de korunur.
        pool.Dispose();
        pools.Remove(pool);
        var reopened = Make();
        Assert.Equal(3, reopened.Store.Count);
        await reopened.SyncAsync("Ghost of Yōtei", force: true);
        Assert.Contains("since=30", server.At("/v1/translations").Last().Query);
    }

    [Fact]
    public async Task EachLanguageHasItsOwnTranslations()
    {
        server.Translations = seen => seen.Query.Contains("lang=ar")
            ? (200, """{"ok":true,"items":[["00000000000000b1","مرحبا",5,"instant"]],"next":null}""")
            : (200, """{"ok":true,"items":[["00000000000000a1","Bir",5,"instant"],["00000000000000a2","İki",6,"instant"]],"next":null}""");
        var pool = Make();
        await pool.SyncAsync(null, force: true);
        Assert.Equal(2, pool.Store.Count);
        Assert.DoesNotContain("game=", server.At("/v1/translations").Last().Query);
        pool.SetLanguage("ar-SA");
        Assert.Equal(0, pool.Store.Count);
        await pool.SyncAsync(null, force: true);
        Assert.Contains("lang=ar", server.At("/v1/translations").Last().Query);
        Assert.Equal(1, pool.Store.Count);
        Assert.Equal("Kapıyı tut.", await pool.TranslateAsync("Hold the gate."));
        Assert.Contains("\"lang\":\"ar\"", server.At("/v1/translate").Last().Body);
        pool.SetLanguage("tr");
        Assert.Equal(2, pool.Store.Count);
        Assert.Null(pool.Store.Match("Hold the gate."));
        pool.SetLanguage("ar");
        Assert.Equal(2, pool.Store.Count);
        Assert.Equal("Kapıyı tut.", pool.Store.Match("Hold the gate."));
    }

    [Fact]
    public async Task PingsAtMostOncePerMinute()
    {
        var pool = Make();
        await pool.PingAsync("Red Dead Redemption 2");
        await pool.PingAsync("Red Dead Redemption 2");
        var ping = Assert.Single(server.At("/v1/ping"));
        Assert.Equal(HttpMethod.Get, ping.Method);
        Assert.Contains($"install={pool.InstallIdentifier}", ping.Query);
        Assert.Contains("platform=windows", ping.Query);
        Assert.Contains("app=0.2.1", ping.Query);
        Assert.Contains("game=red-dead-redemption-2", ping.Query);
        Assert.Contains("lang=tr", ping.Query);
        now += TimeSpan.FromSeconds(60);
        await pool.PingAsync(null);
        Assert.Contains("game=&", server.At("/v1/ping").Last().Query);
        Assert.Equal(2, server.At("/v1/ping").Count());
    }

    [Fact]
    public void ContextKeepsRecentLines()
    {
        var at = DateTimeOffset.FromUnixTimeSeconds(1000);
        var context = new PoolContext(() => at);
        Assert.Empty(context.Add("One."));
        Assert.Equal(["One."], context.Add("Two."));
        at += TimeSpan.FromSeconds(31);
        Assert.Empty(context.Add("Three."));
        Assert.Equal(["Three."], context.Add("Four."));
    }
    /// Nino: oyunu ekrandan tanıma isteği (Mac: identify(jpeg:)).
    [Fact]
    public async Task IdentifiesGameFromScreenshot()
    {
        var pool = Make();
        var jpeg = new byte[] { 0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9 };
        Assert.Equal("Grand Theft Auto VI", await pool.IdentifyAsync(jpeg));
        var post = Assert.Single(server.At("/v1/identify"));
        Assert.Equal(HttpMethod.Post, post.Method);
        Assert.StartsWith("nino-pool/1 (windows; 0.2.1)", post.UserAgent);
        using var json = JsonDocument.Parse(post.Body!);
        var root = json.RootElement;
        Assert.Equal(1, root.GetProperty("v").GetInt32());
        Assert.Equal(pool.InstallIdentifier, root.GetProperty("install").GetString());
        Assert.Equal("windows", root.GetProperty("platform").GetString());
        Assert.Equal("0.2.1", root.GetProperty("app").GetString());
        Assert.Equal(jpeg, Convert.FromBase64String(root.GetProperty("image").GetString()!));
        Assert.Equal(["app", "image", "install", "platform", "v"], root.EnumerateObject().Select(p => p.Name).Order().ToArray());

        server.Identify = _ => (200, """{"ok":true,"game":null,"id":null,"confidence":0}""");
        Assert.Null(await pool.IdentifyAsync(jpeg));
        server.Identify = _ => (500, "");
        Assert.Null(await pool.IdentifyAsync(jpeg));
        // Çok büyük kare gönderilmez.
        Assert.Null(await pool.IdentifyAsync(new byte[TranslationPool.MaxIdentifyBytes + 1]));
        Assert.Equal(3, server.At("/v1/identify").Count());
    }

    [Fact]
    public async Task IdentifyIsSilentWhenSharingIsOff()
    {
        var pool = Make(enabled: false);
        Assert.Null(await pool.IdentifyAsync([1, 2, 3]));
        Assert.Empty(server.At("/v1/identify"));
    }

}

/// <summary>Havuzdan sonradan gelen çeviri yalnız ekrandaki satırın yerine konur (Mac: SubtitlePipeline.upgrade).</summary>
public class PoolUpgradeTests
{
    private static readonly Frame Image = Frame.Blank(64, 64);

    private static async Task RunTimed(SubtitlePipeline pipeline, int frames, Action advance, bool wait = true)
    {
        for (var i = 0; i < frames; i++)
        {
            await pipeline.ProcessAsync(Image, new CropRegion());
            if (wait) await pipeline.WaitForTranslationsAsync();
            advance();
        }
    }

    private static PackMatch? Pack(string text) => PackKey.Canon(text) == "get down"
        ? new PackMatch("Yere yat!", [new SpokenLine("Get down!", "Yere yat!")])
        : null;

    [Fact]
    public async Task UpgradeReplacesTheLineOnScreen()
    {
        var sender = new FakeSender();
        long clock = 0;
        var pipeline = new SubtitlePipeline(new FakeReader(Enumerable.Repeat("Hold the gate", 8).ToArray()), new FakeTranslator(), sender, clock: () => clock)
            { PackLookup = Pack };
        var shown = new List<(string, string)>();
        pipeline.PairShown += (source, translation) => shown.Add((source, translation));
        await RunTimed(pipeline, 4, () => clock += 150);
        Assert.Equal(["TR: Hold the gate"], sender.Sent);
        pipeline.Upgrade("Hold the gate", "Kapıyı tut");
        Assert.Equal(["TR: Hold the gate", "Kapıyı tut"], sender.Sent);
        Assert.True(sender.Replaces[^1]);
        Assert.Equal("havuz", pipeline.LastOrigin);
        Assert.Equal(("Hold the gate", "Kapıyı tut"), pipeline.LastPair);
        Assert.Equal(("Hold the gate", "Kapıyı tut"), shown[^1]);
        // Aynısı yeniden gelirse gönderilmez.
        pipeline.Upgrade("Hold the gate", "Kapıyı tut");
        Assert.Equal(2, sender.Sent.Count);
    }

    [Fact]
    public async Task UpgradeAfterTheLineLeftIsOnlyRemembered()
    {
        var sender = new FakeSender();
        long clock = 0;
        var frames = Enumerable.Repeat("Hold the gate", 4).Concat(Enumerable.Repeat("", 20)).ToArray();
        var pipeline = new SubtitlePipeline(new FakeReader(frames), new FakeTranslator(), sender, clock: () => clock) { PackLookup = Pack };
        await RunTimed(pipeline, 24, () => clock += 150);
        Assert.Equal(["TR: Hold the gate"], sender.Sent);
        pipeline.Upgrade("Hold the gate", "Kapıyı tut");
        Assert.Equal(["TR: Hold the gate"], sender.Sent);
        Assert.Equal("motor", pipeline.LastOrigin);
    }

    [Fact]
    public async Task UpgradeLeavesAnotherLineAlone()
    {
        var sender = new FakeSender();
        long clock = 0;
        var frames = Enumerable.Repeat("Hold the gate", 4).Concat(Enumerable.Repeat("Ride to the river", 4)).ToArray();
        var pipeline = new SubtitlePipeline(new FakeReader(frames), new FakeTranslator(), sender, clock: () => clock) { PackLookup = Pack };
        await RunTimed(pipeline, 8, () => clock += 150);
        Assert.Equal("TR: Ride to the river", sender.Sent[^1]);
        var count = sender.Sent.Count;
        pipeline.Upgrade("Hold the gate", "Kapıyı tut");
        Assert.Equal(count, sender.Sent.Count);
    }

    [Fact]
    public async Task PackLineIsNotUpgraded()
    {
        var sender = new FakeSender();
        var pipeline = new SubtitlePipeline(new FakeReader("Get down!", "Get down!", "Get down!"), new FakeTranslator(), sender) { PackLookup = Pack };
        await RunTimed(pipeline, 3, () => { });
        Assert.Equal(["Yere yat!"], sender.Sent);
        pipeline.Upgrade("Get down!", "Eğil!");
        Assert.Equal(["Yere yat!"], sender.Sent);
        Assert.Equal("paket", pipeline.LastOrigin);
    }

    /// <summary>Çeviri sürerken havuza gelen çeviri, motorun sonucu yerine gösterilir.</summary>
    [Fact]
    public async Task PoolAnswerBeforeTheEngineWins()
    {
        var sender = new FakeSender();
        var translator = new GatedTranslator();
        var store = new Dictionary<string, string>();
        long clock = 0;
        var pipeline = new SubtitlePipeline(new FakeReader(Enumerable.Repeat("Hold the gate", 4).ToArray()), translator, sender, clock: () => clock)
        {
            PackLookup = text => Pack(text) ?? (store.TryGetValue(text, out var found) ? new PackMatch(found, [new SpokenLine(text, found)]) : null),
        };
        var spoken = new List<IReadOnlyList<SpokenLine>>();
        pipeline.SpeechReady += spoken.Add;
        await RunTimed(pipeline, 4, () => clock += 150, wait: false);
        while (translator.Requested.Count == 0) await Task.Delay(5);
        store["Hold the gate"] = "Kapıyı tut";
        translator.Open();
        await pipeline.WaitForTranslationsAsync();
        Assert.Equal(["Kapıyı tut"], sender.Sent);
        Assert.Equal("Kapıyı tut", Assert.Single(spoken).Single().Turkish);
    }
}
