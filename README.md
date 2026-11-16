<p align="center"><img src="docs/nino/afis.jpg" width="420" alt="Nino Game Translator: PS5 oyunlarına Türkçe altyazı"></p>

<h1 align="center">Nino Game Translator</h1>

<p align="center"><b>Türkçe desteği olmayan PS5 oyunlarını Türkçe oynayın.</b><br>
Oyundaki İngilizce altyazıyı anlık olarak Türkçeye (ya da Arapçaya) çevirir ve TV'de, oyunun tam üstünde gösterir.<br>
Tamamen ücretsiz · açık kaynak · reklamsız · abonelik yok · hesap yok</p>

<p align="center">
  <a href="https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Mac.zip"><b>⬇️ Mac</b></a> &nbsp;·&nbsp;
  <a href="https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Windows-Setup.exe"><b>⬇️ Windows</b></a> &nbsp;·&nbsp;
  <b>📺 TV: Downloader'a <code>is.gd/ninoapk</code> yazın</b><br>
  <a href="https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Telefon.apk">⬇️ Android telefon</a> &nbsp;·&nbsp;
  📱 iPhone: App Store incelemesinde &nbsp;·&nbsp;
  <a href="docs/KURULUM.md"><b>📘 Kurulum Rehberi</b></a>
</p>

<p align="center">
  <img src="docs/nino/mac-salon.png" width="440" alt="Nino Mac: Salon ana ekranı, TV'de Türkçe altyazı">&nbsp;
  <img src="docs/nino/mac-cam-dugme.png" width="440" alt="Nino Mac: Cam düğme ana ekranı">
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
- **Bilgisayarınız yoksa ya da monitörde oynuyorsanız:** **Android telefon** (yakında iPhone) aynı işi yapar; altyazıyı TV'ye gönderir ya da kendi ekranında gösterir.

## 0.1.7'de yenilikler

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
| **Konsol** | PS5 (Remote Play açık) |
| **Bilgisayar** | Apple Silicon (M1 ve sonrası) Mac, macOS 13+ · ya da Windows 10/11 (64 bit). Bilgisayar yoksa Android 8+ telefon. |
| **TV** | Android TV / Google TV (denendi). LG ve Samsung deneysel. |
| **PSN** | İkinci, ücretsiz bir PSN hesabı (Remote Play için; oyun sizin hesabınızda oynanır). Capture Card ile gerekmez. |
| **Ağ** | PS5, bilgisayar/telefon ve TV aynı Wi-Fi'de |

## Kurulum

Adım adım anlatım: **[📘 Kurulum Rehberi](docs/KURULUM.md)**

**Mac:** [`Nino-Mac.zip`](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Mac.zip)'i indirin, Nino'yu **Uygulamalar**'a sürükleyin ve açın ("doğrulanamadı" derse **Sistem Ayarları › Gizlilik ve Güvenlik › Yine de Aç**). Nino adım adım yol gösterir: ikinci PSN hesabıyla giriş, PS5'i 8 haneli kodla eşleme, TV seçimi. TV'de USB hata ayıklama açıksa TV uygulamasını da Mac kurar.

**Windows:** [`Nino-Windows-Setup.exe`](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Windows-Setup.exe)'yi çalıştırın ("bilgisayarınızı korudu" derse **Ek bilgi › Yine de çalıştır**). Kurulum Mac ile aynıdır.

**TV (Android TV / Google TV):** Google Play'den **Downloader**'ı kurun, `is.gd/ninoapk` yazıp inen dosyayı kurun.

**Android telefon (bilgisayar yerine):** [`Nino-Telefon.apk`](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Telefon.apk)'yı telefonda indirip kurun, ikinci PSN hesabıyla **Sony İle Giriş Yapın**, PS5'teki 8 haneli kodu yazın ve oyunu açınca **kaydırın**.

## Telefon uygulaması

<p align="center">
  <img src="docs/nino/tanitim/tr1.jpg" width="190" alt="PS5 oyunlarına anında Türkçe altyazı">&nbsp;
  <img src="docs/nino/tanitim/tr2.jpg" width="190" alt="Kaydırın, altyazılar aksın">&nbsp;
  <img src="docs/nino/tanitim/tr3.jpg" width="190" alt="Hazır paketlerle beklemeden">&nbsp;
  <img src="docs/nino/tanitim/tr4.jpg" width="190" alt="TV'de ya da telefonunuzda">
</p>

<p align="center">
  <img src="docs/nino/v017/android-karsilama-1.jpg" width="150" alt="Karşılama">&nbsp;
  <img src="docs/nino/v017/android-psn.jpg" width="150" alt="İkinci PSN hesabı">&nbsp;
  <img src="docs/nino/v017/android-cikis.jpg" width="150" alt="Altyazılar nerede görünsün">&nbsp;
  <img src="docs/nino/v017/android-ana-ekran.jpg" width="150" alt="Ana ekran">&nbsp;
  <img src="docs/nino/v017/android-canli.jpg" width="150" alt="Canlı çeviri">
</p>

## العربية · Arapça

<p align="center">
  <img src="docs/nino/tanitim/ar1.jpg" width="200" alt="ترجمة عربية فورية لألعاب PS5">&nbsp;
  <img src="docs/nino/tanitim/ar2.jpg" width="200" alt="اسحب لتبدأ الترجمة">&nbsp;
  <img src="docs/nino/v017/android-arapca-canli.jpg" width="200" alt="الواجهة العربية">
</p>

<p dir="rtl" align="right"><b>نينو</b> يقرأ الترجمة الإنجليزية في ألعاب PS5 ويعرضها مترجمة إلى العربية فورًا فوق اللعبة على التلفاز، عبر تطبيق Mac أو Windows أو الهاتف. اختر العلم السعودي لتختار الترجمة العربية. مجاني بالكامل، مفتوح المصدر، بلا إعلانات ولا اشتراكات.</p>

## Gizlilik

- Altyazı okuma (yazı tanıma) ve ücretsiz çeviri cihazınızda yapılır.
- Gemini, DeepL gibi bir çeviri hizmeti seçerseniz yalnızca altyazı metni, **sizin anahtarınızla** o hizmete gider.
- **Ortak havuz:** Hazır pakette bulunmayan İngilizce altyazı satırları (yalnız metin, adsız) yeni oyun paketleri hazırlamak için Nino'nun kendi havuzuna gönderilir. Ayarlar'dan kapatabilirsiniz; kapatınca bekleyen satırlar da silinir.
- Nino hesap açtırmaz, reklam göstermez, sizi izlemez. Ayrıntılar: [PRIVACY.md](PRIVACY.md).

## Sık sorulanlar

**PS5'im yok, önce görmek istiyorum.** Android telefonda ana ekrandaki **"PS5'siz Deneyin"**e dokunun; örnek altyazılarla uygulamayı gezebilirsiniz.

**Neden ikinci bir PSN hesabı gerekiyor?** Remote Play, PS5'e bağlanmak için bir hesap ister. Kendi hesabınızla oyun oynarken aynı anda o hesapla Remote Play açılamaz; ikinci (ücretsiz) hesap bunu çözer.

**Ekranda sürekli "Uzaktan Oynama" bildirimi çıkıyor.** PS5'te **Ayarlar › Sistem › Uzaktan Oynama**'ya gidip en alttaki seçeneği kapatın.

**Altyazı İngilizcenin tam üstüne gelmiyor.** Nino ilk birkaç altyazıda oyunun altyazı yerini öğrenir. Sorun sürerse Ayarlar › Altyazı'dan yerleşimi değiştirin.

**Dublajda yanlış ses çıkıyor.** Oyunun ses ayarlarında konuşma sesini kısın ama tamamen kapatmayın; Nino kimin konuştuğunu o sesten anlar.

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
9. **Diğer açık kaynak parçalar:** FFmpeg, OpenSSL, curl, nanopb, Jerasure, GF-Complete, json-c, libevent, miniupnpc, ONNX Runtime, Velopack (Windows kurulumu ve güncelleme), SSH.NET ve Patrick Stel'in [tizen-sdb](https://github.com/PatrickSt1991/tizen-sdb)'si (LG ve Samsung TV kurulumu). Tam liste: [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Bu projelerin geliştiricilerine çok teşekkürler. Nino onların emeği olmadan olmazdı. 🙏

Geliştiren: **Yunus Demirbağ** · Destekleyenler: **M. Akif Demirbağ**

*Nino, Sony Interactive Entertainment ile bağlantılı değildir. PlayStation ve PS5, Sony Interactive Entertainment Inc.'in ticari markalarıdır.*

---

### English

**Nino** translates the English subtitles of PS5 games into Turkish (or Arabic) in real time and shows them on your TV, right on top of the game, or on your phone. An Android phone (or a Mac, a Windows PC, or an iPhone) watches the game through Remote Play (with a second, free PSN account), reads the subtitles, translates them and sends them to the Nino app on the TV. Free, open source (AGPL-3.0), no ads, no subscriptions. Based on CouchSubs by Sinan Yorulmaz.
