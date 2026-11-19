// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.Core.LgTv;
using CouchSubs.RemotePlay;
using CouchSubs.Shell;

namespace CouchSubs.Shell.Tests;

/// <summary>Nino: "Cihaz bilgileri"nin TV, konsol ve durum satırları. Ad, adres ve serbest metin girmez.</summary>
public class DeviceReportTests
{
    [Fact]
    public void TvIsBrandAndAppVersionWithoutNameOrAddress()
    {
        Assert.Null(DeviceReport.Tv(null, "3.4.0", connected: true));
        Assert.Equal("LG webOS · TV uygulaması 3.4.0 · bağlı", DeviceReport.Tv(new LgTv("Zeynep'in TV'si", "192.168.1.153"), "3.4.0", connected: true));
        Assert.Equal("Samsung Tizen · bağlı değil", DeviceReport.Tv(new LgTv("[TV] Salon", "192.168.1.20", TvBrand.Samsung), null, connected: false));
        Assert.Equal("Android TV · TV uygulaması 0.2.6-beta.3 · bağlı",
            DeviceReport.Tv(new LgTv("Android TV", "", TvBrand.AndroidTv), " 0.2.6-beta.3 ", connected: true));
        // Sürüm gibi görünmeyen değer satıra girmez.
        Assert.Equal("LG webOS · bağlı değil", DeviceReport.Tv(new LgTv("LG TV", "192.168.1.153"), "192.168.1.153 | x", connected: false));
    }

    [Fact]
    public void ConsoleTellsTheConnectionPath()
    {
        var settings = new UserSettings();
        Assert.Equal("PS5 · Remote Play", DeviceReport.Console(settings, GameConsoleKind.PlayStation, null));
        Assert.Equal("PS5 · Remote Play penceresi (chiaki-ng)",
            DeviceReport.Console(settings with { FrameSource = FrameSource.RemotePlayWindow, RemotePlayApp = RemotePlayApp.Chiaki }, GameConsoleKind.PlayStation, null));
        Assert.Equal("Seçilen pencere", DeviceReport.Console(settings with { FrameSource = FrameSource.CaptureWindow }, GameConsoleKind.PlayStation, null));
        Assert.Equal("Xbox Series X · uzaktan oynatma",
            DeviceReport.Console(settings, GameConsoleKind.Xbox, new XboxConsole("F4", "Oturma Odası Xbox", "XboxSeriesX", true)));
        Assert.Equal("Xbox · uzaktan oynatma", DeviceReport.Console(settings, GameConsoleKind.Xbox, null));
        Assert.Equal("Yakalama kartı", DeviceReport.Console(settings with { VideoSource = VideoSource.Card }, GameConsoleKind.PlayStation, null));
        Assert.Equal("Xbox · oyun penceresi",
            DeviceReport.Console(settings with { VideoSource = VideoSource.Window, GameConsole = GameConsole.Xbox }, GameConsoleKind.PlayStation, null));
        Assert.Equal("PS5 · oyun penceresi", DeviceReport.Console(settings with { VideoSource = VideoSource.Window }, GameConsoleKind.PlayStation, null));
    }

    [Theory]
    [InlineData("XboxSeriesX", "Xbox Series X")]
    [InlineData("XboxSeriesS", "Xbox Series S")]
    [InlineData("XboxOne", "Xbox One")]
    [InlineData("Xbox", "Xbox")]
    [InlineData("Ali'nin Xbox'ı", "Xbox")]
    [InlineData(null, "Xbox")]
    public void XboxModelIsReadableAndNeverAName(string? model, string expected) => Assert.Equal(expected, DeviceReport.XboxModel(model));

    [Fact]
    public void StatusNamesThePhaseAndOnlyTheConsoleCode()
    {
        var settings = new UserSettings();
        string Status(bool running, SessionState state, string? last = null) =>
            DeviceReport.Status(running, settings, GameConsoleKind.PlayStation, state, GameWindowStatus.Stopped, CaptureCardState.Stopped, last);

        Assert.Equal("çeviri kapalı, PS5: Disconnected", Status(false, SessionState.Disconnected(DisconnectKind.Stopped)));
        Assert.Equal("çeviri açık, PS5: Streaming", Status(true, SessionState.Streaming));
        Assert.Equal("çeviri açık, PS5: Connecting", Status(true, SessionState.Connecting));
        Assert.Equal("çeviri açık, PS5: Disconnected (Rejected 0x80108bff)", Status(true, SessionState.Disconnected(DisconnectKind.Rejected, "0x80108bff")));
        // PS5 bulunamadıysa ayrıntı adrestir; adres yazılmaz.
        Assert.Equal("çeviri açık, PS5: Disconnected (NotFound)", Status(true, SessionState.Disconnected(DisconnectKind.NotFound, "192.168.1.253")));
        Assert.Equal("çeviri kapalı, PS5: Disconnected, son kopma: ConsoleAsleep", Status(false, SessionState.Disconnected(DisconnectKind.Stopped), "ConsoleAsleep"));
        Assert.Equal("çeviri kapalı, PS5: Disconnected", Status(false, SessionState.Disconnected(DisconnectKind.Stopped), "PS5-789 192.168.1.253"));

        Assert.Equal("çeviri açık, pencere: Capturing", DeviceReport.Status(true, settings with { VideoSource = VideoSource.Window },
            GameConsoleKind.PlayStation, SessionState.Streaming, GameWindowStatus.Capturing, CaptureCardState.Stopped));
        Assert.Equal("çeviri açık, kart: NoCard", DeviceReport.Status(true, settings with { VideoSource = VideoSource.Card },
            GameConsoleKind.PlayStation, SessionState.Streaming, GameWindowStatus.Stopped, CaptureCardState.NoCard));
        Assert.Equal("çeviri açık, Xbox: Disconnected (Refused)", DeviceReport.Status(true, settings, GameConsoleKind.Xbox,
            SessionState.Disconnected(DisconnectKind.Refused, "Oturma Odası Xbox yayını reddetti"), GameWindowStatus.Stopped, CaptureCardState.Stopped));
    }

    [Fact]
    public void ControllerSummaryHasNoNamesOrAddresses()
    {
        var store = new MemoryStore();
        store.Save(StoreKeys.AccountId, Enumerable.Repeat((byte)1, 8).ToArray());
        store.Save(StoreKeys.Console, new RegisteredConsole("192.168.1.253", "PS5-789", Enumerable.Repeat((byte)0x31, 16).ToArray(), Enumerable.Repeat((byte)2, 16).ToArray()));
        store.Save(StoreKeys.Tv, new LgTv("Zeynep'in TV'si", "192.168.1.153"));
        store.Save(StoreKeys.TvKey, "tv-key");
        store.Save(StoreKeys.TvAppVersion, "3.4.0");
        var controller = AppControllerTests.Make(store: store);

        var rows = controller.DeviceRows("3.4.0");
        Assert.Equal(["app", "device", "system", "tv", "console", "status"], rows.Select(row => row.Id));
        Assert.Equal("LG webOS · TV uygulaması 3.4.0 · bağlı değil", rows.Single(row => row.Id == "tv").Value);
        Assert.Equal("PS5 · Remote Play", rows.Single(row => row.Id == "console").Value);
        Assert.StartsWith("çeviri kapalı, PS5: Disconnected", rows.Single(row => row.Id == "status").Value);

        var summary = controller.DeviceSummary("3.4.0");
        Assert.StartsWith("app: 3.4.0 | device: ", summary);
        // PS5'in ve TV'nin adı, adresleri ve TV anahtarı özete girmez.
        foreach (var secret in new[] { "PS5-789", "Zeynep", "192.168", "tv-key" })
            Assert.DoesNotContain(secret, summary, StringComparison.Ordinal);
    }

    [Fact]
    public void SummaryWithoutATvHasNoTvRow()
    {
        var rows = AppControllerTests.Make().DeviceRows("3.4.0");
        Assert.DoesNotContain(rows, row => row.Id == "tv");
        Assert.Contains(rows, row => row.Id == "console");
    }
}
