CouchSubs'ın yeni deneme sürümü. Türkçe dil desteği olmayan PS5 oyunlarının İngilizce altyazısını okur, Türkçesini TV'de oyunun üstünde gösterir ve isterseniz Türkçe seslendirir.

**Site, kurulum rehberi ve SSS:** [couchsubs.enmeraapps.com](https://couchsubs.enmeraapps.com)

**İndir:** [Mac (DMG)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-macos.dmg) · [Windows (kurulum)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-windows-Setup.exe) · [Android telefon (Google Play)](https://play.google.com/store/apps/details?id=com.couchsubs.mobile)

**Bu sürümde yeni**

- **Xbox bağlan-kop döngüsü durdu (Windows, #262):** Yayın kopunca uygulama her 5 saniyede bir yeniden bağlanıyor, konsol da her seferinde "oyun başka yerde açıldı" deyip oyunu düşürüyordu. Artık en çok 3 kez (5, 15, 45 sn arayla) deneniyor; konsol kalıcı hata verirse hiç denenmiyor ve nedeni ekranda yazıyor. `altyazi.log` dosyasına `[Xbox]` satırları yazılıyor (jeton yazılmaz); sorun sürerse bu dosyayı gönderebilirsiniz.
- **Xbox telefonlarda (Android, iPhone):** Microsoft girişi, kodu tarayıcıda yazarken uygulama arka planda kalınca "İnternete bağlanılamadı" ile bitmiyor; kod dokununca kopyalanıyor, adımlar açıkça yazıyor (#249). Uzaktan oynatmada oyunun sesi artık telefonda çalıyor; yeni "Xbox sesini bu cihazda çal" ayarı, varsayılan açık (#251). Telefon her kareyi Xbox'a onaylıyor, yayın kendi kendine kapanmıyor (#209, #235, #238); yeniden bağlanınca kare durumu sıfırlanıyor (#204). Windows'ta Xbox kareleri daha sık okunuyor, eski kare birikmiyor (#244); Xbox adındaki Türkçe karakter bozulmuyor (#233).
- **Windows pencereleri (#223, #256, #268, #270):** Ayarlar, Geçmiş ve Hakkında pencereleri ana pencereyi kilitlemiyor, ikinci kopyası açılmıyor. Ayarlar kenar çubuğunun başlığı koyu görünümde okunuyor.
- **Okuma ve çeviri:** Kısa bir OCR okuması kuyruktaki tam repliği silmiyor (#254); pakete eşleşen eksik parça tam repliği ezmiyor (#250); iki sütuna yayılan ekran yazıları komşu sütuna karışmıyor (#255); çeviri hizmeti beklerken önbellekteki çeviri yerel motora yeniden gönderilmiyor (#253). Uzun altyazının yarısı paketten gelmiyor, yapay zekânın çevirmeden döndürdüğü satır yine gösteriliyor (#245, #246). Yarım ve bozuk okuma bekletiliyor, aynı satırın en iyi okuması çevriliyor (Mac, iPhone, Android, #220, #226). Uzun çeviri en çok 3 satıra dengeli bölünüyor (#162). Ücretsiz çeviride oyun terimleri sözlüğü, argo düzeltmesi ve hazır ünlem satırları (#163); konuşan adı çeviriye karışmıyor, "Konuşan adını göster" ayarı (#153).
- **Oyun ve paket:** Elle seçilen oyunda hazır çeviri yalnız o oyunun paketinden geliyor (#218, #227); PS5 başka oyun bildirince eski elle seçim siliniyor (#239); yapay zekâya giden oyun adı tek satırla başka oyuna kaymıyor (#27, #217); yerel modelin bitiş işaretleri ekranda kalmıyor (#214).
- **Hız seçenekleri:** "Değişmeyen altyazı alanını daha sık oku" (isteğe bağlı; Mac, Windows, iPhone, Android, #240, #242). Windows'ta ücretsiz çeviri CTranslate2'ye taşındı, isteğe bağlı NVIDIA GPU (Beta) ve gereken CUDA dosyalarının kendiliğinden indirilmesi (#150, #176), CPU çeviri iş parçacığı seçimi (#240). Katkı: [Berkovant](https://github.com/Berkovant).
- **Windows:** Seçilen OBS projektörü ya da oyun penceresi okunabiliyor (#211); Sony girişi uygulama içinde "Can't connect to the server" derse giriş tarayıcıya geçiyor (#243); ağ "Ortak" ise güvenlik duvarı kartı ağı Özel yapmayı söylüyor (#213); güvenlik duvarı izni özel yerel ağla sınırlı (#164); Remote Play penceresi yakalanırken sarı çerçeve çıkmıyor (#157, #224, #229).
- **Telefonlar (Android, iPhone):** TV'deki altyazının yeri telefondan seçiliyor: örtsün, üstünde, altında, sabit (#191). Yazı boyutu %40'a kadar küçülüyor (#221). Önceki satırları üstte tut ayarı (Mac, iPhone, Android, #151). Android'de Sony girişi ilk açılışta boş kalmıyor (#216), Google seçilince tarayıcıya geçiyor (#241); Gemini dakika sınırında en çok 20 saniye bekleniyor (#228); TV kurulumunda telefonun doğru yerel ağ adresi kullanılıyor (#192).
- **Genel:** Pencereden okurken ya da altyazı bilgisayardayken ekran kapanmıyor (Mac, Windows, #219); PS5 oturum isteğini reddedince anlamlı mesaj (#33, #202, #215); OBS'de çeviri İngilizce satırın üstünde ya da altında da yerleşiyor (#208, #212) ve altyazı kalkarken siyah pencere görünmüyor (#158); ek alanların çevirisi OBS ve yayın penceresinde de görünüyor (#169).
- **TV uygulaması 0.9.22:** Zeminsiz altyazı açık sahnelerde de okunuyor (katmanlı gölge, düşük zeminde ince kontur), HDMI kutusu ve bekleme ekranı düzenlendi, güvenli alan (#261). HDMI görüntüsü gelmeyince LG ve Samsung'da da açık mesaj ve giriş seçici (#236); Android TV'de siyah ekran yerine giriş seçici (#155, #156). LG'nin ekran koruyucusu altyazıyı kapatmıyor (#230, #237). Örtü arka plan koyuluğuna uyuyor (#225); ekran çevirisi komşu kutuya ve alt kenara taşmıyor (#248); Android TV'de HDMI sesi tam sesle açılıyor (#198). Masaüstü uygulaması TV'deki eski sürümü görüp güncellemeyi öneriyor.
- **Android telefon:** [Google Play](https://play.google.com/store/apps/details?id=com.couchsubs.mobile) üzerinden güncelleniyor (0.1.0-beta.53).

Katkıda bulunanlar: [erayslyrt00](https://github.com/erayslyrt00) (#161, #164, #166, #171, #173, #175, #248, #250, #253, #254, #255, #260, #261), [erenbati](https://github.com/erenbati) (#180–#195, #203–#207, #211) ve [Berkovant](https://github.com/Berkovant) (#150, #176, #240); teşekkürler.

**beta.44'te gelenler:** Xbox desteği (Beta; Windows, telefonlarda deneysel), tamamen opak arka plan ve tam genişlik bant, topluluk çeviri paketlerini içe aktarma, PS5 görüntü bildiriminde çökmenin giderilmesi, TV uygulaması 0.9.21 (ekran açık kalıyor, oyun modu).

**beta.43'te gelenler:** Windows Güvenlik Duvarı izni ve Ayarlar kartı (#128), 2016 Samsung TV'ler (deneysel, #71), kurulumda Remote Play yardımı (#107, katkı: [lones8888](https://github.com/lones8888)), çeviri ve okuma iyileştirmeleri ile daha sağlam paket indirme (katkı: [erenbati](https://github.com/erenbati)), TV uygulaması 0.9.20.

**beta.42'de gelenler:** Oynanan oyunun kendiliğinden tanınması, paketlerin sunucudan kendiliğinden güncellenmesi, görüntüyü bu bilgisayardaki PS Remote Play penceresinden okuma (katkı: [lones8888](https://github.com/lones8888), #99), LG'de geliştirici modu parola alanının her zaman görünmesi (#94).

**beta.41'de gelenler:** TV uygulamasının her güncellemede aynı imzayla gelmesi (TV uygulaması 0.9.19), ek alan çevirilerinin TV'de de görünmesi, Android TV'de Play sayfasından kurulum, telefon uygulamalarından TV uygulamasını kurma ve güncelleme (Samsung, LG, Android TV).

**beta.40'ta gelenler:** Ek alanlar (Mac ve Windows: görev, bildirim, telefon yazıları), TikTok LIVE Studio ve diğer yayın programları için yayın penceresi, OBS sayfasında düz zemin (`?bg=`), Android'den Samsung TV'ye TV uygulaması kurulumu.

**beta.39'da gelenler:** PS5 görüntüsü takılınca bağlantının kendiliğinden yeniden kurulması, çevirinin bir süre sonra donmaması (Mac, Windows, iPhone, Android), Android telefon APK 0.1.0-beta.43.

**beta.38'de gelenler:** "Ekranı çevir" düzeltmeleri (TV'siz kullanımda sonuçlar altyazı penceresinde, Gemini'de tek istek), PS5 giriş şifresi alanı, Samsung TV izninin her bağlantıda sorulmaması (#40), elle yazılan adreslerin temizlenmesi, yerel yapay zekâda tırnaksız yanıtlar ve oyun adı (#27), GTA V ve RDR2 paketlerinin daha çok satır yakalaması, yeni paketlerin uygulama güncellemesi beklemeden gelmesi, Android TV'de TV HDMI'yı kendi oynatıcısında açınca katman (TV uygulaması 0.9.18, #42), Mac'te "Altyazıyı göster" kartının taşmaması (#43), Android telefon APK 0.1.0-beta.42 (çeviri başlarken kapanma ve PSN girişinde beyaz ekran düzeltildi). Katkı: [mucahitpuren](https://github.com/mucahitpuren).

**beta.37'de gelenler:** Android telefon uygulaması (deneme), "Unknown Session Request Error"un sebebiyle gösterilmesi, açık renkli sahnelerde çevirinin kaybolmaması, DeepL'de adların korunması, Windows ve iPhone'da takılan okumanın çeviriyi durdurmaması, TV uygulaması 0.9.18 (TV eski adrese takılmıyor, yeni altyazı kaynağını kendisi buluyor), Ayarlar'da bilgisayar ekranındaki altyazı için "Altyazı penceresini ayarla".

**beta.35'te gelenler:** Samsung kurulumunda doğru "Host PC IP" (VPN ve sanal bağdaştırıcılar seçilmiyor), Samsung girişi açılmazsa açılır pencere ipucu ve bağlantıyı kopyala düğmesi, Mac'te alan değişince çevirinin durmasının giderilmesi, "Üstünü örtsün"de tek kutu (TV uygulaması 0.9.17), ücretsiz çeviride "Soul" gibi adların korunması.

**beta.34'te gelenler:** Marvel's Spider-Man 2 ve Death Stranding (Director's Cut) yamaları, Mac'te sol sütun taşmasının giderilmesi, Windows'ta uzun yazıların kesilmeden alt satıra inmesi.

**beta.33'te gelenler:** canlı ölçümler (okuma, çeviri, gecikme), altyazı alanı için hazır seçimler ve canlı önizleme, "TV'de test et", Geçmiş, Windows'ta bozuk ve yarım okunan altyazıların çok azalması (katkı: [ronaldinho62](https://github.com/ronaldinho62), #28), TV uygulaması 0.9.16.

**beta.32'de gelenler:** koyu görünümün varsayılan olması ve Ayarlar'da Görünüm seçimi, yerel yapay zekâ ile çeviri (Ollama, LM Studio), sadeleştirilmiş görünüm, Linux sunucusu (Docker; katkı: Ceyhun Yılmaz), 2017–2018 Samsung TV'ler (deneysel), TV uygulaması 0.9.15 (HDMI'ya kendiliğinden geçen TV için ipucu), Mac'te macOS 13 ve Intel desteği, PS5 eşleşmesinin açıkça gösterilmesi, altyazı günlüğü (`altyazi.log`) ve ortak havuza yalnız İngilizce oyun satırlarının gitmesi.

**beta.31'de gelenler:** Mac'te Samsung TV kurulumundaki "EphemeralKeySet" hatasının düzeltilmesi (Kadir Eker), Mac'te "Çeviriyi durdur"da çökmenin giderilmesi, TV uygulaması 0.9.14 (seslendirme açıkken oyun ekranı kararmıyor; Kadir Eker), aynı cümlenin TV'de üst üste yığılmaması ve hızlı konuşmada satırların kaybolmaması.

**beta.30'da gelenler:** Elden Ring + Shadow of the Erdtree paketi, Windows'ta sayı tuş takımı olmayan klavyeler için Ctrl+Shift+rakam kısayolları, Samsung TV ipuçları (Anynet+ ve güç tuşu), TV uygulaması 0.9.13 (dublaj kapatılınca oyunun sesi geri geliyor), yarım kalan TV kurulumunun bitmiş sayılmaması.

**beta.29'da gelenler:** yeni görünüm (Mac ve Windows'ta iki sütunlu ana ekran, tek pencerede bölümlü Ayarlar), Windows'ta bazı bilgisayarlarda hiç çalışmayan ücretsiz çevirinin düzeltilmesi, GTA V ve RDR2 paketlerinin baştan sona gözden geçirilmesi (yaklaşık 26 bin satır düzeltildi), TV uygulaması 0.9.12.

**beta.28'de gelenler:** oyun paketlerinin ekrandan bozuk okunan ve parça parça gösterilen satırları da yakalaması (Mafia'da kaçan satırların yarısından fazlası artık paketten), altı paketin kalite denetimi (yaklaşık 2.600 satır düzeltildi).

**beta.27'de gelenler:** GTA V, Red Dead Redemption 2, Assassin's Creed Shadows, Death Stranding 2 ve Call of Duty: Modern Warfare (2019) paketleri; Android TV'de siyah ekran için katman modu (TV uygulaması 0.9.11); Windows'ta "Çeviriyi başlat"ta kapanma düzeltmesi; daha açık PS5 durumu; Samsung TV kurulumu düzeltmeleri (sebepli hata mesajları, eski TV uygulamasının kendiliğinden güncellenmesi).

**beta.25 ve beta.26'da gelenler**

- **Oyun çeviri paketleri:** Desteklenen oyunlarda altyazı, önceden hazırlanmış Türkçe çeviriyle anında ve internet gerekmeden gösterilir. İlk paket **Mafia: The Old Country** (18 bin satır, oyunun bütün metni Claude ile çevrildi). Pakette olmayan satırlar her zamanki çeviri motoruyla çevrilir. Ayarlar › Çeviri › Oyun paketleri.
- **Ortak altyazı havuzu:** Paketlerde bulunmayan İngilizce altyazı satırları anonim olarak ortak havuza gönderilir; biriken satırlar çevrilip yeni paketlerle herkese gelir. Yalnız oyunun İngilizce metni gider, başka hiçbir bilgi gitmez. Ayarlar › Çeviri'den kapatılabilir.
- **Altyazı bilgisayar ekranında (TV'siz kullanım):** Kurulumda "TV'm yok, bilgisayar ekranında göster" seçilebiliyor. Altyazı her zaman üstte duran saydam bir pencerede, TV'deki görünümle gösterilir; sürüklenip genişletilebilir, "Tıklamalar geçsin" ile fareyi engellemez (geri almak için Mac'te ⌥⌘L, Windows'ta Num 7). Ana ekranda ve ayarlarda "Altyazıyı göster: TV / Bilgisayar ekranı / İkisi de".
- **PS5 eşleme ve PSN girişi düzeltildi:** Eşleme kodu yazılıp Enter'a basılınca artık bağlanıyor (önceden hiçbir şey olmuyor, kodun süresi doluyordu); kod boşluklu ya da tireli yazılabiliyor. Eşleme ve giriş hataları artık sebebiyle gösteriliyor ("Kod yanlış ya da süresi dolmuş", "PS5 yanıt vermedi", "Sony çok fazla giriş denemesi aldı" gibi). Sorun sürerse ekranda gösterilen günlük dosyasını gönderebilirsiniz (Mac'te `~/Library/Logs/CouchSubs/remoteplay.log`).
- **Ücretsiz Gemini ile daha iyi çeviri:** Kurulumun sonunda isteğe bağlı "Daha iyi çeviri (ücretsiz)" adımı: bir dakikada ücretsiz Google Gemini anahtarı alıp yapıştırınca çeviri çok daha iyi olur. Ücretsiz kotanın dakikalık sınırı aşılmaz; aşılacaksa o satır ücretsiz yerel çeviriyle gösterilir.

**beta.24'te gelenler:** altyazı yazı rengi (beyaz/sarı, TV uygulaması 0.9.10, katkı: [Kadir Eker](https://github.com/kadireker)), Mac'te her açılışta güncelleme kontrolü.

**beta.23'te gelenler:** daha kararlı altyazı (tekrar eden ve kaybolan satırlar giderildi), hızlı konuşmada önceki satırların TV'de üstte kalması (TV uygulaması 0.9.9), isteğe bağlı yapay zekâ çevirisi (Gemini, OpenAI, Claude), oyun sözlüğüyle daha iyi ücretsiz çeviri, kalıcı çeviri önbelleği, TV'nin kopan bağlantıyı kendisi toparlaması, Android TV'de doğru HDMI girişi, Windows'ta LG parolası ve WebView2 düzeltmeleri.

**beta.22'de gelenler:** LG TV'de sihirli kumandanın işaretçisiyle Tamam tuşu (TV uygulaması 0.9.8).

**beta.21'de gelenler:** TV'de altyazının bir an görünüp kaybolması için düzeltme ve panelde Tanı satırı (TV uygulaması 0.9.7), Windows'ta PS5'in IP adresi değişince yeniden bulunması, PS5 eşleştirme hatalarında gerçek sebebin görünmesi, Windows dublajında Türkçe ses motoru hatasının gösterilmesi.

**beta.20'de gelenler:** LG TV'de "TV uygulaması kurulamadı" hatasının düzeltilmesi (bildiren: [yag_ats](https://x.com/yag_ats)).

**beta.19'da gelenler:** Samsung ve Android TV'de görünmeyen altyazının düzeltilmesi (TV uygulaması 0.9.6), Windows Güvenlik Duvarı izni, GTA V ve renkli zeminlerde daha düzgün çeviri (Windows), ortalı altyazının kutusunun ortada durması (Mac ve Windows).

**beta.18'de gelenler:** OBS katmanı (Mac ve Windows), altyazı geçmişi (Mac, katkı: [rumpony](https://github.com/rumpony)).

**beta.17'de gelenler:** Mac uygulamasının macOS 26'da yeniden açılması, kapanıştaki Remote Play çökmesinin giderilmesi (Mac ve Windows), Mac'te disk dolu uyarısı.

**beta.16'da gelenler:** Ekranı çevir (Windows'ta Num 9, Mac'te ⌥⌘T: menüler, görev paneli ve bilgi kutuları TV'de kendi yerinde Türkçe), TV uygulaması 0.9.5, Windows'ta aynı hizadaki uzak yazıların ayrılması.

**beta.15'te gelenler:** birkaç çeviriyi deneyip en iyisini seçen Windows çevirisi, oyun ifadelerinin ("friendlies", "got your six") anlamıyla çevrilmesi, isteğe bağlı DeepL çevirisi (Mac ve Windows), Windows'ta indirmesiz hızlı Türkçe ses.

**beta.14'te gelenler:** Windows'ta İngilizce yazı tanıma paketi uyarısı ve tek düğmeyle kurulumu, menü/gösterge/kumanda ipuçlarının altyazıya karışmaması, yeni altyazı gelince eski dublaj cümlesinin kesilmesi, fareyle çizilen alan ve Num 1/2/3 ek bölgeler (katkı: [sadumqn](https://github.com/sadumqn)), Samsung'da eski kurulumun yeni sürümü engellememesi.

**İndirme**

| Dosya | Ne için |
|---|---|
| `CouchSubs-macos.dmg` | Mac kurulumu (macOS 13+, Apple Silicon ve Intel) |
| `CouchSubs-windows-Setup.exe` | Windows 10 (2004) / 11 kurulumu, 64 bit |
| `CouchSubs-macos.zip`, `CouchSubs-windows-x64.zip` | Kurulumsuz kullanmak isteyenler için |
| `com.couchsubs.tv_…_all.ipk` | LG TV uygulaması, elle kurmak isteyenler için |
| `CouchSubs-samsung-kaynak.zip` | Samsung TV uygulaması, Tizen Studio ile elle kurmak isteyenler için |
| `CouchSubs-androidtv.apk` | Android TV / Google TV uygulaması, USB bellekle kurmak isteyenler için |
| `appcast.xml`, `releases.win.json`, `*.nupkg` | Uygulama içi güncelleme dosyaları (elle indirmeyin) |
| `SHA256SUMS.txt` | Dosyaların doğrulama özetleri |

**Bilinen durumlar**

- Windows kurulum dosyası imzasız: "Windows bilgisayarınızı korudu" uyarısında **Ek bilgi › Yine de çalıştır**. Uyarı yalnız ilk kurulumda çıkar; güncellemelerde çıkmaz.
- Dublaj yeni: sesin TV'den oyunun sesiyle birlikte çalması her TV'de henüz denenmedi. TV'den ses gelmezse ayarlardan sesi bilgisayara alın ve modelinizi yazın. Oyunun ses ayarlarından konuşma (diyalog) sesini kısın.
- Sesler yapaydır, gerçek kişilere ait değildir: Pocket TTS Turkish (wite-tech, CC BY 4.0), Kyutai'nin pocket-tts programıyla.
- Samsung ve Android TV kurulumu gerçek TV'de henüz az denendi. Sorun olursa TV modelinizle birlikte [Issues](https://github.com/yorulmazsinan/couchsubs/issues) sayfasından yazın; Windows'ta günlükler `%LOCALAPPDATA%\CouchSubs` klasöründe (`hata.log`, `remoteplay.log`).
- PS5 aynı anda tek Remote Play bağlantısına izin verdiği için oyun PS Remote Play uygulamasıyla oynanırken CouchSubs kullanılamaz; PS5'in TV'ye HDMI ile bağlı olması gerekir.
- Mağaza sürümleri henüz yok. Vestel, Arçelik, Beko ve Grundig'in Linux modelleri ile Philips Saphi ve Titan OS desteklenmiyor.

---

New beta. Two new game translation packs: Grand Theft Auto V (story text from the GTA TR / TechnoGame Turkish translation, the rest including GTA Online translated with Claude) and Red Dead Redemption 2 (all subtitles and UI text translated with Claude), shown instantly and offline. Also includes beta.25 and beta.26: game translation packs: supported games show a ready-made Turkish translation instantly and offline; the first pack is Mafia: The Old Country (the whole game text translated with Claude). Shared subtitle pool: English lines missing from the packs are sent anonymously so they can be translated for everyone (can be turned off in Settings). Subtitles on the computer screen: a no-TV setup option and an always-on-top, click-through subtitle window. Free Gemini key step for much better free translation. PS5 pairing and PSN sign-in fixed: Enter now connects and every failure shows its reason. Also includes beta.24: subtitle text colour (TV app 0.9.10, contributed by Kadir Eker) and update checks on every Mac launch. Download: [Mac (DMG)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-macos.dmg) · [Windows (installer)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-windows-Setup.exe). Also: Three new game translation packs, translated with Claude and shown instantly and offline: Assassin's Creed Shadows (40k lines), Death Stranding 2: On the Beach (23k lines) and Call of Duty: Modern Warfare (2019) (51k lines: multiplayer and Warzone radio chatter, cinematics, menus). Also includes beta.26: game translation packs (first pack Mafia: The Old Country), the anonymous shared subtitle pool (can be turned off in Settings), subtitles on the computer screen (no-TV setup, click-through window), the PS5 pairing and PSN sign-in fix and the free Gemini key step. Download: [Mac (DMG)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-macos.dmg) · [Windows (installer)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-windows-Setup.exe). Overlay mode for Android TVs where the PS5 picture stays black inside CouchSubs (TCL and others, TV app 0.9. Windows no longer closes when starting translation (errors are shown and logged), and a paired PS5 now reads "paired, connects when translation starts" instead of "not connected". Samsung TV install fixed on Mac (failed after the first install), every install error now shows its reason, and the Samsung TV app is updated automatically.
