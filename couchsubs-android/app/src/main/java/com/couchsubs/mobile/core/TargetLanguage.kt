// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Nino: çeviri dili (Mac: TargetLanguage.swift ile aynı kurallar). Varsayılan Türkçe; Arapça, Hintçe, Endonezce ve
 * öbürleri seçilebilir. Sözlük, oyun paketleri ve Türkçe düzeltmeler yalnız Türkçede çalışır. Arap harfli çeviri sağdan
 * sola gösterilir.
 */
object TargetLanguage {
    /**
     * Seçilebilen diller: kod ve kendi dilindeki adı. Türkçe hep ilk sırada. Filipince, ilk iki harfle Fince ("fi")
     * sanılmasın diye Tagalogca koduyla ("tl") tutulur.
     */
    val choices = listOf(
        "tr" to "Türkçe", "ar" to "العربية", "hi" to "हिन्दी", "id" to "Bahasa Indonesia", "th" to "ไทย",
        "vi" to "Tiếng Việt", "ur" to "اردو", "bn" to "বাংলা", "ms" to "Bahasa Melayu", "tl" to "Filipino",
        "nl" to "Nederlands",
    )

    /** Seçim ekranındaki bayraklar. */
    val flags = mapOf(
        "tr" to "🇹🇷", "ar" to "🇸🇦", "hi" to "🇮🇳", "id" to "🇮🇩", "th" to "🇹🇭", "vi" to "🇻🇳", "ur" to "🇵🇰",
        "bn" to "🇧🇩", "ms" to "🇲🇾", "tl" to "🇵🇭", "nl" to "🇳🇱",
    )

    fun flag(target: String): String = flags[code(target)] ?: "🌐"

    /** Dilin kendi adı ("Türkçe", "हिन्दी"); listede yoksa kodu. */
    fun nativeName(target: String): String = choices.firstOrNull { it.first == code(target) }?.second ?: target

    fun code(language: String): String = language.take(2).lowercase()

    fun isTurkish(target: String) = code(target) == "tr"

    fun isArabic(target: String) = code(target) == "ar"

    /** İstemlerde kullanılan İngilizce dil adı. */
    fun englishName(target: String) = when (code(target)) {
        "ar" -> "Arabic"
        "hi" -> "Hindi"
        "id" -> "Indonesian"
        "th" -> "Thai"
        "vi" -> "Vietnamese"
        "ur" -> "Urdu"
        "bn" -> "Bengali"
        "ms" -> "Malay"
        "tl" -> "Filipino"
        "nl" -> "Dutch"
        else -> "Turkish"
    }

    /** DeepL'in çevirebildiği hedef diller (Hintçe, Urduca, Bengalce, Malayca ve Filipince yok). */
    fun deepLSupports(target: String) = code(target) in setOf("tr", "ar", "id", "th", "vi", "nl")

    /** İlk açılışta: telefonun dili listedeyse o, değilse Türkçe. */
    fun preferred(deviceLanguage: String): String {
        // Eski Java kodları: Endonezce "in" (Android'in Locale'i hâlâ bunu verebilir), Filipince "fil".
        val lower = deviceLanguage.lowercase()
        val language = if (lower.startsWith("fil")) "tl" else if (lower == "in" || lower.startsWith("in-") || lower.startsWith("in_")) "id" else code(lower)
        return if (choices.any { it.first == language }) language else "tr"
    }

    /**
     * Nino: arayüz dili çeviri dilini izler (11 dilin hepsinin arayüz çevirisi var). Filipince Android'de "fil" etiketiyle
     * istenir (kaynaklar values-tl ve values-b+fil); Endonezce "id" (kaynaklar values-in). Listede olmayan dilde İngilizce.
     */
    fun interfaceTag(target: String): String = when (val language = code(target)) {
        "tl" -> "fil"
        in choices.map { it.first } -> language
        else -> "en"
    }

    /** Sağdan sola yazılan hedef dil mi (Arapça, Urduca). */
    fun isRightToLeft(target: String) = code(target) in setOf("ar", "ur")

    /** Nino: Türkçe ve Arapça dışındaki dillerde örnek ve deneme ekranındaki üç satır (İngilizcesi ve çevirisi). */
    fun sampleLines(target: String): List<Pair<String, String>> {
        val english = listOf("Who's there?", "They're coming. Stay out of sight.", "Get to the rooftop. Now!")
        val translated = when (code(target)) {
            "hi" -> listOf("वहाँ कौन है?", "वे आ रहे हैं। नज़रों से दूर रहो।", "छत पर जाओ। अभी!")
            "id" -> listOf("Siapa di sana?", "Mereka datang. Jangan sampai terlihat.", "Naik ke atap. Sekarang!")
            "th" -> listOf("ใครอยู่ตรงนั้น?", "พวกมันมาแล้ว อย่าให้ใครเห็น", "ขึ้นไปบนดาดฟ้า เดี๋ยวนี้!")
            "vi" -> listOf("Ai ở đó?", "Chúng đang đến. Đừng để bị nhìn thấy.", "Lên sân thượng. Ngay!")
            "ur" -> listOf("وہاں کون ہے؟", "وہ آ رہے ہیں۔ نظروں سے دور رہو۔", "چھت پر جاؤ۔ ابھی!")
            "bn" -> listOf("ওখানে কে?", "ওরা আসছে। চোখের আড়ালে থাকো।", "ছাদে যাও। এখনই!")
            "ms" -> listOf("Siapa di sana?", "Mereka datang. Jangan sampai dilihat.", "Naik ke bumbung. Sekarang!")
            "tl" -> listOf("Sino'ng nandiyan?", "Paparating na sila. Huwag kang magpapakita.", "Umakyat ka sa bubong. Ngayon na!")
            "nl" -> listOf("Wie is daar?", "Ze komen eraan. Blijf uit het zicht.", "Ga naar het dak. Nu!")
            else -> return emptyList()
        }
        return english.zip(translated)
    }

    /** Kendine özgü yazısı olan diller: Tay, Devanagari (Hintçe), Bengal. */
    private val ownScript = mapOf("th" to 0x0E00..0x0E7F, "hi" to 0x0900..0x097F, "bn" to 0x0980..0x09FF)

    /** Arap yazısının harfleri (Arapça, ek harfler ve sunum biçimleri). */
    fun isArabicLetter(c: Int): Boolean = c in 0x0620..0x064A || c in 0x066E..0x06D3 || c in 0x06FA..0x06FF ||
        c in 0x0750..0x077F || c in 0x08A0..0x08FF || c in 0xFB50..0xFDFF || c in 0xFE70..0xFEFF

    fun containsArabic(text: String): Boolean = text.codePoints().anyMatch(::isArabicLetter)

    /**
     * Yazı zaten hedef dilde mi: Arapça ve Urducada Arap harfli, Tayca, Hintçe ve Bengalcede o dilin yazısıyla yazılmış
     * yazı (İngilizce oyunda çıkmaz, PS5'in kendi menüsüdür) çevirmene gönderilmez.
     */
    fun isAlready(text: String, target: String): Boolean {
        val language = code(target)
        if (isRightToLeft(language) && containsArabic(text)) return true
        val range = ownScript[language] ?: return false
        return text.codePoints().anyMatch { it in range }
    }

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
