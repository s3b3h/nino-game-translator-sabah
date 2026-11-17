// SPDX-License-Identifier: AGPL-3.0-only
// Gerçek Chromium yerleşimiyle TV ekran çevirisi. node --test scripts/tv-screen.test.js
// Tarayıcı yolu: COUCHSUBS_TEST_BROWSER; bağımlılık/model indirme ve canlı TV bağlantısı yok.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const root = path.join(__dirname, '..', 'tv-webos');
const browser = [process.env.COUCHSUBS_TEST_BROWSER, process.env.CHROME_BIN,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'].find(p => p && fs.existsSync(p));
const item = (text, left, top, right, bottom, line = .03) => ({ text, box: { left, top, right, bottom }, line });
const upper = item('Bu bölgedeki bütün gizli belgeleri bul ve güvenli bölgeye geri dön.', .10, .20, .28, .23);
const lower = item('Görevler', .10, .26, .28, .28, .02);
const scenarios = {
  neighbours: [upper, lower],
  tight: [upper, item('Görevler', .10, .24, .28, .26, .02)],
  reversed: [lower, upper],
  isolated: [item('Kaydet', .10, .20, .28, .23)],
  columns: [item('Kaydet', .10, .20, .28, .23), item('Seçenekler', .70, .21, .90, .24)],
  edge: [item('Gizli belgeleri bul ve güvenli bölgeye geri dön.', .1, .945, .28, .975)],
  paragraph: [Object.assign(item('Bu görevde önce köprüyü geçmeli, ardından köyün kuzeyindeki güvenli bölgeye ulaşmalısın.\nYanındaki belgeleri muhafıza teslim et.', .1, .1, .45, .4), {paragraphs:true}),
    item('Harita', .1, .5, .3, .53)],
  dense: [item('Bütün belgeleri güvenli bölgeye götür. '.repeat(30), .1, .2, .2, .23),
    item('Görevler', .1, .24, .2, .26, .02)],
  invalid: [null, {text:'Geçersiz',box:{left:.2,top:.2,right:.1,bottom:.3}},
    item('', .1, .23, .28, .24), item('Kaydet', .1, .2, .28, .23)],
};

function render(width, height) {
  const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
  const start = app.indexOf('  var screenTimer = null;');
  const end = app.indexOf('\n  //', app.indexOf('  function hideScreen()', start));
  const validStart = app.indexOf('  function validBox(box)');
  const validEnd = app.indexOf('\n  //', validStart);
  assert.ok(start > 0 && end > start && validStart > 0 && validEnd > validStart, 'TV işlevleri bulunamadı');
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'couchsubs-screen-test-'));
  try {
    const html = `<!doctype html><meta charset="utf-8"><style>${fs.readFileSync(path.join(root, 'style.css'), 'utf8')}</style>
      <div id="screen"></div><pre id="result"></pre><script>
      function $(id) { return document.getElementById(id); }
      var hidden = []; function hideSubtitle(reason) { hidden.push(reason); }
      ${app.slice(validStart, validEnd)}
      ${app.slice(start, end)}
      var result = {};
      var scenarios = ${JSON.stringify(scenarios)};
      for (var key in scenarios) {
        showScreen(scenarios[key], 10000);
        result[key] = Array.from($('screen').children).map(function(el) {
          var b = el.getBoundingClientRect();
          return {text: el.textContent, left:b.left, right:b.right, top:b.top, bottom:b.bottom,
            width:b.width, height:b.height, font:parseFloat(getComputedStyle(el).fontSize),
            clientHeight:el.clientHeight, scrollHeight:el.scrollHeight, align:getComputedStyle(el).textAlign};
        });
      }
      hideScreen(); result.hidden = $('screen').className; result.count = $('screen').children.length;
      result.viewport = {width:innerWidth,height:innerHeight}; result.hideReasons = hidden;
      $('result').textContent = btoa(unescape(encodeURIComponent(JSON.stringify(result))));
      </script>`;
    // Pencere çerçevesi/işletim sistemi ölçeği yerine tam hedef çözünürlükte bir iframe.
    const encoded = Buffer.from(html, 'utf8').toString('base64');
    const page = `<!doctype html><iframe id="frame" style="border:0;width:${width}px;height:${height}px"></iframe>
      <pre id="result"></pre><script>
      var frame = document.getElementById('frame');
      frame.contentDocument.open();
      frame.contentDocument.write(decodeURIComponent(escape(atob('${encoded}'))));
      frame.contentDocument.close();
      document.getElementById('result').textContent = frame.contentDocument.getElementById('result').textContent;
      </script>`;
    const file = path.join(temp, 'test.html'); fs.writeFileSync(file, page);
    const run = spawnSync(browser, ['--headless=new', '--disable-gpu', '--disable-background-networking',
      '--no-first-run', '--no-default-browser-check', '--hide-scrollbars', '--force-device-scale-factor=1', '--window-size=' + width + ',' + height,
      ...(process.platform === 'linux' ? ['--no-sandbox'] : []),
      '--user-data-dir=' + path.join(temp, 'profile'), '--dump-dom', pathToFileURL(file).href],
      { encoding:'utf8', timeout:30000, maxBuffer:2*1024*1024, windowsHide:true });
    assert.equal(run.status, 0, String(run.error || run.stderr));
    const match = run.stdout.match(/<pre id="result">([A-Za-z0-9+/=]+)<\/pre>/);
    assert.ok(match, 'Tarayıcı ölçüm üretmedi: ' + run.stdout.slice(-1000));
    return JSON.parse(Buffer.from(match[1], 'base64').toString('utf8'));
  } finally {
    // Yalnız bu testin sistem geçici dizininde oluşturduğu klasör.
    assert.equal(path.dirname(temp), path.resolve(os.tmpdir()));
    fs.rmSync(temp, {recursive:true, force:true, maxRetries:5, retryDelay:200});
  }
}

if (process.env.CI) assert.ok(browser, 'CI: gerçek yerleşim testi için Chrome/Edge gerekli');
for (const [width, height] of [[1280,720], [1920,1080], [3840,2160]]) {
test('TV ekran çevirisi: ' + width + '×' + height, {skip: !browser && 'Chrome/Edge bulunamadı'}, async t => {
  const r = render(width, height);
  assert.deepEqual(r.viewport, {width, height});
  await t.test('uzun üst etiket alttaki bağımsız etiketi kapatmaz', () => {
    assert.ok(r.neighbours[0].bottom <= r.neighbours[1].top, JSON.stringify(r.neighbours));
    assert.equal(r.neighbours[0].text, upper.text);
    assert.ok(r.neighbours[0].scrollHeight <= r.neighbours[0].clientHeight + 1);
  });
  await t.test('çok dar aralıkta okunabilirlik alt sınırı korunur', () => {
    // 720p'de iki satır 14 px ile bu aralığa fiziksel olarak sığmaz.
    // Böyle bir durumda metni kesmek/gizlemek yerine mevcut doğal büyüme kalır.
    if (width >= 1920) assert.ok(r.tight[0].bottom <= r.tight[1].top);
    else assert.equal(r.tight[0].font, 14);
    assert.equal(r.tight[0].text, upper.text);
    assert.ok(r.tight[0].scrollHeight <= r.tight[0].clientHeight + 1);
  });
  await t.test('veri sırası sonucu değiştirmez', () => {
    assert.deepEqual(r.reversed, [...r.neighbours].reverse());
  });
  await t.test('kısa etiket ve ayrı sütunların yerleşimi aynı kalır', () => {
    assert.deepEqual(r.isolated[0], r.columns[0]);
    assert.equal(r.isolated[0].font, Math.max(14, Math.min(96, Math.round(.03 * r.viewport.height * .95))));
    // Nino: kutunun sol payı daha geniştir (SCREEN_PAD_X = 0.018; CouchSubs'ta 0.004).
    assert.ok(Math.abs(r.isolated[0].left - .082*r.viewport.width) < 1);
  });
  await t.test('ekranın alt kenarında metin kaybolmaz', () => {
    assert.ok(r.edge[0].bottom <= r.viewport.height, JSON.stringify(r.edge));
    assert.equal(r.edge[0].text, scenarios.edge[0].text);
  });
  await t.test('paragraf hizası ve tam metin korunur', () => {
    // Nino: 'start' hizası Arapçada sağa, öbür dillerde sola yaslar.
    assert.equal(r.paragraph[0].align, 'start');
    assert.equal(r.paragraph[0].text, scenarios.paragraph[0].text);
    assert.ok(r.paragraph[0].scrollHeight <= r.paragraph[0].clientHeight + 1);
    assert.ok(r.paragraph[0].bottom < r.paragraph[1].top);
  });
  await t.test('sığması imkânsız metin kesilmez ve 14 px altına inmez', () => {
    assert.equal(r.dense.length, 2);
    assert.equal(r.dense[0].text, scenarios.dense[0].text);
    assert.ok(r.dense[0].font >= 14);
    assert.ok(r.dense[0].scrollHeight <= r.dense[0].clientHeight + 1);
  });
  await t.test('boş/geçersiz kutular sağlam etiketi küçültmez', () => {
    assert.deepEqual(r.invalid, r.isolated);
  });
  await t.test('kapatma ve normal altyazıdan geçiş korunur', () => {
    assert.equal(r.hidden, 'hidden'); assert.equal(r.count, 0);
    assert.ok(r.hideReasons.every(reason => reason === 'screen'));
  });
});

}
