// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { canon, lineKey } from "../src/key.js";

// Uygulamaların ortak deneme verisi: sunucu anahtarı Mac/Windows/Android ile birebir aynı hesaplamalı.
const vectors = JSON.parse(
  readFileSync(new URL("../../core/Tests/CouchSubsCoreTests/Fixtures/golden-vectors.json", import.meta.url), "utf8"),
);

test("anahtar uygulamalardaki PackKey ile aynı", async () => {
  assert.ok(vectors.length > 5);
  for (const v of vectors) {
    assert.equal(canon(v.input), v.canon, `canon: ${JSON.stringify(v.input)}`);
    assert.equal(await lineKey(v.input), v.key || null, `key: ${JSON.stringify(v.input)}`);
  }
});

test("yazılış farkı aynı anahtar", async () => {
  assert.equal(await lineKey("Get down!"), await lineKey("GET   DOWN"));
  assert.equal(await lineKey("!!!"), null);
});
