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

  // Nino ana ekranı: logo, bağlantı durumu ve tek bir yönerge. Düğme ve ayar yok; Geri tuşu çıkar.
  var TR = /^tr/i.test(navigator.language || '');
  // Türkçe ekler sayıya göre: HDMI 1'de/1'e, 2'de/2'ye, 3'te/3'e, 4'te/4'e.
  var LOC = { 1: "'de", 2: "'de", 3: "'te", 4: "'te" };
  var DAT = { 1: "'e", 2: "'ye", 3: "'e", 4: "'e" };
  // Giriş adı yalnız "PS5" değilse parantez içinde gösterilir (ör. "Oyun").
  function extraLabel(label) { return label && !/ps\s*5|playstation/i.test(label) ? ' (' + label + ')' : ''; }
  var TEXT = TR ? {
    connected: 'Bilgisayardaki Nino\'ya bağlı',
    waiting: 'Bilgisayardaki Nino bekleniyor',
    goTitle: function (port, label) { return port ? 'PS5\'iniz HDMI ' + port + (LOC[port] || "'de") + extraLabel(label) : 'PS5\'inizin girişine geçin'; },
    goText: function (port) {
      return 'Kumandanın kaynak tuşuyla ' + (port ? 'HDMI ' + port + (DAT[port] || "'e") : 'PS5\'in bağlı olduğu girişe') +
        ' geçin. Türkçe altyazı oyunun üstünde görünecek.';
    },
    permTitle: 'Bir kerelik onay gerekiyor',
    permText: 'Altyazıyı oyunun üstünde göstermek için bilgisayardaki Nino\'da çeviriyi başlatın. TV\'de “USB hata ayıklamaya ' +
      'izin verilsin mi?” sorusu çıkınca “Bu bilgisayardan her zaman izin ver”i işaretleyip İzin ver\'i seçin.',
    back: 'Geri: çık'
  } : {
    connected: 'Connected to Nino on your computer',
    waiting: 'Waiting for Nino on your computer',
    goTitle: function (port, label) { return port ? 'Your PS5 is on HDMI ' + port + extraLabel(label) : 'Switch to your PS5\'s input'; },
    goText: function (port) {
      return 'Use the input button on your remote to switch to ' + (port ? 'HDMI ' + port : 'the PS5\'s input') +
        '. Turkish subtitles will appear over the game.';
    },
    permTitle: 'One-time approval needed',
    permText: 'To show subtitles over the game, start translating in Nino on your computer. When the TV asks to allow USB ' +
      'debugging, tick “Always allow from this computer” and choose Allow.',
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
    root.innerHTML =
      '<div class="glow g1"></div><div class="glow g2"></div>' +
      '<div class="brand"><img class="logo" src="logo.png" alt=""><div class="name">Nino</div><div class="tag">GAME TRANSLATOR</div></div>' +
      '<div class="status"><span class="dot"></span><span class="s-text"></span></div>' +
      '<div class="card' + (permission ? ' warn' : '') + '"><h1></h1><p></p></div>' +
      '<div class="foot"></div>';
    document.body.appendChild(root);
    root.querySelector('.card h1').textContent = permission ? TEXT.permTitle : TEXT.goTitle(hint.port, hint.label);
    root.querySelector('.card p').textContent = permission ? TEXT.permText : TEXT.goText(hint.port);
    root.querySelector('.foot').textContent = TEXT.back + (version ? '  ·  Nino ' + version : '');
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
      ' background: #E5484D; opacity: 0.8; z-index: 50; }' +
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
      // Android TV'nin güvenli alanı (yanlarda 48dp, üstte 27dp: 1080p'de 96 ve 54 piksel): panel ve demo notu kenara
      // taşan (overscan) TV'lerde kesilmesin (TV-OV).
      var safe = document.createElement('style');
      safe.textContent = '#panel { top: 54px; left: 96px; } #demo-badge { top: 54px; right: 96px; }';
      document.head.appendChild(safe);
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
