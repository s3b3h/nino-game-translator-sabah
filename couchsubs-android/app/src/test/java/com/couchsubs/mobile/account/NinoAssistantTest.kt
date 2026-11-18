// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.account

import com.couchsubs.mobile.account.NinoAssistant.Result
import com.couchsubs.mobile.account.NinoAssistant.Turn
import com.couchsubs.mobile.translation.Http
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.URL
import java.util.Base64

/** "Nino'ya Sor": gövdenin biçimi (nino-pool/src/assistant.js), fotoğraf ve boy sınırları, yanıt eşlemesi. Ağa çıkmaz. */
class NinoAssistantTest {
    private val image = byteArrayOf(-1, -40, -1, 1, 2, 3)

    private fun messages(body: String) = JSONObject(body).getJSONArray("messages")

    @Test
    fun bodyHasServerShape() {
        val body = JSONObject(NinoAssistant.body("install-1234", "0.2.0", "tr",
            listOf(Turn(true, "  Merhaba  "), Turn(false, "Selam!"), Turn(true, "x".repeat(3000), listOf(image)))))
        assertEquals(1, body.getInt("v"))
        assertEquals("install-1234", body.getString("install"))
        assertEquals("0.2.0", body.getString("app"))
        assertEquals("android", body.getString("platform"))
        assertEquals("tr", body.getString("language"))
        val list = body.getJSONArray("messages")
        assertEquals(3, list.length())
        assertEquals("user", list.getJSONObject(0).getString("role"))
        assertEquals("Merhaba", list.getJSONObject(0).getString("text"))
        assertFalse(list.getJSONObject(0).has("images"))
        assertEquals("assistant", list.getJSONObject(1).getString("role"))
        val last = list.getJSONObject(2)
        assertEquals(NinoAssistant.MAX_TEXT, last.getString("text").length)
        val sent = last.getJSONArray("images").getJSONObject(0)
        assertEquals("image/jpeg", sent.getString("mime"))
        assertEquals(image.toList(), Base64.getDecoder().decode(sent.getString("data")).toList())
    }

    @Test
    fun keepsLast24MessagesAndSkipsEmptyOnes() {
        val turns = (1..30).map { Turn(it % 2 == 1, "m$it") } + Turn(false, "   ") + Turn(true, "son")
        val list = messages(NinoAssistant.body("install-1234", "1", "en", turns))
        assertEquals(NinoAssistant.MAX_MESSAGES, list.length())
        assertEquals("son", list.getJSONObject(list.length() - 1).getString("text"))
        for (i in 0 until list.length()) assertTrue(list.getJSONObject(i).getString("text").isNotBlank())
    }

    @Test
    fun onlyLastTwoImageMessagesCarryImages() {
        val turns = listOf(
            Turn(true, "", listOf(image)), Turn(false, "a"),
            Turn(true, "ikinci", listOf(image)), Turn(false, "b"),
            Turn(true, "üçüncü", listOf(image, image)), Turn(false, "c"),
            Turn(true, "dördüncü", listOf(image, image, image, image)),
        )
        val list = messages(NinoAssistant.body("install-1234", "1", "tr", turns))
        assertEquals(NinoAssistant.SCREENSHOT, list.getJSONObject(0).getString("text"))
        assertFalse(list.getJSONObject(0).has("images"))
        assertEquals("ikinci\n${NinoAssistant.SCREENSHOT}", list.getJSONObject(2).getString("text"))
        assertFalse(list.getJSONObject(2).has("images"))
        assertEquals(2, list.getJSONObject(4).getJSONArray("images").length())
        // En çok 3 fotoğraf.
        assertEquals(NinoAssistant.MAX_IMAGES, list.getJSONObject(6).getJSONArray("images").length())
    }

    @Test
    fun imageOnlyMessageIsSent() {
        val list = messages(NinoAssistant.body("install-1234", "1", "tr", listOf(Turn(true, "", listOf(image)))))
        assertEquals(1, list.length())
        assertEquals("", list.getJSONObject(0).getString("text"))
        assertEquals(1, list.getJSONObject(0).getJSONArray("images").length())
    }

    @Test
    fun fittedBodyDropsOlderImagesWhenTooBig() {
        val big = ByteArray(1000) { 7 }
        val turns = listOf(Turn(true, "a", listOf(big)), Turn(false, "b"), Turn(true, "c", listOf(big)))
        val full = NinoAssistant.body("install-1234", "1", "tr", turns).length
        // Tek fotoğraf sığar: eski mesaj "[screenshot]" olur, sonuncusu fotoğrafını korur.
        val one = NinoAssistant.fittedBody("install-1234", "1", "tr", turns, maxBytes = full - 100)!!
        val list = messages(one)
        assertFalse(list.getJSONObject(0).has("images"))
        assertEquals(1, list.getJSONObject(2).getJSONArray("images").length())
        // Hiç fotoğraf sığmaz: hepsi yazıya iner.
        val none = messages(NinoAssistant.fittedBody("install-1234", "1", "tr", turns, maxBytes = 400)!!)
        assertFalse(none.getJSONObject(2).has("images"))
        assertEquals("c\n${NinoAssistant.SCREENSHOT}", none.getJSONObject(2).getString("text"))
        assertNull(NinoAssistant.fittedBody("install-1234", "1", "tr", turns, maxBytes = 50))
    }

    @Test
    fun realisticChatFitsSixMegabytes() {
        val photo = ByteArray(NinoAssistant.MAX_IMAGE_BYTES)
        val turns = (1..4).flatMap { listOf(Turn(true, "soru $it", List(3) { photo }), Turn(false, "yanıt $it")) } + Turn(true, "son")
        val body = NinoAssistant.fittedBody("install-1234", "1", "tr", turns)!!
        assertTrue(body.toByteArray().size <= NinoAssistant.MAX_BODY_BYTES)
        val list = messages(body)
        // Son iki fotoğraflı mesaj (3. ve 4. soru) fotoğraflarıyla gider.
        assertEquals(3, list.getJSONObject(4).getJSONArray("images").length())
        assertEquals(3, list.getJSONObject(6).getJSONArray("images").length())
        assertFalse(list.getJSONObject(2).has("images"))
    }

    @Test
    fun mapsResponses() {
        assertEquals(Result.Reply("Merhaba!", null), NinoAssistant.result(200, """{"ok":true,"reply":" Merhaba! ","report":null}"""))
        assertEquals(Result.Reply("Gönderdim.", "r-42"), NinoAssistant.result(200, """{"ok":true,"reply":"Gönderdim.","report":"r-42"}"""))
        assertEquals(Result.Failed, NinoAssistant.result(200, """{"ok":true,"reply":""}"""))
        assertEquals(Result.Failed, NinoAssistant.result(200, "not json"))
        assertEquals(Result.Disabled, NinoAssistant.result(503, """{"ok":false,"error":"assistant_disabled"}"""))
        assertEquals(Result.Failed, NinoAssistant.result(503, "Service Unavailable"))
        assertEquals(Result.RateLimited, NinoAssistant.result(429, """{"ok":false,"error":"rate_limited"}"""))
        assertEquals(Result.Busy, NinoAssistant.result(429, """{"ok":false,"error":"busy"}"""))
        assertEquals(Result.TooLarge, NinoAssistant.result(413, """{"ok":false,"error":"image_too_large"}"""))
        assertEquals(Result.Invalid, NinoAssistant.result(400, """{"ok":false,"error":"bad_request"}"""))
        assertEquals(Result.Failed, NinoAssistant.result(502, """{"ok":false,"error":"model_failed"}"""))
        assertEquals(Result.Failed, NinoAssistant.result(502, """{"ok":false,"error":"refused"}"""))
    }

    @Test
    fun sendPostsToAssistantPath() {
        var seen: String? = null
        var timeout = 0
        val http = Http { method, url, headers, _, timeoutMs ->
            seen = "$method $url ${headers["Content-Type"]}"
            timeout = timeoutMs
            200 to """{"ok":true,"reply":"Selam","report":null}"""
        }
        val result = NinoAssistant.send(URL("https://pool.example/"), "{}", http)
        assertEquals(Result.Reply("Selam", null), result)
        assertEquals("POST https://pool.example/v1/assistant application/json", seen)
        assertEquals(NinoAssistant.TIMEOUT_MS, timeout)
    }

    @Test
    fun sendHandlesNetworkErrorsAndOversizedBodies() {
        assertEquals(Result.Failed, NinoAssistant.send(URL("https://pool.example/"), "{}", Http { _, _, _, _, _ -> throw IOException("down") }))
        var called = false
        val huge = "x".repeat(NinoAssistant.MAX_BODY_BYTES + 1)
        assertEquals(Result.TooLarge, NinoAssistant.send(URL("https://pool.example/"), huge, Http { _, _, _, _, _ -> called = true; 200 to "" }))
        assertFalse(called)
    }

    @Test
    fun findsLinksWithoutTrailingPunctuation() {
        val text = "Rehber: https://nino.example/kurulum. Ayrıca (http://a.example/b?c=1) bak."
        val found = NinoAssistant.links(text).map { text.substring(it) }
        assertEquals(listOf("https://nino.example/kurulum", "http://a.example/b?c=1"), found)
        assertTrue(NinoAssistant.links("bağlantı yok, ftp://x.example").isEmpty())
    }

    private fun paragraph(text: String) = NinoAssistant.Block(NinoAssistant.Block.Kind.PARAGRAPH, text)
    private fun step(number: String, text: String) = NinoAssistant.Block(NinoAssistant.Block.Kind.STEP, text, number)
    private fun bullet(text: String) = NinoAssistant.Block(NinoAssistant.Block.Kind.BULLET, text)

    @Test
    fun blocksSplitParagraphsAndSpacedSteps() {
        val reply = """
            Kolay yol var, TV'ye iki farklı şekilde kurabilirsin.

            1. Mac'inde Nino'yu aç ve ilk kurulumda TV seçimine gel.

            2. TV'ni seç (Android TV / Google TV, Samsung ya da LG); Nino uygulamayı TV'ye kendisi kurar.

            3. TV'de bir kez izin istenirse kumandayla onayla.

            Hangi TV markasını kullanıyorsun?
        """.trimIndent()
        assertEquals(listOf(
            paragraph("Kolay yol var, TV'ye iki farklı şekilde kurabilirsin."),
            step("1", "Mac'inde Nino'yu aç ve ilk kurulumda TV seçimine gel."),
            step("2", "TV'ni seç (Android TV / Google TV, Samsung ya da LG); Nino uygulamayı TV'ye kendisi kurar."),
            step("3", "TV'de bir kez izin istenirse kumandayla onayla."),
            paragraph("Hangi TV markasını kullanıyorsun?"),
        ), NinoAssistant.blocks(reply))
    }

    @Test
    fun blocksConsecutiveStepsInsideParagraph() {
        val reply = "Şunu dene:\r\n1. Ayarlar'ı aç.\n2) https://nino.example/kurulum adresine git.\n   Sayfa açılmazsa bekle.\nOlmazsa yaz.\nBen buradayım.\n\n\n"
        assertEquals(listOf(
            paragraph("Şunu dene:"),
            step("1", "Ayarlar'ı aç."),
            step("2", "https://nino.example/kurulum adresine git.\nSayfa açılmazsa bekle."),
            paragraph("Olmazsa yaz.\nBen buradayım."),
        ), NinoAssistant.blocks(reply))
    }

    @Test
    fun blocksBulletsAndNonSteps() {
        val reply = "Gerekenler:\n- PS5\n• Remote Play için ikinci hesap\n* Aynı Wi-Fi\n\n2024. yılında çıkan oyunlar da olur.\n10. adım: 1.5 saniye bekle."
        assertEquals(listOf(
            paragraph("Gerekenler:"),
            bullet("PS5"),
            bullet("Remote Play için ikinci hesap"),
            bullet("Aynı Wi-Fi"),
            paragraph("2024. yılında çıkan oyunlar da olur."),
            step("10", "adım: 1.5 saniye bekle."),
        ), NinoAssistant.blocks(reply))
        assertTrue(NinoAssistant.blocks("  \n\n").isEmpty())
        assertEquals(listOf(paragraph("-yok\n1.yok")), NinoAssistant.blocks("-yok\n1.yok"))
    }
}
