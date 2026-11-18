// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Text;
using System.Text.Json;
using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

public sealed class NinoPoolTests : IDisposable
{
    private sealed class FakeServer : HttpMessageHandler
    {
        public enum Answer { Ok, Offline, LostAck, WrongBody, Status }
        public readonly Queue<(Answer Kind, int Code, string? RetryAfter)> Answers = new();
        public (Answer Kind, int Code, string? RetryAfter) Fallback = (Answer.Ok, 200, null);
        public readonly List<NinoPool.Batch> Received = [];
        public readonly List<string> Paths = [];

        public IEnumerable<NinoPool.WireLine> Lines => Received.SelectMany(b => b.Lines);

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var batch = JsonSerializer.Deserialize<NinoPool.Batch>(await request.Content!.ReadAsStringAsync(token))!;
            Paths.Add(request.RequestUri!.AbsolutePath);
            var answer = Answers.Count > 0 ? Answers.Dequeue() : Fallback;
            switch (answer.Kind)
            {
                case Answer.Ok:
                    Received.Add(batch);
                    return Reply(200, $$"""{"ok":true,"batch":"{{batch.Id}}","accepted":{{batch.Lines.Count}},"rejected":[]}""");
                case Answer.Offline:
                    throw new HttpRequestException("çevrimdışı");
                case Answer.LostAck:
                    Received.Add(batch);
                    throw new HttpRequestException("yanıt kayboldu");
                case Answer.WrongBody:
                    return Reply(200, "<html>captive portal</html>");
                default:
                    var response = Reply(answer.Code, """{"ok":false}""");
                    if (answer.RetryAfter is { } retry) response.Headers.TryAddWithoutValidation("Retry-After", retry);
                    return response;
            }
        }

        private static HttpResponseMessage Reply(int code, string body) =>
            new((HttpStatusCode)code) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
    }

    private readonly string directory = Path.Combine(Path.GetTempPath(), "ninopool-" + Guid.NewGuid());
    private readonly FakeServer server = new();
    private DateTimeOffset now = DateTimeOffset.FromUnixTimeSeconds(1_763_300_000);
    private readonly List<NinoPool> pools = [];
    private static readonly Uri Endpoint = new("http://localhost:8787/");

    public void Dispose()
    {
        foreach (var pool in pools) pool.Dispose();
        try { Directory.Delete(directory, true); } catch (IOException) { }
    }

    private NinoPool Make(Uri? endpoint = null, bool noEndpoint = false, string app = "0.1.6", string? legacy = null, NinoPool.Limits? limits = null)
    {
        var pool = new NinoPool(directory, app, "windows", true, noEndpoint ? null : endpoint ?? Endpoint, useConfiguredEndpoint: false,
            legacyFile: legacy, limits: limits, handler: server, clock: () => now);
        pools.Add(pool);
        return pool;
    }

    [Fact]
    public async Task LineIsOnDiskImmediatelyAndSurvivesCrash()
    {
        Assert.True(Make().Offer("Where is Lamar going?", "gta-v"));
        var reopened = Make();
        Assert.Equal(1, reopened.GetStatus().PendingLines);
        await reopened.FlushAsync(force: true);
        Assert.Equal(["Where is Lamar going?"], server.Lines.Select(l => l.Text));
        Assert.Equal("gta-v", server.Lines.First().Game);
    }

    [Fact]
    public async Task NoEndpointKeepsLinesQueued()
    {
        var pool = Make(noEndpoint: true);
        pool.Offer("This line waits for a server.");
        await pool.FlushAsync(force: true);
        Assert.Empty(server.Received);
        Assert.Equal(1, pool.GetStatus().PendingLines);
        Assert.False(pool.GetStatus().HasEndpoint);
        pool.SetEndpoint(Endpoint);
        await pool.FlushAsync(force: true);
        Assert.Single(server.Lines);
    }

    [Fact]
    public async Task TornLastLineIsSkippedOthersKept()
    {
        var pool = Make();
        pool.Offer("First full line here.");
        pool.Offer("Second full line here.");
        File.AppendAllText(Path.Combine(directory, "pending.jsonl"), """{"s":3,"t":"Half writ""");
        var reopened = Make();
        reopened.Offer("Third full line here.");
        await reopened.FlushAsync(force: true);
        Assert.Equal(new[] { "First full line here.", "Second full line here.", "Third full line here." }.ToHashSet(),
            server.Lines.Select(l => l.Text).ToHashSet());
    }

    [Fact]
    public async Task OutboxSurvivesRestartBeforeSending()
    {
        server.Fallback = (FakeServer.Answer.Offline, 0, null);
        var pool = Make();
        pool.Offer("Frozen but not sent.");
        await pool.FlushAsync(force: true);
        Assert.Equal(1, pool.GetStatus().OutboxBatches);
        Assert.Equal(0, pool.GetStatus().PendingLines);
        server.Fallback = (FakeServer.Answer.Ok, 200, null);
        var reopened = Make();
        await reopened.FlushAsync();
        Assert.Equal(["Frozen but not sent."], server.Lines.Select(l => l.Text));
        Assert.Equal(0, reopened.GetStatus().OutboxBatches);
    }

    [Fact]
    public async Task CrashMidFreezeKeepsUnwrittenChunks()
    {
        server.Fallback = (FakeServer.Answer.Offline, 0, null);
        var limits = new NinoPool.Limits { BatchSize = 3 };
        var pool = Make(limits: limits);
        for (var i = 0; i < 7; i++) pool.Offer($"Chunked line number {i}.");
        var pendingPath = Path.Combine(directory, "pending.jsonl");
        var pending = File.ReadAllBytes(pendingPath);
        await pool.FlushAsync(force: true);
        var outbox = NinoPool.BatchFiles(Path.Combine(directory, "outbox"));
        Assert.Equal(3, outbox.Count);
        foreach (var file in outbox.Skip(1)) File.Delete(file);
        File.WriteAllBytes(pendingPath, pending);
        var statePath = Path.Combine(directory, "state.json");
        var state = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(File.ReadAllText(statePath))!;
        var edited = state.ToDictionary(kv => kv.Key, kv => (object)kv.Value);
        edited["frozenThrough"] = 0;
        File.WriteAllText(statePath, JsonSerializer.Serialize(edited));
        server.Fallback = (FakeServer.Answer.Ok, 200, null);
        await Make(limits: limits).FlushAsync(force: true);
        Assert.Equal(7, server.Lines.Count());
        Assert.Equal(7, server.Lines.Select(l => l.Text).Distinct().Count());
        Assert.All(server.Lines, l => Assert.Equal(1, l.Count));
    }

    [Fact]
    public async Task InertPoolKeepsQueue()
    {
        server.Fallback = (FakeServer.Answer.Offline, 0, null);
        var pool = Make();
        pool.Offer("Waiting line stays put.");
        await pool.FlushAsync(force: true);
        pool.Offer("Pending line stays put.");
        var inert = new NinoPool(directory, "0.1.6", "windows", enabled: false, Endpoint, useConfiguredEndpoint: false, handler: server, clock: () => now);
        pools.Add(inert);
        Assert.False(inert.Offer("Not taken while inert."));
        Assert.Equal(1, inert.GetStatus().OutboxBatches);
        Assert.Equal(1, inert.GetStatus().PendingLines);
    }

    [Fact]
    public async Task RepeatsAreCountedAndBatched()
    {
        var pool = Make(limits: new NinoPool.Limits { BatchSize = 3 });
        for (var i = 0; i < 4; i++) pool.Offer("Same line again and again.", "GTA V");
        now = now.AddSeconds(10);
        pool.Offer("Same line again and again.", "GTA V");
        for (var i = 0; i < 4; i++) pool.Offer($"Different line number {i}.");
        await pool.FlushAsync(force: true);
        Assert.Equal([3, 2], server.Received.Select(b => b.Lines.Count));
        var repeated = server.Lines.Single(l => l.Text == "Same line again and again.");
        Assert.Equal(5, repeated.Count);
        Assert.Equal("gta-v", repeated.Game);
        Assert.Equal(10, repeated.Last - repeated.First);
        Assert.Single(server.Lines.Select(l => l.Session).Distinct());
        Assert.Equal("/v1/batches", server.Paths[0]);
    }

    [Fact]
    public async Task WaitsBeforeSendingSmallAmounts()
    {
        var pool = Make();
        pool.Offer("Not sent right away.");
        await pool.FlushAsync();
        Assert.Empty(server.Received);
        now += NinoPool.SendEvery;
        await pool.FlushAsync();
        Assert.Single(server.Lines);
    }

    [Fact]
    public async Task ServerErrorKeepsBatchWithGrowingBackoff()
    {
        server.Fallback = (FakeServer.Answer.Status, 500, null);
        var pool = Make();
        pool.Offer("Server is down right now.");
        await pool.FlushAsync(force: true);
        Assert.Single(server.Paths);
        now = now.AddSeconds(10);
        await pool.FlushAsync();
        Assert.Single(server.Paths);
        now = now.AddSeconds(40);
        await pool.FlushAsync();
        Assert.Equal(2, server.Paths.Count);
        now = now.AddSeconds(40);
        await pool.FlushAsync();
        Assert.Equal(2, server.Paths.Count);
        server.Fallback = (FakeServer.Answer.Ok, 200, null);
        now = now.AddSeconds(40);
        await pool.FlushAsync();
        Assert.Equal(["Server is down right now."], server.Lines.Select(l => l.Text));
        Assert.Equal(0, pool.GetStatus().OutboxBatches);
    }

    [Fact]
    public async Task LostAckResendsSameBatchId()
    {
        server.Answers.Enqueue((FakeServer.Answer.LostAck, 0, null));
        var pool = Make();
        pool.Offer("The reply never arrived.");
        await pool.FlushAsync(force: true);
        await pool.NetworkAvailableAsync();
        Assert.Equal(2, server.Received.Count);
        Assert.Equal(server.Received[0].Id, server.Received[1].Id);
    }

    [Fact]
    public async Task ForeignOkDoesNotDeleteBatch()
    {
        server.Answers.Enqueue((FakeServer.Answer.WrongBody, 0, null));
        var pool = Make();
        pool.Offer("Captive portal says OK.");
        await pool.FlushAsync(force: true);
        Assert.Equal(1, pool.GetStatus().OutboxBatches);
        await pool.NetworkAvailableAsync();
        Assert.Single(server.Lines);
    }

    [Fact]
    public async Task RetryAfterIsRespected()
    {
        server.Answers.Enqueue((FakeServer.Answer.Status, 429, "600"));
        var pool = Make();
        pool.Offer("Slow down, please.");
        await pool.FlushAsync(force: true);
        await pool.NetworkAvailableAsync();
        now = now.AddSeconds(599);
        await pool.FlushAsync();
        Assert.Empty(server.Received);
        now = now.AddSeconds(2);
        await pool.FlushAsync();
        Assert.Single(server.Lines);
    }

    [Fact]
    public async Task RejectedBatchIsParkedAndRetriedAfterUpdate()
    {
        server.Answers.Enqueue((FakeServer.Answer.Status, 400, null));
        var pool = Make();
        pool.Offer("Server did not like this.");
        pool.Offer("Nor this one.");
        await pool.FlushAsync(force: true);
        Assert.Equal(0, pool.GetStatus().OutboxBatches);
        Assert.Equal(1, pool.GetStatus().ParkedBatches);
        await Make().FlushAsync(force: true);
        Assert.Empty(server.Received);
        await Make(app: "0.1.7").FlushAsync();
        Assert.Equal(2, server.Lines.Count());
    }

    [Fact]
    public async Task TooLargeBatchIsSplit()
    {
        server.Answers.Enqueue((FakeServer.Answer.Status, 413, null));
        var pool = Make();
        for (var i = 0; i < 5; i++) pool.Offer($"Split line number {i}.");
        await pool.FlushAsync(force: true);
        Assert.Equal([2, 3], server.Received.Select(b => b.Lines.Count));
        Assert.Equal(5, server.Lines.Select(l => l.Text).Distinct().Count());
    }

    [Fact]
    public async Task NotFoundIsRetriedNotDropped()
    {
        server.Answers.Enqueue((FakeServer.Answer.Status, 404, null));
        var pool = Make();
        pool.Offer("Wrong address for a while.");
        await pool.FlushAsync(force: true);
        Assert.Equal(1, pool.GetStatus().OutboxBatches);
        Assert.Equal(0, pool.GetStatus().ParkedBatches);
    }

    [Fact]
    public async Task DisablingWipesEverything()
    {
        server.Fallback = (FakeServer.Answer.Offline, 0, null);
        var pool = Make();
        pool.Offer("Line before opting out.");
        await pool.FlushAsync(force: true);
        pool.Offer("Another before opting out.");
        pool.SetEnabled(false);
        var status = pool.GetStatus();
        Assert.Equal(0, status.PendingLines + status.OutboxBatches + status.ParkedBatches);
        Assert.False(pool.Offer("Ignored while off."));
    }

    [Fact]
    public async Task ImportsLegacyQueueOnce()
    {
        Directory.CreateDirectory(directory);
        var legacy = Path.Combine(directory, "..", $"legacy-{Guid.NewGuid()}.json");
        File.WriteAllText(legacy, """{"install":"x","queue":[{"text":"Old queued line here.","key":"k","firstSeen":"2026-11-11T03:17:00Z"},{"text":"Oturum Açtı","key":"k2","firstSeen":"2026-11-11T03:17:00Z"}],"sent":[]}""");
        try
        {
            var pool = Make(legacy: legacy);
            Assert.Equal(1, pool.GetStatus().PendingLines);
            Assert.False(File.Exists(legacy));
            Make(legacy: legacy);
            await pool.FlushAsync(force: true);
            Assert.Equal(["Old queued line here."], server.Lines.Select(l => l.Text));
            Assert.Equal(1_794_367_020, server.Lines.First().First);
        }
        finally
        {
            File.Delete(legacy + ".imported");
        }
    }

    [Fact]
    public void Filter()
    {
        Assert.True(NinoPool.Accepts("Run!"));
        Assert.True(NinoPool.Accepts("Where are you going, Franklin?"));
        Assert.False(NinoPool.Accepts("Oturum Açtı"));
        Assert.False(NinoPool.Accepts("PlayerOne signed in"));
        Assert.False(NinoPool.Accepts("100/100 HP 25%"));
        Assert.False(NinoPool.Accepts(string.Concat(Enumerable.Repeat("Long sentence. ", 40))));
        Assert.Equal("Hello there.", NinoPool.Clean("  Hello​\n  there.  "));
        Assert.Equal("gta-v", NinoPool.GameId("GTA V"));
        // Art arda tireler teke iner (Mac ile aynı).
        Assert.Equal("mafia-the-old-country", NinoPool.GameId("Mafia: The Old Country"));
        Assert.Equal("mafia-the-old-country", NinoPool.GameId("mafia--the-old-country"));
        Assert.Equal("marvel-s-spider-man-2", NinoPool.GameId("Marvel's  Spider-Man 2"));
        Assert.Equal("death-stranding-2-on-the-beach", NinoPool.GameId("  Death Stranding 2: On the Beach!! "));
        Assert.Null(NinoPool.GameId("  "));
        Assert.Null(NinoPool.GameId(null));
    }

    [Fact]
    public void EndpointConfiguration()
    {
        Directory.CreateDirectory(directory);
        Assert.Equal(NinoPool.LiveEndpoint, NinoPool.ConfiguredEndpoint(directory, _ => null));
        File.WriteAllText(Path.Combine(directory, "endpoint.txt"), "http://localhost:9000\n");
        Assert.Equal("http://localhost:9000/", NinoPool.ConfiguredEndpoint(directory, _ => null)?.ToString());
        Assert.Equal("pool.example", NinoPool.ConfiguredEndpoint(directory, n => n == "NINO_POOL_URL" ? "https://pool.example" : null)?.Host);
    }

    /// <summary>Yerel sunucuya gerçek gönderim: NINO_POOL_E2E_URL=http://localhost:8787 dotnet test --filter E2E</summary>
    [Fact]
    public async Task E2ELocalServer()
    {
        if (Environment.GetEnvironmentVariable("NINO_POOL_E2E_URL") is not { Length: > 0 } value) return;
        using var pool = new NinoPool(directory, "e2e-windows", "windows", true, new Uri(value), useConfiguredEndpoint: false);
        foreach (var text in new[] { "Where is Lamar going?", "Windows says hello to the pool.", "GET DOWN!" }) pool.Offer(text, "gta-v");
        await pool.FlushAsync(force: true);
        Assert.Equal(0, pool.GetStatus().OutboxBatches);
        Assert.Equal(0, pool.GetStatus().PendingLines);
    }
}
