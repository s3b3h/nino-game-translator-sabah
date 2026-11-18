// SPDX-License-Identifier: AGPL-3.0-only
// Nino: telefon uygulamasının yeni sürüm bildirimi. GitHub'daki son sürüme en çok 12 saatte bir bakar; yeni sürüm
// varsa ana ekranda sakin bir kart gösterir. Google Play'den kurulan kopyada hiç bakılmaz (Play kendisi günceller).
// Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-18.
package com.couchsubs.mobile.update

import android.content.Context
import android.os.Build
import com.couchsubs.mobile.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** Android'e dokunmayan kısım (JVM testleri bunu sınar): sürüm karşılaştırma, etiket okuma, bakma zamanı. */
object AppVersions {
    const val CHECK_INTERVAL_MS = 12 * 60 * 60 * 1000L

    private data class Parsed(val core: List<Int>, val pre: List<String>)

    /** "v0.2.0", "0.1.0-beta.37", "1.2+build.5" → çekirdek sayılar ve ön sürüm parçaları; okunamazsa null. */
    private fun parse(raw: String): Parsed? {
        val text = raw.trim().removePrefix("v").removePrefix("V").substringBefore('+')
        if (text.isEmpty()) return null
        val core = text.substringBefore('-')
        val pre = if ('-' in text) text.substringAfter('-') else ""
        val numbers = core.split('.').map { it.toIntOrNull() ?: return null }
        if (numbers.isEmpty() || numbers.any { it < 0 }) return null
        val parts = if (pre.isEmpty()) emptyList() else pre.split('.').also { list -> if (list.any { it.isEmpty() }) return null }
        return Parsed(numbers, parts)
    }

    /** Semantik sürüm karşılaştırması; okunamayan sürümde null. 0.2.0 > 0.1.10 > 0.1.9, 0.1.0 > 0.1.0-beta.37. */
    fun compare(a: String, b: String): Int? {
        val x = parse(a) ?: return null
        val y = parse(b) ?: return null
        for (i in 0 until maxOf(x.core.size, y.core.size)) {
            val l = x.core.getOrElse(i) { 0 }
            val r = y.core.getOrElse(i) { 0 }
            if (l != r) return l.compareTo(r)
        }
        // Ön sürüm, aynı numaralı asıl sürümden eskidir.
        if (x.pre.isEmpty() || y.pre.isEmpty()) return y.pre.size.coerceAtMost(1) - x.pre.size.coerceAtMost(1)
        for (i in 0 until minOf(x.pre.size, y.pre.size)) {
            val l = x.pre[i]
            val r = y.pre[i]
            val ln = l.toIntOrNull()
            val rn = r.toIntOrNull()
            val result = when {
                ln != null && rn != null -> ln.compareTo(rn)
                ln != null -> -1
                rn != null -> 1
                else -> l.compareTo(r)
            }
            if (result != 0) return result
        }
        return x.pre.size.compareTo(y.pre.size)
    }

    /** [remote], [current]'ten yeniyse true; biri okunamazsa false (kullanıcıya yanlış uyarı gösterilmez). */
    fun isNewer(remote: String, current: String): Boolean = (compare(remote, current) ?: 0) > 0

    /** GitHub `releases/latest` yanıtındaki etiket, başındaki "v" atılmış ("v0.2.0" → "0.2.0"); yoksa null. */
    fun latestVersion(json: String): String? = try {
        val release = JSONObject(json)
        if (release.optBoolean("draft") || release.optBoolean("prerelease")) null
        else release.optString("tag_name").trim().removePrefix("v").removePrefix("V").takeIf { it.isNotEmpty() && parse(it) != null }
    } catch (error: Exception) {
        null
    }

    /** Son bakıştan 12 saat geçtiyse (ya da saat geri alındıysa) yeniden bakılır. */
    fun isCheckDue(now: Long, lastCheckedAt: Long): Boolean =
        lastCheckedAt <= 0L || lastCheckedAt > now || now - lastCheckedAt >= CHECK_INTERVAL_MS

    /** Kartta gösterilecek sürüm: kayıtlı son sürüm bu sürümden yeniyse ve kullanıcı onu kapatmadıysa. */
    fun versionToShow(latest: String?, current: String, dismissed: String?): String? =
        latest?.takeIf { isNewer(it, current) && it != dismissed }
}

object AppUpdate {
    const val DOWNLOAD_URL = "https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Telefon.apk"
    private const val LATEST_URL = "https://api.github.com/repos/yunusdemirbag/nino-game-translator/releases/latest"
    private const val PREFS = "app_update"
    private const val KEY_CHECKED_AT = "checked_at"
    private const val KEY_LATEST = "latest"
    private const val KEY_DISMISSED = "dismissed"
    private const val PLAY_STORE = "com.android.vending"

    private val state = MutableStateFlow<String?>(null)

    /** Ana ekranda gösterilecek yeni sürüm (ör. "0.2.0"); yoksa null. */
    val available: StateFlow<String?> = state

    /** Uygulama açılınca: önce kayıtlı sonuç gösterilir, 12 saat geçtiyse GitHub'a sessizce yeniden bakılır. */
    suspend fun check(context: Context) = withContext(Dispatchers.IO) {
        try {
            if (installedFromPlay(context)) {
                state.value = null
                return@withContext
            }
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            fun publish() {
                state.value = AppVersions.versionToShow(prefs.getString(KEY_LATEST, null), BuildConfig.VERSION_NAME, prefs.getString(KEY_DISMISSED, null))
            }
            publish()
            val now = System.currentTimeMillis()
            if (!AppVersions.isCheckDue(now, prefs.getLong(KEY_CHECKED_AT, 0L))) return@withContext
            val (code, body) = fetch() ?: return@withContext
            // Yanıt geldiyse (403/oran sınırı dahil) 12 saat beklenir; ağ hatasında bir dahaki açılışta yine denenir.
            val edit = prefs.edit().putLong(KEY_CHECKED_AT, now)
            if (code == HttpURLConnection.HTTP_OK) AppVersions.latestVersion(body)?.let { edit.putString(KEY_LATEST, it) }
            edit.apply()
            publish()
        } catch (error: Exception) {
            // Sessiz: güncelleme denetimi hiçbir zaman kullanıcıyı rahatsız etmez.
        }
    }

    /** Karttaki ✕: bu sürüm bir daha gösterilmez (daha yenisi çıkınca kart yine gelir). */
    fun dismiss(context: Context, version: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_DISMISSED, version).apply()
        state.value = null
    }

    private fun fetch(): Pair<Int, String>? {
        val connection = (URL(LATEST_URL).openConnection() as? HttpURLConnection) ?: return null
        return try {
            connection.connectTimeout = 8_000
            connection.readTimeout = 8_000
            connection.setRequestProperty("User-Agent", "Nino-Android")
            connection.setRequestProperty("Accept", "application/vnd.github+json")
            val code = connection.responseCode
            val body = if (code == HttpURLConnection.HTTP_OK) connection.inputStream.bufferedReader().use { it.readText() } else ""
            code to body
        } catch (error: Exception) {
            null
        } finally {
            connection.disconnect()
        }
    }

    private fun installedFromPlay(context: Context): Boolean = try {
        val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getInstallerPackageName(context.packageName)
        }
        installer == PLAY_STORE
    } catch (error: Exception) {
        false
    }
}
