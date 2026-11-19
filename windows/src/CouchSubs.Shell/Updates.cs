// SPDX-License-Identifier: AGPL-3.0-only

using System.Reflection;

namespace CouchSubs.Shell;

/// <summary>Uygulama güncellemesi (gerçekte Velopack, GitHub sürümlerinden).</summary>
public interface IUpdater
{
    /// <summary>Kurulum dosyasıyla kurulduysa kendini günceller; zip'ten açıldıysa yalnız sürüm sayfasını gösteririz.</summary>
    bool CanUpdateItself { get; }
    Uri DownloadPage { get; }
    /// <summary>Daha yeni sürüm varsa numarası, yoksa null.</summary>
    Task<string?> CheckAsync();
    /// <summary>
    /// İndirir, kurar ve uygulamayı yeniden başlatır. İndirme bitip kurulum başlamadan hemen önce
    /// <paramref name="beforeApply"/> çağrılır (kurulum uygulamayı kapattığı için sonrasında kod çalışmaz); hata
    /// fırlatırsa kurulum başlatılmaz.
    /// </summary>
    Task InstallAsync(IProgress<double> progress, Action? beforeApply = null);
}

/// <summary>
/// Kendiliğinden kurulumun sürüm başına deneme sayısı (auto-update-tried.txt). Kurulum uygulamayı yeniden başlatır;
/// yeniden açılan uygulama hâlâ eski sürümse (kurulum olmadıysa) aynı sürüm yine bulunur. Sayaç bunu sınırlar: sürüm
/// başına en çok <see cref="MaxAttempts"/> kez kendiliğinden kurulur, sonra yalnız "Güncelle" düğmesi kalır.
/// Deneme, indirme bitip kurulum gerçekten başlarken yazılır; yarıda kalan indirme hakkı tüketmez.
/// </summary>
public sealed class AutoUpdateLog(string? file)
{
    public const int MaxAttempts = 2;
    private readonly object gate = new();
    /// <summary>Dosya yoksa (testler) ya da yazılamıyorsa bu süreçteki sayım.</summary>
    private (string Version, int Count) memory = ("", 0);

    /// <summary>Bu sürümün kurulumu kaç kez başlatıldı. Eski biçimde (yalnız sürüm yazan) dosya bir deneme sayılır.</summary>
    public int Attempts(string version)
    {
        lock (gate)
        {
            var remembered = memory.Version == version ? memory.Count : 0;
            return Math.Max(remembered, Read(version));
        }
    }

    public bool Exhausted(string version) => Attempts(version) >= MaxAttempts;

    /// <summary>Bir denemeyi kaydeder; diske yazılamadıysa false (sayım bu süreçte yine tutulur).</summary>
    public bool Record(string version)
    {
        lock (gate)
        {
            var count = Math.Max(memory.Version == version ? memory.Count : 0, Read(version)) + 1;
            memory = (version, count);
            if (file is null) return true;
            try
            {
                if (Path.GetDirectoryName(file) is { Length: > 0 } directory) Directory.CreateDirectory(directory);
                File.WriteAllText(file, $"{version}\n{count}\n");
                return true;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                return false;
            }
        }
    }

    private int Read(string version)
    {
        if (file is null) return 0;
        try
        {
            if (!File.Exists(file)) return 0;
            var lines = File.ReadAllText(file).Split('\n', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
            if (lines.Length == 0 || lines[0] != version) return 0;
            return lines.Length > 1 && int.TryParse(lines[1], out var count) && count > 0 ? count : 1;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return 0;
        }
    }
}

/// <summary>Sürüm numaraları: "0.1.0-beta.10" (anlamsal sürüm, ön sürüm parçaları sayıysa sayı olarak karşılaştırılır).</summary>
public static class AppVersion
{
    /// <summary>Derlemenin sürümü (CI etiketten verir: -p:Version=0.1.0-beta.10); "+commit" eki atılır.</summary>
    public static string Current(Assembly assembly) =>
        (assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0.0").Split('+')[0];

    public static bool IsNewer(string candidate, string current) => Compare(candidate, current) > 0;

    public static int Compare(string a, string b)
    {
        var (coreA, preA) = Split(a);
        var (coreB, preB) = Split(b);
        for (var i = 0; i < Math.Max(coreA.Length, coreB.Length); i++)
        {
            var x = i < coreA.Length ? coreA[i] : 0;
            var y = i < coreB.Length ? coreB[i] : 0;
            if (x != y) return x.CompareTo(y);
        }
        // Ön sürümü olmayan, ön sürümlüden yenidir (0.1.0 > 0.1.0-beta.9).
        if (preA.Length == 0 || preB.Length == 0) return preB.Length.CompareTo(preA.Length);
        for (var i = 0; i < Math.Max(preA.Length, preB.Length); i++)
        {
            if (i >= preA.Length) return -1;
            if (i >= preB.Length) return 1;
            var numberA = int.TryParse(preA[i], out var na);
            var numberB = int.TryParse(preB[i], out var nb);
            var result = numberA && numberB ? na.CompareTo(nb)
                : numberA ? -1 : numberB ? 1 : string.CompareOrdinal(preA[i], preB[i]);
            if (result != 0) return Math.Sign(result);
        }
        return 0;
    }

    private static (int[] Core, string[] Pre) Split(string version)
    {
        var text = version.Trim().TrimStart('v').Split('+')[0];
        var dash = text.IndexOf('-');
        var core = (dash < 0 ? text : text[..dash]).Split('.').Select(part => int.TryParse(part, out var n) ? n : 0).ToArray();
        var pre = dash < 0 ? [] : text[(dash + 1)..].Split('.');
        return (core, pre);
    }
}
