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
}
