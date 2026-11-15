// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SystemHealthTest {
    private var now = 1_000_000L
    private fun recorder() = HealthRecorder { now }
    private fun advance(seconds: Int) { now += seconds * 1000L }

    @Test
    fun nothingMeasuredBeforeTranslationStarts() {
        val s = HealthRecorder().snapshot()
        assertTrue(s.isEmpty)
        assertEquals(HealthLevel.UNKNOWN, HealthReport.stream(s))
        assertEquals(HealthLevel.UNKNOWN, HealthReport.connection(s))
        assertEquals(HealthLevel.UNKNOWN, HealthReport.translation(s))
    }

    @Test
    fun smoothStreamIsGoodAndSlowStreamIsAProblem() {
        val health = recorder()
        health.sessionStarted()
        health.connecting()
        health.streaming()
        advance(60)
        health.frameTotal(60 * 30)
        assertEquals(30.0, health.snapshot().framesPerSecond!!, 0.01)
        assertEquals(HealthLevel.GOOD, HealthReport.stream(health.snapshot()))

        val slow = recorder()
        slow.sessionStarted()
        slow.streaming()
        advance(60)
        slow.frameTotal(60 * 8)
        assertEquals(HealthLevel.PROBLEM, HealthReport.stream(slow.snapshot()))
        assertEquals(HealthLevel.PROBLEM, HealthReport.network(NetworkKind.WIFI, HealthLevel.PROBLEM))
        assertEquals(HealthLevel.GOOD, HealthReport.network(NetworkKind.WIRED, HealthLevel.PROBLEM))
    }

    @Test
    fun wifiIsNotGreenBeforeThePictureIsMeasured() {
        assertEquals(HealthLevel.UNKNOWN, HealthReport.network(NetworkKind.WIFI, HealthLevel.UNKNOWN))
        assertEquals(HealthLevel.PROBLEM, HealthReport.network(NetworkKind.OFFLINE, HealthLevel.UNKNOWN))
    }

    @Test
    fun ratesWaitForEnoughStreaming() {
        val health = recorder()
        health.sessionStarted()
        health.streaming()
        advance(5)
        health.frameTotal(150)
        assertNull(health.snapshot().framesPerSecond)
    }

    @Test
    fun framesOnlyCountWhilePictureArrivesAndSurviveReconnect() {
        val health = recorder()
        health.sessionStarted()
        health.connecting()
        advance(100)
        health.frameTotal(0)
        health.streaming()
        advance(30)
        health.frameTotal(900)
        health.disconnected("NETWORK")
        advance(100)
        health.connecting()
        health.streaming()
        advance(30)
        health.frameTotal(1800)
        val s = health.snapshot()
        assertEquals(60.0, s.streamingSeconds, 0.01)
        assertEquals(1800L, s.frames)
        assertEquals(1, s.drops)
        assertEquals("NETWORK", s.lastDisconnect)
    }

    @Test
    fun neverConnectingIsAProblemAndUserStopIsNotADrop() {
        val health = recorder()
        health.sessionStarted()
        repeat(2) { health.connecting(); health.disconnected("NOT_FOUND") }
        assertEquals(HealthLevel.PROBLEM, HealthReport.connection(health.snapshot()))
        assertEquals(0, health.snapshot().drops)

        val stopped = recorder()
        stopped.sessionStarted()
        repeat(3) { stopped.connecting(); stopped.streaming(); stopped.disconnected("NETWORK") }
        assertEquals(HealthLevel.WARNING, HealthReport.connection(stopped.snapshot()))
        stopped.streaming()
        stopped.disconnected(null)
        assertEquals(3, stopped.snapshot().drops)
    }

    @Test
    fun translationTimeUsesMedianAndIgnoresPackLines() {
        val health = recorder()
        health.sessionStarted()
        listOf(400L, 500L, 600L, 9000L).forEach { health.line(it) }
        health.line(null)
        val s = health.snapshot()
        assertEquals(5, s.lines)
        assertEquals(4, s.translations)
        assertEquals(9000L, s.translationMaxMs)
        assertEquals(HealthLevel.GOOD, HealthReport.translation(s))
        repeat(10) { health.line(3500) }
        assertEquals(HealthLevel.PROBLEM, HealthReport.translation(health.snapshot()))
    }

    @Test
    fun countsSurviveSessionEndAndResetOnNextStart() {
        val health = recorder()
        health.sessionStarted()
        health.line(500)
        health.sessionEnded()
        assertEquals(1, health.snapshot().lines)
        health.sessionStarted()
        assertEquals(0, health.snapshot().lines)
        assertTrue(health.snapshot().active)
    }
}
