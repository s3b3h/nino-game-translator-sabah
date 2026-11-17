// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.account

import com.couchsubs.mobile.translation.Http
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.net.URL
import java.util.Base64

/** "Sorun Bildir": gövdenin biçimi (nino-pool/src/reports.js), fotoğraf küçültme, günlükten anahtar gizleme. Ağa çıkmaz. */
class ProblemReportTest {
    @get:Rule val folder = TemporaryFolder()

    @Test
    fun bodyHasServerShapeAndClipsFields() {
        val image = byteArrayOf(-1, -40, -1, 1, 2, 3)
        val body = JSONObject(ProblemReport.body("install-1234", "1.2.3", "tr", "  Altyazı gelmiyor  " + "x".repeat(5000),
            "  @nino  ", "log satırı", listOf(image, image, image, image)))
        assertEquals(1, body.getInt("v"))
        assertEquals("install-1234", body.getString("install"))
        assertEquals("1.2.3", body.getString("app"))
        assertEquals("android", body.getString("platform"))
        assertEquals("tr", body.getString("language"))
        assertEquals(ProblemReport.MAX_TEXT, body.getString("text").length)
        assertTrue(body.getString("text").startsWith("Altyazı gelmiyor"))
        assertEquals("@nino", body.getString("contact"))
        assertEquals("log satırı", body.getString("log"))
        val images = body.getJSONArray("images")
        assertEquals(3, images.length())
        assertEquals("image/jpeg", images.getJSONObject(0).getString("mime"))
        // Sunucu standart base64 bekler (+ ve /, URL-güvenli değil).
        assertTrue(image.contentEquals(Base64.getDecoder().decode(images.getJSONObject(0).getString("data"))))
    }

    @Test
    fun emptyContactAndLogAreLeftOut() {
        val body = JSONObject(ProblemReport.body("install-1234", "1", "tr", "Sorun", "   ", null, emptyList()))
        assertFalse(body.has("contact"))
        assertFalse(body.has("log"))
        assertEquals(0, body.getJSONArray("images").length())
        val long = JSONObject(ProblemReport.body("install-1234", "1", "tr", "Sorun", null, "a".repeat(70_000) + "SON", emptyList()))
        assertEquals(ProblemReport.MAX_LOG, long.getString("log").length)
        assertTrue(long.getString("log").endsWith("SON"))
    }

    @Test
    fun threeLargestImagesFitTheBodyLimit() {
        val image = ByteArray(ProblemReport.MAX_IMAGE_BYTES) { (it % 251).toByte() }
        val body = ProblemReport.body("install-1234", "1", "tr", "x".repeat(4000), "c".repeat(200), "l".repeat(60_000), List(3) { image })
        assertTrue(body.toByteArray(Charsets.UTF_8).size < ProblemReport.MAX_BODY_BYTES)
    }

    @Test
    fun sendMapsStatusCodes() {
        var sentUrl = ""
        var sentHeaders = emptyMap<String, String>()
        fun http(code: Int) = Http { _, url, headers, _, _ -> sentUrl = url; sentHeaders = headers; code to "{}" }
        val endpoint = URL("https://example.test")
        assertEquals(ProblemReport.Outcome.SENT, ProblemReport.send(endpoint, "{}", http(200)))
        assertEquals("https://example.test/v1/reports", sentUrl)
        assertEquals("application/json", sentHeaders["Content-Type"])
        assertEquals(ProblemReport.Outcome.INVALID, ProblemReport.send(endpoint, "{}", http(400)))
        assertEquals(ProblemReport.Outcome.TOO_LARGE, ProblemReport.send(endpoint, "{}", http(413)))
        assertEquals(ProblemReport.Outcome.RATE_LIMITED, ProblemReport.send(endpoint, "{}", http(429)))
        assertEquals(ProblemReport.Outcome.FAILED, ProblemReport.send(endpoint, "{}", http(500)))
        assertEquals(ProblemReport.Outcome.FAILED, ProblemReport.send(endpoint, "{}", Http { _, _, _, _, _ -> throw IOException("yok") }))
        var called = false
        val huge = "x".repeat(ProblemReport.MAX_BODY_BYTES + 1)
        assertEquals(ProblemReport.Outcome.TOO_LARGE, ProblemReport.send(endpoint, huge, Http { _, _, _, _, _ -> called = true; 200 to "" }))
        assertFalse(called)
    }

    @Test
    fun installIdComesFromPoolStateElseStoredOnce() {
        val dir = folder.newFolder()
        var stored: String? = null
        val first = ProblemReport.installId(dir, { stored }, { stored = it })
        assertEquals(first, stored)
        assertEquals(first, ProblemReport.installId(dir, { stored }, { error("yeniden üretilmemeli") }))
        File(dir, "pool").mkdirs()
        File(dir, "pool/state.json").writeText(JSONObject().put("install", "pool-install-id").toString())
        assertEquals("pool-install-id", ProblemReport.installId(dir, { stored }, { error("yeniden üretilmemeli") }))
    }

    @Test
    fun logScrubbingHidesKeysAndTokens() {
        val log = """
            11-18 10:00 I Nino: çeviri başladı
            Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature
            url=https://api.deepl.com/v2?auth_key=abcd1234-ef56:fx&x=1
            gemini AIzaSyA1234567890abcdefghijklmnopqrstu
            openai sk-proj-ABCDEFGHIJKLMNOPQRST123
            token: "s3cr3tValue"
            digest 0123456789abcdef0123456789abcdef01
            blob QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVphYmNkZWZnaGlqa2xtbm9w
        """.trimIndent()
        val scrubbed = ProblemReport.scrubLog(log)
        listOf("eyJhbGci", "abcd1234-ef56", "AIzaSy", "sk-proj", "s3cr3tValue", "0123456789abcdef0123", "QUJDREVGR0hJ").forEach {
            assertFalse("$it gizlenmeli", scrubbed.contains(it))
        }
        assertTrue(scrubbed.contains("çeviri başladı"))
        assertTrue(scrubbed.contains("gemini"))
    }

    @Test
    fun downscaleKeepsLongestSideAtMost1600() {
        assertEquals(1, ProblemReport.sampleSize(1600, 900))
        assertEquals(2, ProblemReport.sampleSize(4032, 3024))
        assertEquals(4, ProblemReport.sampleSize(8000, 6000))
        assertEquals(1600 to 1200, ProblemReport.scaledSize(4032, 3024))
        assertEquals(900 to 1600, ProblemReport.scaledSize(2160, 3840))
        assertEquals(800 to 600, ProblemReport.scaledSize(800, 600))
    }

    @Test
    fun fitJpegLowersQualityThenSize() {
        val tries = mutableListOf<Triple<Int, Int, Int>>()
        // Sahte kodlayıcı: bayt sayısı piksel × kalite ile büyür.
        val result = ProblemReport.fitJpeg(4000, 3000, maxBytes = 600_000) { w, h, q ->
            tries += Triple(w, h, q)
            ByteArray(w * h * q / 400)
        }
        assertEquals(Triple(1600, 1200, 70), tries.first())
        assertTrue(tries.all { maxOf(it.first, it.second) <= 1600 })
        assertTrue(result!!.size <= 600_000)
        assertNull(ProblemReport.fitJpeg(4000, 3000, maxBytes = 10) { w, h, _ -> ByteArray(w * h) })
    }
}
