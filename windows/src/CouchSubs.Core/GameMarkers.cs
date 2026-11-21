// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Nino: oyunu ekrandaki kendine özgü yazılardan, sunucuya sormadan tanır. PS5'in keşif yanıtı çalışan oyunu çoğu zaman
/// bildirmiyor (21 Kasım 2026: PS5 14.23, GTA 6 açıkken <c>running-app-name</c> hiç yok); yeni kurulumda oyun
/// "Bilinmiyor" kalıyor, GTA 6'ya özgü telefon ve harita çevirisi açılmıyordu. Mac/iPhone (GameMarkers.swift) ve Android
/// (GameMarkers.kt) ile aynı kurallar.
/// </summary>
public static class GameMarkers
{
    /// <summary>Listede ve ekranda görünen ad; <see cref="GameName.Key"/> ile "Grand Theft Auto VI" ile aynıdır.</summary>
    public const string Gta6 = "GTA 6";

    /// <summary>
    /// Okumada GTA 6'ya özgü yazı varsa oyunun adı, yoksa null: harita tuş listesi (<see cref="MapCard.IsMapScreen"/>),
    /// duraklatma menüsünün sekme şeridi ("JASON &amp; LUCIA" ya da "BRIEF" ve "PROGRESS" birlikte) ya da telefonun "WhatUp"
    /// uygulaması.
    /// </summary>
    public static string? Game(Reading reading)
    {
        if (MapCard.IsMapScreen(reading)) return Gta6;
        var lines = reading.Lines.Select(l => TextMatch.Normalize(MapCard.CleanMenuText(l.Text))).ToList();
        var words = lines.SelectMany(l => l.Split(' ', StringSplitOptions.RemoveEmptyEntries)).ToHashSet();
        if (lines.Any(l => l.Contains("jason", StringComparison.Ordinal) && l.Contains("lucia", StringComparison.Ordinal))) return Gta6;
        if (lines.Contains("brief") && lines.Contains("progress") && (words.Contains("jason") || words.Contains("lucia") || lines.Contains("map")))
            return Gta6;
        return lines.Contains("whatup") ? Gta6 : null;
    }
}
