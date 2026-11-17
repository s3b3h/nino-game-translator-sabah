import assert from "node:assert/strict";
import test from "node:test";
import { GENERAL, jobPackId, parseReply, runAutopack } from "../src/autopack.js";

test("malformed current-night state is rebuilt instead of stopping the scheduler", async () => {
  const now = new Date("2026-11-20T04:00:00Z");
  for (const invalid of [
    { night: "2026-11-20", translated: 0, done: [] },
    { night: "2026-11-20", queue: {}, translated: 0, done: [] },
    { night: "2026-11-20", queue: [], translated: -1, done: [] },
  ]) {
    const stored = new Map([
      ["auto/state.json", JSON.stringify(invalid)],
      ["index.json", JSON.stringify({ packs: [] })],
    ]);
    const env = {
      AI: {},
      PACKS: {
        get: async (name) => stored.has(name) ? { text: async () => stored.get(name) } : null,
        put: async (name, value) => { stored.set(name, value); },
      },
      DB: {
        prepare: () => ({
          bind: () => ({
            all: async () => ({ results: [] }),
            first: async () => ({ lines: 0 }),
          }),
        }),
      },
    };
    const result = await runAutopack(env, now);
    assert.equal(result.phase, "plan");
    assert.deepEqual(JSON.parse(stored.get("auto/state.json")).queue, []);
  }
});

test("general pool scans past separated game rows before applying the row limit", async () => {
  const now = new Date("2026-11-20T04:00:00Z");
  const state = {
    night: now.toISOString().slice(0, 10),
    queue: [{ titleId: GENERAL, game: null, lines: 350 }],
    namedGames: ["GTA 6"],
    translated: 0,
    done: [],
  };
  const stored = new Map([
    ["auto/state.json", JSON.stringify(state)],
    ["index.json", JSON.stringify({ packs: [] })],
  ]);
  const rows = [
    ...Array.from({ length: 5_001 }, (_, i) => ({
      key: (0x1000000000000000n + BigInt(i)).toString(16).padStart(16, "0"),
      text: "Get in the car, Lucia.",
      game: "GTA 6",
      installs: 10,
      last_seen: "2026-11-20T03:00:00.000Z",
    })),
    ...Array.from({ length: 350 }, (_, i) => ({
      key: (0x2000000000000000n + BigInt(i)).toString(16).padStart(16, "0"),
      text: "Get in the car, Lucia.",
      game: null,
      installs: 2,
      last_seen: "2026-11-20T02:00:00.000Z",
    })),
  ];
  let generalQuery;
  const env = {
    AI: {
      run: async (_model, { messages }) => {
        const count = messages[1].content.split("\n").filter(Boolean).length;
        return {
          response: JSON.stringify({
            items: Array.from({ length: count }, (_, i) => ({ id: String(i), tr: "Arabaya bin, Lucia." })),
          }),
        };
      },
    },
    PACKS: {
      get: async (name) => name === "auto/known-keys.bin"
        ? { arrayBuffer: async () => new ArrayBuffer(0) }
        : stored.has(name) ? { text: async () => stored.get(name) } : null,
      put: async (name, value) => { stored.set(name, value); },
    },
    DB: {
      prepare: (sql) => ({
        bind: (...args) => ({
          all: async () => {
            generalQuery = { sql, args };
            const separated = sql.includes("json_each(?)") ? JSON.parse(args[1]) : [];
            const eligible = rows.filter((row) => !row.game || !separated.includes(row.game));
            eligible.sort((a, b) => b.installs - a.installs || b.last_seen.localeCompare(a.last_seen));
            return { results: eligible.slice(0, 5_000) };
          },
        }),
      }),
    },
  };

  const result = await runAutopack(env, now);

  assert.equal(result.phase, "translate");
  assert.equal(result.looked, 200);
  assert.equal(result.translated, 200);
  assert.match(generalQuery.sql, /json_each\(\?\)/);
  assert.deepEqual(generalQuery.args, [2, JSON.stringify(["GTA 6"])]);
  const cache = JSON.parse(stored.get("auto/tr/GENEL.json"));
  const translatedKeys = Object.keys(cache.lines);
  assert.equal(translatedKeys.length, 200);
  assert.ok(translatedKeys.every((key) => key.startsWith("2")));
});


test("AI parser ignores malformed item collections and IDs without misassigning subtitles", async () => {

  const lines = [{ en: "Where are you going?" }, { en: "We have to leave now." }];
  for (const items of [null, {}, 42, true]) {
    const reply = { response: JSON.stringify({ items }) };
    assert.deepEqual([...parseReply(reply, lines)], [], `malformed items: ${JSON.stringify(items)}`);
  }
  for (const id of [null, "", " ", true, false, {}, -1, 1.5, "0abc"]) {
    const reply = { response: JSON.stringify({ items: [{ id, tr: "Yanlış satıra yazılmamalı." }] }) };
    assert.deepEqual([...parseReply(reply, lines)], [], `invalid id: ${JSON.stringify(id)}`);
  }
  const valid = { response: JSON.stringify({ items: [{ id: "0", tr: "Nereye gidiyorsun?" }, { id: 1, tr: "Hemen gitmeliyiz." }] }) };
  assert.deepEqual([...parseReply(valid, lines)], [[0, "Nereye gidiyorsun?"], [1, "Hemen gitmeliyiz."]]);
});

test("autopack never replaces an absent or unreadable pack index", async () => {
  const now = new Date("2026-11-20T04:00:00Z");
  const job = { titleId: GENERAL, game: null, lines: 350 };
  const cache = {
    lines: Object.fromEntries(Array.from({ length: 300 }, (_, i) => {
      const k = (BigInt(i) + 1n).toString(16).padStart(16, "0");
      return [k, { k, en: "Get in the car, Lucia.", tr: "Arabaya bin, Lucia." }];
    })),
    skip: {}, fail: {},
  };
  for (const rawIndex of [null, "{broken json", JSON.stringify({ packs: null })]) {
    const state = { night: "2026-11-20", queue: [job], translated: 0, done: [] };
    const stored = new Map([
      ["auto/state.json", JSON.stringify(state)],
      ["auto/tr/GENEL.json", JSON.stringify(cache)],
    ]);
    if (rawIndex !== null) stored.set("index.json", rawIndex);
    const writes = [];
    const env = {
      AI: {},
      PACKS: {
        get: async (name) => name === "auto/known-keys.bin"
          ? { arrayBuffer: async () => new ArrayBuffer(0) }
          : stored.has(name) ? { text: async () => stored.get(name) } : null,
        put: async (name, value) => { writes.push(name); stored.set(name, value); },
      },
      DB: {
        prepare: () => ({ bind: () => ({ all: async () => ({ results: [] }) }) }),
      },
    };

    await assert.rejects(runAutopack(env, now), /index.*(missing|invalid|unavailable)/i);
    assert.deepEqual(writes, [], `index was ${rawIndex}: no package or index may be overwritten`);
    assert.deepEqual(JSON.parse(stored.get("auto/state.json")), state);
  }
});

test("autopack must not publish an empty pack when an existing translation cache is corrupted", async () => {
  const now = new Date("2026-11-20T04:00:00Z");
  const state = {
    night: "2026-11-20",
    queue: [{ titleId: GENERAL, game: null, lines: 350 }],
    translated: 0, done: [],
  };
  for (const cacheRaw of ["{broken", JSON.stringify({ lines: [], skip: {} }), JSON.stringify({ lines: null, skip: {} })]) {
    const stored = new Map([
      ["auto/state.json", JSON.stringify(state)],
      ["index.json", JSON.stringify({ packs: [{ id: "pool-genel", version: 1 }] })],
      ["auto/tr/GENEL.json", cacheRaw],
    ]);
    const writes = [];
    const env = {
      AI: {},
      PACKS: {
        get: async (name) => name === "auto/known-keys.bin"
          ? { arrayBuffer: async () => new ArrayBuffer(0) }
          : stored.has(name) ? { text: async () => stored.get(name) } : null,
        put: async (name, value) => { writes.push(name); stored.set(name, value); },
      },
      DB: {
        prepare: () => ({ bind: () => ({ all: async () => ({ results: [] }) }) }),
      },
    };
    const result = await runAutopack(env, now);
    assert.equal(result.phase, "waiting");
    assert.deepEqual(writes, [], "corrupt cache must not cause pack or index writes");
    assert.deepEqual(JSON.parse(stored.get("auto/state.json")), state);
  }
});

test("autopack waits rather than using a truncated manual-key index", async () => {
  const now = new Date("2026-11-20T04:00:00Z");
  const state = {
    night: "2026-11-20",
    queue: [{ titleId: GENERAL, game: null, lines: 350 }],
    translated: 0, done: [],
  };
  const malformed = [new Uint8Array(9).buffer];
  for (const bytes of malformed) {
    const stored = new Map([["auto/state.json", JSON.stringify(state)]]);
    const writes = [];
    const env = {
      AI: {},
      PACKS: {
        get: async (name) => name === "auto/known-keys.bin"
          ? { arrayBuffer: async () => bytes }
          : stored.has(name) ? { text: async () => stored.get(name) } : null,
        put: async (name, value) => { writes.push(name); stored.set(name, value); },
      },
      DB: {
        prepare: () => ({ bind: () => ({ all: async () => ({ results: [] }) }) }),
      },
    };
    const result = await runAutopack(env, now);
    assert.equal(result.phase, "waiting");
    assert.deepEqual(writes, []);
    assert.deepEqual(JSON.parse(stored.get("auto/state.json")), state);
  }
});

test("autopack preserves published translations when their R2 cache is missing", async () => {
  const now = new Date("2026-11-20T04:00:00Z");
  const state = { night: "2026-11-20", queue: [{ titleId: GENERAL, game: null, lines: 350 }], translated: 0, done: [] };
  const index = { packs: [{ id: "pool-genel", version: 4, entries: 350, sha256: "a".repeat(64) }] };
  const stored = new Map([
    ["auto/state.json", JSON.stringify(state)],
    ["index.json", JSON.stringify(index)],
    // A previous cache may disappear independently from the published pack in R2.
  ]);
  const writes = [];
  const env = {
    AI: {},
    PACKS: {
      get: async (name) => name === "auto/known-keys.bin"
        ? { arrayBuffer: async () => new ArrayBuffer(0) }
        : stored.has(name) ? { text: async () => stored.get(name) } : null,
      put: async (name, data) => { writes.push(name); stored.set(name, data); },
    },
    DB: { prepare: () => ({ bind: () => ({ all: async () => ({ results: [] }) }) }) },
  };

  const result = await runAutopack(env, now);
  assert.equal(result.phase, "waiting", "missing cache cannot be treated as an empty existing pack");
  assert.deepEqual(writes, [], "neither the existing pack nor its index may be overwritten");
  assert.deepEqual(JSON.parse(stored.get("index.json")), index);
  assert.deepEqual(JSON.parse(stored.get("auto/state.json")), state);
});

test("long ASCII game names keep separate translation caches when their pack IDs differ", async () => {
  const now = new Date("2026-11-20T04:00:00Z");
  const shared = "the exceptionally long game title that shares a lengthy prefix ";
  const games = [shared + "alpha", shared + "beta"];
  const jobs = games.map((gameKey) => ({
    titleId: null, gameKey, game: gameKey, games: [gameKey], lines: 301,
  }));
  assert.notEqual(jobPackId(jobs[0]), jobPackId(jobs[1]));

  const stored = new Map([["index.json", JSON.stringify({ packs: [] })]]);
  const env = {
    PACKS: {
      get: async (name) => name === "auto/known-keys.bin"
        ? { arrayBuffer: async () => new ArrayBuffer(0) }
        : stored.has(name) ? { text: async () => stored.get(name) } : null,
      put: async (name, value) => { stored.set(name, value); },
    },
    AI: {
      run: async () => ({ response: JSON.stringify({ items: [{ id: "0", tr: "Hemen kap?ya ilerlemeliyiz." }] }) }),
    },
    DB: {
      prepare: () => ({
        bind: (...args) => ({
          all: async () => ({ results: [{
            key: args[0] === games[0] ? "1111111111111111" : "2222222222222222",
            text: "We must get to the gate right now.",
          }] }),
        }),
      }),
    },
  };
  for (const job of jobs) {
    stored.set("auto/state.json", JSON.stringify({
      night: "2026-11-20", queue: [job], namedGames: [job.game],
      translated: 0, done: [],
    }));
    const result = await runAutopack(env, now);
    assert.equal(result.phase, "translate");
    assert.equal(result.translated, 1);
  }
  const cacheFiles = [...stored.keys()].filter((name) => name.startsWith("auto/tr/name-"));
  assert.equal(cacheFiles.length, 2, "distinct published pack IDs must not share a translation cache");
  const cachedKeys = cacheFiles.map((name) => Object.keys(JSON.parse(stored.get(name)).lines));
  assert.deepEqual(cachedKeys.map((keys) => keys.length), [1, 1]);
});
