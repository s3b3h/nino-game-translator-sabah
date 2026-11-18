// SPDX-License-Identifier: AGPL-3.0-only
// Yardımcının modellerini aynı sorularla dener (assistant/deneme-sorulari.json). Gerçek API'yi çağırır, ücretlidir.
// Kullanım: ASSISTANT_PROVIDER=gemini GEMINI_API_KEY=... node scripts/eval-assistant.mjs
//           ASSISTANT_PROVIDER=anthropic ANTHROPIC_API_KEY=... node scripts/eval-assistant.mjs
import { readFileSync } from "node:fs";
import { askModel, systemText } from "../src/assistant.js";

const questions = JSON.parse(readFileSync(new URL("../assistant/deneme-sorulari.json", import.meta.url)));
const env = process.env;
let passed = 0;
for (const item of questions) {
  const started = Date.now();
  let answer;
  try {
    answer = await askModel(env, systemText(item.lang, "android"), [{ role: "user", text: item.q, images: [] }]);
  } catch (error) {
    console.log(`✗ ${item.q}\n   HATA: ${error.message}`);
    continue;
  }
  const reply = answer?.reply ?? "";
  const ok = item.must.every((pattern) => new RegExp(pattern, "i").test(reply))
    && item.mustNot.every((pattern) => !new RegExp(pattern).test(reply))
    && (item.expectReport === undefined || Boolean(answer?.report) === item.expectReport);
  if (ok) passed++;
  console.log(`${ok ? "✓" : "✗"} [${item.lang}] ${item.q} (${Date.now() - started} ms)\n   ${reply.replace(/\n/g, "\n   ")}${answer?.report ? `\n   [bildirim: ${answer.report.summary}]` : ""}\n`);
}
console.log(`${passed}/${questions.length} geçti (${env.ASSISTANT_PROVIDER} ${env.ASSISTANT_MODEL ?? "varsayılan model"})`);
