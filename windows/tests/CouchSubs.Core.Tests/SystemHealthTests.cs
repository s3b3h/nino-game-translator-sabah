// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>Sistem sağlığı ölçümü (Mac'teki SystemHealthTests ile aynı durumlar).</summary>
public class SystemHealthTests
{
    private sealed class Clock
    {
        public DateTime Time = new(2026, 11, 15, 12, 0, 0, DateTimeKind.Utc);
        public void Advance(double seconds) => Time = Time.AddSeconds(seconds);
    }

    private static HealthRecorder Recorder(Clock clock) => new(() => clock.Time);

    [Fact]
    public void NothingMeasuredBeforeTranslationStarts()
    {
        var s = new HealthRecorder().Snapshot();
        Assert.True(s.IsEmpty);
        Assert.Equal(HealthLevel.Unknown, HealthReport.Stream(s));
        Assert.Equal(HealthLevel.Unknown, HealthReport.Connection(s));
        Assert.Equal(HealthLevel.Unknown, HealthReport.Translation(s));
    }

    [Fact]
    public void LossyWifiStreamIsAProblemAndBlamesWifi()
    {
        var clock = new Clock();
        var health = Recorder(clock);
        health.SessionStarted();
        health.Connecting();
        health.Streaming();
        for (var i = 0; i < 1400; i++) health.RemotePlayLine("[chiaki info] Takion Send Buffer re-sending packet with seqnum 0xb5f23702, tries: 5");
        for (var i = 0; i < 300; i++) health.RemotePlayLine("[chiaki error] Takion Send Buffer overflow");
        for (var i = 0; i < 5; i++)
        {
            health.RemotePlayLine("[chiaki warning] FEC failed, waiting for IDR frame");
            health.RemotePlayLine("[chiaki info] Received IDR frame");
        }
        clock.Advance(60);
        var s = health.Snapshot();
        Assert.Equal(1400, s.Resends);
        Assert.Equal(300, s.Overflows);
        Assert.Equal(5, s.Stalls);
        Assert.Equal(HealthLevel.Problem, HealthReport.Stream(s));
        Assert.Equal(HealthLevel.Problem, HealthReport.Network(NetworkKind.Wifi, HealthLevel.Problem));
        Assert.Equal(HealthLevel.Good, HealthReport.Network(NetworkKind.Wired, HealthLevel.Problem));
    }

    [Fact]
    public void HealthyWiredStreamIsGood()
    {
        var clock = new Clock();
        var health = Recorder(clock);
        health.SessionStarted();
        health.Streaming();
        for (var i = 0; i < 20; i++) health.RemotePlayLine("[chiaki warning] StreamConnection reporting corrupt frame(s) from 1 to 2");
        health.RemotePlayLine("[chiaki warning] Video FEC failure");
        clock.Advance(120);
        var s = health.Snapshot();
        Assert.Equal(20, s.CorruptFrames);
        Assert.Equal(HealthLevel.Good, HealthReport.Stream(s));
        Assert.Equal(HealthLevel.Good, HealthReport.Network(NetworkKind.Wifi, HealthLevel.Good));
    }

    [Fact]
    public void WifiIsNotGreenBeforeThePictureIsMeasured()
    {
        Assert.Equal(HealthLevel.Unknown, HealthReport.Network(NetworkKind.Wifi, HealthLevel.Unknown));
        Assert.Equal(HealthLevel.Good, HealthReport.Network(NetworkKind.Wired, HealthLevel.Unknown));
        Assert.Equal(HealthLevel.Problem, HealthReport.Network(NetworkKind.Offline, HealthLevel.Unknown));
    }

    [Fact]
    public void OneStallPerFreezeUntilKeyFrameArrives()
    {
        var health = new HealthRecorder();
        health.SessionStarted();
        health.RemotePlayLine("[chiaki warning] FEC failed, waiting for IDR frame");
        health.RemotePlayLine("[chiaki warning] Video FEC failure");
        health.RemotePlayLine("[chiaki warning] FEC failed, waiting for IDR frame");
        Assert.Equal(1, health.Snapshot().Stalls);
        health.RemotePlayLine("[chiaki info] Received IDR frame");
        health.RemotePlayLine("[chiaki warning] FEC failed, waiting for IDR frame");
        Assert.Equal(2, health.Snapshot().Stalls);
    }

    [Fact]
    public void RatesWaitForEnoughStreaming()
    {
        var clock = new Clock();
        var health = Recorder(clock);
        health.SessionStarted();
        health.Streaming();
        health.RemotePlayLine("FEC failed");
        clock.Advance(5);
        Assert.Null(health.Snapshot().StallsPerMinute);
        Assert.Equal(HealthLevel.Unknown, HealthReport.Stream(health.Snapshot()));
    }

    [Fact]
    public void StreamingTimeOnlyCountsWhilePictureArrives()
    {
        var clock = new Clock();
        var health = Recorder(clock);
        health.SessionStarted();
        health.Connecting();
        clock.Advance(100);
        health.Streaming();
        clock.Advance(60);
        health.Disconnected("Network");
        clock.Advance(100);
        var s = health.Snapshot();
        Assert.Equal(60, s.StreamingSeconds, 3);
        Assert.Equal(1, s.Drops);
        Assert.Equal("Network", s.LastDisconnect);
    }

    [Fact]
    public void NeverConnectingIsAProblem()
    {
        var health = new HealthRecorder();
        health.SessionStarted();
        health.Connecting();
        health.Disconnected("NotFound");
        health.Connecting();
        health.Disconnected("NotFound");
        var s = health.Snapshot();
        Assert.Equal(HealthLevel.Problem, HealthReport.Connection(s));
        Assert.Equal(0, s.Drops);
    }

    [Fact]
    public void FrequentDropsWarnAndUserStopIsNotADrop()
    {
        var health = new HealthRecorder();
        health.SessionStarted();
        for (var i = 0; i < 3; i++)
        {
            health.Connecting();
            health.Streaming();
            health.Disconnected("Network");
        }
        Assert.Equal(HealthLevel.Warning, HealthReport.Connection(health.Snapshot()));
        health.Streaming();
        health.Disconnected(null);
        Assert.Equal(3, health.Snapshot().Drops);
    }

    [Fact]
    public void TranslationTimeUsesMedianAndIgnoresPackLines()
    {
        var health = new HealthRecorder();
        health.SessionStarted();
        foreach (var ms in new[] { 400, 500, 600, 9000 }) health.Line(ms);
        health.Line(null);
        var s = health.Snapshot();
        Assert.Equal(5, s.Lines);
        Assert.Equal(4, s.Translations);
        Assert.Equal(9000, s.TranslationMaxMs);
        Assert.Equal(HealthLevel.Good, HealthReport.Translation(s));
        for (var i = 0; i < 10; i++) health.Line(3500);
        Assert.Equal(HealthLevel.Problem, HealthReport.Translation(health.Snapshot()));
    }

    [Fact]
    public void CountsSurviveSessionEndAndResetOnNextStart()
    {
        var health = new HealthRecorder();
        health.SessionStarted();
        health.RemotePlayLine("Takion Send Buffer overflow");
        health.SessionEnded();
        var s = health.Snapshot();
        Assert.False(s.Active);
        Assert.Equal(1, s.Overflows);
        health.SessionStarted();
        s = health.Snapshot();
        Assert.True(s.Active);
        Assert.Equal(0, s.Overflows);
    }

    [Fact]
    public void SummaryHasCounts()
    {
        var health = new HealthRecorder();
        health.SessionStarted();
        health.RemotePlayLine("Takion Send Buffer overflow");
        var text = HealthReport.Summary(health.Snapshot(), NetworkKind.Wifi);
        Assert.Contains("ağ: wifi", text);
        Assert.Contains("tampon taşması 1", text);
    }
}
