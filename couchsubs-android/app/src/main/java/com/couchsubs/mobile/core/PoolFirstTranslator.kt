// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Nino: havuz öncelikli oyunlarda (sunucunun `poolFirst` listesi, varsayılan GTA 6) satır önce Nino'nun çeviri havuzuna
 * (sunucuda Claude) sorulur; kullanıcının kendi motoru (Gemini, DeepL, yapay zekâ) hiç çağrılmaz. Sunucu süresinde cevap
 * vermezse, hata verirse ya da günlük bütçe dolduysa altyazı boş kalmasın diye yalnız cihazın ücretsiz çevirisine (ML Kit)
 * düşülür. Öbür oyunlarda her şey eskisi gibi kullanıcının motoruna gider. Windows: PoolFirstTranslator.cs ile aynı davranış.
 * [engine]: kullanıcının seçtiği çevirmen (öbür oyunlar için). [free]: ücretsiz yerel çevirmen (havuz cevap vermezse).
 * [poolFirst]: şu an oynanan oyun havuz öncelikli mi. [ask]: satırı sunucuya sorar, süresinde gelmezse null döner
 * ([TranslationPool.translateFirst]).
 */
class PoolFirstTranslator(
    val engine: TextTranslator,
    private val free: TextTranslator,
    private val poolFirst: () -> Boolean,
    private val ask: (String) -> String?,
) : TextTranslator {
    /** Son satırı kim çevirdi: "havuz", "ücretsiz" ya da "motor" (günlük ve testler için). */
    @Volatile var lastSource: String = ""
        private set

    /** Günlük için (havuzdan gelmedi, ücretsize düşüldü vb.). */
    var log: ((String) -> Unit)? = null

    override fun translate(text: String): String {
        if (!poolFirst()) {
            lastSource = "motor"
            return engine.translate(text)
        }
        val pooled = try {
            ask(text)
        } catch (stopped: InterruptedException) {
            // Okuma hattı satırı bıraktı (iptal): ücretsiz çeviri de yapılmaz.
            throw stopped
        } catch (error: Exception) {
            null
        }
        if (!pooled.isNullOrBlank()) {
            lastSource = "havuz"
            return pooled
        }
        lastSource = "ücretsiz"
        log?.invoke("havuz öncelikli oyun: sunucudan çeviri gelmedi, ücretsiz çeviri kullanıldı")
        return free.translate(text)
    }

    override val translatesTogether: Boolean get() = !poolFirst() && engine.translatesTogether

    override fun translateAll(texts: List<String>): List<String> =
        if (!poolFirst()) engine.translateAll(texts) else texts.map(::translate)
}
