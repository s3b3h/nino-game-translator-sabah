<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# Nino yardımcısının ek bilgileri

Bu dosya, kurulum rehberinde (aşağıda tam metni var) yazmayan ama kullanıcıların sık sorduğu konuları anlatır.
Kurulum rehberiyle çelişirse kurulum rehberi doğrudur.

## Nino nedir
- Nino Game Translator: PS5 ve Xbox oyunlarındaki İngilizce altyazıyı anlık okuyup seçilen dile çevirir ve TV'de oyunun
  tam üstünde (ya da telefonda / bilgisayar ekranında) gösterir. Tamamen ücretsiz, açık kaynak (AGPL-3.0), reklamsız,
  abonelik ve hesap yok. CouchSubs (Sinan Yorulmaz) projesi temel alınarak geliştirildi.
- İndirme ve kaynak kod: https://github.com/yunusdemirbag/nino-game-translator
- Nino'yu çalıştıran cihaz: Mac (Apple Silicon, macOS 13+), Windows 10/11 64 bit, Android telefon (Android 8+).
  iPhone uygulaması App Store incelemesinde; Android uygulaması Google Play'de kapalı testte. O zamana kadar Android'de
  APK ile kurulur.
- Oyun her zamanki gibi TV'de, kendi kolunuzla, kendi hesabınızla oynanır. Nino görüntüyü yalnız okur.

## Nasıl çalışır (kısa)
- PS5: Nino, ikinci (ücretsiz) bir PSN hesabıyla PS5'e Remote Play bağlantısı açar ve altyazıyı bu görüntüden okur.
  Oyun ana hesapta oynanır. İkinci hesap gerekir çünkü PS5 aynı hesapla hem oynamaya hem Remote Play'e izin vermez.
- Xbox: Android telefonda Microsoft hesabıyla (ikinci hesap gerekmez) Xbox'ın ev yayını izlenir. Mac'te Greenlight ya da
  tarayıcıda xbox.com/play penceresi, Windows'ta Xbox uygulamasındaki "Uzaktan oynat" penceresi okunur.
- Capture card: konsol görüntüsü HDMI kartla bilgisayara gelir; Remote Play ve ikinci hesap gerekmez. PS5'te kart
  kullanırken PS5'in Ayarlar › Sistem › HDMI › "HDCP'yi Etkinleştir" kapalı olmalıdır, yoksa görüntü siyah gelir.
- Çeviri bilgisayarda/telefonda yapılır; TV uygulaması yalnız altyazıyı gösterir. Altyazının TV'de görünmesi için TV'de
  Nino TV uygulaması olmalıdır.

## Hangi TV / monitör olur
- Android TV / Google TV (TCL, iFFALCON, Sony, Philips, Xiaomi, Hisense, Vestel, Arçelik, Beko, Grundig…): en çok
  denenen, önerilen.
- Samsung TV ve Samsung akıllı monitörler (M serisi, Smart Monitor; Tizen, 2016 ve sonrası): Samsung TV Android TV
  DEĞİLDİR, Tizen kullanır; Nino TV uygulaması telefondan ya da bilgisayardan geliştirici moduyla kurulur
  (rehberde Bölüm 5.1). 2016–2018 modelleri deneysel.
- LG (webOS): deneysel; LG geliştirici hesabı ve Developer Mode uygulaması gerekir.
- Akıllı olmayan monitör ya da eski TV: TV uygulaması kurulamaz. Altyazıyı telefon ekranında (telefonu ekranın yanına
  koyun) ya da bilgisayar ekranında gösterin. Bilgisayar monitöre bağlıysa Nino altyazıyı oyun görüntüsünün üstünde
  bilgisayar ekranında gösterebilir (Remote Play penceresi ya da capture card ile).
- TV kutuları (Fire TV, Chromecast, Android TV kutusu): denenmedi. Altyazının oyunun üstünde görünmesi için konsolun
  görüntüsünün o cihazın ekranında olması gerekir; emin değilseniz altyazıyı telefonda gösterin.
- Apple TV, Roku, Nintendo Switch, Steam Deck, PS4 desteklenmez.

## Sık sorunlar ve çözümleri
- TV'de altyazı çıkmıyor: TV'de Nino uygulaması açık mı? Bilgisayar/telefon ve TV aynı Wi-Fi'da mı? Bilgisayarda Nino'nun
  yalnız bir kopyası açık olmalı. Oyunun kendi İngilizce altyazısı açık olmalı (Nino onu okur).
- TCL ve bazı TV'lerde "PS5 görüntüsü Nino'nun içinde gelmiyor": TV'de "Diğer uygulamaların üzerinde göster" iznini
  Nino'ya verin (Ayarlar › Uygulamalar › Özel uygulama erişimi). Telefondan/bilgisayardan kurulumda Nino bunu kendisi verir.
- Xbox'ta uzaktan oynatırken TV'nin sesi kesiliyor: bu Xbox'ın kendi davranışıdır (uzaktan oynatmada sesi o cihaza
  verir). Çözümler: sesi telefondan/bilgisayardan dinleyin (kulaklık ya da soundbar), ya da capture card kullanın
  (konsolun sesi TV'de kalır). Android telefonda Xbox sesi ayarı vardır.
- PS5 ekranında sürekli "Uzaktan Oynama bağlandı" bildirimi: ikinci hesapla Ayarlar › Sistem › Uzaktan Oynama'da
  "Uzaktan Oynama Bağlantı Durumunu Gizle"yi açın.
- OBS'te iki altyazı: kartı doğrudan OBS'e ekleyin, Nino'da görüntü kaynağını OBS projektörü yapın, altyazıyı yalnız
  OBS tarayıcı kaynağıyla (Nino'nun OBS adresi) ekleyin (rehberde Bölüm 7). Bu yol şimdilik Windows'ta.
- Nino'dan geçen oyun sesi bozuk/kalitesiz (capture card ile bilgisayarda oynarken): sesi kartın kendi yolundan (OBS
  ya da TV'den) alın; yayın yapıyorsanız OBS yolunu kullanın.
- TV'ye kurulumda en kolayı telefondaki ya da bilgisayardaki Nino'dur; TV'de geliştirici modu (USB hata ayıklama)
  açıkken uygulamayı kendisi kurar ve günceller.
- Güncel sürüm: Mac, Windows, Android telefon ve iPhone uygulamaları Nino V3.3 (teknik numara 0.2.3); TV uygulaması
  Nino V3.2 (0.9.31). TV'deki sürümü görmek için TV'de Nino'yu açıp kumandada OK'e (ya da menü tuşuna) bas;
  açılan panelin üstünde "V3.2 (0.9.31)" yazar. V3.2 yazmıyorsa (ör. yalnız 0.9.22 gibi bir sayı) TV uygulaması eskidir: telefondaki ya da bilgisayardaki Nino'da "TV'ye kur"a yeniden bas. Geliştirici modu
  (USB hata ayıklama) açık kalırsa güncellemeyi Nino bundan sonra kendisi yapar; bu yüzden kurulumu hep bu yolla öner.
- Üçüncü parti indirme uygulamaları (ör. "Downloader") önerilmez.
- iPhone ve iPad: App Store'da yayınlanana kadar TestFlight ile kurulur. Önce App Store'dan ücretsiz TestFlight
  uygulamasını indir, sonra bu bağlantıyı aç: https://testflight.apple.com/join/1K3Q1KXp
- Çeviri havuzu: herkesin oyunda gördüğü İngilizce satırlar sunucuda toplanır, bir kez yüksek kaliteli yapay zekâyla
  Türkçeye çevrilir ve aynı satırı gören herkese anında gider (şimdilik GTA 6 için). Küfür ve argo sansürsüz, oyundaki
  sertlikte çevrilir. Oyunu Nino kendisi tanır (ekrandan ve altyazılardan); kullanıcının seçmesi gerekmez.
- GTA 6'da çeviri (V3.3'ten beri) her zaman Nino'nun çeviri havuzundan gelir; kullanıcının Gemini, DeepL, ChatGPT ya da
  başka anahtarı bu oyunda kullanılmaz, masraf olmaz. Sunucuya ulaşılamazsa cihazın ücretsiz çevirisi gösterilir. Eski
  sürümde (V3.2 ve öncesi) önce kendi motoru çevirir; V3.3'e güncellemek gerekir.
- iPhone'da ekran kapanıyor, bir süre sonra bağlantı kopuyor: iOS, kilitlenen ya da arka plana geçen uygulamayı
  durdurur; bu Apple'ın kuralıdır, hiçbir uygulama aşamaz. Çeviri sürerken Nino ekranı kendisi açık tutar ve
  parlaklığı kısar. Telefonu kilitlemeyin, başka uygulamaya geçmeyin; şarja takılı bırakmak en
  iyisi. Ekranın hiç açık kalmasını istemeyenler bilgisayardaki (Mac/Windows) ya da Android telefondaki Nino'yu
  kullanabilir; Android'de Nino arka planda da çalışır.
- Mac "doğrulanamadı" diyor: Sistem Ayarları › Gizlilik ve Güvenlik › Yine de Aç. Windows "bilgisayarınızı korudu":
  Ek bilgi › Yine de çalıştır.
- Mac PS5'i bulamıyor: Sistem Ayarları › Gizlilik ve Güvenlik › Yerel Ağ'da Nino'ya izin verin.
- Çeviri yanlış ya da kalitesiz: Ayarlar › Çeviri'den yapay zekâ çevirisini açın. Gemini'nin ücretsiz anahtarı yeterlidir
  (Google AI Studio'dan alınır). DeepL, ChatGPT, Claude ve bilgisayardaki yerel model de seçilebilir.
- Yazı çok küçük/büyük, siyah kutu istemiyorum, yazı tipi: Ayarlar › Altyazı görünümü (boyut, renk, arka plan %0 ile kutu
  kalkar, yazı tipi: Aksiyon/GTA tarzı varsayılan, Modern, Yuvarlak, Sade).

## Diller
- 11 çeviri dili: Türkçe, Arapça, Hintçe, Endonezce, Tayca, Vietnamca, Urduca, Bengalce, Malayca, Filipince,
  Felemenkçe. Uygulamanın menüleri de seçilen dile geçer.
- Ücretsiz çeviri hangi dili destekler: Mac ve iPhone'da Apple'ın çevirisi (Urduca, Bengalce, Filipince yok; onlar için
  yapay zekâ motoru, Gemini ücretsiz). Android'de Google ML Kit (11 dilin hepsi). Windows'ta Türkçe, Arapça, Hintçe,
  Endonezce, Vietnamca, Felemenkçe ücretsiz; Tayca, Urduca, Bengalce, Malayca, Filipince için yapay zekâ motoru gerekir.
- Hazır oyun çeviri paketleri, terim listesi ve Türkçe dublaj yalnız Türkçede çalışır.

## Gizlilik
- Hesap yok; ayarlar cihazda kalır. Oyun görüntüsü internete gönderilmez. Kendi anahtarınızla seçtiğiniz çeviri
  hizmetine yalnız okunan İngilizce metin gider. Ortak havuz (Ayarlar'dan kapatılabilir) paketlerde olmayan İngilizce
  satırları anonim toplar. Yardımcıya ve Sorun Bildir'e yazdıklarınız sorunu çözmek için Nino'nun sunucusuna gider.
