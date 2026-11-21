// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.Socket

/** TV uygulamalarının (LG, Samsung, Android TV) okuduğu olay biçimi: Windows'taki SubtitleServerTests ile aynı çıktı. */
class SubtitleServerTest {
    @Test
    fun subtitleFrameMatchesDesktop() {
        val frame = SubtitleServer.subtitleFrame("Merhaba", 4000, TextBox(0.25, 0.8, 0.75, 0.87499), at = 1700000000000)
        assertEquals(
            "event: subtitle\ndata: {\"at\":1700000000000,\"box\":{\"bottom\":0.875,\"left\":0.25,\"right\":0.75,\"top\":0.8}," +
                "\"duration\":4000,\"text\":\"Merhaba\"}\n\n",
            frame,
        )
    }

    @Test
    fun turkishLettersAndQuotesAreEncodedLikeSystemTextJson() {
        val frame = SubtitleServer.subtitleFrame("Işığı \"aç\"\nşimdi", 15000, null, at = 1)
        assertEquals("event: subtitle\ndata: {\"at\":1,\"duration\":15000,\"text\":\"Işığı \\\"aç\\\"\\nşimdi\"}\n\n", frame)
    }

    @Test
    fun boxValuesAreClampedAndRounded() {
        assertEquals("{\"bottom\":1,\"left\":0,\"right\":0.1235,\"top\":0.5}",
            Json.write(SubtitleServer.boxJson(TextBox(-0.2, 0.5, 0.12345678, 1.7))))
    }

    /**
     * "Arka plan koyuluğu" (hata bildirimi, Android 3.4.1: "%50 altı çalışmıyor, %55'te simsiyah oluyor"): örtme kipinde
     * %60 altı TV'ye 100 gider (Mac/iPhone ve Windows ile aynı kural); kaydırıcı aynı işlevi kullanır, o kipte %60'tan başlar.
     */
    @Test
    fun coverPlacementNeverSendsATransparentBox() {
        assertEquals(60, SubtitleStyle.COVER_MIN_BACKGROUND)
        // Örtme kipi: eşiğin altı tamamen opak; eşik ve üstü olduğu gibi.
        for (value in listOf(0, 30, 50, 55, 59)) assertEquals(100, SubtitleStyle.effectiveBackground(SubtitlePlacement.COVER, value))
        for (value in listOf(60, 65, 72, 100)) assertEquals(value, SubtitleStyle.effectiveBackground(SubtitlePlacement.COVER, value))
        // Öbür yerleşimlerde (İngilizce yazı da görünür) kaydırıcının bütün aralığı geçerli.
        for (placement in listOf(SubtitlePlacement.ABOVE, SubtitlePlacement.BELOW, SubtitlePlacement.FIXED))
            for (value in listOf(0, 30, 55, 60, 100)) assertEquals(value, SubtitleStyle.effectiveBackground(placement, value))
        // Aralık dışı değer sınıra çekilir.
        assertEquals(100, SubtitleStyle.effectiveBackground(SubtitlePlacement.ABOVE, 140))
        assertEquals(0, SubtitleStyle.effectiveBackground(SubtitlePlacement.BELOW, -5))
        // TV'ye giden ileti: yüzde 0-100 tam sayı olarak gider (TV 100'e böler); 55 örtmede 100, üstünde 55.
        val cover = SubtitleStyle(placement = SubtitlePlacement.COVER, background = SubtitleStyle.effectiveBackground(SubtitlePlacement.COVER, 55))
        assertTrue(SubtitleServer.styleFrame(cover).contains("\"background\":100,"))
        val above = SubtitleStyle(placement = SubtitlePlacement.ABOVE, background = SubtitleStyle.effectiveBackground(SubtitlePlacement.ABOVE, 55))
        assertTrue(SubtitleServer.styleFrame(above).contains("\"background\":55,"))
        // Kaydırıcının örtme kipindeki durakları: %60'tan %100'e 5'er (aradaki 7 durak), hepsi olduğu gibi gider.
        val floor = SubtitleStyle.COVER_MIN_BACKGROUND
        val stops = (0..(100 - floor) / 5).map { floor + it * 5 }
        assertEquals(listOf(60, 65, 70, 75, 80, 85, 90, 95, 100), stops)
        assertTrue(stops.all { SubtitleStyle.effectiveBackground(SubtitlePlacement.COVER, it) == it })
    }

    @Test
    fun clearAndStyleFrames() {
        assertEquals("event: clear\ndata: {}\n\n", SubtitleServer.clearFrame())
        assertEquals(
            "event: style\ndata: {\"autoSize\":true,\"background\":100,\"backgroundShape\":\"fit\",\"bold\":false,\"bottomPercent\":7,\"displayMode\":\"inApp\",\"font\":\"condensed\",\"fontSize\":46," +
                "\"placement\":\"cover\",\"stackPrevious\":true,\"textColor\":\"white\",\"watermark\":true}\n\n",
            SubtitleServer.styleFrame(SubtitleStyle()),
        )
        assertTrue(SubtitleServer.styleFrame(SubtitleStyle(displayMode = TvDisplayMode.OVERLAY, textColor = SubtitleTextColor.YELLOW))
            .contains("\"displayMode\":\"overlay\""))
        val band = SubtitleServer.styleFrame(SubtitleStyle(background = 100, backgroundShape = SubtitleBackgroundShape.BAND))
        assertTrue(band.contains("\"background\":100") && band.contains("\"backgroundShape\":\"band\""))
        // "Önceki satırları üstte tut" kapalıysa TV'ye false gider (Windows ve Mac ile aynı).
        assertTrue(SubtitleServer.styleFrame(SubtitleStyle(stackPrevious = false)).contains("\"stackPrevious\":false"))
        // Kullanıcı boyu kendisi seçince TV otomatik boyu bırakır; yoksa fontSize TV'de yok sayılır.
        assertTrue(SubtitleServer.styleFrame(SubtitleStyle(autoSize = false)).contains("\"autoSize\":false"))
        // "TV'de Nino filigranını göster" kapalıysa TV yalnız sol alttaki Nino işaretini gizler (Mac ile aynı).
        assertTrue(SubtitleServer.styleFrame(SubtitleStyle(watermark = false)).contains("\"watermark\":false"))
    }

    @Test
    fun fontGoesToTheTvAndDefaultsToCondensed() {
        assertEquals(SubtitleFont.CONDENSED, SubtitleStyle().font)
        assertTrue(SubtitleServer.styleFrame(SubtitleStyle(font = SubtitleFont.ROUNDED)).contains("\"font\":\"rounded\""))
        assertTrue(SubtitleServer.styleFrame(SubtitleStyle(font = SubtitleFont.MODERN)).contains("\"font\":\"modern\""))
        assertTrue(SubtitleServer.styleFrame(SubtitleStyle(font = SubtitleFont.SYSTEM)).contains("\"font\":\"system\""))
        // Mac/Windows ile aynı adlar; eski kayıtta ad yoksa ya da tanınmıyorsa Aksiyon (condensed).
        assertEquals(listOf("condensed", "modern", "rounded", "system"), SubtitleFont.entries.map { it.wire })
        assertEquals(SubtitleFont.CONDENSED, SubtitleFont.from(null))
        assertEquals(SubtitleFont.CONDENSED, SubtitleFont.from("comic"))
        assertEquals(SubtitleFont.ROUNDED, SubtitleFont.from("rounded"))
        assertEquals(SubtitleFont.MODERN, SubtitleFont.from("MODERN"))
    }

    @Test
    fun helloIdentifiesTheServer() {
        val server = SubtitleServer(0)
        val port = server.start()
        try {
            Socket("127.0.0.1", port).use { socket ->
                socket.getOutputStream().write("GET /hello HTTP/1.1\r\nHost: x\r\n\r\n".toByteArray())
                val response = socket.getInputStream().readBytes().toString(Charsets.UTF_8)
                assertTrue(response, response.startsWith("HTTP/1.1 200 OK"))
                assertTrue(response.contains("Access-Control-Allow-Origin: *"))
                assertTrue(response.endsWith("{\"app\":\"couchsubs\"}"))
            }
        } finally {
            server.stop()
        }
    }

    @Test
    fun streamsStyleSubtitleClearAndPing() {
        val server = SubtitleServer(0, pingIntervalMs = 200, clock = { 42 })
        val port = server.start()
        try {
            server.sendStyle(SubtitleStyle())
            Socket("127.0.0.1", port).use { socket ->
                socket.soTimeout = 5000
                socket.getOutputStream().write("GET /events HTTP/1.1\r\nHost: x\r\n\r\n".toByteArray())
                val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
                val lines = mutableListOf<String>()
                fun readUntil(until: String) {
                    while (true) {
                        val line = reader.readLine() ?: return
                        lines.add(line)
                        if (line == until) return
                    }
                }
                readUntil("retry: 2000")
                assertTrue(lines.contains("Content-Type: text/event-stream; charset=utf-8"))
                readUntil("event: style")
                val deadline = System.currentTimeMillis() + 3000
                while (server.connectedClients != 1 && System.currentTimeMillis() < deadline) Thread.sleep(10)
                assertEquals(1, server.connectedClients)
                server.sendSubtitle("Merhaba", 4000, null)
                server.clear()
                readUntil("event: clear")
                assertTrue(lines.contains("data: {\"at\":42,\"duration\":4000,\"text\":\"Merhaba\"}"))
                readUntil("event: ping")
                assertEquals("data: {}", reader.readLine())
            }
        } finally {
            server.stop()
        }
    }

    @Test
    fun subtitlesStayOffTheTvWhenShownOnThePhone() {
        val server = SubtitleServer(0)
        server.sendsToTv = false
        val events = mutableListOf<SubtitleEvent>()
        server.onEvent = { events.add(it) }
        server.sendSubtitle("Merhaba", 1000, null)
        server.clear()
        assertEquals(listOf(SubtitleEvent.Subtitle("Merhaba", 1000), SubtitleEvent.Cleared), events)
    }

    /** `/events` akışını açar ve kısa süre içinde gelenleri döner (başlık ve ilk olaylar). */
    private fun openEvents(port: Int, query: String = "", waitMs: Int = 400): String =
        Socket("127.0.0.1", port).use { socket ->
            socket.soTimeout = waitMs
            socket.getOutputStream().write("GET /events$query HTTP/1.1\r\nHost: x\r\n\r\n".toByteArray())
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            try {
                while (true) {
                    val count = socket.getInputStream().read(buffer)
                    if (count <= 0) break
                    out.write(buffer, 0, count)
                }
            } catch (timeout: java.net.SocketTimeoutException) {
            }
            out.toString("UTF-8").also { assertTrue(it, it.contains("retry: 2000")) }
        }

    @Test
    fun startedIsReplayedToTvsConnectingWithinTwentySeconds() {
        var now = 1_000_000L
        val server = SubtitleServer(0, clock = { now })
        val port = server.start()
        try {
            // Çeviri başlamadan bağlanan TV "started" almaz.
            assertFalse(openEvents(port).contains("event: started"))
            server.sendStarted()
            now += 19_000
            val early = openEvents(port)
            assertTrue(early, early.contains("event: started\ndata: {}\n\n"))
            // İzleyici (OBS) balonu almaz.
            assertFalse(openEvents(port, "?viewer=obs").contains("event: started"))
            now += 1_000
            assertFalse(openEvents(port).contains("event: started"))
        } finally {
            server.stop()
        }
    }

    @Test
    fun startedIsBroadcastToConnectedTvsEvenWhenSubtitlesGoToThePhone() {
        val server = SubtitleServer(0)
        val port = server.start()
        server.sendsToTv = false
        try {
            Socket("127.0.0.1", port).use { socket ->
                socket.soTimeout = 2000
                socket.getOutputStream().write("GET /events HTTP/1.1\r\nHost: x\r\n\r\n".toByteArray())
                val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
                assertTrue(reader.readLine().startsWith("HTTP/1.1 200"))
                // Bağlantı listeye girene kadar bekle.
                val deadline = System.currentTimeMillis() + 2000
                while (server.connectedClients == 0 && System.currentTimeMillis() < deadline) Thread.sleep(10)
                server.sendStarted()
                var found = false
                while (!found) {
                    val line = reader.readLine() ?: break
                    found = line == "event: started"
                }
                assertTrue(found)
            }
        } finally {
            server.stop()
        }
    }
}
