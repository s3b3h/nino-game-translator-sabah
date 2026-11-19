// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.service

import com.couchsubs.mobile.core.ShownPair
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

/** Okuma hattının arayüze gösterdiği durum (servis yazar, ekranlar okur). */
data class LiveStatus(
    val running: Boolean = false,
    /** Kısa durum metni: "PS5'e bağlanılıyor…", "Altyazılar okunuyor" gibi. */
    val phase: String = "",
    /** Nino: PS5 görüntüsü şu an geliyor mu (bağlanırken ve koptuğunda false). */
    val streaming: Boolean = false,
    val connectedTvs: Int = 0,
    /** Son gösterilen çeviriler, yeniden eskiye. */
    val recent: List<ShownPair> = emptyList(),
    /** Telefon ekranında şu an gösterilen altyazı (yoksa boş). */
    val current: String = "",
    /** Telefon ekranında güncelin üstünde soluk duran önceki altyazı (yoksa boş). */
    val previous: String = "",
    /** Telefon ekranındaki ek alan çevirileri (görev, telefon, bildirim). */
    val regions: List<com.couchsubs.mobile.core.SubtitleEvent.Region> = emptyList(),
    /** "Ekranı çevir" sonuçları (telefon ekranında yazının kendi yerinde); yoksa boş. */
    val screen: List<com.couchsubs.mobile.core.ScreenTranslation.Item> = emptyList(),
    /** "Ekranı çevir" düğmesinin durumu: çeviri sürüyor ya da sonuçlar ekranda. */
    val screenState: LiveStatus.ScreenState = LiveStatus.ScreenState.IDLE,
    /** Son satırı veren oyun paketinin başlığı (ör. "GTA V"); paket kullanılmadıysa null. */
    val packInUse: String? = null,
    val error: String? = null,
    val framesReceived: Long = 0,
    /** Okumanın başladığı an (duvar saati, ms); süre göstergesi için. */
    val startedAt: Long = 0,
    /** Seçili çeviri motorunun görünen adı ("DeepL", "Ücretsiz"). */
    val engineLabel: String = "",
    /** Bu oturumda gösterilen satır ve paketten gelenler. */
    val shownLines: Int = 0,
    val packLines: Int = 0,
    /** Nino: PS5'siz demo oturumu (örnek altyazılar; ağ ve PS5 kullanılmaz). */
    val demo: Boolean = false,
    /** Oynanan oyun (PS5'in bildirdiği, paketten tanınan ya da seçilen; bkz. [PlayedGame]); bilinmiyorsa null. */
    val game: String? = null,
    /**
     * Nino: tanınan oyun havuz öncelikli mi (şimdilik GTA 6; hizmetin çeviriyi havuza yönlendirirken kullandığı karar,
     * oyun tanınmışsa). Ana ekrandaki sahnenin (salondaki TV, cam düğmeli arayüzün sahnesi) fonu buna göre seçilir
     * (Mac: liveGamePoolFirst). Demo ve klipte hep false.
     */
    val poolFirstGame: Boolean = false,
    /** "Hangi oyunu oynuyorsunuz?" kartı açık. */
    val askingGame: Boolean = false,
    /** Nino: çevirinin başladığı an (TV'ye "started" gönderildi; duvar saati, ms); telefonda 7 sn "Çeviri başladı" balonu. 0: yok. */
    val startedNoticeAt: Long = 0,
) {
    /**
     * Sunucunun olayı telefon ekranına: yeni satır öncekini üste iter; aynı cümlenin uzamış ya da düzelmiş okuması
     * (`replaces`) öncekinin yerine geçer, üste yığılmaz (TV ve iPhone ile aynı). Temizlenince ekran boşalır.
     */
    enum class ScreenState { IDLE, WORKING, SHOWN }

    /**
     * Nino: Ayarlar'daki "GTA 6" kartı (Mac: ninoPoolActive). GTA 6 (havuz öncelikli oyun) için Nino'nun kendi çevirisi
     * geçerli mi: hedef dil havuzun çevirdiği dillerdense (şimdilik Türkçe) ve tanınan oyun havuz öncelikliyse ya da
     * henüz oyun tanınmadıysa evet; kullanıcı varsayılanın açık olduğunu görür. Çeviri sürerken başka bir oyun tanınınca
     * hayır (o oyunda seçili motor çevirir). [game] durunca silinmediği için yalnız çeviri sürerken dikkate alınır.
     * [poolFirst]: sunucunun listesi hizmetin içindedir; burada varsayılanı (Türkçe) kullanılır.
     */
    fun ninoPoolActive(targetLanguage: String,
                       poolFirst: com.couchsubs.mobile.core.TranslationPool.PoolFirstConfig = com.couchsubs.mobile.core.TranslationPool.PoolFirstConfig()): Boolean =
        poolFirst.allows(targetLanguage) && (!running || game == null || poolFirstGame)

    fun phoneEvent(event: com.couchsubs.mobile.core.SubtitleEvent): LiveStatus = when (event) {
        is com.couchsubs.mobile.core.SubtitleEvent.Subtitle ->
            copy(current = event.text, previous = if (event.replaces || current.isEmpty()) previous else current)
        com.couchsubs.mobile.core.SubtitleEvent.Cleared -> copy(current = "", previous = "")
        // Ek alanın çevirisi telefon ekranında da kendi yerinde küçük kutuda görünür (boş metin kutuyu kaldırır).
        is com.couchsubs.mobile.core.SubtitleEvent.Region ->
            copy(regions = regions.filter { it.id != event.id } + listOfNotNull(event.takeIf { it.text.isNotEmpty() }))
        com.couchsubs.mobile.core.SubtitleEvent.RegionsCleared -> copy(regions = emptyList())
        is com.couchsubs.mobile.core.SubtitleEvent.Screen -> copy(screen = event.items, screenState = ScreenState.SHOWN)
        com.couchsubs.mobile.core.SubtitleEvent.ScreenCleared -> copy(screen = emptyList(), screenState = ScreenState.IDLE)
    }
}

object LiveState {
    private const val RECENT = 20
    /** Nino: Sistem sağlığı ölçümleri (hizmet yazar, Ayarlar › Sistem sağlığı okur). */
    val health = com.couchsubs.mobile.core.HealthRecorder()
    private val state = MutableStateFlow(LiveStatus())
    val status: StateFlow<LiveStatus> = state

    fun update(change: (LiveStatus) -> LiveStatus) = state.update(change)

    fun shown(pair: ShownPair, packTitle: String?) = state.update {
        // Paketten gelen son satırın oyunu, oturum boyunca "… paketi kullanılıyor" olarak kalır.
        it.copy(recent = (listOf(pair) + it.recent).take(RECENT), packInUse = packTitle ?: it.packInUse,
            shownLines = it.shownLines + 1, packLines = it.packLines + if (pair.origin == "paket") 1 else 0)
    }

    /** Nino: son satırın çevirisi havuzdan gelen daha iyisiyle değişti; listedeki satır yenilenir, sayılar değişmez. */
    fun upgraded(pair: ShownPair) = state.update {
        val first = it.recent.firstOrNull()
        if (first == null || first.source != pair.source) it
        else it.copy(recent = listOf(first.copy(translation = pair.translation, origin = pair.origin)) + it.recent.drop(1))
    }
}
