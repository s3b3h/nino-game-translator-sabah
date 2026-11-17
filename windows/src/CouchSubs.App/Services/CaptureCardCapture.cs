// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı (Mac: CaptureCardCapture.swift). Yalnız Windows'un kendi API'lerini
// (Windows.Media.Capture, Windows.Media.Audio) kullanır.

using System.Diagnostics;
using System.Runtime.InteropServices;
using CouchSubs.Core;
using CouchSubs.Shell;
using Windows.Devices.Enumeration;
using Windows.Graphics.Imaging;
using Windows.Media;
using Windows.Media.Audio;
using Windows.Media.Capture;
using Windows.Media.Capture.Frames;
using Windows.Media.MediaProperties;
using Windows.Media.Render;
using WinRT;

namespace CouchSubs.App.Services;

/// <summary>Kartın görüntüsünü ekranda gösteren yüzey (oyun penceresi ve rehberdeki önizleme).</summary>
public interface ICardVideoSink
{
    /// <summary>Kartın her karesi (saniyede 60'a kadar), okuma iş parçacığında. Veri yalnız çağrı süresince geçerlidir.</summary>
    unsafe void Write(byte* bgra, int width, int height, int stride);
}

/// <summary>
/// Bilgisayara takılı HDMI yakalama kartından görüntüyü (ve istenirse sesi) okur. Kartlar Windows'ta kamera gibi görünür
/// (UVC); <see cref="MediaCapture"/> ile tek bir okuyucu açılır ve karesi iki yere dağıtılır:
/// <list type="bullet">
/// <item>Ekrandaki yüzeye (<see cref="VideoSink"/>) kartın tam hızında; oyun bu bilgisayarda gösteriliyorsa gecikme az kalsın.</item>
/// <item>Okuma hattına (<see cref="FrameReceived"/>) PS5 yolundaki boyda (1920 × 1080) ve saniyede 10 kez, kopya olarak.</item>
/// </list>
/// Kart çıkarılıp takılınca (DeviceWatcher) ya da okuma koparsa kendiliğinden yeniden bağlanır. Kart başka bir uygulamada
/// (ya da rehberin önizlemesinde) açıksa birkaç saniyede bir yeniden denenir.
/// </summary>
public sealed class CaptureCardCapture : IDisposable
{
    /// <summary>Okuma hattına giden kare (saniyede 10); herhangi bir iş parçacığından.</summary>
    public event Action<Frame>? FrameReceived;
    /// <summary>Kartın durumu; herhangi bir iş parçacığından.</summary>
    public event Action<CaptureCardStatus>? StatusChanged;
    /// <summary>Takılı görüntü aygıtları değişti (ayarlardaki seçici yenilensin); herhangi bir iş parçacığından.</summary>
    public event Action? DevicesChanged;

    /// <summary>Kullanıcının seçtiği aygıt (yoksa kendiliğinden seçilir). Değişince <see cref="Refresh"/> çağrılmalı.</summary>
    public string? PreferredId { get; set; }
    /// <summary>Oyunun sesi bu bilgisayardan çalınsın mı (oyun bu bilgisayarda gösteriliyorsa; başlamadan önce ayarlanır).</summary>
    public bool PlaysAudio { get; set; }
    /// <summary>Kartın görüntüsünü gösteren yüzey (yoksa yalnız okuma hattına verilir).</summary>
    public ICardVideoSink? VideoSink { get => sink; set => sink = value; }

    public CaptureCardStatus Status { get { lock (gate) return status; } }

    private const string ContainerKey = "System.Devices.ContainerId";
    /// <summary>Açılamayan kart bu kadar sonra yeniden denenir (başka uygulama bırakmış olabilir).</summary>
    private static readonly TimeSpan RetryAfter = TimeSpan.FromSeconds(3);

    private readonly object gate = new();
    private readonly SemaphoreSlim connecting = new(1, 1);
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly BlackPictureWatch blackWatch = new();
    private volatile ICardVideoSink? sink;
    private volatile bool running;
    /// <summary>Her başlatma ve bağlantı yeni bir kuşaktır; eski kuşağın geç olayları yok sayılır.</summary>
    private int generation;
    private CaptureCardStatus status = CaptureCardStatus.Stopped;
    private DeviceWatcher? watcher;
    private Timer? kick;
    private MediaCapture? capture;
    private MediaFrameReader? reader;
    private AudioGraph? audio;
    private CaptureCardInfo? current;
    private double lastEmit = double.NegativeInfinity;
    private int busy;
    /// <summary>Kart bu kadar saniye hiç kare vermezse okuyucu takılmış sayılır ve kart yeniden açılır. Kart sinyali
    /// yeniden kurunca (oyun duraklatılıp uzun süre beklenince, PS5 çözünürlüğü değişince) ses akarken görüntü donabiliyor.</summary>
    private const double StallSeconds = 3;
    /// <summary>Takılan kart en fazla bu aralıkla yeniden denenir (sinyal yokken sesi sürekli kesmemek için).</summary>
    private const double MaxRetrySeconds = 30;
    private Timer? stallTimer;
    private double lastFrameAt;
    private double lastRestartAt = double.NegativeInfinity;
    private double retryGap = StallSeconds;

    public void Start()
    {
        lock (gate)
        {
            if (running) return;
            running = true;
            generation++;
        }
        try
        {
            var deviceWatcher = DeviceInformation.CreateWatcher(DeviceClass.VideoCapture);
            deviceWatcher.Added += (_, _) => DevicesMoved();
            deviceWatcher.Removed += (_, _) => DevicesMoved();
            deviceWatcher.Start();
            watcher = deviceWatcher;
        }
        catch (Exception error)
        {
            SubtitleLog.Write($"yakalama kartı: aygıt izleyici açılamadı: {error.GetType().Name}: {error.Message}");
        }
        Kick(TimeSpan.Zero);
        lock (gate) stallTimer = new Timer(_ => CheckStall(), null, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(1));
    }

    private void CheckStall()
    {
        var now = clock.Elapsed.TotalSeconds;
        lock (gate)
        {
            if (!running || current is null || reader is null) return;
            var quiet = now - Volatile.Read(ref lastFrameAt);
            if (quiet < StallSeconds)
            {
                retryGap = StallSeconds;
                return;
            }
            if (now - lastRestartAt < retryGap) return;
            lastRestartAt = now;
            retryGap = Math.Min(retryGap * 2, MaxRetrySeconds);
            SubtitleLog.Write($"yakalama kartı {quiet:0} sn kare vermedi; yeniden açılıyor");
        }
        Refresh();
    }

    /// <summary>Bloklamaz; kart arka planda bırakılır. Durduktan sonra hiçbir olay gönderilmez.</summary>
    public void Stop()
    {
        lock (gate)
        {
            if (!running) return;
            running = false;
            generation++;
            kick?.Dispose();
            kick = null;
            stallTimer?.Dispose();
            stallTimer = null;
            status = CaptureCardStatus.Stopped;
        }
        var deviceWatcher = watcher;
        watcher = null;
        try
        {
            if (deviceWatcher?.Status is DeviceWatcherStatus.Started or DeviceWatcherStatus.EnumerationCompleted) deviceWatcher.Stop();
        }
        catch { /* izleyici zaten durmuş */ }
        _ = Task.Run(async () =>
        {
            await connecting.WaitAsync();
            try { await TearDownAsync(); }
            finally { connecting.Release(); }
        });
    }

    /// <summary>Kartı yeniden arar (ör. bilgisayar uykudan uyandı ya da başka bir aygıt seçildi).</summary>
    public void Refresh()
    {
        lock (gate) current = null;
        Kick(TimeSpan.Zero, reopen: true);
    }

    public void Dispose() => Stop();

    /// <summary>Takılı görüntü aygıtları (ayarlardaki seçici için).</summary>
    public static async Task<IReadOnlyList<CaptureCardInfo>> VideoDevicesAsync()
    {
        try
        {
            var devices = await DeviceInformation.FindAllAsync(DeviceInformation.GetAqsFilterFromDeviceClass(DeviceClass.VideoCapture), [ContainerKey]);
            return [.. devices.Where(d => d.IsEnabled).Select(Info)];
        }
        catch (Exception error)
        {
            SubtitleLog.Write($"yakalama kartı: aygıtlar listelenemedi: {error.GetType().Name}: {error.Message}");
            return [];
        }
    }

    private static CaptureCardInfo Info(DeviceInformation device) =>
        new(device.Id, device.Name, device.Properties.TryGetValue(ContainerKey, out var group) && group is not null ? group.ToString() ?? "" : "");

    // MARK: Bağlantı

    private void DevicesMoved()
    {
        DevicesChanged?.Invoke();
        // Takma çıkarma olayları art arda gelir; kısa bir beklemeyle bir kez bakılır.
        Kick(TimeSpan.FromMilliseconds(700));
    }

    private void Kick(TimeSpan after, bool reopen = false)
    {
        lock (gate)
        {
            if (!running) return;
            var stamp = generation;
            kick?.Dispose();
            kick = new Timer(_ => _ = ConnectAsync(stamp, reopen), null, after, Timeout.InfiniteTimeSpan);
        }
    }

    private bool Current(int stamp)
    {
        lock (gate) return running && stamp == generation;
    }

    private async Task ConnectAsync(int stamp, bool reopen)
    {
        await connecting.WaitAsync();
        try
        {
            if (!Current(stamp)) return;
            var devices = await VideoDevicesAsync();
            var picked = CaptureCardPicker.Pick(devices, PreferredId);
            if (picked is null)
            {
                await TearDownAsync();
                Report(stamp, CaptureCardStatus.NoCard);
                return;
            }
            // Aynı kart zaten okunuyorsa (başka bir aygıt takıldı ya da çıkarıldı) bir şey yapılmaz.
            CaptureCardInfo? open;
            lock (gate) open = current;
            if (!reopen && open?.Id == picked.Id && reader is not null) return;
            await TearDownAsync();
            if (!Current(stamp)) return;
            await OpenAsync(picked, stamp);
        }
        catch (UnauthorizedAccessException)
        {
            // Windows'un kamera izni kapalı (Ayarlar › Gizlilik ve güvenlik › Kamera). İzin açılınca yeniden denensin.
            await TearDownAsync();
            Report(stamp, CaptureCardStatus.NeedsPermission);
            Retry(stamp, TimeSpan.FromSeconds(5));
        }
        catch (Exception error)
        {
            // Çoğunlukla kart başka bir uygulamada (OBS, kartın kendi programı ya da rehberin önizlemesi) açık.
            SubtitleLog.Write($"yakalama kartı açılamadı: {error.GetType().Name}: 0x{error.HResult:X8} {error.Message}");
            await TearDownAsync();
            if (Status.State is not (CaptureCardState.Capturing or CaptureCardState.BlackPicture)) Report(stamp, CaptureCardStatus.NoCard);
            Retry(stamp, RetryAfter);
        }
        finally
        {
            connecting.Release();
        }
    }

    private void Retry(int stamp, TimeSpan after)
    {
        if (Current(stamp)) Kick(after);
    }

    private async Task OpenAsync(CaptureCardInfo card, int stamp)
    {
        var media = new MediaCapture();
        lock (gate) capture = media;
        await media.InitializeAsync(new MediaCaptureInitializationSettings
        {
            VideoDeviceId = card.Id,
            StreamingCaptureMode = StreamingCaptureMode.Video,
            // Kareler işlemci belleğinde gelsin (pikseller doğrudan kopyalanır).
            MemoryPreference = MediaCaptureMemoryPreference.Cpu,
            SharingMode = MediaCaptureSharingMode.ExclusiveControl,
        });
        media.Failed += (_, e) =>
        {
            SubtitleLog.Write($"yakalama kartı koptu: 0x{e.Code:X8} {e.Message}");
            lock (gate) current = null;
            Retry(stamp, TimeSpan.FromSeconds(1));
        };
        var source = media.FrameSources.Values
            .Where(s => s.Info.SourceKind == MediaFrameSourceKind.Color)
            .OrderByDescending(s => s.Info.MediaStreamType == MediaStreamType.VideoRecord)
            .FirstOrDefault() ?? throw new InvalidOperationException("kartta görüntü kaynağı yok");
        var formats = source.SupportedFormats.ToList();
        var choice = CaptureCardRules.PickFormat(formats.Select(Describe));
        if (choice is not null && formats.FirstOrDefault(f => Describe(f) == choice) is { } format)
        {
            try { await source.SetFormatAsync(format); }
            catch (Exception error) { SubtitleLog.Write($"yakalama kartı biçimi seçilemedi ({choice}): {error.Message}"); }
        }
        // Windows görüntüyü istenen boya ve BGRA'ya kendisi çevirir (çoğunlukla ekran kartıyla).
        var frameReader = await media.CreateFrameReaderAsync(source, MediaEncodingSubtypes.Bgra8,
            new BitmapSize { Width = CaptureCardRules.OutputWidth, Height = CaptureCardRules.OutputHeight });
        frameReader.AcquisitionMode = MediaFrameReaderAcquisitionMode.Realtime;
        frameReader.FrameArrived += (sender, _) => OnFrame(sender, stamp, card);
        var started = await frameReader.StartAsync();
        if (started != MediaFrameReaderStartStatus.Success)
        {
            frameReader.Dispose();
            throw new InvalidOperationException($"kart okunamadı: {started}");
        }
        lock (gate)
        {
            reader = frameReader;
            current = card;
        }
        blackWatch.Reset();
        lastEmit = double.NegativeInfinity;
        Volatile.Write(ref lastFrameAt, clock.Elapsed.TotalSeconds);
        SubtitleLog.Write($"yakalama kartı açıldı: {card.Name}, {(choice is null ? "varsayılan biçim" : $"{choice.Width}×{choice.Height} {choice.FramesPerSecond:0.#} fps {choice.Subtype}")}");
        Report(stamp, CaptureCardStatus.Capturing(card.Name));
        if (PlaysAudio) await StartAudioAsync(card, stamp);
    }

    private static CardVideoFormat Describe(MediaFrameFormat format)
    {
        var rate = format.FrameRate is { Denominator: > 0 } r ? (double)r.Numerator / r.Denominator : 0;
        return new CardVideoFormat((int)(format.VideoFormat?.Width ?? 0), (int)(format.VideoFormat?.Height ?? 0), rate, format.Subtype ?? "");
    }

    /// <summary>
    /// Kartın sesini bu bilgisayarın hoparlöründen çalar (AudioGraph: kartın ses girişi → varsayılan çıkış, en düşük
    /// gecikme). Ses açılamazsa (mikrofon izni kapalı, ses aygıtı yok) görüntü yine okunur.
    /// </summary>
    private async Task StartAudioAsync(CaptureCardInfo card, int stamp)
    {
        try
        {
            var devices = await DeviceInformation.FindAllAsync(DeviceInformation.GetAqsFilterFromDeviceClass(DeviceClass.AudioCapture), [ContainerKey]);
            var infos = devices.Select(Info).ToList();
            if (CaptureCardPicker.Audio(card, infos) is not { } match || devices.FirstOrDefault(d => d.Id == match.Id) is not { } device)
            {
                SubtitleLog.Write("yakalama kartı: ses aygıtı bulunamadı; ses çalınmıyor");
                return;
            }
            var created = await AudioGraph.CreateAsync(new AudioGraphSettings(AudioRenderCategory.GameMedia)
            {
                QuantumSizeSelectionMode = QuantumSizeSelectionMode.LowestLatency,
            });
            if (created.Status != AudioGraphCreationStatus.Success)
            {
                SubtitleLog.Write($"yakalama kartı: ses açılamadı ({created.Status})");
                return;
            }
            var graph = created.Graph;
            var output = await graph.CreateDeviceOutputNodeAsync();
            var input = await graph.CreateDeviceInputNodeAsync(MediaCategory.Media, graph.EncodingProperties, device);
            if (output.Status != AudioDeviceNodeCreationStatus.Success || input.Status != AudioDeviceNodeCreationStatus.Success)
            {
                // AccessDenied: Windows'un mikrofon izni kapalı (kartın sesi Windows'ta mikrofon gibi görünür).
                SubtitleLog.Write($"yakalama kartı: ses bağlanamadı (giriş {input.Status}, çıkış {output.Status})");
                graph.Dispose();
                return;
            }
            input.DeviceInputNode.AddOutgoingConnection(output.DeviceOutputNode);
            if (!Current(stamp))
            {
                graph.Dispose();
                return;
            }
            graph.Start();
            lock (gate) audio = graph;
            SubtitleLog.Write($"yakalama kartı: ses çalınıyor ({device.Name})");
        }
        catch (Exception error)
        {
            SubtitleLog.Write($"yakalama kartı: ses açılamadı: {error.GetType().Name}: {error.Message}");
        }
    }

    private async Task TearDownAsync()
    {
        MediaFrameReader? oldReader;
        MediaCapture? oldCapture;
        AudioGraph? oldAudio;
        lock (gate)
        {
            (oldReader, oldCapture, oldAudio) = (reader, capture, audio);
            (reader, capture, audio, current) = (null, null, null, null);
        }
        try { oldAudio?.Stop(); } catch { /* ses zaten durmuş */ }
        oldAudio?.Dispose();
        if (oldReader is not null)
        {
            try { await oldReader.StopAsync(); } catch { /* okuyucu zaten durmuş */ }
            oldReader.Dispose();
        }
        oldCapture?.Dispose();
    }

    private void Report(int stamp, CaptureCardStatus next)
    {
        lock (gate)
        {
            if (!running || stamp != generation || status == next) return;
            status = next;
        }
        StatusChanged?.Invoke(next);
    }

    // MARK: Kare

    private void OnFrame(MediaFrameReader sender, int stamp, CaptureCardInfo card)
    {
        Volatile.Write(ref lastFrameAt, clock.Elapsed.TotalSeconds);
        // Önceki kare hâlâ işleniyorsa (ekran ya da okuma hattı yavaşsa) yenisi atlanır; birikme olmaz.
        if (Interlocked.Exchange(ref busy, 1) == 1) return;
        try
        {
            if (!Current(stamp)) return;
            using var frame = sender.TryAcquireLatestFrame();
            var bitmap = frame?.VideoMediaFrame?.SoftwareBitmap;
            if (bitmap is null) return;
            SoftwareBitmap? converted = null;
            try
            {
                if (bitmap.BitmapPixelFormat != BitmapPixelFormat.Bgra8)
                    bitmap = converted = SoftwareBitmap.Convert(bitmap, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore);
                Deliver(bitmap, stamp, card);
            }
            finally
            {
                converted?.Dispose();
            }
        }
        catch (Exception error)
        {
            SubtitleLog.Write($"yakalama kartı karesi okunamadı: {error.GetType().Name}: {error.Message}");
        }
        finally
        {
            Volatile.Write(ref busy, 0);
        }
    }

    private unsafe void Deliver(SoftwareBitmap bitmap, int stamp, CaptureCardInfo card)
    {
        using var buffer = bitmap.LockBuffer(BitmapBufferAccessMode.Read);
        var plane = buffer.GetPlaneDescription(0);
        using var reference = buffer.CreateReference();
        reference.As<IMemoryBufferByteAccess>().GetBuffer(out var data, out var capacity);
        if (data is null) return;
        var pixels = data + plane.StartIndex;
        int width = plane.Width, height = plane.Height, stride = plane.Stride;
        if (width <= 0 || height <= 0 || (long)stride * height > capacity - plane.StartIndex) return;

        sink?.Write(pixels, width, height, stride);

        var now = clock.Elapsed.TotalSeconds;
        if (!CaptureCardRules.DueForPipeline(now, lastEmit)) return;
        lastEmit = now;
        var span = new ReadOnlySpan<byte>(pixels, stride * height);
        var black = blackWatch.Update(BlackFrame.IsBlack(span, width, height, stride), now);
        Report(stamp, black ? CaptureCardStatus.BlackPicture(card.Name) : CaptureCardStatus.Capturing(card.Name));
        if (FrameReceived is { } received) received(ToFrame(pixels, width, height, stride));
    }

    /// <summary>Kare okuma hattının beklediği 1920 × 1080'e kopyalanır (Windows ölçeklemediyse en yakın komşuyla).</summary>
    private static unsafe Frame ToFrame(byte* pixels, int width, int height, int stride)
    {
        const int W = CaptureCardRules.OutputWidth, H = CaptureCardRules.OutputHeight;
        if (width == W && height == H) return Frame.Copy((IntPtr)pixels, width, height, stride);
        var result = Frame.Blank(W, H);
        fixed (byte* target = result.Pixels)
        {
            var columns = new int[W];
            for (var x = 0; x < W; x++) columns[x] = Math.Min(width - 1, x * width / W) * 4;
            for (var y = 0; y < H; y++)
            {
                var from = pixels + (long)Math.Min(height - 1, y * height / H) * stride;
                var to = (uint*)(target + (long)y * W * 4);
                for (var x = 0; x < W; x++) to[x] = *(uint*)(from + columns[x]);
            }
        }
        return result;
    }

    /// <summary>WinRT bellek arabelleğinin ham baytları (Windows'un kendi COM arayüzü).</summary>
    [ComImport]
    [Guid("5B0D3235-4DBA-4D44-865E-8F1D0E4FD04D")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private unsafe interface IMemoryBufferByteAccess
    {
        void GetBuffer(out byte* buffer, out uint capacity);
    }
}
