// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Shell;

/// <summary>COM'dan bağımsız kural görünümü; izin kapsamı ve eski kuraldan geçiş test edilebilir.</summary>
public sealed record FirewallRule(string Name, string Program, bool Enabled, int Direction, int Action,
    int Profiles, int Protocol, string RemoteAddresses = "*", string LocalAddresses = "*",
    string LocalPorts = "*", string RemotePorts = "*", string ServiceName = "", string InterfaceTypes = "All",
    string Grouping = "", bool InterfaceRestricted = false, bool EdgeTraversal = false);

public interface IFirewallRuleStore
{
    IReadOnlyList<FirewallRule> Read();
    void Put(FirewallRule rule);
    void Remove(string name);
}

/// <summary>
/// TV ve Remote Play için yalnız Özel ağdaki yerel cihazlardan TCP/UDP izni. TV sunucusu dolu portta başka port
/// seçer; keşif ve PS5 yayını da değişken UDP portları kullanır. Bu nedenle port değil program/ağ kapsamı daraltılır.
/// </summary>
public static class LocalFirewallPolicy
{
    public const int PrivateProfile = 2;
    public const int Inbound = 1;
    public const int Allow = 1;
    public const int Block = 0;
    public const int Tcp = 6;
    public const int Udp = 17;
    public const int AnyProtocol = 256;
    public const string Group = "Nino.LocalNetwork";
    public const string LegacyName = "CouchSubs";
    public const string TcpName = "Nino - Local TCP";
    public const string UdpName = "Nino - Local UDP";
    // Nino: önceki sürümlerin yazdığı adlar. Aynı işi görürler, o yüzden yalnız adı değiştirmek için yönetici izni
    // sorulmaz (HasRules ada bakmaz); izin başka bir nedenle zaten alındığında (Apply) yeni adlara çevrilirler. Asıl
    // CouchSubs da kendi exe'si için bu adları kullanır; onun kurallarına dokunulmaz.
    public const string PreviousGroup = "CouchSubs.LocalNetwork";
    public const string PreviousTcpName = "CouchSubs - Local TCP";
    public const string PreviousUdpName = "CouchSubs - Local UDP";

    public static IReadOnlyList<FirewallRule> Required(string exe) =>
    [
        new(TcpName, exe, true, Inbound, Allow, PrivateProfile, Tcp, "LocalSubnet", Grouping: Group),
        new(UdpName, exe, true, Inbound, Allow, PrivateProfile, Udp, "LocalSubnet", Grouping: Group),
    ];

    public static bool SameProgram(string a, string b)
    {
        if (string.IsNullOrEmpty(a) || string.IsNullOrEmpty(b)) return false;
        try { return string.Equals(Path.GetFullPath(Environment.ExpandEnvironmentVariables(a)),
            Path.GetFullPath(Environment.ExpandEnvironmentVariables(b)), StringComparison.OrdinalIgnoreCase); }
        catch (Exception) { return false; }
    }

    private static bool Any(string value) => string.IsNullOrEmpty(value) || value == "*";
    private static bool LocalScope(string value) => Any(value) || value.Equals("LocalSubnet", StringComparison.OrdinalIgnoreCase);
    private static bool AllInterfaces(string value) => value.Equals("All", StringComparison.OrdinalIgnoreCase);
    private static bool SameName(string a, string b) => a.Equals(b, StringComparison.OrdinalIgnoreCase);

    /// <summary>Yalnız uygulamanın önceki sürümünün oluşturduğu geniş kural otomatik taşınır.</summary>
    private static bool IsLegacy(FirewallRule r, string exe) => SameName(r.Name, LegacyName) && SameProgram(r.Program, exe)
        && r.Direction == Inbound && r.Action == Allow && r.Protocol == AnyProtocol
        && (r.Profiles & 7) == 7 && Any(r.RemoteAddresses) && Any(r.LocalAddresses)
        && Any(r.LocalPorts) && Any(r.RemotePorts) && r.ServiceName.Length == 0 && r.Grouping.Length == 0
        && AllInterfaces(r.InterfaceTypes) && !r.InterfaceRestricted && !r.EdgeTraversal;

    private static bool HasManagedName(FirewallRule r) => SameName(r.Name, TcpName) || SameName(r.Name, UdpName);

    private static bool IsCurrentManaged(FirewallRule r, string exe) => HasManagedName(r)
        && SameName(r.Grouping, Group) && SameProgram(r.Program, exe) && r.Direction == Inbound && r.Action == Allow;

    /// <summary>Bu exe için önceki sürümün eski adlarla ("CouchSubs - Local TCP/UDP") yazdığı kural.</summary>
    private static bool IsPreviousManaged(FirewallRule r, string exe) =>
        (SameName(r.Name, PreviousTcpName) || SameName(r.Name, PreviousUdpName))
        && SameName(r.Grouping, PreviousGroup) && SameProgram(r.Program, exe) && r.Direction == Inbound && r.Action == Allow;

    private static bool IsManaged(FirewallRule r, string exe) => IsCurrentManaged(r, exe) || IsPreviousManaged(r, exe);

    /// <summary>İzin Özel ağ içindir; Ortak/Etki alanı profillerinin açık olması aranmaz.</summary>
    public static bool HasRules(IReadOnlyList<FirewallRule> rules, string exe, bool privateFirewallEnabled = true) =>
        !rules.Any(r => IsLegacy(r, exe)) && (!privateFirewallEnabled || CoversLocalTraffic(rules, exe));

    private static bool CoversLocalTraffic(IReadOnlyList<FirewallRule> rules, string exe)
    {
        foreach (var protocol in new[] { Tcp, Udp })
        {
            var relevant = rules.Where(r => r.Enabled && r.Direction == Inbound && (r.Profiles & PrivateProfile) != 0
                && (r.Protocol == protocol || r.Protocol == AnyProtocol)).ToList();
            // Başka servislerin/uygulamaların engelleri bu programın izni sayılmaz. Genel tam engel ise izni ezer.
            if (relevant.Any(r => r.Action == Block && (SameProgram(r.Program, exe)
                || (r.Program.Length == 0 && r.ServiceName.Length == 0 && Any(r.LocalPorts)
                    && Any(r.RemotePorts) && LocalScope(r.RemoteAddresses) && Any(r.LocalAddresses))))) return false;
            if (!relevant.Any(r => r.Action == Allow && SameProgram(r.Program, exe) && LocalScope(r.RemoteAddresses)
                && Any(r.LocalAddresses) && Any(r.LocalPorts) && Any(r.RemotePorts)
                && r.ServiceName.Length == 0 && AllInterfaces(r.InterfaceTypes) && !r.InterfaceRestricted)) return false;
        }
        return true;
    }

    /// <summary>
    /// Önce dar kurallar eklenir ve doğrulanır, ancak sonra eski geniş kural kaldırılır. Silinen engeller yalnız bu
    /// exe'yi Özel profilde hedefleyen yerel engellerdir (ör. Windows'un ilk açılış sorusu kapatılınca yazdığı kural); kullanıcı
    /// "izin ver" dediği için kaldırılır. Genel, başka programın, servisin ya da gruplu kuralların engelleri korunur.
    /// Aynı adlı yabancı kural varsa adla yapılan COM silmesi ona da dokunabileceği için o ad hiç silinmez.
    /// </summary>
    public static bool Apply(IFirewallRuleStore store, string exe)
    {
        var before = store.Read();
        if (before.Any(r => HasManagedName(r) && !IsCurrentManaged(r, exe))) return false;
        var groups = before.GroupBy(r => r.Name, StringComparer.OrdinalIgnoreCase).ToList();
        if (groups.Any(g => g.Any(r => IsLegacy(r, exe)) && !g.All(r => SameProgram(r.Program, exe)))) return false;
        // Silinecek ad grupları: içinde eski geniş kural ya da bu exe'nin yerel engeli olan, tamamı bu exe'ye ait gruplar.
        // Önceki sürümün eski adlı kuralları da (yalnız o adın tamamı bu exe'ninse) yenileri yazıldıktan sonra silinir:
        // yönetici izni zaten alınmışken yeniden adlandırma. Aynı adı asıl CouchSubs da kullanıyorsa o ad silinmez.
        var obsolete = groups.Where(g => (g.All(r => SameProgram(r.Program, exe) && !IsManaged(r, exe))
                && g.Any(r => IsLegacy(r, exe) || IsOwnBlock(r, exe)))
            || g.All(r => IsPreviousManaged(r, exe))).SelectMany(g => g).ToList();
        var intended = before.Where(r => !IsManaged(r, exe) && !obsolete.Contains(r)).Concat(Required(exe)).ToList();
        if (!CoversLocalTraffic(intended, exe)) return false;
        foreach (var rule in Required(exe)) store.Put(rule);
        // Eski geniş izin yeni kuralların yazılamamasını maskelemesin.
        var installed = store.Read();
        if (!Required(exe).All(expected => installed.Any(r => r == expected))) return false;
        // COM'da Remove(ad) aynı adlı kurallardan birini ya da hepsini silebilir; ad kalmayana dek tekrarlanır.
        foreach (var group in obsolete.GroupBy(r => r.Name, StringComparer.OrdinalIgnoreCase))
            for (var i = 0; i < group.Count() && store.Read().Any(r => SameName(r.Name, group.Key)); i++)
                store.Remove(group.Key);
        return HasRules(store.Read(), exe);
    }

    private static bool IsOwnBlock(FirewallRule r, string exe) => r.Action == Block && r.Direction == Inbound
        && (r.Profiles & PrivateProfile) != 0
        && SameProgram(r.Program, exe) && r.Grouping.Length == 0 && r.ServiceName.Length == 0;

    public static void RemoveOwned(IFirewallRuleStore store, string exe)
    {
        var rules = store.Read();
        foreach (var group in rules.GroupBy(r => r.Name, StringComparer.OrdinalIgnoreCase))
        {
            if (!group.All(r => IsManaged(r, exe) || IsLegacy(r, exe))) continue;
            foreach (var rule in group) store.Remove(rule.Name);
        }
    }
}
