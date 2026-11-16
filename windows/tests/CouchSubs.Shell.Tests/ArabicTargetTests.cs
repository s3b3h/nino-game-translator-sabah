// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.Shell.Tests;

/// <summary>Nino: çeviri dili Arapça. Çevrimiçi motorlar Arapçaya çevirir; dublaj ve paketler yalnız Türkçede.</summary>
public class ArabicTargetTests
{
    [Fact]
    public void OldSettingsOpenInTurkish() => Assert.Equal("tr", new UserSettings().TargetLanguage);

    [Fact]
    public async Task OnlineEnginesGetTheArabicTarget()
    {
        var services = new FakeServices();
        services.Translation.Installed = false;
        var (controller, _, _) = AppControllerRunTests.Ready(services);
        await controller.SetDeepLKeyAsync("key:fx");
        controller.Settings = controller.Settings with { TargetLanguage = "ar" };
        Assert.True(controller.OnlineTranslationActive);

        await controller.StartAsync();
        Assert.Equal(["ar"], services.OnlineTargets);
        controller.Dispose();
    }

    [Fact]
    public void DubbingIsOnlyForTurkish()
    {
        var controller = AppControllerTests.Make();
        controller.Settings = controller.Settings with { Dubbing = controller.Settings.Dubbing with { Enabled = true } };
        Assert.True(controller.DubbingActive);
        controller.Settings = controller.Settings with { TargetLanguage = "ar" };
        Assert.False(controller.DubbingActive);
        controller.Dispose();
    }
}
