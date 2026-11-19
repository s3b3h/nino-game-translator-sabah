// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Shell;

namespace CouchSubs.Shell.Tests;

/// <summary>Nino: salon sahnesinin fiş ve kablo hesabı (Mac: PlugTests ve LivingRoomScene.cable).</summary>
public sealed class LivingRoomLayoutTests
{
    private static readonly ScenePoint Socket = new(1564, 378), Rest = new(1600, 885);

    /// Fiş dinlenirken aşağı bakar; prize yaklaştıkça uçları prize döner (eskiden hep aşağı bakıyordu).
    [Fact]
    public void PlugTurnsTowardTheSocketAsItGetsCloser()
    {
        Assert.Equal(0, LivingRoomLayout.PlugTurn(Rest, Socket, Rest), 3);
        // Prizden uzaklaşınca (aşağı/sağa çekilince) dönmez.
        Assert.Equal(0, LivingRoomLayout.PlugTurn(new(1640, 930), Socket, Rest), 3);
        // Prizin hemen altında: uçlar yukarı (prize) bakar: (−sin θ, cos θ) ≈ (0, −1).
        var below = LivingRoomLayout.PlugTurn(new(1564, 470), Socket, Rest);
        Assert.InRange(-Math.Sin(below), -0.05, 0.05);
        Assert.InRange(Math.Cos(below), -1.05, -0.95);
        // Prizin solunda: uçlar sağa bakar.
        var left = LivingRoomLayout.PlugTurn(new(1460, 378), Socket, Rest);
        Assert.InRange(-Math.Sin(left), 0.95, 1.05);
        // Yol ortasında kısmen dönmüştür.
        var mid = Math.Abs(LivingRoomLayout.PlugTurn(new(1585, 640), Socket, Rest));
        Assert.InRange(mid, 0.2, Math.PI - 0.2);
        Assert.NotEqual(0.2, mid);
    }

    /// Uçların yönü (−sin θ, cos θ): dönmemiş fişte aşağı; prize 120 piksel kala tam prize dönük.
    [Fact]
    public void ProngsPointAtTheSocketOnceWithinTurnDone()
    {
        Assert.Equal(new ScenePoint(0, 1), LivingRoomLayout.Prong(0));
        foreach (var layout in new[] { LivingRoomLayout.Ps5, LivingRoomLayout.Xbox })
        {
            Assert.Equal(0, layout.PlugTurn(layout.Hanging), 6);
            var plug = new ScenePoint(layout.Socket.X - 60, layout.Socket.Y + 80);
            var prong = LivingRoomLayout.Prong(layout.PlugTurn(plug));
            var distance = plug.DistanceTo(layout.Socket);
            Assert.Equal((layout.Socket.X - plug.X) / distance, prong.X, 6);
            Assert.Equal((layout.Socket.Y - plug.Y) / distance, prong.Y, 6);
        }
    }

    /// PS5 sahnesi: kablo görseldeki kablonun yolunu izleyerek başlar, (0.5, 0.87) yönünde çıkar, fişin arkasına girer.
    [Fact]
    public void Ps5CableFollowsThePicturedCableAndEntersTheBackOfThePlug()
    {
        var layout = LivingRoomLayout.Ps5;
        Assert.Equal("living-room.png", layout.Image);
        Assert.Equal(new ScenePoint(1564, 378), layout.Socket);
        Assert.Equal(new ScenePoint(1600, 885), layout.Hanging);
        var cable = layout.Cable(layout.Hanging, seated: false);
        Assert.Equal([new(1490, 706), new(1522, 706), new(1535, 709), new(1545, 716), new(1552, 727)], cable.Lead);
        // Dinlenen fiş aşağı bakar: arkası fişin 40 piksel üstü, ikinci denetim noktası 80 piksel daha yukarıda.
        Assert.Equal(new ScenePoint(1600, 845), cable.End);
        var sag = (LivingRoomLayout.CableLength - new ScenePoint(1552, 727).DistanceTo(cable.End)) * 0.45;
        Assert.True(sag > 0);
        Assert.Equal(1552 + 0.5 * 70, cable.Control1.X, 6);
        Assert.Equal(727 + 0.87 * 70 + sag, cable.Control1.Y, 6);
        Assert.Equal(1600, cable.Control2.X, 6);
        Assert.Equal(845 - 80 + sag, cable.Control2.Y, 6);
    }

    /// Fiş prize dönükken kablo fişe ekseni boyunca, arkasından (alttan) girer; boyundan artan kadar sarkar, gerginken sarkmaz.
    [Fact]
    public void CableEntersAlongThePlugAxisAndSagsOnlyWhenSlack()
    {
        foreach (var layout in new[] { LivingRoomLayout.Ps5, LivingRoomLayout.Xbox })
        {
            var plug = new ScenePoint(layout.Socket.X, layout.Socket.Y + 100);
            var cable = layout.Cable(plug, seated: false);
            var start = cable.Lead[^1];
            // Uçlar yukarı (prize) bakar: arka fişin 40 piksel altında, denetim noktası 80 piksel daha aşağıda.
            Assert.Equal(plug.X, cable.End.X, 6);
            Assert.Equal(plug.Y + 40, cable.End.Y, 6);
            var sag = Math.Max(0, LivingRoomLayout.CableLength - start.DistanceTo(cable.End)) * 0.45;
            Assert.True(sag > 0);
            Assert.Equal(plug.X, cable.Control2.X, 6);
            Assert.Equal(plug.Y + 120 + sag, cable.Control2.Y, 6);
            Assert.Equal(start.X + layout.CableOut.X * 70, cable.Control1.X, 6);
            Assert.Equal(start.Y + layout.CableOut.Y * 70 + sag, cable.Control1.Y, 6);

            // Kablo boyundan (330) uzağa çekilince sarkma kalmaz.
            var far = new ScenePoint(layout.Socket.X - 300, layout.Socket.Y);
            var stretched = layout.Cable(far, seated: false);
            Assert.True(start.DistanceTo(stretched.End) > LivingRoomLayout.CableLength);
            Assert.Equal(start.Y + layout.CableOut.Y * 70, stretched.Control1.Y, 6);
        }
    }

    /// Xbox sahnesi: görselde kablo yok; kablo konsolun sağ arkasından (1572, 722) çıkar, çıkış yönü (1, 0.1).
    [Fact]
    public void XboxCableLeavesTheBackOfTheConsole()
    {
        var layout = LivingRoomLayout.Xbox;
        Assert.Equal("living-room-xbox.png", layout.Image);
        Assert.Empty(layout.CableLead);
        Assert.Equal(new ScenePoint(1572, 722), layout.CableStart);
        Assert.Equal(new ScenePoint(1, 0.1), layout.CableOut);
        Assert.Equal(new ScenePoint(1561, 381), layout.Socket);
        Assert.Equal(new ScenePoint(1646, 912), layout.Hanging);
        var cable = layout.Cable(layout.Hanging, seated: false);
        Assert.Equal([new(1572, 722)], cable.Lead);
        Assert.Equal(new ScenePoint(1646, 872), cable.End);
        var sag = (LivingRoomLayout.CableLength - new ScenePoint(1572, 722).DistanceTo(cable.End)) * 0.45;
        Assert.Equal(1572 + 70, cable.Control1.X, 6);
        Assert.Equal(722 + 7 + sag, cable.Control1.Y, 6);
    }

    /// Fiş takılıyken kablo alttan prize kıvrılır (iki sahnede de).
    [Fact]
    public void SeatedCableCurlsUpIntoTheSocket()
    {
        var ps5 = LivingRoomLayout.Ps5.Cable(LivingRoomLayout.Ps5.Socket, seated: true);
        Assert.Equal(new ScenePoint(1564, 408), ps5.End);
        Assert.Equal(new ScenePoint(1552 + 0.5 * 90, 727 + 0.87 * 90), ps5.Control1);
        Assert.Equal(new ScenePoint(1574, 578), ps5.Control2);
        Assert.Equal(5, ps5.Lead.Count);
        var xbox = LivingRoomLayout.Xbox.Cable(LivingRoomLayout.Xbox.Socket, seated: true);
        Assert.Equal(new ScenePoint(1561, 411), xbox.End);
        Assert.Equal(new ScenePoint(1572 + 90, 722 + 9), xbox.Control1);
    }

    /// Sehpa pencerenin ortasına gelir; ekran içeriği Mac'teki 588 noktalık ekrandan büyütülür.
    [Fact]
    public void StandIsCentredAndScreenScalesFromTheLogicalWidth()
    {
        Assert.Equal(72, LivingRoomLayout.Ps5.Shift);
        Assert.Equal(6, LivingRoomLayout.Xbox.Shift);
        Assert.Equal(1151 / 588.0, LivingRoomLayout.Ps5.ScreenScale, 9);
        Assert.Equal(1185 / 588.0, LivingRoomLayout.Xbox.ScreenScale, 9);
        Assert.Same(LivingRoomLayout.Xbox, LivingRoomLayout.For(xbox: true));
        Assert.Same(LivingRoomLayout.Ps5, LivingRoomLayout.For(xbox: false));
        Assert.Equal(8, LivingRoomLayout.CableWidth);
        Assert.Equal(86, LivingRoomLayout.SocketSize);
    }
}
