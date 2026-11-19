// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>Alanda altyazının yanında menü, köşe göstergesi ve kumanda ipucu da okunur (Mac: SubtitleBlockTests).</summary>
public class SubtitleBlockTests
{
    private static readonly TextBox Area = new(0, 0.6, 1, 1);

    private static TextLine Line(string text, double left, double top, double right, double height = 0.07) =>
        new(text, new TextBox(left, top, right, top + height));

    [Fact]
    public void MenuAndCornerTextAreNotSubtitles()
    {
        string[] items = ["MAP", "HELP", "PROGRESS", "PLAYER", "STORY", "ONLINE", "SOCIAL CLUB", "SETTINGS"];
        var menu = items.Select((item, i) => Line(item, 0.05, 0.05 + (i * 0.1), 0.05 + (item.Length * 0.015)));
        var reading = new Reading([.. menu, Line("PHOTO MODE", 0.85, 0.9, 0.97)]);
        Assert.Empty(reading.SubtitleBlock(Area).Lines);
    }

    /// <summary>Nino: RDR2'nin açılıştaki yasal uyarısı alanın iki yanından taşar; çevrilmez. Tek yana taşan satır kalır.</summary>
    [Fact]
    public void LineClippedOnBothSidesIsNotSubtitle()
    {
        var clipped = new Reading([Line("rema pay or play, or copy protector crediverton is promoted a volutes coun", 0.0, 0.8, 1.0)]);
        Assert.Empty(clipped.WithoutClippedLines().SubtitleBlock(Area).Lines);
        var wide = new Reading([Line("Arthur, we need to get to the boat before the storm reaches the valley!", 0.06, 0.8, 0.94)]);
        Assert.Single(wide.WithoutClippedLines().Lines);
        var oneSide = new Reading([Line("before the storm reaches the valley", 0.0, 0.8, 0.7)]);
        Assert.Single(oneSide.WithoutClippedLines().Lines);
    }

    [Fact]
    public void CenteredSubtitleIsKeptWithoutCornerGauge()
    {
        var reading = new Reading([
            Line("We'll lose these tracks if we don't hurry.", 0.25, 0.7, 0.75),
            Line("9", 0.02, 0.7, 0.04),
            Line("PHOTO MODE", 0.85, 0.9, 0.97),
        ]);
        var block = reading.SubtitleBlock(Area);
        Assert.Equal("We'll lose these tracks if we don't hurry.", block.Text);
        Assert.Equal(new TextBox(0.25, 0.7, 0.75, 0.77), block.Box!.Value with { Bottom = Math.Round(block.Box!.Value.Bottom, 2) });
    }

    [Fact]
    public void TwoLineSubtitleStaysTogether()
    {
        var reading = new Reading([
            Line("Mac and John... they were both shot.", 0.3, 0.6, 0.7),
            Line("We need to move.", 0.4, 0.68, 0.6),
        ]);
        Assert.Equal("Mac and John... they were both shot.\nWe need to move.", reading.SubtitleBlock(Area).Text);
    }

    [Fact]
    public void LeftAlignedSentenceIsStillRead()
    {
        var reading = new Reading([Line("Mafioso: We're worried about this one.", 0.05, 0.8, 0.5)]);
        Assert.Equal("Mafioso: We're worried about this one.", reading.SubtitleBlock(Area).Text);
    }

    [Fact]
    public void LinesWithoutPlaceAreUntouched()
    {
        var reading = Reading.FromText("MAP\nHELP");
        Assert.Same(reading, reading.SubtitleBlock(Area));
    }

    [Theory]
    [InlineData("PHOTO MODE L1 + R1", true)]
    [InlineData("PHOTO MODE [L1] + [R3]", true)]
    [InlineData("Hand me the L1.", false)]
    public void ButtonAtTheEndIsAPrompt(string line, bool prompt) => Assert.Equal(prompt, ButtonPrompts.IsPrompt(line));

    [Theory]
    [InlineData("9? We'll lose these tracks.", "We'll lose these tracks.")]
    [InlineData("100. Mac and John...", "Mac and John...")]
    [InlineData("23m CESARE: It's here! Shoot him!", "CESARE: It's here! Shoot him!")]
    [InlineData("100 men came", "100 men came")]
    public void GaugeNumberStuckToLineIsDropped(string line, string clean) => Assert.Equal(clean, OcrNoise.Clean(line));

    // --- Dev yazılar (tabela, reklam panosu) ---

    private static readonly TextBox LowerHalf = new(0.06, 0.56, 0.98, 1);

    [Fact]
    public void NormalSubtitleLinesAreKept()
    {
        // Alanın %9'u × alan yüksekliği 0.44 ≈ karenin %4'ü: sıradan altyazı satırı.
        var reading = new Reading([
            new TextLine("I told you not to come here.", new TextBox(0.3, 0.60, 0.7, 0.69)),
            new TextLine("You never listen.", new TextBox(0.38, 0.70, 0.62, 0.79)),
        ]);
        Assert.Equal(reading.Lines, reading.WithoutOversizedLines(LowerHalf).Lines);
        Assert.False(reading.IsOversizedBlock(LowerHalf));
    }

    [Fact]
    public void GiantSignLineIsDroppedButSubtitleStays()
    {
        // Tabela satırı alanın %30'u ≈ karenin %13'ü; altyazı yanında kalır.
        var sign = new TextLine("Welcome to Leonida", new TextBox(0.1, 0.05, 0.9, 0.35));
        var subtitle = new TextLine("Where are we going?", new TextBox(0.35, 0.80, 0.65, 0.88));
        var reading = new Reading([sign, subtitle]).WithoutOversizedLines(LowerHalf);
        Assert.Equal([subtitle], reading.Lines);
    }

    [Fact]
    public void LineHeightIsMeasuredAgainstTheWholeFrame()
    {
        // Aynı satır dar bir alanda alanın yarısını kaplar ama karede %5'tir: atılmaz.
        var narrow = new TextBox(0.2, 0.85, 0.8, 0.95);
        var line = new TextLine("Stay close to me.", new TextBox(0.2, 0.2, 0.8, 0.7));
        Assert.Equal([line], new Reading([line]).WithoutOversizedLines(narrow).Lines);
        // Aynı oran bütün karede okunursa karenin yarısıdır: atılır.
        var full = new TextBox(0, 0, 1, 1);
        Assert.Empty(new Reading([line]).WithoutOversizedLines(full).Lines);
    }

    [Fact]
    public void LinesWithoutBoxesAreNeverDropped()
    {
        var reading = new Reading([new TextLine("No position known.")]);
        Assert.Equal(reading.Lines, reading.WithoutOversizedLines(LowerHalf).Lines);
        Assert.False(reading.IsOversizedBlock(LowerHalf));
    }

    [Fact]
    public void TallBlockIsNotASubtitle()
    {
        // Normal boyda ama üst üste yedi satır (afiş, not): blok karenin %26'sından yüksek ve 5 satırdan çok.
        var lines = Enumerable.Range(0, 7).Select(index =>
        {
            var top = 0.05 + (index * 0.12);
            return new TextLine($"Line number {index} of a poster.", new TextBox(0.3, top, 0.7, top + 0.09));
        }).ToList();
        Assert.True(new Reading(lines).IsOversizedBlock(LowerHalf));
        // Üç satırlık uzun altyazı kalır.
        Assert.False(new Reading(lines.Take(3)).IsOversizedBlock(LowerHalf));
    }

    [Fact]
    public void FewLinesCoveringTooMuchHeightAreNotASubtitle()
    {
        // İki satır ama aralarında büyük boşluk: kutu karenin %30'u.
        var reading = new Reading([
            new TextLine("Top of a billboard", new TextBox(0.3, 0.05, 0.7, 0.15)),
            new TextLine("bottom of a billboard", new TextBox(0.3, 0.65, 0.7, 0.75)),
        ]);
        Assert.True(reading.IsOversizedBlock(LowerHalf));
    }

    [Fact]
    public void TallSentenceIsKeptBecauseItMayBeASubtitleMergedWithJunk()
    {
        // Gerçek olay (V3.4): altyazı yanındaki göstergeyle aynı sıraya düşüp karenin %9'u ölçüldü ve atıldı.
        var merged = new TextLine("What happened? 00060000", new TextBox(0.2, 0.60, 0.8, 0.80));
        Assert.Equal([merged], new Reading([merged]).WithoutOversizedLines(LowerHalf).Lines);
        // Aynı yükseklikte etiket gibi satır (en çok 4 sözcük, noktalama yok) tabeladır.
        var sign = new TextLine("Boat Charters", new TextBox(0.2, 0.60, 0.8, 0.80));
        Assert.Empty(new Reading([sign]).WithoutOversizedLines(LowerHalf).Lines);
        Assert.True(Reading.IsLabelLike("OHM BOY"));
        Assert.True(Reading.IsLabelLike("BOAT CHARTERS TO LON"));
        Assert.False(Reading.IsLabelLike("We made it!"));
        Assert.False(Reading.IsLabelLike("You made it through half a scuba tour"));
    }
}
