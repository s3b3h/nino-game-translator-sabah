// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı.

using System.Collections.Concurrent;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CouchSubs.App.Services;

namespace CouchSubs.App.Controls;

/// <summary>
/// Yakalama kartının görüntüsünü gösteren yüzey (oyun penceresi ve rehberdeki önizleme).
/// <para>
/// Kart her kareyi okuma iş parçacığında bir arabelleğe yazar; WPF her ekran yenilemesinde (CompositionTarget.Rendering)
/// yalnız en son kareyi alır ve <see cref="WriteableBitmap"/>'e kopyalar. Geride kalan kare beklemez, atlanır; böylece
/// gecikme en çok bir yenileme (60 Hz'de ~17 ms) artı WPF'in çizimi kadardır ve kuyruk birikmez.
/// </para>
/// </summary>
public sealed class CardVideoSurface : Image, ICardVideoSink
{
    /// <summary>Okuma tarafının yazdığı son kare (arayüz alınca boşalır).</summary>
    private Buffer? latest;
    private readonly ConcurrentBag<Buffer> pool = [];
    private WriteableBitmap? bitmap;
    private bool rendering;

    public CardVideoSurface()
    {
        Stretch = Stretch.Uniform;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.Linear);
        // Görüntü aynalanmaz (Arapça arayüzde de).
        FlowDirection = FlowDirection.LeftToRight;
        Loaded += (_, _) => SetRendering(true);
        Unloaded += (_, _) => SetRendering(false);
    }

    /// <summary>Son kare ekranda kaldı mı (kart koptuğunda siyaha döner).</summary>
    public void Clear()
    {
        Interlocked.Exchange(ref latest, null);
        Source = null;
        bitmap = null;
    }

    public unsafe void Write(byte* bgra, int width, int height, int stride)
    {
        if (!pool.TryTake(out var buffer) || buffer.Width != width || buffer.Height != height)
            buffer = new Buffer(width, height);
        fixed (byte* target = buffer.Pixels)
        {
            var row = width * 4;
            for (var y = 0; y < height; y++)
                System.Buffer.MemoryCopy(bgra + (long)y * stride, target + (long)y * row, row, row);
        }
        // Arayüz önceki kareyi almadıysa o kare atlanır; arabellek yeniden kullanılır.
        if (Interlocked.Exchange(ref latest, buffer) is { } skipped) pool.Add(skipped);
    }

    private void SetRendering(bool on)
    {
        if (on == rendering) return;
        rendering = on;
        if (on) CompositionTarget.Rendering += OnRendering;
        else CompositionTarget.Rendering -= OnRendering;
    }

    private void OnRendering(object? sender, EventArgs e)
    {
        if (Interlocked.Exchange(ref latest, null) is not { } frame) return;
        try
        {
            if (bitmap is null || bitmap.PixelWidth != frame.Width || bitmap.PixelHeight != frame.Height)
            {
                // Bgr32: kartın saydamlık baytı yok sayılır (bazı kartlar 0 verir).
                bitmap = new WriteableBitmap(frame.Width, frame.Height, 96, 96, PixelFormats.Bgr32, null);
                Source = bitmap;
            }
            bitmap.WritePixels(new Int32Rect(0, 0, frame.Width, frame.Height), frame.Pixels, frame.Width * 4, 0);
        }
        finally
        {
            pool.Add(frame);
        }
    }

    private sealed class Buffer(int width, int height)
    {
        public int Width { get; } = width;
        public int Height { get; } = height;
        public byte[] Pixels { get; } = new byte[width * height * 4];
    }
}
