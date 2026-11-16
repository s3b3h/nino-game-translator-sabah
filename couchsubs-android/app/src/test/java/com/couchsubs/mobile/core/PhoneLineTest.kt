// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Test

class PhoneLineTest {
    @Test
    fun reportedDurationIsUsedButNeverTooShort() {
        assertEquals(4_000L, PhoneLine.visibleMs("Merhaba", 4_000))
        assertEquals(PhoneLine.MIN_VISIBLE_MS, PhoneLine.visibleMs("Merhaba", 300))
    }

    @Test
    fun withoutDurationLongLinesStayLongerButNotForever() {
        assertEquals(2_000L + 10 * 60L, PhoneLine.visibleMs("0123456789", 0))
        assertEquals(PhoneLine.MAX_READING_MS, PhoneLine.visibleMs("x".repeat(500), 0))
    }
}
