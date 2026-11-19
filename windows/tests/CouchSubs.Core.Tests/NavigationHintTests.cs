// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>Nino: oyunun yol tarifi satırları altyazı değildir (Mac: NavigationHintTests).</summary>
public class NavigationHintTests
{
    [Theory]
    [InlineData("Turn Right 405 ft 432 ft")]
    [InlineData("Keep Left O ft 2 ft")]
    [InlineData("U-Turn Left 5 ft 24 ft")]
    [InlineData("Turn Left 366 ft—")]
    [InlineData("-turn Right 67 ft 82 ft")]
    [InlineData("Turn Right i 100 ft 103 ft")]
    [InlineData("Keep Right 3.9 km")]
    public void TurnByTurnLinesAreNotSubtitles(string hint) => Assert.True(Reading.IsNavigationHint(hint), hint);

    [Theory]
    [InlineData("Turn right at the lights, okay?")]
    [InlineData("Turn Right")]
    [InlineData("Keep left and you'll be fine, 20 ft or so")]
    [InlineData("Keep it down!")]
    [InlineData("I said turn left, 50 ft back there you idiot.")]
    public void SentencesAboutDirectionsStaySubtitles(string subtitle) => Assert.False(Reading.IsNavigationHint(subtitle), subtitle);

    [Fact]
    public void HintLinesAreRemovedFromTheReading()
    {
        var reading = new Reading([new TextLine("Turn Right 405 ft"), new TextLine("Where the hell are we going?")]);
        Assert.Equal(["Where the hell are we going?"], reading.WithoutNavigationHints().Lines.Select(line => line.Text));
    }

    [Fact]
    public void TurkishSystemLanguageDoesNotChangeTheRule()
    {
        // Türkçe Windows'ta "I" ile "i" eşleşmez; kural kültürden bağımsız çalışmalı.
        var previous = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo("tr-TR");
            Assert.True(Reading.IsNavigationHint("TURN RIGHT 405 ft"));
            Assert.True(Reading.IsNavigationHint("turn right 405 ft"));
            Assert.True(Reading.IsNavigationHint("U-TURN LEFT 5 ft"));
        }
        finally
        {
            CultureInfo.CurrentCulture = previous;
        }
    }
}
