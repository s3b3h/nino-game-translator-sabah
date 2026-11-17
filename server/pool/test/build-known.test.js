// SPDX-License-Identifier: AGPL-3.0-only
import { execFileSync } from "node:child_process";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("../scripts/build-known.mjs", import.meta.url));
const defaultPacks = fileURLToPath(new URL("../../../core/Sources/CouchSubsCore/Resources/packs/", import.meta.url));

test("build-known uses its default pack directory on all platforms", () => {
  const options = { stdio: ["ignore", "pipe", "ignore"], maxBuffer: 16 * 1024 * 1024 };
  const explicit = execFileSync(process.execPath, [script, defaultPacks], options);
  const inferred = execFileSync(process.execPath, [script], options);

  assert.ok(explicit.length > 0);
  assert.deepStrictEqual(inferred, explicit);
});
