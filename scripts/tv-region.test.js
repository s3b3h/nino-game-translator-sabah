// SPDX-License-Identifier: AGPL-3.0-only
// TV'de ek alan kutusunun yeri: kısa ve altta olan yazının (telefonun kısa mesaj bildirimi) çevirisi yazının üstünde,
// yarı saydam kutuda durur; uzun yazılar yerinde çevrilir. node --test scripts/tv-region.test.js (tarayıcı gerekmez)
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const app = fs.readFileSync(path.join(__dirname, '..', 'tv-webos', 'app.js'), 'utf8');
const slice = (from, to) => {
  const start = app.indexOf(from);
  const end = app.indexOf(to, start);
  assert.ok(start > 0 && end > start, `TV işlevi bulunamadı: ${from}`);
  return app.slice(start, end);
};

function show(data) {
  const made = [];
  const regions = { className: 'hidden', appendChild() {}, removeChild() {} };
  const context = {
    window: { innerWidth: 1920, innerHeight: 1080 },
    document: { createElement() { const el = { style: {}, className: '', textContent: '' }; made.push(el); return el; } },
    $: () => regions,
  };
  vm.runInNewContext(`${slice('  function validBox(box)', '\n  //')}\n${slice('  var regionBoxes = {};', '  function hideRegion(id)')}\nshowRegion(${JSON.stringify(data)});`, context);
  return made[0];
}

test('kısa mesaj bildirimi (sağ altta, kısa): çeviri yazının üstünde ve yarı saydam', () => {
  const el = show({ id: 'phone', text: 'Neredesin?', box: { left: 0.74, top: 0.80, right: 0.97, bottom: 0.88 }, line: 0.03 });
  assert.equal(el.className, 'region beside');
  // Kutunun alt kenarı asıl yazının üst kenarının hemen üstünde: bottom ≈ (1 - 0.80) = %20.
  assert.ok(Math.abs(parseFloat(el.style.bottom) - 20.8) < 0.01, el.style.bottom);
  assert.equal(el.style.top, '');
  assert.ok(el.style.right.endsWith('%'));
});

test('uzun yazı (açık telefon ekranı) ve üstteki görev yazısı eskisi gibi yerinde', () => {
  const phone = show({ id: 'phone', text: 'Uzun mesaj', box: { left: 0.74, top: 0.52, right: 0.97, bottom: 0.92 }, line: 0.03 });
  assert.equal(phone.className, 'region');
  assert.ok(Math.abs(parseFloat(phone.style.bottom) - 7.6) < 0.01, phone.style.bottom);
  const quest = show({ id: 'quest', text: 'Görev', box: { left: 0.70, top: 0.05, right: 0.97, bottom: 0.10 }, line: 0.03 });
  assert.equal(quest.className, 'region');
  assert.ok(quest.style.top.endsWith('%'));
  assert.equal(quest.style.bottom, '');
});
