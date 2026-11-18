// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Text;
using System.Text.Json;
using CouchSubs.Core;
using static CouchSubs.Core.NinoAssistant;

namespace CouchSubs.Core.Tests;

public class NinoAssistantTests
{
    private static Turn User(string text, int images = 0, int size = 5) =>
        new(Role.User, text, [.. Enumerable.Range(0, images).Select(i => Enumerable.Repeat((byte)(i + 1), size).ToArray())]);

    private static Turn Nino(string text) => new(Role.Assistant, text);

    private static JsonElement Root(Payload payload) => JsonDocument.Parse(ToJson(payload)).RootElement;

    [Fact]
    public void JsonHasTheServerShape()
    {
        var payload = Build("install-12345", "0.2.0", "tr", [User("TV'de altyazı çıkmıyor", images: 1), Nino("Hangi TV?"), User("Samsung")]);
        var root = Root(payload);
        Assert.Equal(1, root.GetProperty("v").GetInt32());
        Assert.Equal("install-12345", root.GetProperty("install").GetString());
        Assert.Equal("0.2.0", root.GetProperty("app").GetString());
        Assert.Equal("windows", root.GetProperty("platform").GetString());
        Assert.Equal("tr", root.GetProperty("language").GetString());
        var messages = root.GetProperty("messages").EnumerateArray().ToList();
        Assert.Equal(["user", "assistant", "user"], messages.Select(m => m.GetProperty("role").GetString()));
        Assert.Equal("TV'de altyazı çıkmıyor", messages[0].GetProperty("text").GetString());
        var image = Assert.Single(messages[0].GetProperty("images").EnumerateArray());
        Assert.Equal("image/jpeg", image.GetProperty("mime").GetString());
        Assert.Equal(new byte[] { 1, 1, 1, 1, 1 }, Convert.FromBase64String(image.GetProperty("data").GetString()!));
        // Fotoğrafsız mesajlarda "images" hiç yazılmaz; Nino mesajında asla yoktur.
        Assert.False(messages[1].TryGetProperty("images", out _));
        Assert.False(messages[2].TryGetProperty("images", out _));
        Assert.DoesNotContain("\\u", ToJson(payload));
    }

    [Fact]
    public void LastMessageMustBeTheUsers()
    {
        Assert.Throws<ArgumentException>(() => Build("install-12345", "1", "en", [User("hi"), Nino("hello")]));
        Assert.Throws<ArgumentException>(() => Build("install-12345", "1", "en", []));
        Assert.Throws<ArgumentException>(() => Build("install-12345", "1", "en", [User("   ")]));
    }

    [Fact]
    public void KeepsTheLast24MessagesAndStartsWithTheUser()
    {
        var turns = new List<Turn>();
        for (var i = 0; i < 20; i++) { turns.Add(User($"soru {i}")); turns.Add(Nino($"cevap {i}")); }
        turns.Add(User("son soru"));
        var messages = Root(Build("install-12345", "1", "tr", turns)).GetProperty("messages").EnumerateArray().ToList();
        Assert.True(messages.Count <= MaxMessages);
        Assert.Equal("user", messages[0].GetProperty("role").GetString());
        Assert.Equal("son soru", messages[^1].GetProperty("text").GetString());
        // 24'ün ilki bir Nino cevabıydı; atıldı.
        Assert.Equal(MaxMessages - 1, messages.Count);
    }

    [Fact]
    public void TextIsTrimmedAndClipped()
    {
        var messages = Root(Build("install-12345", new string('9', 80), "tr", [User("  " + new string('a', 3000) + "  ")])).GetProperty("messages");
        Assert.Equal(MaxText, messages[0].GetProperty("text").GetString()!.Length);
    }

    [Fact]
    public void OnlyTheLatestTwoImageMessagesCarryImages()
    {
        var payload = Build("install-12345", "1", "tr",
        [
            User("ilk", images: 2), Nino("a"), User("", images: 1), Nino("b"), User("üçüncü", images: 1), Nino("c"), User("dördüncü", images: 5),
        ]);
        var messages = Root(payload).GetProperty("messages").EnumerateArray().ToList();
        Assert.Equal("ilk " + ScreenshotMarker, messages[0].GetProperty("text").GetString());
        Assert.False(messages[0].TryGetProperty("images", out _));
        // Yalnız fotoğraftan oluşan eski mesaj boş kalmaz (sunucu boş mesajı atar).
        Assert.Equal(ScreenshotMarker, messages[2].GetProperty("text").GetString());
        Assert.False(messages[2].TryGetProperty("images", out _));
        Assert.Equal(1, messages[4].GetProperty("images").GetArrayLength());
        // Mesaj başına en çok 3 fotoğraf.
        Assert.Equal(MaxImagesPerMessage, messages[6].GetProperty("images").GetArrayLength());
    }

    [Fact]
    public void ImageOnlyLatestMessageIsAccepted()
    {
        var messages = Root(Build("install-12345", "1", "tr", [User("", images: 1)])).GetProperty("messages");
        Assert.Equal("", messages[0].GetProperty("text").GetString());
        Assert.Equal(1, messages[0].GetProperty("images").GetArrayLength());
    }

    [Fact]
    public void BodyOverTheLimitDropsTheOlderImageMessageFirst()
    {
        var turns = new List<Turn> { User("eski", images: 3, size: 4000), Nino("tamam"), User("yeni", images: 3, size: 4000) };
        // Her mesajın fotoğrafları ~16 KB base64; sınır yalnız bir mesajınkine yetiyor.
        var payload = Build("install-12345", "1", "tr", turns, maxBodyBytes: 24_000);
        Assert.True(Encoding.UTF8.GetByteCount(ToJson(payload)) <= 24_000);
        Assert.Null(payload.Messages[0].Images);
        Assert.Equal("eski " + ScreenshotMarker, payload.Messages[0].Text);
        Assert.Equal(3, payload.Messages[2].Images!.Count);

        var tiny = Build("install-12345", "1", "tr", turns, maxBodyBytes: 2_000);
        Assert.All(tiny.Messages, message => Assert.Null(message.Images));
        Assert.Equal("yeni " + ScreenshotMarker, tiny.Messages[2].Text);
    }

    [Fact]
    public void SixFullSizeImagesFitTheServerBody()
    {
        var turns = new List<Turn> { User("a", images: 3, size: TargetImageBytes), Nino("b"), User("c", images: 3, size: TargetImageBytes) };
        var payload = Build("install-12345", "1", "tr", turns);
        Assert.Equal(6, payload.Messages.Sum(message => message.Images?.Count ?? 0));
        Assert.True(Encoding.UTF8.GetByteCount(ToJson(payload)) <= MaxBodyBytes);
    }

    [Fact]
    public void EndpointIsUnderThePool()
    {
        Assert.Equal("https://pool.example/v1/assistant", Endpoint(new Uri("https://pool.example/"))!.ToString());
        Assert.Null(Endpoint(null));
    }

    [Theory]
    [InlineData(503, """{"ok":false,"error":"assistant_disabled"}""", Outcome.Disabled)]
    [InlineData(503, """{"ok":false}""", Outcome.Failed)]
    [InlineData(429, """{"ok":false,"error":"rate_limited"}""", Outcome.RateLimited)]
    [InlineData(429, """{"ok":false,"error":"busy"}""", Outcome.Busy)]
    [InlineData(400, """{"ok":false,"error":"bad_request"}""", Outcome.Rejected)]
    [InlineData(413, """{"ok":false,"error":"image_too_large"}""", Outcome.Rejected)]
    [InlineData(502, """{"ok":false,"error":"model_failed"}""", Outcome.Failed)]
    [InlineData(502, """{"ok":false,"error":"refused"}""", Outcome.Failed)]
    [InlineData(500, "<html>oops</html>", Outcome.Failed)]
    [InlineData(200, """{"ok":true}""", Outcome.Failed)]
    [InlineData(200, "not json", Outcome.Failed)]
    public void ErrorsAreMapped(int status, string body, Outcome expected) =>
        Assert.Equal(expected, Map((HttpStatusCode)status, body).Outcome);

    [Fact]
    public void ReplyAndReportAreRead()
    {
        var result = Map(HttpStatusCode.OK, """{"ok":true,"reply":"  Merhaba!  ","report":"r-42"}""");
        Assert.Equal(Outcome.Replied, result.Outcome);
        Assert.Equal("Merhaba!", result.Reply);
        Assert.Equal("r-42", result.Report);
        Assert.Null(Map(HttpStatusCode.OK, """{"ok":true,"reply":"x","report":null}""").Report);
    }

    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public string? Body { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
            return respond(request);
        }
    }

    [Fact]
    public async Task SendPostsJsonAndReadsRetryAfter()
    {
        var handler = new StubHandler(request =>
        {
            Assert.Equal(HttpMethod.Post, request.Method);
            Assert.Equal("application/json", request.Content!.Headers.ContentType!.MediaType);
            var response = new HttpResponseMessage(HttpStatusCode.TooManyRequests) { Content = new StringContent("""{"ok":false,"error":"busy"}""") };
            response.Headers.RetryAfter = new System.Net.Http.Headers.RetryConditionHeaderValue(TimeSpan.FromSeconds(3600));
            return response;
        });
        using var http = new HttpClient(handler);
        var result = await SendAsync(http, new Uri("https://pool.example/v1/assistant"), Build("install-12345", "1", "tr", [User("selam")]));
        Assert.Equal(Outcome.Busy, result.Outcome);
        Assert.Equal(TimeSpan.FromHours(1), result.RetryAfter);
        Assert.Contains("\"selam\"", handler.Body);
    }

    [Fact]
    public async Task NetworkErrorsAndMissingEndpointAreRetryableFailures()
    {
        using var http = new HttpClient(new StubHandler(_ => throw new HttpRequestException("yok")));
        var payload = Build("install-12345", "1", "tr", [User("selam")]);
        Assert.Equal(Outcome.Failed, (await SendAsync(http, new Uri("https://pool.example/v1/assistant"), payload)).Outcome);
        Assert.Equal(Outcome.Failed, (await SendAsync(http, null, payload)).Outcome);
    }

    [Fact]
    public void ReplyIsSplitIntoParagraphsNumberedItemsAndLinks()
    {
        var blocks = Format("Şunu dene:\n\n1. Ayarlar'ı aç.\n2) https://nino.example/kurulum adresine git.\n\nOlmazsa yaz.\nBen buradayım.");
        Assert.Equal(4, blocks.Count);
        Assert.Null(blocks[0].Number);
        Assert.Equal("1.", blocks[1].Number);
        Assert.Equal("Ayarlar'ı aç.", Assert.Single(blocks[1].Spans).Text);
        Assert.Equal("2.", blocks[2].Number);
        var link = blocks[2].Spans[0];
        Assert.Equal(new Uri("https://nino.example/kurulum"), link.Link);
        Assert.Equal(" adresine git.", blocks[2].Spans[1].Text);
        Assert.Equal("Olmazsa yaz.\nBen buradayım.", Assert.Single(blocks[3].Spans).Text);
    }

    [Fact]
    public void OnlyWebLinksAreClickableAndTrailingPunctuationStaysOut()
    {
        var spans = Linkify("Bak: https://a.example/x. Ya da javascript:alert(1) ya da file:///C:/x");
        Assert.Equal(new Uri("https://a.example/x"), spans[1].Link);
        Assert.StartsWith(". Ya da", spans[2].Text);
        Assert.Single(spans, span => span.Link is not null);
    }

    // --- Sohbet durumu ---

    private static Func<IReadOnlyList<Turn>, Task<Result>> Answer(Result result, List<IReadOnlyList<Turn>>? seen = null) => turns =>
    {
        seen?.Add(turns);
        return Task.FromResult(result);
    };

    [Fact]
    public async Task NoticesAreNeverSentAndRetryResendsTheSameConversation()
    {
        var chat = new NinoChat();
        var seen = new List<IReadOnlyList<Turn>>();
        await chat.SendAsync("selam", [], Answer(new Result(Outcome.Replied, "Merhaba!", "r-1"), seen));
        await chat.SendAsync("TV'm Samsung", [], Answer(new Result(Outcome.Failed), seen));
        Assert.Equal(NinoChat.EntryKind.Notice, chat.Entries[^1].Kind);
        Assert.True(chat.Entries[^1].CanRetry);
        Assert.Equal("r-1", chat.Entries[1].Report);

        Assert.True(await chat.RetryAsync(Answer(new Result(Outcome.Replied, "Tamam."), seen)));
        Assert.Equal(seen[1].Select(turn => turn.Text), seen[2].Select(turn => turn.Text));
        Assert.Equal(["selam", "Merhaba!", "TV'm Samsung"], seen[2].Select(turn => turn.Text));
        Assert.DoesNotContain(chat.Entries, entry => entry.Kind == NinoChat.EntryKind.Notice);
        Assert.Equal("Tamam.", chat.Entries[^1].Text);
    }

    [Fact]
    public async Task DisabledIsANoticeWithoutRetry()
    {
        var chat = new NinoChat();
        await chat.SendAsync("selam", [], Answer(new Result(Outcome.Disabled)));
        Assert.Equal(Outcome.Disabled, chat.Entries[^1].Outcome);
        Assert.False(chat.Entries[^1].CanRetry);
        Assert.False(await chat.RetryAsync(Answer(new Result(Outcome.Replied, "x"))));
        Assert.Single(chat.Turns());
    }

    [Fact]
    public async Task NewChatDropsALateReply()
    {
        var chat = new NinoChat();
        var pending = new TaskCompletionSource<Result>();
        var sending = chat.SendAsync("selam", [], _ => pending.Task);
        Assert.True(chat.Waiting);
        Assert.False(await chat.SendAsync("ikinci", [], Answer(new Result(Outcome.Replied, "x"))));
        chat.Reset();
        pending.SetResult(new Result(Outcome.Replied, "geç cevap"));
        await sending;
        Assert.True(chat.IsEmpty);
        Assert.False(chat.Waiting);
    }

    [Fact]
    public async Task EmptyMessagesAreNotSentAndImagesAreCapped()
    {
        var chat = new NinoChat();
        Assert.False(await chat.SendAsync("   ", [], Answer(new Result(Outcome.Replied, "x"))));
        Assert.True(chat.IsEmpty);
        await chat.SendAsync("", [[1], [2], [3], [4]], Answer(new Result(Outcome.Replied, "x")));
        Assert.Equal(3, chat.Entries[0].Jpegs.Count);
    }
}
