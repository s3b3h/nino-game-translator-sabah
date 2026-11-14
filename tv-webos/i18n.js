// SPDX-License-Identifier: AGPL-3.0-only
// TV uygulamasının metinleri. Dil TV'nin diline göre seçilir; Türkçe değilse İngilizce.
(function () {
  'use strict';

  var TEXTS = {
    tr: {
      waiting: 'Mac\'inizde, Windows bilgisayarınızda ya da Android telefonunuzda Nino\'yu açın.',
      waitingHint: 'Nino bu TV\'yi kendisi bulur, altyazılar buraya gelir.',
      step1: 'Mac, Windows Ya Da Android Telefonda Nino\'yu Açın',
      step2: 'Aynı Wi-Fi Ağında Olun',
      step3: 'Gerisini Nino Halleder',
      waitingStatus: 'Bağlantı Bekleniyor',
      demoArrow: 'Altyazılar Oyunda Böyle Görünür',
      panelTitle: 'Nino',
      panelTag: 'Game Translator · PS5 altyazıları Türkçe',
      heroOk: 'Çeviri hazır',
      previewEmpty: 'Altyazı bekleniyor',
      heroWait: 'Bilgisayar bekleniyor',
      heroBad: 'Bağlantı koptu',
      previewLabel: 'Son altyazı · TV\'de böyle görünüyor',
      rOk: 'Bu paneli aç / kapat',
      rLR: 'HDMI girişini değiştir',
      rUD: 'Altyazıyı yukarı / aşağı taşı',
      rNum: '1–4 giriş seç · 0 PS5\'i bul',
      rRed: 'Deneme altyazısı',
      rGreen: 'Panel',
      rBlue: 'Demo',
      hdmi: 'HDMI',
      lastSubtitle: 'Son altyazı',
      diagnostics: 'Tanı',
      server: 'Uygulama',
      connection: 'Bağlantı',
      loading: '(yükleniyor)',
      videoReady: '(görüntü geldi)',
      playing: '(oynatılıyor)',
      inputError: '(giriş açılamadı)',
      sourceError: '(bu kaynak desteklenmiyor)',
      auto: 'otomatik',
      consoleNotFound: 'PS5 bulunamadı',
      noEventSource: 'Bu TV desteklenmiyor (EventSource yok)',
      connecting: 'bağlanıyor…',
      connected: 'bağlı',
      reconnecting: 'bağlantı koptu, yeniden deneniyor…',
      none: '—',
      keys: 'OK: bu panel · ◀ ▶: HDMI girişi · 1–4: HDMI girişi · 0: PS5\'i otomatik bul · ▲ ▼: altyazıyı taşı · Kırmızı: deneme altyazısı · Mavi: demo · Yeşil: bu panel',
      localTest: 'Deneme: bu yazıyı oyunun üstünde görüyor musunuz?',
      positionPreview: 'Altyazı burada görünecek',
      demoButton: 'Demoyu izle',
      demoBadge: 'ÖRNEK',
      demoHint: 'Oyundaki İngilizce altyazı burada Türkçe görünür. Çıkmak için Geri\'ye basın.',
      sourceSwitchTitle: 'TV kendi kendine HDMI\'ya geçti.',
      sourceSwitchHint: 'Ayarlar › Tüm Ayarlar › Bağlantı › Harici Cihaz Yöneticisi\'nden Anynet+ (HDMI-CEC) ve Otomatik Kaynak Değiştirme\'yi kapatın.',
      sourceSwitchClose: 'Kapatmak için Tamam\'a ya da Geri\'ye basın.'
    },
    en: {
      waiting: 'Open Nino on your Mac, Windows PC or Android phone.',
      waitingHint: 'The app will find this TV and send subtitles here.',
      step1: 'Open Nino On A Mac, Windows PC Or Android Phone',
      step2: 'Be On The Same Wi-Fi',
      step3: 'Nino Does The Rest',
      waitingStatus: 'Waiting For Connection',
      demoArrow: 'This Is How Subtitles Look In The Game',
      panelTitle: 'Nino',
      panelTag: 'Game Translator · subtitles, translated',
      heroOk: 'Ready to translate',
      previewEmpty: 'Waiting for subtitles',
      heroWait: 'Waiting for the computer',
      heroBad: 'Connection lost',
      previewLabel: 'Last subtitle · as shown on TV',
      rOk: 'Open / close this panel',
      rLR: 'Change HDMI input',
      rUD: 'Move subtitles up / down',
      rNum: '1–4 pick input · 0 find PS5',
      rRed: 'Test subtitle',
      rGreen: 'Panel',
      rBlue: 'Demo',
      hdmi: 'HDMI',
      lastSubtitle: 'Last subtitle',
      diagnostics: 'Diagnostics',
      server: 'App',
      connection: 'Connection',
      loading: '(loading)',
      videoReady: '(picture received)',
      playing: '(playing)',
      inputError: '(error: input could not be opened)',
      sourceError: '(error: source not supported)',
      auto: 'automatic',
      consoleNotFound: 'console not found',
      noEventSource: 'This TV is not supported (no EventSource)',
      connecting: 'connecting…',
      connected: 'connected',
      reconnecting: 'disconnected, retrying…',
      none: '—',
      keys: 'OK: this panel · ◀▶: HDMI input (panel open) · 1–4: HDMI input · 0: find console automatically · ▲▼: move subtitles up/down · Red: test subtitle · Blue: demo · Green: this panel',
      localTest: 'Test: is this text shown on top of the game?',
      positionPreview: 'Subtitles will appear here',
      demoButton: 'Watch the demo',
      demoBadge: 'DEMO',
      demoHint: 'Example: the game\'s English subtitles appear here in Turkish. Press Back to exit.',
      sourceSwitchTitle: 'The TV switched to HDMI by itself.',
      sourceSwitchHint: 'Turn off Anynet+ (HDMI-CEC) and Auto Source Switching in Settings › All Settings › Connection › External Device Manager.',
      sourceSwitchClose: 'Press OK or Back to close.'
    }
  };

  var lang = (navigator.language || 'en').toLowerCase().indexOf('tr') === 0 ? 'tr' : 'en';

  window.t = function (key) {
    return (TEXTS[lang] && TEXTS[lang][key]) || TEXTS.en[key] || key;
  };

  // data-i18n niteliği taşıyan öğelerin metnini doldurur.
  window.applyI18n = function () {
    var nodes = document.querySelectorAll('[data-i18n]');
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].textContent = window.t(nodes[i].getAttribute('data-i18n'));
    }
  };
})();
