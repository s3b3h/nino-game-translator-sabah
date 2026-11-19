// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import com.couchsubs.mobile.account.NinoAssistant
import com.couchsubs.mobile.account.ProblemReport
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

/** "Cihaz bilgileri": satırlar ve sunucuya giden özet (Mac/iPhone: DeviceInfoTests.swift ile aynı senaryolar). */
class DeviceInfoTest {
    @Test fun rowsSkipUnknownValues() {
        val rows = DeviceInfo.rows(app = "3.4.0 (19)", model = "Google Pixel 8", system = "Android 14 (API 34)",
            tv = null, console = "PS5 · Remote Play", status = "  ")
        assertEquals(listOf("app", "device", "system", "console"), rows.map { it.id })
    }

    @Test fun rowsKeepTheFixedOrder() {
        val rows = DeviceInfo.rows(app = "3.4.0 (19)", model = "Google Pixel 8", system = "Android 14 (API 34)",
            tv = "LG", console = "PS5 · Remote Play", status = "Altyazılar okunuyor")
        assertEquals(listOf("app", "device", "system", "tv", "console", "status"), rows.map { it.id })
    }

    @Test fun summaryIsOneLine() {
        val rows = DeviceInfo.rows(app = "3.4.0 (19)", model = "Google Pixel 8", system = "Android 14 (API 34)",
            tv = "Samsung QE55Q70C\nTV uygulaması 3.4.0", console = "PS5 | Remote Play")
        assertEquals("app: 3.4.0 (19) | device: Google Pixel 8 | system: Android 14 (API 34) | " +
            "tv: Samsung QE55Q70C TV uygulaması 3.4.0 | console: PS5 / Remote Play", DeviceInfo.summary(rows))
    }

    @Test fun summaryIsClipped() {
        val rows = DeviceInfo.rows(app = "x".repeat(2000), model = "Google Pixel 8", system = "Android 14 (API 34)")
        assertEquals(DeviceInfo.MAX_LENGTH, DeviceInfo.summary(rows).length)
    }

    @Test fun modelAndSystemAreReadable() {
        assertEquals("samsung SM-S918B", DeviceInfo.model("samsung", "SM-S918B"))
        assertEquals("Pixel 8", DeviceInfo.model(null, " Pixel 8 "))
        assertEquals("Android 14 (API 34)", DeviceInfo.system("14", 34))
        assertEquals("Android (API 34)", DeviceInfo.system(null, 34))
    }

    @Test fun tvAndConsoleLeaveOutWhatIsUnknown() {
        assertEquals("Samsung · TV uygulaması 3.4.0", DeviceInfo.tv("Samsung", "3.4.0"))
        assertEquals("LG", DeviceInfo.tv("LG", null))
        assertNull(DeviceInfo.tv(null, "3.4.0"))
        assertEquals("PS5 · Remote Play", DeviceInfo.console("PS5", "Remote Play"))
        assertEquals("Yakalama kartı", DeviceInfo.console(null, "Yakalama kartı"))
        assertNull(DeviceInfo.console(null, " "))
    }

    @Test fun statusNeverCarriesAddressesOrDeviceNames() {
        assertEquals("PS5 … adresinde bulunamadı.", DeviceInfo.withoutAddresses("PS5 192.168.1.20 adresinde bulunamadı."))
        assertEquals("… kapalı (…)", DeviceInfo.withoutAddresses("Ali'nin PS5'i kapalı (10.0.0.7:9295)", listOf("Ali'nin PS5'i", null, "")))
        assertEquals("Kod 0x80108b12", DeviceInfo.withoutAddresses("Kod 0x80108b12", listOf("PS")))
    }

    @Test fun reportCarriesDeviceOnlyWhenKnown() {
        val with = JSONObject(ProblemReport.body("12345678", "3.4.0", "tr", "x", null, null, emptyList(),
            device = " app: 3.4.0 | device: Google Pixel 8 "))
        assertEquals("app: 3.4.0 | device: Google Pixel 8", with.getString("device"))
        assertFalse(JSONObject(ProblemReport.body("12345678", "3.4.0", "tr", "x", null, null, emptyList())).has("device"))
        assertFalse(JSONObject(ProblemReport.body("12345678", "3.4.0", "tr", "x", null, null, emptyList(), device = "  ")).has("device"))
        val long = JSONObject(ProblemReport.body("12345678", "3.4.0", "tr", "x", null, null, emptyList(), device = "d".repeat(2000)))
        assertEquals(DeviceInfo.MAX_LENGTH, long.getString("device").length)
    }

    @Test fun assistantCarriesDeviceOnlyWhenKnown() {
        val turns = listOf(NinoAssistant.Turn(true, "TV'de altyazı çıkmıyor"))
        val with = JSONObject(NinoAssistant.body("12345678", "3.4.0", "tr", turns, device = " app: 3.4.0 | tv: LG "))
        assertEquals("app: 3.4.0 | tv: LG", with.getString("device"))
        assertFalse(JSONObject(NinoAssistant.body("12345678", "3.4.0", "tr", turns)).has("device"))
        // Sığdırılan gövde de taşır (fotoğraflar atılırken cihaz bilgisi düşmez).
        val fitted = JSONObject(NinoAssistant.fittedBody("12345678", "3.4.0", "tr", turns, device = "app: 3.4.0")!!)
        assertEquals("app: 3.4.0", fitted.getString("device"))
        assertFalse(JSONObject(NinoAssistant.fittedBody("12345678", "3.4.0", "tr", turns)!!).has("device"))
    }
}
