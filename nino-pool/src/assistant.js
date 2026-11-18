// SPDX-License-Identifier: AGPL-3.0-only
// Nino yardımcısı ("Nino robotu"): uygulamalardaki sohbet. Kullanıcının sorusunu (ve ekran görüntülerini) kurulum bilgi
// tabanıyla birlikte seçilen modele sorar; model çözemediğini kullanıcı onaylarsa Sorun Bildir'e bildirim yazar.
// Model sunucu ayarıyla seçilir (ASSISTANT_PROVIDER: anthropic | gemini | deepseek, ASSISTANT_MODEL); anahtarlar
// Cloudflare sırlarıdır (ANTHROPIC_API_KEY, GEMINI_API_KEY, DEEPSEEK_API_KEY) ve uygulamalara hiç gitmez.

import Anthropic from "@anthropic-ai/sdk";
import { KNOWLEDGE } from "./knowledge.js";
import { saltedDigest } from "./key.js";
import { receiveReport } from "./reports.js";

export const ASSISTANT_LIMITS = {
  maxBodyBytes: 6 * 1024 * 1024,
  maxMessages: 24,
  maxText: 2000,
  maxImages: 3,
  maxImageBytes: 1500 * 1024,
  perInstallPerDay: 60,
  dailyBudget: 4000,
  // Günlük en çok harcama (dolar). Aşılınca yardımcı ertesi güne kadar "çok yoğunum" der.
  dailyUsd: 2,
  // Hazır cevaplar bu kadar gün geçerli; bilgi tabanı değişince zaten yeni anahtar oluşur.
  answerDays: 30,
};

// Model fiyatları (dolar / milyon token). 1 dolar/MTok = token başına 1 mikro dolar.
// Bilinmeyen model ya da sağlayıcı için güvenli tarafta kalan istek başı tahmin kullanılır.
const PRICES = {
  "claude-haiku-5-5": { input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite1h: 0.20 },
};
const FALLBACK_REQUEST_MICRO_USD = 5000;

/** Anthropic kullanım bilgisinden maliyet (mikro dolar). */
export function usageCost(model, usage) {
  const price = PRICES[model];
  if (!price || !usage) return FALLBACK_REQUEST_MICRO_USD;
  return Math.ceil(
    (usage.input_tokens ?? 0) * price.input +
    (usage.output_tokens ?? 0) * price.output +
    (usage.cache_read_input_tokens ?? 0) * price.cacheRead +
    (usage.cache_creation_input_tokens ?? 0) * price.cacheWrite1h,
  );
}

/** Hazır cevap anahtarı: yalnız resimsiz, tek mesajlık ilk soru için; aksi hâlde null. */
async function answerKey(input) {
  if (input.messages.length !== 1 || input.messages[0].images.length) return null;
  const text = input.messages[0].text.toLocaleLowerCase("tr").normalize("NFKC")
    .replace(/[\p{P}\p{S}]+/gu, " ").replace(/\s+/g, " ").trim();
  if (!text) return null;
  const source = `${KNOWLEDGE.length}|${INSTRUCTIONS.length}|${input.language}|${input.platform}|${text}`;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(source));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const PLATFORMS = new Set(["mac", "windows", "linux", "android", "ios", "tv"]);
const MIMES = new Set(["image/jpeg", "image/png", "image/webp"]);
const DEFAULT_MODELS = { anthropic: "claude-haiku-5-5", gemini: "gemini-flash-lite-latest", deepseek: "deepseek-chat" };

const INSTRUCTIONS = `You are "Nino", the friendly little robot helper inside the Nino Game Translator apps. You help people install
and use Nino: the free, open-source app that translates English subtitles of PS5 and Xbox games live and shows them on
the TV on top of the game.

How to answer:
- Always reply in the language the user writes in (if unclear, use the app language given below).
- The NINO KNOWLEDGE is written in Turkish. When you answer in another language, write EVERYTHING in that language,
  including menu and button names: translate Nino's own menu names (e.g. "Profil › Nino'yu TV'ye Kur" →
  "Profile › Install Nino on TV" in English), and give TV, PS5, Xbox, Windows and Mac menu names as they appear in that
  language. Never leave Turkish words in a non-Turkish answer.
- In Turkish always use the casual "sen" form (kurdun mu, söyler misin), never "siz".
- Be warm, short and concrete. Format every answer for easy reading on a phone:
  * one short opening sentence (no "Merhaba, ben Nino" after the first message), then an empty line;
  * steps as a numbered list, each step on its OWN line starting with "1.", "2.", … and ONE short action per step
    (max ~15 words; put the menu path in the step, e.g. "Ayarlar › Sistem › Hakkında'yı aç.");
  * put an empty line between steps and before any closing note or question;
  * a closing question or tip goes in its own short paragraph at the end.
  Plain text only: no tables, no headings, no bold/markdown, no markdown links (write URLs plainly).
- Base every answer on the NINO KNOWLEDGE below. If it doesn't cover the question, say honestly that you are not sure
  and suggest sending a report. Never invent menu names, features, prices or dates.
- Your character: a cheerful little robot with a red Turkish-flag cap. Friendly and casual ("sen" in Turkish), never
  childish; a light emoji now and then is fine.
- Think like an expert support technician. Start from the user's setup. If you don't yet know their devices, first
  ask (in one short message) which they have and where they want Nino: console (PS5 or Xbox), screen (Android TV /
  Google TV, Samsung or LG TV, smart or plain monitor, TV brand and model), and what runs Nino (Mac, Windows PC,
  Android phone, iPhone). When they answer (e.g. "monitor, PS5, phone"), pick the right path from the knowledge and
  give a short, numbered plan for exactly that setup.
- When something goes wrong, find WHERE it fails before answering: which step of the setup, what the screen shows,
  the exact error text, app versions. Ask ONE focused question at a time (never a long questionnaire) and ask for a
  screenshot when it would help; when the user sends one, read it carefully (menus, error text, which app/screen).
  Then give the most likely fix first, then the next one if that doesn't help.
- Stay on topic: Nino, consoles, TVs, monitors, capture cards, streaming with Nino. Politely decline other topics.
- Never ask for passwords, PSN/Microsoft credentials, API keys or payment details.

Reports to the Nino team (the bug pool):
- Send a report RIGHT AWAY (no need to ask permission) when:
  * it is a bug in Nino: a crash, a button or screen that doesn't work, wrong/missing subtitles or translation that
    isn't explained by settings, an error message from Nino, something the knowledge says should work but doesn't;
  * or you have tried the fixes the knowledge offers and the problem is still not solved;
  * or the user asks for a feature or device Nino doesn't support yet (kind "request").
- To send: set "report" with kind ("bug", "unsolved" or "request") and a short English summary for the team: Nino
  device and app, console, TV/monitor brand and model, language, what happens, at which step, error text, what was
  already tried. In your reply tell the user briefly that you sent it to the team and that they will look at it, and
  still give any workaround you know.
- Send at most one report per problem in a conversation: if your earlier reply already says you sent it, don't send it
  again unless there is clearly new information.
- Otherwise "report" is null.

Reply with JSON only: {"reply": "<message to the user>", "report": null or {"kind": "bug" | "unsolved" | "request", "summary": "<for the team>"}}.`;

const REPLY_SCHEMA = {
  type: "object",
  properties: {
    reply: { type: "string" },
    report: {
      anyOf: [
        { type: "null" },
        { type: "object", properties: { kind: { type: "string", enum: ["bug", "unsolved", "request"] }, summary: { type: "string" } }, required: ["kind", "summary"], additionalProperties: false },
      ],
    },
  },
  required: ["reply", "report"],
  additionalProperties: false,
};

export function systemText(language, platform) {
  return `${INSTRUCTIONS}\n\nApp language: ${language || "unknown"}. User's device running Nino: ${platform}.`;
}

function decodeBase64(text) {
  if (typeof text !== "string" || !/^[A-Za-z0-9+/=\s]+$/.test(text)) return null;
  try {
    return atob(text.replace(/\s+/g, "")).length;
  } catch {
    return null;
  }
}

/** Gelen sohbeti doğrular: [{role: "user"|"assistant", text, images?: [{mime, data}]}]; son mesaj kullanıcınındır. */
export function validateConversation(body) {
  if (!body || typeof body !== "object" || body.v !== 1) return { error: "bad_request" };
  const install = typeof body.install === "string" ? body.install : "";
  if (install.length < 8 || install.length > 64) return { error: "bad_request" };
  const platform = PLATFORMS.has(body.platform) ? body.platform : "";
  if (!platform) return { error: "bad_platform" };
  const raw = Array.isArray(body.messages) ? body.messages.slice(-ASSISTANT_LIMITS.maxMessages) : [];
  if (!raw.length || raw[raw.length - 1]?.role !== "user") return { error: "bad_request" };
  let imageCount = 0;
  const messages = [];
  for (const message of raw) {
    const role = message?.role === "assistant" ? "assistant" : message?.role === "user" ? "user" : null;
    if (!role) return { error: "bad_request" };
    const text = typeof message.text === "string" ? message.text.slice(0, ASSISTANT_LIMITS.maxText) : "";
    const images = [];
    for (const image of (role === "user" && Array.isArray(message.images) ? message.images : [])) {
      const size = decodeBase64(image?.data);
      if (!MIMES.has(image?.mime) || !size) return { error: "bad_image" };
      if (size > ASSISTANT_LIMITS.maxImageBytes) return { error: "image_too_large", status: 413 };
      images.push({ mime: image.mime, data: image.data.replace(/\s+/g, "") });
    }
    imageCount += images.length;
    if (!text.trim() && !images.length) continue;
    messages.push({ role, text, images });
  }
  if (imageCount > ASSISTANT_LIMITS.maxImages * 2) return { error: "too_many_images" };
  if (!messages.length || messages[messages.length - 1].role !== "user") return { error: "bad_request" };
  return {
    install, platform, messages,
    app: typeof body.app === "string" ? body.app.slice(0, 40) : "",
    language: typeof body.language === "string" ? body.language.slice(0, 16) : "",
  };
}

// ---- Modeller ----

async function askAnthropic(env, model, system, messages) {
  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });
  const response = await client.messages.create({
    model,
    max_tokens: 2000,
    // Bilgi tabanı sabit kalır ve önbelleğe alınır; her soruda yeniden ücretlendirilmez.
    system: [
      { type: "text", text: `NINO KNOWLEDGE:\n\n${KNOWLEDGE}`, cache_control: { type: "ephemeral", ttl: "1h" } },
      { type: "text", text: system },
    ],
    messages: messages.map((m) => ({
      role: m.role,
      content: [
        ...m.images.map((image) => ({ type: "image", source: { type: "base64", media_type: image.mime, data: image.data } })),
        { type: "text", text: m.text || "(screenshot)" },
      ],
    })),
    output_config: { effort: "medium", format: { type: "json_schema", schema: REPLY_SCHEMA } },
  });
  const cost = usageCost(model, response.usage);
  if (response.stop_reason === "refusal") return { reply: "", report: null, refused: true, cost };
  const text = response.content.filter((block) => block.type === "text").map((block) => block.text).join("");
  return { ...JSON.parse(text), cost };
}

async function askGemini(env, model, system, messages, fetcher) {
  const response = await fetcher(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: `NINO KNOWLEDGE:\n\n${KNOWLEDGE}\n\n${system}` }] },
      contents: messages.map((m) => ({
        role: m.role === "assistant" ? "model" : "user",
        parts: [...m.images.map((image) => ({ inlineData: { mimeType: image.mime, data: image.data } })), { text: m.text || "(screenshot)" }],
      })),
      generationConfig: {
        maxOutputTokens: 1500,
        responseMimeType: "application/json",
        responseSchema: {
          type: "OBJECT",
          properties: { reply: { type: "STRING" }, report: { type: "OBJECT", nullable: true, properties: { kind: { type: "STRING", enum: ["bug", "unsolved", "request"] }, summary: { type: "STRING" } } } },
          required: ["reply"],
        },
      },
    }),
  });
  if (!response.ok) throw new Error(`gemini ${response.status}`);
  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts?.map((p) => p.text ?? "").join("") ?? "";
  return JSON.parse(text);
}

async function askDeepSeek(env, model, system, messages, fetcher) {
  // DeepSeek resim göremez: ekran görüntüsü yalnız "gönderildi" diye belirtilir.
  const response = await fetcher("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${env.DEEPSEEK_API_KEY}` },
    body: JSON.stringify({
      model,
      max_tokens: 1500,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: `NINO KNOWLEDGE:\n\n${KNOWLEDGE}\n\n${system}` },
        ...messages.map((m) => ({
          role: m.role,
          content: (m.images.length ? `[The user attached ${m.images.length} screenshot(s) you cannot see; ask them to describe it.]\n` : "") + (m.text || ""),
        })),
      ],
    }),
  });
  if (!response.ok) throw new Error(`deepseek ${response.status}`);
  const data = await response.json();
  return JSON.parse(data?.choices?.[0]?.message?.content ?? "");
}

/** Seçili modele sorar. Döner: { reply, report: null | { summary } }. Testlerde `ask` verilerek değiştirilir. */
export async function askModel(env, system, messages, fetcher = fetch) {
  const provider = env.ASSISTANT_PROVIDER;
  const model = env.ASSISTANT_MODEL || DEFAULT_MODELS[provider];
  if (provider === "anthropic") return askAnthropic(env, model, system, messages);
  if (provider === "gemini") return askGemini(env, model, system, messages, fetcher);
  if (provider === "deepseek") return askDeepSeek(env, model, system, messages, fetcher);
  throw new Error("no provider");
}

export function assistantEnabled(env) {
  const keys = { anthropic: env.ANTHROPIC_API_KEY, gemini: env.GEMINI_API_KEY, deepseek: env.DEEPSEEK_API_KEY };
  return Boolean(env.ASSISTANT_PROVIDER && keys[env.ASSISTANT_PROVIDER]);
}

/** POST /v1/assistant. Döner: { status, body, retryAfter? }. */
export async function handleAssistant(db, env, body, now, ask = askModel) {
  if (!assistantEnabled(env)) return { status: 503, body: { ok: false, error: "assistant_disabled" } };
  const input = validateConversation(body);
  if (input.error) return { status: input.status ?? 400, body: { ok: false, error: input.error } };

  const day = Math.floor(now / 86400);
  const install = await saltedDigest(input.install, env.INSTALL_SALT ?? "");
  const perInstall = Number(env.ASSISTANT_PER_INSTALL ?? ASSISTANT_LIMITS.perInstallPerDay);
  const budget = Number(env.ASSISTANT_DAILY_BUDGET ?? ASSISTANT_LIMITS.dailyBudget);
  const mine = await db.prepare("SELECT count FROM assistant_usage WHERE install = ? AND day = ?").bind(install, day).first("count");
  if ((mine ?? 0) >= perInstall) return { status: 429, body: { ok: false, error: "rate_limited" }, retryAfter: 3600 };
  const total = await db.prepare("SELECT COALESCE(SUM(count), 0) AS n FROM assistant_usage WHERE day = ?").bind(day).first("n");
  if ((total ?? 0) >= budget) return { status: 429, body: { ok: false, error: "busy" }, retryAfter: 3600 };
  await db.prepare("INSERT INTO assistant_usage (install, day, count) VALUES (?, ?, 1) ON CONFLICT(install, day) DO UPDATE SET count = count + 1")
    .bind(install, day).run();

  // Hazır cevap: aynı ilk soru daha önce sorulduysa modele gitmeden (ücretsiz) verilir.
  const key = await answerKey(input);
  if (key) {
    const saved = await db.prepare("SELECT reply FROM assistant_answers WHERE key = ? AND created > ?")
      .bind(key, now - ASSISTANT_LIMITS.answerDays * 86400).first("reply");
    if (saved) {
      await db.prepare("UPDATE assistant_answers SET hits = hits + 1 WHERE key = ?").bind(key).run();
      return { status: 200, body: { ok: true, reply: saved, report: null } };
    }
  }

  // Günlük harcama sınırı (varsayılan 2 dolar).
  const capMicro = Math.round(Number(env.ASSISTANT_DAILY_USD ?? ASSISTANT_LIMITS.dailyUsd) * 1_000_000);
  const spent = await db.prepare("SELECT micro_usd FROM assistant_cost WHERE day = ?").bind(day).first("micro_usd");
  if ((spent ?? 0) >= capMicro) return { status: 429, body: { ok: false, error: "busy" }, retryAfter: 3600 };

  let answer;
  try {
    answer = await ask(env, systemText(input.language, input.platform), input.messages);
  } catch (error) {
    console.error("yardımcı hatası", error);
    await addCost(db, day, FALLBACK_REQUEST_MICRO_USD);
    return { status: 502, body: { ok: false, error: "model_failed" } };
  }
  await addCost(db, day, Number.isFinite(answer?.cost) ? answer.cost : FALLBACK_REQUEST_MICRO_USD);
  const reply = typeof answer?.reply === "string" ? answer.reply.trim() : "";
  if (!reply) return { status: 502, body: { ok: false, error: answer?.refused ? "refused" : "model_failed" } };

  let reportId = null;
  const summary = typeof answer?.report?.summary === "string" ? answer.report.summary.trim() : "";
  if (summary) {
    // Bildirim: modelin özeti, sohbetin metni ve sohbetteki son en çok 3 ekran görüntüsü.
    const transcript = input.messages.map((m) => `${m.role === "user" ? "Kullanıcı" : "Nino"}: ${m.text}${m.images.length ? ` [${m.images.length} ekran görüntüsü]` : ""}`).join("\n");
    const images = input.messages.flatMap((m) => m.images).slice(-3);
    const saved = await receiveReport(db, env, {
      v: 1, install: input.install, app: input.app, platform: input.platform, language: input.language,
      text: `[Yardımcı · ${KIND_LABELS[answer.report.kind] ?? "Sorun"}] ${summary}\n\n--- Sohbet ---\n${transcript}\nNino: ${reply}`.slice(0, 4000), images,
    }, now);
    if (saved.status === 200) reportId = saved.body.id;
  }
  if (key && !summary) {
    await db.prepare("INSERT INTO assistant_answers (key, reply, created) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET reply = excluded.reply, created = excluded.created, hits = 0")
      .bind(key, reply, now).run();
  }
  return { status: 200, body: { ok: true, reply, report: reportId } };
}

const KIND_LABELS = { bug: "Hata", unsolved: "Çözülemedi", request: "İstek" };

async function addCost(db, day, micro) {
  await db.prepare("INSERT INTO assistant_cost (day, micro_usd) VALUES (?, ?) ON CONFLICT(day) DO UPDATE SET micro_usd = micro_usd + excluded.micro_usd")
    .bind(day, Math.max(0, Math.round(micro))).run();
}
