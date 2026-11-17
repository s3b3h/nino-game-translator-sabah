// SPDX-License-Identifier: AGPL-3.0-only
// Ağ yok: süzgeç ve gönderimin D1'e kaç yazma yaptığı sahte bir veritabanıyla denenir. Çalıştırma: `npm test`.

import { test } from "node:test";
import assert from "node:assert/strict";
import { accepts } from "../src/filter.js";
import worker, { gameName, titleId } from "../src/index.js";
import { GENERAL, jobPackId, nameJobs, runAutopack } from "../src/autopack.js";
import { gameKey, gameSlug } from "../src/games.js";

test("Türkçe arayüz, bozulmuş Türkçe, sistem yazısı ve yarım okumalar alınmaz", () => {
  for (const line of [
    "Oturum Açtı", "Oturum Aqtl", "Oturum Aqtl.", "Sifirlama Seqenekleri", "Sifirlama Seqenekleri.",
    "PS5 Sistemini Yeniden Baslat", "PS5 Sistemini Yeniden Baslat.", "Oyunu Kapat", "Ana Ekranda Tut",
    "Lütfen bekleyin..", "Ekran ve Video", "ilerlemenizi takip edin Kupalar", "Keşfet PS5 ile ilgili Öne Çıkanlar",
    "Ekran görüntüsü kaydedildi.", "Kupa kazandınız!", "John signed in.", "You've earned a trophy!",
    "Please do not quit or turn off your console while the Rockstar cloud save icon is showing.",
    "GO to the", "Take out the trash and the", "it Auto V's Story Mode.", "FREE MONTH OF GTA+", "PHOTO MODE SELECT",
    "Main menu", "Hold on", "HP 100/100 MP 25/50", "Okay.",
  ]) assert.equal(accepts(line), false, line);
});

test("İngilizce oyun satırları alınır", () => {
  for (const line of [
    "Herr Müller will see you now.", "This place was designed in a hurry.", "Tell Sam I signed the deal.",
    "I lie to you, you lie to me.", "DON TORRISI WANTS YOU!", "Get down!", "Who's there?", "Line number 7 here",
    "We need to move before the cops show up", "Give me 50 dollars, Enzo.",
  ]) assert.equal(accepts(line), true, line);
});

// D1'in yalnız bu dosyadaki sorguları kadarını taklit eder; her çalışan yazma deyimini sayar.
function fakeDB() {
  const sightings = new Map(); // anahtar -> kurulumlar
  const lines = new Map();
  const db = {
    writes: 0, lines, quotas: new Map(), last: null, beforeQuotaRead: null,
    batchCalls: 0, failNextBatch: false, failBatchOnCall: null,
  };
  const quotaKey = (install, day) => `${install}\u001f${day}`;
  const run = (sql, args) => {
    if (sql.startsWith("SELECT count FROM quota")) return { count: db.quotas.get(quotaKey(args[0], args[1])) ?? 0 };
    if (sql.startsWith("SELECT")) {
      db.last = { sql, args };
      return { results: [] };
    }
    db.writes++;
    if (sql.startsWith("INSERT OR IGNORE INTO sightings")) {
      const [k, who] = args;
      const set = sightings.get(k) ?? new Set();
      const changes = set.has(who) ? 0 : 1;
      set.add(who);
      sightings.set(k, set);
      return { meta: { changes } };
    }
    if (sql.startsWith("INSERT INTO lines")) {
      // Havuza yalnız iki kurulumdan sonra girer; sayı güncel distinct sightings'dir.
      const [k, text, , , title = null, game = null] = args;
      const n = sightings.get(k)?.size ?? 0;
      if (n < 2) return { meta: { changes: 0 } };
      const row = lines.get(k);
      if (row && row.installs >= n) return { meta: { changes: 0 } };
      lines.set(k, row
        ? { ...row, installs: n, title: row.title ?? title, game: row.game ?? game }
        : { text, installs: n, title, game });
      return { meta: { changes: 1 } };
    }
    if (sql.startsWith("INSERT INTO quota")) {
      const key = quotaKey(args[0], args[1]);
      const delta = args[2];
      const expected = args[3];
      const used = db.quotas.get(key) ?? 0;
      if (args.length === 4 && used !== expected) return { meta: { changes: 0 } };
      db.quotas.set(key, used + delta);
      return { meta: { changes: 1 } };
    }
    if (sql.startsWith("UPDATE quota")) {
      const key = quotaKey(args[1], args[2]);
      db.quotas.set(key, (db.quotas.get(key) ?? 0) - args[0]);
      return { meta: { changes: 1 } };
    }
    throw new Error(sql);
  };
  db.prepare = (sql) => ({
    bind: (...args) => ({
      first: async () => {
        if (sql.startsWith("SELECT count FROM quota")) {
          const result = run(sql, args);
          await db.beforeQuotaRead?.();
          return result;
        }
        return run(sql, args);
      },
      run: async () => run(sql, args), all: async () => run(sql, args), sql, args,
    }),
  });
  // D1'de toplu yazma tek işlemdir: bir deyim hata verirse hiçbiri yazılmaz.
  db.batch = async (stmts) => {
    db.batchCalls++;
    if (db.failNextBatch || db.failBatchOnCall === db.batchCalls) {
      db.failNextBatch = false;
      db.failBatchOnCall = null;
      throw new Error("injected batch failure");
    }
    return stmts.map((s) => run(s.sql, s.args));
  };
  return db;
}

const install = (n) => `00000000-0000-4000-8000-00000000000${n}`;
const post = (env, who, texts) => worker.fetch(new Request("https://pool.test/v1/lines", {
  method: "POST",
  body: JSON.stringify({ install: who, lines: texts.map((text) => ({ text })) }),
}), env);

test("gönderim süzer; tek kurulumun satırı havuza yazılmaz, ikinci kurulumda girer", async () => {
  const DB = fakeDB();
  const env = { DB };
  const reply = await post(env, install(1), ["Oturum Açtı", "Get down!", "Get down!", "Who is that over there?"]);
  assert.deepEqual(await reply.json(), { accepted: 2, recorded: 2 });
  // İki görülme + iki koşullu UPSERT + bir kota rezervasyonu; ilk kurulumda lines'a kayıt girmez.
  assert.equal(DB.lines.size, 0);

  // Aynı kurulum aynı satırları yeniden gönderirse yalnız görülme denemesi ve kota yazılır.
  DB.writes = 0;
  await post(env, install(1), ["Get down!", "Who is that over there?"]);
  assert.equal(DB.writes, 5); // 2 idempotent sightings + 2 idempotent conditional UPSERT + 1 quota
  assert.equal(DB.lines.size, 0);

  // İkinci kurulum: satır havuza installs=2 ile girer; yalnız onun okuduğu satır.
  await post(env, install(2), ["Get down!"]);
  assert.deepEqual([...DB.lines.values()].map((l) => l.installs), [2]);

  // Üçüncü kurulum: sayaç bir artar.
  await post(env, install(3), ["Get down!"]);
  assert.deepEqual([...DB.lines.values()].map((l) => l.installs), [3]);
});

const postLines = (env, who, lines) => worker.fetch(new Request("https://pool.test/v1/lines", {
  method: "POST",
  body: JSON.stringify({ install: who, lines }),
}), env);

test("eşzamanlı gönderimler günlük kota sınırını aşamaz", async () => {
  const DB = fakeDB();
  const who = install(7);
  const day = new Date().toISOString().slice(0, 10);
  DB.quotas.set(`${who}\u001f${day}`, 4990);
  let readers = 0;
  let releaseReads;
  const bothRead = new Promise((resolve) => { releaseReads = resolve; });
  DB.beforeQuotaRead = async () => {
    readers++;
    if (readers === 2) releaseReads();
    await bothRead;
  };

  const lines = Array.from({ length: 20 }, (_, i) => ({ text: `Keep moving ${i} now.` }));
  const replies = await Promise.all([
    postLines({ DB }, who, lines),
    postLines({ DB }, who, lines),
  ]);

  assert.deepEqual(replies.map((reply) => reply.status).sort(), [200, 429]);
  const accepted = replies.find((reply) => reply.status === 200);
  assert.deepEqual(await accepted.json(), { accepted: 10, recorded: 10 });
  assert.equal(DB.quotas.get(`${who}\u001f${day}`), 5000);
  assert.equal(DB.lines.size, 0); // tek kurulumun gördüğü satırlar havuza girmez
});

test("ilk yazma toplu işlemi başarısızsa kota rezervasyonu geri alınır", async () => {
  const DB = fakeDB();
  const who = install(9);
  const day = new Date().toISOString().slice(0, 10);
  DB.quotas.set(`${who}\u001f${day}`, 12);
  DB.failNextBatch = true;

  const reply = await postLines({ DB }, who, [{ text: "Get down!" }]);
  assert.equal(reply.status, 500);
  assert.equal(DB.quotas.get(`${who}\u001f${day}`), 12);
});

test("atomik görülme ve satır batch'i başarısızsa kota rezervasyonu geri alınır", async () => {
  const DB = fakeDB();
  const who = install(4);
  const day = new Date().toISOString().slice(0, 10);
  DB.quotas.set(`${who}\u001f${day}`, 12);
  // İki aşama yerine görülme ve satır yazımı tek D1 batch transaction'ıdır.
  DB.failBatchOnCall = 1;

  const reply = await postLines({ DB }, who, [{ text: "Get down!" }]);
  assert.equal(reply.status, 500);
  assert.equal(DB.batchCalls, 1);
  assert.equal(DB.quotas.get(`${who}\u001f${day}`), 12);
});

test("oyun kimliği ve adı doğrulanır", () => {
  assert.equal(titleId("PPSA01234"), "PPSA01234");
  assert.equal(titleId(" cusa00419_00 "), "CUSA00419_00");
  assert.equal(titleId("PPSA1234"), null);
  assert.equal(titleId("x'; DROP TABLE lines;--"), null);
  assert.equal(titleId(undefined), null);
  assert.equal(gameName("  Grand Theft Auto VI \n"), "Grand Theft Auto VI");
  assert.equal(gameName("A\u0000B"), "A B");
  assert.equal(gameName("x".repeat(300)).length, 120);
  assert.equal(gameName(""), null);
  assert.equal(gameName(42), null);
});

test("satırın oyunu havuza giren (ikinci) kurulumdan alınır; ilk bilinen oyun kalır", async () => {
  const DB = fakeDB();
  const env = { DB };
  const reply = await postLines(env, install(1), [
    { text: "Get in the car, Lucia.", titleId: "PPSA12345", game: "Grand Theft Auto VI" },
    { text: "Who is that over there?" },
    { text: "Keep your head down.", titleId: "bogus", game: "" },
  ]);
  assert.deepEqual(await reply.json(), { accepted: 3, recorded: 3 });
  assert.equal(DB.lines.size, 0);

  await postLines(env, install(2), [{ text: "Get in the car, Lucia.", titleId: "PPSA12345", game: "GTA VI" }]);
  const first = [...DB.lines.values()][0];
  assert.equal(first.installs, 2);
  assert.deepEqual([first.title, first.game], ["PPSA12345", "GTA VI"]);

  // Üçüncü kurulum başka oyunla bildirir: sayaç artar, oyun değişmez.
  await postLines(env, install(3), [{ text: "Get in the car, Lucia.", titleId: "CUSA00419", game: "GTA V" }]);
  const again = [...DB.lines.values()][0];
  assert.equal(again.installs, 3);
  assert.equal(again.title, "PPSA12345");
});

test("dışa aktarma oyuna göre süzülür (yalnız yönetici)", async () => {
  const DB = fakeDB();
  const env = { DB, ADMIN_TOKEN: "t" };
  const get = (query, auth = "Bearer t") => worker.fetch(new Request(`https://pool.test/v1/export?${query}`, {
    headers: { authorization: auth },
  }), env);
  assert.equal((await get("title=PPSA12345", "Bearer x")).status, 401);

  await get("title=ppsa12345&min=1");
  assert.match(DB.last.sql, /title_id=\?/);
  assert.match(DB.last.sql, /SELECT key,text,installs,first_seen,title_id,game/);
  assert.deepEqual(DB.last.args, [1, "PPSA12345", 5000]);

  await get("game=Grand%20Theft_Auto");
  assert.match(DB.last.sql, /game LIKE \? ESCAPE/);
  assert.deepEqual(DB.last.args, [2, "%Grand Theft\\_Auto%", 5000]);

  // Süzgeçsiz istek eski sütunlarla (geçişten önce de çalışır).
  await get("");
  assert.doesNotMatch(DB.last.sql, /title_id|game/);
});

test("oyunu bilinmeyen satırlar ortak pakete sıralanır (oyunu bilinenlerden sonra)", async () => {
  const stored = new Map([["index.json", JSON.stringify({ packs: [] })]]);
  const env = {
    AI: {},
    PACKS: {
      get: async (name) => (stored.has(name) ? { text: async () => stored.get(name) } : null),
      put: async (name, value) => { stored.set(name, value); },
    },
    DB: {
      prepare: (sql) => ({
        bind: () => ({
          all: async () => ({ results: sql.includes("GROUP BY title_id") ? [{ title_id: "PPSA01234", game: "X", lines: 400 }] : [] }),
          first: async () => (sql.includes("title_id IS NULL") ? { lines: 350 } : null),
        }),
      }),
    },
  };
  const plan = await runAutopack(env, new Date("2026-11-20T03:07:00Z"));
  assert.equal(plan.queued, 2);
  const state = JSON.parse(stored.get("auto/state.json"));
  assert.deepEqual(state.queue.map((t) => t.titleId), ["PPSA01234", GENERAL]);
});

test("oyun adı anahtarı aynı oyunun farklı yazımlarını birleştirir", () => {
  for (const name of ["Grand Theft Auto VI", "GTA 6", "gta vi", "GTA6", "Grand Theft Auto VI™"]) assert.equal(gameKey(name), "gta 6", name);
  assert.equal(gameKey("Marvel's Spider-Man 2"), "marvels spider man 2");
  assert.equal(gameKey("The Witcher 3: Wild Hunt"), "witcher 3 wild hunt");
  assert.equal(gameKey("Call of Duty: Black Ops 7"), "cod black ops 7");
  assert.equal(gameKey(""), "");
  assert.equal(gameSlug("gta 6"), "gta-6");
});

test("kimliksiz oyun adları anahtara göre birleşir; tek kurulumun adı ayrı paket açmaz", () => {
  const rows = [{ game: "GTA 6", lines: 200 }, { game: "Grand Theft Auto VI", lines: 300 }, { game: "Yanlış Oyun", lines: 900 }];
  const jobs = nameJobs(rows, new Map([["gta 6", 3], ["yanlis oyun", 1]]));
  assert.equal(jobs.length, 1);
  assert.equal(jobs[0].game, "Grand Theft Auto VI");
  assert.equal(jobs[0].lines, 500);
  assert.deepEqual(jobs[0].games, ["GTA 6", "Grand Theft Auto VI"]);
  assert.equal(jobPackId(jobs[0]), "pool-gta-6");
});

test("Latin dışı oyunlar ayrı paket alır, karışık adlar ASCII adla çakışmaz", () => {
  const names = ["星の旅", "夜の旅", "GTA 6 海外"];
  const votes = new Map(names.map((name) => [gameKey(name), 2]));
  const jobs = nameJobs(names.map((game) => ({ game, lines: 320 })), votes);
  assert.equal(jobs.length, 3, "Latin dışı adlar sessizce elenmemeli");
  const ids = jobs.map(jobPackId);
  assert.equal(new Set(ids).size, 3);
  assert.ok(ids.every((id) => /^[a-z0-9][a-z0-9-]{0,63}$/.test(id)));
  assert.notEqual(jobPackId({ titleId: null, gameKey: gameKey("GTA 6 海外") }), "pool-gta-6");
});

test("uzun oyun adları sunucunun kabul ettiği paket kimliği sınırında kalır", () => {
  const id = jobPackId({ titleId: null, gameKey: "x".repeat(80) });
  assert.match(id, /^[a-z0-9][a-z0-9-]{0,63}$/);
});

test("uzun oyun adlarının paket kimlikleri son karakterde ayrışır", () => {
  const first = jobPackId({ titleId: null, gameKey: "x".repeat(79) + "a" });
  const second = jobPackId({ titleId: null, gameKey: "x".repeat(79) + "b" });
  assert.notEqual(first, second);
  assert.match(first, /^[a-z0-9][a-z0-9-]{0,63}$/);
  assert.match(second, /^[a-z0-9][a-z0-9-]{0,63}$/);
});

test("kimliksiz oyun adı kurulum başına bir oy yazar", async () => {
  const DB = fakeDB();
  const votes = [];
  const batch = DB.batch;
  DB.batch = async (stmts) => {
    if (stmts.every((s) => s.sql.startsWith("INSERT OR IGNORE INTO game_votes"))) {
      votes.push(...stmts.map((s) => s.args));
      return stmts.map(() => ({ meta: { changes: 1 } }));
    }
    return batch(stmts);
  };
  await postLines({ DB }, install(1), [
    { text: "Get in the car, Lucia.", game: "Grand Theft Auto VI" },
    { text: "Keep your head down.", game: "GTA 6" },
    { text: "Who is that over there?", titleId: "PPSA12345", game: "Other" },
  ]);
  assert.deepEqual(votes, [["gta 6", install(1)]]);
});

test("export rejects negative and non-integer pagination before issuing SQL", async () => {
  const DB = fakeDB();
  const env = { DB, ADMIN_TOKEN: "t" };
  const get = (params) => worker.fetch(new Request(`https://pool.test/v1/export?${params}`, {
    headers: { authorization: "Bearer t" },
  }), env);
  for (const params of ["limit=-1", "limit=1.5", "limit=bogus", "min=bogus", "min=-5"]) {
    DB.last = null;
    const response = await get(params);
    assert.equal(response.status, 400, params);
    assert.equal(DB.last, null, `${params} must not execute a query`);
  }
  const valid = await get("limit=100000&min=3");
  assert.equal(valid.status, 200);
  assert.deepEqual(DB.last.args, [3, 20000]);
});

test("a failed line write does not silently lose its sighting on retry", async () => {
  const DB = fakeDB();
  const text = "Don't leave the engine running.";
  const first = await postLines({ DB }, install(1), [{ text }]);
  assert.equal(first.status, 200);
  assert.equal(DB.lines.size, 0);

  const original = DB.batch;
  let failWhenWritingLine = true;
  DB.batch = async (statements) => {
    if (failWhenWritingLine && statements.some((s) => s.sql.startsWith("INSERT INTO lines"))) {
      failWhenWritingLine = false;
      // D1.batch rejects the entire transaction if a statement fails.
      throw new Error("injected failure after sightings would otherwise commit");
    }
    return original(statements);
  };
  const failed = await postLines({ DB }, install(2), [{ text }]);
  assert.equal(failed.status, 500);
  assert.equal(DB.lines.size, 0);
  const retry = await postLines({ DB }, install(2), [{ text }]);
  assert.equal(retry.status, 200);
  assert.equal(DB.lines.size, 1, "retry must still publish a line seen by two distinct installs");
  assert.equal([...DB.lines.values()][0].installs, 2);
});

test("admin export endpoints reject methods outside their documented routes", async () => {
  const DB = fakeDB();
  const env = { DB, ADMIN_TOKEN: "t" };
  const invoke = (path, method, body) => worker.fetch(new Request("https://pool.test" + path, {
    method,
    headers: { authorization: "Bearer t" },
    ...(body ? { body: JSON.stringify(body) } : {}),
  }), env);

  for (const [path, method, body, allow] of [
    ["/v1/export", "POST", { keys: ["1234567890abcdef"] }, "GET"],
    ["/v1/exported", "GET", null, "POST"],
    ["/v1/export", "PATCH", { keys: [] }, "GET"],
  ]) {
    DB.last = null;
    const writes = DB.writes;
    const response = await invoke(path, method, body);
    assert.equal(response.status, 405, method + " " + path);
    assert.equal(response.headers.get("allow"), allow);
    assert.equal(DB.last, null, "wrong methods must not run a DB read");
    assert.equal(DB.writes, writes, "wrong methods must not mutate DB");
  }
  assert.equal((await invoke("/v1/export", "GET")).status, 200);
  assert.equal((await invoke("/v1/exported", "POST", { keys: [] })).status, 200);
});
