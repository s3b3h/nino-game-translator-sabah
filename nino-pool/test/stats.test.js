// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { makeD1 } from "./d1-shim.js";
import { handle } from "../src/worker.js";

const NOW = 1763300000;
const TOKEN = "panel-anahtari";

test("panel: şu an oynayan, kurulumlar, çeviriler; anahtarsız açılmaz", async () => {
  const env = { DB: makeD1(), EXPORT_TOKEN: TOKEN, INSTALL_SALT: "tuz", ANTHROPIC_API_KEY: "k", STATS_GITHUB: "0" };
  const live = async (_e, _l, lines) => ({ texts: lines.map((l) => "TR " + l), cost: 300 });
  const a = randomUUID(), b = randomUUID();
  const ping = (install, platform, game, now = NOW) =>
    handle(new Request(`http://pool/v1/ping?install=${install}&platform=${platform}&app=0.2.2&game=${game}&lang=tr`), env, now);
  assert.equal((await ping(a, "mac", "gta-vi")).status, 204);
  await ping(b, "ios", "gta-vi", NOW - 600); // 10 dk önce: şu an oynamıyor
  await handle(new Request("http://pool/v1/translate", { method: "POST", body: JSON.stringify({
    v: 1, install: a, app: "0.2.2", platform: "mac", lang: "tr", game: "gta-vi", lines: ["Get in the car right now!"] }) }),
    env, NOW, undefined, live);
  assert.equal((await handle(new Request("http://pool/v1/stats"), env, NOW)).status, 401);
  const res = await handle(new Request("http://pool/v1/stats", { headers: { authorization: `Bearer ${TOKEN}` } }), env, NOW,
    undefined, undefined);
  const s = await res.json();
  assert.equal(s.players.now, 1);
  assert.deepEqual(s.players.games, [{ game: "gta-vi", n: 1 }]);
  assert.equal(s.players.installs, 2);
  assert.equal(s.players.active24h, 2);
  assert.equal(s.translations.lines, 1);
  assert.equal(s.translations.words, 6);
  assert.equal(s.spend.translateToday, 0.0003);
  const page = await handle(new Request("http://pool/panel"), env, NOW);
  assert.match(await page.text(), /Nino Panel/);
});
