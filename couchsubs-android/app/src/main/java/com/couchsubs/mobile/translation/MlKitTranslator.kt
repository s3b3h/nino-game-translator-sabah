// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import com.couchsubs.mobile.core.SubtitleSegmenter
import com.couchsubs.mobile.core.TargetLanguage
import com.couchsubs.mobile.core.TextTranslator
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import java.io.IOException
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Ücretsiz, cihaz üstü çeviri: Google ML Kit İngilizceden seçilen dile (model yaklaşık 30 MB, ilk kullanımda bir kez iner;
 * sonra internetsiz çalışır). Türkçede iPhone ve Mac'teki ücretsiz metin hattıyla aynı ([FreeLineTranslator]): cümle cümle
 * çevrilir, terim sözlüğü korunur, kısa satır önceki cümleyle çevrilir, oyun deyimleri düz İngilizceye döner, Türkçe
 * düzeltmeler yapılır. Nino: öbür dillerde (sözlük ve düzeltmeler Türkçeye özgü) cümle cümle düz çeviri yapılır; konuşmacı
 * etiketi ve tireler olduğu gibi kalır.
 * [cache]: kalıcı önbellek (önceki oturumlarda çevrilmiş cümleler hiç çevrilmeden döner); her dilin önbelleği ayrıdır.
 * [target]: çeviri dili ("tr", "ar", "hi"…).
 */
class MlKitTranslator(
    private val cache: TranslationCache = TranslationCache(),
    private val glossary: Glossary = Glossary.Empty,
    target: String = "tr",
) : TextTranslator, AutoCloseable {
    companion object {
        /** Kalıcı önbellek dosyasındaki motor adı; metin hattı değişince ([FreeTranslation.PIPELINE_VERSION]) bu da değişir. */
        val ENGINE_ID = "mlkit-p${FreeTranslation.PIPELINE_VERSION}"

        /** Nino: çeviri dilinin ML Kit karşılığı (hepsi cihaz üstü, ücretsiz). */
        fun language(target: String): String = when (TargetLanguage.code(target)) {
            "ar" -> TranslateLanguage.ARABIC
            "hi" -> TranslateLanguage.HINDI
            "id" -> TranslateLanguage.INDONESIAN
            "th" -> TranslateLanguage.THAI
            "vi" -> TranslateLanguage.VIETNAMESE
            "ur" -> TranslateLanguage.URDU
            "bn" -> TranslateLanguage.BENGALI
            "ms" -> TranslateLanguage.MALAY
            "tl" -> TranslateLanguage.TAGALOG
            "nl" -> TranslateLanguage.DUTCH
            else -> TranslateLanguage.TURKISH
        }
    }

    private val turkish = language(target) == TranslateLanguage.TURKISH
    private val translator = Translation.getClient(
        TranslatorOptions.Builder().setSourceLanguage(TranslateLanguage.ENGLISH).setTargetLanguage(language(target)).build()
    )
    private val line = newLine()

    /** Model yoksa indirir (bloklar). [wifiOnly]: hücresel veride indirme. */
    fun prepare(wifiOnly: Boolean = false, timeoutSeconds: Long = 300) {
        val conditions = DownloadConditions.Builder().apply { if (wifiOnly) requireWifi() }.build()
        await(translator.downloadModelIfNeeded(conditions), timeoutSeconds)
    }

    override fun translate(text: String): String = line.translate(text)

    /**
     * Aynı modeli ve önbelleği kullanan, kendi satır bağlamı olan çevirmen (ek alanlar için: görev yazısı altyazının
     * kısa satırına bağlam olmasın).
     */
    fun separate(): TextTranslator = newLine()

    private fun newLine(): TextTranslator =
        if (turkish) FreeLineTranslator(cache, glossary, engine = ::machine) else PlainLine()

    /** Nino: Türkçe dışındaki diller: cümle cümle çeviri, sözlük ve Türkçe düzeltmeler olmadan. */
    private inner class PlainLine : TextTranslator {
        override fun translate(text: String): String {
            cache.get(text)?.let { return it }
            val result = SubtitleSegmenter.split(text).joinToString("") { piece ->
                if (!piece.translate) piece.text
                else cache.get(piece.text) ?: machine(SubtitleSegmenter.normalizeCase(piece.text)).also { cache.store(piece.text, it) }
            }
            cache.store(text, result)
            return result
        }
    }

    /** Hazır metni ML Kit'e verir. */
    private fun machine(input: String): String = await(translator.translate(input), 10)

    override fun close() = translator.close()

    private fun <T> await(task: com.google.android.gms.tasks.Task<T>, seconds: Long): T = try {
        Tasks.await(task, seconds, TimeUnit.SECONDS)
    } catch (error: ExecutionException) {
        throw IOException("ML Kit: ${error.cause?.message}", error.cause)
    } catch (error: TimeoutException) {
        throw IOException("ML Kit timeout", error)
    }
}
