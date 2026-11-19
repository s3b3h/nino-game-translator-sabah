// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile

import com.couchsubs.mobile.remoteplay.DisconnectKind
import com.couchsubs.mobile.remoteplay.SessionState
import com.couchsubs.mobile.service.LiveStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Ana ekrandaki "neden bağlanamıyor" metninin kuralı ([LiveStatus.nextProblem]). Oturum "koptu → bağlanılıyor → koptu"
 * diye döner; neden yeniden bağlanırken de kalmalı, görüntü gelince silinmelidir.
 */
class LiveProblemTest {
    private val rejected = "PS5 oturumu başlatmadı."
    private val connecting = "PS5'e bağlanılıyor…"
    private val reconnecting = "Bağlantı kesildi, yeniden bağlanılıyor…"

    /** Durumları sırayla uygular (hizmetteki onState gibi); her adımın metni yanında verilir. */
    private fun run(vararg steps: Pair<SessionState, String>, start: String? = null, xbox: Boolean = false): String? =
        steps.fold(start) { problem, (state, text) -> LiveStatus.nextProblem(problem, state, text, xbox) }

    @Test fun reasonSurvivesReconnecting() {
        val afterDrop = run(SessionState.Disconnected(DisconnectKind.REJECTED) to rejected)
        assertEquals(rejected, afterDrop)
        assertEquals(rejected, run(SessionState.Connecting to connecting, start = afterDrop))
        // Döngü: koptu → bağlanılıyor → koptu → bağlanılıyor; neden hiç kaybolmaz.
        assertEquals(rejected, run(SessionState.Disconnected(DisconnectKind.REJECTED) to rejected, SessionState.Connecting to connecting,
            SessionState.Disconnected(DisconnectKind.REJECTED) to rejected, SessionState.Connecting to connecting))
    }

    @Test fun pictureClearsTheReason() {
        assertNull(run(SessionState.Disconnected(DisconnectKind.REJECTED) to rejected, SessionState.Connecting to connecting,
            SessionState.Streaming to "Altyazılar okunuyor"))
    }

    @Test fun stoppingWritesNothing() {
        assertNull(run(SessionState.Disconnected(DisconnectKind.STOPPED) to reconnecting))
        assertEquals(rejected, run(SessionState.Disconnected(DisconnectKind.STOPPED) to reconnecting, start = rejected))
    }

    @Test fun newerReasonReplacesTheOlder() {
        assertEquals("PS5 başka bir Remote Play oturumunda.", run(SessionState.Disconnected(DisconnectKind.NETWORK) to "PS5'e ulaşılamıyor.",
            SessionState.Connecting to connecting, SessionState.Disconnected(DisconnectKind.IN_USE) to "PS5 başka bir Remote Play oturumunda."))
    }

    @Test fun everyNamedKindIsWritten() {
        val silent = LiveStatus.CARD_PROBLEMS + DisconnectKind.STOPPED + DisconnectKind.OTHER
        for (kind in DisconnectKind.entries - silent)
            assertEquals(kind.name, "metin $kind", run(SessionState.Disconnected(kind) to "metin $kind"))
    }

    @Test fun genericPs5DropIsNotAReason() {
        // PS5'te OTHER'ın metni yalnız "yeniden bağlanılıyor"dur (ayrıntı günlük içindir): yazılmaz, önceki neden kalır.
        assertNull(run(SessionState.Disconnected(DisconnectKind.OTHER, "Session Request failed") to reconnecting))
        assertNull(run(SessionState.Disconnected(DisconnectKind.OTHER) to reconnecting))
        assertEquals(rejected, run(SessionState.Disconnected(DisconnectKind.OTHER, "x") to reconnecting, start = rejected))
    }

    @Test fun xboxGivesItsReasonAsOtherWithDetail() {
        val busy = "Xbox başka bir uzaktan oynatmada."
        assertEquals(busy, run(SessionState.Disconnected(DisconnectKind.OTHER, busy) to busy, xbox = true))
        assertEquals(busy, run(SessionState.Disconnected(DisconnectKind.OTHER, busy) to busy, SessionState.Connecting to "Xbox'a bağlanılıyor…", xbox = true))
        // Ayrıntısız OTHER Xbox'ta da genel durumdur.
        assertNull(run(SessionState.Disconnected(DisconnectKind.OTHER) to reconnecting, xbox = true))
    }

    @Test fun captureCardProblemsStayOnTheErrorCard() {
        // Kart sorunları LiveStatus.error ile uyarı kartında görünür; sahnede ikinci kez yazılmaz.
        for (kind in LiveStatus.CARD_PROBLEMS) {
            assertNull(kind.name, run(SessionState.Disconnected(kind) to "Capture Card bulunamadı."))
            assertNull(kind.name, run(SessionState.Disconnected(kind) to "Capture Card bulunamadı.", start = rejected))
        }
    }

    @Test fun freshStatusHasNoReason() {
        assertNull(LiveStatus().problem)
        assertNull(LiveStatus(running = true, phase = "Hazırlanıyor…").problem)
    }
}
