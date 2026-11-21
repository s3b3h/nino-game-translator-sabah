// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

public class SubtitleServerTests
{
    private static readonly HttpClient Http = new() { Timeout = Timeout.InfiniteTimeSpan };

    private static async Task WaitUntil(Func<bool> condition, int timeoutMs = 3000)
    {
        var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (!condition())
        {
            Assert.True(DateTime.UtcNow < deadline, "Koşul zamanında sağlanmadı");
            await Task.Delay(20);
        }
    }

    private static async Task<List<string>> ReadLines(StreamReader reader, string until)
    {
        var lines = new List<string>();
        while (await reader.ReadLineAsync() is { } line)
        {
            lines.Add(line);
            if (line == until) break;
        }
        return lines;
    }

    [Fact]
    public async Task StreamsSubtitleAndClearEventsWithCors()
    {
        using var server = new SubtitleServer(0);
        var port = await server.StartAsync();

        using var response = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("*", response.Headers.GetValues("Access-Control-Allow-Origin").Single());
        Assert.StartsWith("text/event-stream", response.Content.Headers.ContentType?.ToString());

        await WaitUntil(() => server.ConnectedClients == 1);
        server.SendSubtitle("Merhaba", 4000, new TextBox(0.25, 0.8, 0.75, 0.87499));
        // Aynı cümlenin uzamış okuması: TV öncekinin üstüne yığmaz, yerine koyar.
        server.SendSubtitle("Merhaba dostum", 4000, replaces: true);
        server.Clear();

        using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
        var lines = await ReadLines(reader, "event: clear");
        Assert.Contains("event: subtitle", lines);
        Assert.Contains(lines, l => l.StartsWith("data:") && l.Contains("\"text\":\"Merhaba\"") && l.Contains("\"duration\":4000")
            && l.Contains("\"box\":{\"bottom\":0.875,\"left\":0.25,\"right\":0.75,\"top\":0.8}") && !l.Contains("replace"));
        Assert.Contains(lines, l => l.StartsWith("data:") && l.Contains("\"text\":\"Merhaba dostum\"") && l.Contains("\"replace\":true"));
    }

    /// TV yarı açık bağlantıyı adlı "ping" olayının gelmemesinden anlar; yorum satırını EventSource görmez.
    [Fact]
    public async Task PingIsSentAsNamedEvent()
    {
        using var server = new SubtitleServer(0, TimeSpan.FromMilliseconds(50));
        var port = await server.StartAsync();
        using var response = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
        var lines = await ReadLines(reader, "event: ping");
        Assert.Equal("event: ping", lines[^1]);
        Assert.Equal("data: {}", await reader.ReadLineAsync());
    }

    [Fact]
    public async Task StreamsScreenTranslationsAndTheirClear()
    {
        using var server = new SubtitleServer(0);
        var port = await server.StartAsync();
        using var response = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        await WaitUntil(() => server.ConnectedClients == 1);
        server.SendScreen([
            new("Map\nSettings", "Harita\nAyarlar", new TextBox(0.05, 0.3, 0.2, 0.4), 0.03),
            new("Open the door.", "Kapıyı aç.", new TextBox(0.4, 0.8, 0.6, 0.84), 0.04),
        ], 12000);
        server.ClearScreen();

        using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
        var lines = await ReadLines(reader, "event: screen-clear");
        Assert.Contains("event: screen", lines);
        Assert.Contains(lines, l => l.StartsWith("data:") && l.Contains("\"duration\":12000") &&
            l.Contains("{\"box\":{\"bottom\":0.4,\"left\":0.05,\"right\":0.2,\"top\":0.3},\"line\":0.03,\"paragraphs\":true,\"text\":\"Harita\\nAyarlar\"}") &&
            l.Contains("{\"box\":{\"bottom\":0.84,\"left\":0.4,\"right\":0.6,\"top\":0.8},\"line\":0.04,\"text\":\"Kapıyı aç.\"}"));
    }

    /// <summary>
    /// Nino: telefonun yanındaki panel ve balonlar, harita kartı Mac ile aynı alanlarla gider (TV sayfası aynı çizer);
    /// <c>overlay</c> işaretli olay TV'deki altyazıyı silmez.
    /// </summary>
    [Fact]
    public async Task PhoneAndMapItemsCarryTheirStyle()
    {
        using var server = new SubtitleServer(0);
        var port = await server.StartAsync();
        using var response = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        await WaitUntil(() => server.ConnectedClients == 1);
        server.SendScreen([
            new("", "Lucia", new TextBox(0.3, 0.2, 0.57, 0.85), 0.022) { Fill = "#f5f5f6", Alpha = 0.6, Backdrop = true },
            new("Are you high?", "Kafan mı güzel?", new TextBox(0.31, 0.5, 0.45, 0.53), 0.02)
                { Fill = "#acccfe", Ink = "#2c2c2e", Alpha = 0.95, Side = true, Angle = 5.71 },
            new("BUY FLOWERS", "ÇİÇEK AL", new TextBox(0.55, 0.6, 0.8, 0.7), 0.02) { Card = true },
        ], 120000, overlay: true);
        server.ClearScreen();
        using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
        var lines = await ReadLines(reader, "event: screen-clear");
        var data = Assert.Single(lines, l => l.StartsWith("data:") && l.Contains("\"items\""));
        Assert.Contains("\"overlay\":true", data);
        Assert.Contains("\"alpha\":0.6,\"backdrop\":true,", data);
        Assert.Contains("\"fill\":\"#f5f5f6\"", data);
        Assert.Contains("\"alpha\":0.95,\"angle\":5.7,", data);
        Assert.Contains("\"ink\":\"#2c2c2e\"", data);
        Assert.Contains("\"side\":true", data);
        Assert.Contains("\"card\":true", data);
    }

    /// <summary>Ek alanın çevirisi kendi olayıyla gider (eski TV uygulamaları tanımadığı olayı yok sayar; Mac ile aynı).</summary>
    [Fact]
    public async Task StreamsRegionTranslationsAndTheirClear()
    {
        using var server = new SubtitleServer(0);
        var received = new List<SubtitleEvent>();
        server.EventSent += received.Add;
        var port = await server.StartAsync();
        using var response = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        await WaitUntil(() => server.ConnectedClients == 1);
        var box = new TextBox(0.7, 0.05, 0.95, 0.12);
        server.SendRegion("q", "Demirciyi bul", box, 0.03);
        server.SendRegion("q", "", null);
        server.ClearRegions();

        using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
        var lines = await ReadLines(reader, "event: region-clear");
        Assert.Contains("event: region", lines);
        Assert.Contains("data: {\"box\":{\"bottom\":0.12,\"left\":0.7,\"right\":0.95,\"top\":0.05},\"id\":\"q\",\"line\":0.03,\"text\":\"Demirciyi bul\"}", lines);
        Assert.Contains("data: {\"id\":\"q\",\"text\":\"\"}", lines);
        Assert.Equal([new SubtitleEvent(SubtitleEventKind.Region, "Demirciyi bul", Id: "q", Box: box), new SubtitleEvent(SubtitleEventKind.Region, "", Id: "q"),
                      new SubtitleEvent(SubtitleEventKind.RegionClear)], received);
    }

    [Fact]
    public async Task ObsOverlayIsServedAndNotCountedAsTv()
    {
        using var server = new SubtitleServer(0);
        var port = await server.StartAsync();

        using var page = await Http.GetAsync($"http://127.0.0.1:{port}/obs");
        Assert.Equal(HttpStatusCode.OK, page.StatusCode);
        Assert.StartsWith("text/html", page.Content.Headers.ContentType?.ToString());
        Assert.Contains("/events?viewer=obs", await page.Content.ReadAsStringAsync());

        // OBS katmanı olayları alır ama "TV bağlı" sayısına katılmaz.
        using var response = await Http.GetAsync($"http://127.0.0.1:{port}/events?viewer=obs", HttpCompletionOption.ResponseHeadersRead);
        await Task.Delay(200);
        Assert.Equal(0, server.ConnectedClients);
        server.SendSubtitle("Merhaba", 4000);
        server.Clear();
        using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
        Assert.Contains("event: subtitle", await ReadLines(reader, "event: clear"));
    }

    /// Altyazı yalnız bilgisayar ekranındayken TV'ye altyazı gitmez; OBS katmanı ve dublaj sesi gitmeye devam eder.
    [Fact]
    public async Task SubtitlesSkipTvsWhenTvOutputIsOff()
    {
        using var server = new SubtitleServer(0) { SendsToTv = false };
        var port = await server.StartAsync();
        using var tv = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        using var obs = await Http.GetAsync($"http://127.0.0.1:{port}/events?viewer=obs", HttpCompletionOption.ResponseHeadersRead);
        await WaitUntil(() => server.ConnectedClients == 1);
        await Task.Delay(200);
        server.SendSubtitle("Merhaba", 4000);
        server.Clear();
        server.StopSpeech();

        using var obsReader = new StreamReader(await obs.Content.ReadAsStreamAsync());
        Assert.Contains("event: subtitle", await ReadLines(obsReader, "event: clear"));
        using var tvReader = new StreamReader(await tv.Content.ReadAsStreamAsync());
        Assert.DoesNotContain("event: subtitle", await ReadLines(tvReader, "event: speech-stop"));
    }

    /// Bilgisayar ekranındaki pencere sunucudan geçen altyazıyı alır; sunucu başlamamış olsa da.
    [Fact]
    public void LocalListenerGetsSubtitleAndClear()
    {
        using var server = new SubtitleServer(0);
        var received = new List<SubtitleEvent>();
        server.EventSent += received.Add;
        server.SendSubtitle("Merhaba", 4000, null, true);
        server.Clear();
        Assert.Equal([new SubtitleEvent(SubtitleEventKind.Subtitle, "Merhaba", 4000, true), SubtitleEvent.Cleared], received);
    }

    /// <summary>"Ekranı çevir" sonuçları da pencereye gider: altyazı yalnız bilgisayardayken (TV yok) hiçbir yerde görünmüyordu.</summary>
    [Fact]
    public void LocalListenerGetsScreenTranslations()
    {
        using var server = new SubtitleServer(0);
        var received = new List<SubtitleEvent>();
        server.EventSent += received.Add;
        var box = new TextBox(0.1, 0.1, 0.4, 0.2);
        server.SendScreen([new ScreenTranslation.Item("Map\nInventory", "Harita\nEnvanter", box, 0.03), new ScreenTranslation.Item("Leave", "Ayrıl", box, 0.03)], 12000);
        server.ClearScreen();
        Assert.Equal([new SubtitleEvent(SubtitleEventKind.Screen, "Harita\nEnvanter\nAyrıl", 12000, Paragraphs: true), new SubtitleEvent(SubtitleEventKind.ScreenClear)], received);
    }

    [Fact]
    public async Task TurkishTextIsSentAsUtf8()
    {
        using var server = new SubtitleServer(0);
        var port = await server.StartAsync();
        using var response = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        await WaitUntil(() => server.ConnectedClients == 1);
        server.SendSubtitle("Kapıyı tut, evlat!", 4000);
        using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
        var lines = await ReadLines(reader, "");
        lines = await ReadLines(reader, "");
        Assert.Contains(lines, l => l.Contains("Kapıyı tut, evlat!"));
    }

    [Fact]
    public async Task NewClientReceivesLastStyle()
    {
        using var server = new SubtitleServer(0);
        var port = await server.StartAsync();
        server.SendStyle(new SubtitleStyle(58, 10, SubtitlePlacement.Above, 40, true, SubtitleTextColor.Yellow, TvDisplayMode.Overlay, true, SubtitleBackgroundShape.Band));

        using var response = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
        string? data = null;
        while (await reader.ReadLineAsync() is { } line)
            if (line.StartsWith("data:")) { data = line; break; }
        Assert.Contains("\"fontSize\":58", data);
        Assert.Contains("\"bottomPercent\":10", data);
        Assert.Contains("\"placement\":\"above\"", data);
        Assert.Contains("\"background\":40", data);
        Assert.Contains("\"bold\":true", data);
        Assert.Contains("\"textColor\":\"yellow\"", data);
        Assert.Contains("\"displayMode\":\"overlay\"", data);
        // Varsayılan: önceki satırlar üstte kalır (eski davranış); ayar TV'ye gider.
        Assert.Contains("\"stackPrevious\":true", data);
        // Tam genişlik bandı TV'ye gider; eski kayıtta alan yoksa yazı kadar kalır.
        Assert.Contains("\"backgroundShape\":\"band\"", data);
        Assert.Equal(SubtitleBackgroundShape.Fit, System.Text.Json.JsonSerializer.Deserialize<SubtitleStyle>("{\"FontSize\":58}")!.BackgroundShape);
    }

    [Fact]
    public async Task StyleCarriesFontAndDefaultsToCondensed()
    {
        using var server = new SubtitleServer(0);
        var port = await server.StartAsync();
        server.SendStyle(new SubtitleStyle());
        Assert.Contains("\"font\":\"condensed\"", await FirstStyleData(port));
        server.SendStyle(new SubtitleStyle() with { Font = SubtitleFont.Rounded });
        Assert.Contains("\"font\":\"rounded\"", await FirstStyleData(port));
        server.SendStyle(new SubtitleStyle() with { Font = SubtitleFont.System });
        Assert.Contains("\"font\":\"system\"", await FirstStyleData(port));
    }

    [Fact]
    public async Task StyleCarriesWatermarkAndOldSettingsKeepIt()
    {
        using var server = new SubtitleServer(0);
        var port = await server.StartAsync();
        // Varsayılan: TV'nin sol altındaki Nino işareti görünür; ayar TV'ye gider.
        server.SendStyle(new SubtitleStyle());
        Assert.Contains("\"watermark\":true", await FirstStyleData(port));
        server.SendStyle(new SubtitleStyle() with { Watermark = false });
        Assert.Contains("\"watermark\":false", await FirstStyleData(port));
        // Eski kayıtta alan yoksa açık kalır.
        Assert.True(System.Text.Json.JsonSerializer.Deserialize<SubtitleStyle>("{\"FontSize\":58}")!.Watermark);
    }

    private static async Task<string?> FirstStyleData(int port)
    {
        using var response = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
        while (await reader.ReadLineAsync() is { } line)
            if (line.StartsWith("data:")) return line;
        return null;
    }

    [Fact]
    public void FontIsSavedAndOldSettingsGetCondensed()
    {
        var old = System.Text.Json.JsonSerializer.Deserialize<SubtitleStyle>("{\"FontSize\":58}");
        Assert.Equal(SubtitleFont.Condensed, old!.Font);
        var saved = System.Text.Json.JsonSerializer.Serialize(old with { Font = SubtitleFont.Modern });
        Assert.Contains("\"Modern\"", saved);
        Assert.Equal(SubtitleFont.Modern, System.Text.Json.JsonSerializer.Deserialize<SubtitleStyle>(saved)!.Font);
    }

    [Fact]
    public void DisplayModeIsSavedAndOldSettingsStayInsideTheApp()
    {
        var old = System.Text.Json.JsonSerializer.Deserialize<SubtitleStyle>("{\"FontSize\":58}");
        Assert.Equal(TvDisplayMode.InApp, old!.DisplayMode);
        var saved = System.Text.Json.JsonSerializer.Serialize(old with { DisplayMode = TvDisplayMode.Overlay });
        Assert.Contains("\"Overlay\"", saved);
        Assert.Equal(TvDisplayMode.Overlay, System.Text.Json.JsonSerializer.Deserialize<SubtitleStyle>(saved)!.DisplayMode);
    }

    [Fact]
    public void OldSavedStyleGetsNewDefaults()
    {
        var style = System.Text.Json.JsonSerializer.Deserialize<SubtitleStyle>("{\"FontSize\":58,\"BottomPercent\":12}");
        Assert.Equal(new SubtitleStyle(58, 12, SubtitlePlacement.Cover, 100, false), style);
        var again = System.Text.Json.JsonSerializer.Deserialize<SubtitleStyle>(System.Text.Json.JsonSerializer.Serialize(style! with { Placement = SubtitlePlacement.Below }));
        Assert.Equal(SubtitlePlacement.Below, again!.Placement);
    }

    [Fact]
    public async Task ClientCountDropsWhenClientDisconnects()
    {
        using var server = new SubtitleServer(0);
        var port = await server.StartAsync();
        var response = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        await WaitUntil(() => server.ConnectedClients == 1);
        response.Dispose();
        await WaitUntil(() => server.ConnectedClients == 0);
    }

    [Fact]
    public async Task HelloIdentifiesTheApp()
    {
        using var server = new SubtitleServer(0);
        var port = await server.StartAsync();
        using var http = new HttpClient();
        Assert.Equal("{\"app\":\"couchsubs\"}", await http.GetStringAsync($"http://127.0.0.1:{port}/hello"));
    }

    [Fact]
    public async Task UnknownPathIs404()
    {
        using var server = new SubtitleServer(0);
        var port = await server.StartAsync();
        using var response = await Http.GetAsync($"http://127.0.0.1:{port}/nope");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    /// Nino: çeviri başlayınca "started" olayı bağlı TV'ye gider; 20 sn içinde bağlanan TV de alır, OBS izleyicisi almaz.
    [Fact]
    public async Task StartedIsBroadcastAndReplayedToLateTvsOnly()
    {
        using var server = new SubtitleServer(0);
        var now = DateTime.UtcNow;
        server.Clock = () => now;
        var port = await server.StartAsync();

        using var early = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        await WaitUntil(() => server.ConnectedClients == 1);
        server.SendStarted();
        using var earlyReader = new StreamReader(await early.Content.ReadAsStreamAsync());
        Assert.Equal("event: started", (await ReadLines(earlyReader, "event: started"))[^1]);
        Assert.Equal("data: {}", await earlyReader.ReadLineAsync());

        // Geç bağlanan TV (19 sn sonra) olayı açılışta alır.
        now += TimeSpan.FromSeconds(19);
        using var late = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        await WaitUntil(() => server.ConnectedClients == 2);
        using var lateReader = new StreamReader(await late.Content.ReadAsStreamAsync());
        Assert.Equal("event: started", (await ReadLines(lateReader, "event: started"))[^1]);

        // OBS izleyicisi açılışta almaz.
        using var obs = await Http.GetAsync($"http://127.0.0.1:{port}/events?viewer=obs", HttpCompletionOption.ResponseHeadersRead);
        using var obsReader = new StreamReader(await obs.Content.ReadAsStreamAsync());
        // 20 sn geçince bağlanan TV de almaz.
        now += TimeSpan.FromSeconds(2);
        using var tooLate = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        await WaitUntil(() => server.ConnectedClients == 3);
        using var tooLateReader = new StreamReader(await tooLate.Content.ReadAsStreamAsync());
        server.Clear();
        Assert.DoesNotContain("event: started", await ReadLines(obsReader, "event: clear"));
        Assert.DoesNotContain("event: started", await ReadLines(tooLateReader, "event: clear"));
    }
}
