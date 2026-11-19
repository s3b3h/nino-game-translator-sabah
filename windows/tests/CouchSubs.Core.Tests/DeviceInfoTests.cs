// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>Nino: "Cihaz bilgileri" (Mac: DeviceInfoTests). Satırların adı, sırası ve özetin biçimi bütün cihazlarda aynıdır.</summary>
public class DeviceInfoTests
{
    [Fact]
    public void RowsSkipUnknownValues()
    {
        var rows = DeviceInfo.Rows("3.4.0", tv: null, console: "PS5 · Remote Play", status: "  ",
            model: "LENOVO 82JU", system: "Windows 11 (26100)");
        Assert.Equal(["app", "device", "system", "console"], rows.Select(row => row.Id));
    }

    [Fact]
    public void RowsKeepTheSharedOrder()
    {
        var rows = DeviceInfo.Rows("3.4.0", tv: "LG", console: "PS5 · Remote Play", status: "çeviri açık",
            model: "LENOVO 82JU", system: "Windows 11 (26100)");
        Assert.Equal(["app", "device", "system", "tv", "console", "status"], rows.Select(row => row.Id));
    }

    [Fact]
    public void SummaryIsOneLine()
    {
        var rows = DeviceInfo.Rows("3.4.0 (19)", tv: "Samsung QE55Q70C\nTV uygulaması 3.4.0", console: "PS5 | Remote Play",
            model: "Mac16,1", system: "macOS 27.0");
        Assert.Equal(
            "app: 3.4.0 (19) | device: Mac16,1 | system: macOS 27.0 | tv: Samsung QE55Q70C TV uygulaması 3.4.0 | console: PS5 / Remote Play",
            DeviceInfo.Summary(rows));
    }

    [Fact]
    public void SummaryIsClipped()
    {
        var rows = DeviceInfo.Rows(new string('x', 2000), model: "LENOVO 82JU", system: "Windows 11 (26100)");
        Assert.Equal(DeviceInfo.MaxLength, DeviceInfo.Summary(rows).Length);
    }

    [Fact]
    public void ThisMachineHasAModelAndSystem()
    {
        Assert.NotEmpty(DeviceInfo.Model);
        Assert.NotEmpty(DeviceInfo.System);
        var rows = DeviceInfo.Rows("3.4.0");
        Assert.Equal(["app", "device", "system"], rows.Select(row => row.Id));
    }

    [Theory]
    [InlineData(10, 0, 26100, "Windows 11 (26100)")]
    [InlineData(10, 0, 22000, "Windows 11 (22000)")]
    [InlineData(10, 0, 19045, "Windows 10 (19045)")]
    [InlineData(6, 3, 9600, "Windows 6.3 (9600)")]
    public void SystemNameTellsWindows11From10ByBuild(int major, int minor, int build, string expected) =>
        Assert.Equal(expected, DeviceInfo.SystemName(new Version(major, minor, build)));

    [Theory]
    [InlineData("LENOVO", "82JU", "LENOVO 82JU")]
    [InlineData("ASUSTeK COMPUTER INC.", "ROG Strix G614JV", "ASUSTeK COMPUTER INC. ROG Strix G614JV")]
    [InlineData("HP", "HP Pavilion Laptop 15", "HP Pavilion Laptop 15")]
    [InlineData("Micro-Star International Co., Ltd.", "System Product Name", "Micro-Star International Co., Ltd.")]
    [InlineData("System manufacturer", "System Product Name", "Windows PC")]
    [InlineData("To Be Filled By O.E.M.", "To Be Filled By O.E.M.", "Windows PC")]
    [InlineData("Default string", " ", "Windows PC")]
    [InlineData(null, null, "Windows PC")]
    public void ModelIsManufacturerAndProductWithoutPlaceholders(string? manufacturer, string? product, string expected) =>
        Assert.Equal(expected, DeviceInfo.ModelName(manufacturer, product));

    [Fact]
    public void ReportCarriesDeviceOnlyWhenKnown()
    {
        var with = ProblemReport.Build("12345678", "3.4.0", "tr", "x", null, null, [], " app: 3.4.0 | device: LENOVO 82JU ");
        Assert.Equal("app: 3.4.0 | device: LENOVO 82JU", with.Device);
        using (var json = JsonDocument.Parse(ProblemReport.ToJson(with)))
            Assert.Equal("app: 3.4.0 | device: LENOVO 82JU", json.RootElement.GetProperty("device").GetString());

        var without = ProblemReport.Build("12345678", "3.4.0", "tr", "x", null, null, []);
        Assert.Null(without.Device);
        Assert.DoesNotContain("device", ProblemReport.ToJson(without));
        Assert.Null(ProblemReport.Build("12345678", "3.4.0", "tr", "x", null, null, [], "   ").Device);
        Assert.Equal(DeviceInfo.MaxLength, ProblemReport.Build("12345678", "3.4.0", "tr", "x", null, null, [], new string('d', 900)).Device!.Length);
    }

    [Fact]
    public void AssistantCarriesDeviceOnlyWhenKnown()
    {
        NinoAssistant.Turn[] turns = [new(NinoAssistant.Role.User, "TV'de altyazı çıkmıyor")];
        var with = NinoAssistant.Build("12345678", "3.4.0", "tr", turns, device: " app: 3.4.0 | tv: LG ");
        Assert.Equal("app: 3.4.0 | tv: LG", with.Device);
        using (var json = JsonDocument.Parse(NinoAssistant.ToJson(with)))
            Assert.Equal("app: 3.4.0 | tv: LG", json.RootElement.GetProperty("device").GetString());

        var without = NinoAssistant.Build("12345678", "3.4.0", "tr", turns);
        Assert.Null(without.Device);
        Assert.DoesNotContain("device", NinoAssistant.ToJson(without));
    }

    /// <summary>Kartın metinleri ortak katalogda (Mac'in Localizable.xcstrings dosyası) bütün dillerde vardır.</summary>
    [Theory]
    [InlineData("Device info")]
    [InlineData("Added to your problem reports so we can see what you use without asking. It contains no names, serial numbers or addresses.")]
    [InlineData("App version")]
    [InlineData("Device model")]
    [InlineData("Operating system")]
    [InlineData("Console")]
    [InlineData("Current status")]
    [InlineData("Copy device info")]
    [InlineData("Copied")]
    public void CardTextsAreTranslated(string key)
    {
        Assert.NotEqual(key, Localizer.ForLanguage("tr")[key]);
        Assert.NotEqual(key, Localizer.ForLanguage("ar")[key]);
    }
}
