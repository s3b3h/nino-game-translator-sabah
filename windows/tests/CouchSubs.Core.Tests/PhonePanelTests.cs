// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Gerçek GTA 6 kareleri (Mac'in deneme verisi: core/Tests/CouchSubsCoreTests/Fixtures). .NET'te JPEG çözücü yok;
/// macOS'ta kare <c>sips</c> ile BMP'ye çevrilip okunur. Başka sistemde (sips yoksa) null döner, sınama atlanır.
/// </summary>
internal static class GameFrames
{
    private static readonly string? Folder = FindFolder();
    private static readonly string Cache = Path.Combine(Path.GetTempPath(), "nino-fixtures");

    private static string? FindFolder()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var path = Path.Combine(dir.FullName, "core", "Tests", "CouchSubsCoreTests", "Fixtures");
            if (Directory.Exists(path)) return path;
        }
        return null;
    }

    public static Frame? Load(string name)
    {
        if (Folder is null || !OperatingSystem.IsMacOS()) return null;
        var source = Path.Combine(Folder, name);
        if (!File.Exists(source)) return null;
        Directory.CreateDirectory(Cache);
        var bmp = Path.Combine(Cache, Path.ChangeExtension(name, ".bmp"));
        if (!File.Exists(bmp))
        {
            try
            {
                using var process = Process.Start(new ProcessStartInfo("sips", ["-s", "format", "bmp", source, "--out", bmp])
                {
                    RedirectStandardOutput = true, RedirectStandardError = true,
                });
                process?.WaitForExit(20_000);
            }
            catch { return null; }
            if (!File.Exists(bmp)) return null;
        }
        return Bmp(File.ReadAllBytes(bmp));
    }

    /// <summary>24/32 bit sıkıştırmasız BMP → BGRA kare.</summary>
    private static Frame Bmp(byte[] data)
    {
        var offset = BitConverter.ToInt32(data, 10);
        var width = BitConverter.ToInt32(data, 18);
        var rawHeight = BitConverter.ToInt32(data, 22);
        var bits = BitConverter.ToInt16(data, 28);
        var height = Math.Abs(rawHeight);
        var bytes = bits / 8;
        var stride = ((width * bytes) + 3) & ~3;
        var frame = Frame.Blank(width, height);
        for (var y = 0; y < height; y++)
        {
            var sourceRow = rawHeight < 0 ? y : height - 1 - y;
            for (var x = 0; x < width; x++)
            {
                var i = offset + (sourceRow * stride) + (x * bytes);
                var o = (y * frame.Stride) + (x * 4);
                frame.Pixels[o] = data[i];
                frame.Pixels[o + 1] = data[i + 1];
                frame.Pixels[o + 2] = data[i + 2];
                frame.Pixels[o + 3] = 255;
            }
        }
        return frame;
    }
}

/// <summary>Nino: oyundaki telefonun ekranı (Mac: PhonePanelTests.swift ile aynı beklentiler).</summary>
public class PhonePanelTests
{
    /// 240×135 haritada telefonun ekranı: x 139–190, y 27–115 (gerçek karelerdeki yer).
    private static bool Phone(int x, int y) => x is >= 139 and <= 190 && y is >= 27 and <= 115;

    /// Beyaz olmayan her nokta koyu (karanlık sahne).
    private static TextBox? Find(Func<int, int, bool> isWhite) =>
        PhonePanel.Find(240, 135, isWhite, (x, y) => !isWhite(x, y))?.Box;

    private static PhonePanel.Panel Panel(double left, double top, double right, double bottom) =>
        new(new TextBox(left, top, right, bottom), left, 0, right - left);

    private static void Near(double expected, double actual, double accuracy) =>
        Assert.True(Math.Abs(expected - actual) <= accuracy, $"beklenen {expected:0.####}, bulunan {actual:0.####}");

    [Fact]
    public void LeaningPanelIsFound()
    {
        var found = PhonePanel.Find(240, 135, (x, y) =>
        {
            if (y is < 24 or > 105) return false;
            var left = 99 - (int)Math.Round((y - 24) * 0.16, MidpointRounding.AwayFromZero);
            return x >= left && x <= left + 45;
        }, (_, _) => true);
        Assert.NotNull(found);
        var panel = found.Value;
        Near(-0.16, panel.Lean * 240 / 135, 0.03);
        Near(24.0 / 135, panel.Box.Top, 0.01);
        Near(106.0 / 135, panel.Box.Bottom, 0.01);
        Near((99 + 23) / 240.0, panel.Center(panel.Box.Top), 0.012);
        Near((86 + 23) / 240.0, panel.Center(panel.Box.Bottom), 0.012);
    }

    [Fact]
    public void FindsWhitePortraitPanel()
    {
        var box = Find(Phone);
        Assert.NotNull(box);
        Near(139.0 / 240, box.Value.Left, 0.01);
        Near(191.0 / 240, box.Value.Right, 0.01);
        Near(27.0 / 135, box.Value.Top, 0.01);
        Near(116.0 / 135, box.Value.Bottom, 0.01);
    }

    [Fact]
    public void PanelWithPhotoAndBubblesIsStillFound() =>
        Assert.NotNull(Find((x, y) =>
        {
            if (!Phone(x, y)) return false;
            if (y is >= 40 and <= 75 && x is >= 144 and <= 185) return false;
            if (y is >= 95 and <= 108 && x is >= 160 and <= 186) return false;
            return true;
        }));

    [Fact]
    public void NotPhones()
    {
        // Çerçevesi koyu olmayan beyaz dikdörtgen, kenardaki duvar, üst kenara dayanan kapı, karanlık sahne, gökyüzü,
        // yatay kutu ve kenarları oynayan leke telefon değildir.
        Assert.Null(PhonePanel.Find(240, 135, Phone, (_, _) => false));
        Assert.Null(Find((x, y) => x is >= 12 and <= 65 && y is >= 7 and <= 88));
        Assert.Null(Find((x, y) => x is >= 100 and <= 150 && y is >= 0 and <= 68));
        Assert.Null(Find((_, _) => false));
        Assert.Null(Find((_, y) => y < 70));
        Assert.Null(Find((x, y) => x is >= 150 and <= 220 && y is >= 110 and <= 134));
        Assert.Null(Find((x, y) => y is >= 20 and <= 120 && x >= 100 + ((y * 7) % 23) && x <= 150 + ((y * 11) % 29)));
    }

    private static TextLine Line(string text, double left, double top, double right, double bottom) =>
        new(text, new TextBox(left, top, right, bottom));

    [Fact]
    public void ThreadMessagesAreGroupedAndLabelsSkipped()
    {
        var reading = new Reading([
            Line("Kenton", 0.66, 0.22, 0.70, 0.24),
            Line("Nuestra Señora del Ocio", 0.63, 0.295, 0.755, 0.315),
            Line("Dropped off scuba to yuh boat", 0.60, 0.372, 0.752, 0.394),
            Line("man. Happy hunting!", 0.60, 0.398, 0.70, 0.42),
            Line("New message", 0.648, 0.503, 0.718, 0.522),
            Line("Still can't believe u found them", 0.60, 0.558, 0.753, 0.58),
            Line("doubloons. U got that luck boy.", 0.60, 0.582, 0.754, 0.604),
            Line("Need u out there on these", 0.60, 0.607, 0.731, 0.629),
            Line("wrecks man.", 0.60, 0.632, 0.662, 0.652),
            Line("Yeah, I'm on it man.", 0.667, 0.689, 0.766, 0.712),
        ]);
        Assert.Equal([
            "Dropped off scuba to yuh boat man. Happy hunting!",
            "Still can't believe u found them doubloons. U got that luck boy. Need u out there on these wrecks man.",
            "Yeah, I'm on it man.",
        ], PhoneThread.Messages(reading, Panel(0.58, 0.197, 0.793, 0.854)).Select(m => m.Text));
    }

    [Fact]
    public void ThreadHasCenteredNameOnTopButListDoesNot()
    {
        var thread = new Reading([Line("Kenton", 0.653, 0.233, 0.690, 0.248), Line("Hey Jason! Was good meeting u", 0.595, 0.351, 0.750, 0.377)]);
        Assert.True(PhoneThread.IsThread(thread, Panel(0.575, 0.215, 0.783, 0.859)));
        var list = new Reading([
            Line("Suggested", 0.608, 0.230, 0.661, 0.249),
            Line("Donnie", 0.635, 0.272, 0.669, 0.285), Line("Go get em", 0.635, 0.297, 0.685, 0.313),
            Line("Chuck's Gun Shop", 0.634, 0.347, 0.725, 0.367), Line("Hey Jason. You good? I saw", 0.634, 0.371, 0.772, 0.391),
        ]);
        Assert.False(PhoneThread.IsThread(list, Panel(0.583, 0.207, 0.792, 0.852)));
        // Başlığı virgüllü yer adı olan sohbet ("Fleeca, Laguna Lane") de sohbettir.
        var place = new Reading([Line("Fleeca, Laguna Lane", 0.64, 0.21, 0.74, 0.23), Line("Hello Mr. Duval. Please see the", 0.61, 0.55, 0.76, 0.57)]);
        Assert.True(PhoneThread.IsThread(place, Panel(0.59, 0.2, 0.79, 0.81)));
        Assert.Equal("Fleeca, Laguna Lane", PhoneThread.TitleText(place, Panel(0.59, 0.2, 0.79, 0.81)));
    }

    [Fact]
    public void AttachmentLabelsAreNotMessages()
    {
        var reading = new Reading([
            Line("Kenton", 0.653, 0.233, 0.690, 0.248),
            Line("Messages encrypted", 0.620, 0.296, 0.734, 0.322),
            Line("Map Pin Expired", 0.624, 0.478, 0.707, 0.496),
            Line("Here r the spots man. These", 0.595, 0.557, 0.736, 0.576),
            Line("wrecks should be a good place", 0.595, 0.581, 0.747, 0.602),
            Line("Nuestra Señora de la", 0.626, 0.646, 0.734, 0.665),
            Line("Ética Laxa", 0.625, 0.668, 0.681, 0.694),
        ]);
        Assert.Equal(["Here r the spots man. These wrecks should be a good place"],
                     PhoneThread.Messages(reading, Panel(0.575, 0.215, 0.783, 0.859)).Select(m => m.Text));
    }

    [Fact]
    public void ColumnGoesToTheRoomierSideAndBoxesDoNotOverlap()
    {
        var right = Panel(0.58, 0.197, 0.793, 0.854);
        Assert.True(PhoneThread.Column(right).Right < right.Box.Left);
        var middle = PhoneThread.Column(Panel(0.39, 0.2, 0.61, 0.85));
        Assert.True(middle.Left > 0.61);
        Assert.True(middle.Right <= 0.98);
        var messages = new[]
        {
            new PhoneThread.Message("a", new TextBox(0.6, 0.40, 0.7, 0.42), 0.022),
            new PhoneThread.Message("b", new TextBox(0.6, 0.43, 0.7, 0.45), 0.022),
        };
        var boxes = PhoneThread.Boxes(messages, [3, 1], [0.02, 0.02], (0.2, 0.5));
        Assert.True(boxes[1].Top >= boxes[0].Bottom);
    }

    [Fact]
    public void GlossaryAndPhoneWords()
    {
        Assert.Equal("Vadesiz Hesap", PhoneThread.Glossary("Checking Account"));
        Assert.Equal("Aile Birikimi", PhoneThread.Glossary("Family Savings"));
        Assert.Equal("Sonraki hedefe $4.900", PhoneThread.Glossary("$4,900 to next goal"));
        Assert.Null(PhoneThread.Glossary("Are you high right now?"));
        Assert.Equal("Ryde Çağır ($82)", PhoneThread.Glossary("Book Ryde ($82)"));
        Assert.Equal("Yolculuk Bilgileri", PhoneThread.Glossary("Trip Details"));
        Assert.Equal("Seviye 3/4", PhoneThread.Glossary("Level 3/4"));
        Assert.Equal("Kardiyo Antrenmanı", PhoneThread.Glossary("Cardio Workout"));
        Assert.Equal("Kas - Yüksek", PhoneThread.Glossary("Muscle - High"));
        Assert.Equal("Vücut Yağı - Düşük", PhoneThread.Glossary("Body Fat - Low"));
        Assert.Equal("Kaslı", PhoneThread.Glossary("Ripped"));
        Assert.Equal("Kas - Yüksek", PhoneThread.Glossary("Muscle High"));
        Assert.True(PhoneThread.IsPhoneUI("Body Fat Low"));
        foreach (var text in new[] { "Cardio Workout", "Calorie Balance", "You will maintain weight", "I Change Destination",
                                     "I Change Destinatior", "Book Ryde ($82)", "Choose Ryde", "Trip Details", "buckme", "Checking Account" })
            Assert.True(PhoneThread.IsPhoneUI(text), text);
        foreach (var text in new[] { "You got this!", "Get to the car", "Change of plans, meet me downtown", "Rydell's house is over there",
                                     "I skipped my workout today" })
            Assert.False(PhoneThread.IsPhoneUI(text), text);
        Assert.False(PhoneThread.IsSentence("Book Ryde ($82)"));
        Assert.False(PhoneThread.IsSentence("Righto Cash & Carry"));
        Assert.False(PhoneThread.IsSentence("1.74 mi"));
        Assert.True(PhoneThread.IsSentence("Thx amigo! U find anything else"));
        Assert.True(PhoneThread.IsSentence("Are you high right now?"));
        Assert.True(PhoneThread.IsSentence("Dropped off scuba to yuh boat man"));
        Assert.False(PhoneThread.WorthShowing("buckme", "BuckMe mi?"));
        Assert.True(PhoneThread.WorthShowing("Checking Account", "Vadesiz Hesap"));
        Assert.False(PhoneThread.IsMessageList(new Reading(new[] { "Righto Cash & Carry", "Standard Ryde", "Choose Ryde", "Change Destination" }.Select(t => new TextLine(t)))));
        Assert.True(PhoneThread.IsMessageList(new Reading(new[] { "Donnie", "You got my plane?! You be...", "Brian", "Remember, you get your h..." }.Select(t => new TextLine(t)))));
    }

    [Fact]
    public void PhoneWordsWorkInTurkishCulture()
    {
        // Türkçe Windows'ta "I" küçülünce "ı" olur; karşılaştırmalar kültürden bağımsız olmalı.
        var culture = System.Globalization.CultureInfo.CurrentCulture;
        try
        {
            System.Globalization.CultureInfo.CurrentCulture = new System.Globalization.CultureInfo("tr-TR");
            Assert.True(PhoneThread.IsPhoneUI("TRIP DETAILS"));
            Assert.True(MapCard.IsMapScreen(new Reading([new TextLine("RECENTER"), new TextLine("SET DESTINATION")])));
        }
        finally { System.Globalization.CultureInfo.CurrentCulture = culture; }
    }
}

/// <summary>Nino: telefonun yanındaki mesajlaşma paneli ve uygulama baloncukları.</summary>
public class PhoneBubbleTests
{
    private static readonly PhonePanel.Panel Panel = new(new TextBox(0.59, 0.2, 0.79, 0.81), 0.59, 0, 0.2);

    private static void Near(double expected, double actual, double accuracy) =>
        Assert.True(Math.Abs(expected - actual) <= accuracy, $"beklenen {expected:0.####}, bulunan {actual:0.####}");

    [Fact]
    public void TranslationCoversTheBubbleInItsColour()
    {
        var messages = new[]
        {
            new PhoneThread.Message("On my way", new TextBox(0.61, 0.5, 0.7, 0.53), 0.02),
            new PhoneThread.Message("Casa De Donnie", new TextBox(0.61, 0.6, 0.7, 0.63), 0.02),
        };
        var items = PhoneThread.Covers(messages, ["Geliyorum", "Casa De Donnie"], (x, _) => x < 0.6075 ? new Rgb(233, 233, 236) : new Rgb(40, 40, 40));
        var item = Assert.Single(items);
        Assert.Equal("#e9e9ec", item.Fill);
        Assert.Equal("#2c2c2e", item.Ink);
        Assert.True(item.Box.Left < 0.61 && item.Box.Right > 0.7 && item.Box.Top < 0.5 && item.Box.Bottom > 0.53);
    }

    [Fact]
    public void TiltedPhoneHasAnAngle()
    {
        var tilted = new PhonePanel.Panel(Panel.Box, 0.6, -0.1, 0.2);
        Near(Math.Atan(0.1 * 16 / 9) * 180 / Math.PI, tilted.Angle, 1e-9);
        Assert.True(tilted.Angle > 9);
        Near(0, Panel.Angle, 1e-9);
    }

    [Fact]
    public void SideBubblesFormAChatPanelBesideThePhone()
    {
        var messages = new[]
        {
            new PhoneThread.Message("On my way", new TextBox(0.61, 0.5, 0.7, 0.53), 0.02),
            new PhoneThread.Message("Where at?", new TextBox(0.72, 0.6, 0.77, 0.62), 0.02),
        };
        var items = PhoneThread.SideBubbles(messages, ["Geliyorum", "Nerede?"], Panel,
            (x, _) => x < 0.7 ? new Rgb(233, 233, 236) : new Rgb(200, 220, 245), (text, _, _) => (1, text.Length));
        Assert.Equal(3, items.Count);
        var backdrop = items[0];
        Assert.True(backdrop.Backdrop);
        Near(Panel.Box.Top, backdrop.Box.Top, 1e-9);
        Near(Panel.Box.Bottom, backdrop.Box.Bottom, 1e-9);
        Assert.True(backdrop.Box.Right <= Panel.Box.Left, "telefonun solundaki boşlukta");
        Assert.Equal(PhoneThread.BackdropAlpha, backdrop.Alpha);
        var (incoming, outgoing) = (items[1], items[2]);
        foreach (var item in new[] { incoming, outgoing })
        {
            Assert.True(item.Side);
            Assert.True(item.Box.Left >= backdrop.Box.Left && item.Box.Right <= backdrop.Box.Right);
            Assert.Null(item.Angle);
        }
        Near(0.5, incoming.Box.Top, 0.001);
        Assert.True(incoming.Box.Left < outgoing.Box.Left, "gelen solda, giden sağda");
        Assert.Equal("#f8f8f9", incoming.Fill);
        Assert.Equal("#acccfe", outgoing.Fill);
        // Işık bütün balonları mavimsi gösterse de en gri balon gelen sayılır; belirgin mavi balon sağa yaslı.
        var gray = new PhoneThread.Message("Honestly if they didn't let us", new TextBox(0.61, 0.4, 0.77, 0.43), 0.02);
        var longOne = new PhoneThread.Message("No go. Cal's tryin to avoid that chick", new TextBox(0.61, 0.5, 0.77, 0.53), 0.02);
        var tinted = PhoneThread.SideBubbles([gray, longOne], ["Dürüst olmak gerekirse", "Yok, olmaz."], Panel,
            (_, y) => y < 0.45 ? new Rgb(137, 154, 183) : new Rgb(120, 150, 215), (text, _, _) => (1, text.Length));
        Near(tinted[0].Box.Left + 0.012, tinted[1].Box.Left, 1e-9);
        Near(tinted[0].Box.Right - 0.012, tinted[2].Box.Right, 1e-9);
    }

    [Fact]
    public void ChatTitleIsShownOnThePanel()
    {
        var messages = new[] { new PhoneThread.Message("On my way", new TextBox(0.61, 0.5, 0.7, 0.53), 0.02) };
        var items = PhoneThread.SideBubbles(messages, ["Geliyorum"], Panel, (_, _) => new Rgb(233, 233, 236),
            (text, _, _) => (1, text.Length), title: "Lucia");
        Assert.Equal("Lucia", items[0].Translation);
        Assert.True(items[0].Backdrop);
    }

    [Fact]
    public void CoversFollowThePhone()
    {
        var item = new ScreenTranslation.Item("a", "b", new TextBox(0.6, 0.5, 0.7, 0.52), 0.02) { Fill = "#ffffff" };
        var moved = PhoneThread.Shifted([item], 0.01, -0.02)[0];
        Near(0.61, moved.Box.Left, 1e-9);
        Near(0.48, moved.Box.Top, 1e-9);
        Assert.Equal("#ffffff", moved.Fill);
    }

    [Fact]
    public void AppLinesSkipNumbersAndIcons()
    {
        var reading = new Reading([
            new TextLine("$500", new TextBox(0.70, 0.33, 0.77, 0.36)),
            new TextLine("◆ Checking Account", new TextBox(0.61, 0.38, 0.72, 0.40)),
            new TextLine("$4,900 to next goal", new TextBox(0.64, 0.65, 0.74, 0.67)),
        ]);
        var lines = PhoneThread.AppLines(reading, Panel);
        Assert.Equal(["Checking Account", "$4,900 to next goal"], lines.Select(l => l.Text));
        var items = PhoneThread.SideBubbles(lines, ["Vadesiz Hesap", "Sonraki hedefe $4.900"], Panel,
            (_, y) => y < 0.5 ? new Rgb(155, 80, 187) : new Rgb(233, 233, 236), (t, _, _) => (1, t.Length), chat: false);
        Assert.Equal(3, items.Count);
        Assert.True(items[1].Box.Left < items[2].Box.Left, "telefondaki gibi: içeride başlayan satır panelde de içeride");
        Assert.Equal("#f5f5f7", items[1].Ink);
    }

    [Fact]
    public void AppBubblesUseTheAppColourBesideThePhone()
    {
        var lines = new[]
        {
            new PhoneThread.Message("Checking Account", new TextBox(0.61, 0.38, 0.72, 0.40), 0.02),
            new PhoneThread.Message("buckme", new TextBox(0.61, 0.28, 0.66, 0.30), 0.02),
        };
        var items = PhoneThread.AppBubbles(lines, ["Vadesiz Hesap", "BuckMe mi?"], Panel,
            (_, y) => y < 0.45 ? new Rgb(155, 80, 187) : new Rgb(233, 233, 236));
        var item = Assert.Single(items);
        Assert.Equal("Vadesiz Hesap", item.Translation);
        Assert.Equal("#9b50bb", item.Fill);
        Assert.Equal("#ffffff", item.Ink);
        Assert.True(item.Box.Right < Panel.Box.Left, "telefonun solunda");
        Near(0.39, (item.Box.Top + item.Box.Bottom) / 2, 0.002);
    }

    [Fact]
    public void ScreenItemsCarryTheTvFields()
    {
        var item = new ScreenTranslation.Item("a", "b", new TextBox(0.1, 0.2, 0.3, 0.4), 0.02)
        {
            Fill = "#e9e9ec", Ink = "#2c2c2e", Angle = 5.24, Alpha = 0.6, Side = true, Backdrop = true, Card = true,
        };
        var server = new SubtitleServer(0);
        var shown = new List<SubtitleEvent>();
        server.EventSent += shown.Add;
        server.SendScreen([item], 1000, overlay: true);
        Assert.Empty(shown);
        server.SendScreen([item], 1000);
        Assert.Single(shown);
    }
}

/// <summary>Nino: gerçek GTA 6 karelerinde telefon (Mac: RealPhoneFrameTests, DarkPhoneTests, DimPhoneTests…).</summary>
public class RealPhoneFrameTests
{
    private static void Near(double expected, double actual, double accuracy, string name = "") =>
        Assert.True(Math.Abs(expected - actual) <= accuracy, $"{name}: beklenen {expected:0.####}, bulunan {actual:0.####}");

    [Fact]
    public void SilverPhoneIsFoundInEveryFrame()
    {
        foreach (var name in new[] { "gta6-telefon-donnie.jpg", "gta6-telefon-kenton.jpg", "gta6-telefon-shirley.jpg", "gta6-telefon-liste.jpg" })
        {
            if (GameFrames.Load(name) is not { } frame) return;
            var panel = PhonePanel.Find(frame);
            Assert.True(panel is not null, name);
            Near(0.59, panel!.Value.Box.Left, 0.02, name);
            Near(0.79, panel.Value.Box.Right, 0.02, name);
            Near(0.20, panel.Value.Box.Top, 0.03, name);
            Near(0.82, panel.Value.Box.Bottom, 0.03, name);
        }
    }

    [Fact]
    public void TiltedPhoneCutByTheBottomEdgeIsFound()
    {
        if (GameFrames.Load("gta6-telefon-egik-alt.jpg") is not { } frame) return;
        var panel = PhonePanel.Find(frame);
        Assert.NotNull(panel);
        Near(0.58, panel.Value.Box.Top, 0.03);
        Assert.True(panel.Value.Box.Bottom > 0.96);
        Near(0.52, (panel.Value.Box.Left + panel.Value.Box.Right) / 2, 0.03);
    }

    [Fact]
    public void DarkThemedAppIsFoundButDarkClothesAreNot()
    {
        if (GameFrames.Load("gta6-telefon-koyu-rydeme.jpg") is not { } dark || GameFrames.Load("gta6-menu-kapusonlu.jpg") is not { } menu) return;
        var panel = PhonePanel.Find(dark);
        Assert.NotNull(panel);
        Near(0.69, (panel.Value.Box.Left + panel.Value.Box.Right) / 2, 0.03);
        Assert.Null(PhonePanel.Find(menu));
    }

    [Fact]
    public void TrackerKeepsThePhoneWhileItsBodyIsThere()
    {
        if (GameFrames.Load("gta6-telefon-koyu-rydeme.jpg") is not { } first || GameFrames.Load("gta6-telefon-koyu-altpencere.jpg") is not { } sheet
            || GameFrames.Load("gta6-menu-kapusonlu.jpg") is not { } menu) return;
        Assert.Null(PhonePanel.Find(sheet));
        var tracker = new PhonePanel.Tracker();
        var found = tracker.Locate(first);
        Assert.NotNull(found);
        Assert.Equal(found.Value.Box, tracker.Locate(sheet)?.Box);
        Assert.Null(tracker.Locate(menu));
        Assert.Null(tracker.Locate(sheet));
    }

    [Fact]
    public void DimmedPhoneIsFoundAndItsColoursLifted()
    {
        if (GameFrames.Load("gta6-telefon-karanlik.jpg") is not { } frame) return;
        var panel = PhonePanel.Find(frame);
        Assert.NotNull(panel);
        Near(0.36, panel.Value.Box.Left, 0.03);
        Near(0.60, panel.Value.Box.Right, 0.03);
        // "Dropped that stuff off for you" balonu (mavi): renk kanalları karışırsa (BGRA) kırmızı çıkar.
        var blue = PhonePanel.LiftedSampler(frame, panel.Value)(0.44, 0.46);
        Assert.NotNull(blue);
        Assert.True(blue.Value.B > blue.Value.R + 15, blue.ToString());
        Assert.True(blue.Value.B > 150, blue.ToString());
    }

    [Fact]
    public void RydemeDarkThemeIsNotLifted()
    {
        if (GameFrames.Load("gta6-telefon-koyu-rydeme.jpg") is not { } frame) return;
        var panel = PhonePanel.Find(frame)!.Value;
        var lifted = PhonePanel.LiftedSampler(frame, panel);
        var plain = PhonePanel.Sampler(frame);
        var y = (panel.Box.Top + panel.Box.Bottom) / 2;
        var x = panel.Left(y) + (panel.Width * 0.5);
        Assert.Equal(plain(x, y)?.R, lifted(x, y)?.R);
    }

    [Fact]
    public void OtherPhoneFramesAreFound()
    {
        foreach (var (name, center) in new[] { ("gta6-telefon-lucia-foto.jpg", 0.47), ("gta6-telefon-brian-parlama.jpg", -1.0), ("gta6-telefon-egik-mavi.jpg", -1.0) })
        {
            if (GameFrames.Load(name) is not { } frame) return;
            var panel = PhonePanel.Find(frame);
            Assert.True(panel is not null, name);
            if (center > 0) Near(center, (panel!.Value.Box.Left + panel.Value.Box.Right) / 2, 0.04, name);
        }
    }
}

/// <summary>Nino: telefon açıkken altyazı bölgesindeki telefon kısmı okunmadan siyaha boyanır; telefon yazısı altyazı olmaz.</summary>
public class PhoneSubtitleTests
{
    [Fact]
    public void PhoneAreaIsBlackenedInsideTheRegion()
    {
        var area = Frame.Blank(200, 100);
        for (var i = 0; i < area.Pixels.Length; i++) area.Pixels[i] = 255;
        var masked = RegionCropper.Masking(area, new TextBox(0.5, 0.2, 0.8, 0.75), new CropRegion(Top: 0.5, Bottom: 1, Left: 0, Right: 1), margin: 0);
        byte Pixel(int x, int y) => masked.Pixels[(y * masked.Stride) + (x * 4)];
        Assert.Equal(0, Pixel(130, 10));
        Assert.Equal(255, Pixel(130, 80));
        Assert.Equal(255, Pixel(20, 10));
    }

    /// <summary>1920×1080 karanlık kare; ortada siyah çerçeveli beyaz telefon ekranı (x 0.58–0.79, y 0.2–0.85).</summary>
    private static Frame PhoneFrame()
    {
        var frame = Frame.Blank(960, 540);
        for (var y = 0; y < frame.Height; y++)
            for (var x = 0; x < frame.Width; x++)
            {
                double fx = (double)x / frame.Width, fy = (double)y / frame.Height;
                var white = fx is >= 0.58 and < 0.79 && fy is >= 0.2 and < 0.85;
                var i = (y * frame.Stride) + (x * 4);
                frame.Pixels[i] = frame.Pixels[i + 1] = frame.Pixels[i + 2] = (byte)(white ? 240 : 20);
                frame.Pixels[i + 3] = 255;
            }
        return frame;
    }

    [Fact]
    public async Task PhoneTextIsNotASubtitle()
    {
        var frame = PhoneFrame();
        var region = new CropRegion(Top: 0.62, Bottom: 0.97, Left: 0.14, Right: 0.86);
        // Bölgeye göre: telefonun içindeki iki mesaj satırı ve en alttaki gerçek altyazı.
        double X(double frameX) => (frameX - 0.14) / 0.72;
        double Y(double frameY) => (frameY - 0.62) / 0.35;
        var reading = new Reading([
            new TextLine("Still can't believe u found them", new TextBox(X(0.60), Y(0.66), X(0.75), Y(0.68))),
            new TextLine("doubloons. U got that luck boy.", new TextBox(X(0.60), Y(0.69), X(0.75), Y(0.71))),
        ]);
        var sender = new FakeSender();
        var translator = new FakeTranslator();
        var pipeline = new SubtitlePipeline(new LinesReader(reading), translator, sender) { PhonePanels = () => true };
        for (var i = 0; i < 6; i++)
        {
            await pipeline.ProcessAsync(frame, region);
            await pipeline.WaitForTranslationsAsync();
        }
        Assert.Empty(sender.Sent);
        Assert.Empty(translator.Requested);
        // Telefon araması kapalıyken aynı satırlar altyazı olur (karşılaştırma).
        var plain = new FakeSender();
        var engine = new FakeTranslator();
        var other = new SubtitlePipeline(new LinesReader(reading), engine, plain);
        for (var i = 0; i < 6; i++)
        {
            await other.ProcessAsync(frame, region);
            await other.WaitForTranslationsAsync();
        }
        Assert.NotEmpty(engine.Requested);
    }

    [Fact]
    public async Task RecentPhoneMessagesAreNotSubtitles()
    {
        var reading = new Reading([new TextLine("You got my plane?! You better", new TextBox(0.3, 0.7, 0.7, 0.8))]);
        var sender = new FakeSender();
        var pipeline = new SubtitlePipeline(new LinesReader(reading), new FakeTranslator(), sender)
        {
            PhoneTexts = () => ["Donnie: You got my plane?! You better be good to her"],
        };
        for (var i = 0; i < 6; i++)
        {
            await pipeline.ProcessAsync(Frame.Blank(64, 64), new CropRegion());
            await pipeline.WaitForTranslationsAsync();
        }
        Assert.Empty(sender.Sent);
    }

    [Fact]
    public async Task MapScreenHasNoSubtitles()
    {
        var reading = new Reading([new TextLine("Get to the car before the cops arrive.", new TextBox(0.3, 0.7, 0.7, 0.8))]);
        var sender = new FakeSender();
        var pipeline = new SubtitlePipeline(new LinesReader(reading), new FakeTranslator(), sender) { IsMenuScreen = () => true };
        for (var i = 0; i < 6; i++)
        {
            await pipeline.ProcessAsync(Frame.Blank(64, 64), new CropRegion());
            await pipeline.WaitForTranslationsAsync();
        }
        Assert.Empty(sender.Sent);
    }

    [Fact]
    public void WhiteSubtitleIsNotDarkOnLightButPhoneMessageIs()
    {
        // Koyu zeminde beyaz yazı ve açık zeminde koyu yazı (bölge örnekleyicisiyle aynı ölçüler).
        Rgb? WhiteText(double x, double y) => (int)(x * 200) % 4 == 0 ? new Rgb(250, 250, 250) : new Rgb(30, 30, 30);
        Rgb? DarkText(double x, double y) => (int)(x * 200) % 4 == 0 ? new Rgb(30, 30, 30) : new Rgb(235, 235, 238);
        var box = new TextBox(0.2, 0.4, 0.6, 0.5);
        Assert.False(PhoneThread.IsDarkOnLight(box, WhiteText));
        Assert.True(PhoneThread.IsDarkOnLight(box, DarkText));
    }
}
