// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı (Mac: CaptureCardStream.swift).

using System.Windows;
using System.Windows.Threading;
using CouchSubs.App.Views;
using CouchSubs.Core;
using CouchSubs.RemotePlay;
using CouchSubs.Shell;

namespace CouchSubs.App.Services;

/// <summary>
/// Yakalama kartından okunan görüntüyü PS5 bağlantısıyla aynı arayüzle verir; okuma hattı farkı bilmez. İki kullanım var:
/// <list type="bullet">
/// <item>PS5 → kart (geçişli) → TV: oyun TV'de, altyazı TV uygulamasında. Bilgisayar yalnız okur.</item>
/// <item>PS5 → kart → bilgisayar → ekran: Nino oyunu tam ekran gösterir, sesini çalar, altyazı üstünde
/// (<paramref name="showsPlayer"/> açık).</item>
/// </list>
/// </summary>
public sealed class CaptureCardStream(bool showsPlayer, string? preferredId) : ICaptureCardStream
{
    public event Action<Frame>? FrameReceived;
    public event Action<SessionState>? StateChanged;
    public event Action<RegisteredConsole>? ConsoleMoved { add { } remove { } }
    public event Action<CaptureCardStatus>? CardStatusChanged;
    public event Action<ScreenArea?>? GameAreaChanged;
    public event Action? PlayerClosed;

    private readonly CaptureCardCapture capture = new() { PreferredId = preferredId, PlaysAudio = showsPlayer };
    private readonly Dispatcher dispatcher = Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher;
    private CaptureCardPlayerWindow? player;
    private volatile bool stopped;

    public void Start()
    {
        capture.FrameReceived += frame =>
        {
            if (!stopped) FrameReceived?.Invoke(frame);
        };
        capture.StatusChanged += status =>
        {
            if (stopped) return;
            CardStatusChanged?.Invoke(status);
            StateChanged?.Invoke(CaptureCardRules.SessionState(status));
        };
        if (showsPlayer)
        {
            // Pencere kart açılmadan önce kurulur: ilk kareden itibaren ekranda görünsün.
            dispatcher.Invoke(() =>
            {
                var window = new CaptureCardPlayerWindow();
                window.GameAreaChanged += area =>
                {
                    if (!stopped) GameAreaChanged?.Invoke(area);
                };
                window.UserClosed += () =>
                {
                    capture.VideoSink = null;
                    player = null;
                    if (!stopped) PlayerClosed?.Invoke();
                };
                capture.VideoSink = window.Surface;
                player = window;
                window.ShowFullScreen();
            });
        }
        capture.Start();
    }

    /// <summary>Bloklamaz; kart arka planda bırakılır, pencere kapanır.</summary>
    public void Stop()
    {
        if (stopped) return;
        stopped = true;
        capture.VideoSink = null;
        capture.Stop();
        dispatcher.BeginInvoke(() =>
        {
            player?.CloseQuietly();
            player = null;
        });
    }

    public void ReconnectNow() => capture.Refresh();

    public void ToggleFullScreen() => dispatcher.BeginInvoke(() => player?.ToggleFullScreen());

    public void Dispose() => Stop();
}
