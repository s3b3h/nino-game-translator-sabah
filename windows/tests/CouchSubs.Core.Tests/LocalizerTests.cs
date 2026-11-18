// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// Metinler Mac uygulamasının Localizable.xcstrings dosyasından gelir; iki uygulama aynı çevirileri kullanır.
public class LocalizerTests
{
    [Fact]
    public void TurkishTextComesFromSharedCatalog()
    {
        var tr = Localizer.ForLanguage("tr");
        Assert.Equal("Çeviriyi başlat", tr["Start translating"]);
        Assert.Equal("Start translating", Localizer.ForLanguage("en")["Start translating"]);
    }

    [Fact]
    public void UnknownLanguageFallsBackToEnglish() =>
        Assert.Equal("Start translating", Localizer.ForLanguage("de")["Start translating"]);

    [Fact]
    public void MissingKeyShowsTheKey() =>
        Assert.Equal("No such text", Localizer.ForLanguage("tr")["No such text"]);

    [Fact]
    public void PositionalFormatArgumentsAreFilled()
    {
        var tr = Localizer.ForLanguage("tr");
        Assert.Equal("Adım 2 / 6", tr.Format("Step %lld of %lld", 2, 6));
        Assert.Contains("İngilizce", tr.Format("The %@–%@ language pack is not downloaded yet.", "İngilizce", "Türkçe"));
    }

    /// Nino: yalnız Windows'a ait metinler ayrı bir katalogdan gelir ve ortak katalogla birleşir.
    [Fact]
    public void WindowsOnlyTextIsTranslated()
    {
        const string key = "Plug the card into a USB 3 port on this computer. If you use a hub, try a port on the computer itself.";
        Assert.StartsWith("Capture Card'ı bu bilgisayardaki", Localizer.ForLanguage("tr")[key]);
        Assert.NotEqual(key, Localizer.ForLanguage("ar")[key]);
        Assert.Equal(key, Localizer.ForLanguage("en")[key]);
    }

    [Fact]
    public void EveryEntryHasTurkish()
    {
        var missing = Localizer.MissingTranslations("tr");
        Assert.True(missing.Count == 0, string.Join(", ", missing));
    }

    /// Nino: çeviri başlayınca robotun yanındaki balon (Mac ile aynı anahtar).
    [Fact]
    public void TranslationStartedBubbleIsTranslated()
    {
        const string key = "Nino: Subtitle Translation Started. Enjoy the Game!";
        Assert.Equal("Nino: Altyazı Çevirisi Başladı. Keyifli Oyunlar!", Localizer.ForLanguage("tr")[key]);
        Assert.Equal(key, Localizer.ForLanguage("en")[key]);
        Assert.NotEqual(key, Localizer.ForLanguage("ar")[key]);
    }
}
