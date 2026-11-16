// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı (Mac: GameWindowCapture.swift). Yalnız Win32 kullanır.

using System.Diagnostics;
using System.Runtime.InteropServices;
using CouchSubs.Core;
using CouchSubs.RemotePlay;
using CouchSubs.Shell;

namespace CouchSubs.App.Services;

/// <summary>
/// PS Remote Play ya da chiaki-ng penceresini bulur, yalnız oyun alanını okur ve PS5'ten gelen karelerle aynı boyda
/// (1920 × 1080) verir.
/// <list type="bullet">
/// <item>Önce pencerenin kendisi istenir (PrintWindow, tam içerik): pencere başka bir pencerenin altında kalsa da okunur
/// ve Nino'nun altyazı penceresi kareye hiç girmez.</item>
/// <item>Uygulama pencereyi böyle veremiyorsa (kare simsiyah gelir) ekranın o alanı kopyalanır; altyazı penceresi o
/// sırada ekran kopyalarından gizlenir (bkz. <see cref="Views.SubtitleOverlayWindow"/>).</item>
/// <item>Pencere taşınır, büyür, tam ekrana geçer ya da kapanıp açılırsa kendiliğinden yeniden bulunur.</item>
/// <item>Görüntü değişmese de kare sabit hızla verilir; okuma hattı satırı bitirip kaldırabilir.</item>
/// </list>
/// </summary>
public sealed partial class GameWindowCapture : IGameWindowStream
{
    public const int OutputWidth = 1920;
    public const int OutputHeight = 1080;
    /// <summary>Okuma hattına saniyede verilen kare (okuma zaten önceki kare bitmeden yenisini almaz).</summary>
    public const int FramesPerSecond = 10;
    private const int LookupEveryMs = 1500;

    public event Action<Frame>? FrameReceived;
    public event Action<SessionState>? StateChanged;
    public event Action<RegisteredConsole>? ConsoleMoved { add { } remove { } }
    public event Action<GameWindowStatus, string?>? WindowStatusChanged;
    public event Action<ScreenArea?>? GameAreaChanged;

    private readonly object gate = new();
    private Thread? thread;
    private volatile bool running;
    private GameWindowStatus status = GameWindowStatus.Stopped;
    private GameWindowInfo? current;
    private ScreenArea? reportedArea;
    /// <summary>Bu pencere için PrintWindow uzun süre simsiyah verdi, ekran ise doluydu: ekran kopyasına geçildi.</summary>
    private bool screenCopy;
    /// <summary>Art arda simsiyah gelen PrintWindow karesi (yayın başı, yükleme ekranı, kararma gerçekten siyahtır).</summary>
    private int blackStreak;
    /// <summary>Ekran kopyasındayken pencerenin kendini yeniden verip vermediği bu kadar karede bir denenir.</summary>
    private int sinceRetry;
    /// <summary>Bu kadar kare (3 sn) simsiyah gelirse ve ekranın o alanı doluysa ekran kopyasına geçilir.</summary>
    private const int BlackFramesBeforeScreenCopy = 30;
    private const int RetryEvery = 20;
    private readonly int ownProcess = Environment.ProcessId;
    private readonly Dictionary<uint, string> processNames = [];

    public void Start()
    {
        lock (gate)
        {
            if (running) return;
            running = true;
            thread = new Thread(Run) { IsBackground = true, Name = "Nino oyun penceresi" };
            thread.Start();
        }
    }

    /// <summary>Bloklamaz; iş parçacığı en geç bir kare sonra durur. Durduktan sonra hiçbir olay gönderilmez.</summary>
    public void Stop() => running = false;

    public void ReconnectNow()
    {
        lock (gate) current = null;
    }

    public void Dispose() => Stop();

    private void Run()
    {
        // Pencere ölçüleri ve kopyalar gerçek pikselle (başka ölçekli ekrandaki pencere kırpılmasın). Altyazı penceresine
        // giden oyun alanı ayrıca WPF'in (sistem DPI'ı) birimiyle hesaplanır, bkz. AreaForOverlay.
        SetThreadDpiAwarenessContext(PerMonitorAwareV2);
        var clock = Stopwatch.StartNew();
        long nextLookup = 0;
        using var target = new Canvas(OutputWidth, OutputHeight);
        Canvas? source = null;
        try
        {
            while (running)
            {
                var started = clock.ElapsedMilliseconds;
                if (started >= nextLookup)
                {
                    LookUp();
                    nextLookup = started + LookupEveryMs;
                }
                GameWindowInfo? window;
                lock (gate) window = current;
                if (window is not null && !IsWindow(window.Handle)) LookUp();
                lock (gate) window = current;
                if (window is not null)
                {
                    try
                    {
                        var frame = CaptureFrame(window, target, ref source);
                        if (frame is not null && running) FrameReceived?.Invoke(frame);
                    }
                    catch (Exception error)
                    {
                        SubtitleLog.Write($"oyun penceresi okunamadı: {error.GetType().Name}: {error.Message}");
                        lock (gate) current = null;
                    }
                }
                var wait = 1000 / FramesPerSecond - (int)(clock.ElapsedMilliseconds - started);
                if (wait > 0) Thread.Sleep(wait);
            }
        }
        finally
        {
            source?.Dispose();
        }
    }

    // MARK: Pencereyi bulma

    private void LookUp()
    {
        var windows = new List<GameWindowInfo>();
        EnumWindows((handle, _) =>
        {
            if (!IsWindowVisible(handle) || IsIconic(handle)) return true;
            GetWindowThreadProcessId(handle, out var pid);
            if (pid == ownProcess) return true;
            var client = ClientArea(handle);
            if (client is null) return true;
            windows.Add(new GameWindowInfo(handle, ProcessName(pid), WindowTitle(handle), client.Value));
            return true;
        }, IntPtr.Zero);
        var pick = GameWindowRules.Pick(windows);
        lock (gate)
        {
            if (pick is null)
            {
                current = null;
                Report(GameWindowStatus.LookingForWindow, null, null);
                return;
            }
            if (current?.Handle != pick.Handle)
            {
                screenCopy = false;
                blackStreak = 0;
            }
            current = pick;
        }
        Report(GameWindowStatus.Capturing, AppName(pick.ProcessName), AreaForOverlay(pick.Handle));
    }

    private static string AppName(string process) =>
        process.Contains("chiaki", StringComparison.OrdinalIgnoreCase) ? "chiaki-ng" : "PS Remote Play";

    private string ProcessName(uint pid)
    {
        if (processNames.TryGetValue(pid, out var name)) return name;
        try { name = Process.GetProcessById((int)pid).ProcessName; } catch { name = ""; }
        processNames[pid] = name;
        return name;
    }

    private static string WindowTitle(IntPtr handle)
    {
        var buffer = new char[256];
        var length = GetWindowTextW(handle, buffer, buffer.Length);
        return length > 0 ? new string(buffer, 0, length) : "";
    }

    /// <summary>Pencerenin içerik alanı (başlık çubuğu ve kenarlık hariç), ekran pikseliyle.</summary>
    private static ScreenArea? ClientArea(IntPtr handle)
    {
        if (!GetClientRect(handle, out var rect) || rect.Right <= 0 || rect.Bottom <= 0) return null;
        var origin = new Point();
        if (!ClientToScreen(handle, ref origin)) return null;
        return new ScreenArea(origin.X, origin.Y, rect.Right, rect.Bottom);
    }

    /// <summary>
    /// Oyun alanı, altyazı penceresinin (WPF, sistem DPI'ı) gördüğü koordinatlarla: iş parçacığı bir an sistem DPI'ına
    /// geçer, Windows ölçüleri o birime çevirir.
    /// </summary>
    private static ScreenArea? AreaForOverlay(IntPtr handle)
    {
        var previous = SetThreadDpiAwarenessContext(SystemAware);
        try
        {
            return ClientArea(handle) is { } client ? GameWindowRules.GameArea(client) : null;
        }
        finally
        {
            SetThreadDpiAwarenessContext(previous);
        }
    }

    private void Report(GameWindowStatus newStatus, string? app, ScreenArea? area)
    {
        if (!running) return;
        bool statusChanged;
        lock (gate)
        {
            statusChanged = newStatus != status;
            status = newStatus;
        }
        if (statusChanged)
        {
            WindowStatusChanged?.Invoke(newStatus, app);
            StateChanged?.Invoke(GameWindowRules.SessionState(newStatus));
        }
        if (area != reportedArea)
        {
            reportedArea = area;
            GameAreaChanged?.Invoke(area);
        }
    }

    // MARK: Kare

    private Frame? CaptureFrame(GameWindowInfo window, Canvas target, ref Canvas? source)
    {
        var client = ClientArea(window.Handle);
        if (client is null) return null;
        var game = GameWindowRules.GameArea(client.Value);
        // Pencere taşındı ya da boyu değişti: oyun alanı yeniden bildirilir (altyazı penceresi onu izler).
        if (client.Value != window.Client)
        {
            lock (gate) current = window with { Client = client.Value };
            Report(GameWindowStatus.Capturing, AppName(window.ProcessName), AreaForOverlay(window.Handle));
        }
        int gx = (int)(game.Left - client.Value.Left), gy = (int)(game.Top - client.Value.Top);
        int gw = (int)game.Width, gh = (int)game.Height;
        if (gw <= 0 || gh <= 0) return null;

        // Ekran kopyasındayken ara ara pencerenin kendisi yeniden denenir (Remote Play yayını sonradan gelmiş olabilir).
        var tryWindow = !screenCopy || ++sinceRetry >= RetryEvery;
        if (tryWindow)
        {
            sinceRetry = 0;
            int cw = (int)client.Value.Width, ch = (int)client.Value.Height;
            if (source is null || source.Width != cw || source.Height != ch)
            {
                source?.Dispose();
                source = new Canvas(cw, ch);
            }
            // PW_CLIENTONLY | PW_RENDERFULLCONTENT: DirectX ile çizen pencereler de (Windows 8.1+) verilir.
            if (PrintWindow(window.Handle, source.Dc, 0x1 | 0x2) && !source.IsBlack(gx, gy, gw, gh))
            {
                if (screenCopy) SubtitleLog.Write("oyun penceresi yeniden kendini veriyor; ekran kopyası bırakıldı");
                screenCopy = false;
                blackStreak = 0;
                target.Draw(source.Dc, gx, gy, gw, gh);
                return target.ToFrame();
            }
            if (!screenCopy)
            {
                // Siyah kare çoğunlukla gerçekten siyahtır (yayın başı, yükleme); hemen ekrana geçilmez.
                blackStreak++;
                if (blackStreak < BlackFramesBeforeScreenCopy) return target.Clear();
            }
        }

        var screen = GetDC(IntPtr.Zero);
        try
        {
            target.Draw(screen, (int)game.Left, (int)game.Top, gw, gh);
            if (!screenCopy)
            {
                // Ekranın o alanı da siyahsa sahne gerçekten karanlıktır: pencerenin kendisinde kalınır.
                if (target.IsBlack(0, 0, target.Width, target.Height))
                {
                    blackStreak = 0;
                    return target.ToFrame();
                }
                screenCopy = true;
                SubtitleLog.Write("oyun penceresi kendini vermedi; ekran kopyasına geçildi");
            }
        }
        finally
        {
            ReleaseDC(IntPtr.Zero, screen);
        }
        return target.ToFrame();
    }

    /// <summary>Üstten alta, BGRA bir GDI çizim yüzeyi.</summary>
    private sealed class Canvas : IDisposable
    {
        public int Width { get; }
        public int Height { get; }
        public IntPtr Dc { get; }
        private readonly IntPtr bitmap;
        private readonly IntPtr old;
        private readonly IntPtr bits;

        public Canvas(int width, int height)
        {
            Width = width;
            Height = height;
            var info = new BitmapInfo
            {
                Size = 40, // BITMAPINFOHEADER
                Width = width,
                Height = -height, // eksi: satırlar üstten alta
                Planes = 1,
                BitCount = 32,
            };
            Dc = CreateCompatibleDC(IntPtr.Zero);
            bitmap = CreateDIBSection(Dc, ref info, 0, out bits, IntPtr.Zero, 0);
            if (bitmap == IntPtr.Zero)
            {
                DeleteDC(Dc);
                throw new InvalidOperationException("çizim yüzeyi açılamadı");
            }
            old = SelectObject(Dc, bitmap);
        }

        /// <summary>Kaynağın verilen alanını bu yüzeyin tamamına ölçekler.</summary>
        public void Draw(IntPtr from, int x, int y, int width, int height)
        {
            SetStretchBltMode(Dc, 4); // HALFTONE: küçültmede yazılar bozulmasın
            SetBrushOrgEx(Dc, 0, 0, IntPtr.Zero);
            // SRCCOPY | CAPTUREBLT
            if (!StretchBlt(Dc, 0, 0, Width, Height, from, x, y, width, height, 0x00CC0020 | 0x40000000))
                throw new InvalidOperationException("kare kopyalanamadı");
            GdiFlush();
        }

        /// <summary>Alanın içinden 64 noktaya bakar; hepsi siyahsa pencere kendini vermemiştir.</summary>
        public unsafe bool IsBlack(int x, int y, int width, int height)
        {
            GdiFlush();
            var pixels = (uint*)bits;
            for (var row = 1; row <= 8; row++)
            for (var col = 1; col <= 8; col++)
            {
                var px = Math.Clamp(x + width * col / 9, 0, Width - 1);
                var py = Math.Clamp(y + height * row / 9, 0, Height - 1);
                if ((pixels[py * Width + px] & 0x00FFFFFF) != 0) return false;
            }
            return true;
        }

        /// <summary>Siyah kare (pencere henüz görüntü vermiyor); okuma hattı ekranı boş görür, eski satır kalkar.</summary>
        public unsafe Frame Clear()
        {
            GdiFlush();
            new Span<byte>((void*)bits, Width * Height * 4).Clear();
            return ToFrame();
        }

        /// <summary>Kare kendi belleğine kopyalanır (yüzey bir sonraki karede yeniden kullanılır).</summary>
        public Frame ToFrame() => Frame.Copy(bits, Width, Height, Width * 4);

        public void Dispose()
        {
            SelectObject(Dc, old);
            DeleteObject(bitmap);
            DeleteDC(Dc);
        }
    }

    // MARK: Win32

    private static readonly IntPtr SystemAware = -2;
    private static readonly IntPtr PerMonitorAwareV2 = -4;

    [LibraryImport("user32.dll")]
    private static partial IntPtr SetThreadDpiAwarenessContext(IntPtr context);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfo
    {
        public int Size;
        public int Width;
        public int Height;
        public short Planes;
        public short BitCount;
        public int Compression;
        public int SizeImage;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public int ClrUsed;
        public int ClrImportant;
        public int Colors;
    }

    private delegate bool EnumWindowsProc(IntPtr handle, IntPtr param);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr param);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsWindow(IntPtr handle);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsWindowVisible(IntPtr handle);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsIconic(IntPtr handle);

    [LibraryImport("user32.dll")]
    private static partial uint GetWindowThreadProcessId(IntPtr handle, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr handle, char[] text, int max);

    [DllImport("user32.dll")]
    private static extern bool GetClientRect(IntPtr handle, out Rect rect);

    [DllImport("user32.dll")]
    private static extern bool ClientToScreen(IntPtr handle, ref Point point);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool PrintWindow(IntPtr handle, IntPtr dc, uint flags);

    [LibraryImport("user32.dll")]
    private static partial IntPtr GetDC(IntPtr handle);

    [LibraryImport("user32.dll")]
    private static partial int ReleaseDC(IntPtr handle, IntPtr dc);

    [LibraryImport("gdi32.dll")]
    private static partial IntPtr CreateCompatibleDC(IntPtr dc);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateDIBSection(IntPtr dc, ref BitmapInfo info, uint usage, out IntPtr bits, IntPtr section, uint offset);

    [LibraryImport("gdi32.dll")]
    private static partial IntPtr SelectObject(IntPtr dc, IntPtr obj);

    [LibraryImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DeleteObject(IntPtr obj);

    [LibraryImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DeleteDC(IntPtr dc);

    [LibraryImport("gdi32.dll")]
    private static partial int SetStretchBltMode(IntPtr dc, int mode);

    [LibraryImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetBrushOrgEx(IntPtr dc, int x, int y, IntPtr previous);

    [LibraryImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool StretchBlt(IntPtr dest, int x, int y, int width, int height, IntPtr source, int sx, int sy, int sw, int sh, uint rop);

    [LibraryImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GdiFlush();
}
