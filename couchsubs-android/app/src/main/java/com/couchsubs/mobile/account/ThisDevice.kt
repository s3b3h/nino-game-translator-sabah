// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "Cihaz bilgileri"nin bu telefondaki değerleri. Based on CouchSubs by Sinan Yorulmaz
// (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-19.
package com.couchsubs.mobile.account

import android.os.Build
import com.couchsubs.mobile.BuildConfig
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.core.DeviceInfo
import com.couchsubs.mobile.service.LiveState
import com.couchsubs.mobile.service.LiveStatus
import com.couchsubs.mobile.settings.AppSettings
import com.couchsubs.mobile.tv.TvBrand

/**
 * Bu telefonun [DeviceInfo] satırları: uygulama sürümü, telefonun modeli, Android sürümü, TV uygulamasının kurulduğu
 * TV, seçili konsol ve şu anki durum. Ayarlar › Sistem sağlığı gösterir; Sorun Bildir ve Nino'ya Sor her gönderimde
 * yeniden okur (TV sonradan bağlanmış, durum değişmiş olabilir).
 *
 * Kişiyi tanıtan hiçbir şey okunmaz: telefonun adı, ANDROID_ID, seri numarası, hesap, IP adresi yoktur. Konsolun ve
 * TV'nin kullanıcının verdiği adı ("Ali'nin PS5'i", "Salon TV") ile ağ adresi de alınmaz; yalnız türleri ve sürümleri.
 * Değerler sabit yazılır (çevrilmez): özet sunucuya arayüz dilinden bağımsız, hep aynı biçimde gider.
 */
object ThisDevice {
    fun rows(settings: AppSettings = Services.settings, status: LiveStatus = LiveState.status.value): List<DeviceInfo.Row> =
        DeviceInfo.rows(
            app = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
            model = DeviceInfo.model(Build.MANUFACTURER, Build.MODEL),
            system = DeviceInfo.system(Build.VERSION.RELEASE, Build.VERSION.SDK_INT),
            tv = tv(settings),
            console = console(settings),
            status = status(settings, status),
        )

    fun summary(): String = DeviceInfo.summary(rows())

    /** TV uygulamasının bu telefondan kurulduğu TV: marka ve TV'deki sürüm. TV'nin modeli telefonda saklanmaz. */
    private fun tv(settings: AppSettings): String? {
        val tv = settings.installedTv ?: return null
        val brand = when (tv.brand) {
            TvBrand.LG -> "LG"
            TvBrand.SAMSUNG -> "Samsung"
            TvBrand.ANDROID_TV -> "Android TV"
        }
        return DeviceInfo.tv(brand, tv.version)
    }

    /** Seçili görüntü kaynağı: eşlenmiş PS5 ya da Xbox (modeliyle) ve bağlantı yolu; eşleme yoksa satır olmaz. */
    private fun console(settings: AppSettings): String? = when {
        settings.usesCaptureCard -> DeviceInfo.console(null, "Yakalama kartı")
        settings.usesXbox -> settings.xboxConsole?.let { xbox ->
            val model = xbox.model.trim()
            DeviceInfo.console(if (model.startsWith("Xbox", ignoreCase = true)) model else "Xbox $model".trim(), "Remote Play")
        }
        else -> settings.console?.let { DeviceInfo.console("PS5", "Remote Play") }
    }

    /**
     * Son hata, yoksa çeviri açıkken o anki durum ("PS5'e bağlanılıyor…"). Durum metni konsolun adresini taşıyabilir
     * ("… 192.168.1.20 adresinde bulunamadı"): adresler ve cihaz adları çıkarılır.
     */
    private fun status(settings: AppSettings, status: LiveStatus): String? {
        val text = status.error?.takeIf { it.isNotBlank() } ?: status.phase.takeIf { status.running && it.isNotBlank() } ?: return null
        return DeviceInfo.withoutAddresses(text, listOf(settings.console?.host, settings.console?.name, settings.xboxConsole?.name,
            settings.installedTv?.host, settings.tvName))
    }
}
