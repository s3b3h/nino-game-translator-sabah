// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "Cihaz bilgileri". Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-19.

using System.Runtime.InteropServices;
using System.Security;
using Microsoft.Win32;

namespace CouchSubs.Core;

/// <summary>
/// Kullanıcının ne kullandığının kısa özeti: uygulama sürümü, bilgisayarın modeli, işletim sistemi, TV ve konsol.
/// Ayarlar › Sistem sağlığı'nda gösterilir ve Sorun Bildir ile Nino'ya Sor bildirimlerine eklenir (sunucuda <c>device</c>
/// alanı); biri hata bildirdiğinde hangi cihazlarla denediği sorulmadan görülür.
/// Kişiyi tanıtan hiçbir şey içermez: bilgisayarın adı, kullanıcı adı, seri numarası, IP adresi, hesap adı yoktur.
/// Mac/iPhone: CouchSubsCore/DeviceInfo.swift ile aynı satırlar ve aynı özet biçimi.
/// </summary>
public static class DeviceInfo
{
    /// <summary>Sunucunun sakladığı en çok uzunluk (nino-pool/src/reports.js ile aynı).</summary>
    public const int MaxLength = 600;

    /// <summary>Üreticinin ve modelin okunamadığı bilgisayar (kendi toplanmış kasa, sanal makine).</summary>
    public const string UnknownModel = "Windows PC";

    /// <param name="Id">Satırın sabit adı ("app", "device", "system", "tv", "console", "status"); çevrilmez, sunucuya bu gider.</param>
    public sealed record Row(string Id, string Value);

    private static readonly Lazy<string> CachedModel = new(ReadModel);
    private static readonly Lazy<string> CachedSystem = new(ReadSystem);

    /// <summary>Bilgisayarın üreticisi ve modeli: "LENOVO 82JU", "ASUS ROG Strix G16"; okunamazsa "Windows PC".</summary>
    public static string Model => CachedModel.Value;

    /// <summary>İşletim sistemi ve yapı numarası: "Windows 11 (26100)".</summary>
    public static string System => CachedSystem.Value;

    /// <summary>
    /// Satırlar, sırayla. Boş ya da bilinmeyen değer satır olmaz.
    /// </summary>
    /// <param name="app">Uygulama sürümü ("3.4.0").</param>
    /// <param name="tv">TV'nin markası, (biliniyorsa) modeli, TV uygulamasının sürümü ve bağlı olup olmadığı; yoksa null.</param>
    /// <param name="console">Konsol ve bağlantı yolu ("PS5 · Remote Play", "Xbox Series X · uzaktan oynatma"); bilinmiyorsa null.</param>
    /// <param name="status">Şu anki durum ya da son hata; yoksa null.</param>
    /// <param name="model">Bilgisayarın modeli; verilmezse <see cref="Model"/> (testlerde sabit değer verilir).</param>
    /// <param name="system">İşletim sistemi; verilmezse <see cref="System"/>.</param>
    public static IReadOnlyList<Row> Rows(string app, string? tv = null, string? console = null, string? status = null,
                                          string? model = null, string? system = null) =>
    [
        .. new Row[]
        {
            new("app", app), new("device", model ?? Model), new("system", system ?? System), new("tv", tv ?? ""),
            new("console", console ?? ""), new("status", status ?? ""),
        }.Select(row => row with { Value = Clean(row.Value) }).Where(row => row.Value.Length > 0),
    ];

    /// <summary>Sunucuya giden tek satır: "app: 3.4.0 | device: LENOVO 82JU | system: Windows 11 (26100) | tv: …".</summary>
    public static string Summary(IEnumerable<Row> rows)
    {
        var text = string.Join(" | ", rows.Select(row => $"{row.Id}: {row.Value}"));
        return text.Length > MaxLength ? text[..MaxLength] : text;
    }

    /// <summary>
    /// İsteğe (<see cref="ProblemReport"/>, <see cref="NinoAssistant"/>) konacak hali: kırpılır, en çok
    /// <see cref="MaxLength"/> karakter; boşsa null (alan hiç gönderilmez).
    /// </summary>
    public static string? ForPayload(string? device)
    {
        var text = (device ?? "").Trim();
        if (text.Length > MaxLength) text = text[..MaxLength];
        return text.Length == 0 ? null : text;
    }

    /// <summary>Satır sonları ve ayırıcı çizgi değerin içinde kalmaz (özet tek satırdır).</summary>
    internal static string Clean(string value) =>
        value.Replace("\r\n", "\n").Replace('\r', ' ').Replace('\n', ' ').Replace('|', '/').Trim();

    /// <summary>"Windows 11 (26100)": Windows 11'in ana sürüm numarası da 10'dur, yapı numarası 22000'den başlar.</summary>
    public static string SystemName(Version version)
    {
        var name = version.Major == 10 ? (version.Build >= 22000 ? "Windows 11" : "Windows 10") : $"Windows {version.Major}.{version.Minor}";
        return version.Build > 0 ? $"{name} ({version.Build})" : name;
    }

    /// <summary>
    /// Üretici ve model tek değerde. Kendi toplanmış kasalarda anakartın doldurmadığı yer tutucular ("System Product
    /// Name", "To Be Filled By O.E.M.") model sayılmaz; ikisi de yoksa <see cref="UnknownModel"/>. Model üreticinin adıyla
    /// başlıyorsa ad yinelenmez.
    /// </summary>
    public static string ModelName(string? manufacturer, string? product)
    {
        var maker = Known(manufacturer);
        var model = Known(product);
        if (maker is null && model is null) return UnknownModel;
        if (maker is null) return model!;
        if (model is null) return maker;
        return model.StartsWith(maker, StringComparison.OrdinalIgnoreCase) ? model : $"{maker} {model}";
    }

    private static readonly string[] Placeholders =
    [
        "system manufacturer", "system product name", "to be filled by o.e.m.", "to be filled by oem", "default string",
        "not applicable", "not specified", "none", "unknown", "o.e.m.", "oem",
    ];

    private static string? Known(string? value)
    {
        var text = Clean(value ?? "");
        return text.Length == 0 || Placeholders.Contains(text.ToLowerInvariant()) ? null : text;
    }

    /// <summary>
    /// Üretici ve model kayıt defterinden (BIOS'un bildirdiği). Bilgisayarın adı, kullanıcı adı ve seri numarası
    /// okunmaz. Windows dışında (testler) ve okunamazsa <see cref="UnknownModel"/>.
    /// </summary>
    private static string ReadModel()
    {
        if (!OperatingSystem.IsWindows()) return UnknownModel;
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\BIOS");
            return ModelName(key?.GetValue("SystemManufacturer") as string, key?.GetValue("SystemProductName") as string);
        }
        catch (Exception error) when (error is SecurityException or UnauthorizedAccessException or IOException)
        {
            return UnknownModel;
        }
    }

    private static string ReadSystem() => OperatingSystem.IsWindows()
        ? SystemName(Environment.OSVersion.Version)
        : Clean(RuntimeInformation.OSDescription);
}
