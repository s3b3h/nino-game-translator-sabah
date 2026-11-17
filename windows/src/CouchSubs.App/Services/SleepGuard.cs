// SPDX-License-Identifier: AGPL-3.0-only

using System.Runtime.InteropServices;

namespace CouchSubs.App.Services;

/// <summary>Çeviri sürerken bilgisayarın boşta uykuya geçmesini engeller (kullanıcı TV'de oynuyor, bilgisayara dokunmuyor).</summary>
public static partial class SleepGuard
{
    private const uint EsContinuous = 0x80000000;
    private const uint EsSystemRequired = 0x00000001;
    private const uint EsDisplayRequired = 0x00000002;
    private static bool system;
    private static bool display;

    [LibraryImport("kernel32.dll")]
    private static partial uint SetThreadExecutionState(uint flags);

    public static bool IsActive { get; private set; }

    public static void Begin()
    {
        system = true;
        Apply();
        IsActive = true;
    }

    public static void End()
    {
        system = false;
        Apply();
        IsActive = false;
    }

    /// <summary>Oyun bu bilgisayarda gösterilirken (yakalama kartı) ekran da kapanmasın: oyuncu kolla oynar, bilgisayar
    /// hiç dokunuş görmez ve birkaç dakika sonra ekranı karartırdı.</summary>
    public static void KeepDisplayOn(bool on)
    {
        display = on;
        Apply();
    }

    private static void Apply() =>
        SetThreadExecutionState(EsContinuous | (system ? EsSystemRequired : 0) | (display ? EsDisplayRequired | EsSystemRequired : 0));
}
