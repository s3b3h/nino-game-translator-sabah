// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Nino: çeviri dili (Mac: TargetLanguage.swift ile aynı kurallar). Varsayılan Türkçe; Arapça seçilebilir. Sözlük, oyun
 * paketleri ve Türkçe düzeltmeler yalnız Türkçede çalışır. Arapça çeviri sağdan sola gösterilir.
 */
object TargetLanguage {
    /** Seçilebilen diller: kod ve kendi dilindeki adı. */
    val choices = listOf("tr" to "Türkçe", "ar" to "العربية")

    /** Seçim ekranındaki bayraklar. */
    val flags = mapOf("tr" to "🇹🇷", "ar" to "🇸🇦")

    fun code(language: String): String = language.take(2).lowercase()

    fun isTurkish(target: String) = code(target) == "tr"

    /** İstemlerde kullanılan İngilizce dil adı. */
    fun englishName(target: String) = if (code(target) == "ar") "Arabic" else "Turkish"

    /** İlk açılışta: telefonun dili Arapçaysa Arapça, değilse Türkçe. */
    fun preferred(deviceLanguage: String): String = if (code(deviceLanguage) == "ar") "ar" else "tr"

    /** Arap yazısının harfleri (Arapça, ek harfler ve sunum biçimleri). */
    fun isArabicLetter(c: Int): Boolean = c in 0x0620..0x064A || c in 0x066E..0x06D3 || c in 0x06FA..0x06FF ||
        c in 0x0750..0x077F || c in 0x08A0..0x08FF || c in 0xFB50..0xFDFF || c in 0xFE70..0xFEFF

    fun containsArabic(text: String): Boolean = text.codePoints().anyMatch(::isArabicLetter)

    /** Yazı zaten hedef dilde mi (Arapça hedefte Arap harfli yazı çevirmene gönderilmez). */
    fun isAlready(text: String, target: String): Boolean = code(target) == "ar" && containsArabic(text)

    /**
     * Sağdan sola gösterim: Arap harfli yazının her paragrafının başına sağdan sola işareti (U+200F) konur; satır Latin
     * harfli konuşmacı adıyla başlasa da ("ARTHUR: …") sağdan dizilir. Arap harfi yoksa yazı olduğu gibi döner.
     */
    fun displayText(text: String): String {
        if (!containsArabic(text)) return text
        val mark = "‏"
        return text.split("\n").joinToString("\n") { if (it.startsWith(mark)) it else mark + it }
    }
}

/** Yazı zaten hedef dildeyse çevirmene gitmez, olduğu gibi döner (hat aynı yazıyı göstermez). */
class TargetAwareTranslator(private val inner: TextTranslator, private val target: String) : TextTranslator {
    override fun translate(text: String): String = if (TargetLanguage.isAlready(text, target)) text else inner.translate(text)
}
