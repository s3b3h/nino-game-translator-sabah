// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Gerçek GTA 6 karelerinin yazı tanıma satırları (macOS Vision ile bir kez okunup Fixtures/*.lines.txt dosyalarına
/// yazıldı: "sol üst sağ alt[TAB]metin", kareye göre 0–1). Windows'un yazı tanıması burada çalışmaz; satır mantığı bu
/// gerçek okumalarla sınanır.
/// </summary>
internal static class GameLines
{
    private static readonly string? Folder = Find();

    private static string? Find()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var path = Path.Combine(dir.FullName, "windows", "tests", "CouchSubs.Core.Tests", "Fixtures");
            if (Directory.Exists(path)) return path;
            path = Path.Combine(dir.FullName, "Fixtures");
            if (File.Exists(Path.Combine(path, "gta6-harita-buckme.lines.txt"))) return path;
        }
        return null;
    }

    public static Reading Load(string name)
    {
        Assert.NotNull(Folder);
        var lines = File.ReadAllLines(Path.Combine(Folder!, name + ".lines.txt")).Where(l => l.Contains('\t')).Select(l =>
        {
            var parts = l.Split('\t', 2);
            var n = parts[0].Split(' ').Select(v => double.Parse(v, CultureInfo.InvariantCulture)).ToArray();
            return new TextLine(parts[1], new TextBox(n[0], n[1], n[2], n[3]));
        });
        return new Reading(lines);
    }
}

/// <summary>Nino: harita kartı (Mac: MapCardParagraphTests, MapCardIconJunkTests).</summary>
public class MapCardTests
{
    [Fact]
    public void WholeCardIsRead()
    {
        var reading = GameLines.Load("gta6-harita-buckme");
        Assert.True(MapCard.IsMapScreen(reading));
        var card = MapCard.Find(reading);
        Assert.NotNull(card);
        Assert.Equal("DEPOSIT CASH INTO BUCKME", card.Title);
        Assert.Equal(2, card.Sentences.Count);
        Assert.EndsWith("nearby ATMs", card.Sentences[0]);
        Assert.StartsWith("Use the index", card.Sentences[0]);
        Assert.Contains("checking account at an ATM", card.Sentences[^1]);
        Assert.True(card.Box.Bottom > 0.58);
    }

    [Fact]
    public void IconAndDistanceDoNotBreakTheCard()
    {
        var reading = GameLines.Load("gta6-harita-balik");
        Assert.True(MapCard.IsMapScreen(reading));
        var card = MapCard.Find(reading);
        Assert.NotNull(card);
        Assert.Equal("CATCH A BIGGER FISH", card.Title);
        Assert.Equal(["Cal challenged you to catch a stoplight parrotfish larger than 0.9 kg."], card.Sentences);
    }

    [Fact]
    public void PhoneIsNotAMapScreen() => Assert.False(MapCard.IsMapScreen(GameLines.Load("gta6-telefon-brian-parlama")));

    [Fact]
    public void TranslationGoesUnderTheCard()
    {
        var card = MapCard.Find(GameLines.Load("gta6-harita-buckme"))!;
        var item = MapCardWatcher.Placement(card, ["BUCKME'YE NAKİT YATIR", "Yakındaki ATM'leri bulmak için dizini kullan", "Nakit yatır"], null);
        Assert.True(item.Card);
        Assert.True(item.Box.Top > card.Box.Bottom, "kartın altında");
        Assert.Equal(3, item.Translation.Split('\n').Length);
        Assert.True(item.Box.Left <= card.Box.Left);
    }

    [Fact]
    public void PlaceNamesAndTermsAreKept()
    {
        Assert.True(MapCardWatcher.IsPlaceName("RIDEOUT CUSTOMS"));
        Assert.True(MapCardWatcher.IsPlaceName("LADONNA'S SOUL FOOD", "A dive bar in town."));
        Assert.False(MapCardWatcher.IsPlaceName("JASON'S MAILBOX"));
        Assert.Equal("işaretli banknotların izini sür", MapCardWatcher.WithMapTerms("işaretli faturaların izini sür"));
        Assert.Equal("Depoya git: Jason'ın deposu", MapCardWatcher.WithMapTerms("Depoya git: Jason'ın kapalı tutulması"));
    }

    [Fact]
    public async Task WatcherShowsTheCardAndBlocksSubtitles()
    {
        var shown = new List<IReadOnlyList<ScreenTranslation.Item>>();
        var watcher = new MapCardWatcher(new LinesReader(Reading.Empty), new FakeTranslator()) { Changed = shown.Add };
        Assert.False(watcher.MapOpen);
        await watcher.Process(Frame.Blank(64, 36), GameLines.Load("gta6-harita-buckme"));
        await watcher.WhenShown();
        Assert.True(watcher.MapOpen);
        var item = Assert.Single(watcher.Items);
        Assert.True(item.Card);
        Assert.StartsWith("TR: DEPOSİT CASH INTO BUCKME", item.Translation);
        Assert.Contains("TR: Make a cash deposit", item.Translation);
        // Harita kapandı: kart kalkar.
        await watcher.Process(Frame.Blank(64, 36), Reading.Empty);
        Assert.Empty(watcher.Items);
        Assert.Empty(shown[^1]);
    }
}

/// <summary>Nino: telefondaki sohbetin okunması ve TV'ye giden öğeler.</summary>
public class PhoneWatcherTests
{
    private static PhonePanel.Panel? PanelOf(string name) => GameFrames.Load(name + ".jpg") is { } frame ? PhonePanel.Find(frame) : null;

    [Fact]
    public void DaylightPhoneWithPhotoIsAThreadWithTitle()
    {
        if (PanelOf("gta6-telefon-lucia-foto") is not { } panel) return;
        var reading = GameLines.Load("gta6-telefon-lucia-foto");
        Assert.True(PhoneThread.IsThread(reading, panel));
        Assert.Equal("Lucia", PhoneThread.TitleText(reading, panel));
    }

    [Fact]
    public void ChatWithGlareIsStillAThread()
    {
        if (PanelOf("gta6-telefon-brian-parlama") is not { } panel) return;
        var reading = GameLines.Load("gta6-telefon-brian-parlama");
        Assert.True(PhoneThread.IsThread(reading, panel));
        var messages = PhoneThread.Messages(reading, panel);
        Assert.DoesNotContain(messages, m => m.Text == "Brian");
        Assert.Contains(messages, m => m.Text.StartsWith("Remember, you get your hands", StringComparison.Ordinal));
    }

    [Fact]
    public void BlueMessagesGoRightOnTiltedPhone()
    {
        if (GameFrames.Load("gta6-telefon-egik-mavi.jpg") is not { } frame || PhonePanel.Find(frame) is not { } panel) return;
        var reading = GameLines.Load("gta6-telefon-egik-mavi");
        var messages = PhoneThread.Messages(reading, panel);
        var items = PhoneThread.SideBubbles(messages, [.. messages.Select(m => "TR " + m.Text)], panel,
            PhonePanel.LiftedSampler(frame, panel), (t, _, _) => (1, t.Length)).Where(i => !i.Backdrop).ToList();
        var left = items.Min(i => i.Box.Left);
        bool Right(string start) => items.First(i => i.Source.StartsWith(start, StringComparison.OrdinalIgnoreCase)).Box.Left > left + 0.02;
        Assert.True(Right("Shit went sideways"));
        Assert.True(Right("Will do"));
        Assert.False(Right("Ah crap"));
        Assert.False(Right("Remember"));
    }

    private static readonly PhonePanel.Panel Kenton = new(new TextBox(0.58, 0.197, 0.793, 0.854), 0.58, 0, 0.213);

    private static Reading KentonChat() => new([
        new TextLine("Kenton", new TextBox(0.66, 0.22, 0.70, 0.24)),
        new TextLine("Dropped off scuba to yuh boat", new TextBox(0.60, 0.372, 0.752, 0.394)),
        new TextLine("man. Happy hunting!", new TextBox(0.60, 0.398, 0.70, 0.42)),
        new TextLine("Yeah, I'm on it man.", new TextBox(0.667, 0.689, 0.766, 0.712)),
    ]);

    [Fact]
    public async Task ChatBecomesAPanelBesideThePhoneAfterTwoReads()
    {
        var shown = new List<IReadOnlyList<ScreenTranslation.Item>>();
        var translator = new FakeTranslator();
        var watcher = new PhoneWatcher(new LinesReader(Reading.Empty), translator) { Changed = shown.Add };
        var frame = Frame.Blank(960, 540);
        // İlk okuma yalnız not edilir (kaydırma sürerken yarım okunan satırlar çevrilmez).
        await watcher.Process(frame, Kenton, KentonChat(), 0);
        Assert.Empty(shown);
        await watcher.Process(frame, Kenton, KentonChat(), 0);
        var items = Assert.Single(shown);
        Assert.True(items[0].Backdrop);
        Assert.Equal("Kenton", items[0].Translation);
        Assert.Equal(["TR: Dropped off scuba to yuh boat man. Happy hunting!", "TR: Yeah, I'm on it man."],
                     items.Skip(1).Select(i => i.Translation));
        Assert.All(items.Skip(1), i => Assert.True(i.Side && i.Box.Right < Kenton.Box.Left));
        Assert.Contains("Yeah, I'm on it man.", watcher.RecentTexts);
        // Aynı okuma yeniden gelince yeniden çevrilmez.
        await watcher.Process(frame, Kenton, KentonChat(), 0);
        Assert.Single(shown);
        Assert.Equal(2, translator.Requested.Count);
        watcher.Reset();
        Assert.Empty(watcher.Items);
        Assert.Empty(watcher.RecentTexts);
    }

    [Fact]
    public async Task AppScreenUsesTheGlossary()
    {
        var shown = new List<IReadOnlyList<ScreenTranslation.Item>>();
        var translator = new FakeTranslator();
        var watcher = new PhoneWatcher(new LinesReader(Reading.Empty), translator) { Changed = shown.Add };
        var panel = new PhonePanel.Panel(new TextBox(0.59, 0.2, 0.79, 0.81), 0.59, 0, 0.2);
        var reading = new Reading([
            new TextLine("$500", new TextBox(0.70, 0.33, 0.77, 0.36)),
            new TextLine("◆ Checking Account", new TextBox(0.61, 0.38, 0.72, 0.40)),
            new TextLine("$4,900 to next goal", new TextBox(0.64, 0.65, 0.74, 0.67)),
        ]);
        await watcher.Process(Frame.Blank(960, 540), panel, reading, 0);
        await watcher.Process(Frame.Blank(960, 540), panel, reading, 0);
        Assert.Equal(["Vadesiz Hesap", "Sonraki hedefe $4.900"], Assert.Single(shown).Select(i => i.Translation));
        Assert.Empty(translator.Requested);
    }

    /// <summary>
    /// Nino (kullanıcı): GTA'da altyazı koyu sahnede beyaz yazıdır; telefondaki mesaj açık zeminde koyu yazıdır ve altyazı
    /// bölgesine girse de altyazı sayılmaz (Mac: DarkOnLightTests). Bölge, uygulamadaki gibi kırpılıp örneklenir.
    /// </summary>
    private static (List<TextLine> Lines, Func<double, double, Rgb?> Color)? SubtitleArea(string name)
    {
        if (GameFrames.Load(name + ".jpg") is not { } frame) return null;
        var region = new CropRegion(Top: 0.66, Bottom: 0.97, Left: 0.14, Right: 0.86);
        var color = PhonePanel.Sampler(RegionCropper.Crop(frame, region));
        // Satırlar kareye göre yazılı; bölgeye göre yerleşir.
        var lines = GameLines.Load(name).Lines.Where(l => l.Text.Count(char.IsLetter) >= 4).Select(l =>
        {
            var b = l.Box!.Value;
            return l with { Box = new TextBox((b.Left - 0.14) / 0.72, (b.Top - 0.66) / 0.31, (b.Right - 0.14) / 0.72, (b.Bottom - 0.66) / 0.31) };
        }).ToList();
        return (lines, color);
    }

    [Fact]
    public void WhiteSubtitleIsNotDarkOnLight()
    {
        if (SubtitleArea("gta6-altyazi-beyaz") is not { } area) return;
        var (lines, color) = area;
        var subtitle = lines.First(l => l.Text.Contains("gonna love it", StringComparison.Ordinal));
        Assert.False(PhoneThread.IsDarkOnLight(subtitle.Box!.Value, color), subtitle.Text);
        var phone = lines.Where(l => l.Text.Contains("finder", StringComparison.Ordinal) || l.Text.Contains("lockups", StringComparison.Ordinal)).ToList();
        Assert.NotEmpty(phone);
        foreach (var line in phone) Assert.True(PhoneThread.IsDarkOnLight(line.Box!.Value, color), line.Text);
    }

    [Fact]
    public void PhoneMessageIsDarkOnLight()
    {
        if (SubtitleArea("gta6-telefon-yakin-alt") is not { } area) return;
        var (lines, color) = area;
        var message = lines.Where(l => l.Text.Contains("plane", StringComparison.Ordinal) || l.Text.Contains("good to her", StringComparison.Ordinal)).ToList();
        Assert.NotEmpty(message);
        foreach (var line in message) Assert.True(PhoneThread.IsDarkOnLight(line.Box!.Value, color), line.Text);
    }

    [Fact]
    public void IconsAreStrippedFromTranslations()
    {
        Assert.Equal("Geliyorum", PhoneWatcher.WithoutIcons("Geliyorum 👍"));
        Assert.Equal("Tom & Jerry", PhoneWatcher.WithoutIcons("Tom &amp; Jerry"));
    }
}
