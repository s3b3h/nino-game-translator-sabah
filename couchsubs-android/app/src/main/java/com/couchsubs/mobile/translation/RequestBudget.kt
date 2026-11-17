// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import java.util.concurrent.ConcurrentHashMap

/**
 * Kayan bir dakikalık pencerede en çok [perMinute] istek hakkı (Windows: CouchSubs.Core/RequestBudget.cs, Mac/iPhone:
 * CouchSubsCore/RequestBudget.swift ile aynı). Gemini'nin ücretsiz katmanı dakikadaki istek sayısını sınırlar; sınırın
 * üstüne çıkan istek 429 alır. Hak önceden sayılınca istek hiç gönderilmez, o satır hemen yerel çeviriyle çevrilir;
 * böylece hem gecikme hem hata uyarısı olmaz ve pencere boşaldıkça hizmete kendiliğinden dönülür.
 */
class RequestBudget(perMinute: Int, private val now: () -> Long = System::currentTimeMillis) {
    private var limit = maxOf(1, perMinute)
    /** Penceredeki isteklerin zamanları, eskiden yeniye. */
    private val sent = ArrayDeque<Long>()

    /** Şu anki dakikalık sınır. */
    val perMinute: Int get() = synchronized(this) { limit }

    /** Hak varsa bir istek hakkı kullanır ve true döner; yoksa false (istek gönderilmemeli). */
    fun take(): Boolean = synchronized(this) {
        val time = now()
        while (sent.isNotEmpty() && time - sent.first() >= WINDOW_MS) sent.removeFirst()
        if (sent.size >= limit) return false
        sent.addLast(time)
        true
    }

    /** Hizmet daha düşük bir sınır bildirdi (429 yanıtındaki "quotaValue"); yükseltmez. */
    fun lower(perMinute: Int) = synchronized(this) { limit = maxOf(1, minOf(limit, perMinute)) }

    companion object {
        /** Pencerenin uzunluğu. */
        const val WINDOW_MS = 60_000L

        private val registry = ConcurrentHashMap<String, RequestBudget>()

        /** Modelin uygulama genelindeki ortak hakkı (Google sınırı proje ve model başına sayar); modelin sınırı yoksa null. */
        fun shared(provider: AiProvider, model: AiModel): RequestBudget? {
            val perMinute = model.requestsPerMinute ?: return null
            return registry.getOrPut(AiTranslator.engineId(provider, model)) { RequestBudget(perMinute) }
        }
    }
}
