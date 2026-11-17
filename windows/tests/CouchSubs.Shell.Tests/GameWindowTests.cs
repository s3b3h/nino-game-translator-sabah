// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core;
using CouchSubs.RemotePlay;

namespace CouchSubs.Shell.Tests;

/// <summary>Nino: görüntünün bu bilgisayardaki PS Remote Play penceresinden okunması (Mac: GameWindowTests.swift).</summary>
public class GameWindowTests
{
    private static GameWindowInfo Window(string process, double w, double h, int id = 1, string title = "") =>
        new(id, process, title, new ScreenArea(0, 0, w, h));

    [Fact]
    public void PicksLargestRemotePlayWindow()
    {
        var picked = GameWindowRules.Pick([
            Window("chrome", 1600, 900, 1),
            Window("RemotePlay", 400, 300, 2),
            Window("RemotePlay", 1280, 720, 3),
            Window("chiaki", 200, 100, 4),
        ]);
        Assert.Equal(3, (int)picked!.Handle);
    }

    [Fact]
    public void MatchesTitleAndIgnoresTinyOrOtherWindows()
    {
        Assert.Equal(5, (int)GameWindowRules.Pick([Window("chiaki-ng", 960, 540, 5)])!.Handle);
        Assert.Equal(6, (int)GameWindowRules.Pick([Window("app", 960, 540, 6, "PS Remote Play")])!.Handle);
        Assert.Null(GameWindowRules.Pick([Window("RemotePlay", 300, 150)]));
        Assert.Null(GameWindowRules.Pick([Window("explorer", 1200, 800)]));
    }

    /// <summary>Nino: Xbox: Xbox uygulaması, Greenlight ya da başlığında "Xbox" olan tarayıcı; PS5 pencereleri seçilmez.</summary>
    [Fact]
    public void PicksXboxStreamWindow()
    {
        GameWindowInfo[] windows = [
            Window("chrome", 1800, 1000, 1, "Haberler - Google Chrome"),
            Window("msedge", 1400, 800, 2, "Xbox Cloud Gaming on Xbox.com - Microsoft Edge"),
            Window("RemotePlay", 1600, 900, 3),
            Window("notepad", 1700, 900, 4, "xbox notları"),
        ];
        Assert.Equal(2, (int)GameWindowRules.Pick(windows, GameConsole.Xbox)!.Handle);
        Assert.Equal(5, (int)GameWindowRules.Pick([.. windows, Window("XboxPcApp", 1500, 850, 5, "Xbox")], GameConsole.Xbox)!.Handle);
        Assert.Null(GameWindowRules.Pick([Window("Greenlight", 300, 150, 6)], GameConsole.Xbox));
        Assert.Equal(3, (int)GameWindowRules.Pick(windows, GameConsole.Ps5)!.Handle);
        Assert.Equal("Xbox", GameWindowRules.AppName("XboxPcApp"));
        Assert.Equal("xbox.com/play", GameWindowRules.AppName("msedge"));
        Assert.Equal("PS Remote Play", GameWindowRules.AppName("RemotePlay"));
    }

    [Fact]
    public void GameAreaIsLetterboxedInsideTheClientArea()
    {
        Assert.Equal(new ScreenArea(100, 50, 1280, 720), GameWindowRules.GameArea(new ScreenArea(100, 50, 1280, 720)));
        // Geniş pencere: yanlarda bant.
        Assert.Equal(new ScreenArea(360, 0, 1280, 720), GameWindowRules.GameArea(new ScreenArea(0, 0, 2000, 720)));
        // 16:10 tam ekran: üstte ve altta bant.
        Assert.Equal(new ScreenArea(0, 60, 1920, 1080), GameWindowRules.GameArea(new ScreenArea(0, 0, 1920, 1200)));
    }

    [Fact]
    public void OverlaySitsAtTheBottomOfTheGame()
    {
        var place = GameWindowRules.OverlayOver(new ScreenArea(100, 100, 1000, 500), 200);
        Assert.Equal(900, place.Width);
        Assert.Equal(150, place.Left);
        Assert.Equal(100 + 500 - 15 - 200, place.Top);
    }

    [Fact]
    public void OldSettingsKeepPs5AndNewChoiceIsSavedAsText()
    {
        var old = JsonSerializer.Deserialize<UserSettings>("""{"SourceLanguage":"en"}""")!;
        Assert.Equal(VideoSource.Ps5, old.VideoSource);
        var json = JsonSerializer.Serialize(new UserSettings { VideoSource = VideoSource.Window });
        Assert.Contains("\"VideoSource\":\"Window\"", json);
        Assert.Equal(VideoSource.Window, JsonSerializer.Deserialize<UserSettings>(json)!.VideoSource);
    }

    [Fact]
    public async Task StartsFromTheWindowWithoutPs5OrTv()
    {
        var services = new FakeServices();
        var controller = AppControllerTests.Make(services);
        Assert.False(controller.CanStart);
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Window };
        Assert.True(controller.CanStart);
        Assert.True(controller.ShowsOnComputer);
        Assert.False(controller.ShowsOnTv);

        await controller.StartAsync();
        Assert.True(controller.IsRunning);
        Assert.Empty(services.Streams);
        var stream = Assert.Single(services.WindowStreams);
        Assert.True(stream.Started);
        Assert.Equal("Open PS Remote Play or chiaki-ng and start playing", controller.Ps5StatusText);

        stream.Emit(GameWindowStatus.Capturing, "PS Remote Play", new ScreenArea(0, 0, 1280, 720));
        Assert.Equal(SessionPhase.Streaming, controller.SessionState.Phase);
        Assert.Equal("Reading PS Remote Play", controller.Ps5StatusText);
        Assert.Equal(new ScreenArea(0, 0, 1280, 720), controller.GameArea);

        controller.Stop();
        Assert.False(stream.Started);
        Assert.Null(controller.GameArea);
        Assert.Equal(GameWindowStatus.Stopped, controller.WindowStatus);
    }

    [Fact]
    public async Task SwitchingSourceWhileRunningRestartsWithTheNewSource()
    {
        var services = new FakeServices();
        var controller = AppControllerTests.Make(services);
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Window };
        await controller.StartAsync();
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Ps5 };
        // PS5 kurulu değil: eski pencere kaynağı durur, çeviri başlayamaz.
        Assert.False(Assert.Single(services.WindowStreams).Started);
        Assert.False(controller.IsRunning);
    }
}

public class GameWindowSetupTests
{
    /// <summary>Nino: "Xbox'ta oynuyorum": PS5 adımları atlanır, TV adımı sorulur; "TV'm yok" ile altyazı bilgisayarda.</summary>
    [Fact]
    public async Task XboxWindowSetupSendsSubtitlesToTheTv()
    {
        var services = new FakeServices();
        var settings = new MemorySettings();
        var controller = AppControllerTests.Make(services, new MemoryStore(), settings);
        controller.UseXboxWindowSetup();
        Assert.Equal(OnboardingStep.Tv, controller.Step);
        Assert.True(controller.UsesXboxWindow);
        Assert.True(controller.ShowsOnTv);
        Assert.False(controller.ShowsOnComputer);
        Assert.False(controller.CanStart);
        controller.Back();
        Assert.Equal(OnboardingStep.Welcome, controller.Step);
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        Assert.True(controller.CanStart);
        await controller.StartAsync();
        Assert.Equal(GameConsole.Xbox, services.WindowConsole);
        Assert.Equal(GameConsole.Xbox, JsonSerializer.Deserialize<UserSettings>(JsonSerializer.Serialize(controller.Settings))!.GameConsole);
    }

    [Fact]
    public void SetupWithoutPs5WhenPlayingOnThisComputer()
    {
        var store = new MemoryStore();
        var settings = new MemorySettings();
        var controller = AppControllerTests.Make(new FakeServices(), store, settings);
        Assert.Equal(OnboardingStep.Welcome, controller.Step);
        controller.UseGameWindowSetup();
        Assert.Equal(OnboardingStep.Translation, controller.Step);
        Assert.True(controller.UsesGameWindow);
        Assert.True(controller.CanStart);
        controller.Step = OnboardingStep.Done;
        var reopened = AppControllerTests.Make(new FakeServices(), store, settings);
        Assert.Equal(OnboardingStep.Done, reopened.Step);
        Assert.True(reopened.UsesGameWindow);
    }

    /// <summary>Nino: Ayarlar › Bağlantı'da Xbox'a geçince PS5'e doğrudan bağlanma bırakılır, Xbox penceresi okunur.</summary>
    [Fact]
    public void SwitchConsoleInSettings()
    {
        var controller = AppControllerTests.Make(new FakeServices(), new MemoryStore(), new MemorySettings());
        Assert.Equal(VideoSource.Ps5, controller.Settings.VideoSource);
        controller.SwitchConsole(GameConsole.Xbox);
        Assert.Equal(GameConsole.Xbox, controller.Settings.GameConsole);
        Assert.Equal(VideoSource.Window, controller.Settings.VideoSource);
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Card };
        controller.SwitchConsole(GameConsole.Ps5);
        Assert.Equal(VideoSource.Card, controller.Settings.VideoSource);
    }
}
