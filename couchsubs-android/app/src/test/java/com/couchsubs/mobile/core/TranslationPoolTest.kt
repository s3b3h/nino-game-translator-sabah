// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.net.URL
import java.nio.file.Files
import java.util.UUID

/** Nino çeviri havuzu (Mac/iPhone: TranslationPoolTests.swift ile aynı durumlar). */
class TranslationPoolTest {
    /** Sahte sunucu: istekleri kaydeder, yola göre cevap verir. */
    private class FakeServer {
        val requests = mutableListOf<TranslationPool.Request>()
        var translateReply: (TranslationPool.Request) -> String = { """{"ok":true,"translations":[{"text":"Kim lan sen?","tier":1}]}""" }
        val pages = ArrayDeque(listOf("""{"ok":true,"now":10,"items":[],"next":null}"""))
        var identifyReply: String = """{"ok":true,"game":"Mafia: The Old Country","id":"mafia-the-old-country","confidence":0.92}"""
        var config = """{"ok":true,"translate":{"enabled":true,"deadlineMs":700,"syncSeconds":60,"contextLines":2,"maxLines":12}}"""

        fun handle(request: TranslationPool.Request): NinoPool.Response = synchronized(this) {
            requests += request
            val path = request.url.path
            val body = when {
                path.endsWith("/v1/config") -> config
                path.endsWith("/v1/translate") -> translateReply(request)
                path.endsWith("/v1/ping") -> ""
                path.endsWith("/v1/identify") -> identifyReply
                else -> pages.removeFirstOrNull() ?: """{"ok":true,"items":[],"next":null}"""
            }
            NinoPool.Response(if (path.endsWith("/v1/ping")) 204 else 200, body, null)
        }

        fun paths() = synchronized(this) { requests.map { it.url.path } }
        fun calls(suffix: String) = synchronized(this) { requests.filter { it.url.path.endsWith(suffix) } }
    }

    private val directories = mutableListOf<File>()
    private var now = 1_763_300_000_000L

    private fun newDirectory() = Files.createTempDirectory("translations").toFile().also { directories += it }

    private fun makePool(server: FakeServer, directory: File = newDirectory(), language: String = "tr", enabled: Boolean = true) =
        TranslationPool(directory, URL("https://pool.test"), UUID.randomUUID().toString(), "0.2.2", "android", language, enabled,
            { server.handle(it) }) { now }

    @After fun tearDown() { directories.forEach { it.deleteRecursively() } }

    @Test fun translateAsksServerOnceAndRemembers() {
        val server = FakeServer()
        val pool = makePool(server)
        val first = pool.translate("Who the fuck are you?", listOf("Hey.", "Back up!", "Wait."), "Grand Theft Auto VI")
        assertEquals("Kim lan sen?", first)
        assertEquals("Kim lan sen?", pool.store.match("WHO THE FUCK ARE YOU"))
        pool.translate("Who the fuck are you?")
        val calls = server.calls("/v1/translate")
        assertEquals(1, calls.size)
        assertEquals("POST", calls[0].method)
        val body = JSONObject(calls[0].body!!)
        assertEquals(1, body.getInt("v"))
        assertEquals("tr", body.getString("lang"))
        assertEquals("android", body.getString("platform"))
        assertEquals("grand-theft-auto-vi", body.getString("game"))
        assertEquals(listOf("Who the fuck are you?"), body.getJSONArray("lines").toList())
        // Sunucu ayarındaki kadar bağlam gider.
        assertEquals(listOf("Back up!", "Wait."), body.getJSONArray("context").toList())
    }

    @Test fun concurrentRequestsForSameLineAreSentOnce() {
        val server = FakeServer()
        val started = java.util.concurrent.CountDownLatch(1)
        val release = java.util.concurrent.CountDownLatch(1)
        server.translateReply = {
            started.countDown()
            release.await()
            """{"ok":true,"translations":[{"text":"Yere yat!","tier":1}]}"""
        }
        val pool = makePool(server)
        pool.refreshConfig(force = true)
        val results = java.util.Collections.synchronizedList(mutableListOf<String?>())
        val first = Thread { results += pool.translate("Get down!") }.apply { start() }
        started.await()
        // İlk istek sürerken (sunucu kilidi tutmasın diye) ikincisi ayrı iş parçacığında bekler.
        val second = Thread { results += pool.translate("Get down!") }.apply { start() }
        Thread.sleep(100)
        release.countDown()
        first.join(5000)
        second.join(5000)
        assertEquals(listOf("Yere yat!", "Yere yat!"), results.toList())
        assertEquals(1, server.calls("/v1/translate").size)
    }

    @Test fun nullTranslationIsNotStored() {
        val server = FakeServer()
        server.translateReply = { """{"ok":true,"limited":"daily_cap","translations":[{"text":null,"tier":0}]}""" }
        val pool = makePool(server)
        assertNull(pool.translate("Get down!"))
        assertNull(pool.store.match("Get down!"))
        assertEquals(0, pool.store.count)
    }

    @Test fun syncDownloadsPagesAndSavesPerLanguage() {
        val server = FakeServer()
        val car = PackKey.key("Get in the car!")!!
        val move = PackKey.key("Move!")!!
        server.pages.clear()
        server.pages += """{"ok":true,"now":50,"items":[["$car","Bin arabaya!",20,1]],"next":{"since":20,"after":"$car"}}"""
        server.pages += """{"ok":true,"now":50,"items":[["$move","Yürü!",30,2],["${PackKey.key("Stop!")}",null,31,0]],"next":null}"""
        val directory = newDirectory()
        val pool = makePool(server, directory)
        assertEquals(2, pool.sync("gta-vi"))
        assertEquals("Bin arabaya!", pool.store.match("get in the car"))
        assertNull(pool.store.match("Stop!"))
        val urls = server.calls("/v1/translations").map { it.url }
        assertEquals(2, urls.size)
        assertTrue(urls[0].query.contains("lang=tr"))
        assertTrue(urls[0].query.contains("game=gta-vi"))
        assertTrue(urls[0].query.contains("since=0"))
        assertFalse(urls[0].query.contains("after="))
        assertTrue(urls[1].query.contains("since=20"))
        assertTrue(urls[1].query.contains("after=$car"))
        // Aralık dolmadan yeniden sormaz; diskten yeniden açılınca çeviriler durur.
        pool.sync("gta-vi")
        assertEquals(2, server.calls("/v1/translations").size)
        // Aralık dolunca kaldığı yerden (son güncelleme zamanından) sorar.
        now += 61_000
        pool.sync("gta-vi")
        assertTrue(server.calls("/v1/translations").last().url.query.contains("since=30"))
        val reopened = makePool(FakeServer(), directory)
        assertEquals("Yürü!", reopened.store.match("Move!"))
        assertTrue(File(directory, "translations-tr.json").exists())
        // Başka dilde boş başlar; geri dönünce yine yüklenir.
        reopened.setLanguage("ar")
        assertNull(reopened.store.match("Move!"))
        reopened.setLanguage("tr-TR")
        assertEquals("Yürü!", reopened.store.match("Move!"))
    }

    @Test fun disabledPoolSendsNothing() {
        val server = FakeServer()
        val pool = makePool(server, enabled = false)
        assertNull(pool.translate("Get down!"))
        pool.sync(null)
        pool.ping("gta-vi")
        assertFalse(server.paths().any { it.endsWith("/v1/translate") || it.endsWith("/v1/translations") || it.endsWith("/v1/ping") })
    }

    @Test fun turningPoolOffForgetsTranslations() {
        val server = FakeServer()
        val directory = newDirectory()
        val pool = makePool(server, directory)
        pool.translate("Who the fuck are you?")
        // Kaydetmeden kapatılır: çeviri yine diskte kalır, kapalıyken kaydetmek onu silmez.
        pool.setEnabled(false)
        assertNull(pool.store.match("Who the fuck are you?"))
        assertNull(pool.translate("Get down!"))
        assertEquals(1, server.calls("/v1/translate").size)
        pool.save()
        assertEquals("Kim lan sen?", makePool(FakeServer(), directory).store.match("Who the fuck are you?"))
        pool.setEnabled(true)
        assertEquals("Kim lan sen?", pool.store.match("Who the fuck are you?"))
    }

    @Test fun serverCanSwitchPoolOff() {
        val server = FakeServer()
        server.config = """{"ok":true,"translate":{"enabled":false,"deadlineMs":700,"syncSeconds":60,"contextLines":2,"maxLines":12}}"""
        val pool = makePool(server)
        pool.refreshConfig(force = true)
        assertNull(pool.translate("Get down!"))
        assertEquals(0, pool.sync("gta-vi", force = true))
        assertFalse(server.paths().any { it.endsWith("/v1/translate") || it.endsWith("/v1/translations") })
    }

    @Test fun noiseIsNotSent() {
        val server = FakeServer()
        val pool = makePool(server)
        assertNull(pool.translate("!!!"))
        assertNull(pool.translate("Ali oturum açtı ğş"))
        assertFalse(server.paths().any { it.endsWith("/v1/translate") })
    }

    @Test fun pingSaysWhoIsPlaying() {
        val server = FakeServer()
        val pool = makePool(server, language = "ar")
        pool.ping("Grand Theft Auto VI")
        val ping = server.calls("/v1/ping").single()
        assertEquals("GET", ping.method)
        val query = ping.url.query.split("&").associate { it.substringBefore("=") to it.substringAfter("=") }
        assertTrue(runCatching { UUID.fromString(query["install"]) }.isSuccess)
        assertEquals("android", query["platform"])
        assertEquals("0.2.2", query["app"])
        assertEquals("grand-theft-auto-vi", query["game"])
        assertEquals("ar", query["lang"])
        // Oyun bilinmiyorsa boş gider; sunucuya ulaşılamasa da hata vermez.
        pool.ping(null)
        assertEquals("", server.calls("/v1/ping").last().url.query.split("&").first { it.startsWith("game=") }.removePrefix("game="))
        val offline = TranslationPool(newDirectory(), URL("https://pool.test"), null, "0.2.2", "android", "tr", true,
            { throw java.io.IOException("çevrimdışı") }) { now }
        offline.ping("gta-vi")
    }

    @Test fun contextKeepsRecentLinesOnly() {
        var time = 0L
        val context = PoolContext { time }
        assertEquals(emptyList<String>(), context.add("Hey."))
        time += 1000
        assertEquals(listOf("Hey."), context.add("Back up!"))
        time += 31_000
        assertEquals(emptyList<String>(), context.add("Wait."))
    }

    @Test fun identifySendsTheFrameAndReturnsTheGame() {
        val server = FakeServer()
        val pool = makePool(server)
        val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 1, 2, 3)
        assertEquals("Mafia: The Old Country", pool.identify(jpeg))
        val call = server.calls("/v1/identify").single()
        assertEquals("POST", call.method)
        val body = JSONObject(call.body!!)
        assertEquals(1, body.getInt("v"))
        assertEquals("android", body.getString("platform"))
        assertEquals("0.2.2", body.getString("app"))
        assertTrue(runCatching { UUID.fromString(body.getString("install")) }.isSuccess)
        assertEquals(java.util.Base64.getEncoder().encodeToString(jpeg), body.getString("image"))
        // Ping ile aynı kurulum kimliği.
        pool.ping("Mafia: The Old Country")
        val ping = server.calls("/v1/ping").single().url.query.split('&').associate { it.substringBefore('=') to java.net.URLDecoder.decode(it.substringAfter('='), "UTF-8") }
        assertEquals(body.getString("install"), ping["install"])
        assertEquals("mafia-the-old-country", ping["game"])
    }

    @Test fun identifyUnknownOrDisabledGivesNull() {
        val server = FakeServer()
        val pool = makePool(server)
        server.identifyReply = """{"ok":true,"game":null,"id":null,"confidence":0}"""
        assertNull(pool.identify(byteArrayOf(1, 2, 3)))
        server.identifyReply = """{"ok":true,"game":"  "}"""
        assertNull(pool.identify(byteArrayOf(1, 2, 3)))
        // Çok büyük kare gönderilmez.
        assertNull(pool.identify(ByteArray(TranslationPool.MAX_IDENTIFY_BYTES + 1)))
        assertEquals(2, server.calls("/v1/identify").size)
        val off = FakeServer()
        assertNull(makePool(off, enabled = false).identify(byteArrayOf(1, 2, 3)))
        assertTrue(off.calls("/v1/identify").isEmpty())
    }

    @Test fun contextBeforeDoesNotAddTheLine() {
        var time = 0L
        val context = PoolContext { time }
        context.add("Hey.")
        time += 1000
        context.add("Back up!")
        assertEquals(listOf("Hey."), context.before("Back up!"))
        assertEquals(listOf("Hey.", "Back up!"), context.before("Wait."))
        assertEquals(listOf("Hey.", "Back up!"), context.add("Wait."))
        time += 31_000
        assertEquals(emptyList<String>(), context.before("Go."))
    }

    // --- Havuz öncelikli oyunlar (poolFirst) ---

    @Test fun poolFirstDefaultsToGta6() {
        val pool = makePool(FakeServer())
        assertTrue(pool.isPoolFirst("Grand Theft Auto VI"))
        assertTrue(pool.isPoolFirst("GTA VI"))
        assertTrue(pool.isPoolFirst("gta6"))
        assertFalse(pool.isPoolFirst("Grand Theft Auto V"))
        assertFalse(pool.isPoolFirst("Red Dead Redemption 2"))
        assertFalse(pool.isPoolFirst(null))
        assertEquals(1500, pool.poolFirst.deadlineMs)
        // Eski sunucu poolFirst göndermez: varsayılan kalır.
        pool.refreshConfig(force = true)
        assertTrue(pool.isPoolFirst("Grand Theft Auto VI"))
        assertEquals(1500, pool.poolFirst.deadlineMs)
    }

    @Test fun poolFirstListAndDeadlineComeFromServer() {
        val server = FakeServer()
        server.config = """{"translate":{"enabled":true},"poolFirst":{"games":["mafia-the-old-country"],"deadlineMs":700}}"""
        val pool = makePool(server)
        pool.refreshConfig(force = true)
        assertTrue(pool.isPoolFirst("Mafia: The Old Country"))
        assertFalse(pool.isPoolFirst("Grand Theft Auto VI"))
        assertEquals(700, pool.poolFirst.deadlineMs)
    }

    @Test fun poolFirstOffWhenServerTurnsTranslationOff() {
        val server = FakeServer()
        server.config = """{"translate":{"enabled":false}}"""
        val pool = makePool(server)
        pool.refreshConfig(force = true)
        assertFalse(pool.isPoolFirst("Grand Theft Auto VI"))
    }

    @Test fun poolFirstGameIsAskedEvenWhenSharingIsOff() {
        val server = FakeServer()
        val pool = makePool(server, enabled = false)
        assertEquals("Kim lan sen?", pool.translate("Who the fuck are you?", emptyList(), "Grand Theft Auto VI"))
        assertNull(pool.translate("Open the door now.", emptyList(), "Red Dead Redemption 2"))
        val post = server.calls("/v1/translate").single()
        assertEquals("grand-theft-auto-vi", JSONObject(post.body!!).getString("game"))
        // Ortak havuz kapalıyken öbür istekler yine gitmez.
        pool.sync("Grand Theft Auto VI", force = true)
        pool.ping("Grand Theft Auto VI")
        assertFalse(server.paths().any { it.endsWith("/v1/translations") || it.endsWith("/v1/ping") })
    }

    @Test fun translateFirstGivesUpAfterDeadlineButKeepsLateAnswer() {
        val server = FakeServer()
        server.config = """{"translate":{"enabled":true},"poolFirst":{"games":["grand-theft-auto-vi"],"deadlineMs":150}}"""
        val pool = makePool(server)
        pool.refreshConfig(force = true)
        val release = java.util.concurrent.CountDownLatch(1)
        server.translateReply = {
            release.await()
            """{"ok":true,"translations":[{"text":"Kapıyı tut.","tier":1}]}"""
        }
        try {
            val started = System.nanoTime()
            assertNull(pool.translateFirst("Hold the gate.", emptyList(), "Grand Theft Auto VI"))
            val waited = (System.nanoTime() - started) / 1_000_000
            assertTrue("bekleme $waited ms", waited in 100..3000)
            // Geç gelen çeviri kaybolmaz: aynı satırın süren isteği bekler, sonra havuzda.
            val late = java.util.concurrent.CompletableFuture.supplyAsync { pool.translate("Hold the gate.", emptyList(), "Grand Theft Auto VI") }
            release.countDown()
            assertEquals("Kapıyı tut.", late.get(5, java.util.concurrent.TimeUnit.SECONDS))
            assertEquals(1, server.calls("/v1/translate").size)
            assertEquals("Kapıyı tut.", pool.store.match("Hold the gate."))
        } finally {
            release.countDown()
        }
    }

    @Test fun translateFirstReturnsNullWhenBudgetIsSpentOrServerFails() {
        val server = FakeServer()
        server.translateReply = { """{"ok":true,"limited":"daily_cap","translations":[{"text":null,"tier":0}]}""" }
        val pool = makePool(server)
        assertNull(pool.translateFirst("Hold the gate.", emptyList(), "Grand Theft Auto VI"))
        assertEquals(1, server.calls("/v1/translate").size)
        val broken = TranslationPool(newDirectory(), URL("https://pool.test"), null, "0.2.2", "android", "tr", true,
            { request -> if (request.url.path.endsWith("/v1/translate")) NinoPool.Response(500, "", null) else server.handle(request) }) { now }
        assertNull(broken.translateFirst("Open the door now.", emptyList(), "Grand Theft Auto VI"))
        val offline = TranslationPool(newDirectory(), URL("https://pool.test"), null, "0.2.2", "android", "tr", true,
            { throw java.io.IOException("çevrimdışı") }) { now }
        assertNull(offline.translateFirst("Open the door now.", emptyList(), "Grand Theft Auto VI"))
    }

    private fun org.json.JSONArray.toList() = (0 until length()).map { getString(it) }
}
