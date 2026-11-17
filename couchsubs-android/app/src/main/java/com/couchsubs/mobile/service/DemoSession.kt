// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.service

import com.couchsubs.mobile.Services
import com.couchsubs.mobile.core.ShownPair
import com.couchsubs.mobile.core.TargetLanguage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Nino: PS5'siz demo. PS5'i olmayan ya da mağaza incelemesinde uygulamayı deneyen biri, gerçek bir oturumdaki gibi
 * örnek İngilizce altyazıların seçili dile çevrilip ekranda aktığını görür. Ağ, PS5 ve hizmet kullanılmaz; yalnız
 * [LiveState] beslenir, bu yüzden ana ekran, tam ekran ve yan çevirme aynen çalışır.
 */
object DemoSession {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var job: Job? = null

    val active: Boolean get() = job?.isActive == true

    private val turkish = listOf(
        "Arthur, we need to move. Now!" to "Arthur, harekete geçmemiz lazım. Hemen!",
        "They're coming. Stay out of sight." to "Geliyorlar. Gözden uzak dur.",
        "I told you this would happen." to "Bunun olacağını sana söylemiştim.",
        "Get to the rooftop and wait for my signal." to "Çatıya çık ve işaretimi bekle.",
        "We ride at dawn." to "Şafakta yola çıkıyoruz.",
    )
    private val arabic = listOf(
        "Arthur, we need to move. Now!" to "آرثر، علينا التحرك. الآن!",
        "They're coming. Stay out of sight." to "إنهم قادمون. ابقَ بعيدًا عن الأنظار.",
        "I told you this would happen." to "قلت لك إن هذا سيحدث.",
        "Get to the rooftop and wait for my signal." to "اصعد إلى السطح وانتظر إشارتي.",
        "We ride at dawn." to "ننطلق عند الفجر.",
    )

    fun start() {
        if (active) return
        val target = Services.settings.targetLanguage
        val lines = TargetLanguage.sampleLines(target).takeIf { it.isNotEmpty() }
            ?: if (TargetLanguage.code(target) == "ar") arabic else turkish
        LiveState.update {
            it.copy(running = true, streaming = true, demo = true, current = "", error = null, recent = emptyList(),
                startedAt = System.currentTimeMillis(), shownLines = 0, packLines = 0, packInUse = null)
        }
        job = scope.launch {
            delay(1200)
            var index = 0
            while (true) {
                val (source, translation) = lines[index % lines.size]
                LiveState.shown(ShownPair(source, translation, "demo"), null)
                LiveState.update { it.copy(current = translation) }
                delay(3600)
                LiveState.update { it.copy(current = "") }
                delay(900)
                index++
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        LiveState.update { it.copy(running = false, streaming = false, demo = false, current = "") }
    }
}
