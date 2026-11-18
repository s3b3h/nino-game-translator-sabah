// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { makeD1 } from "./d1-shim.js";
import { handle } from "../src/worker.js";
import { reviewTranslations, usable, translateCost, instructions } from "../src/translate.js";
import { lineKey } from "../src/key.js";

const NOW = 1763300000;

function setup(vars = {}, live) {
  const env = { DB: makeD1(), INSTALL_SALT: "tuz", ANTHROPIC_API_KEY: "k", ...vars };
  const calls = [];
  const fake = live ?? (async (_env, lang, lines, context) => {
    calls.push({ lang, lines, context });
    return { texts: lines.map((l) => `TR:${l}`), cost: 1000 };
  });
  const post = (body, now = NOW) =>
    handle(new Request("http://pool/v1/translate", { method: "POST", body: JSON.stringify(body) }), env, now, undefined, fake);
  const get = (query, now = NOW) => handle(new Request(`http://pool/v1/translations?${query}`), env, now);
  return { env, post, get, calls };
}
const req = (lines, extra = {}) => ({ v: 1, install: randomUUID(), app: "0.2.2", platform: "mac", lang: "tr", game: "gta-vi", lines, ...extra });

test("bilinmeyen satır o an çevrilir, ikinci oyuncu aynısını modelsiz alır", async () => {
  const { post, calls } = setup();
  let res = await post(req(["Get in the car!", "Shut the fuck up."], { context: ["Lucia, wait."] }));
  assert.equal(res.status, 200);
  let body = await res.json();
  assert.deepEqual(body.translations, [{ text: "TR:Get in the car!", tier: 1 }, { text: "TR:Shut the fuck up.", tier: 1 }]);
  assert.deepEqual(calls[0].context, ["Lucia, wait."]);
  // Aynı cümlenin başka yazılışı da aynı anahtar: model yeniden çağrılmaz.
  res = await post(req(["GET IN THE CAR"]));
  body = await res.json();
  assert.equal(body.translations[0].text, "TR:Get in the car!");
  assert.equal(calls.length, 1);
});

test("aynı istekte tekrar eden satır bir kez çevrilir", async () => {
  const { post, calls } = setup();
  const body = await (await post(req(["Move!", "move", "Go."]))).json();
  assert.equal(calls[0].lines.length, 2);
  assert.equal(body.translations[1].text, "TR:Move!");
});

test("günlük sınır dolunca model çağrılmaz, uygulama kendi çevirisine döner", async () => {
  const { post, calls, env } = setup({ TRANSLATE_DAILY_USD: "0.001" });
  await post(req(["One."]));
  const body = await (await post(req(["Two."]))).json();
  assert.equal(body.limited, "daily_cap");
  assert.equal(body.translations[0].text, null);
  assert.equal(calls.length, 1);
  const spent = await env.DB.prepare("SELECT micro_usd FROM translate_cost").first("micro_usd");
  assert.equal(spent, 1000);
});

test("model ret cevabı verirse çevrilemedi diye hatırlanır, yeniden ücretlendirilmez", async () => {
  let calls = 0;
  const { post, get } = setup({}, async (_e, _l, lines) => { calls++; return { texts: lines.map(() => "I'm sorry, I can't translate that."), cost: 5 }; });
  const body = await (await post(req(["You son of a bitch."]))).json();
  assert.equal(body.translations[0].text, null);
  const again = await (await post(req(["You son of a bitch."]))).json();
  assert.equal(again.translations[0].text, null);
  assert.equal(calls, 1);
  assert.equal((await (await get("lang=tr&since=0")).json()).items.length, 0);
  const { post: post2 } = setup({}, async () => ({ texts: ["tek"], cost: 5 }));
  const body2 = await (await post2(req(["One.", "Two."]))).json();
  assert.deepEqual(body2.translations.map((t) => t.text), [null, null]);
});

test("anahtar yoksa ya da kapalıysa çeviri yapılmaz ama bilinenler döner", async () => {
  const { post, env } = setup();
  await post(req(["Hello."]));
  env.ANTHROPIC_API_KEY = "";
  const body = await (await post(req(["Hello.", "Bye."]))).json();
  assert.equal(body.limited, "disabled");
  assert.deepEqual(body.translations.map((t) => t.text), ["TR:Hello.", null]);
});

test("bozuk istekler", async () => {
  const { post } = setup();
  assert.equal((await post({ v: 1, install: "x", lang: "tr", lines: ["a"] })).status, 400);
  assert.equal((await post(req(["a"], { lang: "fr" }))).status, 400);
  assert.equal((await post(req(Array.from({ length: 13 }, (_, i) => `Line ${i}`)))).status, 413);
  const body = await (await post(req(["!!!", "x".repeat(400), "Okay."]))).json();
  assert.deepEqual(body.translations.map((t) => t.text), [null, null, "TR:Okay."]);
});

test("toplu indirme: oyunun çevirileri ve sonradan değişenler, sayfalı", async () => {
  const { post, get } = setup();
  await post(req(["Alpha."]), NOW);
  await post(req(["Beta."], { game: "rdr2" }), NOW + 10);
  await post(req(["Gamma."], { lang: "ar" }), NOW + 20);
  let body = await (await get("lang=tr&game=gta-vi&since=0&_byGame=1", NOW + 30)).json();
  assert.equal(body.items.length, 1);
  // Oyun adı şimdilik süzmez: dilin bütün çevirileri gelir.
  assert.equal((await (await get("lang=tr&game=gta-vi&since=0", NOW + 30)).json()).items.length, 2);
  assert.equal(body.items[0][1], "TR:Alpha.");
  assert.equal(body.items[0][0], await lineKey("Alpha."));
  body = await (await get("lang=tr&since=0")).json();
  assert.equal(body.items.length, 2);
  body = await (await get(`lang=tr&since=${NOW}`)).json();
  assert.deepEqual(body.items.map((i) => i[1]), ["TR:Beta."]);
  assert.equal((await get("lang=xx")).status, 400);
});

test("gözden geçirme: güçlü model sırayla okur, değişen çeviri güncellenir ve yeniden indirilir", async () => {
  const { post, get, env } = setup();
  await post(req(["Where's the money?", "Relax."]), NOW);
  const seenBy = [];
  const review = async (_env, lang, game, items) => {
    seenBy.push({ lang, game, items });
    return { texts: items.map((i) => (i.source === "Relax." ? "Sakin ol be." : i.text)), cost: 2000 };
  };
  // Gecikme dolmadan gözden geçirilmez.
  let result = await reviewTranslations(env.DB, env, NOW + 60, review);
  assert.equal(result.reviewed, 0);
  result = await reviewTranslations(env.DB, env, NOW + 3600, review);
  assert.deepEqual(result, { reviewed: 2, changed: 1, cost: 2000 });
  assert.equal(seenBy[0].game, "gta-vi");
  const body = await (await get(`lang=tr&since=${NOW}`, NOW + 3600)).json();
  assert.deepEqual(body.items.map((i) => [i[1], i[3]]), [["Sakin ol be.", 2]]);
  // Ret: parça işaretlenir, bir daha gönderilmez.
  await post(req(["Third line here."]), NOW + 100);
  let fails = 0;
  const refusing = async () => { fails++; return { texts: null, cost: 10 }; };
  assert.equal((await reviewTranslations(env.DB, env, NOW + 4000, refusing)).failed, 1);
  await reviewTranslations(env.DB, env, NOW + 6000, refusing);
  assert.equal(fails, 1);
  // İkinci tur: gözden geçirilmiş satırlar yeniden gitmez.
  result = await reviewTranslations(env.DB, env, NOW + 7200, review);
  assert.equal(result.reviewed, 0);
});

test("uzaktan ayar", async () => {
  const { env } = setup({ TRANSLATE_DEADLINE_MS: "700", MIN_VERSION_IOS: "0.2.2" });
  const body = await (await handle(new Request("http://pool/v1/config"), env, NOW)).json();
  assert.equal(body.translate.enabled, true);
  assert.equal(body.translate.deadlineMs, 700);
  assert.equal(body.minVersion.ios, "0.2.2");
  // Havuz öncelikli oyunlar: varsayılan GTA 6, bekleme 1500 ms.
  assert.deepEqual(body.poolFirst.games, ["grand-theft-auto-vi", "gta-vi", "gta-6", "gta6"]);
  assert.equal(body.poolFirst.deadlineMs, 1500);
});

test("uzaktan ayar: havuz öncelikli oyunlar ve bekleme değişebilir", async () => {
  const { env } = setup({ POOL_FIRST_GAMES: " GTA6 , mafia--the-old-country,", POOL_FIRST_DEADLINE_MS: "2000" });
  const body = await (await handle(new Request("http://pool/v1/config"), env, NOW)).json();
  assert.deepEqual(body.poolFirst.games, ["gta6", "mafia-the-old-country"]);
  assert.equal(body.poolFirst.deadlineMs, 2000);
  const { env: off } = setup({ POOL_FIRST_GAMES: "" });
  assert.deepEqual((await (await handle(new Request("http://pool/v1/config"), off, NOW)).json()).poolFirst.games, []);
});

test("yardımcılar", () => {
  assert.equal(usable("Fuck you!", "Siktir git!"), true);
  assert.equal(usable("Hi", ""), false);
  assert.equal(usable("Hi", "x".repeat(200)), false);
  assert.equal(translateCost("claude-haiku-5-5", { input_tokens: 1000, output_tokens: 1000 }), 600);
  assert.match(instructions("tr"), /Never soften, censor/);
  assert.match(instructions("tr"), /"sen"/);
});

test("Claude yalnız izinli oyunlarda çevirir", async () => {
  const { post, calls } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi,mafia" });
  let body = await (await post(req(["Hello there."], { game: "elden-ring" }))).json();
  assert.equal(body.limited, "game");
  assert.equal(calls.length, 0);
  body = await (await post(req(["Hello there."], { game: "" }))).json();
  assert.equal(body.limited, "game");
  body = await (await post(req(["Get in the car!"], { game: "grand-theft-auto-vi" }))).json();
  assert.equal(body.translations[0].text, "TR:Get in the car!");
  body = await (await post(req(["Move it."], { game: "mafia-the-old-country" }))).json();
  assert.equal(body.translations[0].text, "TR:Move it.");
  assert.equal(calls.length, 2);
});

test("oyun bildirilmese de GTA 6 satırlardan tanınır ve kurulum için hatırlanır", async () => {
  const { post, calls } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi" });
  const install = randomUUID();
  // İsim yok: tanınmaz, Claude çağrılmaz.
  let body = await (await post(req(["Get in the car."], { game: "", install }))).json();
  assert.equal(body.limited, "game");
  // Bağlamda Lucia geçti: GTA 6 tanınır.
  body = await (await post(req(["Drive, drive!"], { game: "", install, context: ["Lucia, you okay?"] }))).json();
  assert.equal(body.game, "grand-theft-auto-vi");
  assert.equal(body.translations[0].text, "TR:Drive, drive!");
  // Sonraki isimsiz satır da aynı kurulumda GTA 6 sayılır.
  body = await (await post(req(["Hold on tight."], { game: "", install }, ), NOW + 600)).json();
  assert.equal(body.translations[0].text, "TR:Hold on tight.");
  assert.equal(calls.length, 2);
  // Başka kurulum etkilenmez.
  body = await (await post(req(["Hold on, man."], { game: "" }))).json();
  assert.equal(body.limited, "game");
});

test("oyun ekrandan tanınır, kurulum için hatırlanır ve çeviri o oyunla yapılır", async () => {
  const { env, calls } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi" });
  const install = randomUUID();
  const identify = async () => ({ game: "Grand Theft Auto VI", confidence: 0.95, cost: 500 });
  const res = await handle(new Request("http://pool/v1/identify", { method: "POST", body: JSON.stringify({ v: 1, install, image: "/9j/AAAA" }) }),
    env, NOW, undefined, undefined, identify);
  const body = await res.json();
  assert.deepEqual([body.game, body.id], ["Grand Theft Auto VI", "grand-theft-auto-vi"]);
  const fake = async (_e, _l, lines) => { calls.push(lines); return { texts: lines.map((l) => "TR:" + l), cost: 1 }; };
  const t = await (await handle(new Request("http://pool/v1/translate", { method: "POST",
    body: JSON.stringify(req(["Hold on tight."], { game: "", install })) }), env, NOW + 60, undefined, fake)).json();
  assert.equal(t.translations[0].text, "TR:Hold on tight.");
  assert.equal(t.game, "grand-theft-auto-vi");
  // Emin değilse oyun yazılmaz.
  const unsure = async () => ({ game: "Some Game", confidence: 0.3, cost: 1 });
  const u = await (await handle(new Request("http://pool/v1/identify", { method: "POST", body: JSON.stringify({ v: 1, install: randomUUID(), image: "/9j/AAAA" }) }),
    env, NOW, undefined, undefined, unsure)).json();
  assert.equal(u.game, null);
});

test("oyun havuzdaki satırdan da tanınır", async () => {
  const { post, calls } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi" });
  await post(req(["We hit the jewelry store at midnight, Jason."], { game: "grand-theft-auto-vi" }));
  const install = randomUUID();
  // Yeni oyuncu oyun adı göndermiyor; havuzda bilinen uzun satır geldi: GTA 6 tanınır.
  let body = await (await post(req(["We hit the jewelry store at midnight, Jason."], { game: "", install }))).json();
  assert.equal(body.game, "grand-theft-auto-vi");
  // Sonraki yeni satırı da Claude çevirir.
  body = await (await post(req(["Grab the duffel bag."], { game: "", install }), NOW + 30)).json();
  assert.equal(body.translations[0].text, "TR:Grab the duffel bag.");
  assert.equal(calls.length, 2);
});

test("havuz öncelikli oyunun satırı, uygulama başka oyun sansa da o oyunu döndürür", async () => {
  const { post } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi" });
  const line = "I still can't believe I shacked up with a car thief.";
  let body = await (await post(req([line], { game: "grand-theft-auto-vi" }))).json();
  assert.equal(body.game, "grand-theft-auto-vi");
  body = await (await post(req([line], { game: "call-of-duty-modern-warfare-2019" }))).json();
  assert.equal(body.game, "grand-theft-auto-vi");
  assert.ok(body.translations[0].text);
  // Bilinmeyen satır ve başka oyun: oyun değişmez.
  body = await (await post(req(["A brand new line nobody has seen."], { game: "red-dead-redemption-2" }))).json();
  assert.equal(body.game, "red-dead-redemption-2");
});

test("GTA 6'ya özgü ad geçen satır, uygulama başka oyun sansa da GTA 6 sayılır", async () => {
  const { post } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi" });
  const body = await (await post(req(["Lucia, get in the car."], { game: "red-dead-redemption-2" }))).json();
  assert.equal(body.game, "grand-theft-auto-vi");
  assert.ok(body.translations[0].text);
});
