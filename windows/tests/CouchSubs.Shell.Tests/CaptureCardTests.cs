// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı (Mac: CaptureCardTests.swift ile aynı kurallar).

using System.Text.Json;
using CouchSubs.Core;
using CouchSubs.Core.LgTv;
using CouchSubs.RemotePlay;

namespace CouchSubs.Shell.Tests;

/// <summary>Nino: görüntünün bu bilgisayara takılı HDMI yakalama kartından okunması.</summary>
public class CaptureCardTests
{
    private static CaptureCardInfo Device(string name, string id = "", string group = "") => new(id.Length > 0 ? id : name, name, group);

    [Fact]
    public void PrefersACardOverTheLaptopCamera()
    {
        var picked = CaptureCardPicker.Pick([Device("Integrated Camera"), Device("Elgato HD60 X"), Device("Logitech BRIO")]);
        Assert.Equal("Elgato HD60 X", picked!.Name);
        // Ucuz kartlar çoğunlukla "USB Video" diye görünür.
        Assert.Equal("USB Video", CaptureCardPicker.Pick([Device("HP TrueVision HD Camera"), Device("USB Video")])!.Name);
    }

    [Fact]
    public void SkipsWebcamsAndFallsBackToTheFirstOtherDevice()
    {
        Assert.Null(CaptureCardPicker.Pick([Device("Integrated Webcam"), Device("Logitech C920")]));
        Assert.Equal("ACME 1080P", CaptureCardPicker.Pick([Device("Front Camera"), Device("ACME 1080P"), Device("Other")])!.Name);
        Assert.Null(CaptureCardPicker.Pick([]));
    }

    [Fact]
    public void HonoursTheChosenDeviceWhilePluggedIn()
    {
        var devices = new[] { Device("Elgato HD60 X", "a"), Device("Logitech BRIO", "b") };
        Assert.Equal("b", CaptureCardPicker.Pick(devices, preferred: "b")!.Id);
        // Seçilen aygıt takılı değilse kendiliğinden seçilir.
        Assert.Equal("a", CaptureCardPicker.Pick(devices, preferred: "gone")!.Id);
    }

    [Fact]
    public void FindsTheCardsAudioBySameUsbDeviceThenByName()
    {
        var card = Device("Live Gamer Ultra", "v", "{1234}");
        var audio = new[] { Device("Microphone (Realtek)", "m", "{9999}"), Device("Digital Audio Interface", "d", "{1234}") };
        Assert.Equal("d", CaptureCardPicker.Audio(card, audio)!.Id);
        var noGroup = Device("Cam Link 4K", "v");
        Assert.Equal("c", CaptureCardPicker.Audio(noGroup, [Device("Microphone", "m"), Device("Cam Link 4K", "c")])!.Id);
        Assert.Null(CaptureCardPicker.Audio(noGroup, [Device("Microphone", "m")]));
        // Yerleşik aygıtların ortak kabı eşleştirme sayılmaz: bilgisayarın mikrofonu hoparlöre verilmez.
        var builtIn = Device("Integrated HDMI Capture", "v", "{00000000-0000-0000-FFFF-FFFFFFFFFFFF}");
        Assert.Null(CaptureCardPicker.Audio(builtIn, [Device("Microphone Array (Realtek)", "m", "{00000000-0000-0000-FFFF-FFFFFFFFFFFF}")]));
    }

    private static byte[] Image(int width, int height, byte value, int stride)
    {
        var pixels = new byte[stride * height];
        for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
        {
            var p = y * stride + x * 4;
            pixels[p] = pixels[p + 1] = pixels[p + 2] = value;
            pixels[p + 3] = 255;
        }
        return pixels;
    }

    [Fact]
    public void BlackFrameIgnoresNoiseButSeesAnyPicture()
    {
        // HDCP açıkken kart simsiyah ya da çok karanlık gürültülü kare verir.
        Assert.True(BlackFrame.IsBlack(Image(640, 360, 0, 640 * 4), 640, 360, 640 * 4));
        Assert.True(BlackFrame.IsBlack(Image(640, 360, 20, 640 * 4), 640, 360, 640 * 4));
        Assert.False(BlackFrame.IsBlack(Image(640, 360, 40, 640 * 4), 640, 360, 640 * 4));
        // Satır sonunda dolgu olan (stride > genişlik) arabellek de doğru okunur.
        var padded = Image(640, 360, 0, 700 * 4);
        Assert.True(BlackFrame.IsBlack(padded, 640, 360, 700 * 4));
        padded[(16 * 700 + 16) * 4 + 1] = 200; // tek bir parlak örnek (yeşil)
        Assert.False(BlackFrame.IsBlack(padded, 640, 360, 700 * 4));
    }

    [Fact]
    public void BlackPictureIsReportedOnlyAfterFourSeconds()
    {
        var watch = new BlackPictureWatch();
        Assert.False(watch.Update(true, 10));
        Assert.False(watch.Update(true, 13.9));
        Assert.True(watch.Update(true, 14));
        // Görüntü gelince sayaç sıfırlanır.
        Assert.False(watch.Update(false, 14.1));
        Assert.False(watch.Update(true, 15));
        Assert.False(watch.Update(true, 18.5));
        Assert.True(watch.Update(true, 19));
    }

    [Fact]
    public void PipelineGetsTenFramesPerSecond()
    {
        Assert.True(CaptureCardRules.DueForPipeline(0, double.NegativeInfinity));
        Assert.False(CaptureCardRules.DueForPipeline(0.05, 0));
        Assert.True(CaptureCardRules.DueForPipeline(0.1, 0));
    }

    [Fact]
    public void PicksFullHdAtTheHighestRateAndPrefersUncompressed()
    {
        var formats = new[]
        {
            new CardVideoFormat(3840, 2160, 30, "NV12"),
            new CardVideoFormat(1920, 1080, 30, "NV12"),
            new CardVideoFormat(1920, 1080, 60, "MJPG"),
            new CardVideoFormat(1920, 1080, 59.94, "YUY2"),
            new CardVideoFormat(1280, 720, 60, "NV12"),
        };
        Assert.Equal(new CardVideoFormat(1920, 1080, 59.94, "YUY2"), CaptureCardRules.PickFormat(formats));
        // 1080p yoksa en akıcı, sonra 1080'e en yakın boy.
        Assert.Equal(new CardVideoFormat(1280, 720, 60, "NV12"),
            CaptureCardRules.PickFormat([new CardVideoFormat(3840, 2160, 30, "NV12"), new CardVideoFormat(1280, 720, 60, "NV12"), new CardVideoFormat(640, 480, 60, "YUY2")]));
        Assert.Null(CaptureCardRules.PickFormat([]));
    }

    [Fact]
    public void GameAreaIsLetterboxedInsideThePlayerWindow()
    {
        // Tam ekran 16:10 monitör: üstte ve altta bant.
        Assert.Equal(new ScreenArea(0, 60, 1920, 1080), CaptureCardRules.GameArea(new ScreenArea(0, 0, 1920, 1200)));
        // Geniş (ultrawide) ekran: yanlarda bant.
        Assert.Equal(new ScreenArea(520, 0, 2400, 1350), CaptureCardRules.GameArea(new ScreenArea(0, 0, 3440, 1350)));
        // İkinci ekranda pencere: başlangıç noktası korunur.
        Assert.Equal(new ScreenArea(-1600, 100, 1280, 720), CaptureCardRules.GameArea(new ScreenArea(-1600, 100, 1280, 720)));
    }

    [Fact]
    public void StatusMapsToStreamState()
    {
        Assert.Equal(SessionPhase.Streaming, CaptureCardRules.SessionState(CaptureCardStatus.Capturing("Elgato")).Phase);
        // Siyah görüntüde de akış sürer (okuma hattı boş ekran görür, eski satır kalkar).
        Assert.Equal(SessionPhase.Streaming, CaptureCardRules.SessionState(CaptureCardStatus.BlackPicture("Elgato")).Phase);
        Assert.Equal(SessionPhase.Connecting, CaptureCardRules.SessionState(CaptureCardStatus.NoCard).Phase);
        Assert.Equal(SessionPhase.Connecting, CaptureCardRules.SessionState(CaptureCardStatus.NeedsPermission).Phase);
        Assert.NotEqual(SessionPhase.Streaming, CaptureCardRules.SessionState(CaptureCardStatus.Stopped).Phase);
    }

    [Fact]
    public void CardChoiceIsSavedAsText()
    {
        var json = JsonSerializer.Serialize(new UserSettings { VideoSource = VideoSource.Card });
        Assert.Contains("\"VideoSource\":\"Card\"", json);
        Assert.Equal(VideoSource.Card, JsonSerializer.Deserialize<UserSettings>(json)!.VideoSource);
    }

    [Fact]
    public void StatusTextTellsWhatToDo()
    {
        var text = Localizer.ForLanguage("en");
        Assert.Equal("Reads the capture card", AppController.CardStatusTextFor(CaptureCardStatus.Stopped, text));
        Assert.Equal("Plug in your capture card", AppController.CardStatusTextFor(CaptureCardStatus.NoCard, text));
        Assert.Equal("Reading Elgato HD60 X", AppController.CardStatusTextFor(CaptureCardStatus.Capturing("Elgato HD60 X"), text));
        Assert.Contains("HDCP", AppController.CardStatusTextFor(CaptureCardStatus.BlackPicture("Elgato"), text));
        Assert.Contains("Privacy & security", AppController.CardStatusTextFor(CaptureCardStatus.NeedsPermission, text));
        // Türkçede "Capture Card" İngilizce kalır.
        Assert.Contains("Capture Card", AppController.CardStatusTextFor(CaptureCardStatus.NoCard, Localizer.ForLanguage("tr")));
    }
}

public class CaptureCardControllerTests
{
    private static void PairTv(MemoryStore store)
    {
        store.Save(StoreKeys.Tv, new LgTv("LG TV", "192.168.1.153"));
        store.Save(StoreKeys.TvKey, "tv-key");
    }

    [Fact]
    public void CardNeedsNoPs5ButNeedsAPlaceForTheSubtitles()
    {
        var controller = AppControllerTests.Make();
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Card, Output = SubtitleOutput.Tv };
        Assert.True(controller.UsesCaptureCard);
        Assert.False(controller.UsesGameWindow);
        // Kartla altyazı TV'ye gidebilir (geçişli kart); TV eşleşmeden başlatılamaz.
        Assert.True(controller.ShowsOnTv);
        Assert.False(controller.ShowsOnComputer);
        Assert.True(controller.NeedsTv);
        Assert.False(controller.CanStart);
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        Assert.False(controller.ShowsOnTv);
        Assert.True(controller.ShowsOnComputer);
        Assert.True(controller.CanStart);
    }

    /// <summary>PS5 yolunda altyazının yeri seçilmez; PS5'e dönülünce altyazı TV'ye gider.</summary>
    [Fact]
    public void BackToPs5SendsSubtitlesToTheTv()
    {
        var controller = AppControllerTests.Make();
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Card, Output = SubtitleOutput.Computer };
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Ps5 };
        Assert.Equal(SubtitleOutput.Tv, controller.Settings.Output);
        Assert.True(controller.ShowsOnTv);
    }

    [Fact]
    public void CardWithPairedTvCanStartOnTheTv()
    {
        var store = new MemoryStore();
        PairTv(store);
        var controller = AppControllerTests.Make(store: store);
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Card, Output = SubtitleOutput.Tv };
        Assert.True(controller.ShowsOnTv);
        Assert.True(controller.CanStart);
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Both };
        Assert.True(controller.ShowsOnTv);
        Assert.True(controller.ShowsOnComputer);
    }

    [Fact]
    public void GuideOnComputerGoesToTheTestWithoutPs5Steps()
    {
        var store = new MemoryStore();
        var settings = new MemorySettings();
        var controller = AppControllerTests.Make(new FakeServices(), store, settings);
        controller.UseCaptureCardSetup();
        Assert.True(controller.CardSetupActive);
        Assert.Equal(OnboardingStep.Welcome, controller.Step);
        controller.FinishCaptureCardSetup(toTv: false);
        Assert.False(controller.CardSetupActive);
        Assert.Equal(controller.ModelInstalled ? OnboardingStep.Test : OnboardingStep.Translation, controller.Step);
        Assert.Equal(SubtitleOutput.Computer, controller.Settings.Output);
        Assert.True(controller.CanStart);
        // Geri: PS5 adımlarına değil rehbere döner.
        controller.Step = OnboardingStep.Test;
        controller.Back();
        Assert.True(controller.CardSetupActive);
        Assert.Equal(OnboardingStep.Welcome, controller.Step);
        controller.CancelCaptureCardSetup();
        Assert.False(controller.CardSetupActive);

        // Kurulum bitince açılışta sihirbaz atlanır (PS5 eşleşmesi olmadan).
        controller.UseCaptureCardSetup();
        controller.FinishCaptureCardSetup(toTv: false);
        controller.Step = OnboardingStep.Done;
        var reopened = AppControllerTests.Make(new FakeServices(), store, settings);
        Assert.Equal(OnboardingStep.Done, reopened.Step);
        Assert.True(reopened.UsesCaptureCard);
    }

    [Fact]
    public void GuideOnTvAsksForTheTvOnlyWhenNoneIsPaired()
    {
        var controller = AppControllerTests.Make();
        controller.UseCaptureCardSetup();
        controller.FinishCaptureCardSetup(toTv: true);
        Assert.Equal(OnboardingStep.Tv, controller.Step);
        Assert.Equal(SubtitleOutput.Tv, controller.Settings.Output);
        controller.Back();
        Assert.True(controller.CardSetupActive);

        var store = new MemoryStore();
        PairTv(store);
        var paired = AppControllerTests.Make(store: store);
        paired.UseCaptureCardSetup();
        paired.FinishCaptureCardSetup(toTv: true);
        Assert.Equal(paired.ModelInstalled ? OnboardingStep.Test : OnboardingStep.Translation, paired.Step);
    }

    [Fact]
    public void ContinuingFromWelcomeTakesThePs5Path()
    {
        var controller = AppControllerTests.Make();
        controller.UseCaptureCardSetup();
        controller.FinishCaptureCardSetup(toTv: true);
        controller.Back();
        controller.CancelCaptureCardSetup();
        Assert.Equal(OnboardingStep.Welcome, controller.Step);
        controller.Advance();
        Assert.Equal(VideoSource.Ps5, controller.Settings.VideoSource);
        Assert.Equal(OnboardingStep.SecondAccount, controller.Step);
    }

    [Fact]
    public void BothIsKeptForTheCardAfterRestart()
    {
        var settings = new MemorySettings();
        settings.Save(new UserSettings { VideoSource = VideoSource.Card, Output = SubtitleOutput.Both });
        Assert.Equal(SubtitleOutput.Both, AppControllerTests.Make(settings: settings).Settings.Output);
        settings.Save(new UserSettings { VideoSource = VideoSource.Ps5, Output = SubtitleOutput.Both });
        Assert.Equal(SubtitleOutput.Tv, AppControllerTests.Make(settings: settings).Settings.Output);
    }

    [Fact]
    public void GuideFromSettingsOnlySavesTheChoice()
    {
        var controller = AppControllerTests.Make();
        controller.Step = OnboardingStep.Done;
        controller.FinishCaptureCardSetup(toTv: false);
        Assert.Equal(OnboardingStep.Done, controller.Step);
        Assert.True(controller.UsesCaptureCard);
        Assert.Equal(SubtitleOutput.Computer, controller.Settings.Output);
    }

    [Fact]
    public async Task StartsFromTheCardAndShowsTheGameOnThisComputer()
    {
        var services = new FakeServices();
        var store = new MemoryStore();
        var controller = AppControllerTests.Make(services, store);
        controller.PreferredCardId = "card-1";
        Assert.Equal("card-1", store.Load<string>(StoreKeys.CaptureCardId));
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Card, Output = SubtitleOutput.Computer };
        Assert.Equal("Reads the capture card", controller.Ps5StatusText);

        await controller.StartAsync();
        Assert.True(controller.IsRunning);
        Assert.Empty(services.Streams);
        var stream = Assert.Single(services.CardStreams);
        Assert.True(stream.Started);
        Assert.True(stream.ShowsPlayer);
        Assert.Equal("card-1", stream.PreferredId);
        Assert.True(controller.ShowsCardPlayer);

        stream.Emit(CaptureCardStatus.NoCard);
        Assert.Equal("Plug in your capture card", controller.Ps5StatusText);
        Assert.Equal(StatusTone.Warning, controller.Ps5Tone);
        stream.Emit(CaptureCardStatus.Capturing("Elgato HD60 X"), new ScreenArea(0, 0, 1920, 1080));
        Assert.Equal(SessionPhase.Streaming, controller.SessionState.Phase);
        Assert.Equal("Reading Elgato HD60 X", controller.Ps5StatusText);
        Assert.Equal(StatusTone.Good, controller.Ps5Tone);
        Assert.Equal(new ScreenArea(0, 0, 1920, 1080), controller.GameArea);
        stream.Emit(CaptureCardStatus.BlackPicture("Elgato HD60 X"), new ScreenArea(0, 0, 1920, 1080));
        Assert.Equal(StatusTone.Warning, controller.Ps5Tone);

        controller.ToggleCardFullScreen();
        Assert.Equal(1, stream.FullScreenToggles);

        // Oyun penceresini kapatmak çeviriyi durdurur.
        stream.ClosePlayer();
        Assert.False(controller.IsRunning);
        Assert.False(stream.Started);
        Assert.Null(controller.GameArea);
        Assert.Equal(CaptureCardStatus.Stopped, controller.CardStatus);
    }

    [Fact]
    public async Task PassthroughCardReadsOnlyAndSendsToTheTv()
    {
        var services = new FakeServices();
        var store = new MemoryStore();
        PairTv(store);
        var controller = AppControllerTests.Make(services, store);
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Card, Output = SubtitleOutput.Tv };
        await controller.StartAsync();
        var stream = Assert.Single(services.CardStreams);
        Assert.False(stream.ShowsPlayer);
        Assert.False(controller.ShowsCardPlayer);
        // Altyazı TV'ye gider: TV uygulaması açık tutulur.
        Assert.Single(services.Keepers);
    }

    [Fact]
    public async Task ChangingWhereSubtitlesGoRestartsTheCard()
    {
        var services = new FakeServices();
        var store = new MemoryStore();
        PairTv(store);
        var controller = AppControllerTests.Make(services, store);
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Card, Output = SubtitleOutput.Tv };
        await controller.StartAsync();
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        // Oyun artık bu bilgisayarda gösterilir: kart oyun penceresiyle yeniden açılır.
        Assert.Equal(2, services.CardStreams.Count);
        Assert.False(services.CardStreams[0].Started);
        Assert.True(services.CardStreams[1].Started);
        Assert.True(services.CardStreams[1].ShowsPlayer);
        Assert.True(controller.IsRunning);
    }

    [Fact]
    public async Task LateEventsFromAnOldCardSessionAreIgnored()
    {
        var services = new FakeServices();
        var controller = AppControllerTests.Make(services);
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Card, Output = SubtitleOutput.Computer };
        await controller.StartAsync();
        var old = services.CardStreams[0];
        controller.Stop();
        await controller.StartAsync();
        old.Emit(CaptureCardStatus.Capturing("Old"), new ScreenArea(0, 0, 10, 10));
        old.ClosePlayer();
        Assert.True(controller.IsRunning);
        Assert.Null(controller.GameArea);
        Assert.Equal(CaptureCardStatus.Stopped, controller.CardStatus);
    }
}
