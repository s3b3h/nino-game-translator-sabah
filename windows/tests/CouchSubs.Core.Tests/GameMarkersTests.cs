// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>Nino: GTA 6 ekrandaki kendine özgü yazılarından tanınır (Mac/iPhone: GameMarkersTests).</summary>
public class GameMarkersTests
{
    private static TextLine Line(string text, double top = 0.1) => new(text, new TextBox(0.4, top, 0.6, top + 0.03));

    [Fact]
    public void MapScreenIsGta6() => Assert.Equal("GTA 6", GameMarkers.Game(GameLines.Load("gta6-harita-buckme")));

    [Fact]
    public void PauseMenuTabsAndPhoneAreGta6()
    {
        Assert.Equal("GTA 6", GameMarkers.Game(new Reading([Line("JASON & LUCIA"), Line("MAP"), Line("BRIEF"), Line("PROGRESS")])));
        Assert.Equal("GTA 6", GameMarkers.Game(new Reading([Line("MAP"), Line("BRIEF"), Line("PROGRESS")])));
        Assert.Equal("GTA 6", GameMarkers.Game(new Reading([Line("Reminders"), Line("WhatUp", 0.8)])));
    }

    [Fact]
    public void OtherScreensAreNotRecognised()
    {
        Assert.Null(GameMarkers.Game(new Reading([Line("Options"), Line("Map"), Line("Progress"), Line("Quit Game")])));
        Assert.Null(GameMarkers.Game(new Reading([Line("Jason, wait for me!", 0.85)])));
        Assert.Null(GameMarkers.Game(GameLines.Load("gta6-altyazi-beyaz")));
        Assert.Null(GameMarkers.Game(GameLines.Load("gta6-telefon-brian-parlama")));
    }

    [Fact]
    public void CatalogShowsTheShortNameAndStillMatchesTheLongOne()
    {
        Assert.Equal(GameName.Key("GTA 6"), GameName.Key("Grand Theft Auto VI"));
        Assert.Contains("GTA 6", GameCatalog.Suggestions("grand theft", [], null));
        Assert.Equal("GTA 6", GameCatalog.Suggestions("", [], null)[0]);
    }
}
