// SPDX-License-Identifier: AGPL-3.0-only

using System.Collections.Concurrent;
using System.Reflection;
using System.Runtime.InteropServices;

namespace CouchSubs.RemotePlay.Tests;

public class StaleSessionEventTests
{
    [Theory]
    [InlineData(NativeMethods.EventConnected, 0)]
    [InlineData(NativeMethods.EventLoginPin, 0)]
    [InlineData(NativeMethods.EventQuit, NativeMethods.QuitNetwork)]
    public async Task QueuedNativeEventsFromStoppedGenerationAreIgnored(int eventType, int quitReason)
    {
        var console = new RegisteredConsole("127.0.0.1", "test", new byte[16], new byte[16]);
        var session = new StreamSession(console, new byte[8]);
        var states = new ConcurrentQueue<SessionState>();
        session.StateChanged += states.Enqueue;
        var queue = (SerialQueue)typeof(StreamSession)
            .GetField("queue", BindingFlags.Instance | BindingFlags.NonPublic)!
            .GetValue(session)!;
        using var entered = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        var handled = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        object? box = null;
        var boxHandle = default(GCHandle);

        try
        {
            queue.Post(() =>
            {
                entered.Set();
                release.Wait();
            });
            Assert.True(entered.Wait(TimeSpan.FromSeconds(2)), "session queue did not reach the test barrier");

            // Queue Connect first, then a native callback. Stop advances the generation and queues CloseBox
            // behind both actions, reproducing a callback already waiting when Stop is called.
            session.Start();
            const int eventGeneration = 1;
            var boxType = typeof(StreamSession).GetNestedType("SessionBox", BindingFlags.NonPublic)!;
            var constructor = boxType.GetConstructor(BindingFlags.Instance | BindingFlags.NonPublic, null,
                [typeof(StreamSession), typeof(int)], null)!;
            box = constructor.Invoke([session, eventGeneration]);
            boxHandle = (GCHandle)boxType.GetField("handle", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(box)!;
            typeof(StreamSession).GetField("box", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, box);
            typeof(StreamSession).GetMethod("Handle", BindingFlags.Instance | BindingFlags.NonPublic)!
                .Invoke(session, [eventType, quitReason, null, eventGeneration, null]);

            session.Stop();
            queue.Post(() => handled.TrySetResult(true));
            release.Set();
            await handled.Task.WaitAsync(TimeSpan.FromSeconds(3));

            Assert.Empty(states);
        }
        finally
        {
            release.Set();
            session.Dispose();
            if (boxHandle.IsAllocated) boxHandle.Free();
        }
    }
}

public class ReconnectPolicyTests
{
    [Fact]
    public void BackoffDoublesUpToThirtySeconds()
    {
        var policy = new ReconnectPolicy();
        Assert.Equal([2, 4, 8, 16, 30, 30, 30], Enumerable.Range(0, 7).Select(_ => policy.NextDelay()));
    }

    [Fact]
    public void ResetStartsOver()
    {
        var policy = new ReconnectPolicy();
        policy.NextDelay();
        policy.NextDelay();
        policy.Reset();
        Assert.Equal(2, policy.NextDelay());
    }
}

public class PictureWatchdogTests
{
    /// <summary>
    /// Hata: istenen IDR karesi de bozuk gelince libchiaki yeniden istemiyor, bağlantı açık kalıp hiç kare gelmiyordu;
    /// oturum hiç yeniden kurulmuyor, altyazı ancak uygulamayı kapatıp açınca dönüyordu.
    /// </summary>
    [Fact]
    public void ConnectedWithoutPictureForEightSecondsIsStalled()
    {
        var watchdog = new PictureWatchdog();
        watchdog.Connected(0);
        for (var second = 1; second <= 120; second++) watchdog.Picture(second * 1000);
        // İki dakika görüntü geldi, sonra kesildi.
        Assert.Null(watchdog.Stalled(127_000));
        Assert.Equal(PictureWatchdog.StallAfter, watchdog.Stalled(128_000));
    }

    /// <summary>Olağan FEC duraklaması (IDR bir saniyeden kısa sürede gelir) oturumu yeniden kurdurmaz.</summary>
    [Fact]
    public void ShortGapIsNotAStall()
    {
        var watchdog = new PictureWatchdog();
        watchdog.Connected(0);
        watchdog.Picture(1000);
        watchdog.Picture(2500);
        Assert.Null(watchdog.Stalled(9000));
    }

    /// <summary>Bağlandıktan sonra ilk kare hiç gelmezse de yakalanır.</summary>
    [Fact]
    public void NoFirstPictureIsStalled()
    {
        var watchdog = new PictureWatchdog();
        watchdog.Connected(0);
        Assert.NotNull(watchdog.Stalled((long)PictureWatchdog.StallAfter.TotalMilliseconds));
    }

    /// <summary>Bağlı değilken görüntü beklenmez; geç gelen eski kare de bekçiyi kurmaz.</summary>
    [Fact]
    public void NotConnectedIsNeverStalled()
    {
        var watchdog = new PictureWatchdog();
        watchdog.Picture(0);
        Assert.Null(watchdog.Stalled(600_000));
        watchdog.Connected(0);
        watchdog.Ended();
        Assert.Null(watchdog.Stalled(600_000));
    }
}

public class RegisteredConsoleTests
{
    [Fact]
    public void WakeCredentialIsHexOfRegistKey()
    {
        var key = "1a2b3c4d"u8.ToArray().Concat(new byte[8]).ToArray();
        var console = new RegisteredConsole("192.168.1.253", "PS5", key, Enumerable.Repeat((byte)7, 16).ToArray());
        Assert.Equal(0x1a2b3c4dUL, console.WakeCredential);
    }
}

public class ConsoleSubnetTests
{
    [Fact]
    public void Slash24ListsOtherHosts()
    {
        var hosts = ConsoleDiscovery.Hosts(0xC0A8_010A, 0xFFFF_FF00); // 192.168.1.10/24
        Assert.Equal(253, hosts.Count);
        Assert.Equal(0xC0A8_0101u, hosts[0]);
        Assert.Equal(0xC0A8_01FEu, hosts[^1]);
        Assert.DoesNotContain(0xC0A8_010Au, hosts);
    }

    [Fact]
    public void Slash22IsTheLargestScannedNetwork()
    {
        Assert.Equal(1021, ConsoleDiscovery.Hosts(0xC0A8_0001, 0xFFFF_FC00).Count);
        Assert.Empty(ConsoleDiscovery.Hosts(0xC0A8_0001, 0xFFFF_F800));
    }

    [Fact]
    public void LargeNetworksAreSkipped()
    {
        Assert.Empty(ConsoleDiscovery.Hosts(0x0A00_0001, 0xFFFF_0000));
    }

    [Fact]
    public void AddressesConvertBothWays()
    {
        Assert.Equal(0xC0A8_010Au, ConsoleDiscovery.ToUInt32(System.Net.IPAddress.Parse("192.168.1.10")));
        Assert.Equal("192.168.1.254", ConsoleDiscovery.ToText(0xC0A8_01FE));
    }

    [Fact]
    public void LocalTargetsAlwaysIncludeBroadcast()
    {
        var targets = ConsoleDiscovery.LocalTargets();
        Assert.Contains("255.255.255.255", targets);
        Assert.Equal(targets.Count, targets.Distinct().Count());
        Assert.DoesNotContain("127.0.0.1", targets);
    }
}

public class DisconnectReasonTests
{
    [Fact]
    public void QuitReasonsMapToUserFacingCases()
    {
        Assert.Equal(new DisconnectReason(DisconnectKind.InUse), DisconnectReasons.FromNative(NativeMethods.QuitInUse, null));
        Assert.Equal(new DisconnectReason(DisconnectKind.Stopped), DisconnectReasons.FromNative(NativeMethods.QuitStopped, null));
        Assert.Equal(new DisconnectReason(DisconnectKind.Refused), DisconnectReasons.FromNative(NativeMethods.QuitRefused, "ignored"));
        Assert.Equal(new DisconnectReason(DisconnectKind.Network), DisconnectReasons.FromNative(NativeMethods.QuitNetwork, null));
        Assert.Equal(new DisconnectReason(DisconnectKind.Other, "Version Mismatch"),
                     DisconnectReasons.FromNative(NativeMethods.QuitOther, "Version Mismatch"));
    }

    /// "Unknown Session Request Error"ın asıl nedeni libchiaki'nin günlük satırındadır (satırlar session.c'deki gibi).
    [Theory]
    [InlineData("Reported Application Reason: 0x80108b09 (Regist failed, probably invalid PIN)", DisconnectKind.RegistrationInvalid)]
    [InlineData("Reported Application Reason: 0x80108B02 (Invalid PSN ID)", DisconnectKind.RegistrationInvalid)]
    [InlineData("Reported Application Reason: 0x80108b26 (unknown)", DisconnectKind.RegistrationInvalid)]
    [InlineData("Reported Application Reason: 0x80108b12 (unknown)", DisconnectKind.RemotePlayDisabled)]
    [InlineData("Session request connect failed eventually.", DisconnectKind.Network)]
    [InlineData("Failed to receive session request response", DisconnectKind.Network)]
    [InlineData("Failed to send session request", DisconnectKind.Network)]
    public void SessionRequestLogLinesAreClassified(string line, DisconnectKind kind) =>
        Assert.Equal(new DisconnectReason(kind), DisconnectReasons.SessionRequestHint(line));

    /// <summary>PS5 kayıt dışı bir kodla reddetti: kod ayrıntıda (libchiaki "unknown" der).</summary>
    [Fact]
    public void OtherApplicationReasonIsRejection() =>
        Assert.Equal(new DisconnectReason(DisconnectKind.Rejected, "0x80108bff"),
                     DisconnectReasons.SessionRequestHint("Reported Application Reason: 0x80108bff (unknown)"));

    [Theory]
    [InlineData("Reported Application Reason: garbage")]
    [InlineData("Session request successful")]
    [InlineData("Failed to parse session request response")]
    [InlineData(null)]
    public void OtherLogLinesGiveNoHint(string? line) => Assert.Null(DisconnectReasons.SessionRequestHint(line));

    /// Günlükten anlaşılan neden yalnız bilinmeyen oturum isteği hatasının yerine geçer.
    [Fact]
    public void SessionRequestHintRefinesOnlyUnknownSessionRequest()
    {
        var invalid = new DisconnectReason(DisconnectKind.RegistrationInvalid);
        Assert.Equal(invalid, DisconnectReasons.FromNative(NativeMethods.QuitOther, DisconnectReasons.UnknownSessionRequest, invalid));
        Assert.Equal(new DisconnectReason(DisconnectKind.Rejected),
                     DisconnectReasons.FromNative(NativeMethods.QuitOther, DisconnectReasons.UnknownSessionRequest, null));
        var rejected = new DisconnectReason(DisconnectKind.Rejected, "0x80108bff");
        Assert.Equal(rejected, DisconnectReasons.FromNative(NativeMethods.QuitOther, DisconnectReasons.UnknownSessionRequest, rejected));
        // PS5 oturum isteğine yanıt verdi: reddetmesi "bulunamadı" değildir.
        Assert.Equal(rejected, StreamSession.Classify(rejected, false, "192.168.1.70"));
        Assert.Equal(new DisconnectReason(DisconnectKind.Other, "Version Mismatch"),
                     DisconnectReasons.FromNative(NativeMethods.QuitOther, "Version Mismatch", invalid));
        Assert.Equal(new DisconnectReason(DisconnectKind.InUse), DisconnectReasons.FromNative(NativeMethods.QuitInUse, null, invalid));
        Assert.Equal(invalid, StreamSession.Classify(invalid, false, "192.168.1.70"));
    }
}

public class SessionReasonTests
{
    /// PS5 aramaya yanıt vermediyse ve oturum ağ hatasıyla düştüyse neden "bulunamadı"dır; yanıt verdiyse neden olduğu gibi kalır.
    [Fact]
    public void MissingConsoleIsReportedAsNotFound()
    {
        var network = new DisconnectReason(DisconnectKind.Network);
        Assert.Equal(new DisconnectReason(DisconnectKind.NotFound, "192.168.1.70"), StreamSession.Classify(network, false, "192.168.1.70"));
        Assert.Equal(new DisconnectReason(DisconnectKind.NotFound, "192.168.1.70"),
                     StreamSession.Classify(new DisconnectReason(DisconnectKind.Other, "x"), false, "192.168.1.70"));
        Assert.Equal(network, StreamSession.Classify(network, true, "192.168.1.70"));
        var inUse = new DisconnectReason(DisconnectKind.InUse);
        Assert.Equal(inUse, StreamSession.Classify(inUse, false, "192.168.1.70"));
    }
}

public class RegistrationReasonTests
{
    [Fact]
    public void InvalidPsnIdMeansWrongAccount()
    {
        Assert.Equal(RegistrationFailure.WrongAccount, Registration.FailureFrom(0x80108b02));
        Assert.Equal(RegistrationFailure.Failed, Registration.FailureFrom(0x80108bff));
        Assert.Equal(RegistrationFailure.Failed, Registration.FailureFrom(null));
    }

    [Fact]
    public void KnownReasonsAndMissingSearchAnswerAreDistinguished()
    {
        Assert.Equal(RegistrationFailure.WrongCode, Registration.FailureFrom(0x80108b09));
        Assert.Equal(RegistrationFailure.InUse, Registration.FailureFrom(0x80108b10));
        Assert.Equal(RegistrationFailure.VersionMismatch, Registration.FailureFrom(0x80108b11));
        Assert.Equal(RegistrationFailure.ConsoleCrashed, Registration.FailureFrom(0x80108b15));
        Assert.Equal(RegistrationFailure.NoAnswer, Registration.FailureFrom(null, ["Regist timed out waiting for search response", "Regist search failed"]));
        // PS5 kod bildirdiyse arama aşaması geçilmiştir.
        Assert.Equal(RegistrationFailure.WrongCode, Registration.FailureFrom(0x80108b09, ["Regist timed out waiting for search response"]));
    }

    /// PS5 kod bildirmediyse libchiaki'nin hata satırlarından nerede kalındığı anlaşılır (satırlar regist.c'den).
    [Theory]
    [InlineData(RegistrationFailure.NoAnswer, "Regist failed to send search: Unknown error", "Regist search failed")]
    [InlineData(RegistrationFailure.NoAnswer, "Regist connect failed: 10060", "Regist eventually failed to connect for request")]
    [InlineData(RegistrationFailure.NoAnswer, "Regist eventually failed to connect for search", "Regist search failed")]
    [InlineData(RegistrationFailure.BadAddress, "Regist failed to getaddrinfo on 192.168.1.", "Regist eventually failed")]
    [InlineData(RegistrationFailure.NoReply, "Regist failed to receive response HTTP header", "Regist eventually failed")]
    [InlineData(RegistrationFailure.NoReply, "Regist timed out receiving response content", "Regist eventually failed")]
    [InlineData(RegistrationFailure.Failed, "Regist response is missing RegistKey (or it was invalid)", "Regist eventually failed")]
    public void ChiakiErrorLinesAreClassified(RegistrationFailure expected, string first, string second) =>
        Assert.Equal(expected, Registration.FailureFrom(null, [first, second]));

    [Theory]
    [InlineData("12345678", 12345678u)]
    [InlineData("1234 5678", 12345678u)]
    [InlineData(" 1234-5678\n", 12345678u)]
    [InlineData("01234567", 1234567u)]
    [InlineData("１２３４５６７８", 12345678u)]
    [InlineData("١٢٣٤٥٦٧٨", 12345678u)]
    public void PinIsRead(string text, uint expected) => Assert.Equal(expected, Registration.ParsePin(text));

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("1234567")]
    [InlineData("123456789")]
    [InlineData("1234567O")]
    [InlineData("1234567½")]
    public void InvalidPinIsRejected(string? text) => Assert.Null(Registration.ParsePin(text));

    [Fact]
    public void DetailPrefersThePs5Reason()
    {
        Assert.Equal("0x80108b09 (Regist Failed)", Registration.DetailFrom(
            ["Regist received HTTP code 403", "Reported Application Reason: 0x80108b09 (Regist Failed)", "Regist eventually failed"]));
        Assert.Equal("Regist received HTTP code 500", Registration.DetailFrom(["Regist received HTTP code 500", "Regist eventually failed"]));
        Assert.Null(Registration.DetailFrom([]));
    }

    [Fact]
    public void MovedConsoleIsPickedOnlyWhenCertain()
    {
        var a = new ConsoleInfo("192.168.1.20", "PS5-A", true);
        var b = new ConsoleInfo("192.168.1.21", "PS5-B", true);
        Assert.Equal(a, ConsoleDiscovery.PickMoved([a], "other name"));
        Assert.Equal(b, ConsoleDiscovery.PickMoved([a, b], "PS5-B"));
        Assert.Null(ConsoleDiscovery.PickMoved([a, b], "other name"));
        Assert.Null(ConsoleDiscovery.PickMoved([], "PS5-A"));
    }

    [Fact]
    public async Task AccountIdMustBeEightBytes()
    {
        await Assert.ThrowsAsync<ArgumentException>(() => Registration.RegisterAsync("192.168.1.2", new byte[4], 12345678));
    }
}

public class NativeHelperTests
{
    [Fact]
    public void PaddedCopiesPrefixAndFillsZeros()
    {
        Assert.Equal(new byte[] { 1, 2, 0, 0 }, NativeMethods.Padded([1, 2], 4));
        Assert.Equal(new byte[] { 1, 2 }, NativeMethods.Padded([1, 2, 3], 2));
    }

    [Fact]
    public unsafe void FixedStringStopsAtZero()
    {
        var bytes = "PS5-123\0garbage"u8.ToArray();
        fixed (byte* pointer = bytes)
            Assert.Equal("PS5-123", NativeMethods.FixedString(pointer, bytes.Length));
    }
}
