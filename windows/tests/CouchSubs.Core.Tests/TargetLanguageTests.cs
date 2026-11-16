// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.Core.Dubbing;
using Xunit;

namespace CouchSubs.Core.Tests;

/// <summary>Nino: çeviri dili Türkçe (varsayılan) ya da Arapça; Arapça satır sağdan sola gösterilir.</summary>
public class TargetLanguageTests
{
    [Fact]
    public void FirstLaunchFollowsTheInterfaceLanguage()
    {
        Assert.Equal("ar", TargetLanguage.Preferred("ar"));
        Assert.Equal("tr", TargetLanguage.Preferred("tr"));
        Assert.Equal("tr", TargetLanguage.Preferred("en"));
        Assert.Equal("tr", TargetLanguage.Preferred(""));
    }

    [Fact]
    public void ArabicTextIsAlreadyInTheArabicTarget()
    {
        Assert.True(TargetLanguage.IsAlready("الإعدادات", "ar"));
        Assert.False(TargetLanguage.IsAlready("Settings", "ar"));
        Assert.False(TargetLanguage.IsAlready("الإعدادات", "tr"));
        Assert.True(TargetLanguage.IsTurkish("tr"));
        Assert.False(TargetLanguage.IsTurkish("ar"));
        Assert.Equal("Arabic", TargetLanguage.EnglishName("ar"));
        Assert.Equal("Turkish", TargetLanguage.EnglishName("tr"));
    }

    [Fact]
    public void ArabicDisplayTextStartsEveryParagraphRightToLeft()
    {
        Assert.Equal("‏ATREUS: أين أبي؟\n‏آرثر، انتظر", TargetLanguage.DisplayText("ATREUS: أين أبي؟\nآرثر، انتظر"));
        Assert.Equal("Bu iş bitmedi.", TargetLanguage.DisplayText("Bu iş bitmedi."));
        Assert.Equal("‏مرحبا", TargetLanguage.DisplayText(TargetLanguage.DisplayText("مرحبا")));
    }

    private sealed class Echo : ITextTranslator
    {
        public List<string> Calls { get; } = [];
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default)
        {
            Calls.Add(text);
            return Task.FromResult("[" + text + "]");
        }
    }

    [Fact]
    public async Task ArabicMenusAreNotSentToTheTranslator()
    {
        var inner = new Echo();
        var arabic = new TargetScriptGuard(inner, "ar");
        Assert.Equal("الألعاب", await arabic.TranslateAsync("الألعاب"));
        Assert.Equal("[Stay close.]", await arabic.TranslateAsync("Stay close."));
        var turkish = new TargetScriptGuard(inner, "tr");
        Assert.Equal("[الألعاب]", await turkish.TranslateAsync("الألعاب"));
        Assert.Equal(["Stay close.", "الألعاب"], inner.Calls);
    }

    [Fact]
    public void ArabicInterfaceUsesTheArabicCatalog()
    {
        var arabic = Localizer.ForLanguage("ar-SA");
        Assert.Equal("ar", arabic.Language);
        Assert.True(arabic.IsRightToLeft);
        Assert.Equal("الإعدادات", arabic["Settings"]);
        Assert.Equal("لغة الترجمة", arabic["Translation language"]);
        Assert.False(Localizer.ForLanguage("tr-TR").IsRightToLeft);
        Assert.Equal("en", Localizer.ForLanguage("de").Language);
    }
}
