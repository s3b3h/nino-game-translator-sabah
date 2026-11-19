// SPDX-License-Identifier: AGPL-3.0-only

using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CouchSubs.Core;
using CouchSubs.RemotePlay;
using CouchSubs.Shell;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace CouchSubs.App.Services;

/// <summary>Receives Xbox WebRTC video in an off-screen WebView2 and passes decoded frames to the normal OCR pipeline.</summary>
internal sealed class XboxStreamSession(XboxBridge bridge, XboxConsole console, string token, Action<string> tokenUpdated, bool legacyFrameRate) : IStreamSession
{
    // Oynatıcı sayfası yalnız WebRTC el sıkışma komutlarını çağırabilir; giriş ve token dönen komutlar ona kapalı.
    private static readonly HashSet<string> PlayerCommands = ["sdp", "chatSdp", "ice", "keepalive"];
    private readonly CancellationTokenSource cancel = new();
    private string currentToken = token;
    private Window? window;
    private WebView2? browser;
    private TaskCompletionSource<bool>? browserEnded;
    private bool started;
    private int frameBusy;

    public event Action<Frame>? FrameReceived;
    public event Action<SessionState>? StateChanged;
    public event Action<RegisteredConsole>? ConsoleMoved { add { } remove { } }

    public void Start()
    {
        if (started) return;
        started = true;
        _ = RunAsync();
    }

    /// <summary>
    /// Ardışık yeniden denemelerin bekleme süreleri. Konsol "oyun başka yerde açıldı" deyip yayını keserse eskiden her
    /// 5 sn'de bir yeniden açılıyor, konsol uyarıyı yeniden veriyor ve oyun düşüyordu; üç denemeden sonra durulur.
    /// </summary>
    private static readonly int[] RetryDelaysMs = [5000, 15000, 45000];
    /// <summary>Yayın bu kadar ayakta kaldıysa sonraki kopma yeni bir dizi deneme başlatır.</summary>
    private const long HealthyStreamMs = 60_000;
    private long streamingSince;
    private string? endReason;

    private static void Log(string line) => SubtitleLog.Write("[Xbox] " + line);

    /// <summary>Oturum kimliğinin yalnız başı günlüğe yazılır.</summary>
    private static string Mask(string? value) => string.IsNullOrEmpty(value) ? "?" : value.Length <= 8 ? value : value[..8] + "…";

    /// <summary>Konsolun bildirdiği hata ayrıntısı; alan yoksa ya da tüm değerleri boşsa null.</summary>
    private static string? ErrorDetails(JsonElement status)
    {
        if (!status.TryGetProperty("errorDetails", out var details)) return null;
        return details.ValueKind switch
        {
            JsonValueKind.String => string.IsNullOrWhiteSpace(details.GetString()) ? null : details.GetString(),
            JsonValueKind.Object when details.EnumerateObject().Any(p => p.Value.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined)
                && !(p.Value.ValueKind == JsonValueKind.String && string.IsNullOrWhiteSpace(p.Value.GetString()))) => details.GetRawText(),
            _ => null,
        };
    }

    private async Task RunAsync()
    {
        Log($"konsol: id {console.Id}, ad {console.Name}, model {console.Model}");
        var failures = 0;
        while (!cancel.IsCancellationRequested)
        {
            string? reason = null;
            var permanent = false;
            try
            {
                StateChanged?.Invoke(SessionState.Connecting);
                await bridge.RestoreAsync(currentToken);
                var startedSession = await bridge.CallAsync("start", new { consoleId = console.Id });
                RememberToken(startedSession);
                Log($"play yanıtı: oturum {Mask(startedSession.TryGetProperty("sessionId", out var sid) ? sid.GetString() : null)}");
                string? lastState = null;
                for (var attempt = 0; attempt < 90 && !cancel.IsCancellationRequested; attempt++)
                {
                    var status = await bridge.CallAsync("status");
                    RememberToken(status);
                    var state = status.TryGetProperty("state", out var value) ? value.GetString() : null;
                    if (state != lastState) Log($"state: {lastState ?? "-"} → {state ?? "?"}");
                    lastState = state;
                    if (status.TryGetProperty("connected", out _)) Log("connect: başarılı");
                    var details = ErrorDetails(status);
                    if (details is not null) Log($"errorDetails: {details}");
                    if (state == "Provisioned") break;
                    if (state == "Failed" || details is not null)
                    {
                        // Konsol yayını kendisi reddetti: yeniden denemek konsolu yeniden tetikler.
                        permanent = true;
                        throw new InvalidOperationException(details ?? Localizer.Current["Couldn't start the Xbox stream"]);
                    }
                    if (attempt == 89) throw new TimeoutException(Localizer.Current["Timed out waiting for the Xbox stream to be ready."]);
                    await Task.Delay(1000, cancel.Token);
                }
                if (cancel.IsCancellationRequested) break;
                await OpenPlayerAsync();
                if (browserEnded is not null) await browserEnded.Task.WaitAsync(cancel.Token);
                if (!cancel.IsCancellationRequested) throw new IOException(endReason ?? Localizer.Current["The Xbox picture connection closed."]);
            }
            catch (OperationCanceledException) when (cancel.IsCancellationRequested) { break; }
            catch (Exception error)
            {
                reason = error.Message;
                Log($"kopma: {reason}");
            }
            finally
            {
                ClosePlayer();
                try { await bridge.CallAsync("stop"); } catch { /* A lost connection has no session to stop. */ }
            }
            if (cancel.IsCancellationRequested) break;
            // Yayın en az bir dakika sürdüyse bu kopma yeni bir dizinin ilkidir.
            var since = Interlocked.Exchange(ref streamingSince, 0);
            if (since != 0 && Environment.TickCount64 - since >= HealthyStreamMs) failures = 0;
            endReason = null;
            failures++;
            if (permanent || failures > RetryDelaysMs.Length)
            {
                Log(permanent ? "kalıcı hata: yeniden denenmiyor, yayın durdu" : $"{RetryDelaysMs.Length} deneme bitti: yeniden denenmiyor, yayın durdu");
                StateChanged?.Invoke(SessionState.Disconnected(DisconnectKind.Refused,
                    Localizer.Current.Format("The Xbox connection was lost: %@. Restart the Xbox to reconnect.", reason ?? "?")));
                break;
            }
            var delay = RetryDelaysMs[failures - 1];
            Log($"yeniden deneme {failures}/{RetryDelaysMs.Length}: {delay / 1000} sn sonra");
            StateChanged?.Invoke(SessionState.Disconnected(DisconnectKind.Other, reason));
            try { await Task.Delay(delay, cancel.Token); }
            catch (OperationCanceledException) { break; }
        }
    }

    private async Task OpenPlayerAsync()
    {
        var folder = Path.Combine(AppContext.BaseDirectory, "xbox-bridge");
        if (!File.Exists(Path.Combine(folder, "player.html"))) throw new FileNotFoundException(Localizer.Current["The Xbox player is missing."]);
        browser = new WebView2();
        window = new Window
        {
            Content = browser, Width = 1280, Height = 720, Left = -10000, Top = -10000,
            WindowStartupLocation = WindowStartupLocation.Manual, WindowStyle = WindowStyle.None,
            ShowInTaskbar = false, ShowActivated = false, ResizeMode = ResizeMode.NoResize,
            Title = "Nino Xbox reader",
        };
        browserEnded = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        window.Closed += (_, _) => browserEnded?.TrySetResult(true);
        window.Show();
        var profile = Path.Combine(AppPaths.Data, "xbox-webview");
        var options = new CoreWebView2EnvironmentOptions("--disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows");
        var environment = await CoreWebView2Environment.CreateAsync(null, profile, options);
        await browser.EnsureCoreWebView2Async(environment);
        browser.CoreWebView2.Settings.IsStatusBarEnabled = false;
        browser.CoreWebView2.Settings.AreDevToolsEnabled = false;
        browser.CoreWebView2.SetVirtualHostNameToFolderMapping("couchsubs-xbox.local", folder, CoreWebView2HostResourceAccessKind.DenyCors);
        browser.CoreWebView2.WebMessageReceived += OnMessage;
        browser.CoreWebView2.NavigationCompleted += (_, result) =>
        {
            try
            {
                if (result.IsSuccess) browser?.CoreWebView2?.PostWebMessageAsJson(JsonSerializer.Serialize(new { kind = "start", legacyFrameRate }));
                else browserEnded?.TrySetResult(true);
            }
            catch { browserEnded?.TrySetResult(true); }
        };
        browser.CoreWebView2.Navigate("https://couchsubs-xbox.local/player.html");
    }

    private async void OnMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs eventArgs)
    {
        try
        {
            using var document = JsonDocument.Parse(eventArgs.WebMessageAsJson);
            var message = document.RootElement;
            switch (message.GetProperty("kind").GetString())
            {
                case "frame":
                    if (Interlocked.Exchange(ref frameBusy, 1) != 0) return;
                    OfferFrame(message.GetProperty("image").GetString()!);
                    break;
                case "state":
                    var state = message.GetProperty("state").GetString();
                    if (state == "connected")
                    {
                        Log("WebRTC bağlandı");
                        Interlocked.CompareExchange(ref streamingSince, Environment.TickCount64, 0);
                        StateChanged?.Invoke(SessionState.Streaming);
                    }
                    else if (state is "closed" or "failed" or "error")
                    {
                        var detail = message.TryGetProperty("detail", out var value) ? value.GetString() : Localizer.Current["The Xbox WebRTC connection was lost"];
                        Log($"WebRTC {state}: {detail}");
                        endReason ??= detail;
                        browserEnded?.TrySetResult(true);
                    }
                    break;
                case "rpc":
                    var id = message.GetProperty("id").GetInt32();
                    var command = message.GetProperty("command").GetString()!;
                    if (!PlayerCommands.Contains(command))
                    {
                        browser?.CoreWebView2?.PostWebMessageAsJson(JsonSerializer.Serialize(new { kind = "reply", id, error = Localizer.Current["This command isn't allowed."] }));
                        break;
                    }
                    var args = message.TryGetProperty("args", out var parameters) ? (object)parameters.Clone() : null;
                    try
                    {
                        var result = await bridge.CallAsync(command, args);
                        browser?.CoreWebView2?.PostWebMessageAsJson(JsonSerializer.Serialize(new { kind = "reply", id, value = result }));
                    }
                    catch (Exception error)
                    {
                        browser?.CoreWebView2?.PostWebMessageAsJson(JsonSerializer.Serialize(new { kind = "reply", id, error = error.Message }));
                    }
                    break;
            }
        }
        catch (Exception error)
        {
            StateChanged?.Invoke(SessionState.Disconnected(DisconnectKind.Other, error.Message));
            browserEnded?.TrySetResult(true);
        }
    }

    /// <summary>
    /// Kare arayüz iş parçacığında değil, PS5'teki gibi kare iş parçacığında çözülür ve okuma hattına verilir. Önceden
    /// çözme ve okuma hattına giriş arayüz iş parçacığındaydı: <c>frameBusy</c> hiç dolu görünmüyordu, arayüz
    /// yavaşlayınca kareler WebView2 ileti kuyruğunda birikiyor, saniyeler önceki kare okunuyordu. Bitince oynatıcıya
    /// haber verilir; oynatıcı ancak o zaman yeni kare gönderir.
    /// </summary>
    private void OfferFrame(string data)
    {
        var view = browser;
        _ = Task.Run(() =>
        {
            try
            {
                var comma = data.IndexOf(',');
                if (comma >= 0) FrameReceived?.Invoke(DecodeJpeg(Convert.FromBase64String(data[(comma + 1)..])));
            }
            catch
            {
                // Tek bir karenin çözülememesi akışı durdurmaz; sonraki kare okunur.
            }
            finally
            {
                Volatile.Write(ref frameBusy, 0);
                view?.Dispatcher.InvokeAsync(() =>
                {
                    try { if (browser == view) view.CoreWebView2?.PostWebMessageAsJson("{\"kind\":\"frameDone\"}"); }
                    catch { /* Oynatıcı bu arada kapandı. */ }
                });
            }
        });
    }

    private static Frame DecodeJpeg(byte[] bytes)
    {
        using var input = new MemoryStream(bytes);
        var source = new JpegBitmapDecoder(input, BitmapCreateOptions.None, BitmapCacheOption.OnLoad).Frames[0];
        var converted = new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        var stride = converted.PixelWidth * 4;
        var pixels = new byte[stride * converted.PixelHeight];
        converted.CopyPixels(pixels, stride, 0);
        return new Frame(pixels, converted.PixelWidth, converted.PixelHeight, stride);
    }

    private void RememberToken(JsonElement result)
    {
        if (!result.TryGetProperty("userToken", out var refreshed)) return;
        currentToken = refreshed.GetRawText();
        tokenUpdated(currentToken);
    }

    private void ClosePlayer()
    {
        browserEnded?.TrySetResult(true);
        browserEnded = null;
        window?.Close();
        browser?.Dispose();
        window = null;
        browser = null;
    }

    public void Stop()
    {
        if (cancel.IsCancellationRequested) return;
        cancel.Cancel();
        ClosePlayer();
        StateChanged?.Invoke(SessionState.Disconnected(DisconnectKind.Stopped));
    }

    public void ReconnectNow()
    {
        if (!cancel.IsCancellationRequested) browserEnded?.TrySetResult(true);
    }

    public void Dispose()
    {
        Stop();
    }
}
