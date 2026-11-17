// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import com.couchsubs.mobile.translation.AiModel
import com.couchsubs.mobile.translation.AiProvider
import com.couchsubs.mobile.translation.AiRequest
import com.couchsubs.mobile.translation.DeepLTranslator
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Nino: Arapça çeviri dili (Mac'teki TargetLanguage ve AIRequest testleriyle aynı kurallar). */
class TargetLanguageTest {
    @Test fun firstLaunchFollowsPhoneLanguage() {
        assertEquals("ar", TargetLanguage.preferred("ar"))
        assertEquals("tr", TargetLanguage.preferred("tr"))
        assertEquals("tr", TargetLanguage.preferred("en"))
    }

    @Test fun arabicTextIsAlreadyArabic() {
        assertTrue(TargetLanguage.isAlready("الإعدادات", "ar"))
        assertFalse(TargetLanguage.isAlready("Where is the camp?", "ar"))
        assertFalse(TargetLanguage.isAlready("الإعدادات", "tr"))
    }

    @Test fun arabicLinesStartRightToLeft() {
        assertEquals("‏ARTHUR: أين المخيم؟\n‏آرثر، انتظر", TargetLanguage.displayText("ARTHUR: أين المخيم؟\nآرثر، انتظر"))
        assertEquals("Bu iş bitmedi.", TargetLanguage.displayText("Bu iş bitmedi."))
    }

    @Test fun alreadyArabicTextIsNotSentToTheTranslator() {
        var calls = 0
        val translator = TargetAwareTranslator({ calls++; "ترجمة" }, "ar")
        assertEquals("الإعدادات", translator.translate("الإعدادات"))
        assertEquals("ترجمة", translator.translate("Settings"))
        assertEquals(1, calls)
    }

    @Test fun aiRequestUsesArabicPrompt() {
        val request = AiRequest.build(AiProvider.CLAUDE, "k", AiModel("m", "M"), listOf("Stay close."),
            listOf(AiRequest.ContextLine("Arthur?", "آرثر؟")), target = "ar")
        val body = JSONObject(request.body)
        assertTrue(body.getString("system").contains("Modern Standard Arabic"))
        val user = body.getJSONArray("messages").getJSONObject(0).getString("content")
        assertTrue(user.contains("into Arabic"))
        assertTrue(user.contains("Arabic: آرثر؟"))
        assertFalse(user.contains("Turkish"))
        assertEquals(AiRequest.SYSTEM_PROMPT, AiRequest.systemPrompt("tr"))
    }

    @Test fun deepLGoesToArabicWithoutTurkishFormality() {
        val arabic = JSONObject(DeepLTranslator.body(listOf("Hi"), null, target = "ar"))
        assertEquals("AR", arabic.getString("target_lang"))
        assertFalse(arabic.has("formality"))
        val turkish = JSONObject(DeepLTranslator.body(listOf("Hi"), null))
        assertEquals("TR", turkish.getString("target_lang"))
        assertEquals("prefer_less", turkish.getString("formality"))
    }

    @Test fun moreLanguagesWithFlagsTurkishFirst() {
        assertEquals("tr", TargetLanguage.choices.first().first)
        assertEquals(11, TargetLanguage.choices.size)
        TargetLanguage.choices.forEach { assertTrue(TargetLanguage.flag(it.first) != "🌐") }
        assertEquals("hi", TargetLanguage.preferred("hi"))
        assertEquals("tl", TargetLanguage.preferred("fil"))
        assertEquals("tr", TargetLanguage.preferred("fi"))
        assertEquals("id", TargetLanguage.preferred("in"))
    }

    @Test fun ownScriptIsAlreadyInTarget() {
        assertTrue(TargetLanguage.isAlready("ตั้งค่า", "th"))
        assertTrue(TargetLanguage.isAlready("सेटिंग्स", "hi"))
        assertTrue(TargetLanguage.isAlready("ترتیبات", "ur"))
        assertFalse(TargetLanguage.isAlready("Where is the camp?", "th"))
        assertFalse(TargetLanguage.isAlready("Pengaturan", "id"))
    }

    @Test fun aiPromptNamesTheChosenLanguage() {
        assertTrue(AiRequest.systemPrompt("hi").contains("natural Hindi"))
        assertFalse(AiRequest.systemPrompt("vi").contains("Arabic"))
        assertEquals(AiRequest.ARABIC_SYSTEM_PROMPT, AiRequest.systemPrompt("ar"))
        assertTrue(TargetLanguage.deepLSupports("id"))
        assertFalse(TargetLanguage.deepLSupports("hi"))
        assertEquals(3, TargetLanguage.sampleLines("nl").size)
        assertTrue(TargetLanguage.sampleLines("tr").isEmpty())
    }
}
