// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile

import com.couchsubs.mobile.core.LinePool
import com.couchsubs.mobile.core.PackKey
import com.couchsubs.mobile.core.RunningGame
import com.couchsubs.mobile.remoteplay.PsnAccount
import com.couchsubs.mobile.remoteplay.PsnPageProblem
import com.couchsubs.mobile.remoteplay.RegisteredConsole
import com.couchsubs.mobile.remoteplay.Registration
import com.couchsubs.mobile.remoteplay.RegistrationFailure
import com.couchsubs.mobile.translation.AiModel
import com.couchsubs.mobile.translation.AiProvider
import com.couchsubs.mobile.translation.AiRequest
import com.couchsubs.mobile.translation.AiTranslator
import com.couchsubs.mobile.translation.DeepLTranslator
import com.couchsubs.mobile.translation.Http
import com.couchsubs.mobile.translation.OnlineKeyState
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.IOException
import java.net.URL
import java.nio.file.Files

class RemotePlayLogicTest {
    @Test
    fun pinIsParsedLikeTheDesktop() {
        assertEquals(12345678, Registration.parsePin("1234 5678"))
        assertEquals(12345678, Registration.parsePin("1234-5678"))
        assertEquals(1, Registration.parsePin("00000001"))
        assertNull(Registration.parsePin("1234567"))
        assertNull(Registration.parsePin("1234567a"))
        assertEquals(12345678, Registration.parsePin("١٢٣٤٥٦٧٨"))
    }

    @Test
    fun failuresAreExplained() {
        assertEquals(RegistrationFailure.WRONG_ACCOUNT, Registration.failureFrom(0x80108b02.toInt(), emptyList()))
        assertEquals(RegistrationFailure.WRONG_CODE, Registration.failureFrom(0x80108b09.toInt(), emptyList()))
        assertEquals(RegistrationFailure.NO_ANSWER, Registration.failureFrom(null, listOf("Regist search failed")))
        assertEquals(RegistrationFailure.FAILED, Registration.failureFrom(null, emptyList()))
        assertEquals("0x80108b09 (Regist failed)", Registration.detailFrom(listOf("x", "Reported Application Reason: 0x80108b09 (Regist failed)")))
    }

    @Test
    fun accountIdIsLittleEndian() {
        assertArrayEquals(byteArrayOf(1, 0, 0, 0, 0, 0, 0, 0), PsnAccount.accountIdBytes("1"))
        assertArrayEquals(ByteArray(8) { -1 }, PsnAccount.accountIdBytes("18446744073709551615"))
        assertNull(PsnAccount.accountIdBytes("-1"))
        assertNull(PsnAccount.accountIdBytes("abc"))
    }

    @Test
    fun redirectGivesCodeOrSonyError() {
        val base = PsnAccount.REDIRECT_PREFIX
        assertEquals("v3.abc", PsnAccount.codeFromRedirect("$base?code=v3.abc&cid=1"))
        assertNull(PsnAccount.codeFromRedirect("https://example.com/?code=x"))
        assertEquals("access_denied: User denied (4165)",
            PsnAccount.errorFromRedirect("$base?error=access_denied&error_description=User+denied&error_code=4165"))
        assertTrue(PsnAccount.authorizeUrl.contains("redirect_uri=https://remoteplay.dl.playstation.net/remoteplay/redirect"))
        assertTrue(PsnAccount.authorizeUrl.contains("scope=psn:clientapp%20referenceDataService"))
    }

    @Test
    fun pastedBrowserAddressGivesRedirect() {
        val base = PsnAccount.REDIRECT_PREFIX
        assertEquals("$base?code=v3.abc&cid=1", PsnAccount.redirectFromText("  $base?code=v3.abc&cid=1\n"))
        assertEquals("$base?code=v3.abc", PsnAccount.redirectFromText("Adres: $base?code=v3.abc bu"))
        assertEquals("$base?error=access_denied", PsnAccount.redirectFromText("$base?error=access_denied"))
        assertNull(PsnAccount.redirectFromText(base))
        assertNull(PsnAccount.redirectFromText("$base?cid=1"))
        assertNull(PsnAccount.redirectFromText("https://example.com/?code=x"))
    }

    @Test
    fun googleSignInIsDetected() {
        assertTrue(PsnAccount.isGoogleSignIn("https://accounts.google.com/o/oauth2/v2/auth?client_id=x"))
        assertTrue(PsnAccount.isGoogleSignIn("https://ACCOUNTS.google.com/signin"))
        assertFalse(PsnAccount.isGoogleSignIn("https://my.account.sony.com/?next=accounts.google.com"))
        assertFalse(PsnAccount.isGoogleSignIn("https://accounts.google.com.evil.example/"))
        assertFalse(PsnAccount.isGoogleSignIn("not a url"))
    }

    @Test
    fun loginPageProblemsAreTold() {
        assertEquals(PsnPageProblem.OFFLINE, PsnPageProblem.fromWebError(-2))
        assertEquals(PsnPageProblem.OFFLINE, PsnPageProblem.fromWebError(-6))
        assertEquals(PsnPageProblem.TIMEOUT, PsnPageProblem.fromWebError(-8))
        assertEquals(PsnPageProblem.SSL, PsnPageProblem.fromWebError(-11))
        assertEquals(PsnPageProblem.OTHER, PsnPageProblem.fromWebError(-1))
        assertTrue(PsnPageProblem.looksBlank("0"))
        assertTrue(PsnPageProblem.looksBlank("null"))
        assertFalse(PsnPageProblem.looksBlank("42"))
    }

    @Test
    fun wakeCredentialIsTheHexRegistKey() {
        val key = "0a1b2c3d".toByteArray() + ByteArray(8)
        assertEquals(0x0a1b2c3dL, RegisteredConsole("h", "PS5", key, ByteArray(16)).wakeCredential)
    }
}

class OnlineTranslationTest {
    private class FakeHttp(val status: Int, val body: String) : Http {
        val requests = mutableListOf<Triple<String, Map<String, String>, String?>>()
        override fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutMs: Int): Pair<Int, String> {
            requests.add(Triple(url, headers, body))
            return status to this.body
        }
    }

    @Test
    fun deepLSendsSentencesAndKeepsSpeakerLabels() {
        val http = FakeHttp(200, "{\"translations\":[{\"text\":\"Şimdi gidiyoruz.\"},{\"text\":\"Yakın dur, evlat.\"}]}")
        val translator = DeepLTranslator("abc:fx", null, http)
        assertEquals("KRATOS: Şimdi gidiyoruz. Yakın dur, evlat.", translator.translate("KRATOS: We go now. Stay close, boy."))
        val (url, headers, body) = http.requests.single()
        assertEquals("https://api-free.deepl.com/v2/translate", url)
        assertEquals("DeepL-Auth-Key abc:fx", headers["Authorization"])
        val json = JSONObject(body!!)
        assertEquals(2, json.getJSONArray("text").length())
        assertEquals("prefer_less", json.getString("formality"))
        // Aynı satır ikinci kez sorulmaz.
        translator.translate("KRATOS: We go now. Stay close, boy.")
        assertEquals(1, http.requests.size)
    }

    @Test
    fun failureFallsBackToTheLocalEngine() {
        val translator = DeepLTranslator("bad", { "yerel: $it" }, FakeHttp(403, ""))
        assertEquals("yerel: Run!", translator.translate("Run!"))
        assertEquals(OnlineKeyState.INVALID, translator.lastError)
    }

    @Test
    fun claudeRequestShapeAndReply() {
        val http = FakeHttp(200, "{\"content\":[{\"type\":\"thinking\",\"thinking\":\"…\"},{\"type\":\"text\",\"text\":\"[\\\"Koş!\\\"]\"}]}")
        val translator = AiTranslator(AiProvider.CLAUDE, "sk", AiModel("claude-x", "Hızlı", effort = "low"), null, http)
        assertEquals("Koş!", translator.translate("Run!"))
        val (url, headers, body) = http.requests.single()
        assertEquals("https://api.anthropic.com/v1/messages", url)
        assertEquals("2023-06-01", headers["anthropic-version"])
        val json = JSONObject(body!!)
        assertEquals("claude-x", json.getString("model"))
        assertEquals("low", json.getJSONObject("output_config").getString("effort"))
        assertTrue(json.getJSONArray("messages").getJSONObject(0).getString("content").endsWith("[\"Run!\"]"))
    }

    @Test
    fun aiCacheIsScopedByTheGameAndTheGameGoesToTheModel() {
        val http = FakeHttp(200, "{\"content\":[{\"type\":\"text\",\"text\":\"[\\\"Banka kapalı.\\\"]\"}]}")
        var game: String? = null
        val translator = AiTranslator(AiProvider.CLAUDE, "sk", AiModel("claude-x", "Hızlı"), null, http, playedGame = { game })
        translator.translate("The bank is close.")
        // Oyun bilinmiyorken eski (oyunsuz) kayıt kullanılır.
        translator.translate("The bank is close.")
        assertEquals(1, http.requests.size)
        game = " Red Dead Redemption 2 "
        translator.translate("The bank is close.")
        assertEquals(2, http.requests.size)
        val body = JSONObject(http.requests.last().third!!).getJSONArray("messages").getJSONObject(0).getString("content")
        assertTrue(body.startsWith("Game: Red Dead Redemption 2\n"))
        translator.translate("The bank is close.")
        assertEquals(2, http.requests.size)
        game = "Mafia"
        translator.translateAll(listOf("The bank is close."))
        assertEquals(3, http.requests.size)
    }

    @Test
    fun translationsAcceptFencedArraysAndPlainText() {
        assertEquals(listOf("Bir", "İki"), AiRequest.translations("```json\n[\"Bir\", \"İki\"]\n```", 2))
        assertEquals(listOf("Koş!"), AiRequest.translations("\"Koş!\"", 1))
        // Tırnaksız dizi (#27): köşeli parantezler ekranda kalmaz, cümle içi virgül bölünmez.
        assertEquals(listOf("Hareket etmemiz lazım."), AiRequest.translations("[Hareket etmemiz lazım.]", 1))
        assertEquals(listOf("Geri çekil lan!"), AiRequest.translations("<think>…</think>\n[Geri çekil lan!]", 1))
        assertEquals(listOf("[gülüyor] Hadi."), AiRequest.translations("[gülüyor] Hadi.", 1))
        assertEquals(listOf("Satır bir.", "Satır iki."), AiRequest.translations("[Satır bir., Satır iki.]", 2))
        assertEquals(listOf("Gidelim.", "Yakın dur."), AiRequest.translations("[\n  Gidelim.,\n  Yakın dur.\n]", 2))
        assertEquals(listOf("Evet, efendim.", "Hayır, gitmiyorum."), AiRequest.translations("[Evet, efendim., Hayır, gitmiyorum.]", 2))
        assertNull(AiRequest.unquotedList("[Dur, bekle, gitme.]", 2))
        assertEquals(listOf("Dur, bekle, gitme."), AiRequest.translations("[Dur, bekle, gitme.]", 1))
        assertNull(AiRequest.unquotedList("[Satır bir.]", 2))
        // Yerel modellerin bitiş işaretleri ekranda kalmaz; sondaki fazla virgül diziyi bozmaz (#27).
        assertEquals(listOf("Yere yat!"), AiRequest.translations("[\"Yere yat!\"]</s>", 1))
        assertEquals(listOf("Yere yat!"), AiRequest.translations("[Yere yat!]</s>", 1))
        assertEquals(listOf("Defol buradan!"), AiRequest.translations("Defol buradan!<|im_end|>", 1))
        assertEquals(listOf("Bir.", "İki."), AiRequest.translations("<s>[\"Bir.\", \"İki.\",]<|eot_id|>", 2))
        assertEquals(listOf("<b> etiketi kalır"), AiRequest.translations("[\"<b> etiketi kalır\"]", 1))
        assertEquals(OnlineKeyState.INVALID, AiRequest.failure(400, "API key not valid"))
        assertEquals(OnlineKeyState.MODEL_REJECTED, AiRequest.failure(404, ""))
    }

    @Test
    fun sharedModelListParses() {
        val file = File(System.getProperty("couchsubs.packs") ?: return, "../ai-models.json")
        val models = AiModel.parse(file.readText())
        assertTrue(models.keys.containsAll(listOf("gemini", "openai", "claude")))
        assertTrue(models.getValue("gemini").first().freeTier)
    }
}

class LinePoolTest {
    @Test
    fun acceptsOnlyRealLines() {
        assertTrue(LinePool.accepts("Get in the car, Enzo."))
        assertFalse(LinePool.accepts("Hello"))
        assertFalse(LinePool.accepts("100/100 HP 25%"))
        assertFalse(LinePool.accepts("Across ou$3e waters"))
        assertFalse(LinePool.accepts("x ".repeat(200)))
    }

    @Test
    fun queuedLinesAreSentOnceAndSurviveRestart() {
        val file = File(Files.createTempDirectory("pool").toFile(), "pool.json")
        val bodies = mutableListOf<String>()
        var status = 503
        val post = { _: URL, body: String -> bodies.add(body); status to null }
        val pool = LinePool(file, "test", post = post, clock = { 1_700_000_000_000 })
        pool.offer("Get in the car, Enzo.")
        pool.offer("Get in the car, Enzo.")
        pool.flush()
        assertEquals(1, pool.queued.size)
        val reopened = LinePool(file, "test", post = post, clock = { 1_700_000_000_000 })
        assertEquals(1, reopened.queued.size)
        assertEquals(pool.installId, reopened.installId)
        status = 200
        reopened.flush()
        assertEquals(0, reopened.queued.size)
        val sent = JSONObject(bodies.last())
        assertEquals("android", sent.getString("platform"))
        val line = sent.getJSONArray("lines").getJSONObject(0)
        assertEquals(PackKey.key("Get in the car, Enzo."), line.getString("key"))
        assertEquals("2023-11-14T22:13:20Z", line.getString("firstSeen"))
        // Gönderilen satır yeniden kuyruğa girmez.
        reopened.offer("Get in the car, Enzo.")
        assertEquals(0, reopened.queued.size)
    }

    /** PS5'te çalışan oyun bilinince satırla gider ve kuyruk dosyasında kalır; bilinmiyorsa alanlar hiç yazılmaz. */
    @Test
    fun runningGameTravelsWithTheLine() {
        val file = File(Files.createTempDirectory("pool").toFile(), "pool.json")
        val bodies = mutableListOf<String>()
        var status = 503
        val post = { _: URL, body: String -> bodies.add(body); status to null }
        val pool = LinePool(file, "test", post = post, clock = { 1_700_000_000_000 })
        pool.offer("Who is that over there?")
        pool.setGame(RunningGame.create("ppsa12345", "  Grand Theft Auto VI\n"))
        pool.offer("Get in the car, Lucia.")
        pool.setGame(null)
        pool.offer("Keep your head down, Jason.")
        pool.flush()
        val reopened = LinePool(file, "test", post = post, clock = { 1_700_000_000_000 })
        assertEquals("PPSA12345", reopened.queued[1].titleId)
        assertEquals("Grand Theft Auto VI", reopened.queued[1].game)
        status = 200
        reopened.flush()
        val lines = JSONObject(bodies.last()).getJSONArray("lines")
        assertFalse(lines.getJSONObject(0).has("titleId"))
        assertEquals("PPSA12345", lines.getJSONObject(1).getString("titleId"))
        assertEquals("Grand Theft Auto VI", lines.getJSONObject(1).getString("game"))
        assertFalse(lines.getJSONObject(2).has("game"))
    }

    @Test
    fun runningGameValidatesTheTitleId() {
        assertEquals("CUSA00419_00", RunningGame.create("CUSA00419_00", null)?.titleId)
        assertNull(RunningGame.create("PPSA1234", "x"))
        assertNull(RunningGame.create("PPSA01234_0", "x"))
        assertNull(RunningGame.create(null, "x"))
        assertNull(RunningGame.create("PPSA01234", " \u0000 ")?.name)
        assertEquals(120, RunningGame.create("PPSA01234", "x".repeat(300))?.name?.length)
        // Yerel kütüphanenin keşif satırı: eski biçim (üç alan) ve oyunlu biçim.
        val old = com.couchsubs.mobile.remoteplay.ConsoleDiscovery.parseLine("192.168.1.20\tPS5-123\t1")
        assertNull(old?.runningAppTitleId)
        val playing = com.couchsubs.mobile.remoteplay.ConsoleDiscovery.parseLine("192.168.1.20\tPS5-123\t1\tPPSA12345\tGrand Theft Auto VI")
        assertEquals("PPSA12345", playing?.runningAppTitleId)
        assertEquals("Grand Theft Auto VI", playing?.runningAppName)
        assertNull(com.couchsubs.mobile.remoteplay.ConsoleDiscovery.parseLine("192.168.1.20\tPS5-123\t0\t\t")?.runningAppName)
    }

    @Test
    fun disablingDropsTheQueue() {
        val pool = LinePool(File(Files.createTempDirectory("pool").toFile(), "pool.json"), "test", post = { _, _ -> throw IOException() })
        pool.offer("Get in the car, Enzo.")
        pool.setEnabled(false)
        assertEquals(0, pool.queued.size)
        pool.offer("Who is that man?")
        assertEquals(0, pool.queued.size)
    }
}
