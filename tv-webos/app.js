// SPDX-License-Identifier: AGPL-3.0-only
// CouchSubs TV uygulaması (webOS ve Tizen ortak).
// HDMI girişini tam ekran gösterir, üstüne CouchSubs uygulamasından gelen altyazıyı basar.
// TV'ye özgü işler platform.js'tedir. Eski TV tarayıcıları için ES5 ile yazıldı.
(function () {
  'use strict';

  // TV uygulamasının sürümü: appinfo.json, tv-tizen/config.xml ve tv-android/app/build.gradle ile aynı tutulur.
  var APP_VERSION = '4.0.3';
  // Nino: herkesin göreceği sürüm adı (bütün uygulamalarda aynı: V3.2). Teknik numara parantez içinde.
  var APP_LABEL = 'V4.0';
  var t = window.t;
  var config = window.COUCHSUBS_CONFIG || {};
  var platform = window.COUCHSUBS_PLATFORM;
  var KEY = { RED: 403, GREEN: 404, BLUE: 406, LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, OK: 13, BACK: platform.backKey };

  var server = null;
  var eventSource = null;
  // Kumandayla seçilen port kayıtlıysa o kullanılır, yoksa PS5 otomatik aranır.
  var savedPort = Number(load('hdmi'));
  // Nino: 0 = bilinmiyor; Android TV katmanında TV'nin son girişi açılır (HDMI 1'e zorlanmaz).
  var hdmiPort = savedPort || 0;

  var bottomPercent = 7;
  // Çevirinin yeri: oyundaki İngilizce altyazının üstünü örterek (cover), üstünde (above), altında (below)
  // ya da sabit yükseklikte (fixed). Yeri bildirmeyen eski CouchSubs sürümlerinde sabit kalır.
  var PLACEMENTS = { cover: 1, above: 1, below: 1, fixed: 1 };
  var placement = 'fixed';
  // Gösterilen satırın oyundaki İngilizce altyazının yeri (ekrana oranla), bilinmiyorsa null.
  var currentBox = null;

  // Hızlı konuşma: yeni satır öncekinden bu süre içinde gelirse önceki okunamamış olabilir. Önceki çeviri yeni satırın
  // üstünde küçük ve soluk olarak bir süre daha kalır, sonra solarak kalkar. Üç kişi art arda konuşursa iki önceki satır
  // da en üstte daha soluk durur; ekranda en çok üç satır olur.
  var STACK_WITHIN_MS = 1500;
  var PREVIOUS_HOLD_MS = 1500;
  var PREVIOUS_FADE_MS = 400;
  // Yeni satırla yer değiştirmedikçe hiçbir satır bundan kısa görünmez.
  var MIN_VISIBLE_MS = 1200;
  var shownAt = 0;
  var shownParagraphs = false;
  // Bilgisayardaki "Hızlı konuşmada önceki satırları üstte göster" ayarı (kapalıysa yeni satır eskisinin yerine geçer).
  // Ayar bilgisayardan gelene kadar son bilinen değer kullanılır; hiç gelmediyse açıktır (eski davranış).
  var stackPrevious = load('stackPrevious') !== '0';
  // Üstteki satırlar: 'subtitle-prev' bir önceki, 'subtitle-prev2' iki önceki. Her birinin kendi zamanlayıcıları var.
  var previousTimers = { 'subtitle-prev': [null, null], 'subtitle-prev2': [null, null] };

  var hideTimer = null;
  var panelTimer = null;

  // Bilgisayarın "temizle" olayı satırı bundan erken kaldırmaz: oyundaki satır çeviri gelirken kalkmışsa yazı TV'de
  // bir an görünüp kayboluyordu. Süre, bilgisayarın okuma süresi kuralıyla aynıdır; üst sınırı daha kısadır.
  var HOLD_MAX_MS = 5000;
  var holdUntil = 0;
  // Bağlantı bir an koptuğunda yazı silinmez; ancak bu süre içinde geri gelmezse silinir.
  var DROP_HIDE_MS = 6000;
  var dropTimer = null;

  // Panelde görünen tanı bilgisi: "yazı TV'ye gelmiyor" bildirimlerinde sebebi buradan okuruz.
  var diag = { subtitles: 0, clears: 0, drops: 0, backgrounded: 0, lastHide: '-', place: '-', error: '' };

  function $(id) { return document.getElementById(id); }

  function renderDiag() {
    var el = $('st-diag');
    if (!el) return;
    el.textContent = 'sub ' + diag.subtitles + ' · clear ' + diag.clears + ' · drop ' + diag.drops +
      ' · bg ' + diag.backgrounded + ' · hide ' + diag.lastHide + ' · ' + diag.place +
      (window.__screenSaverStatus ? ' · saver ' + window.__screenSaverStatus : '') +
      (diag.error ? ' · err ' + diag.error : '');
  }

  function noteError(message) {
    diag.error = String(message).slice(0, 120);
    renderDiag();
  }

  window.onerror = function (message, source, line) {
    noteError(message + ' @' + line);
    return false;
  };

  document.addEventListener('visibilitychange', function () {
    if (document.hidden) diag.backgrounded++;
    renderDiag();
  });

  function load(key) {
    try { return window.localStorage.getItem('couchsubs.' + key); } catch (e) { return null; }
  }

  function save(key, value) {
    try { window.localStorage.setItem('couchsubs.' + key, String(value)); } catch (e) {}
  }

  function setStatus(id, text, cls) {
    var el = $(id);
    el.textContent = text;
    // Nino: yazının kendi sınıfı korunur, durum sınıfı yanına eklenir.
    var base = el.getAttribute('data-base');
    if (base === null) { base = el.className || ''; el.setAttribute('data-base', base); }
    el.className = (base + ' ' + (cls || '')).trim();
    // Panelin durumu (renk, başlık, salıncak) yalnız bağlantıdan gelir: 'ok', 'bad', başka her şey = bekliyor.
    // Eskiden HDMI satırı da aynı niteliği yazıyordu; bağlantı koptuğu hâlde görüntü gelince "hazır" görünüyordu.
    if (id === 'st-conn') {
      var hero = document.querySelector('#panel .hero');
      if (hero) hero.setAttribute('data-state', cls || '');
    }
  }

  // --- Başlatma parametreleri ---

  function parseParams(raw) {
    if (!raw) return {};
    if (typeof raw === 'object') return raw;
    try { return JSON.parse(raw) || {}; } catch (e) { return {}; }
  }

  // Parametrelerdeki sunucu ve HDMI tercihini uygular; sunucu değiştiyse yeniden bağlanır.
  function applyParams(params) {
    if (params.hdmi >= 1 && params.hdmi <= 4) {
      hdmiPort = Number(params.hdmi);
      save('hdmi', hdmiPort);
      showHdmi(hdmiPort);
    }
    if (params.server && params.server !== server) {
      save('server', params.server);
      connect(params.server);
    }
  }

  // --- HDMI görüntüsü ---

  function showHdmi(port) {
    setStatus('st-hdmi', port ? String(port) : t('auto'));
    var statuses = {
      loading: ['loading', 'muted'],
      ready: ['videoReady', 'ok'],
      playing: ['playing', 'ok'],
      inputError: ['inputError', 'bad'],
      sourceError: ['sourceError', 'bad']
    };
    watchPicture(port);
    platform.showHdmi(port, $('video-host'), function (kind) {
      setStatus('st-video', t(statuses[kind][0]), statuses[kind][1]);
      notePicture(port, kind);
    });
  }

  // --- HDMI görüntüsü gelmiyor ---
  // LG'de HDMI girişi <video> ile (ext://hdmi), Samsung'da TVWindow ile açılır. Giriş açılamazsa ya da 10 sn içinde
  // görüntü gelmezse ekran sessizce siyah kalıyordu (LG QNED: "Çeviriyi başlat"a basınca TV kararıyor). Artık nedeni ve
  // HDMI girişi düğmeleri gösterilir; doğru girişte de siyahsa TV'nin kendi girişine dönüp altyazıyı telefonda izlemek
  // önerilir. Android TV'deki giriş seçiciyle (#155) aynı akış; Android bunu kendi ekranında yaptığından orada kapalıdır.

  var NO_PICTURE_MS = 10000;
  var pictureTimer = null;
  var pictureOk = false;
  var noPictureClosed = false;
  var noPictureFocus = 0;
  var noPictureActions = [];

  function watchPicture(port) {
    clearTimeout(pictureTimer);
    pictureOk = false;
    noPictureClosed = false;
    hideNoPicture();
    if (!platform.noPictureHelp) return;
    pictureTimer = setTimeout(function () {
      // Bazı TV'ler görüntüyü gösterip 'playing' olayını hiç göndermiyor; görüntü varsa kutu açılmaz.
      if (pictureOk || (platform.hasPicture && platform.hasPicture())) return;
      showNoPicture(port, false);
    }, NO_PICTURE_MS);
  }

  function notePicture(port, kind) {
    if (port !== hdmiPort) return;
    if (kind === 'ready' || kind === 'playing') {
      pictureOk = true;
      clearTimeout(pictureTimer);
      hideNoPicture();
    } else if (kind === 'inputError' || kind === 'sourceError') {
      clearTimeout(pictureTimer);
      if (platform.noPictureHelp) showNoPicture(port, true);
    }
  }

  function noPictureShown() { return $('no-picture').className !== 'hidden'; }

  function showNoPicture(port, failed) {
    if (noPictureClosed || pictureOk || demoRunning()) return;
    // Neden ve ne yapılacağı düğmelerin üstünde; uzun "hâlâ siyah mı" açıklaması (index.html, #no-picture-help)
    // düğmelerin altında, küçük ve ikincil renkte durur.
    $('no-picture-text').textContent = t(failed ? 'noPictureError' : 'noPicture').replace('%1', port) + ' ' +
      t('noPictureChoose');
    var box = $('no-picture-choices');
    box.innerHTML = '';
    var actions = [];
    for (var i = 1; i <= 4; i++) actions.push({ label: 'HDMI ' + i, port: i });
    actions.push({ label: t('noPictureExit'), exit: true });
    actions.push({ label: t('noPictureClose'), close: true });
    for (var j = 0; j < actions.length; j++) {
      var button = document.createElement('div');
      button.className = 'button' + (actions[j].port === port ? ' current' : '');
      button.textContent = actions[j].label;
      button.addEventListener('click', choiceClick(actions[j], j));
      // LG Magic Remote: işaretçinin üstünde durduğu düğme seçili olur; Tamam ve oklar oradan devam eder.
      button.addEventListener('mouseover', choiceHover(j));
      actions[j].el = button;
      box.appendChild(button);
    }
    noPictureActions = actions;
    $('panel').className = 'hidden';
    $('waiting').className = 'hidden';
    $('no-picture').className = '';
    // Açık olandan sonraki giriş seçili gelir (HDMI 1 açıksa HDMI 2).
    focusNoPicture(port % 4);
  }

  function choiceClick(action, index) {
    return function (e) {
      e.stopPropagation();
      // Tamam tuşu işaretçi görünürken tıklama da gönderir; tuşla seçilen bir daha seçilmez.
      if (Date.now() - lastOkKey < 400) return;
      focusNoPicture(index);
      runNoPicture(action);
    };
  }

  function choiceHover(index) {
    return function () {
      if (index !== noPictureFocus) focusNoPicture(index);
    };
  }

  function focusNoPicture(index) {
    var count = noPictureActions.length;
    noPictureFocus = (index + count) % count;
    for (var i = 0; i < count; i++) {
      var el = noPictureActions[i].el;
      el.className = el.className.replace(' focused', '') + (i === noPictureFocus ? ' focused' : '');
    }
  }

  // ▲▼: düğmeler iki satıra bölünürse (uzun dil, dar ekran) bir üst/alt satırda yatayda en yakın düğmeye geçer.
  // Tek satırda yerinde kalır (◀▶ zaten sırayla gezer).
  function focusNoPictureRow(step) {
    var current = noPictureActions[noPictureFocus].el;
    var top = current.offsetTop;
    var center = current.offsetLeft + current.offsetWidth / 2;
    var best = -1, bestRow = 0, bestSide = 0;
    for (var i = 0; i < noPictureActions.length; i++) {
      var el = noPictureActions[i].el;
      var row = (el.offsetTop - top) * step;
      // Aynı satırdakiler (birkaç piksel fark dahil) ve ters yöndekiler atlanır.
      if (row <= 2) continue;
      var side = Math.abs(el.offsetLeft + el.offsetWidth / 2 - center);
      if (best < 0 || row < bestRow - 2 || (Math.abs(row - bestRow) <= 2 && side < bestSide)) {
        best = i;
        bestRow = row;
        bestSide = side;
      }
    }
    if (best >= 0) focusNoPicture(best);
  }

  function runNoPicture(action) {
    if (action.exit) {
      hideNoPicture();
      leaving = true;
      platform.exit();
    } else if (action.close) {
      closeNoPicture();
    } else {
      hdmiPort = action.port;
      save('hdmi', hdmiPort);
      showHdmi(hdmiPort);
      showPanel(true);
    }
  }

  // Kullanıcı kutuyu kapattı: başka giriş seçilene ya da uygulama yeniden başlatılana kadar yeniden açılmaz.
  function closeNoPicture() {
    noPictureClosed = true;
    hideNoPicture();
  }

  function hideNoPicture() {
    var el = $('no-picture');
    if (!el || el.className === 'hidden') return;
    el.className = 'hidden';
    if (!server && !demoRunning()) $('waiting').className = '';
  }

  function autoSelectConsole(onNotFound) {
    platform.findConsolePort(function (port, label) {
      if (!port) return onNotFound && onNotFound();
      if (port !== hdmiPort) {
        hdmiPort = port;
        showHdmi(port);
      }
      setStatus('st-hdmi', port + ' — ' + label + ' (' + t('auto') + ')');
    });
  }

  // --- Altyazı ---

  // Kutunun sayıları geçerli mi (0–1 arası, sağ soldan, alt üstten büyük).
  function validBox(box) {
    if (!box || typeof box !== 'object') return null;
    var keys = ['left', 'top', 'right', 'bottom'];
    for (var i = 0; i < keys.length; i++) {
      var value = box[keys[i]];
      if (typeof value !== 'number' || value < 0 || value > 1) return null;
    }
    return box.right > box.left && box.bottom > box.top ? box : null;
  }

  // --- Uzun çeviriyi bölme ---
  // Uzun çeviri ekranda tek uzun satır olarak taşmasın: satır başına en çok 42 karakter, en çok 3 satır, kelime
  // sınırından ve dengeli bölünür; 3 satıra sığmazsa yazı biraz küçülür (en çok %75'e kadar). Konuşan adı ("ARTHUR:")
  // sonraki sözcükle birleşik kalır, hep ilk satırdadır. Mac, Windows, Android ve OBS (SubtitleWrap) aynı kuralları uygular.
  // Nino: satır daha geniş, en çok iki satır (üç satırlık kutu kalın görünüyordu; Türkçe çeviri İngilizceden uzun).
  var WRAP_MAX_CHARS = 56;
  var WRAP_MAX_LINES = 2;
  var WRAP_MIN_SCALE = 0.75;
  var fontBase = 46;

  function wrapTokens(text) {
    var words = text.split(/\s+/).filter(function (w) { return w; });
    for (var i = 0; i < Math.min(3, words.length); i++) {
      var w = words[i];
      if (w.charAt(w.length - 1) === ':' || w.charAt(w.length - 1) === '\uFF1A') {
        if (i + 1 < words.length) words.splice(0, i + 2, words.slice(0, i + 2).join(' '));
        break;
      }
    }
    return words;
  }

  function wrapWidth(words, from, to) {
    var sum = to - from - 1;
    for (var i = from; i < to; i++) sum += words[i].length;
    return sum;
  }

  function wrapBalance(words, lines) {
    var count = words.length;
    var best = null;
    function consider(cuts) {
      var edges = [0].concat(cuts, [count]);
      var longest = 0;
      var spread = 0;
      for (var i = 0; i < edges.length - 1; i++) {
        var width = wrapWidth(words, edges[i], edges[i + 1]);
        longest = Math.max(longest, width);
        spread += width * width;
      }
      if (!best || longest < best.longest || (longest === best.longest && spread < best.spread)) {
        best = { longest: longest, spread: spread, cuts: cuts };
      }
    }
    var a, b;
    if (lines === 2 || count < 3) {
      for (a = 1; a < count; a++) consider([a]);
    } else {
      for (a = 1; a < count - 1; a++) for (b = a + 1; b < count; b++) consider([a, b]);
    }
    if (!best) return words.join(' ');
    var all = [0].concat(best.cuts, [count]);
    var out = [];
    for (var i = 0; i < all.length - 1; i++) out.push(words.slice(all[i], all[i + 1]).join(' '));
    return out.join('\n');
  }

  function wrapSubtitle(text) {
    var length = Array.from ? Array.from(text).length : text.length;
    if (length <= WRAP_MAX_CHARS || text.indexOf('\n') >= 0) return { text: text, scale: 1 };
    var words = wrapTokens(text);
    if (words.length < 2) return { text: text, scale: 1 };
    var scale = Math.min(1, Math.max(WRAP_MIN_SCALE, WRAP_MAX_CHARS * WRAP_MAX_LINES / length));
    var cap = Math.floor(WRAP_MAX_CHARS / scale);
    var lines = Math.min(WRAP_MAX_LINES, Math.max(2, Math.ceil(length / cap)));
    return { text: wrapBalance(words, Math.min(lines, words.length)), scale: scale };
  }

  // Satırı yazar. Sayfadaki metin bölünmüş hâlidir; karşılaştırmalar için özgün metin elementte kalır.
  // Nino: rich ise düğme simgeleri rozet olarak çizilir (setRich); her durumda Arapça satır sağdan sola dizilir.
  function setLineText(textId, text, paragraphs, baseSize, rich) {
    var el = $(textId);
    var wrapped = paragraphs ? { text: text, scale: 1 } : wrapSubtitle(text);
    el.rawText = text;
    if (rich) {
      setRich(el, wrapped.text);
    } else {
      el.textContent = wrapped.text;
      setDirection(el, text);
    }
    el.style.whiteSpace = 'pre-line';
    el.style.fontSize = Math.round(baseSize * wrapped.scale) + 'px';
  }

  function rawText(id) {
    var el = $(id);
    return el.rawText !== undefined ? el.rawText : el.textContent;
  }

  // paragraphs: görev paneli gibi başlık ve maddeli yazılar satır satır, sola yaslı gösterilir.
  // replaces: bilgisayar bu satırı öncekinin uzamış ya da düzelmiş okuması saydı (bkz. replacesCurrent).
  var startedTimer = null;
  function showStartedNotice() {
    var el = $('started-notice');
    if (!el) {
      el = document.createElement('div');
      el.id = 'started-notice';
      el.innerHTML = '<span class="bot"><img src="nino-bot.png" alt=""></span><span class="bubble"></span>';
      document.body.appendChild(el);
    }
    el.querySelector('.bubble').textContent = t('translationStarted');
    el.className = 'show';
    clearTimeout(startedTimer);
    startedTimer = setTimeout(function () { el.className = ''; }, 7000);
  }

  // Nino: paneldeki "son altyazı" yalnız bilgisayardan ya da telefondan gelen gerçek altyazıdır; demo satırları, deneme
  // yazısı ve yer önizlemesi buraya yazılmaz. Alan ilk altyazıyla birlikte görünür (o zamana kadar boş kutu gösterilmez).
  function notePanelSubtitle(text) {
    setStatus('st-last', text.length > 60 ? text.slice(0, 60) + '…' : text);
    var preview = $('st-preview');
    if (preview) preview.className = 'p-preview';
  }

  // Nino (akıllı koyuluk): sahne aydınlıksa zemin koyulaşır, karanlıksa açılıp sahneye karışır. Örtü (İngilizceyi
  // kapatan zemin) her zaman opaktır; yalnız dışa taşan yumuşak gölgesi değişir.
  var sceneLight = 0.5;
  function applySceneLight(light) {
    sceneLight = Math.max(0, Math.min(1, light));
    if (!document.body || document.body.className.indexOf('glass') < 0) return;
    var alpha = (0.3 + 0.55 * sceneLight).toFixed(2);
    textBackground = 'rgba(10, 10, 10, ' + alpha + ')';
    var shadow = '0 0 ' + Math.round(14 + 22 * sceneLight) + 'px ' + Math.round(2 + 8 * sceneLight) + 'px rgba(10, 10, 10, ' + (0.5 + 0.4 * sceneLight).toFixed(2) + ')';
    $('subtitle-cover').style.setProperty('box-shadow', shadow, 'important');
  }

  // Nino (buzlu zemin): bilgisayar altyazının arkasındaki sahnenin bulanık halini gönderir; örtünün zemini o olur
  // (siyah kutu değil, sahnenin buzlu cam görünümü; İngilizce bulanıklıkta kaybolur). Yoksa koyu zemin kalır.
  function applyCoverImage(cover) {
    var el = $('subtitle-cover');
    if (cover && document.body && document.body.className.indexOf('glass') >= 0) {
      el.style.setProperty('background', 'linear-gradient(rgba(0, 0, 0, 0.16), rgba(0, 0, 0, 0.16)), url(data:image/jpeg;base64,' + cover + ') center / 100% 100% no-repeat', 'important');
      el.style.setProperty('box-shadow', 'none', 'important');
      document.body.classList.add('frosted');
    } else {
      el.style.removeProperty('background');
      document.body.classList.remove('frosted');
    }
  }

  function showSubtitle(text, duration, box, paragraphs, replaces) {
    var now = Date.now();
    var current = rawText('subtitle-text');
    // Önceki satır kısa göründüyse yeni satırın üstünde kalır. Aynı cümlenin başka bir okunuşu (ya da yeniden gelen
    // satır) ikinci çeviri gibi durmasın diye üste çıkmaz; görev paneli gibi çok satırlı yazılar da üst üste binmez.
    if (replacesCurrent(replaces, paragraphs)) {
      // Üstteki daha eski satırlar olduğu gibi kalır.
    } else if (stackPrevious && $('subtitle').className !== 'hidden' && current && now - shownAt < STACK_WITHIN_MS &&
        !paragraphs && !shownParagraphs && !sameLine(current, text)) {
      showPrevious(current);
    } else {
      hidePrevious();
    }
    shownAt = now;
    shownParagraphs = !!paragraphs;
    holdUntil = shownAt + Math.min(HOLD_MAX_MS, 2000 + text.length * 60);
    currentBox = validBox(box);
    setLineText('subtitle-text', text, paragraphs, fontBase, true);
    // Nino: "start" sağdan sola (Arapça) satırda sağa yaslar.
    $('subtitle-text').style.textAlign = paragraphs ? 'start' : '';
    $('subtitle').className = '';
    layout();
    notePlace();
    clearTimeout(hideTimer);
    // Geçersiz ya da çok kısa süre yazıyı gösterir göstermez kaldırmasın.
    var ms = duration > 0 ? Math.max(MIN_VISIBLE_MS, duration) : Math.min(8000, 2000 + text.length * 60);
    hideTimer = setTimeout(function () { hideSubtitle('timer'); }, ms);
  }

  // Yazının ekrandaki gerçek yeri ve görünürlüğü (tanı için).
  function notePlace() {
    var el = $('subtitle-text');
    var rect = el.getBoundingClientRect();
    var height = document.documentElement.clientHeight || window.innerHeight || 0;
    diag.place = 'y ' + Math.round(rect.top) + '-' + Math.round(rect.bottom) + '/' + height + ' ' +
      window.getComputedStyle($('subtitle')).visibility + ' f' + window.getComputedStyle(el).fontSize;
    renderDiag();
  }

  // reason: yazıyı neyin kaldırdığı; panelde görünen süreyle birlikte sebebi gösterir.
  function hideSubtitle(reason) {
    clearTimeout(hideTimer);
    if ($('subtitle').className !== 'hidden') {
      diag.lastHide = (reason || '?') + ' ' + (Date.now() - shownAt) + 'ms';
      renderDiag();
    }
    $('subtitle').className = 'hidden';
    $('subtitle-cover').className = 'hidden';
    hidePrevious();
  }

  // Bilgisayardan gelen "temizle": yazı okunacak kadar görünmediyse kalan süre dolunca kaldırılır.
  function onClear() {
    diag.clears++;
    renderDiag();
    var left = holdUntil - Date.now();
    if (left <= 0 || $('subtitle').className === 'hidden') return hideSubtitle('clear');
    clearTimeout(hideTimer);
    hideTimer = setTimeout(function () { hideSubtitle('clear-held'); }, left);
  }

  // Bilgisayar, daktilo efektinde büyüyen ya da belirirken yarım okunan cümlenin her okunuşunu ayrı çevirir; bunlar
  // üst üste yığılınca aynı cümlenin iki üç çevirisi görünüyordu. "replace" ile gelen satır öncekinin yerine geçer.
  function replacesCurrent(replaces, paragraphs) {
    return replaces === true && !paragraphs && $('subtitle').className !== 'hidden' && !!$('subtitle-text').textContent;
  }

  // Önceki satır üste çıkar. Orada hâlâ görünen bir satır varsa o da bir üst sıraya (iki önceki) kayar; en çok üç satır.
  function showPrevious(text) {
    var older = $('subtitle-prev');
    var olderText = rawText('subtitle-prev-text');
    if (older.className === '' && olderText && !sameLine(olderText, text)) {
      showSlot('subtitle-prev2', olderText);
    } else {
      hideSlot('subtitle-prev2');
    }
    showSlot('subtitle-prev', text);
  }

  function showSlot(id, text) {
    var timers = previousTimers[id];
    clearTimeout(timers[0]);
    clearTimeout(timers[1]);
    setLineText(id + '-text', text, false, Math.round(fontBase * 0.8));
    $(id).className = '';
    timers[0] = setTimeout(function () {
      $(id).className = 'fading';
      timers[1] = setTimeout(function () { hideSlot(id); }, PREVIOUS_FADE_MS);
    }, PREVIOUS_HOLD_MS);
  }

  function hideSlot(id) {
    var timers = previousTimers[id];
    clearTimeout(timers[0]);
    clearTimeout(timers[1]);
    $(id).className = 'hidden';
  }

  function hidePrevious() {
    hideSlot('subtitle-prev');
    hideSlot('subtitle-prev2');
  }

  // Büyük-küçük harf ve noktalama dışında aynı mı, ya da biri ötekinin başı/devamı mı ("Kapı" → "Kapı daha fazla…").
  function sameLine(a, b) {
    var x = plainText(a);
    var y = plainText(b);
    if (!x || !y) return x === y;
    // Boşluklar karşılaştırmaya girmez (OCR boşluğu bazen yutar ya da fazladan koyar). Tek sözcüklük satır ise
    // ancak öteki satırda tam sözcük olarak geçerse aynıdır: "No!" ve "Not now!" farklı altyazılardır.
    var cx = x.replace(/ /g, '');
    var cy = y.replace(/ /g, '');
    if (cx === cy) return true;
    if (cx.indexOf(cy) >= 0) return y.indexOf(' ') >= 0 || (' ' + x + ' ').indexOf(' ' + y + ' ') >= 0;
    if (cy.indexOf(cx) >= 0) return x.indexOf(' ') >= 0 || (' ' + y + ' ').indexOf(' ' + x + ' ') >= 0;
    return false;
  }

  function plainText(text) {
    // Nino: Arapça noktalama (، ؟ ؛) da yok sayılır.
    return String(text).toLowerCase().replace(/[.,!?;:…"'“”‘’«»()\[\]\-–—،؟؛]+/g, '').replace(/\s+/g, ' ').trim();
  }

  // --- Ekranı çevir ---
  // Bilgisayar ekranın tamamını okuyup her yazı grubunun çevirisini yeriyle gönderir. Her çeviri kendi İngilizce
  // yazısını örter; yazı boyu o yazının satır yüksekliğinden seçilir, Türkçe uzun gelirse sığana kadar küçülür.


  // Ekran çevirisinin durumu. Nino'nun yazı yardımcıları (setRich, setDirection) bundan sonra durur: ekran çevirisi
  // onları kullanır ve scripts/tv-screen.test.js bu satırdan hideScreen'e kadarki bölümü tarayıcıda çalıştırır.
  var screenTimer = null;

  // Nino: çevirideki düğme simgeleri (✕ ○ △ □ ●, L1–R3) oyundaki gibi yuvarlak rozet olarak çizilir.
  var ICON_RE = /(✕|○|△|□|●|↑|↓|←|→|✜|▦|◆|[\u24B6-\u24CF]|\b[LR][123]\b|\bOPTIONS\b|\bTOUCHPAD\b)/;
  // Nino: Arapça çeviri sağdan sola dizilir. Yön Arap harfinden seçilir ("auto" değil): satır Latin harfli
  // konuşmacı adıyla başlasa da ("ATREUS: …") sağdan başlar.
  var ARABIC_RE = /[\u0620-\u064A\u066E-\u06D3\u06FA-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]/;
  function setDirection(el, text) {
    if (ARABIC_RE.test(String(text))) el.setAttribute('dir', 'rtl'); else el.removeAttribute('dir');
  }

  // Nino: dört yüz tuşu kendi çizimimiz (SVG). Sony'nin dosyası ya da logosu değildir. Cam gibi koyu bir tuş:
  // üstten alta koyulaşan yüzey, üstte ışık yansıması, ince parlak kenar; şekil kendi renginde hafifçe parlar.
  // Ortak gradyanlar sayfaya bir kez eklenir (ensureFaceDefs); her simge yalnız onlara başvurur.
  var FACE_SHAPES = {
    '✕': ['#a9cbff', '<path d="M35 35L65 65M65 35L35 65"/>'],
    '○': ['#ff9494', '<circle cx="50" cy="50" r="17"/>'],
    '△': ['#6eebc0', '<path d="M50 31.5L69 64H31Z"/>'],
    '□': ['#ffa8e4', '<rect x="33" y="33" width="34" height="34" rx="2.5"/>']
  };
  function faceSvg(tok) {
    var s = FACE_SHAPES[tok];
    var stroke = ' fill="none" stroke="' + s[0] + '" stroke-linecap="round" stroke-linejoin="round"';
    return '<svg viewBox="0 0 100 100" aria-hidden="true">' +
      '<circle cx="50" cy="50" r="47" fill="url(#nino-key-face)"/>' +
      '<circle cx="50" cy="50" r="45.5" fill="none" stroke="url(#nino-key-rim)" stroke-width="3"/>' +
      '<ellipse cx="50" cy="27" rx="31" ry="15" fill="url(#nino-key-gloss)"/>' +
      '<g' + stroke + ' stroke-width="15" opacity="0.22">' + s[1] + '</g>' +
      '<g' + stroke + ' stroke-width="8">' + s[1] + '</g></svg>';
  }
  var faceDefsAdded = false;
  function ensureFaceDefs() {
    if (faceDefsAdded || !document.body) return;
    faceDefsAdded = true;
    var holder = document.createElement('div');
    holder.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden';
    holder.innerHTML = '<svg width="0" height="0" aria-hidden="true"><defs>' +
      '<radialGradient id="nino-key-face" cx="50%" cy="30%" r="75%">' +
        '<stop offset="0" stop-color="#3b3e48"/><stop offset="0.6" stop-color="#1c1d23"/><stop offset="1" stop-color="#0c0d10"/></radialGradient>' +
      '<linearGradient id="nino-key-rim" x1="0" y1="0" x2="0" y2="1">' +
        '<stop offset="0" stop-color="#fff" stop-opacity="0.75"/><stop offset="0.55" stop-color="#fff" stop-opacity="0.18"/>' +
        '<stop offset="1" stop-color="#fff" stop-opacity="0.35"/></linearGradient>' +
      '<linearGradient id="nino-key-gloss" x1="0" y1="0" x2="0" y2="1">' +
        '<stop offset="0" stop-color="#fff" stop-opacity="0.22"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>' +
      '</defs></svg>';
    document.body.appendChild(holder);
  }

  function setRich(el, text) {
    el.textContent = '';
    setDirection(el, text);
    var parts = String(text).split(ICON_RE);
    for (var i = 0; i < parts.length; i++) {
      if (!parts[i]) continue;
      if (i % 2 === 1) {
        var icon = document.createElement('span');
        // L3/R3 (çubuğa basma) oyundaki gibi daire; L1/L2/R1/R2 ve OPTIONS yuvarlatılmış kutu.
        var tok = parts[i];
        if (/^[\u24B6-\u24CF]$/.test(tok)) {
          // Harita işareti: sarı daire içinde harf.
          icon.className = 'btn-icon marker';
          tok = String.fromCharCode(tok.charCodeAt(0) - 0x24B6 + 65);
        } else if (/^[↑↓←→✜]$/.test(tok)) {
          icon.className = 'btn-icon dpad';
        } else if (tok === '▦' || tok === 'TOUCHPAD') {
          icon.className = 'btn-icon pill pad';
          tok = '';
        } else {
          icon.className = /^[LR][12]$/.test(tok) || tok.length > 2 ? 'btn-icon pill' : (/^[LR]3$/.test(tok) ? 'btn-icon stick' : 'btn-icon');
        }
        if (FACE_SHAPES[tok]) {
          ensureFaceDefs();
          icon.className = 'btn-icon face';
          icon.setAttribute('data-key', tok);
          icon.innerHTML = faceSvg(tok);
        } else {
          icon.textContent = tok;
        }
        el.appendChild(icon);
      } else {
        el.appendChild(document.createTextNode(parts[i]));
      }
    }
  }
  var SCREEN_PAD = 0.004;
  var SCREEN_PAD_X = 0.018;
  var SCREEN_PAD_Y = 0.008;
  var SCREEN_MIN_FONT = 14;
  // Nino: balonun içine sığdırılan çevirinin en küçük yazısı (px).
  var BUBBLE_MIN_FONT = 11;

  // Yalnız aşağıdaki bağımsız kutular büyümeyi sınırlar; kaynakta zaten üst üste olan
  // kutuların yerini değiştirmeyiz. Aynı hesap bütün sonuçlar için yapılır, sıra önemli değildir.
  function screenBottom(items, box, left, width, screenWidth, screenHeight) {
    var bottom = screenHeight;
    for (var j = 0; j < items.length; j++) {
      var other = items[j];
      var next = validBox(other && other.box);
      if (!next || !other.text || next.top < box.bottom) continue;
      // Nino: komşunun örtüsü de solda ve dikeyde geniş paylıdır (showScreen ile aynı).
      var nextLeft = Math.max(0, next.left - SCREEN_PAD_X) * screenWidth;
      var nextWidth = Math.max(80, (Math.min(1, next.right + SCREEN_PAD) * screenWidth - nextLeft));
      if (left < nextLeft + nextWidth && left + width > nextLeft)
        bottom = Math.min(bottom, Math.max(0, next.top - SCREEN_PAD_Y) * screenHeight);
    }
    return bottom;
  }

  function showScreen(items, duration, overlay) {
    var host = $('screen');
    // Nino: telefon balonlarının örtüleri sık gelir (telefon elde sallanır). Yazılar aynıysa silinip yeniden çizilmez
    // (yazı boyu zıplıyordu); yalnız yerleri yumuşakça güncellenir.
    if (moveBubbles(host, items, duration)) return;
    // Panel zaten görünüyorsa (yeni mesaj, kaydırma) zemin yeniden belirmez; yalnız balonlar yumuşakça gelir.
    var panelShown = (host.className === '' || host.className === 'steady') && !!host.querySelector('.item.backdrop');
    // "Ekran çevriliyor…" yazısı sonuçların üstünde kalmasın. Nino: köşe/ipucu çevirisi (overlay) gelince altyazı
    // silinmez; ikisi aynı anda görünür.
    if (overlay !== true) hideSubtitle('screen');
    host.innerHTML = '';
    host.className = panelShown ? 'steady' : '';
    var width = window.innerWidth || 1920;
    var height = window.innerHeight || 1080;
    for (var i = 0; i < (items || []).length; i++) {
      var item = items[i];
      var box = validBox(item && item.box);
      // Nino: yazısız zemin (telefonun yanındaki mesajlaşma paneli).
      if (box && item.backdrop === true && typeof item.fill === 'string' && /^#[0-9a-fA-F]{6}$/.test(item.fill)) {
        var panelEl = document.createElement('div');
        panelEl.className = 'item backdrop';
        panelEl.setAttribute('data-text', '');
        var alpha = typeof item.alpha === 'number' ? item.alpha : 1;
        panelEl.style.background = 'rgba(' + parseInt(item.fill.substr(1, 2), 16) + ',' + parseInt(item.fill.substr(3, 2), 16) + ','
          + parseInt(item.fill.substr(5, 2), 16) + ',' + alpha + ')';
        panelEl.style.left = (box.left * 100) + '%';
        panelEl.style.top = (box.top * 100) + '%';
        panelEl.style.width = ((box.right - box.left) * width) + 'px';
        panelEl.style.height = ((box.bottom - box.top) * height) + 'px';
        // Nino: panelin sağ alt köşesinde, mini haritanın altındakinin aynısı, daha saydam logo.
        var mark = document.createElement('img');
        mark.className = 'panel-badge';
        mark.src = 'nino-badge.png';
        mark.alt = '';
        panelEl.appendChild(mark);
        // Nino (kullanıcı isteği): panelin en üstünde ortada gönderenin adı, telefonun başlığı gibi.
        if (typeof item.text === 'string' && item.text) {
          var head = document.createElement('div');
          head.className = 'panel-title';
          head.textContent = item.text;
          var headLine = typeof item.line === 'number' && item.line > 0 ? item.line * height : 24;
          head.style.fontSize = Math.max(BUBBLE_MIN_FONT, Math.round(headLine * 1.05)) + 'px';
          panelEl.appendChild(head);
        }
        host.appendChild(panelEl);
        continue;
      }
      if (!box || !item.text) continue;
      var el = document.createElement('div');
      el.className = item.paragraphs === true ? 'item paragraphs' : 'item';
      // Nino: kutusuz sade yazı (oyunun görev yazısının altındaki Türkçesi): pay yok, sola yaslı, yalnız gölge.
      if (item.plain === true) el.className += ' plain';
      // Nino: harita kartının Türkçesi, oyunun kartı gibi (style.css .item.card).
      if (item.card === true) el.className += ' card';
      if (item.italic === true) el.className += ' italic';
      // Nino: oyunun kutusunun (telefon mesaj balonu) tam üstü: aynı zemin ve yazı rengiyle, kutunun içine sığdırılır.
      var fill = typeof item.fill === 'string' && /^#[0-9a-fA-F]{6}$/.test(item.fill) ? item.fill : null;
      if (fill) {
        el.className = 'item bubble';
        el.setAttribute('data-text', item.text);
        setRich(el, item.text);
        var ink = typeof item.ink === 'string' && /^#[0-9a-fA-F]{6}$/.test(item.ink) ? item.ink : '#1c1c1e';
        el.style.background = fill;
        if (typeof item.alpha === 'number' && item.alpha >= 0 && item.alpha < 1) {
          el.style.background = 'rgba(' + parseInt(fill.substr(1, 2), 16) + ',' + parseInt(fill.substr(3, 2), 16) + ','
            + parseInt(fill.substr(5, 2), 16) + ',' + item.alpha + ')';
        }
        if (item.side === true) {
          el.className += ' side';
          // Balonlar sırayla, hafifçe yukarı kayarak gelir.
          el.style.animationDelay = (Math.min(i, 8) * 60) + 'ms';
        }
        el.style.color = ink;
        el.style.left = (box.left * 100) + '%';
        el.style.top = (box.top * 100) + '%';
        var bubbleWidth = Math.max(40, (box.right - box.left) * width);
        var bubbleHeight = Math.max(12, (box.bottom - box.top) * height);
        el.style.width = bubbleWidth + 'px';
        el.style.height = bubbleHeight + 'px';
        var bubbleLine = typeof item.line === 'number' && item.line > 0 ? item.line * height : bubbleHeight;
        var bubbleSize = Math.max(BUBBLE_MIN_FONT, Math.min(64, Math.round(bubbleLine * 0.98)));
        el.style.fontSize = bubbleSize + 'px';
        // Eğik tutulan telefonun balonları eğiktir: Türkçe de aynı açıyla, ortasından döner.
        if (typeof item.angle === 'number' && Math.abs(item.angle) >= 0.3 && Math.abs(item.angle) <= 30) {
          el.style.transform = 'rotate(' + item.angle + 'deg)';
        }
        host.appendChild(el);
        // Türkçe çoğu zaman İngilizceden uzundur: balondan taşmasın diye yazı küçülür.
        while ((el.scrollHeight > bubbleHeight + 1 || el.scrollWidth > bubbleWidth + 1) && bubbleSize > BUBBLE_MIN_FONT) {
          bubbleSize -= 1;
          el.style.fontSize = bubbleSize + 'px';
        }
        continue;
      }
      setRich(el, item.text);
      // Nino: oyunun süslü İngilizce harfleri OCR kutusundan taşar; örtü solda ve dikeyde daha geniş,
      // sağda (düğme simgesine doğru) dar tutulur ki simge örtülmesin.
      var left = Math.max(0, box.left - SCREEN_PAD_X);
      var top = Math.max(0, box.top - SCREEN_PAD_Y);
      var boxHeight = (box.bottom - box.top + 2 * SCREEN_PAD_Y) * height;
      el.style.left = (left * 100) + '%';
      el.style.top = (top * 100) + '%';
      var itemWidth = Math.max(80, (Math.min(1, box.right + SCREEN_PAD) - left) * width);
      el.style.width = itemWidth + 'px';
      if (box.left > 0.5) el.style.textAlign = 'right';
      // Bir piksel pay, tarayıcının kesirli koordinat/scrollHeight yuvarlamasını karşılar.
      var available = Math.max(0, Math.floor(screenBottom(items, box, left * width, itemWidth, width, height) - top * height) - 1);
      el.style.minHeight = Math.min(Math.round(boxHeight), available) + 'px';
      var line = typeof item.line === 'number' && item.line > 0 ? item.line * height : box.bottom * height - box.top * height;
      var size = Math.max(SCREEN_MIN_FONT, Math.min(96, Math.round(line * 0.95)));
      el.style.fontSize = size + 'px';
      host.appendChild(el);
      // Türkçe çoğu zaman İngilizceden uzundur: kutu biraz uzayabilir, daha fazlası için yazı küçülür.
      var limit = Math.min(available, Math.max(boxHeight * 1.5, line * 2.6));
      while (el.scrollHeight > limit && size > SCREEN_MIN_FONT) {
        size = Math.max(SCREEN_MIN_FONT, size - 2);
        el.style.fontSize = size + 'px';
      }
      // En küçük okunabilir boyutta da sığmayan metni kesmeyiz/gizlemeyiz.
      // Bu uç durumda eski doğal büyüme davranışı korunur.
    }
    clearTimeout(screenTimer);
    screenTimer = setTimeout(hideScreen, duration || 20000);
  }

  function moveBubbles(host, items, duration) {
    var list = items || [];
    if (!list.length || host.className === 'hidden' || host.className === 'leaving' || host.children.length !== list.length) return false;
    for (var i = 0; i < list.length; i++) {
      var child = host.children[i];
      if (!list[i] || !list[i].fill || !list[i].box || child.getAttribute('data-text') !== (list[i].text || '')) return false;
    }
    for (var j = 0; j < list.length; j++) {
      var box = validBox(list[j].box);
      if (!box) continue;
      host.children[j].style.left = (box.left * 100) + '%';
      host.children[j].style.top = (box.top * 100) + '%';
    }
    clearTimeout(screenTimer);
    screenTimer = setTimeout(hideScreen, duration || 20000);
    return true;
  }

  function hideScreen() {
    clearTimeout(screenTimer);
    var host = $('screen');
    // Nino: telefonun yanındaki panel yumuşakça solar (birden kaybolmaz).
    if (host.className !== 'hidden' && host.querySelector('.item.side, .item.backdrop')) {
      host.className = 'leaving';
      screenTimer = setTimeout(function () {
        host.className = 'hidden';
        host.innerHTML = '';
      }, 320);
      return;
    }
    host.className = 'hidden';
    host.innerHTML = '';
  }

  // --- Ek alanlar ---
  // Bilgisayar altyazının yanında ekranın köşelerindeki yazıları da (görev, telefon mesajı, bildirim) sürekli okur ve
  // her alanın çevirisini "region" olayıyla gönderir: {id, text, box, line}. Çeviri İngilizce yazının yerinde küçük bir
  // kutuda durur; ekranın sağ yarısındaki kutu sağa, alt yarısındaki alta yaslanır, Türkçe uzun gelirse kutu ekranın
  // içine doğru büyür. Boş "text" o alanın kutusunu, "region-clear" hepsini kaldırır. Ana altyazıya dokunulmaz.

  var regionBoxes = {};
  var REGION_PAD = 0.004;
  var REGION_MIN_FONT = 18;
  var REGION_MAX_FONT = 44;
  // Nino: ekranın alt yarısındaki KISA yazı (oyundaki telefonun sağ alttaki kısa mesaj bildirimi gibi) yerinde
  // kapatılmaz: çeviri yazının hemen ÜSTÜNDE, yarı saydam kutuda durur, asıl mesaj da görünür kalır. Eskiden simsiyah
  // kutu mesajın yarısını kapatıyordu. Uzun yazılar (açık telefon ekranı, görev metni) eskisi gibi yerinde çevrilir.
  var REGION_BESIDE_MAX_HEIGHT = 0.16;

  // Kutunun yüksekliği kısaysa ve alt yarıdaysa çeviri yazının üstüne konur.
  function regionBeside(box) {
    return (box.top + box.bottom) / 2 > 0.5 && (box.bottom - box.top) <= REGION_BESIDE_MAX_HEIGHT;
  }

  function showRegion(data) {
    var id = data && typeof data.id === 'string' ? data.id : '';
    if (!id) return;
    var box = validBox(data.box);
    if (!data.text || !box) return hideRegion(id);
    var el = regionBoxes[id];
    if (!el) {
      el = document.createElement('div');
      el.className = 'region';
      $('regions').appendChild(el);
      regionBoxes[id] = el;
    }
    $('regions').className = '';
    var width = window.innerWidth || 1920;
    var height = window.innerHeight || 1080;
    el.textContent = data.text;
    el.style.left = el.style.right = el.style.top = el.style.bottom = '';
    if ((box.left + box.right) / 2 > 0.5) {
      el.style.right = (Math.max(0, 1 - box.right - REGION_PAD) * 100) + '%';
    } else {
      el.style.left = (Math.max(0, box.left - REGION_PAD) * 100) + '%';
    }
    var beside = regionBeside(box);
    el.className = beside ? 'region beside' : 'region';
    if (beside) {
      // Kutunun alt kenarı asıl yazının üst kenarına oturur (araya ince bir boşluk).
      el.style.bottom = (Math.min(1, 1 - box.top + REGION_PAD * 2) * 100) + '%';
    } else if ((box.top + box.bottom) / 2 > 0.5) {
      el.style.bottom = (Math.max(0, 1 - box.bottom - REGION_PAD) * 100) + '%';
    } else {
      el.style.top = (Math.max(0, box.top - REGION_PAD) * 100) + '%';
    }
    var boxWidth = (box.right - box.left + 2 * REGION_PAD) * width;
    el.style.minWidth = Math.round(boxWidth) + 'px';
    el.style.maxWidth = Math.round(Math.max(boxWidth, width * 0.3)) + 'px';
    var line = typeof data.line === 'number' && data.line > 0 ? data.line * height : 30;
    el.style.fontSize = Math.max(REGION_MIN_FONT, Math.min(REGION_MAX_FONT, Math.round(line * 0.9))) + 'px';
  }

  function hideRegion(id) {
    var el = regionBoxes[id];
    if (!el) return;
    delete regionBoxes[id];
    $('regions').removeChild(el);
  }

  function hideRegions() {
    for (var id in regionBoxes) {
      if (Object.prototype.hasOwnProperty.call(regionBoxes, id)) $('regions').removeChild(regionBoxes[id]);
    }
    regionBoxes = {};
    $('regions').className = 'hidden';
  }

  // Konum hem CouchSubs uygulamasından hem kumandanın oklarıyla ayarlanır. Kumandayla
  // seçilen konum, uygulamadaki ayar değişene kadar korunur (son değiştiren geçerlidir).
  // Alttan en az %3: ekran kenarı taşan (overscan) TV'lerde altyazının alt satırı kesilmesin.
  var BOTTOM_MIN_PERCENT = 3;

  function setBottom(percent) {
    bottomPercent = Math.max(BOTTOM_MIN_PERCENT, Math.min(85, percent));
    layout();
  }

  var SIDE_MIN = 0.05;

  // Altyazıyı seçilen yerleşime göre konumlar. İngilizce altyazının yeri bilinmiyorsa sabit yükseklik kullanılır.
  function layout() {
    var el = $('subtitle');
    var cover = $('subtitle-cover');
    var box = placement === 'fixed' ? null : currentBox;
    el.style.left = '8%';
    el.style.right = '8%';
    el.style.top = 'auto';
    el.style.bottom = bottomPercent + '%';
    cover.className = 'hidden';
    document.body.classList.remove('covering');
    $('subtitle-text').style.background = textBackground;
    // Altyazı yokken (ör. ayar değişince yeniden yerleşirken) örtü tek başına boş siyah kutu olarak kalmasın.
    if (!box || el.className === 'hidden') return;

    var height = document.documentElement.clientHeight || window.innerHeight || 1080;
    var gap = Math.round(height * 0.012);
    var mode = placement;
    // Ekranın kenarında yer yoksa öbür yana geçilir.
    if (mode === 'below' && box.bottom > 0.88) mode = 'above';
    if (mode === 'above' && box.top < 0.12) mode = 'below';

    // Yatayda İngilizce satırın ortasına hizalanır; yanlarda güvenli alan (1920'de 96 piksel, %5) kadar boşluk kalır.
    var center = (box.left + box.right) / 2;
    var half = Math.max(0.3, Math.min(center, 1 - center));
    el.style.left = (Math.max(SIDE_MIN, center - half) * 100) + '%';
    el.style.right = (Math.max(SIDE_MIN, 1 - center - half) * 100) + '%';

    if (autoSize) {
      // Nino: oyunun tek satırlık altyazı yüksekliği bu oturumda öğrenilir (son kutuların alçak olanları); kutunun
      // kaç satır olduğu buna göre sayılır. Eskiden sabit bir satır aralığı (%3,5) varsayılıyordu: satırları sık olan
      // oyunda (Mafia) iki satırlık altyazı tek satır sanılıp yazı iki katına çıkıyor, boy satırdan satıra zıplıyordu.
      // Boy, son birkaç satırın ortancasıdır (zıplamaz) ve okunaklı olsun diye en az 27 pikseldir.
      var boxHeight = box.bottom - box.top;
      autoHeights.push(boxHeight);
      if (autoHeights.length > 24) autoHeights.shift();
      var sortedHeights = autoHeights.slice().sort(function (a, b) { return a - b; });
      var single = sortedHeights[Math.floor((sortedHeights.length - 1) * 0.3)];
      var lineCount = Math.max(1, Math.round(boxHeight / Math.max(0.01, single)));
      // Kullanıcı isteği: oyunun yazısından %5, sonra %3, sonra %5 daha büyük (0.9 → 0.945 → 0.973 → 1.022).
      var measured = Math.round(boxHeight * height / lineCount * 1.022);
      autoSizes.push(measured);
      if (autoSizes.length > 7) autoSizes.shift();
      var sortedSizes = autoSizes.slice().sort(function (a, b) { return a - b; });
      var size = sortedSizes[Math.floor(sortedSizes.length / 2)];
      size = Math.max(27, Math.min(Math.round(height * 0.0508), size));
      $('subtitle-text').style.fontSize = size + 'px';
      $('subtitle-prev-text').style.fontSize = Math.round(size * 0.8) + 'px';
      $('subtitle-prev2-text').style.fontSize = Math.round(size * 0.8) + 'px';
    }
    if (mode === 'cover') {
      // İngilizce yazı koyu bir zeminle örtülür, çeviri onun ortasına gelir.
      var middle = (1 - (box.top + box.bottom) / 2) * height;
      el.style.bottom = Math.max(0, Math.round(middle - $('subtitle-text').offsetHeight / 2)) + 'px';
      placeCover(cover, box, $('subtitle-text').getBoundingClientRect());
      // Zemini örtü verir; çevirinin kendi yarı saydam zemini örtünün üstünde ikinci bir kutu gibi görünmesin.
      $('subtitle-text').style.background = 'transparent';
      // Nino: örtülürken oyunun kendi altyazısı gibi görünsün: tek siyah kutu, içinde düz beyaz yazı (tema çerçevesi yok).
      document.body.classList.add('covering');
    } else if (mode === 'above') {
      el.style.bottom = Math.round((1 - box.top) * height + gap) + 'px';
    } else {
      el.style.bottom = 'auto';
      el.style.top = Math.round(box.bottom * height + gap) + 'px';
    }
    keepOnScreen(el, cover);
  }

  // Örtü İngilizce satırın kutusunu (biraz paylı) kaplar. Türkçe daha uzun ya da daha çok satırsa örtü çevirinin
  // kutusunu da içine alacak kadar büyür: eskiden çevirinin yarı saydam zemini siyah örtüden taşıyor, ekranda boyları
  // farklı iki kutu görünüyordu. Örtü çevirinin zeminini tamamen kapladığından ikisi tek bir siyah kutu gibi görünür.
  // Nino: örtünün payı inceldi (kutu kalın görünmesin).
  var COVER_PAD = 0.012;
  // Nino: yazı boyu İngilizce satırın yüksekliğine uydurulur (varsayılan açık).
  var autoSize = true;
  // Nino: otomatik boy için son kutu yükseklikleri ve ölçülen boylar (bkz. layout).
  var autoHeights = [];
  var autoSizes = [];

  function placeCover(cover, box, text) {
    var width = document.documentElement.clientWidth || window.innerWidth || 1920;
    var height = document.documentElement.clientHeight || window.innerHeight || 1080;
    var left = (box.left - COVER_PAD) * width;
    var top = (box.top - COVER_PAD) * height;
    var right = (box.right + COVER_PAD) * width;
    var bottom = (box.bottom + COVER_PAD) * height;
    if (text && text.width > 0 && text.height > 0) {
      left = Math.min(left, text.left);
      top = Math.min(top, text.top);
      right = Math.max(right, text.right);
      bottom = Math.max(bottom, text.bottom);
    }
    // Tam genişlik bandı: oyundaki İngilizce yazı yan yana taşsa da görünmesin diye örtü ekranın iki kenarına uzanır.
    if (bandShape) { left = 0; right = width; }
    cover.style.left = Math.round(left) + 'px';
    // Çeviri gibi alttan konumlanır: sayfanın yüksekliği sonradan değişirse (Android TV ölçeklemesi) ikisi birlikte kayar.
    cover.style.top = 'auto';
    cover.style.bottom = Math.round(height - bottom) + 'px';
    cover.style.width = Math.round(right - left) + 'px';
    cover.style.height = Math.round(bottom - top) + 'px';
    // Örtü telefondaki "Arka plan koyuluğu"na uyar: eskiden hep %97'ydi, kaydırıcı %0'da da kutu opak kalıyordu.
    // %100 tamamen opaktır; koyuluğu göndermeyen eski sürümlerde style.css'teki %97 geçerlidir.
    cover.style.background = coverBackground;
    cover.className = '';
  }

  // Bazı TV'lerde (Samsung, Android TV) sayfanın bildirdiği yükseklik ekranla uyuşmayabiliyor; altyazı ekranın
  // dışına düşerse hiç görünmüyordu. Yerleştirilen altyazı görünür alanda değilse sabit yüksekliğe döner.
  function keepOnScreen(el, cover) {
    var rect = el.getBoundingClientRect();
    var viewHeight = document.documentElement.clientHeight || window.innerHeight || 1080;
    var viewWidth = document.documentElement.clientWidth || window.innerWidth || 1920;
    var visible = rect.height > 0 && rect.top >= -2 && rect.bottom <= viewHeight + 2 && rect.right > 0 && rect.left < viewWidth;
    if (visible) return;
    el.style.left = '8%';
    el.style.right = '8%';
    el.style.top = 'auto';
    el.style.bottom = bottomPercent + '%';
    cover.className = 'hidden';
    document.body.classList.remove('covering');
    $('subtitle-text').style.background = textBackground;
  }

  // Çevirinin zemini (bilgisayardaki "Zemin koyuluğu"); boşsa style.css'teki varsayılan. Örtü varken saydam olur.
  var textBackground = '';

  // Örtünün zemini (koyuluğa göre, %100'de tamamen opak; boşsa style.css'teki %97) ve tam genişlik bant mı; eski
  // bilgisayar uygulamaları alanı göndermez, yazı kadar kalır.
  var coverBackground = '';
  var bandShape = false;

  // body'deki tek bir sınıfı açar ya da kapatır; diğerleri kalır. Eskiden className baştan yazılıyordu ve Android TV
  // katmanının 'overlay' sınıfı ilk style olayında siliniyordu.
  function setBodyClass(name, on) {
    var body = document.body;
    if (!body) return;
    var rest = (' ' + body.className + ' ').replace(' ' + name + ' ', ' ');
    body.className = (on ? rest + name : rest).replace(/^\s+|\s+$/g, '').replace(/\s+/g, ' ');
  }

  // Bilgisayardaki "Yazı rengi" seçimi; bilinmeyen değer gelirse renk değişmez.
  var TEXT_COLORS = { white: '#FFFFFF', yellow: '#FFE135' };

  function applyStyle(style) {
    // Nino: ayarlardan filigran kapatılabilir; alanı göndermeyen eski bilgisayar/telefon sürümlerinde rozet görünür.
    if (typeof style.watermark === 'boolean') setBodyClass('no-watermark', !style.watermark);
    if (style.fontSize) {
      fontBase = style.fontSize;
      var shown = rawText('subtitle-text');
      if ($('subtitle-text').rawText !== undefined && shown) setLineText('subtitle-text', shown, !!shownParagraphs, fontBase, true);
      else $('subtitle-text').style.fontSize = style.fontSize + 'px';
      $('subtitle-prev-text').style.fontSize = Math.round(style.fontSize * 0.8) + 'px';
      $('subtitle-prev2-text').style.fontSize = Math.round(style.fontSize * 0.8) + 'px';
    }
    if (PLACEMENTS[style.placement]) placement = style.placement;
    bandShape = style.backgroundShape === 'band';
    setBodyClass('band', bandShape);
    if (typeof style.background === 'number') {
      var alpha = Math.max(0, Math.min(100, style.background)) / 100;
      // Zemin çok saydamsa yazıya sert kontur eklenir (style.css, body.thin-bg).
      setBodyClass('thin-bg', alpha < 0.3);
      textBackground = 'rgba(0, 0, 0, ' + alpha + ')';
      coverBackground = style.background >= 100 ? '#000' : textBackground;
      // Nino (kullanıcı isteği, 21 Kasım 2026): tam siyah zemin yerine buzlu cam: koyu, hafif saydam geçiş, ince açık
      // kenar ve üstte parlama (style.css body.glass). Altındaki İngilizce sızmasın diye yeterince koyu.
      var glass = style.background >= 90;
      setBodyClass('glass', glass);
      if (glass) {
        textBackground = 'rgba(16, 16, 16, 0.8)';
        coverBackground = 'rgba(16, 16, 16, 0.86)';
      }
      $('subtitle-text').style.background = textBackground;
      $('subtitle-prev-text').style.background = 'rgba(0, 0, 0, ' + (alpha * 0.83).toFixed(2) + ')';
      $('subtitle-prev2-text').style.background = 'rgba(0, 0, 0, ' + (alpha * 0.83).toFixed(2) + ')';
    }
    // Ayarı göndermeyen bilgisayar (eski Windows sürümü, Mac) eski davranışı bekler: önceki satırlar üstte kalır.
    // Yoksa bir kez kapatılan ayar başka bilgisayara bağlanınca da kapalı kalırdı.
    stackPrevious = typeof style.stackPrevious === 'boolean' ? style.stackPrevious : true;
    save('stackPrevious', stackPrevious ? '1' : '0');
    if (!stackPrevious) hidePrevious();
    if (typeof style.bold === 'boolean') {
      $('subtitle-text').style.fontWeight = style.bold ? '700' : '600';
      $('subtitle-prev-text').style.fontWeight = style.bold ? '700' : '600';
      $('subtitle-prev2-text').style.fontWeight = style.bold ? '700' : '600';
    }
    if (typeof style.autoSize === 'boolean') autoSize = style.autoSize;
    // Nino: yazı tipi (style.css'te body[data-font=...] kuralları; fonts/ klasöründeki OFL yazı tipleri).
    if (typeof style.font === 'string') document.body.setAttribute('data-font', style.font);
    // Nino: altyazı teması (style.css'te body[data-theme=...] kuralları).
    if (typeof style.theme === 'string') document.body.setAttribute('data-theme', style.theme);
    if (TEXT_COLORS[style.textColor]) {
      $('subtitle-text').style.color = TEXT_COLORS[style.textColor];
      $('subtitle-prev-text').style.color = TEXT_COLORS[style.textColor];
      $('subtitle-prev2-text').style.color = TEXT_COLORS[style.textColor];
    }
    layout();
    if (style.bottomPercent >= 0 && String(style.bottomPercent) !== load('appBottom')) {
      save('appBottom', style.bottomPercent);
      save('bottom', '');
      setBottom(style.bottomPercent);
    }
  }

  function nudgeSubtitle(step) {
    // Yer oyundaki altyazıya bağlıysa kumandayla taşınmaz.
    if (placement !== 'fixed') return;
    setBottom(bottomPercent + step);
    save('bottom', bottomPercent);
    // Nereye gittiği görülsün diye yazı yoksa örnek gösterilir.
    if ($('subtitle').className === 'hidden') showSubtitle(t('positionPreview'), 2500);
  }

  // --- Sunucu bağlantısı (Server-Sent Events) ---

  function onEvent(name, handler) {
    eventSource.addEventListener(name, function (e) {
      lastActivity = Date.now();
      var data;
      try {
        data = JSON.parse(e.data);
      } catch (err) {
        noteError(name + ': bad json');
        return;
      }
      try {
        handler(data);
      } catch (err) {
        noteError(name + ': ' + err.message);
      }
    });
  }

  // Nino: sol alttaki rozet yalnız çeviri gerçekten sürerken görünür (bilgisayarda/telefonda fiş takılı, oyundan
  // yazı geliyor). Bağlı olmak yetmez: TV başka uygulamaya (YouTube) ya da başka HDMI'ya geçince, oyundan çıkınca ya da
  // fiş çekilince kaybolur. "started" ve her altyazı/ekran olayı rozeti açar; "stopped" ya da bağlantı kopması kapatır;
  // BADGE_IDLE_MS boyunca oyundan hiç yazı gelmezse de kapanır (eski bilgisayar sürümleri "stopped" göndermez).
  var BADGE_IDLE_MS = 90000;
  var badgeTimer = null;
  function setBadge(on) {
    clearTimeout(badgeTimer);
    badgeTimer = null;
    $('nino-badge').className = on ? '' : 'hidden';
    if (on) badgeTimer = setTimeout(function () { setBadge(false); }, BADGE_IDLE_MS);
  }

  function connect(address) {
    if (demoRunning()) stopDemo();
    if (eventSource) eventSource.close();
    if (address !== server) failures = 0;
    server = address;
    $('waiting').className = 'hidden';
    setStatus('st-server', address);
    if (!window.EventSource) {
      setStatus('st-conn', t('noEventSource'), 'bad');
      return;
    }
    setStatus('st-conn', t('connecting'), 'muted');
    eventSource = new EventSource(address + '/events');
    lastActivity = Date.now();
    eventSource.onopen = function () {
      lastActivity = Date.now();
      failures = 0;
      cancelScan();
      clearTimeout(dropTimer);
      dropTimer = null;
      setStatus('st-conn', t('connected'), 'ok');
    };
    eventSource.onerror = function () {
      // Bağlantı kısa süre içinde geri gelmezse eski altyazı ekranda asılı kalmasın. Bir anlık kopma yazıyı silmez.
      diag.drops++;
      renderDiag();
      if (dropTimer === null) {
        dropTimer = setTimeout(function () {
          dropTimer = null;
          hideSubtitle('drop');
          hideScreen();
          hideRegions();
          setBadge(false);
        }, DROP_HIDE_MS);
      }
      setStatus('st-conn', t('reconnecting'), 'bad');
      // Bilgisayarın adresi değişmiş ya da altyazı kaynağı başka cihaz olmuş olabilir.
      noteFailure();
    };
    // Bilgisayar 15 sn'de bir "ping" gönderir; gelmezse bağlantı yarı kopmuştur (bkz. watchConnection).
    eventSource.addEventListener('ping', function () {
      lastActivity = Date.now();
      pingSeen = true;
    });
    onEvent('subtitle', function (data) {
      diag.subtitles++;
      renderDiag();
      if (data.text) {
        if (typeof data.light === 'number') applySceneLight(data.light);
        applyCoverImage(typeof data.cover === 'string' ? data.cover : '');
        showSubtitle(data.text, data.duration, data.box, data.paragraphs === true, data.replace === true);
        setBadge(true);
        notePanelSubtitle(data.text);
      }
    });
    // Nino: bilgisayarda çeviri başladı; 7 sn sol üstte robot ve balon.
    onEvent('started', function () { showStartedNotice(); setBadge(true); });
    onEvent('stopped', function () { setBadge(false); hideSubtitle('drop'); hideScreen(); hideRegions(); });
    onEvent('clear', onClear);
    onEvent('screen', function (data) { showScreen(data.items, data.duration, data.overlay); if (data.items && data.items.length) setBadge(true); });
    onEvent('screen-clear', hideScreen);
    onEvent('region', showRegion);
    onEvent('region-clear', hideRegions);
    onEvent('style', applyStyle);
    onEvent('speech', function (data) { if (data.url) playSpeech(server + data.url); });
    onEvent('speech-stop', stopSpeech);
  }

  // --- Bağlantı bekçisi ---
  // Bazı TV'lerde bağlantı yarı kopar: EventSource "bağlı" görünür ama hiçbir şey gelmez, ya da kapanıp (CLOSED) bir daha
  // denemez. Altyazılar ancak kullanıcı uygulamaya dokununca geri geliyordu. Bekçi bu iki durumda bağlantıyı yeniden kurar.
  // Sessizlik sınırı yalnız ping gönderen bilgisayarlarda uygulanır (eski sürümler ping göndermez).

  var SILENCE_LIMIT_MS = 45000;
  var lastActivity = 0;
  var pingSeen = false;

  function watchConnection() {
    if (!server || !eventSource || demoRunning()) return;
    var closed = eventSource.readyState === 2;
    var silent = pingSeen && Date.now() - lastActivity > SILENCE_LIMIT_MS;
    if (closed || silent) {
      diag.drops++;
      renderDiag();
      pingSeen = false;
      connect(server);
    }
  }

  setInterval(watchConnection, 10000);

  // --- Türkçe dublaj ---
  // Bilgisayar her cümleyi seslendirip adresini gönderir; TV oyunun sesiyle birlikte çalar. Bilgisayar sıradakini
  // bu ses bitince gönderir; yine de üst üste gelirse eskisi kesilir.
  //
  // Ses Web Audio ile çalınır (katkı: Kadir Eker). <audio> öğesi TV'nin donanım medya oynatıcısını kullanır;
  // Samsung'da (TVWindow) ve LG'de (ext://hdmi) bu oynatıcı HDMI görüntüsüyle aynı yolu paylaştığından seslendirme
  // başlayınca oyun ekranı kararıyordu. Web Audio yalnız ses çıkışını kullanır. AudioContext olmayan ya da açılamayan,
  // sesi başlatmayan (askıda kalan) TV'de eski <audio> yoluna dönülür. Android TV sayfası <audio> ile çalar: HDMI'yi
  // TvView gösterir, karışmaz; platform.js de dublajı uygulama arka plandayken <audio> üzerinden susturur.
  //
  // Her cümlenin kaynağı bitince ayrılır; AudioContext bir süre boş kalınca kapatılır, sıradaki cümlede yeniden açılır.
  // <audio> yolunda her cümlenin oynatıcısı bitince, kesilince ya da hata verince bırakılır (src boşaltılıp load()).
  // Samsung'da duraklatılmış ya da bitmiş ama bırakılmamış oynatıcı sesi tutuyor, HDMI'deki oyunun ve PS5'in sesi
  // dublaj kapatılsa da uygulama kapanana dek gelmiyordu; açık kalan ses çıkışı aynı sorunu yapmasın.

  var SPEECH_FETCH_TIMEOUT_MS = 15000;
  var AUDIO_RESUME_WAIT_MS = 1500;
  var AUDIO_IDLE_MS = 10000;
  var speech = null; // çalan <audio>
  var speechSource = null; // çalan AudioBufferSourceNode
  var speechRequest = null;
  var speechToken = 0; // her yeni cümle ya da durdurma artırır; geç inen/çözülen eski ses çalınmaz
  var pendingToken = 0; // indirilip çözülmekte olan cümlenin numarası
  var audioContext = null;
  var audioIdleTimer = null;
  var webAudioFailed = false;

  function webAudio() {
    if (webAudioFailed || platform.speechElement) return null;
    if (audioContext) return audioContext;
    var Context = window.AudioContext || window.webkitAudioContext;
    if (!Context) return null;
    try { audioContext = new Context(); } catch (e) { audioContext = null; }
    return audioContext;
  }

  function playSpeech(url) {
    stopSpeech();
    clearTimeout(audioIdleTimer);
    var token = speechToken;
    var context = webAudio();
    if (!context) {
      playSpeechElement(url);
      return;
    }
    pendingToken = token;
    var request = new XMLHttpRequest();
    speechRequest = request;
    var failed = function () {
      if (speechRequest === request) speechRequest = null;
      if (token !== speechToken) return;
      pendingToken = 0;
      idleAudio();
    };
    request.onload = function () {
      if (speechRequest === request) speechRequest = null;
      if (token !== speechToken) return;
      if (request.status !== 200 || !request.response) return failed();
      decodeSpeech(context, request.response, function (buffer) {
        if (token !== speechToken) return;
        pendingToken = 0;
        startSource(context, buffer, url, token);
      }, failed);
    };
    request.onerror = failed;
    request.ontimeout = failed;
    try {
      request.open('GET', url, true);
      request.responseType = 'arraybuffer';
      request.timeout = SPEECH_FETCH_TIMEOUT_MS;
      request.send();
    } catch (e) {
      failed();
    }
  }

  // Eski WebKit'te decodeAudioData söz (Promise) döndürmez; yenisinde hem geri çağrı hem söz çalışır, biri sayılır.
  function decodeSpeech(context, data, onDecoded, onFailed) {
    var settled = false;
    var ok = function (buffer) {
      if (settled) return;
      settled = true;
      onDecoded(buffer);
    };
    var fail = function () {
      if (settled) return;
      settled = true;
      onFailed();
    };
    try {
      var promise = context.decodeAudioData(data, ok, fail);
      if (promise && promise.then) promise.then(ok, fail);
    } catch (e) {
      fail();
    }
  }

  function startSource(context, buffer, url, token) {
    var source = null;
    try {
      source = context.createBufferSource();
      source.buffer = buffer;
      source.connect(context.destination);
      source.onended = function () { releaseSource(source); };
      speechSource = source;
      source.start(0);
    } catch (e) {
      if (source) releaseSource(source);
      fallBackToElement(url);
      return;
    }
    if (context.state !== 'suspended' || !context.resume) return;
    // TV otomatik oynatmaya izin vermedi ya da ses çıkışını açmadı: kısa sürede başlamazsa <audio>'ya dönülür.
    try {
      var resumed = context.resume();
      if (resumed && resumed.then) resumed.then(null, function () { /* aşağıdaki bekleme karar verir */ });
    } catch (e) { /* yok */ }
    setTimeout(function () {
      if (token !== speechToken || speechSource !== source || context.state !== 'suspended') return;
      releaseSource(source);
      fallBackToElement(url);
    }, AUDIO_RESUME_WAIT_MS);
  }

  function fallBackToElement(url) {
    webAudioFailed = true;
    closeAudio();
    playSpeechElement(url);
  }

  function releaseSource(source) {
    if (speechSource === source) speechSource = null;
    source.onended = null;
    try { source.disconnect(); } catch (e) { /* yok */ }
    idleAudio();
  }

  function idleAudio() {
    clearTimeout(audioIdleTimer);
    if (!audioContext) return;
    audioIdleTimer = setTimeout(function () {
      if (speechSource || pendingToken === speechToken) return;
      closeAudio();
    }, AUDIO_IDLE_MS);
  }

  function closeAudio() {
    clearTimeout(audioIdleTimer);
    var context = audioContext;
    if (!context) return;
    try {
      var result = null;
      if (context.close) {
        audioContext = null;
        result = context.close();
      } else if (context.suspend) {
        result = context.suspend();
      }
      if (result && result.then) result.then(null, function () { /* yok */ });
    } catch (e) {
      audioContext = null;
    }
  }

  function playSpeechElement(url) {
    var audio = null;
    try {
      audio = new Audio(url);
      speech = audio;
      audio.addEventListener('ended', function () { releaseSpeech(audio); });
      audio.addEventListener('error', function () { releaseSpeech(audio); });
      var played = audio.play();
      if (played && played.catch) played.catch(function () { releaseSpeech(audio); });
    } catch (e) {
      if (audio) releaseSpeech(audio);
      speech = null;
    }
  }

  function releaseSpeech(audio) {
    if (speech === audio) speech = null;
    if (audio.couchsubsReleased) return;
    audio.couchsubsReleased = true;
    try { audio.pause(); } catch (e) { /* yok */ }
    try {
      audio.removeAttribute('src');
      audio.load();
    } catch (e) { /* yok */ }
  }

  function stopSpeech() {
    speechToken++;
    if (speechRequest) {
      var request = speechRequest;
      speechRequest = null;
      try { request.abort(); } catch (e) { /* yok */ }
    }
    if (speechSource) {
      var source = speechSource;
      try { source.stop(0); } catch (e) { /* yok */ }
      releaseSource(source);
    }
    if (speech) releaseSpeech(speech);
    idleAudio();
  }

  // --- Bilgisayarı ağda bulma ---
  // Bilgisayar TV uygulamasını açamıyorsa adres gelmez; kayıtlı adres de eskiyebilir (altyazı kaynağı başka cihaz oldu
  // ya da cihazın IP'si değişti). Uygulama o zaman ağı tarar: TV'nin kendi ağını (adresini söyleyebiliyorsa) ve kayıtlı
  // adresin ağını. Kayıtlı adres art arda FAILS_BEFORE_SCAN kez yanıt vermezse tarama kısa süre içinde başlar.

  var SERVER_PORT = 8787;
  var SCAN_PARALLEL = 24;
  var SCAN_TIMEOUT_MS = 1200;
  var SCAN_PAUSE_MS = 30000;
  var SCAN_SOON_MS = 3000;
  var FAILS_BEFORE_SCAN = 3;
  var scanTimer = null;
  var scanDue = 0;
  var scanning = false;
  var failures = 0;

  // Bekleyen tarama daha erken başlayacaksa korunur. Eskiden her bağlantı hatası zamanlayıcıyı baştan kuruyordu;
  // EventSource birkaç saniyede bir yeniden denediğinden 30 sn hiç dolmuyor, tarama hiç başlamıyordu.
  function scheduleScan(delay) {
    if (scanning) return;
    if (delay === undefined) delay = SCAN_PAUSE_MS;
    var due = Date.now() + delay;
    if (scanTimer !== null && scanDue <= due) return;
    clearTimeout(scanTimer);
    scanDue = due;
    scanTimer = setTimeout(function () {
      scanTimer = null;
      scanForServer();
    }, delay);
  }

  function cancelScan() {
    clearTimeout(scanTimer);
    scanTimer = null;
  }

  // Bağlantı hatası: kayıtlı adres art arda birkaç kez yanıt vermediyse ağ hemen taranır, yoksa bir süre beklenir.
  function noteFailure() {
    failures++;
    scheduleScan(failures >= FAILS_BEFORE_SCAN ? SCAN_SOON_MS : SCAN_PAUSE_MS);
  }

  function subnetOf(address) {
    var match = /^(?:https?:\/\/)?(\d+\.\d+\.\d+)\.\d+(?::\d+)?\/?$/.exec(address || '');
    return match ? match[1] : null;
  }

  // Bekleme ekranındaki durum satırı: TV'nin adresi (biliniyorsa; telefonda elle yazılabilir) ve aramanın sürdüğü.
  // Adres ayrıca sorulmaz, taramanın zaten sorduğu adres kullanılır.
  var tvAddress = null;

  function renderWaitingStatus() {
    var el = $('waiting-status');
    if (!el) return;
    el.textContent = (tvAddress ? t('waitingAddress').replace('%1', tvAddress) + ' · ' : '') + t('waitingSearching');
  }

  // Taranacak ağlar: TV'nin kendi ağı, sonra kayıtlı adresin ağı (aynıysa bir kez).
  function scanSubnets(done) {
    var fromServer = subnetOf(server);
    function finish(ip) {
      if (ip && ip !== tvAddress) {
        tvAddress = ip;
        renderWaitingStatus();
      }
      var list = [];
      var own = subnetOf(ip);
      if (own) list.push(own);
      if (fromServer && fromServer !== own) list.push(fromServer);
      done(list);
    }
    if (!platform.localAddress) return finish(null);
    var answered = false;
    function once(ip) {
      if (answered) return;
      answered = true;
      finish(ip);
    }
    // Adresi soran servis yanıt vermezse tarama kayıtlı adresin ağıyla sürer.
    setTimeout(function () { once(null); }, 3000);
    try {
      platform.localAddress(once);
    } catch (e) {
      once(null);
    }
  }

  function probe(address, done) {
    var request = new XMLHttpRequest();
    var finished = false;
    function finish(ok) {
      if (finished) return;
      finished = true;
      done(ok);
    }
    request.onload = function () { finish(request.status === 200 && request.responseText.indexOf('couchsubs') >= 0); };
    request.onerror = function () { finish(false); };
    request.ontimeout = function () { finish(false); };
    try {
      request.open('GET', address + '/hello');
      request.timeout = SCAN_TIMEOUT_MS;
      request.send();
    } catch (e) {
      finish(false);
    }
  }

  function scanForServer() {
    if (scanning) return;
    cancelScan();
    scanning = true;
    scanSubnets(function (subnets) {
      var addresses = [];
      for (var s = 0; s < subnets.length; s++) {
        for (var host = 1; host <= 254; host++) addresses.push('http://' + subnets[s] + '.' + host + ':' + SERVER_PORT);
      }
      var next = 0, active = 0, found = false;
      function pump() {
        while (!found && active < SCAN_PARALLEL && next < addresses.length) {
          active++;
          tryAddress(addresses[next++]);
        }
        if (!found && !active && next >= addresses.length) {
          scanning = false;
          scheduleScan();
        }
      }
      function tryAddress(address) {
        probe(address, function (ok) {
          active--;
          if (found) return;
          if (!ok) return pump();
          found = true;
          scanning = false;
          // Bulunan adres kaydedilir: TV bir sonraki açılışta eski adrese takılmasın.
          save('server', address);
          // Aynı bilgisayarsa EventSource kendisi yeniden bağlanır; kapanıp vazgeçtiyse (CLOSED) yeniden kurulur.
          if (address !== server || (eventSource && eventSource.readyState === 2)) connect(address);
        });
      }
      pump();
    });
  }

  // --- Demo ---
  // Mağaza incelemesi ve ilk kez açanlar için: PS5 ve bilgisayar olmadan örnek altyazılar gösterilir.

  // next: sonraki satıra kadar geçen süre. Kısa olanlar hızlı konuşmayı gösterir: önceki satır üstte soluk kalır.
  var DEMO_LINE_MS = 3200;
  var DEMO_GAP_MS = 700;
  var DEMO_FAST_MS = 1000;
  var DEMO_LINES = [
    { en: 'This city needs someone to watch over it.', text: 'Bu şehrin onu kollayacak birine ihtiyacı var.', next: DEMO_LINE_MS + DEMO_GAP_MS },
    { en: 'They\'re coming. Stay out of sight.', text: 'Geliyorlar. Gözden uzak dur.', next: DEMO_LINE_MS + DEMO_GAP_MS },
    { en: 'Who\'s there?', text: 'Kim var orada?', next: DEMO_FAST_MS },
    { en: 'Not tonight.', text: 'Bu gece olmaz.', next: DEMO_LINE_MS + DEMO_GAP_MS },
    { en: 'The rain hides everything.', text: 'Yağmur her şeyi saklıyor.', next: DEMO_LINE_MS + DEMO_GAP_MS },
    { en: 'Get to the rooftop. Now!', text: 'Çatıya çık. Hemen!', next: DEMO_FAST_MS },
    { en: 'This isn\'t over.', text: 'Bu iş daha bitmedi.', next: DEMO_LINE_MS + DEMO_GAP_MS }
  ];
  var demoTimer = null;
  var demoIndex = 0;

  function demoRunning() { return demoTimer !== null; }

  function nextDemoLine() {
    var line = DEMO_LINES[demoIndex];
    showSubtitle(line.text, DEMO_LINE_MS);
    demoIndex = (demoIndex + 1) % DEMO_LINES.length;
    demoTimer = setTimeout(nextDemoLine, line.next);
  }

  function startDemo() {
    if (demoRunning()) return;
    hidePanel();
    $('waiting').className = 'hidden';
    $('demo-badge').className = '';
    demoIndex = 0;
    nextDemoLine();
  }

  function stopDemo() {
    clearTimeout(demoTimer);
    demoTimer = null;
    hideSubtitle('demo');
    $('demo-badge').className = 'hidden';
    // Uygulamaya bağlı değilse bekleme ekranına dönülür.
    if (!server) $('waiting').className = '';
  }

  // --- Nino: bekleme ekranında kendi kendine oynayan demo ---
  // Uygulamaya bağlı değilken sinematik bir sahne oynar: önce oyunun İngilizce altyazısı çıkar, ~0,9 sn sonra Nino'nun
  // Türkçesi tam üstüne biner. Bilgisayar bağlanınca (bekleme kutusu gizlenince) kendiliğinden durur.
  var attractTimer = null;
  var attractIndex = 0;
  var ATTRACT_EN_MS = 900;
  var ATTRACT_TR_MS = 3000;
  var ATTRACT_GAP_MS = 900;

  function attractRunning() { return attractTimer !== null; }

  function attractStep() {
    var line = DEMO_LINES[attractIndex];
    attractIndex = (attractIndex + 1) % DEMO_LINES.length;
    var en = $('game-sub');
    en.textContent = line.en;
    en.className = 'on';
    attractTimer = setTimeout(function () {
      showSubtitle(line.text, ATTRACT_TR_MS);
      attractTimer = setTimeout(function () {
        en.className = '';
        attractTimer = setTimeout(attractStep, ATTRACT_GAP_MS);
      }, ATTRACT_TR_MS);
    }, ATTRACT_EN_MS);
  }

  function startAttract() {
    if (attractRunning()) return;
    $('attract').className = '';
    document.body.classList.add('attract');
    attractIndex = 0;
    attractTimer = setTimeout(attractStep, 1200);
  }

  function stopAttract() {
    clearTimeout(attractTimer);
    attractTimer = null;
    $('attract').className = 'hidden';
    $('game-sub').className = '';
    document.body.classList.remove('attract');
    hideSubtitle('attract');
  }

  // Bekleme kutusunun görünürlüğü birçok yerde değişiyor; demo onu izler.
  setInterval(function () {
    // Katman modunda (Android TV'de PS5 görüntüsünün üstüne çizilen pencere) demo hiç oynamaz: oyunun üstünü örterdi.
    var overlay = document.body.classList.contains('overlay');
    var waiting = $('waiting').className !== 'hidden' && !overlay;
    if (waiting && !attractRunning() && !demoRunning()) startAttract();
    else if (!waiting && attractRunning()) stopAttract();
  }, 250);

  // Geri tuşu: önce ipucu, demo ya da panel kapanır; giriş ekranında TV'nin ana ekranına dönülür.
  function goBack() {
    if (sourceTipShown()) return hideSourceTip();
    if (noPictureShown()) return closeNoPicture();
    if (demoRunning()) return stopDemo();
    if ($('panel').className !== 'hidden') return hidePanel();
    leaving = true;
    platform.exit();
  }

  // --- TV kendiliğinden HDMI'ya geçiyor (Samsung) ---
  // Samsung'da Anynet+ (HDMI-CEC) ya da Otomatik Kaynak Değiştirme açıkken TV, PS5'ten sinyal gelince CouchSubs'ı
  // arka plana atıp kendi HDMI girişine geçebiliyor: çeviri bir an görünüp kayboluyor. Uygulama açıldıktan ya da öne
  // geldikten kısa süre sonra arka plana düşerse, ya da kısa sürede birkaç kez düşerse bu not edilir; uygulama yeniden
  // göründüğünde ipucu gösterilir. Not localStorage'da durur: TV uygulamayı kapatıp sonra yeniden açsa da ipucu çıkar.
  // Yalnız ipucu menüleri Samsung'a uyan platformda (platform.sourceSwitchTip) çalışır.

  var SOURCE_SWITCH_SOON_MS = 10000;
  var SOURCE_SWITCH_REPEAT = 3;
  var SOURCE_SWITCH_WINDOW_MS = 300000;
  var SOURCE_TIP_MS = 30000;
  var visibleSince = Date.now();
  var hiddenTimes = [];
  var leaving = false; // Geri tuşuyla çıkılıyor: arka plana düşmesi kendiliğinden değil.
  var sourceTipTimer = null;

  function noteHidden() {
    if (!platform.sourceSwitchTip || leaving) return;
    var now = Date.now();
    hiddenTimes.push(now);
    while (hiddenTimes.length && now - hiddenTimes[0] > SOURCE_SWITCH_WINDOW_MS) hiddenTimes.shift();
    if (now - visibleSince < SOURCE_SWITCH_SOON_MS || hiddenTimes.length >= SOURCE_SWITCH_REPEAT) {
      save('sourceSwitch', now);
    }
  }

  function noteVisible() {
    visibleSince = Date.now();
    maybeShowSourceTip();
  }

  function maybeShowSourceTip() {
    if (!platform.sourceSwitchTip || !load('sourceSwitch')) return;
    save('sourceSwitch', '');
    $('source-tip').className = '';
    clearTimeout(sourceTipTimer);
    sourceTipTimer = setTimeout(hideSourceTip, SOURCE_TIP_MS);
  }

  function sourceTipShown() { return $('source-tip').className !== 'hidden'; }

  function hideSourceTip() {
    clearTimeout(sourceTipTimer);
    $('source-tip').className = 'hidden';
  }

  document.addEventListener('visibilitychange', function () {
    if (document.hidden) noteHidden(); else noteVisible();
  });

  // --- Panel ve kumanda ---

  // "1–4: HDMI girişi · 0: …" satırını tuş başına bir satıra böler; tuş adı vurgu renginde.
  function formatKeys() {
    var el = $('keys');
    var parts = el.textContent.split(' · ');
    el.innerHTML = '';
    for (var i = 0; i < parts.length; i++) {
      var colon = parts[i].indexOf(':');
      var row = document.createElement('div');
      row.className = 'key';
      var name = colon > 0 ? parts[i].slice(0, colon).trim() : '';
      // Nino: tuş adı kumanda tuşu gibi çizilir; renkli tuşlar renkli nokta olur.
      var keyEl = document.createElement('b');
      var color = { 'Kırmızı': 'red', 'Red': 'red', 'Mavi': 'blue', 'Blue': 'blue', 'Yeşil': 'green', 'Green': 'green', 'Sarı': 'yellow', 'Yellow': 'yellow' }[name];
      if (color) {
        keyEl.className = 'kbd color ' + color;
        keyEl.innerHTML = '<i></i>';
        keyEl.appendChild(document.createTextNode(name));
      } else {
        keyEl.className = 'kbd';
        keyEl.textContent = name;
      }
      row.appendChild(keyEl);
      var what = document.createElement('span');
      what.textContent = colon > 0 ? parts[i].slice(colon + 1).trim() : parts[i];
      row.appendChild(what);
      el.appendChild(row);
    }
  }

  // Panel açıkken bekleme kutusu kapanır: ikisi üst üste binince yazılar okunmuyor.
  function showPanel(autoHide) {
    $('waiting').className = 'hidden';
    $('panel').className = '';
    clearTimeout(panelTimer);
    if (autoHide) panelTimer = setTimeout(hidePanel, 8000);
  }

  function hidePanel() {
    $('panel').className = 'hidden';
    if (!server && !demoRunning()) $('waiting').className = '';
  }

  function togglePanel() {
    if ($('panel').className === 'hidden') showPanel(false); else hidePanel();
  }

  // Sayı tuşu olmayan kumandalar için: panel açıkken sol ve sağ HDMI girişini değiştirir.
  function stepHdmi(step) {
    hdmiPort = (hdmiPort + step + 3) % 4 + 1;
    save('hdmi', hdmiPort);
    showHdmi(hdmiPort);
    showPanel(true);
  }

  // Sihirli kumandada işaretçi görünürken Tamam tuşu keydown yerine tıklama gönderir; tuş sonrası gelen tıklama sayılmaz.
  var lastOkKey = 0;
  document.addEventListener('click', function () {
    if (Date.now() - lastOkKey < 400) return;
    if (sourceTipShown()) hideSourceTip();
    else if (noPictureShown()) return;
    else if ($('waiting').className !== 'hidden') togglePanel();
    else if (!demoRunning()) togglePanel();
  });

  document.addEventListener('keydown', function (e) {
    var code = e.keyCode;
    if (code === KEY.OK) lastOkKey = Date.now();
    if (code === KEY.OK && sourceTipShown()) {
      hideSourceTip();
    } else if (noPictureShown() && (code === KEY.LEFT || code === KEY.RIGHT)) {
      focusNoPicture(noPictureFocus + (code === KEY.RIGHT ? 1 : -1));
      e.preventDefault();
    } else if (noPictureShown() && (code === KEY.UP || code === KEY.DOWN)) {
      focusNoPictureRow(code === KEY.DOWN ? 1 : -1);
      e.preventDefault();
    } else if (noPictureShown() && code === KEY.OK) {
      runNoPicture(noPictureActions[noPictureFocus]);
    } else if (code === 48) { // 0: elle seçimi unut, konsolu yeniden ara
      save('hdmi', '');
      autoSelectConsole(function () {
        setStatus('st-hdmi', hdmiPort + ' (' + t('consoleNotFound') + ')', 'bad');
      });
      showPanel(true);
    } else if (code >= 49 && code <= 52) { // 1–4
      hdmiPort = code - 48;
      save('hdmi', hdmiPort);
      showHdmi(hdmiPort);
      showPanel(true);
    } else if (code === KEY.RED) {
      showSubtitle(t('localTest'), 4000);
    } else if (code === KEY.GREEN) {
      togglePanel();
    } else if (code === KEY.BLUE) {
      if (demoRunning()) stopDemo(); else startDemo();
    } else if (code === KEY.OK && $('waiting').className !== 'hidden') {
      togglePanel();
    } else if (code === KEY.OK && !demoRunning()) {
      togglePanel();
    } else if ((code === KEY.LEFT || code === KEY.RIGHT) && $('panel').className !== 'hidden') {
      stepHdmi(code === KEY.RIGHT ? 1 : -1);
    } else if (code === KEY.BACK) {
      goBack();
      e.preventDefault();
    } else if (code === KEY.UP || code === KEY.DOWN) {
      nudgeSubtitle(code === KEY.UP ? 3 : -3);
      e.preventDefault();
    }
  });

  // Uygulama zaten açıkken yeniden başlatılırsa (ör. CouchSubs onu öne getirdiğinde) parametreler burada gelir.
  platform.onRelaunch(function (raw) { applyParams(parseParams(raw)); });

  platform.init();
  window.applyI18n();
  formatKeys();
  var savedBottom = load('bottom') || load('appBottom');
  if (savedBottom) setBottom(Number(savedBottom));
  showHdmi(hdmiPort);
  if (!savedPort) autoSelectConsole();

  $('app-version').textContent = APP_LABEL + ' (' + APP_VERSION + ')';
  renderDiag();
  renderWaitingStatus();
  // Önceki açılışta TV kendiliğinden kaynağa geçtiyse ipucu şimdi gösterilir.
  maybeShowSourceTip();
  var initial = parseParams(platform.launchParams());
  var address = initial.server || load('server') || config.server;
  applyParams(initial);
  if (!server) {
    if (address) connect(address); else $('waiting').className = '';
  }
  if (!server) scanForServer();
  // Bekleme ekranı açıksa panel kendiliğinden açılmaz; yeşil tuşla açılabilir.
  if (server) showPanel(true); else hidePanel();
})();
