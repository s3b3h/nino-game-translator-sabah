# Nino Gizlilik Politikası / Privacy Policy

*Son güncelleme / Last updated: 2026-11-16*

Bu politika **Nino Game Translator** (Nino) uygulamalarını kapsar: Android telefon (`com.ninotranslator.mobile`),
iPhone, Mac, Windows ve TV uygulamaları. Nino ücretsiz ve açık kaynaklıdır (AGPL-3.0); CouchSubs'tan türetilmiştir.
İletişim: [GitHub › Issues](https://github.com/yunusdemirbag/nino-game-translator/issues).

## Türkçe

**Kısaca:** Nino hesap açtırmaz, reklam göstermez, sizi izlemez, kişisel verinizi satmaz ya da paylaşmaz.

**Cihazınızda kalanlar**

- PS5'ten ya da Xbox'tan (Remote Play, Xbox ev yayını ya da Capture Card ile) gelen oyun görüntüsü yalnız altyazıyı okumak için bellekte işlenir;
  kaydedilmez, hiçbir yere gönderilmez.
- Yazı tanıma ve ücretsiz çeviri cihazınızda yapılır. Çeviriler yalnız sizin ekranınızda ya da ev ağınızdaki TV'de
  gösterilir.
- PlayStation Network hesap kimliği (sayısal) ve PS5/TV eşleme anahtarları yalnız cihazınızda saklanır.
- Capture Card kullanırsanız kamera izni yalnız kartın görüntüsünü okumak için istenir.

**Dışarıyla kurulan bağlantılar**

- **Sony:** PlayStation Network girişi doğrudan Sony'nin kendi sayfasında yapılır. Şifrenizi Nino görmez ve saklamaz.
- **Microsoft (yalnız Xbox kullanırsanız):** Giriş, Microsoft'un kendi sayfasında (microsoft.com/link) kodla yapılır;
  şifrenizi Nino görmez. Xbox'ın ev yayınını açmak için Microsoft ve Xbox Live sunucularıyla konuşulur. Oturum jetonu
  yalnız cihazınızda şifreli saklanır; görüntü ev ağınızda doğrudan Xbox'tan gelir ve kaydedilmez.
- **Ev ağı:** PS5'i ve TV'yi bulmak ve onlara bağlanmak için yalnız yerel ağ kullanılır.
- **Çeviri modeli ve oyun paketleri:** Ücretsiz çeviri modeli ve hazır oyun çeviri paketleri internetten indirilir;
  bu indirmelerde sizinle ilgili bir bilgi gönderilmez.
- **Seçtiğiniz çeviri hizmeti (isteğe bağlı):** Ayarlarda kendi anahtarınızla DeepL, Google Gemini, OpenAI ya da
  Anthropic seçerseniz okunan İngilizce altyazı metni çeviri için o hizmete gider. Görüntü, ses ya da hesap bilgisi
  gitmez. Anahtarınız yalnız cihazınızda kalır. Bu hizmetlerin kendi gizlilik koşulları geçerlidir.
- **Ortak havuz (isteğe bağlı, Ayarlar'dan kapatılabilir):** Hiçbir hazır pakette olmayan İngilizce altyazı satırları,
  yeni oyun paketleri hazırlamak için Nino'nun havuz sunucusuna (Cloudflare Workers) şifreli bağlantıyla gönderilir.
  Giden yalnız: satırın metni, hangi oyuna yakın olduğu, kaç kez görüldüğü, rastgele üretilmiş bir kurulum kimliği,
  uygulama sürümü ve işletim sistemi. Ad, e-posta, PSN bilgisi, görüntü ya da ses gönderilmez. Sunucu IP adresini
  kaydetmez. Kapatınca gönderim durur ve bekleyen satırlar silinir.
- **Çeviri havuzu ve oyun tanıma (V3.2'den beri, ortak havuz açıkken):** Havuzdaki İngilizce satırlar, herkese aynı
  çeviriyi verebilmek için sunucumuzda yapay zekâ çeviri hizmetine (Anthropic, Claude) gönderilip çevrilir; çeviri
  havuzda saklanır. Oynadığınız oyunu anlamak için Remote Play görüntüsünden küçük bir kare (yaklaşık 768 piksel
  genişlik) arada bir aynı hizmete gönderilir; kare saklanmaz, yalnız oyunun adı kurulum kimliğinize yazılır. Ortak
  havuzu kapatınca ikisi de durur.

**Olmayanlar:** Reklam, reklam kimliği, analiz ya da izleme kodu, hesap sistemi, uygulama içi satın alma yoktur.
Nino 13 yaş altındaki çocuklara yönelik değildir ve bilerek onlardan veri toplamaz.

**Verilerinizin silinmesi:** Nino'da hesap olmadığı için silinecek bir hesap yoktur. Uygulamayı kaldırdığınızda
cihazdaki her şey silinir. Havuza giden satırlar kişiyle ilişkilendirilemez; yine de kurulum kimliğinize bağlı
satırların silinmesini GitHub › Issues üzerinden isteyebilirsiniz.

**Değişiklikler:** Bu politika değişirse bu sayfa ve üstteki tarih güncellenir.

## English

**In short:** Nino needs no account, shows no ads, does not track you, and does not sell or share your personal data.

**Stays on your device:** The PS5 or Xbox picture (from Remote Play, the Xbox home stream or a capture card) is processed in memory only to read
the subtitles; it is never stored or sent anywhere. Text recognition and the free translation run on your device.
Your numeric PSN account ID and PS5/TV pairing keys are stored only on your device. Camera permission is requested
only to read a capture card's picture.

**External connections:**

- **Sony:** PSN sign-in happens on Sony's own page. Nino never sees or stores your password.
- **Microsoft (only if you use Xbox):** sign-in happens on Microsoft's own page (microsoft.com/link) with a code; Nino
  never sees your password. Nino talks to Microsoft and Xbox Live servers to start the Xbox home stream. The session
  token is stored encrypted only on your device; the picture comes directly from your Xbox over your home network and
  is not stored.
- **Home network:** used only to find and connect to your PS5 and TV.
- **Translation model and game packs** are downloaded without sending any information about you.
- **Translation service you choose (optional):** if you enter your own DeepL, Google Gemini, OpenAI or Anthropic key,
  the English subtitle text is sent to that service for translation. No picture, audio or account data is sent. Your
  key stays on your device. That service's own privacy terms apply.
- **Shared pool (optional, can be turned off in Settings):** English subtitle lines that are not in any game pack are
  sent over an encrypted connection to Nino's pool server (Cloudflare Workers) to build new game packs. Only the line
  text, the nearest game pack, how often it was seen, a random installation ID, the app version and the operating
  system are sent. No name, email, PSN data, picture or audio. The server does not log IP addresses. Turning it off
  stops sending and deletes pending lines.
- **Translation pool and game recognition (since V3.2, while the shared pool is on):** pool lines are translated on
  our server by an AI translation service (Anthropic, Claude) so everyone gets the same translation; the translation is
  stored in the pool. To tell which game you play, a small frame of the Remote Play picture (about 768 px wide) is sent
  to the same service now and then; the frame is not stored, only the game's name is saved with your installation ID.
  Turning the shared pool off stops both.

**Not included:** ads, advertising IDs, analytics or tracking code, accounts, in-app purchases. Nino is not directed
at children under 13 and does not knowingly collect their data.

**Deletion:** There is no account to delete; uninstalling the app removes all data on the device. Pool lines cannot
be linked to a person; you may still request deletion of lines tied to your installation ID via GitHub Issues.

**Changes:** If this policy changes, this page and the date above are updated.
