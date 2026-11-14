// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Nino: her oyunun altyazısının ekranda nerede durduğunu öğrenir (Mac: SubtitleLayout.swift, aynı kurallar).
 * Gösterilen her altyazının kutusu kaydedilir; yeterince örnek olunca o oyunun altyazı şeridi bilinir ve şeridin
 * altında başlayan yazılar (görev, öğretici, menü) altyazı sayılmaz.
 */
class SubtitleLayout(private val file: File?) {
    companion object {
        const val MINIMUM_SAMPLES = 8
        const val MAXIMUM_SAMPLES = 60
        /** Öğrenene kadar kullanılan sınır: ekranın en alt şeridi. */
        const val FALLBACK_HUD_TOP = 0.885

        fun quantile(sorted: List<Double>, q: Double): Double {
            if (sorted.isEmpty()) return 0.0
            val index = Math.round((sorted.size - 1) * q).toInt().coerceIn(0, sorted.size - 1)
            return sorted[index]
        }
    }

    private val samples = mutableMapOf<String, MutableList<Pair<Double, Double>>>()

    init {
        try {
            if (file != null && file.exists()) {
                val json = JSONObject(file.readText())
                for (game in json.keys()) {
                    val array = json.getJSONArray(game)
                    samples[game] = MutableList(array.length()) { i ->
                        val item = array.getJSONArray(i)
                        item.getDouble(0) to item.getDouble(1)
                    }
                }
            }
        } catch (error: Exception) {
            samples.clear()
        }
    }

    @Synchronized
    fun record(box: TextBox, game: String) {
        if (box.bottom <= box.top || box.top < 0 || box.bottom > 1) return
        val list = samples.getOrPut(game) { mutableListOf() }
        list.add(box.top to box.bottom)
        while (list.size > MAXIMUM_SAMPLES) list.removeAt(0)
        save()
    }

    /** Oyunun altyazı şeridi (üst, alt); yeterli örnek yoksa null. Uç değerler atılır. */
    @Synchronized
    fun band(game: String): Pair<Double, Double>? {
        val list = samples[game] ?: return null
        if (list.size < MINIMUM_SAMPLES) return null
        return quantile(list.map { it.first }.sorted(), 0.1) to quantile(list.map { it.second }.sorted(), 0.9)
    }

    /** Bu çizginin altında başlayan satır altyazı sayılmaz; altyazısı en dipte duran oyunda null. */
    fun hudTop(game: String): Double? {
        val band = band(game) ?: return FALLBACK_HUD_TOP
        // Şeridin altına bir satır yüksekliği pay (iki satırlık altyazının ikinci satırı kesilmesin).
        val heights = synchronized(this) { samples[game].orEmpty().map { it.second - it.first }.sorted() }
        val line = band.second + maxOf(0.012, quantile(heights, 0.5))
        return if (line >= 0.97) null else maxOf(line, band.first + 0.03)
    }

    private fun save() {
        val target = file ?: return
        try {
            val json = JSONObject()
            for ((game, list) in samples) json.put(game, JSONArray(list.map { JSONArray(listOf(it.first, it.second)) }))
            target.parentFile?.mkdirs()
            target.writeText(json.toString())
        } catch (error: Exception) {
            // Kaydedilemezse öğrenilen yer yalnız bu oturumda kalır.
        }
    }
}
