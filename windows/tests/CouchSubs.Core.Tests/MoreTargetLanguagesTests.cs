// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using Xunit;

namespace CouchSubs.Core.Tests;

/// <summary>Nino: GTA 6'nın altyazı listesinde olmayan diller (Hintçe, Endonezce, Tayca…); Türkçe hep ilk sırada.</summary>
public class MoreTargetLanguagesTests
{
    [Fact]
    public void TurkishFirstAndElevenLanguages()
    {
        Assert.Equal("tr", TargetLanguage.Choices[0].Code);
        Assert.Equal(11, TargetLanguage.Choices.Count);
        Assert.True(TargetLanguage.IsSupported("hi"));
        Assert.False(TargetLanguage.IsSupported("fi"));
        Assert.Equal("Bahasa Indonesia", TargetLanguage.NativeName("id"));
        Assert.Equal("Filipino", TargetLanguage.EnglishName("tl"));
    }

    [Fact]
    public void FirstLaunchPicksAListedWindowsLanguage()
    {
        Assert.Equal("vi", TargetLanguage.Preferred("vi"));
        Assert.Equal("tl", TargetLanguage.Preferred("fil"));
        Assert.Equal("tr", TargetLanguage.Preferred("fi"));
    }

    [Fact]
    public void OwnScriptIsAlreadyInTheTarget()
    {
        Assert.True(TargetLanguage.IsAlready("ตั้งค่า", "th"));
        Assert.True(TargetLanguage.IsAlready("सेटिंग्स", "hi"));
        Assert.True(TargetLanguage.IsAlready("সেটিংস", "bn"));
        Assert.True(TargetLanguage.IsAlready("ترتیبات", "ur"));
        Assert.False(TargetLanguage.IsAlready("Where is the camp?", "th"));
        Assert.True(TargetLanguage.IsRightToLeft("ur"));
        Assert.False(TargetLanguage.IsRightToLeft("hi"));
    }

    [Fact]
    public void DeepLOnlyForItsLanguages()
    {
        Assert.True(TargetLanguage.DeepLSupports("nl"));
        Assert.False(TargetLanguage.DeepLSupports("bn"));
    }
}
