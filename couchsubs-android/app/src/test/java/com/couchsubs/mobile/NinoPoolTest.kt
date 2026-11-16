// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile

import com.couchsubs.mobile.core.NinoPool
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.IOException
import java.net.URL
import java.nio.file.Files

class NinoPoolTest {
    private val directory: File = Files.createTempDirectory("ninopool").toFile()
    private var now = 1_763_300_000_000L
    private val received = mutableListOf<JSONObject>()
    private val answers = ArrayDeque<String>()
    private var fallback = "ok"
    private val endpoint = URL("http://localhost:8787")

    private val post: (URL, String) -> NinoPool.Response = { url, body ->
        assertEquals("/v1/batches", url.path)
        val batch = JSONObject(body)
        when (val answer = answers.removeFirstOrNull() ?: fallback) {
            "ok" -> {
                received += batch
                NinoPool.Response(200, """{"ok":true,"batch":"${batch.getString("batch")}","rejected":[]}""", null)
            }
            "offline" -> throw IOException("çevrimdışı")
            "lostAck" -> {
                received += batch
                throw IOException("yanıt kayboldu")
            }
            "wrongBody" -> NinoPool.Response(200, "<html>portal</html>", null)
            else -> {
                val (code, retry) = answer.split(":").let { it[0].toInt() to it.getOrNull(1)?.toLong() }
                NinoPool.Response(code, """{"ok":false}""", retry)
            }
        }
    }

    private fun lines() = received.flatMap { b -> (0 until b.getJSONArray("lines").length()).map { b.getJSONArray("lines").getJSONObject(it) } }

    private fun make(app: String = "0.1.6", url: URL? = endpoint, legacy: File? = null, limits: NinoPool.Limits = NinoPool.Limits()) =
        NinoPool(directory, app, "android", true, url, legacy, limits, post) { now }

    @After fun tearDown() { directory.deleteRecursively() }

    @Test fun lineSurvivesRestartAndIsSent() {
        assertTrue(make().offer("Where is Lamar going?", "gta-v"))
        val reopened = make()
        assertEquals(1, reopened.status().pendingLines)
        reopened.flush(force = true)
        assertEquals(listOf("Where is Lamar going?"), lines().map { it.getString("text") })
        assertEquals("gta-v", lines()[0].getString("game"))
    }

    @Test fun noEndpointKeepsLines() {
        val pool = make(url = null)
        pool.offer("This line waits for a server.")
        pool.flush(force = true)
        assertTrue(received.isEmpty())
        assertEquals(1, pool.status().pendingLines)
        pool.setEndpoint(endpoint)
        pool.flush(force = true)
        assertEquals(1, lines().size)
    }

    @Test fun tornLineIsCut() {
        val pool = make()
        pool.offer("First full line here.")
        File(directory, "pending.jsonl").appendText("""{"s":2,"t":"Half""")
        val reopened = make()
        reopened.offer("Second full line here.")
        reopened.flush(force = true)
        assertEquals(setOf("First full line here.", "Second full line here."), lines().map { it.getString("text") }.toSet())
    }

    @Test fun crashMidFreezeKeepsUnwrittenChunks() {
        fallback = "offline"
        val limits = NinoPool.Limits(batchSize = 3)
        val pool = make(limits = limits)
        repeat(7) { pool.offer("Chunked line number $it.") }
        val pendingFile = File(directory, "pending.jsonl")
        val pending = pendingFile.readBytes()
        pool.flush(force = true)
        val outbox = File(directory, "outbox").listFiles()!!.filter { it.name.endsWith(".json") }.sortedBy { it.name }
        assertEquals(3, outbox.size)
        outbox.drop(1).forEach { it.delete() }
        pendingFile.writeBytes(pending)
        val stateFile = File(directory, "state.json")
        stateFile.writeText(JSONObject(stateFile.readText()).put("frozenThrough", 0).toString())
        fallback = "ok"
        make(limits = limits).flush(force = true)
        assertEquals(7, lines().size)
        assertEquals(7, lines().map { it.getString("text") }.toSet().size)
        assertTrue(lines().all { it.getInt("count") == 1 })
    }

    @Test fun inertPoolKeepsQueue() {
        fallback = "offline"
        val pool = make()
        pool.offer("Waiting line stays put.")
        pool.flush(force = true)
        pool.offer("Pending line stays put.")
        val inert = NinoPool(directory, "0.1.6", "android", false, endpoint, null, NinoPool.Limits(), post) { now }
        assertFalse(inert.offer("Not taken while inert."))
        assertEquals(1, inert.status().outboxBatches)
        assertEquals(1, inert.status().pendingLines)
    }

    @Test fun repeatsCountedAndBatched() {
        val pool = make(limits = NinoPool.Limits(batchSize = 3))
        repeat(4) { pool.offer("Same line again and again.", "GTA V") }
        now += 10_000
        pool.offer("Same line again and again.", "GTA V")
        repeat(4) { pool.offer("Different line number $it.") }
        pool.flush(force = true)
        assertEquals(listOf(3, 2), received.map { it.getJSONArray("lines").length() })
        val repeated = lines().first { it.getString("text") == "Same line again and again." }
        assertEquals(5, repeated.getInt("count"))
        assertEquals("gta-v", repeated.getString("game"))
        assertEquals(10L, repeated.getLong("last") - repeated.getLong("first"))
    }

    @Test fun serverErrorBacksOffAndKeepsBatch() {
        fallback = "500"
        val pool = make()
        pool.offer("Server is down right now.")
        pool.flush(force = true)
        now += 10_000
        pool.flush()
        fallback = "ok"
        assertTrue(received.isEmpty())
        now += 40_000
        pool.flush()
        assertEquals(1, lines().size)
        assertEquals(0, pool.status().outboxBatches)
    }

    @Test fun lostAckResendsSameId() {
        answers += "lostAck"
        val pool = make()
        pool.offer("The reply never arrived.")
        pool.flush(force = true)
        pool.networkAvailable()
        assertEquals(2, received.size)
        assertEquals(received[0].getString("batch"), received[1].getString("batch"))
    }

    @Test fun foreignOkKeepsBatch() {
        answers += "wrongBody"
        val pool = make()
        pool.offer("Captive portal says OK.")
        pool.flush(force = true)
        assertEquals(1, pool.status().outboxBatches)
    }

    @Test fun retryAfterRespected() {
        answers += "429:600"
        val pool = make()
        pool.offer("Slow down, please.")
        pool.flush(force = true)
        pool.networkAvailable()
        now += 599_000
        pool.flush()
        assertTrue(received.isEmpty())
        now += 2_000
        pool.flush()
        assertEquals(1, lines().size)
    }

    @Test fun badRequestParkedUntilUpdate() {
        answers += "400"
        val pool = make()
        pool.offer("Server did not like this.")
        pool.flush(force = true)
        assertEquals(1, pool.status().parkedBatches)
        make().flush(force = true)
        assertTrue(received.isEmpty())
        make(app = "0.1.7").flush()
        assertEquals(1, lines().size)
    }

    @Test fun tooLargeIsSplit() {
        answers += "413"
        val pool = make()
        repeat(5) { pool.offer("Split line number $it.") }
        pool.flush(force = true)
        assertEquals(listOf(2, 3), received.map { it.getJSONArray("lines").length() })
    }

    @Test fun disablingWipes() {
        fallback = "offline"
        val pool = make()
        pool.offer("Line before opting out.")
        pool.flush(force = true)
        pool.offer("Another before opting out.")
        pool.setEnabled(false)
        val s = pool.status()
        assertEquals(0, s.pendingLines + s.outboxBatches + s.parkedBatches)
        assertFalse(pool.offer("Ignored while off."))
    }

    @Test fun importsLegacyQueue() {
        val legacy = File(directory.parentFile, "legacy-${System.nanoTime()}.json")
        legacy.writeText("""{"install":"x","queue":[{"text":"Old queued line here.","key":"k","firstSeen":"2026-11-11T03:17:00Z"},{"text":"Oturum Açtı","key":"k2","firstSeen":"2026-11-11T03:17:00Z"}],"sent":[]}""")
        try {
            val pool = make(legacy = legacy)
            assertEquals(1, pool.status().pendingLines)
            assertFalse(legacy.exists())
            pool.flush(force = true)
            assertEquals(1_794_367_020L, lines()[0].getLong("first"))
        } finally {
            File(legacy.parentFile, legacy.name + ".imported").delete()
        }
    }

    @Test fun filter() {
        assertTrue(NinoPool.accepts("Run!"))
        assertFalse(NinoPool.accepts("Oturum Açtı"))
        assertFalse(NinoPool.accepts("PlayerOne signed in"))
        assertFalse(NinoPool.accepts("100/100 HP 25%"))
        assertEquals("Hello there.", NinoPool.clean("  Hello​\n  there.  "))
        assertEquals("gta-v", NinoPool.gameId("GTA V"))
        assertNull(NinoPool.gameId(" "))
    }

    @Test fun endpointFromFile() {
        assertEquals(NinoPool.LIVE_ENDPOINT, NinoPool.configuredEndpoint(directory))
        File(directory, "endpoint.txt").writeText("http://192.168.0.5:8787\n")
        assertEquals("192.168.0.5", NinoPool.configuredEndpoint(directory)?.host)
    }
}
