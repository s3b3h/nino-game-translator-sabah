// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppVersionsTest {
    @Test
    fun comparesNumericPartsNotText() {
        assertTrue(AppVersions.isNewer("0.2.0", "0.1.10"))
        assertTrue(AppVersions.isNewer("0.1.10", "0.1.9"))
        assertTrue(AppVersions.isNewer("v0.2.0", "0.1.9"))
        assertTrue(AppVersions.isNewer("1.0", "0.9.99"))
        assertFalse(AppVersions.isNewer("0.1.9", "0.1.10"))
    }

    @Test
    fun equalVersionsAreNotNewer() {
        assertFalse(AppVersions.isNewer("0.2.0", "0.2.0"))
        assertFalse(AppVersions.isNewer("v0.2.0", "0.2"))
        assertFalse(AppVersions.isNewer("0.2.0+build.7", "0.2.0"))
    }

    @Test
    fun prereleaseIsOlderThanItsRelease() {
        assertTrue(AppVersions.isNewer("0.1.0", "0.1.0-beta.37"))
        assertFalse(AppVersions.isNewer("0.1.0-beta.37", "0.1.0"))
        assertTrue(AppVersions.isNewer("0.1.0-beta.38", "0.1.0-beta.37"))
        assertTrue(AppVersions.isNewer("0.1.0-beta.10", "0.1.0-beta.9"))
        assertTrue(AppVersions.isNewer("0.1.0-beta", "0.1.0-alpha.5"))
        assertTrue(AppVersions.isNewer("0.1.0-beta.1", "0.1.0-beta"))
        assertTrue(AppVersions.isNewer("0.1.1-beta.1", "0.1.0"))
    }

    @Test
    fun unreadableVersionsNeverShowTheCard() {
        assertFalse(AppVersions.isNewer("latest", "0.1.0"))
        assertFalse(AppVersions.isNewer("", "0.1.0"))
        assertFalse(AppVersions.isNewer("0.2.0", "dev"))
        assertNull(AppVersions.compare("0..1", "0.1"))
    }

    @Test
    fun readsTagFromGithubResponse() {
        assertEquals("0.2.0", AppVersions.latestVersion("""{"tag_name":"v0.2.0","draft":false,"prerelease":false}"""))
        assertEquals("0.2.0", AppVersions.latestVersion("""{"tag_name":"0.2.0"}"""))
        assertNull(AppVersions.latestVersion("""{"tag_name":"v0.3.0","prerelease":true}"""))
        assertNull(AppVersions.latestVersion("""{"message":"API rate limit exceeded"}"""))
        assertNull(AppVersions.latestVersion("not json"))
    }

    @Test
    fun checksAtMostEveryThreeHours() {
        val hour = 60 * 60 * 1000L
        val now = 100 * hour
        assertEquals(3 * hour, AppVersions.CHECK_INTERVAL_MS)
        assertTrue(AppVersions.isCheckDue(now, 0L))
        assertFalse(AppVersions.isCheckDue(now, now - 2 * hour))
        assertFalse(AppVersions.isCheckDue(now, now - 3 * hour + 1))
        assertTrue(AppVersions.isCheckDue(now, now - 3 * hour))
        assertTrue(AppVersions.isCheckDue(now, now + hour))
    }

    @Test
    fun settingsRowKeepsShowingADismissedVersion() {
        // Ana ekrandaki kart ✕ ile kapatıldı: kart gizlenir, Ayarlar'daki satır sürümü göstermeye devam eder.
        assertNull(AppVersions.versionToShow("0.2.0", "0.1.9", "0.2.0"))
        assertEquals("0.2.0", AppVersions.newerVersion("0.2.0", "0.1.9"))
        assertNull(AppVersions.newerVersion("0.2.0", "0.2.0"))
        assertNull(AppVersions.newerVersion("0.1.8", "0.1.9"))
        assertNull(AppVersions.newerVersion(null, "0.1.9"))
    }

    @Test
    fun cardHidesDismissedAndInstalledVersions() {
        assertEquals("0.2.0", AppVersions.versionToShow("0.2.0", "0.1.9", null))
        assertNull(AppVersions.versionToShow("0.2.0", "0.1.9", "0.2.0"))
        assertEquals("0.3.0", AppVersions.versionToShow("0.3.0", "0.1.9", "0.2.0"))
        assertNull(AppVersions.versionToShow("0.2.0", "0.2.0", null))
        assertNull(AppVersions.versionToShow(null, "0.1.9", null))
    }
}
