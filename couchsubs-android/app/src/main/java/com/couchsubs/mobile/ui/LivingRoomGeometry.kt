// SPDX-License-Identifier: AGPL-3.0-only
// Nino: salon sahnesinin ölçüleri ve saf geometri kuralları (Mac: LivingRoomScene.swift ile aynı sayılar ve kurallar).
// Çizimden ayrı durur ki JVM testleriyle sınanabilsin (LivingRoomGeometryTest).
package com.couchsubs.mobile.ui

import androidx.annotation.DrawableRes
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import com.couchsubs.mobile.R
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/**
 * Sahne konsola göre değişir: PS5'li salon (`living_room`) ya da Xbox'lı salon (`living_room_xbox`; aynı TV, sehpa ve
 * priz). Koordinatlar görsellerin piksel ölçüsündedir (1672×941); görseller Mac'tekilerle aynı dosyalardır.
 */
internal class RoomLayout(
    @DrawableRes val image: Int,
    val screen: Rect,
    val tvFrame: Rect,
    val standFrame: Rect,
    val socket: Offset,
    /** Kablonun çizilmeye başladığı yer (PS5'te görseldeki kablonun ucu, Xbox'ta konsolun sağ arkası). */
    val cableStart: Offset,
    /**
     * Görseldeki kablonun (varsa) son parçası: çizilen kablo bunun üstünden başlar, ek yeri görünmez. Yoksa boş (Xbox
     * görselinde kablo yok; kablo [cableStart]taki girişten küçük bir fiş başıyla çıkar).
     */
    val cableLead: List<Offset> = emptyList(),
    /** Kablonun çizilen parçasının başladığı yerdeki yönü: görseldeki kablonun bittiği eğimle sürer. */
    val cableOut: Offset = Offset(1f, 0.1f),
    /** Fiş çıkıkken sehpanın yanından sarkar. */
    val hanging: Offset,
    /** Sehpanın ön yüzündeki kaydırma rayının ortası (y); ray iki sahnede de aynı x aralığındadır. */
    val railY: Float,
) {
    companion object {
        const val CANVAS_W = 1672f
        const val CANVAS_H = 941f

        val PS5 = RoomLayout(
            image = R.drawable.living_room,
            screen = Rect(Offset(149f, 40f), Size(1151f, 595f)),
            tvFrame = Rect(Offset(139f, 27f), Size(1171f, 621f)),
            standFrame = Rect(Offset(49f, 713f), Size(1502f, 160f)),
            socket = Offset(1564f, 378f),
            cableStart = Offset(1550f, 734f),
            // Görseldeki kablo: PS5'in arkasından yatay çıkar (y≈706), 1523'ten sonra aşağı kıvrılıp (1552, 727)'de biter
            // (Mac'te ölçüldü; görsel aynı dosya). Çizilen kablo aynı yolu izleyip oradan devam eder.
            cableLead = listOf(Offset(1490f, 706f), Offset(1522f, 706f), Offset(1535f, 709f), Offset(1545f, 716f), Offset(1552f, 727f)),
            cableOut = Offset(0.5f, 0.87f),
            hanging = Offset(1600f, 885f),
            railY = 792f,
        )
        val XBOX = RoomLayout(
            image = R.drawable.living_room_xbox,
            screen = Rect(Offset(136f, 40f), Size(1185f, 596f)),
            tvFrame = Rect(Offset(121f, 26f), Size(1214f, 630f)),
            standFrame = Rect(Offset(43f, 733f), Size(1580f, 167f)),
            socket = Offset(1561f, 381f),
            cableStart = Offset(1572f, 722f),
            hanging = Offset(1646f, 912f),
            // Sehpa bu görselde 20 piksel aşağıda ve biraz daha yüksek: ray ön yüzün aynı yerinde dursun.
            railY = 816f,
        )
    }
}

/** Konsoldan fişe giden kablonun yolu (sahne pikseli): [lead] noktaları düz çizgilerle, sonra [end]e tek eğri. */
internal class CableShape(val lead: List<Offset>, val control1: Offset, val control2: Offset, val end: Offset)

internal object LivingRoomGeometry {
    /** Prize bu kadar yaklaşınca fiş tam prize dönmüş olur (sahne pikseli). */
    const val TURN_DONE = 120f
    /** Kablonun serbest boyu: fiş konsola yaklaşınca kablo bu boydan artanı kadar sarkar. */
    const val CABLE_LENGTH = 330f
    const val CABLE_WIDTH = 8f
    /** Görseldeki prizin kenar uzunluğu (sahne pikseli). */
    const val SOCKET_SIZE = 86f

    /**
     * Fiş çıkıkken uçlarının baktığı yön (radyan; 0 = aşağı, saat yönü artı). Dinlenirken yerçekimiyle aşağı sarkar;
     * prize yaklaştıkça yumuşak geçişle prize döner, prize [TURN_DONE] kala tam dönüktür (eskiden hep aşağı bakıyordu,
     * prize götürürken de). Uçlar dönmeden önce (0, +1) yönüne bakar; θ kadar dönünce (−sin θ, cos θ).
     */
    fun plugTurn(plug: Offset, socket: Offset, rest: Offset): Float {
        val restDistance = hypot(socket.x - rest.x, socket.y - rest.y)
        val distance = hypot(socket.x - plug.x, socket.y - plug.y)
        if (restDistance <= TURN_DONE || distance <= 1f) return 0f
        val t = ((restDistance - distance) / (restDistance - TURN_DONE)).coerceIn(0f, 1f)
        val eased = t * t * (3 - 2 * t)
        return eased * atan2(-(socket.x - plug.x), socket.y - plug.y)
    }

    /** Uçların baktığı yön (birim vektör). */
    fun prong(turn: Float): Offset = Offset(-sin(turn), cos(turn))

    /**
     * Kablonun yolu. Görseldeki kablonun (PS5) son parçasının üstünden başlar ki ek yeri belli olmasın; Xbox'ta konsolun
     * arkasından çıkar. Fiş çıkıkken fişin arkasına (gövdenin üstündeki kablo boğazı) fişin ekseni boyunca girer ve boyundan
     * artan kadar sarkar; takılıyken ([inSocket]) alttan prize kıvrılır.
     */
    fun cable(layout: RoomLayout, plug: Offset, turn: Float, inSocket: Boolean): CableShape {
        val lead = layout.cableLead.ifEmpty { listOf(layout.cableStart) }
        val start = lead.last()
        val out = layout.cableOut
        if (inSocket) {
            val end = Offset(plug.x, plug.y + 30)
            return CableShape(lead, Offset(start.x + out.x * 90, start.y + out.y * 90), Offset(end.x + 10, end.y + 170), end)
        }
        val prong = prong(turn)
        val back = Offset(plug.x - prong.x * 40, plug.y - prong.y * 40)
        val sag = (CABLE_LENGTH - hypot(back.x - start.x, back.y - start.y)).coerceAtLeast(0f) * 0.45f
        return CableShape(lead,
            Offset(start.x + out.x * 70, start.y + out.y * 70 + sag),
            Offset(back.x - prong.x * 80, back.y - prong.y * 80 + sag), back)
    }
}
