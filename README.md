<p align="center"><img src="docs/nino/tanitim/v3/ekran/nino-v3-yatay-1.jpg" width="880" alt="Nino V3: PS5 ve Xbox oyunları artık Türkçe"></p>

<h1 align="center">Nino Game Translator</h1>

<p align="center"><b>Türkçe desteği olmayan PS5 ve Xbox oyunlarını Türkçe oynayın.</b><br>
Oyundaki İngilizce altyazıyı anlık olarak Türkçeye (ya da Arapçaya) çevirir ve TV'de, oyunun tam üstünde gösterir.<br>
Tamamen ücretsiz · açık kaynak · reklamsız · abonelik yok · hesap yok</p>

<p align="center">
  <a href="https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Mac.zip"><b>⬇️ Mac</b></a> &nbsp;·&nbsp;
  <a href="https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Windows-Setup.exe"><b>⬇️ Windows</b></a> &nbsp;·&nbsp;
  <a href="https://yunusdemirbag.github.io/nino-game-translator/"><b>📺 Android TV</b></a> (TV'de Downloader'a <code>is.gd/ninotvapk</code> yazın)<br>
  <a href="https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Telefon.apk">⬇️ Android telefon</a> &nbsp;·&nbsp;
  📱 iPhone: App Store incelemesinde &nbsp;·&nbsp;
  ▶️ Google Play: kapalı testte &nbsp;·&nbsp;
  <a href="docs/KURULUM.md"><b>📘 Kurulum Rehberi</b></a> &nbsp;·&nbsp;
  <a href="#fotoğraflı-kurulum-ps5--android-tv"><b>📷 Fotoğraflı Kurulum (PS5 + Android TV)</b></a>
</p>

<p align="center">
  <img src="docs/nino/video/rdr2-turkce-altyazi.gif" width="880" alt="Red Dead Redemption 2: TV'de oyunun üstünde akan Türkçe altyazı"><br>
  <sub>Gerçek bir TV'den, Red Dead Redemption 2: İngilizce altyazı anında Türkçe olarak oyunun üstünde. <a href="docs/nino/video/rdr2-turkce-altyazi.mp4"><b>▶️ Sesli tam video (30 sn)</b></a></sub>
</p>

<p align="center">
  <img src="docs/nino/v3/ekranlar/ana-ps5.jpg" width="440" alt="Nino Mac ana ekranı: PS5">&nbsp;
  <img src="docs/nino/v3/ekranlar/ana-xbox.jpg" width="440" alt="Nino Mac ana ekranı: Xbox"><br>
  <sub>PS5 ya da Xbox: fişi prize takın, çeviri başlasın. Ana ekran seçtiğiniz konsola göre değişir.</sub>
</p>

---

## Nasıl çalışır

```
PS5 ──HDMI──▶ TV  ◀── Türkçe altyazı (TV'deki Nino uygulaması, oyunun üstünde)
 │                         ▲
 └─ Remote Play ──▶ Nino (Mac ya da Windows): okur → çevirir ─┘
    (ikinci, ücretsiz PSN hesabıyla)
```

Oyunu her zamanki gibi TV'de, kendi kolunuzla oynarsınız. Bilgisayardaki Nino aynı görüntüyü Remote Play ile alır,
altyazıyı okur, çevirir ve TV'ye gönderir. TV'deki Nino çeviriyi İngilizcenin tam üstüne koyar.

- **TV'de oynuyorsanız:** Önerilen kurulum **Mac ya da Windows + TV uygulaması**.
- **Capture Card'ınız varsa:** Mac ya da Windows görüntüyü karttan alır; Remote Play ve ikinci PSN hesabı gerekmez.
- **Xbox'ta oynuyorsanız:** Android telefon Xbox'ın ev yayınını Microsoft hesabınızla okur; Mac ve Windows Xbox penceresini okur. Ayrıntılar aşağıda, [Xbox](#xbox) bölümünde.
- **Bilgisayarınız yoksa ya da monitörde oynuyorsanız:** **Android telefon** (yakında iPhone) aynı işi yapar; altyazıyı TV'ye gönderir ya da kendi ekranında gösterir.

## Yenilikler

**0.2.0** (Mac, Windows ve Android telefon; kurulu Nino kendiliğinden güncellenir):

- 🌍 **11 çeviri dili:** 🇹🇷 Türkçe (en başta), 🇸🇦 Arapça, 🇮🇳 Hintçe, 🇮🇩 Endonezce, 🇹🇭 Tayca, 🇻🇳 Vietnamca, 🇵🇰 Urduca, 🇧🇩 Bengalce, 🇲🇾 Malayca, 🇵🇭 Filipince, 🇳🇱 Felemenkçe. Bayraklı menüden seçilir; uygulamanın menüleri de o dile geçer.
- 🔤 **Altyazı yazı tipi:** Aksiyon (GTA tarzı, yeni varsayılan), Modern, Yuvarlak ya da Sade. TV'de, bilgisayarda, telefonda ve OBS'te aynı yazı tipi.
- 📺 **TV uygulamasını telefondan kurun:** Android telefondaki Nino, Android TV, Samsung ve LG TV'ye uygulamayı bilgisayarsız kurar (Profil › Nino'yu TV'ye Kur).
- 🎥 **Yayıncılar için (Windows):** Capture card doğrudan OBS'e bağlanır, Nino altyazıyı OBS projektöründen okur (Ayarlar › Görüntü kaynağı › OBS projektörü). Görüntü ve ses OBS'ten temiz gider, altyazı OBS'e tek gelir.
- 🤖 **Nino'ya Sor:** Türk bayraklı şapkalı kurulum yardımcısı robot. Cihazlarınızı sorar, kurulumu adım adım anlatır, ekran görüntüsüne bakar, çözemediği sorunu ekibe kendisi bildirir. 12 dilde.
- 🐞 **Sorun Bildir:** Ayarlar'dan açıklama ve ekran görüntüsü ile doğrudan bize yazın.
- CouchSubs'ın son düzeltmeleri: Xbox bağlantısı, TV'de daha okunaklı altyazı, daha doğru altyazı okuma ve daha fazlası.

<p align="center">
  <img src="docs/nino/v3/v020/android-dil-menusu.jpg" width="200" alt="11 dil, bayraklı menü">&nbsp;
  <img src="docs/nino/v3/v020/android-hintce.jpg" width="200" alt="Hintçe arayüz">&nbsp;
  <img src="docs/nino/v3/v020/android-yazi-tipi.jpg" width="200" alt="Yazı tipi seçimi">&nbsp;
  <img src="docs/nino/v3/v020/android-tv-kur.jpg" width="200" alt="Telefondan TV'ye kurulum">
</p>
<p align="center"><img src="docs/nino/v3/v020/tv-yazi-tipleri.jpg" width="700" alt="TV'de dört yazı tipi"></p>

<p align="center">
  <img src="docs/nino/tanitim/v3/ekran/nino-v3-1.jpg" width="170" alt="Nino V3">&nbsp;
  <img src="docs/nino/tanitim/v3/ekran/nino-v3-2.jpg" width="170" alt="Altyazı TV'de">&nbsp;
  <img src="docs/nino/tanitim/v3/ekran/nino-v3-3.jpg" width="170" alt="Nino'ya Sor">&nbsp;
  <img src="docs/nino/tanitim/v3/ekran/nino-v3-4.jpg" width="170" alt="11 dilde">&nbsp;
  <img src="docs/nino/tanitim/v3/ekran/nino-v3-5.jpg" width="170" alt="Her cihazda: PS5 ve Xbox">&nbsp;
</p>

> Önceki sürümün (0.1.9) yenilikleri:

- **🎮 İlk ekranda konsol seçimi (Mac):** "Hangi konsolda oynuyorsunuz?" **PS5** seçilirse ikinci hesap ve eşleştirme adımları, **Xbox** seçilirse "Xbox'ınızı Bu Mac'e Getirin" sayfası gelir (xbox.com/play ya da Greenlight). Konsol sonradan **Ayarlar › Bağlantı**'dan değiştirilir.
- **🟩 Xbox'a özel ana ekran:** Xbox seçilince salon sahnesinde Xbox durur; fiş ve priz aynı çalışır.
- **✨ Yeniden tasarlanan kurulum:** Her sayfa pencereye kaydırmadan sığar. Sade, kurumsal anlatım; PSN girişi tek büyük düğme; PS5 eşleştirme üç adım kartı ve 8 kutulu kod alanı; TV seçiminde görseller; "Deneyelim" ortalı.
- **📷 Fotoğraflı kurulum:** PS5 + Android TV kurulumu gerçek fotoğraflarla [aşağıda](#fotoğraflı-kurulum-ps5--android-tv).
- **🧹 Daha temiz çeviri:** Oyunların açılıştaki yasal uyarıları ve ekranın iki yanından taşan kesik yazılar artık altyazı sanılıp çevrilmez.
- **🇸🇦 Mac'te tam Arapça:** Arapça bayrağı seçilince arayüz de Arapçaya döner ve sağdan sola dizilir.
- **🔄 Sıfırla:** Ayarların en altında ayrı bir bölüm: "TV'den itibaren yeniden kur" ya da "Her şeyi sıfırla" (kurulum konsol seçiminden başlar).
- **Düzeltmeler:** PS5 menü adları Türkçe arayüzle aynı ("Uzaktan Oynama", "Uzaktan Oynama Bağlantı Durumunu Gizle"); "Monitörde Remote Play ile oynuyorum"; TV'siz kullanım için "TV'm Yok, Bu Mac'in Ekranında Göster".

<details>
<summary><b>Yeni kurulum ekranları (Mac)</b></summary>

| | |
|---|---|
| <img src="docs/nino/v3/ekranlar/ps5-karsilama.jpg" width="420" alt="PS5 karşılama"> | <img src="docs/nino/v3/ekranlar/xbox-kurulum.jpg" width="420" alt="Xbox'ınızı Bu Mac'e Getirin"> |
| PS5 karşılaması | Xbox: Xbox'ınızı Bu Mac'e Getirin |
| <img src="docs/nino/v3/ekranlar/ikinci-hesap.jpg" width="420" alt="Altyazı için 2. PSN hesabı"> | <img src="docs/nino/v3/ekranlar/psn-giris.jpg" width="420" alt="İkinci hesabınızla giriş yapın"> |
| Altyazı için 2. PSN hesabı | İkinci hesabınızla giriş |
| <img src="docs/nino/v3/ekranlar/ps5-baglama.jpg" width="420" alt="PS5'inizi bağlayın"> | <img src="docs/nino/v3/ekranlar/tv-secimi.jpg" width="420" alt="TV'nizi bağlayın"> |
| PS5'inizi bağlayın (8 haneli kod) | TV'nizi bağlayın |
| <img src="docs/nino/v3/ekranlar/deneyelim.jpg" width="420" alt="Deneyelim"> | <img src="docs/nino/v3/ekranlar/daha-iyi-ceviri.jpg" width="420" alt="Daha doğal çeviri"> |
| Deneyelim | Daha doğal çeviri (ücretsiz) |
| <img src="docs/nino/v3/ekranlar/ayarlar-baglanti.jpg" width="420" alt="Ayarlar › Bağlantı: PS5 ya da Xbox"> | <img src="docs/nino/v3/ekranlar/ayarlar-sifirla.jpg" width="420" alt="Ayarlar › Sıfırla"> |
| Ayarlar › Bağlantı: konsol seçimi | Ayarlar › Sıfırla |

</details>

<details>
<summary><b>0.1.8'de yenilikler</b></summary>


- **🎮 Xbox desteği (deneysel):**
  - **Android telefon:** İlk açılışta "Hangi Konsolda Oynuyorsunuz?" diye sorar. Xbox'ı seçin, Microsoft hesabınızla giriş yapın (şifre yazmadan, microsoft.com/link'te kodla), Xbox'ınızı seçin ve kaydırın. İkinci hesap gerekmez.
  - **Mac ve Windows:** İlk ekranda **"Xbox'ta oynuyorum"**. Nino; Windows'ta Xbox uygulamasının **Uzaktan oynat** penceresini, Mac'te [Greenlight](https://github.com/unknownskl/greenlight) ya da **xbox.com/play** penceresini okur.
  - **Capture Card** yolu Xbox'ta da çalışır.
- Mac'in ilk ekranındaki kısa yollar (Remote Play penceresi, Xbox, Capture Card) artık hep görünüyor.
- Android'de gizlilik, yardım ve kaynak bağlantıları Nino'nun kendi sayfalarına yönlendirildi. [Gizlilik politikası](PRIVACY.md) Nino için yeniden yazıldı.

</details>

<details>
<summary><b>0.1.7'de yenilikler</b></summary>

**Mac ve Windows**
- **HDMI Capture Card:** PS5 görüntüsünü Capture Card'dan alma. Remote Play ve ikinci PSN hesabı gerekmez (Ayarlar › Bağlantı).
- **PS Remote Play penceresinden okuma** ve **Arapça çeviri**.
- Mac 0.1.5 ve sonrası güncellemeyi kendisi alır; Windows da kendini günceller.

**Android telefon (ve yakında iPhone)**
- **Yeni tasarım:** Sade ana ekran, canlı altyazıların aktığı koyu sahne kartı ve **"Başlatmak İçin Kaydırın"** çubuğu; kaydırınca tutamaç camlı bir **ay yıldız** (Arapça'da 🇸🇦) olur.
- **Yan çevirin, tam ekran açılsın;** ana ekran hep dikey kalır. Yenilenen kurulum ekranları ve **PS5'siz demo**.
- **Tam Arapça:** Çeviri dili Arapça seçilince menüler de Arapçaya döner; uygulama yalnız Türkçe ve Arapça açılır.
- **PS5 kendiliğinden bulunur**, Sony girişi düzeldi, bazı MediaTek telefonlarda görüntü okunamaması giderildi.
- **HDMI Capture Card (deneysel):** Android 14+ telefonlarda USB-C ile.

</details>

## Kimler kullanabilir

| Nino'yu çalıştıran cihaz | Durum |
|---|---|
| **Mac** (Apple Silicon: M1 ve sonrası) | ✅ Hazır, en çok denenen |
| **Windows 10/11** bilgisayar | ✅ Hazır |
| **Android telefon** (Android 8 ve üzeri) | ✅ Hazır, yeni tasarım |
| **iPhone** | 🔜 App Store incelemesinde |

| Altyazının çıktığı yer | Durum |
|---|---|
| **Android TV / Google TV** (TCL, Sony, Philips, Xiaomi, Hisense ve diğerleri) | ✅ Hazır, denendi |
| **LG** (webOS) · **Samsung** (Tizen) | 🧪 Deneysel |
| **Bilgisayar ya da telefon ekranı** (TV uygulaması olmadan, monitörde oynayanlar için) | ✅ Hazır |

## Gerekenler

| | |
|---|---|
| **Konsol** | PS5 (Remote Play açık) ya da Xbox Series X\|S (Uzak özellikler açık, deneysel) |
| **Bilgisayar** | Apple Silicon (M1 ve sonrası) Mac, macOS 13+ · ya da Windows 10/11 (64 bit). Bilgisayar yoksa Android 8+ telefon. |
| **TV** | Android TV / Google TV (denendi). LG ve Samsung deneysel. |
| **Hesap** | PS5: ikinci, ücretsiz bir PSN hesabı (Remote Play için; oyun sizin hesabınızda oynanır). Xbox: kendi Microsoft hesabınız. Capture Card ile hesap gerekmez. |
| **Ağ** | Konsol, bilgisayar/telefon ve TV aynı Wi-Fi'de |

## Kurulum

Adım adım anlatım: **[📘 Kurulum Rehberi](docs/KURULUM.md)** · PS5 ve Android TV için fotoğraflı anlatım: **[aşağıda](#fotoğraflı-kurulum-ps5--android-tv)**

**Mac:** [`Nino-Mac.zip`](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Mac.zip)'i indirin, Nino'yu **Uygulamalar**'a sürükleyin ve açın ("doğrulanamadı" derse **Sistem Ayarları › Gizlilik ve Güvenlik › Yine de Aç**). Nino adım adım yol gösterir: ikinci PSN hesabıyla giriş, PS5'i 8 haneli kodla eşleme, TV seçimi. TV'de USB hata ayıklama açıksa TV uygulamasını da Mac kurar.

**Windows:** [`Nino-Windows-Setup.exe`](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Windows-Setup.exe)'yi çalıştırın ("bilgisayarınızı korudu" derse **Ek bilgi › Yine de çalıştır**). Kurulum Mac ile aynıdır.

**TV (Android TV / Google TV):** TV uygulamasını yazı yazmadan kurmanın iki yolu var:
- **Telefondan (bilgisayarsız):** Android telefondaki Nino'da **Profil › Nino'yu TV'ye Kur**'a basın (Android TV, Samsung ve LG). Telefon TV'yi Wi-Fi'da bulur, uygulamayı kurar ve açar; ekrandaki adımlar TV'nizin markasına göre anlatılır. Android TV'de bir kez **Ayarlar › Sistem › Hakkında › Android TV işletim sistemi yapısı**'na 7 kez basıp **Geliştirici seçenekleri**'nde hata ayıklamayı açmanız ve TV'deki izin sorusuna **Tamam** demeniz yeter.
- **Bilgisayardan:** Mac ya da Windows'taki Nino aynı şekilde kendisi kurar.

Elle kurmak isterseniz: TV'de Google Play'den ücretsiz **Downloader**'ı açın, **Ana Sayfa**'daki adres kutusuna **`https://is.gd/ninotvapk`** yazıp **Git**'e basın ve inen dosyayı kurun (Downloader'ın Tarayıcı sekmesine yazarsanız Google'da arar). Doğrudan link: [Nino TV indirme sayfası](https://yunusdemirbag.github.io/nino-game-translator/) · [`Nino-TV.apk`](https://yunusdemirbag.github.io/nino-game-translator/tv.apk).

**Android telefon (bilgisayar yerine):** [`Nino-Telefon.apk`](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Telefon.apk)'yı telefonda indirip kurun, ikinci PSN hesabıyla **Sony İle Giriş Yapın**, PS5'teki 8 haneli kodu yazın ve oyunu açınca **kaydırın**.

**Xbox:** Telefonda ve Mac'te ilk ekranda **Xbox**'ı seçin (telefonda Microsoft hesabınızla giriş yapılır); Windows'ta **"Xbox'ta oynuyorum"**a tıklayın. Adımlar: [Kurulum Rehberi › Xbox](docs/KURULUM.md#6-xbox-ile-kullanım-yeni-deneysel).

## Fotoğraflı kurulum: PS5 + Android TV

PS5'i **Android TV ya da Google TV**'ye bağlı olanlar için, gerçek bir kurulumdan fotoğraflarla (TCL, iFFALCON, Sony, Philips, Vestel, Arçelik, Beko, Grundig ve diğerleri). Kurulum bir kez yapılır ve yaklaşık **10 dakika** sürer. PS5, TV ve bilgisayar **aynı Wi-Fi ağında** olmalıdır. Ayrı sayfa olarak: [📷 Android TV Rehberi](docs/KURULUM-ANDROID-TV.md).

### Adım 1 — İkinci PSN hesabını PS5'e ekleyin

1. [playstation.com](https://www.playstation.com)'da **yeni bir e-posta adresiyle** ücretsiz bir PSN hesabı oluşturun.
2. PS5'te kullanıcı seçme ekranında **Kullanıcı Ekle**'yi seçin ve yeni hesapla bir kez giriş yapın.

Aşağıdaki örnekte ikinci hesabın adı **"Ceviri Altyazi"**dir. Siz istediğiniz adı verebilirsiniz.

![PS5 kullanıcı seçme ekranı: Kullanıcı Ekle ve ikinci hesap](docs/nino/v3/rehber/android-tv/2-ikinci-hesap.jpg)

> PS5 açıkken başka bir hesaba geçmek için: **PS düğmesi › profil resminiz › Kullanıcı Değiştir**.
>
> ![Kullanıcı Değiştir penceresi](docs/nino/v3/rehber/android-tv/1-kullanici-degistir.jpg)


### Adım 2 — İkinci hesapta Uzaktan Oynama'yı açın

İkinci hesaptayken **Ayarlar › Sistem › Uzaktan Oynama**'ya gidin:

| Seçenek | Ne yapılacak |
|---|---|
| **Uzaktan Oynama'yı Etkinleştir** | Açın. |
| **Uzaktan Oynama Bağlantı Durumunu Gizle** (en alttaki) | **Açın.** Böylece oyun sırasında "Uzaktan Oynama bağlandı" bildirimi çıkmaz. |
| **Cihazı Eşleştir** | Adım 3'te bilgisayardaki Nino isteyince seçeceksiniz. |

![PS5 Ayarlar › Sistem › Uzaktan Oynama](docs/nino/v3/rehber/android-tv/3-uzaktan-oynama.jpg)


### Adım 3 — Bilgisayarda Nino'yu kurun

1. Nino'yu indirip açın: [Mac](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Mac.zip)
   · [Windows](docs/KURULUM.md#2-mac-ve-windows-ile-kurulum-tv-için-önerilen).
2. İlk ekranda **PS5**'i seçin ve **Devam**'a basın.
3. **İkinci hesabınızla giriş yapın.** Şifrenizi yalnızca Sony'nin kendi sayfasına yazarsınız; Nino şifrenizi görmez.
4. **PS5'inizi bağlayın.** PS5'te ikinci hesaptayken **Ayarlar › Sistem › Uzaktan Oynama › Cihazı Eşleştir**'i seçin.
   TV'de görünen **8 haneli kodu** Nino'ya yazın ve **Bağlan**'a basın. Kod yaklaşık 5 dakika geçerlidir.
5. **TV'nizi bağlayın.** **Android TV / Google TV**'yi seçin. Nino, TV uygulamasını TV'ye kendisi kurar ve açar;
   TV bir kez izin isterse kumandayla onaylayın.


### Adım 4 — TV'de Nino uygulaması

Kurulumdan sonra Nino, TV'nin uygulamalar satırında görünür. Açtığınızda bilgisayardaki Nino'yu bekler ve PS5'in hangi
HDMI girişinde olduğunu söyler.

![TV'deki Nino uygulaması: Bilgisayardaki Nino bekleniyor](docs/nino/v3/rehber/android-tv/6-nino-tv.jpg)


### Adım 5 — Oynayın

1. PS5'te **kendi hesabınıza** dönün ve oyununuzu açın.

   ![Kendi hesabınızla PS5 ana ekranı](docs/nino/v3/rehber/android-tv/4-kendi-hesabin.jpg)

2. Bilgisayardaki Nino'da **fişi prize takın** (ya da çeviri düğmesine basın). Nino ikinci hesapla bağlanır; TV'deki
   Nino uygulaması kendiliğinden açılır.

   ![Uzaktan Oynama bağlandı; TV'nin uygulamalar satırında Nino](docs/nino/v3/rehber/android-tv/5-uzaktan-oynama-baglandi.jpg)

3. TV kumandasının kaynak tuşuyla PS5'in HDMI girişine geçin. Türkçe altyazı, oyunun üstünde görünür.

   ![Oyunun üstünde Türkçe altyazı](docs/nino/v3/rehber/android-tv/7-oyunda-turkce-altyazi.jpg)

   Konuşanın adı da çevrilir ve altyazı oyunun kendi yerinde durur (Mafia: The Old Country):

   ![Mafia: The Old Country'de konuşan adıyla Türkçe altyazı](docs/nino/v3/rehber/android-tv/8-mafia-turkce-altyazi.jpg)

Bir dahaki sefere yalnız 5. adım yeterlidir: oyunu açın, fişi takın.


### Sorun giderme

| Sorun | Çözüm |
|---|---|
| TV'de **"Bilgisayardaki Nino bekleniyor"** yazısı gitmiyor | Bilgisayardaki Nino'nun açık olduğundan ve fişin takılı olduğundan emin olun. Olmazsa bilgisayardaki Nino'yu kapatıp yeniden açın. TV ve bilgisayar aynı Wi-Fi'da olmalı. |
| Bilgisayarda **"TV uygulaması bekleniyor"** yazıyor | TV'de Nino uygulamasını açın. Bilgisayarda Nino'nun yalnızca **bir** kopyasının açık olduğundan emin olun. |
| Oyun açılırken yasal uyarılar ya da menü yazıları çevriliyor | Nino yalnız oyunun altyazı alanını okur; açılış ekranları geçince düzelir. Ayarlar › Altyazı alanı'ndan alanı daraltabilirsiniz. |
| Ekranda **"Uzaktan Oynama bağlandı"** bildirimi çıkıyor | İkinci hesapla Ayarlar › Sistem › Uzaktan Oynama'da **Uzaktan Oynama Bağlantı Durumunu Gizle**'yi açın. |
| PS5 bulunamıyor | PS5 açık ya da dinlenme modunda olmalı ve aynı Wi-Fi'da olmalı. Mac'te **Sistem Ayarları › Gizlilik ve Güvenlik › Yerel Ağ**'da Nino'ya izin verin. Gerekirse PS5'in IP adresini elle girin. |
| Her şeyi baştan kurmak istiyorum | Nino'da **Ayarlar › Sıfırla**. |

## Telefon uygulaması

<p align="center">
  <img src="docs/nino/v3/v017/android-karsilama-1.jpg" width="150" alt="Karşılama">&nbsp;
  <img src="docs/nino/v3/v017/android-psn.jpg" width="150" alt="İkinci PSN hesabı">&nbsp;
  <img src="docs/nino/v3/v017/android-cikis.jpg" width="150" alt="Altyazılar nerede görünsün">&nbsp;
  <img src="docs/nino/v3/v017/android-ana-ekran.jpg" width="150" alt="Ana ekran">&nbsp;
  <img src="docs/nino/v3/v017/android-canli.jpg" width="150" alt="Canlı çeviri">
</p>

## Xbox

<p align="center">
  <img src="docs/nino/v3/tanitim/xbox-konsol.jpg" width="190" alt="Hangi konsolda oynuyorsunuz">&nbsp;
  <img src="docs/nino/v3/tanitim/xbox-giris.jpg" width="190" alt="Xbox'ınızı bağlayın">&nbsp;
  <img src="docs/nino/v3/tanitim/xbox-kaynak.jpg" width="190" alt="Görüntü kaynağı: PS5, Xbox, Capture Card">
</p>
<p align="center">
  <img src="docs/nino/v3/tanitim/xbox-mac.jpg" width="560" alt="Mac: Xbox'ta oynuyorum">
</p>

- **Android telefon:** Nino, Xbox uygulamasındaki "Uzaktan oynat" ile aynı ev yayınını Wi-Fi'dan **yalnız izler**: ses çalmaz, kolunuza ve hesabınıza dokunmaz. Microsoft girişi kodla yapılır, şifrenizi Nino görmez; oturum jetonu yalnız telefonda şifreli saklanır.
- **Mac ve Windows:** Xbox'ı bilgisayarda açtığınız pencereden (Windows'ta Xbox uygulaması, Mac'te Greenlight ya da xbox.com/play) okur.
- **Xbox'ta:** Ayarlar › Cihazlar ve bağlantılar › **Uzak özellikler** açık olmalı.
- Xbox desteği yeni: kod hazır ve testleri geçiyor ama gerçek Xbox'larla az denendi. Gördüğünüz sorunları [Issues](https://github.com/yunusdemirbag/nino-game-translator/issues)'a yazın.

## العربية · Arapça

<p align="center">
  <img src="docs/nino/v3/v017/android-arapca-canli.jpg" width="200" alt="الواجهة العربية">
</p>

<p dir="rtl" align="right"><b>نينو</b> يقرأ الترجمة الإنجليزية في ألعاب PS5 ويعرضها مترجمة إلى العربية فورًا فوق اللعبة على التلفاز، عبر تطبيق Mac أو Windows أو الهاتف. اختر العلم السعودي لتختار الترجمة العربية. مجاني بالكامل، مفتوح المصدر، بلا إعلانات ولا اشتراكات.</p>

## Gizlilik

- Altyazı okuma (yazı tanıma) ve ücretsiz çeviri cihazınızda yapılır.
- Gemini, DeepL gibi bir çeviri hizmeti seçerseniz yalnızca altyazı metni, **sizin anahtarınızla** o hizmete gider.
- **Ortak havuz:** Hazır pakette bulunmayan İngilizce altyazı satırları (yalnız metin, adsız) yeni oyun paketleri hazırlamak için Nino'nun kendi havuzuna gönderilir. Ayarlar'dan kapatabilirsiniz; kapatınca bekleyen satırlar da silinir.
- Nino hesap açtırmaz, reklam göstermez, sizi izlemez. Ayrıntılar: [PRIVACY.md](PRIVACY.md).

## Sık sorulanlar

**PS5'im yok, önce görmek istiyorum.** Android telefonda ana ekrandaki **"PS5'siz Deneyin"**e dokunun; örnek altyazılarla uygulamayı gezebilirsiniz.

**Xbox'ta da ikinci hesap gerekiyor mu?** Hayır. Xbox'ta kendi Microsoft hesabınızla giriş yapmanız yeter.

**Neden ikinci bir PSN hesabı gerekiyor?** Remote Play, PS5'e bağlanmak için bir hesap ister. Kendi hesabınızla oyun oynarken aynı anda o hesapla Remote Play açılamaz; ikinci (ücretsiz) hesap bunu çözer.

**Ekranda sürekli "Uzaktan Oynama" bildirimi çıkıyor.** PS5'te ikinci hesapla **Ayarlar › Sistem › Uzaktan Oynama**'ya gidip en alttaki **Uzaktan Oynama Bağlantı Durumunu Gizle**'yi açın.

**Altyazı İngilizcenin tam üstüne gelmiyor.** Nino ilk birkaç altyazıda oyunun altyazı yerini öğrenir. Sorun sürerse Ayarlar › Altyazı'dan yerleşimi değiştirin.

**Dublajda yanlış ses çıkıyor.** Oyunun ses ayarlarında konuşma sesini kısın ama tamamen kapatmayın; Nino kimin konuştuğunu o sesten anlar.

**TV'ye uygulamayı nasıl kurarım?** En kolayı Android telefondaki Nino'da **Profil › Nino'yu TV'ye Kur** (Android TV, Samsung, LG). Bilgisayardaki Nino da kendisi kurar. Elle kurmak için TV'deki Downloader'ın **Ana Sayfa**'sına `https://is.gd/ninotvapk` yazın. Adım adım: [Kurulum Rehberi › TV](docs/KURULUM.md#5-tv-uygulamasını-kurma).

**Samsung ya da LG akıllı monitörüm var, olur mu?** Samsung akıllı monitörler (M serisi, 2016 sonrası) Samsung TV gibi çalışır. Akıllı olmayan monitörde altyazıyı telefonda ya da bilgisayar ekranında gösterin.

**Altyazının siyah kutusunu kaldırabilir miyim? Yazı tipini değiştirebilir miyim?** Evet: **Ayarlar › Altyazı görünümü**'nde arka planı %0 yapın ve **Yazı tipi**'nden Aksiyon (GTA tarzı), Modern, Yuvarlak ya da Sade'yi seçin.

**OBS ile yayın yapıyorum, iki altyazı çıkıyor.** Windows'ta kartı doğrudan OBS'e bağlayın ve Nino'da görüntü kaynağı olarak OBS projektörünü seçin: [Kurulum Rehberi › Yayıncılar](docs/KURULUM.md#7-yayıncılar-için-obs-ile-windows).

**Takıldım, kime sorarım?** Uygulamada Ayarlar'daki **Sorun Bildir**'den açıklama ve ekran görüntüsüyle bize yazın.

## Kaynak koddan derleme

Mac ve iPhone uygulamaları Swift/SwiftUI, Android uygulaması Kotlin/Jetpack Compose ile yazılmıştır; Remote Play bağlantısı için [chiaki-ng](https://github.com/streetpea/chiaki-ng)'nin kütüphanesi kullanılır.

```bash
git submodule update --init --recursive
./scripts/build-chiaki-macos.sh        # libchiaki (Remote Play)
cd mac && xcodegen generate && xcodebuild -scheme CouchSubs -configuration Release build
```

TV uygulaması: `tv-android` (Android TV), `tv-webos` (LG ve paylaşılan TV sayfası), `tv-tizen` (Samsung).
Windows uygulaması: `windows` (.NET/WPF). Android telefon uygulaması: `couchsubs-android`. Ayrıntılar CouchSubs'ın [orijinal README'sinde](docs/README-CouchSubs.md).

## Lisans ve teşekkür

Nino, **GNU AGPL-3.0** lisansıyla yayımlanan ücretsiz ve açık kaynak bir yazılımdır. Ayrıntılar: [LICENSE](LICENSE), [NOTICE](NOTICE).

**Nino © 2026 Yunus Demirbağ.** Based on [CouchSubs](https://github.com/yorulmazsinan/couchsubs) by Sinan Yorulmaz, modified by Yunus Demirbağ on 2026-11-16.

Nino şu projelerin üzerine kuruludur:
1. **[Chiaki](https://git.sr.ht/~thestr4ng3r/chiaki)** — Florian Märkl ve katkıda bulunanlar: açık kaynak PlayStation Remote Play istemcisi.
2. **[chiaki-ng](https://github.com/streetpea/chiaki-ng)** — Street Pea ve katkıda bulunanlar: Chiaki'nin bakımı süren devamı.
3. **[CouchSubs](https://github.com/yorulmazsinan/couchsubs)** — Sinan Yorulmaz: Nino'nun kodunun başladığı altyazı okuma ve çeviri uygulaması.
4. **Dublaj sesleri:** Kyutai'nin [pocket-tts](https://github.com/kyutai-labs/pocket-tts)'i ve [Pocket TTS Turkish](https://huggingface.co/wite-tech/pocket-tts-turkish) (wite-tech, CC BY 4.0). Sesler yapaydır, gerçek kişilere ait değildir.
5. **Ücretsiz, internetsiz çeviri:** Windows'ta Helsinki Üniversitesi'nin [OPUS-MT](https://github.com/Helsinki-NLP/Opus-MT) İngilizce→Türkçe modeli (CC BY 4.0); Mac ve iPhone'da Apple'ın, Android'de Google ML Kit'in cihaz içi çevirisi.
6. **Yazı tanıma:** Apple Vision (Mac, iPhone), Windows OCR ve Google ML Kit (Android).
7. **Bilgisayarda yapay zekâ ile çeviri (isteğe bağlı):** [Ollama](https://ollama.com), Google'ın [TranslateGemma](https://ollama.com/library/translategemma)'sı ve Xiaomi'nin [MiLMMT](https://huggingface.co/xiaomi-research/MiLMMT-46-4B-v1.0)'si.
8. **Çevrimiçi çeviri (isteğe bağlı, kendi anahtarınızla):** Google Gemini, DeepL, OpenAI, Claude.
9. **Xbox:** UnknownSKL'nin [Greenlight](https://github.com/unknownskl/greenlight)'ı ve [xal-node](https://github.com/unknownskl/xal-node)'u (MIT; akış onlardan öğrenildi, kod Kotlin'de yeniden yazıldı) ve Google'ın [WebRTC](https://webrtc.org)'si (BSD-3).
10. **Diğer açık kaynak parçalar:** FFmpeg, OpenSSL, curl, nanopb, Jerasure, GF-Complete, json-c, libevent, miniupnpc, ONNX Runtime, Velopack (Windows kurulumu ve güncelleme), SSH.NET ve Patrick Stel'in [tizen-sdb](https://github.com/PatrickSt1991/tizen-sdb)'si (LG ve Samsung TV kurulumu). Tam liste: [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Bu projelerin geliştiricilerine çok teşekkürler. Nino onların emeği olmadan olmazdı. 🙏

Geliştiren: **Yunus Demirbağ** · Destekleyenler: **M. Akif Demirbağ**

*Nino, Sony Interactive Entertainment ve Microsoft ile bağlantılı değildir. PlayStation ve PS5, Sony Interactive Entertainment Inc.'in; Xbox, Microsoft Corporation'ın ticari markalarıdır.*

---

### English

**Nino** translates the English subtitles of PS5 and Xbox games into Turkish (or Arabic) in real time and shows them on your TV, right on top of the game, or on your phone. An Android phone (or a Mac, a Windows PC, or an iPhone) watches the game through Remote Play (with a second, free PSN account), reads the subtitles, translates them and sends them to the Nino app on the TV. On Xbox (experimental) the Android app signs in with your Microsoft account and watches the Xbox home stream; Mac and Windows read the Xbox window. Free, open source (AGPL-3.0), no ads, no subscriptions. Based on CouchSubs by Sinan Yorulmaz.
