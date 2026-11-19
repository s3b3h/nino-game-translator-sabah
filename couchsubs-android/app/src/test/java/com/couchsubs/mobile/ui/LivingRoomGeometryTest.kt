// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import androidx.compose.ui.geometry.Offset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/** Salon sahnesinin geometri kuralları (Mac: DownloadCounterTests.swift içindeki PlugTests ile aynı beklentiler). */
class LivingRoomGeometryTest {
    private val socket = Offset(1564f, 378f)
    private val rest = Offset(1600f, 885f)

    /** Fiş dinlenirken aşağı bakar; prize yaklaştıkça uçları prize döner (eskiden hep aşağı bakıyordu). */
    @Test fun plugTurnsTowardTheSocketAsItGetsCloser() {
        assertEquals(0f, LivingRoomGeometry.plugTurn(rest, socket, rest), 0.001f)
        // Prizden uzaklaşınca (aşağı/sağa çekilince) dönmez.
        assertEquals(0f, LivingRoomGeometry.plugTurn(Offset(1640f, 930f), socket, rest), 0.001f)
        // Prizin hemen altında: uçlar yukarı (prize) bakar: (−sin θ, cos θ) ≈ (0, −1).
        val below = LivingRoomGeometry.plugTurn(Offset(1564f, 470f), socket, rest)
        assertEquals(0f, -sin(below), 0.05f)
        assertEquals(-1f, cos(below), 0.05f)
        // Prizin solunda: uçlar sağa bakar.
        val left = LivingRoomGeometry.plugTurn(Offset(1460f, 378f), socket, rest)
        assertEquals(1f, -sin(left), 0.05f)
        // Yol ortasında kısmen dönmüştür.
        val mid = abs(LivingRoomGeometry.plugTurn(Offset(1585f, 640f), socket, rest))
        assertTrue(mid > 0.2f)
        assertTrue(mid < Math.PI.toFloat() - 0.2f)
    }

    /** Alttaki rayla giderken de döner: dinlenme yerinden prize düz yolda önce aşağı, sona doğru prize bakar. */
    @Test fun plugTurnsAlongTheRailPath() {
        for (layout in listOf(RoomLayout.PS5, RoomLayout.XBOX)) {
            fun at(progress: Float) = Offset(layout.hanging.x + (layout.socket.x - layout.hanging.x) * progress,
                layout.hanging.y + (layout.socket.y - layout.hanging.y) * progress)
            assertEquals(0f, LivingRoomGeometry.plugTurn(at(0f), layout.socket, layout.hanging), 0.001f)
            var last = 0f
            for (step in 1..99) {
                val turn = abs(LivingRoomGeometry.plugTurn(at(step / 100f), layout.socket, layout.hanging))
                assertTrue("geri dönmez ($step)", turn >= last - 0.001f)
                last = turn
            }
            // Sona az kala uçlar prize bakar (uç yönü ile prize giden yön aynı).
            val near = at(0.99f)
            val prong = LivingRoomGeometry.prong(LivingRoomGeometry.plugTurn(near, layout.socket, layout.hanging))
            val distance = hypot(layout.socket.x - near.x, layout.socket.y - near.y)
            assertEquals((layout.socket.x - near.x) / distance, prong.x, 0.01f)
            assertEquals((layout.socket.y - near.y) / distance, prong.y, 0.01f)
        }
    }

    /** PS5'te kablo görseldeki kablonun yolundan başlar ve fişin arkasına (uçların tersine 40) girer. */
    @Test fun ps5CableFollowsTheImageAndEntersThePlugFromBehind() {
        val layout = RoomLayout.PS5
        val hanging = LivingRoomGeometry.cable(layout, layout.hanging, 0f, inSocket = false)
        assertEquals(listOf(Offset(1490f, 706f), Offset(1522f, 706f), Offset(1535f, 709f), Offset(1545f, 716f), Offset(1552f, 727f)), hanging.lead)
        // Dinlenirken uçlar aşağı bakar: kablo fişin 40 üstünden girer.
        assertEquals(Offset(1600f, 845f), hanging.end)
        // Kablo boyundan (330) artan kadar sarkar: iki denetim noktasının y'sine eklenir.
        val sag = (330f - hypot(1600f - 1552f, 845f - 727f)) * 0.45f
        assertEquals(1552f + 0.5f * 70, hanging.control1.x, 0.01f)
        assertEquals(727f + 0.87f * 70 + sag, hanging.control1.y, 0.01f)
        assertEquals(1600f, hanging.control2.x, 0.01f)
        assertEquals(845f - 80 + sag, hanging.control2.y, 0.01f)
        // Uzaktayken sarkmaz; fiş sola bakıyorsa (uçlar sağa) kablo soldan, fişin ekseni boyunca girer.
        val turned = LivingRoomGeometry.cable(layout, Offset(1200f, 300f), (-Math.PI / 2).toFloat(), inSocket = false)
        assertEquals(1160f, turned.end.x, 0.01f)
        assertEquals(300f, turned.end.y, 0.01f)
        assertEquals(1080f, turned.control2.x, 0.01f)
        assertEquals(300f, turned.control2.y, 0.01f)
        assertEquals(727f + 0.87f * 70, turned.control1.y, 0.01f)
    }

    /** Xbox görselinde kablo yok: kablo konsolun sağ arkasından (1572, 722), (1, 0.1) yönünde çıkar. */
    @Test fun xboxCableLeavesTheConsoleBack() {
        val layout = RoomLayout.XBOX
        val far = LivingRoomGeometry.cable(layout, Offset(1200f, 300f), 0f, inSocket = false)
        assertEquals(listOf(Offset(1572f, 722f)), far.lead)
        assertEquals(1572f + 70f, far.control1.x, 0.01f)
        assertEquals(722f + 7f, far.control1.y, 0.01f)
        assertTrue(layout.cableLead.isEmpty())
    }

    /** Takılıyken kablo alttan prize kıvrılır (iki sahnede de). */
    @Test fun cableCurvesUpIntoTheSocketWhenPluggedIn() {
        for (layout in listOf(RoomLayout.PS5, RoomLayout.XBOX)) {
            val start = layout.cableLead.lastOrNull() ?: layout.cableStart
            val cable = LivingRoomGeometry.cable(layout, layout.socket, 0f, inSocket = true)
            assertEquals(Offset(layout.socket.x, layout.socket.y + 30), cable.end)
            assertEquals(Offset(start.x + layout.cableOut.x * 90, start.y + layout.cableOut.y * 90), cable.control1)
            assertEquals(Offset(layout.socket.x + 10, layout.socket.y + 200), cable.control2)
        }
    }
}
