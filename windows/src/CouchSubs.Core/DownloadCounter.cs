// SPDX-License-Identifier: AGPL-3.0-only
// Nino: ana ekrandaki TV'nin sağ üst köşesinde görünen "Toplam indirme" sayısı (Mac'teki DownloadCounter ile aynı kural).

using System.Globalization;
using System.Text.Json;

namespace CouchSubs.Core;

/// <summary>
/// Toplam indirme sayısı (GitHub'daki uygulama dosyalarının indirme toplamı). Sunucunun <c>GET /v1/config</c>
/// cevabındaki <c>downloads</c> alanından okunur (<see cref="TranslationPool.RefreshConfigAsync"/> ayarı zaten sorar;
/// ayrı istek yapılmaz). İstek kullanıcıya ait hiçbir bilgi taşımaz. İnternet yoksa ya da sunucu sayıyı veremiyorsa son
/// bilinen sayı gösterilmeye devam eder (dosyada kalıcı saklanır); hiç alınamadıysa sayaç görünmez. Sayı olduğu gibi
/// gösterilir, üstüne ekleme yapılmaz.
/// </summary>
public sealed class DownloadCounter
{
    /// <summary>Son bilinen sayının saklandığı dosyanın adı (havuz klasöründe).</summary>
    public const string FileName = "downloads.txt";
    /// <summary>Sunucuya en çok bu aralıkla sorulur (sn); ana ekran bu aralıkla yeniler.</summary>
    public const double RefreshSeconds = 600;

    private readonly object gate = new();
    private readonly string? file;
    private int? total;

    /// <param name="file">Son bilinen sayının dosyası; null ise saklanmaz.</param>
    public DownloadCounter(string? file)
    {
        this.file = file;
        total = Load(file);
    }

    /// <summary>Son bilinen toplam; hiç alınamadıysa null (gösterge görünmez).</summary>
    public int? Total
    {
        get { lock (gate) return total; }
    }

    /// <summary>
    /// Sunucunun ayar cevabını işler. Sayı okunamazsa (cevap yok, alan yok, bozuk) eldeki sayı kalır. Sayı değiştiyse
    /// saklar ve true döner.
    /// </summary>
    public bool Record(string? body)
    {
        if (Parse(body) is not { } value) return false;
        lock (gate)
        {
            if (total == value) return false;
            total = value;
        }
        Save(value);
        return true;
    }

    /// <summary><c>/v1/config</c> cevabındaki toplam indirme; alan yoksa ya da sayı geçersizse null.</summary>
    public static int? Parse(string? body)
    {
        if (string.IsNullOrWhiteSpace(body)) return null;
        try
        {
            using var document = JsonDocument.Parse(body);
            if (document.RootElement.ValueKind != JsonValueKind.Object
                || !document.RootElement.TryGetProperty("downloads", out var field)
                || field.ValueKind != JsonValueKind.Number) return null;
            if (field.TryGetInt32(out var value)) return value > 0 ? value : null;
            // "3439.0" gibi tam sayı değerli ondalık yazım da sayılır; kesirli ya da taşan sayı sayılmaz.
            return field.TryGetDouble(out var number) && number > 0 && number <= int.MaxValue && Math.Floor(number) == number
                ? (int)number : null;
        }
        catch (JsonException) { return null; }
    }

    /// <summary>Sayı, binlik ayırıcısı yerel biçimde ("3.439" ya da "3,439").</summary>
    public static string Format(int total, CultureInfo? culture = null) => total.ToString("N0", culture ?? CultureInfo.CurrentCulture);

    private static int? Load(string? file)
    {
        if (file is null) return null;
        try
        {
            return File.Exists(file) && int.TryParse(File.ReadAllText(file).Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out var saved)
                && saved > 0 ? saved : null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
    }

    private void Save(int value)
    {
        if (file is null) return;
        try
        {
            if (Path.GetDirectoryName(file) is { Length: > 0 } directory) Directory.CreateDirectory(directory);
            var temporary = file + ".tmp";
            File.WriteAllText(temporary, value.ToString(CultureInfo.InvariantCulture));
            File.Move(temporary, file, overwrite: true);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}
