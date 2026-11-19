// SPDX-License-Identifier: AGPL-3.0-only
// Android TV'ye özgü işler; asıl iş MainActivity.java ve OverlayService.java'dadır. webOS karşılığı: tv-webos/platform.js
(function () {
  'use strict';

  var bridge = window.AndroidTV;
  var hdmiStatus = function () {};
  var relaunch = function () {};
  // Katman modu: sayfa TV'nin kendi HDMI ekranının üstündeki, kumandanın ulaşmadığı şeffaf pencerede çalışır.
  var overlay = !!(bridge.isOverlay && bridge.isOverlay());
  // Nino ana ekranı: "home" (katman izinli; kullanıcı kumandayla PS5 girişine geçer) ya da "permission" (onay gerekiyor).
  var homeMode = bridge.homeMode ? bridge.homeMode() : '';
  var homeStatus = null;
  // Bağlantı bu süre içinde gelmezse katmanda küçük kırmızı nokta görünür.
  var DOT_AFTER_MS = 5000;
  var dot = null;
  var dotTimer = null;

  // Uygulamadan çıkılınca (Ana ekran, başka uygulama) Türkçe dublaj susar, öne gelince yeniden duyulur. Ortak sayfa sesi
  // new Audio(...) ile çalar; burada sarılır ki çalan ve arka plandayken başlayan ses kısılsın. Zamanlama değişmez.
  var NativeAudio = window.Audio;
  var muted = false;
  var lastAudio = null;
  if (NativeAudio) {
    var TrackedAudio = function (url) {
      var audio = url === undefined ? new NativeAudio() : new NativeAudio(url);
      audio.muted = muted;
      lastAudio = audio;
      return audio;
    };
    TrackedAudio.prototype = NativeAudio.prototype;
    window.Audio = TrackedAudio;
  }
  window.__onBackground = function (hidden) {
    muted = !!hidden;
    if (lastAudio) lastAudio.muted = muted;
  };

  window.__onHdmiStatus = function (kind) { hdmiStatus(kind); };
  window.__onRelaunch = function (raw) { relaunch(raw); };
  // Kumanda tuşunu sayfaya iletir (Geri ve renk tuşları sayfaya kendiliğinden gelmez).
  window.__onKey = function (code) {
    var event = new Event('keydown', { cancelable: true });
    event.keyCode = code;
    document.dispatchEvent(event);
  };

  // Nino: kurulu TV'lerin marka ve modeli panelde görünsün diye günde bir kez anonim bildirilir: rastgele bir kimlik,
  // marka, model ve uygulama sürümü. Ad, adres ya da hesap gönderilmez. İnternet yoksa sessizce geçilir.
  function reportTv(brand, model) {
    try {
      var store = window.localStorage;
      if (!store || !model) return;
      var now = new Date().getTime();
      if (now - parseInt(store.getItem('ninoTvPing') || '0', 10) < 20 * 3600 * 1000) return;
      var id = store.getItem('ninoTvId');
      if (!id) {
        id = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
          var r = Math.floor(Math.random() * 16);
          return (c === 'x' ? r : (r & 3) | 8).toString(16);
        });
        store.setItem('ninoTvId', id);
      }
      store.setItem('ninoTvPing', String(now));
      var label = document.getElementById('app-version');
      var version = (((label && label.textContent) || '').match(/\d+(\.\d+)+/) || [''])[0];
      new Image().src = 'https://nino-pool.y-demirbag2506.workers.dev/v1/tv?install=' + id + '&brand=' + brand +
        '&model=' + encodeURIComponent(String(model).slice(0, 60)) + '&app=' + encodeURIComponent(version);
    } catch (e) { /* bildirim isteğe bağlı */ }
  }
  window.addEventListener('load', function () {
    setTimeout(function () { reportTv('androidtv', bridge.deviceModel ? bridge.deviceModel() : ''); }, 4000);
  });

  // Nino ana ekranı: logo, bağlantı durumu ve tek bir yönerge. Düğme ve ayar yok; Geri tuşu çıkar.
  var TR = /^tr/i.test(navigator.language || '');
  // Türkçe ekler sayıya göre: HDMI 1'de/1'e, 2'de/2'ye, 3'te/3'e, 4'te/4'e.
  var LOC = { 1: "'de", 2: "'de", 3: "'te", 4: "'te" };
  var DAT = { 1: "'e", 2: "'ye", 3: "'e", 4: "'e" };
  // Giriş adı yalnız "PS5" değilse parantez içinde gösterilir (ör. "Oyun").
  function extraLabel(label) { return label && !/ps\s*5|playstation/i.test(label) ? ' (' + label + ')' : ''; }
  // Nino: TV'yi telefon da bilgisayar da sürebilir; yazılar ikisini de söyler (eskiden yalnız "bilgisayardaki Nino").
  var TEXT = TR ? {
    connected: 'Nino\'ya bağlı',
    waiting: 'Telefondaki ya da bilgisayardaki Nino bekleniyor',
    goTitle: function (port, label) { return port ? 'PS5\'iniz HDMI ' + port + (LOC[port] || "'de") + extraLabel(label) : 'PS5\'inizin girişine geçin'; },
    goText: function (port) {
      return 'Kumandanın kaynak tuşuyla ' + (port ? 'HDMI ' + port + (DAT[port] || "'e") : 'PS5\'in bağlı olduğu girişe') +
        ' geçin. Altyazı çevirisi oyunun üstünde görünecek.';
    },
    permTitle: 'Bir kerelik izin gerekiyor',
    permText: 'Altyazının oyunun üstünde görünmesi için Nino\'ya “Diğer uygulamaların üzerinde göster” izni gerekir. ' +
      'TV\'de USB hata ayıklama açıksa telefondaki ya da bilgisayardaki Nino\'da çeviriyi başlatın; TV sorunca ' +
      '“Her zaman izin ver”i işaretleyip İzin ver\'i seçin, izin kendiliğinden verilir. Açık değilse aşağıdan seçin.',
    permSettings: 'İzni TV\'den ver',
    permInApp: 'İzin vermeden devam et',
    permHint: 'İzin vermeden devam ederseniz oyun Nino\'nun içinde gösterilir; bazı TV\'lerde görüntü siyah kalabilir.',
    back: 'Geri: çık'
  } : {
    connected: 'Connected to Nino',
    waiting: 'Waiting for Nino on your phone or computer',
    goTitle: function (port, label) { return port ? 'Your PS5 is on HDMI ' + port + extraLabel(label) : 'Switch to your PS5\'s input'; },
    goText: function (port) {
      return 'Use the input button on your remote to switch to ' + (port ? 'HDMI ' + port : 'the PS5\'s input') +
        '. Translated subtitles will appear over the game.';
    },
    permTitle: 'One-time permission needed',
    permText: 'To show subtitles over the game, Nino needs the “Display over other apps” permission. If USB debugging ' +
      'is on, start translating in Nino on your phone or computer; when the TV asks, tick “Always allow” and choose ' +
      'Allow, and the permission is granted by itself. If it is off, choose below.',
    permSettings: 'Grant on the TV',
    permInApp: 'Continue without permission',
    permHint: 'Without the permission the game is shown inside Nino; on some TVs the picture may stay black.',
    back: 'Back: exit'
  };

  function setupHome() {
    var style = document.createElement('style');
    style.textContent = [
      'body.home { background: #03060d !important; }',
      'body.home > *:not(#nino-home) { display: none !important; }',
      '#nino-home { position: absolute; inset: 0; overflow: hidden; color: #fff; display: flex; flex-direction: column;',
      ' align-items: center; justify-content: center; font-family: -apple-system, "SF Pro Display", Roboto, "Helvetica Neue", Arial, sans-serif; }',
      '#nino-home .glow { position: absolute; border-radius: 50%; filter: blur(140px); opacity: 0.55; }',
      '#nino-home .g1 { width: 1100px; height: 1100px; left: -320px; top: -420px; background: #1d4ed8; animation: ninoDrift 14s ease-in-out infinite alternate; }',
      '#nino-home .g2 { width: 900px; height: 900px; right: -280px; bottom: -380px; background: #c8102e; opacity: 0.32; animation: ninoDrift 18s ease-in-out infinite alternate-reverse; }',
      '@keyframes ninoDrift { from { transform: translate(0,0) scale(1); } to { transform: translate(60px,40px) scale(1.08); } }',
      '#nino-home .brand { display: flex; flex-direction: column; align-items: center; z-index: 1; }',
      '#nino-home .logo { width: 200px; height: 200px; border-radius: 46px; box-shadow: 0 30px 90px rgba(29,78,216,0.55); }',
      '#nino-home .name { margin-top: 34px; font-size: 92px; font-weight: 700; letter-spacing: -2px; }',
      '#nino-home .tag { margin-top: 4px; font-size: 22px; font-weight: 600; letter-spacing: 9px; color: rgba(255,255,255,0.55); }',
      '#nino-home .status { margin-top: 44px; display: flex; align-items: center; gap: 14px; font-size: 28px; color: rgba(255,255,255,0.8); z-index: 1; }',
      '#nino-home .dot { width: 14px; height: 14px; border-radius: 50%; background: #f5a524; box-shadow: 0 0 18px #f5a524; }',
      '#nino-home .status.ok .dot { background: #30d158; box-shadow: 0 0 18px #30d158; }',
      '#nino-home .card { margin-top: 64px; width: 1180px; padding: 44px 56px; border-radius: 36px; z-index: 1; text-align: center;',
      ' background: rgba(255,255,255,0.07); border: 1px solid rgba(255,255,255,0.14); box-shadow: 0 40px 120px rgba(0,0,0,0.45); }',
      '#nino-home .card h1 { margin: 0; font-size: 54px; font-weight: 700; letter-spacing: -0.5px; }',
      '#nino-home .card p { margin: 18px 0 0; font-size: 30px; line-height: 1.45; color: rgba(255,255,255,0.72); }',
      '#nino-home .card.warn h1 { color: #ffd166; }',
      '#nino-home .actions { display: flex; gap: 22px; margin-top: 34px; justify-content: center; }',
      '#nino-home .btn { font-size: 28px; font-weight: 600; padding: 18px 34px; border-radius: 999px; color: #fff;',
      ' background: rgba(255,255,255,0.10); border: 3px solid transparent; }',
      '#nino-home .btn.on { background: #fff; color: #03060d; border-color: #ffd166; }',
      '#nino-home .card .hint { font-size: 22px; color: rgba(255,255,255,0.5); margin-top: 20px; }',
      // İzin ekranında yazı ve düğmeler de var: 1080 piksele sığsın diye logo ve boşluklar küçülür.
      '#nino-home.perm .logo { width: 120px; height: 120px; border-radius: 28px; }',
      '#nino-home.perm .name { margin-top: 18px; font-size: 60px; }',
      '#nino-home.perm .tag { display: none; }',
      '#nino-home.perm .status { margin-top: 20px; }',
      '#nino-home.perm .card { margin-top: 30px; padding: 34px 48px; }',
      '#nino-home.perm .card h1 { font-size: 46px; }',
      '#nino-home.perm .card p { font-size: 27px; margin-top: 14px; }',
      '#nino-home.perm .card .hint { font-size: 21px; }',
      '#nino-home .foot { position: absolute; bottom: 54px; left: 0; right: 0; text-align: center; font-size: 22px; color: rgba(255,255,255,0.38); z-index: 1; }'
    ].join('\n');
    document.head.appendChild(style);
    document.body.className += ' home';

    var hint = { port: 0, label: '' };
    try { hint = JSON.parse(bridge.consoleHint()) || hint; } catch (e) { /* bilinmiyor */ }
    var version = bridge.appVersion ? bridge.appVersion() : '';
    var permission = homeMode === 'permission';
    var root = document.createElement('div');
    root.id = 'nino-home';
    if (permission) root.className = 'perm';
    root.innerHTML =
      '<div class="glow g1"></div><div class="glow g2"></div>' +
      '<div class="brand"><img class="logo" src="logo.png" alt=""><div class="name">Nino</div><div class="tag">GAME TRANSLATOR</div></div>' +
      '<div class="status"><span class="dot"></span><span class="s-text"></span></div>' +
      '<div class="card' + (permission ? ' warn' : '') + '"><h1></h1><p></p>' +
      (permission && bridge.continueInApp ? '<div class="actions"><div class="btn on"></div><div class="btn"></div></div><p class="hint"></p>' : '') +
      '</div>' +
      '<div class="foot"></div>';
    document.body.appendChild(root);
    root.querySelector('.card h1').textContent = permission ? TEXT.permTitle : TEXT.goTitle(hint.port, hint.label);
    root.querySelector('.card p').textContent = permission ? TEXT.permText : TEXT.goText(hint.port);
    root.querySelector('.foot').textContent = TEXT.back + (version ? '  ·  Nino ' + version : '');

    // İzin ekranı: iki düğme (sol/sağ ile seçilir, OK ile açılır). Geliştirici seçeneği olmayan TV'lerde ekran çıkışsız
    // kalıyordu (panelde 13 bildirim); izin TV'nin ayarından verilebilir ya da izinsiz, Nino'nun içinde devam edilir.
    var buttons = root.querySelectorAll('.btn');
    var chosen = 0;
    if (buttons.length === 2) {
      buttons[0].textContent = TEXT.permSettings;
      buttons[1].textContent = TEXT.permInApp;
      root.querySelector('.hint').textContent = TEXT.permHint;
      document.addEventListener('keydown', function (e) {
        var code = e.keyCode;
        if (code === 37 || code === 39) {
          chosen = code === 37 ? 0 : 1;
          buttons[0].className = 'btn' + (chosen === 0 ? ' on' : '');
          buttons[1].className = 'btn' + (chosen === 1 ? ' on' : '');
          e.preventDefault();
        } else if (code === 13) {
          e.preventDefault();
          if (chosen === 0) bridge.openOverlaySettings(); else bridge.continueInApp();
        }
      }, true);
    }
    homeStatus = root.querySelector('.status');
    homeConnection(false);

    // Geri tuşu Nino'dan çıkar (ana ekranda başka bir şey yapmaz).
    document.addEventListener('keydown', function (e) {
      if (e.keyCode !== 4 && e.keyCode !== 27 && e.keyCode !== 8) return;
      e.stopImmediatePropagation();
      e.preventDefault();
      bridge.exit();
    }, true);
  }

  function homeConnection(open) {
    if (!homeStatus) return;
    homeStatus.className = 'status' + (open ? ' ok' : '');
    homeStatus.querySelector('.s-text').textContent = open ? TEXT.connected : TEXT.waiting;
  }

  // Bağlantı kopukken katmanda sağ üstte küçük bir nokta; bağlıyken hiçbir şey görünmez.
  function connection(open) {
    homeConnection(open);
    if (!dot) return;
    clearTimeout(dotTimer);
    if (open) {
      dot.className = 'hidden';
      return;
    }
    dotTimer = setTimeout(function () { dot.className = ''; }, DOT_AFTER_MS);
  }

  function setupOverlay() {
    var style = document.createElement('style');
    // Bekleme kutusu ve demo kumandayla kapatılamaz; oyunun üstünde asılı kalmasın.
    style.textContent = 'body.overlay #waiting, body.overlay #demo-badge { display: none !important; }' +
      '#overlay-dot { position: absolute; top: 32px; right: 32px; width: 14px; height: 14px; border-radius: 50%;' +
      ' background: #F28B82; opacity: 0.8; z-index: 50; }' +
      '#overlay-dot.hidden { display: none; }';
    document.head.appendChild(style);
    document.body.className += ' overlay';
    dot = document.createElement('div');
    dot.id = 'overlay-dot';
    dot.className = 'hidden';
    document.body.appendChild(dot);
    connection(false);
  }

  // Ortak sayfanın EventSource'u sarılır: bilgisayarın görüntü modu seçimi (style olayındaki displayMode) Android'e
  // iletilir, bağlantı durumu katmandaki noktayı yönetir. Sayfanın kendi dinleyicileri olduğu gibi çalışır.
  var NativeSource = window.EventSource;
  if (NativeSource) {
    var Source = function (url, options) {
      var source = options === undefined ? new NativeSource(url) : new NativeSource(url, options);
      source.addEventListener('open', function () { connection(true); });
      source.addEventListener('error', function () { connection(source.readyState === 1); });
      source.addEventListener('style', function (e) {
        var mode;
        try { mode = JSON.parse(e.data).displayMode; } catch (err) { return; }
        if (typeof mode === 'string' && bridge.setDisplayMode) bridge.setDisplayMode(mode);
      });
      return source;
    };
    Source.prototype = NativeSource.prototype;
    Source.CONNECTING = 0;
    Source.OPEN = 1;
    Source.CLOSED = 2;
    window.EventSource = Source;
  }

  window.COUCHSUBS_PLATFORM = {
    backKey: 4,

    // Dublaj <audio> ile çalınır (LG ve Samsung'da Web Audio): HDMI'yi TvView gösterdiği için karışmaz, yukarıdaki
    // sarmalayıcı da sesi arka planda susturabilir.
    speechElement: true,

    init: function () {
      // Android TV'nin güvenli alanı (yanlarda 48dp, üstte 27dp: 1080p'de 96 ve 54 piksel, TV-OV) artık ortak
      // style.css'in varsayılanıdır; burada ayrıca kurulmaz.
      if (overlay) setupOverlay();
      else if (homeMode) {
        if (document.body) setupHome(); else window.addEventListener('DOMContentLoaded', setupHome);
      }
      // Panelde Android uygulamasının kendi sürümü görünsün (ortak sayfadaki sayı LG ve Samsung'unkidir).
      var version = bridge.appVersion ? bridge.appVersion() : '';
      if (version) {
        window.addEventListener('load', function () {
          var el = document.getElementById('app-version');
          if (el) el.textContent = version;
        });
      }
    },

    launchParams: function () { return bridge.launchParams(); },

    onRelaunch: function (callback) { relaunch = callback; },

    // onStatus: 'loading' | 'ready' | 'playing' | 'inputError' | 'sourceError'
    showHdmi: function (port, host, onStatus) {
      hdmiStatus = onStatus;
      onStatus('loading');
      bridge.showHdmi(port);
    },

    findConsolePort: function (callback) {
      var port = bridge.consolePort();
      callback(port > 0 ? port : null, port > 0 ? 'HDMI ' + port : null);
    },

    localAddress: function (callback) { callback(bridge.localAddress() || null); },

    exit: function () { bridge.exit(); }
  };
})();
