// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.settings

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.couchsubs.mobile.core.SubtitlePlacement
import com.couchsubs.mobile.core.toJson
import com.couchsubs.mobile.core.SubtitleStyle
import com.couchsubs.mobile.core.SubtitleTextColor
import com.couchsubs.mobile.core.TargetLanguage
import com.couchsubs.mobile.remoteplay.LoginPasscode
import com.couchsubs.mobile.remoteplay.RegisteredConsole
import com.couchsubs.mobile.tv.InstalledTv
import com.couchsubs.mobile.tv.LgSessionRenewalPolicy
import com.couchsubs.mobile.tv.TvBrand
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Okunan konsol: PlayStation (varsayılan, Remote Play) ya da Xbox (Beta, ev yayını). */
enum class ConsolePlatform { PLAYSTATION, XBOX }

/** Altyazının gösterileceği yer. */
enum class SubtitleTarget { TV, PHONE }

/**
 * Nino: oyun görüntüsünün kaynağı: PS5 Remote Play (ikinci PSN hesabı), Xbox ev yayını (Microsoft hesabı) ya da USB-C ile
 * takılı HDMI yakalama kartı (iki konsolda da çalışır).
 */
enum class VideoSource { REMOTE_PLAY, CAPTURE_CARD, XBOX }

/** Nino: ana ekran arayüzü (Mac ile aynı): Salon (fişi prize takın) ya da Cam düğme. */
enum class HomeStyle { LIVING_ROOM, TOGGLE }

/** Çeviri motoru: ücretsiz cihaz üstü (ML Kit) ya da kullanıcının anahtarıyla çevrimiçi hizmet. */
enum class EngineChoice { FREE, DEEPL, GEMINI, OPENAI, CLAUDE }

/**
 * Anahtarlar ve PS5 kaydı Android Keystore'daki (donanım destekli, dışarı çıkarılamayan) AES-GCM anahtarıyla şifrelenip
 * saklanır. Windows'taki SecureStore (DPAPI) ve Mac'teki Anahtar Zinciri karşılığı. Uygulama silinince gider.
 */
class SecretStore(context: Context) {
    private val prefs = context.getSharedPreferences("secrets", Context.MODE_PRIVATE)
    private val alias = "couchsubs-secrets"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getEntry(alias, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    fun put(name: String, value: String?) {
        if (value.isNullOrEmpty()) {
            prefs.edit().remove(name).apply()
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val sealed = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        prefs.edit().putString(name, Base64.encodeToString(sealed, Base64.NO_WRAP)).apply()
    }

    /** Bütün şifreli değerler ve anahtarın kendisi silinir. */
    fun clear() {
        prefs.edit().clear().commit()
        try {
            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(alias)
        } catch (error: Exception) {
        }
    }

    fun get(name: String): String? {
        val stored = prefs.getString(name, null) ?: return null
        return try {
            val sealed = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, 12))
            String(cipher.doFinal(sealed, 12, sealed.size - 12), Charsets.UTF_8)
        } catch (error: Exception) {
            // Anahtar silinmiş (ör. yedekten geri yükleme): değer okunamaz, yeniden girilir.
            null
        }
    }
}

/** Uygulama ayarları; gizli olanlar [SecretStore]'da. */
class AppSettings(private val appContext: Context) : com.couchsubs.mobile.core.DownloadCounter.Store {
    private val prefs: SharedPreferences = appContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
    val secrets = SecretStore(appContext)

    /** Nino: son bilinen toplam indirme sayısı (ana ekrandaki TV'de; internet yokken bu gösterilir). Hiç alınmadıysa 0. */
    override var downloadTotal: Int
        get() = prefs.getInt("ninoDownloadTotal", 0)
        set(value) = prefs.edit().putInt("ninoDownloadTotal", value).apply()

    var onboarded: Boolean
        get() = prefs.getBoolean("onboarded", false)
        set(value) = prefs.edit().putBoolean("onboarded", value).apply()

    /** Kurulumda PSN girişi ve PS5 eşlemesi "Şimdilik geç" ile atlandı; eşleme sonra Ayarlar'dan yapılır. */
    var setupSkipped: Boolean
        get() = prefs.getBoolean("setupSkipped", false)
        set(value) = prefs.edit().putBoolean("setupSkipped", value).apply()

    /** Nino: görüntü kaynağı; yakalama kartında PSN hesabı ve PS5 eşlemesi gerekmez. */
    var videoSource: VideoSource
        get() = enumOr(prefs.getString("videoSource", null), VideoSource.REMOTE_PLAY)
        set(value) = prefs.edit().putString("videoSource", value.name).apply()

    val usesCaptureCard: Boolean get() = videoSource == VideoSource.CAPTURE_CARD

    /** Nino: Xbox ev yayını seçili (PSN girişi ve PS5 eşlemesi yerine Microsoft girişi ve Xbox seçimi). */
    val usesXbox: Boolean get() = videoSource == VideoSource.XBOX

    /** Kurulumda konsol türü (PS5 / Xbox) soruldu mu. */
    var consoleAsked: Boolean
        get() = prefs.getBoolean("consoleAsked", false)
        set(value) = prefs.edit().putBoolean("consoleAsked", value).apply()

    /** Xbox ile çeviriye hazır: Microsoft girişi yapılmış ve konsol seçilmiş. */
    val xboxReady: Boolean get() = xboxConsole != null && com.couchsubs.mobile.Services.xboxAuth.signedIn

    var target: SubtitleTarget
        get() = enumOr(prefs.getString("target", null), SubtitleTarget.TV)
        set(value) = prefs.edit().putString("target", value.name).apply()

    /**
     * Nino: çeviri dili ("tr" ya da "ar"). Kayıt yoksa: kurulumu bitmiş eski kurulumlar Türkçe açılır; yeni kurulumda
     * telefonun dili Arapçaysa Arapça, değilse Türkçe seçilir (ilk okumada kaydedilir).
     */
    var targetLanguage: String
        get() {
            prefs.getString("targetLanguage", null)?.let { return it }
            val first = if (onboarded) "tr" else TargetLanguage.preferred(java.util.Locale.getDefault().language)
            prefs.edit().putString("targetLanguage", first).apply()
            return first
        }
        set(value) {
            prefs.edit().putString("targetLanguage", TargetLanguage.code(value)).apply()
            applyInterfaceLanguage(value)
        }

    /**
     * Nino: arayüz dili çeviri dilini izler (Arapça seçilince menüler de Arapça; Türkçe seçilince Türkçe). Android 13+
     * uygulama dili olarak ayarlanır; açık ekranlar kendiliğinden yeniden çizilir.
     */
    fun applyInterfaceLanguage(code: String = targetLanguage) {
        if (android.os.Build.VERSION.SDK_INT < 33) return
        try {
            val manager = appContext.getSystemService(android.app.LocaleManager::class.java) ?: return
            // Nino: arayüz çeviri dilinde (Türkçe, Arapça, Hintçe…; Urducada da sağdan sola).
            val wanted = android.os.LocaleList.forLanguageTags(TargetLanguage.interfaceTag(code))
            if (manager.applicationLocales != wanted) manager.applicationLocales = wanted
        } catch (error: Exception) {
            android.util.Log.w("CouchSubsSettings", "arayüz dili", error)
        }
    }

    var engine: EngineChoice
        get() = enumOr(prefs.getString("engine", null), EngineChoice.FREE)
        set(value) = prefs.edit().putString("engine", value.name).apply()

    /** Seçilen yapay zekâ modeli (listede yoksa varsayılan kullanılır). */
    var aiModel: String?
        get() = prefs.getString("aiModel", null)
        set(value) = prefs.edit().putString("aiModel", value).apply()

    var packsEnabled: Boolean
        get() = prefs.getBoolean("packsEnabled", true)
        set(value) = prefs.edit().putBoolean("packsEnabled", value).apply()

    var disabledPacks: Set<String>
        get() = prefs.getStringSet("disabledPacks", emptySet()) ?: emptySet()
        set(value) = prefs.edit().putStringSet("disabledPacks", value).apply()

    /** Ortak havuz: varsayılan açık (masaüstüyle aynı), ayarlardan kapatılır. */
    var sharePool: Boolean
        get() = prefs.getBoolean("sharePool", true)
        set(value) = prefs.edit().putBoolean("sharePool", value).apply()

    /** Oynanan oyun paketle tanınmazsa çeviri başladıktan iki dakika sonra bir kez sorulur (bkz. GameSense). */
    var askGame: Boolean
        get() = prefs.getBoolean("askGame", true)
        set(value) = prefs.edit().putBoolean("askGame", value).apply()

    /** Altyazıdaki konuşan adı ("ARTHUR: …") çeviride gösterilir; kapalıysa yalnız Türkçe cümle görünür. */
    var showSpeakerNames: Boolean
        get() = prefs.getBoolean("showSpeakerNames", true)
        set(value) = prefs.edit().putBoolean("showSpeakerNames", value).apply()

    /**
     * Xbox ev yayınında oyunun sesi bu telefonda çalınır. Xbox uzaktan oynatma sürerken sesi istemciye verip TV'yi
     * susturabilir; kapalıyken ses hiçbir yerden gelmeyebilir, bu yüzden varsayılan açık. PS5'i etkilemez.
     */
    var xboxAudioOnDevice: Boolean
        get() = prefs.getBoolean("xboxAudioOnDevice", true)
        set(value) = prefs.edit().putBoolean("xboxAudioOnDevice", value).apply()

    /** Değişmeyen altyazı bölgesi 20 yerine en fazla 2 kare yeniden kullanılır (Mac/Windows ile aynı); varsayılan kapalı. */
    var fastSubtitleDetection: Boolean
        get() = prefs.getBoolean("fastSubtitleDetection", false)
        set(value) = prefs.edit().putBoolean("fastSubtitleDetection", value).apply()

    /** Bu PS5'te son seçilen oyun ("Hangi oyunu oynuyorsunuz?" kartının ilk önerisi). */
    fun lastGame(console: String): String? = prefs.getString("lastGame.$console", null)

    fun rememberGame(console: String, name: String) = prefs.edit().putString("lastGame.$console", name).apply()

    var keepScreenOn: Boolean
        get() = prefs.getBoolean("keepScreenOn", true)
        set(value) = prefs.edit().putBoolean("keepScreenOn", value).apply()

    /** Telefon ekranındaki altyazının yazı boyu (sp). */
    var phoneTextSize: Int
        get() = prefs.getInt("phoneTextSize", 34)
        set(value) = prefs.edit().putInt("phoneTextSize", value).apply()

    var textColor: SubtitleTextColor
        get() = enumOr(prefs.getString("textColor", null), SubtitleTextColor.WHITE)
        set(value) = prefs.edit().putString("textColor", value.name).apply()

    /** Altyazının yazı tipi (TV, OBS ve telefon ekranı); varsayılan Aksiyon (Barlow Condensed), eski kayıtlarda da. */
    var subtitleFont: com.couchsubs.mobile.core.SubtitleFont
        get() = com.couchsubs.mobile.core.SubtitleFont.from(prefs.getString("subtitleFont", null))
        set(value) = prefs.edit().putString("subtitleFont", value.wire).apply()

    /** TV'deki altyazı kutusunun koyuluğu, yüzde (100: tamamen opak; oyundaki İngilizce yazıyı kapatır). */
    var tvBackground: Int
        get() = prefs.getInt("tvBackground", 72).coerceIn(0, 100)
        set(value) = prefs.edit().putInt("tvBackground", value.coerceIn(0, 100)).apply()

    var tvBackgroundShape: com.couchsubs.mobile.core.SubtitleBackgroundShape
        get() = enumOr(prefs.getString("tvBackgroundShape", null), com.couchsubs.mobile.core.SubtitleBackgroundShape.FIT)
        set(value) = prefs.edit().putString("tvBackgroundShape", value.name).apply()

    /** Hızlı konuşmada önceki satırları üstte tut: varsayılan açık (Windows, Mac ve iPhone ile aynı). */
    var stackPrevious: Boolean
        get() = prefs.getBoolean("stackPrevious", true)
        set(value) = prefs.edit().putBoolean("stackPrevious", value).apply()

    /** Nino: TV'nin sol altındaki küçük Nino işareti görünsün mü (Mac: SubtitleStyle.watermark). Varsayılan açık. */
    var tvWatermark: Boolean
        get() = prefs.getBoolean("tvWatermark", true)
        set(value) = prefs.edit().putBoolean("tvWatermark", value).apply()

    /**
     * Android TV'de PS5 görüntüsünün nasıl gösterileceği. Bazı TV'lerde (ör. TCL) uygulama içindeki görüntü siyah kalıyor;
     * Katman'da TV, PS5'i kendi HDMI girişinde gösterir, altyazı üstte çıkar (Mac, Windows ve iPhone ile aynı seçim).
     */
    var tvDisplayMode: com.couchsubs.mobile.core.TvDisplayMode
        get() = enumOr(prefs.getString("tvDisplayMode", null), com.couchsubs.mobile.core.TvDisplayMode.IN_APP)
        set(value) = prefs.edit().putString("tvDisplayMode", value.name).apply()

    /**
     * TV'de çevirinin yeri: İngilizce altyazının üstünü örtsün (varsayılan), üstünde, altında ya da sabit yükseklikte.
     * Üstünde/altında seçilince oyundaki İngilizce altyazı da görünür (Mac ve Windows'taki Yeri seçimi, iPhone ile aynı).
     */
    var tvPlacement: SubtitlePlacement
        get() = enumOr(prefs.getString("tvPlacement", null), SubtitlePlacement.COVER)
        set(value) = prefs.edit().putString("tvPlacement", value.name).apply()

    /** Sabit yerdeyken altyazının ekranın altından yüksekliği, yüzde (0-85; TV uygulamasıyla aynı sınır). */
    var tvBottomPercent: Int
        get() = prefs.getInt("tvBottomPercent", 7).coerceIn(0, 85)
        set(value) = prefs.edit().putInt("tvBottomPercent", value.coerceIn(0, 85)).apply()

    /** TV'deki yazı boyu: 36, 46, 58, 72. */
    var tvFontSize: Int
        get() = prefs.getInt("tvFontSize", 46)
        set(value) = prefs.edit().putInt("tvFontSize", value).apply()

    /**
     * TV'ye giden görünüm. Yazı boyu Ayarlar › Altyazı görünümündeki ölçekle TV'deki varsayılana (46) göre büyür
     * (iPhone ile aynı: %120 → 55); eskiden ölçek yalnız telefon ekranını değiştiriyor, TV hep 46 kalıyordu.
     */
    val style: SubtitleStyle
        get() = SubtitleStyle(fontSize = scaledFontSize(tvFontSize, subtitleScale), placement = tvPlacement,
            bottomPercent = tvBottomPercent,
            // Nino: örtme kipinde saydam kutu İngilizce yazıyı gizleyemez (iki yazı karışır); bu kipte kutu hep koyu.
            background = SubtitleStyle.effectiveBackground(tvPlacement, tvBackground), backgroundShape = tvBackgroundShape, textColor = textColor, stackPrevious = stackPrevious,
            displayMode = tvDisplayMode, font = subtitleFont, autoSize = tvAutoSize, watermark = tvWatermark)

    /**
     * Nino: TV yazı boyunu oyunun altyazısına uydursun mu (Mac: "Match the game's subtitle size", varsayılan açık). Açıkken
     * TV, Yazı boyu ölçeğini yok sayar; ölçek değiştirilince kapanır ([subtitleScale]). Kaydı olmayan eski kurulumda boyu
     * daha önce değiştirmiş kullanıcı için kapalı başlar (seçtiği boy TV'de görünsün).
     */
    var tvAutoSize: Boolean
        get() = if (prefs.contains("tvAutoSize")) prefs.getBoolean("tvAutoSize", true) else subtitleScale == 100 && tvFontSize == 46
        set(value) = prefs.edit().putBoolean("tvAutoSize", value).apply()

    /** Altyazının arandığı bölge (Ayarlar › Altyazı alanı; iPhone ile aynı hazır seçimler ve Özel). */
    var region: com.couchsubs.mobile.core.CropRegion
        get() = com.couchsubs.mobile.core.cropRegionFrom(prefs.getString("region", null)?.let { runCatching { JSONObject(it) }.getOrNull() })
            ?: com.couchsubs.mobile.core.CropRegion()
        set(value) = prefs.edit().putString("region", value.toJson().toString()).apply()

    var areaPreset: com.couchsubs.mobile.core.AreaPreset
        get() = prefs.getString("areaPreset", null)?.let { name -> runCatching { com.couchsubs.mobile.core.AreaPreset.valueOf(name) }.getOrNull() }
            ?: com.couchsubs.mobile.core.AreaPreset.matching(region)
        set(value) = prefs.edit().putString("areaPreset", value.name).apply()

    /** Hazır seçim: bölgesi de kaydedilir (Özel'de kayıtlı bölge kalır). */
    fun selectAreaPreset(preset: com.couchsubs.mobile.core.AreaPreset) {
        preset.region?.let { region = it }
        areaPreset = preset
    }

    fun setCustomRegion(value: com.couchsubs.mobile.core.CropRegion) {
        region = value
        areaPreset = com.couchsubs.mobile.core.AreaPreset.CUSTOM
    }

    /** Altyazının yanında sürekli okunan ek alanlar (görev, bildirim, telefon; en çok üç). Varsayılan: hiç yok. */
    var extraAreas: List<com.couchsubs.mobile.core.ExtraArea>
        get() = com.couchsubs.mobile.core.ExtraArea.listFromJson(prefs.getString("extraAreas", null))
        set(value) = prefs.edit().putString("extraAreas", com.couchsubs.mobile.core.ExtraArea.listToJson(value.take(com.couchsubs.mobile.core.ExtraArea.MAX_COUNT))).apply()

    /** Bölge ya da ek alanlar değişince (çeviri sürerken yeni bölge hemen okunur). */
    fun onAreasChanged(action: () -> Unit): SharedPreferences.OnSharedPreferenceChangeListener {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == "region" || key == "extraAreas") action()
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        return listener
    }

    /**
     * Altyazının gideceği yer (TV ya da telefon) değişince çağrılır. Çeviri sürerken Ayarlar'dan TV seçilir ya da
     * telefondan TV uygulaması kurulursa altyazı hemen TV'ye gider (iPhone: outputChanged ile aynı). Eskiden yeni seçim
     * ancak çeviri yeniden başlayınca geçerli oluyordu: TV bağlı göründüğü halde altyazı yalnız telefonda kalıyordu.
     */
    fun onTargetChanged(action: () -> Unit): SharedPreferences.OnSharedPreferenceChangeListener {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == "target") action()
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        return listener
    }

    /** Nino: ortak havuz ayarı değişince çağrılır; çeviri sürerken kapatılırsa havuza hemen hiçbir şey sorulmaz. */
    fun onSharePoolChanged(action: () -> Unit): SharedPreferences.OnSharedPreferenceChangeListener {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == "sharePool") action()
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        return listener
    }

    /** Görünüm ayarı değişince (ölçek, renk) çağrılır; çeviri sürerken TV'ye yeni görünüm gider. */
    fun onStyleChanged(action: () -> Unit): SharedPreferences.OnSharedPreferenceChangeListener {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == "subtitleScale" || key == "textColor" || key == "subtitleFont" || key == "tvFontSize" ||
                key == "tvBackground" || key == "tvBackgroundShape" || key == "stackPrevious" || key == "tvDisplayMode" ||
                key == "tvPlacement" || key == "tvBottomPercent" || key == "tvAutoSize" || key == "tvWatermark") action()
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        return listener
    }

    fun removeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) =
        prefs.unregisterOnSharedPreferenceChangeListener(listener)

    companion object {
        /**
         * Yazı ölçeğinin sınırları, yüzde (iPhone ile aynı). Alt sınır eskiden %80'di (TV'de 37 piksel); TV'de en küçüğü
         * bile büyük kalıyordu (#218). %40, TV'de 18 piksel: Mac'teki (20) ve Windows'taki (16) en küçük boya denk.
         */
        const val MIN_SUBTITLE_SCALE = 40
        const val MAX_SUBTITLE_SCALE = 160

        /** Yüzde ölçekle yazı boyu (yuvarlanır). */
        fun scaledFontSize(base: Int, percent: Int): Int =
            Math.round(base * percent.coerceIn(MIN_SUBTITLE_SCALE, MAX_SUBTITLE_SCALE) / 100.0).toInt()
    }

    /** PSN hesap kimliği (8 bayt, base64). */
    var accountId: ByteArray?
        get() = secrets.get("accountId")?.let { Base64.decode(it, Base64.NO_WRAP) }?.takeIf { it.size == 8 }
        set(value) = secrets.put("accountId", value?.let { Base64.encodeToString(it, Base64.NO_WRAP) })

    var console: RegisteredConsole?
        get() = secrets.get("console")?.let {
            try {
                val json = JSONObject(it)
                RegisteredConsole(
                    json.getString("host"), json.getString("name"),
                    Base64.decode(json.getString("registKey"), Base64.NO_WRAP), Base64.decode(json.getString("morning"), Base64.NO_WRAP),
                )
            } catch (error: Exception) {
                null
            }
        }
        set(value) = secrets.put("console", value?.let {
            JSONObject().put("host", it.host).put("name", it.name)
                .put("registKey", Base64.encodeToString(it.registKey, Base64.NO_WRAP))
                .put("morning", Base64.encodeToString(it.morning, Base64.NO_WRAP)).toString()
        })

    /**
     * Konsol türü; seçilmediyse null (kurulumda sorulur). Eski kurulumlar PlayStation sayılır.
     * Nino: tek doğru [videoSource]'tadır (Ayarlar › Görüntü Kaynağı da onu yazar): Xbox ev yayını seçiliyse Xbox,
     * konsol sorulduysa ya da yakalama kartı seçildiyse PlayStation.
     */
    var platformChoice: ConsolePlatform?
        get() = when {
            videoSource == VideoSource.XBOX -> ConsolePlatform.XBOX
            consoleAsked || usesCaptureCard || prefs.contains("platform") -> ConsolePlatform.PLAYSTATION
            else -> null
        }
        set(value) {
            consoleAsked = value != null
            prefs.edit().putString("platform", value?.name).apply()
            if (value == ConsolePlatform.XBOX) videoSource = VideoSource.XBOX
            else if (videoSource == VideoSource.XBOX) videoSource = VideoSource.REMOTE_PLAY
        }

    val platform: ConsolePlatform get() = platformChoice ?: ConsolePlatform.PLAYSTATION
    /** Xbox ev yayınıyla okunuyor (yakalama kartında false: görüntü karttan gelir). */
    val xbox: Boolean get() = platform == ConsolePlatform.XBOX

    /** Microsoft kullanıcı jetonu (Windows'taki userToken JSON'u); Keystore ile şifreli. */
    var xboxUserToken: String?
        get() = secrets.get("xboxUserToken")
        set(value) = secrets.put("xboxUserToken", value)

    /** Seçilen Xbox (kimlik, ad). */
    var xboxConsole: com.couchsubs.mobile.xbox.XboxConsole?
        get() = com.couchsubs.mobile.xbox.XboxConsole.fromJson(prefs.getString("xboxConsole", null))
        set(value) = prefs.edit().apply { if (value == null) remove("xboxConsole") else putString("xboxConsole", value.toJson()) }.apply()

    /** İkinci hesabın PS5 giriş şifresi (4 hane, isteğe bağlı); PS5 isterse oturum açılırken gönderilir. */
    var loginPasscode: String?
        get() = LoginPasscode.normalized(secrets.get("loginPasscode"))
        set(value) = secrets.put("loginPasscode", LoginPasscode.normalized(value))

    /** Hedef seçiminde görülen TV'nin adı (ana ekrandaki "Altyazı · Salon TV"). */
    var tvName: String?
        get() = prefs.getString("tvName", null)
        set(value) = prefs.edit().putString("tvName", value).apply()

    /** Son okuma oturumunun süresi (ms). */
    var lastSessionMs: Long
        get() = prefs.getLong("lastSessionMs", 0)
        set(value) = prefs.edit().putLong("lastSessionMs", value).apply()

    /** Çeviri hizmeti çalışıyor mu; süreç ölünce true kalır, sonraki açılışta kapanışın çeviri sırasında olduğu anlaşılır. */
    var translating: Boolean
        get() = prefs.getBoolean("translating", false)
        set(value) = prefs.edit().putBoolean("translating", value).apply()

    /** Son raporlanan önceki kapanışın anı (ApplicationExitInfo.timestamp; bkz. ExitReport). */
    var lastExitReportAt: Long
        get() = prefs.getLong("lastExitReportAt", 0)
        set(value) = prefs.edit().putLong("lastExitReportAt", value).apply()

    /**
     * Nino: son tanınan oyun havuz öncelikli miydi (GTA 6). Yeni oturumda oyun tanınana kadar ana ekrandaki tema buna göre
     * seçilir (Mac: UserDefaults "ninoLastGamePoolFirst").
     */
    var lastGamePoolFirst: Boolean
        get() = prefs.getBoolean("ninoLastGamePoolFirst", false)
        set(value) = prefs.edit().putBoolean("ninoLastGamePoolFirst", value).apply()

    /** Altyazı yazı ölçeği, yüzde (40–160; tasarım: Ayarlar › Altyazı görünümü). */
    var subtitleScale: Int
        get() = prefs.getInt("subtitleScale", 100).coerceIn(MIN_SUBTITLE_SCALE, MAX_SUBTITLE_SCALE)
        set(value) = prefs.edit().putInt("subtitleScale", value.coerceIn(MIN_SUBTITLE_SCALE, MAX_SUBTITLE_SCALE)).apply()

    /** Profil › Kullanım verisi: hata ve kullanım istatistikleri (Firebase, Meta olay adları). Varsayılan açık. */
    var usageData: Boolean
        get() = prefs.getBoolean("usageData", true)
        set(value) = prefs.edit().putBoolean("usageData", value).apply()

    /** Tanıtım (3 sayfa) ve ana ekran turu (4 adım) bir kez gösterilir. */
    var welcomeSeen: Boolean
        get() = prefs.getBoolean("welcomeSeen", false)
        set(value) = prefs.edit().putBoolean("welcomeSeen", value).apply()

    var tourShown: Boolean
        get() = prefs.getBoolean("tourShown", false)
        set(value) = prefs.edit().putBoolean("tourShown", value).apply()

    /** Nino: ana ekran arayüzü; varsayılan Salon (Mac'teki gibi). */
    var homeStyle: HomeStyle
        // Nino V4: bütün uygulamalarda ortak tasarım salon (fişi prize takmak). V4'ten önce kaydedilen seçim
        // ("homeStyle") yok sayılır, herkes bir kez salona geçer; sonra Ayarlar › Arayüz'den cam düğme seçilebilir.
        get() = enumOr(prefs.getString("homeStyleV4", null), HomeStyle.LIVING_ROOM)
        set(value) = prefs.edit().putString("homeStyleV4", value.name).apply()

    /** Bildirim tercihleri: bağlantı koptuğunda ve yeni paket geldiğinde. */
    var notifyDisconnect: Boolean
        get() = prefs.getBoolean("notify.disconnect", true)
        set(value) = prefs.edit().putBoolean("notify.disconnect", value).apply()

    var notifyNewPacks: Boolean
        get() = prefs.getBoolean("notify.packs", true)
        set(value) = prefs.edit().putBoolean("notify.packs", value).apply()

    /** Kurulum ekranında son seçilen marka; hiç seçilmediyse null (ekran ağda bulduğu TV'nin markasını seçer). */
    var tvInstallBrand: TvBrand?
        get() = prefs.getString("experimental.tvInstallBrand", null)?.let { runCatching { enumValueOf<TvBrand>(it) }.getOrNull() }
        set(value) = prefs.edit().putString("experimental.tvInstallBrand", value?.name).apply()

    /**
     * Bu telefonun TV uygulamasını kurduğu (ya da sürümüne baktığı) TV: marka, adres ve TV'deki sürüm. Uygulama açılınca
     * ve TV her bağlandığında bu TV'deki sürüme bakılır; telefondaki paketten eskiyse güncelleme önerilir.
     */
    var installedTv: InstalledTv?
        get() {
            val brand = prefs.getString("tvApp.brand", null)?.let { runCatching { enumValueOf<TvBrand>(it) }.getOrNull() } ?: return null
            val host = prefs.getString("tvApp.host", null)?.takeIf { it.isNotBlank() } ?: return null
            return InstalledTv(brand, host, prefs.getInt("tvApp.port", 0), prefs.getString("tvApp.version", null))
        }
        set(value) = prefs.edit().apply {
            if (value == null) listOf("tvApp.brand", "tvApp.host", "tvApp.port", "tvApp.version").forEach { remove(it) }
            else putString("tvApp.brand", value.brand.name).putString("tvApp.host", value.host).putInt("tvApp.port", value.port)
                .putString("tvApp.version", value.version)
        }.apply()

    /** LG geliştirici modu için son başarılı uzatma zamanı (ms), TV adresine göre saklanır. */
    fun lgSessionRenewedAt(host: String): Long? {
        val key = LgSessionRenewalPolicy.storageKey(host)
        return if (prefs.contains(key)) prefs.getLong(key, 0L) else null
    }

    fun setLgSessionRenewedAt(host: String, value: Long) {
        prefs.edit().putLong(LgSessionRenewalPolicy.storageKey(host), value).apply()
    }

    fun apiKey(engine: EngineChoice): String? = secrets.get("key." + engine.name)
    fun setApiKey(engine: EngineChoice, key: String?) = secrets.put("key." + engine.name, key?.trim())

    private inline fun <reified T : Enum<T>> enumOr(name: String?, fallback: T): T =
        name?.let { runCatching { enumValueOf<T>(it) }.getOrNull() } ?: fallback
}
