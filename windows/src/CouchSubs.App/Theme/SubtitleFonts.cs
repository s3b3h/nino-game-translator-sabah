// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows.Media;
using CouchSubs.Core;

namespace CouchSubs.App.Theme;

/// <summary>
/// Nino: altyazının yazı tipi (<see cref="SubtitleFont"/>). Barlow, Barlow Condensed ve Nunito uygulamaya gömülüdür
/// (Fonts klasörü, OFL lisanslı). WPF için iki değişiklik var: Nunito'nun değişken dosyası WPF'te en ince hâliyle
/// çizildiği için yarı kalın ve kalın olarak sabitlendi; Barlow Condensed, WPF adındaki "Condensed"i ayıklayıp onu
/// Barlow'un bir yüzü saymasın diye "Nino Action" adıyla gömülü (NinoAction-*.ttf). Bu yazı tiplerinde olmayan harfler (Arapça, Tayca, Hintçe) listedeki sistem yazı tipiyle çizilir.
/// </summary>
public static class SubtitleFonts
{
    private static readonly Uri Base = new("pack://application:,,,/");
    private const string Fallback = "Segoe UI, Segoe UI Historic, Nirmala UI, Leelawadee UI";

    private static readonly Dictionary<SubtitleFont, FontFamily> Families = new()
    {
        [SubtitleFont.Condensed] = new FontFamily(Base, $"./Fonts/#Nino Action, {Fallback}"),
        [SubtitleFont.Modern] = new FontFamily(Base, $"./Fonts/#Barlow, {Fallback}"),
        [SubtitleFont.Rounded] = new FontFamily(Base, $"./Fonts/#Nunito, {Fallback}"),
    };

    /// <summary>Seçilen yazı tipi; <see cref="SubtitleFont.System"/> için null (pencerenin kendi yazı tipi, eskisi gibi).</summary>
    public static FontFamily? Family(SubtitleFont font) => Families.GetValueOrDefault(font);

    /// <summary>Yazı tipini bloğa uygular; Sade'de bloğun kendi yazı tipi kalır.</summary>
    public static System.Windows.Controls.TextBlock Apply(System.Windows.Controls.TextBlock block, SubtitleFont font)
    {
        if (Family(font) is { } family) block.FontFamily = family;
        return block;
    }
}
