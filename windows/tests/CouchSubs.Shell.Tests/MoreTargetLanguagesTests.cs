// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.Shell.Tests;

/// <summary>Nino: ücretsiz modeli olmayan dil (Tayca) kurulumu takmaz; DeepL desteklemediği dilde açılmaz.</summary>
public class MoreTargetLanguagesTests
{
    [Fact]
    public void LanguageWithoutFreeModelDoesNotBlockSetup()
    {
        var services = new FakeServices();
        services.Translation.Installed = false;
        var controller = AppControllerTests.Make(services);
        controller.Settings = controller.Settings with { TargetLanguage = "th" };
        Assert.False(controller.HasFreeModel);
        Assert.True(controller.ModelInstalled);
        controller.Step = OnboardingStep.Translation;
        Assert.True(controller.CanAdvance);
        Assert.Equal(TranslatorStatus.Unsupported, controller.TranslatorStatus);
    }

    [Fact]
    public async Task DeepLIsNotUsedForHindi()
    {
        var services = new FakeServices();
        var (controller, _, _) = AppControllerRunTests.Ready(services);
        await controller.SetDeepLKeyAsync("key:fx");
        controller.Settings = controller.Settings with { TargetLanguage = "id" };
        Assert.True(controller.OnlineTranslationActive);
        controller.Settings = controller.Settings with { TargetLanguage = "hi" };
        Assert.False(controller.OnlineTranslationActive);
        controller.Dispose();
    }
}

/// <summary>Nino: OBS projektörü seçilince yakalama kartı bırakılır (yoksa kart önce geldiği için OBS hiç okunmazdı).</summary>
public class PictureSourceTests
{
    [Fact]
    public void ChoosingObsProjectorDropsTheCaptureCard()
    {
        var controller = AppControllerTests.Make();
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Card };
        Assert.True(controller.UsesCaptureCard);
        controller.Settings = controller.Settings with { FrameSource = FrameSource.CaptureWindow, Output = SubtitleOutput.Computer };
        Assert.False(controller.UsesCaptureCard);
        Assert.Equal(FrameSource.CaptureWindow, controller.Settings.FrameSource);
        Assert.Equal(SubtitleOutput.Computer, controller.Settings.Output);
        controller.Settings = controller.Settings with { VideoSource = VideoSource.Card };
        Assert.Equal(FrameSource.Ps5, controller.Settings.FrameSource);
    }
}
