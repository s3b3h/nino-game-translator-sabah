// SPDX-License-Identifier: AGPL-3.0-only
// Nino çeviri havuzu. Uygulama, hazır pakette olmayan bir satırı buraya sorar:
//   - çevirisi varsa (başka bir oyuncu daha önce görmüşse) hemen döner;
//   - yoksa hızlı model (Claude Haiku) o an çevirir, kaydeder ve döner; sonraki herkes aynısını anında alır.
// Birkaç saatte bir güçlü model (Claude Sonnet) son çevirileri oyunun bağlamıyla yeniden okur, daha iyi olanları
// değiştirir. Uygulamalar oyun başlarken o oyunun bütün çevirilerini tek seferde, sonra yalnız değişenleri çeker.
// Küfür ve argo sansürsüz: oyun diyaloğu olduğu gibi çevrilir.

import Anthropic from "@anthropic-ai/sdk";
import { lineKey, saltedDigest } from "./key.js";

export const TRANSLATE_LIMITS = Object.freeze({
  maxBodyBytes: 64 * 1024,
  maxLines: 12,
  maxText: 300,
  maxContext: 4,
  /** Günlük harcama sınırı (dolar); env.TRANSLATE_DAILY_USD ile değişir. */
  dailyUsd: 6,
  /** Gözden geçirme, sınırın bu kadarı harcanmışsa durur (geri kalanı anında çeviriye kalır). */
  reviewShare: 0.4,
  /** Kurulum başına saatte en çok anında çevrilen satır (aynı sunucu örneği içinde, kaba koruma). */
  perInstallHour: 1500,
  /** Toplu indirmede sayfa başına en çok satır. */
  pageSize: 4000,
  /** Gözden geçirmede bir parçadaki satır ve bir turdaki parça. */
  reviewChunk: 20,
  reviewChunksPerRun: 30,
  /** Yeni çeviri gözden geçirilmeden önce bu kadar bekler (aynı sahnenin satırları birikir). */
  reviewDelay: 10 * 60,
});

// Nino: ilk çeviri de mükemmel olsun diye anında çeviri de güçlü modelle (her satır bir kez çevrilir, herkes havuzdan alır).
export const LIVE_MODEL = "claude-sonnet-5-5";
// Gözden geçirme en güçlü modelle (Codex ile birlikte kararlaştırılan Plan 1); sahne sahne, bağlamla.
export const REVIEW_MODEL = "claude-opus-5-5";
/** Plan 3: Plan 1 zamanında cevap vermez, reddeder ya da hata verirse yalnız o satır için hızlı model. */
export const FALLBACK_MODEL = "claude-haiku-5-5";
/** Plan 1 için en çok bekleme (ms); sonra Plan 3 denenir. */
export const LIVE_TIMEOUT_MS = 4000;
export const FALLBACK_TIMEOUT_MS = 2500;

/** Dolar / milyon jeton (resmî fiyat, 100K jetona kadar). */
const PRICES = {
  "claude-haiku-5-5": { input: 0.10, output: 0.50 },
  "claude-sonnet-5-5": { input: 2.00, output: 10.00, cacheRead: 0.10, cacheWrite1h: 4.00 },
  "claude-opus-5-5": { input: 4.00, output: 20.00, cacheRead: 0.20, cacheWrite1h: 8.00 },
};
const FALLBACK_MICRO_USD = 20000;

export const LANGUAGES = Object.freeze({
  tr: "Turkish", ar: "Arabic", hi: "Hindi", id: "Indonesian", th: "Thai", vi: "Vietnamese",
  ur: "Urdu", bn: "Bengali", ms: "Malay", tl: "Filipino (Tagalog)", nl: "Dutch",
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const GAME = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const LETTER = /\p{L}/u;
const CONTROL = /[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028\u2029\ufeff]/gu;

/** Model fiyatıyla mikro dolar. */
export function translateCost(model, usage) {
  const price = PRICES[model];
  if (!price || !usage) return FALLBACK_MICRO_USD;
  return Math.ceil((usage.input_tokens ?? 0) * price.input + (usage.output_tokens ?? 0) * price.output
    + (usage.cache_read_input_tokens ?? 0) * (price.cacheRead ?? price.input * 0.1)
    + (usage.cache_creation_input_tokens ?? 0) * (price.cacheWrite1h ?? price.input * 2));
}

const LANGUAGE_NOTES = {
  tr: [
    "Use informal \"sen\" between characters unless the speaker is clearly formal (police to suspect, servant to boss). Natural spoken Istanbul Turkish; Turkish street slang where the original is slangy (\"bro/homie\" → \"kanka/birader\", \"dude\" → \"lan/abi\").",
    "Turkish swearing that matches the English intensity, used the way Turkish speakers really swear:",
    "  \"Fuck!\" / \"Oh fuck!\" → \"Siktir!\" / \"Hassiktir!\"; \"What the fuck?\" → \"Ne halt?\" / \"Bu ne amına koyayım?\"; \"Who the fuck are you?\" → \"Sen de kimsin lan?\";",
    "  \"Shut the fuck up\" → \"Kapa çeneni lan\" / \"Sus amına koyayım\"; \"fucking\" as intensifier → \"lanet olası\", \"siktiğimin\", \"amına koyduğumun\" or a strong \"lan\", never dropped;",
    "  \"motherfucker\" → \"orospu çocuğu\"; \"son of a bitch\" → \"şerefsiz\" / \"orospu çocuğu\"; \"shit\" → \"bok\" (\"No more stupid shit\" → \"Artık saçma sapan bok yemek yok\"), \"shitshow\" → \"bok gibi rezalet\"; \"ass\" → \"göt\"; \"fuck up\" → \"sıçıp batırmak\".",
    "Never add swearing or insults that are not in the English line, and never change the meaning to make it ruder: translate idioms by meaning (\"Says who?\" → \"Kim demiş?\", \"Says fuckin' who?\" → \"Kim demiş lan?\", \"pick you up\" said of cops → \"seni içeri alırlar\").",
  ].join("\n"),
  ar: "Use natural spoken Modern Standard Arabic suitable for game subtitles.",
  nl: "Use informal \"je/jij\" unless clearly formal.",
};

/** Çeviri talimatı. Sansürsüz: kurgu diyaloğu, yaş sınırlı oyun. */
export function instructions(lang, { review = false } = {}) {
  const name = LANGUAGES[lang];
  return [
    `You are a professional video game localizer translating English subtitles of an age-rated (18+) video game into ${name}. Players read your lines live on screen while playing, so they must be short, natural and instantly readable, like the subtitles of an officially localized AAA game.`,
    "",
    "Rules:",
    "- Translate meaning and tone, not word by word. Keep it as short as the original.",
    "- Profanity, insults, slurs, slang, sexual and violent language MUST be translated at exactly the same intensity. Never soften, censor, euphemize, bleep, add asterisks, omit or add moral comments. Fictional characters swear; a sanitized translation is a wrong translation.",
    "- Keep proper names as they are: people, gangs, places, brands, vehicles, weapons, missions, radio stations. Keep the original spelling.",
    "- Keep numbers, money and units as in the original.",
    "- If a line is a UI prompt or objective (\"Go to\", \"Press\", \"Lose the cops\"), translate it as the game would show it.",
    "- The English comes from screen reading (OCR): fix obvious misreads (\"Youlre\" = \"You're\", \"Donlt\" = \"Don't\", \"Ihäd\" = \"I had\") and drop stray HUD fragments or single stray letters around the dialogue. A speaker label like \"Amy:\" stays as \"Amy:\". If the whole line is unreadable garbage, return it unchanged.",
    "- Output only translations. No quotes, notes, explanations or alternatives.",
    LANGUAGE_NOTES[lang] ? `- ${LANGUAGE_NOTES[lang]}` : "",
    review
      ? "- You are reviewing earlier fast translations. The lines are in the order they were first seen in the game, so neighbours give context (who speaks, who is addressed, running jokes, names). Fix mistranslations, wrong address (sen/siz), wrong gender, lost slang or softened swearing, unnatural wording. Check each line separately for: (1) meaning, (2) swearing intensity: is it softer or harsher than the English, (3) added swearing or insults not in the English, (4) names kept as in the original. If a translation is already good, return it unchanged."
      : "- Context lines (if given) are what was said just before; use them to pick the right meaning and address, but translate only the numbered lines.",
  ].filter(Boolean).join("\n");
}

const LIVE_SCHEMA = {
  type: "object",
  properties: { translations: { type: "array", items: { type: "string" } } },
  required: ["translations"],
  additionalProperties: false,
};

/** Tek modelle anında çeviri. Dönüş { texts: string[]|null, cost }. */
async function askLiveModel(env, model, lang, lines, context, timeoutMs) {
  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, timeout: timeoutMs, maxRetries: 0 });
  const body = [
    context.length ? `Context (do not translate):\n${context.map((c) => `- ${c}`).join("\n")}\n` : "",
    `Translate these ${lines.length} lines into ${LANGUAGES[lang]}. Return exactly ${lines.length} translations in the same order.`,
    ...lines.map((line, i) => `${i + 1}. ${line}`),
  ].filter(Boolean).join("\n");
  const sonnet = model === LIVE_MODEL;
  const response = await client.messages.create({
    model,
    max_tokens: 1500,
    // Düşünme kapalı (hız): Sonnet 5.5'te "between_tools", Haiku 5.5'te "disabled".
    thinking: { type: sonnet ? "between_tools" : "disabled" },
    // Talimat her dilde aynı kalır: bir saat önbellekte durur, her satırda yeniden ücretlendirilmez.
    system: [{ type: "text", text: instructions(lang), cache_control: { type: "ephemeral", ttl: "1h" } }],
    messages: [{ role: "user", content: body }],
    output_config: { effort: sonnet ? "high" : "low", format: { type: "json_schema", schema: LIVE_SCHEMA } },
  });
  const cost = translateCost(model, response.usage);
  if (response.stop_reason !== "end_turn") return { texts: null, cost };
  const text = response.content.filter((b) => b.type === "text").map((b) => b.text).join("");
  const parsed = JSON.parse(text);
  const texts = Array.isArray(parsed.translations) && parsed.translations.length === lines.length ? parsed.translations : null;
  return { texts, cost };
}

/**
 * Anında çeviri, plan sırasıyla: Plan 1 Sonnet 5.5 (en çok 4 sn); zamanında cevap vermez, reddeder ya da hata
 * verirse Plan 3 Haiku 5.5 (en çok 2,5 sn). Her satır yeniden Plan 1'den başlar. Dönüş { texts, cost, model }.
 */
export async function askLive(env, lang, lines, context) {
  let cost = 0;
  for (const [model, timeout] of [[LIVE_MODEL, LIVE_TIMEOUT_MS], [FALLBACK_MODEL, FALLBACK_TIMEOUT_MS]]) {
    try {
      const answer = await askLiveModel(env, model, lang, lines, context, timeout);
      cost += answer.cost;
      if (answer.texts && answer.texts.every((t, i) => usable(lines[i], t))) return { texts: answer.texts, cost, model };
    } catch (error) {
      console.error("çeviri hatası", model, String(error?.message ?? error).slice(0, 200));
    }
  }
  return { texts: null, cost };
}

const REVIEW_SCHEMA = {
  type: "object",
  properties: {
    lines: {
      type: "array",
      items: {
        type: "object",
        properties: { n: { type: "integer" }, text: { type: "string" } },
        required: ["n", "text"],
        additionalProperties: false,
      },
    },
  },
  required: ["lines"],
  additionalProperties: false,
};

/** Gözden geçirme: [{source, text}] sırayla; dönüş { texts: string[]|null, cost }. */
export async function askReview(env, lang, game, items) {
  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, timeout: 90_000, maxRetries: 1 });
  const body = [
    `Game: ${game || "unknown"}. Review these ${items.length} subtitle translations into ${LANGUAGES[lang]}.`,
    `Return all ${items.length} lines with their number n and the final translation.`,
    "",
    ...items.map((item, i) => `${i + 1}. EN: ${item.source}\n   ${lang.toUpperCase()}: ${item.text}`),
  ].join("\n");
  const response = await client.messages.create({
    model: REVIEW_MODEL,
    max_tokens: 16000,
    system: instructions(lang, { review: true }),
    messages: [{ role: "user", content: body }],
    thinking: { type: "adaptive" },
    output_config: { effort: "high", format: { type: "json_schema", schema: REVIEW_SCHEMA } },
  });
  const cost = translateCost(REVIEW_MODEL, response.usage);
  if (response.stop_reason !== "end_turn") return { texts: null, cost };
  const text = response.content.filter((b) => b.type === "text").map((b) => b.text).join("");
  const parsed = JSON.parse(text);
  const out = items.map((item) => item.text);
  for (const line of parsed.lines ?? []) {
    const i = Number(line.n) - 1;
    if (i >= 0 && i < out.length && typeof line.text === "string") out[i] = line.text;
  }
  return { texts: out, cost };
}

function day(now) {
  return new Date(now * 1000).toISOString().slice(0, 10);
}

function capMicro(env) {
  const usd = Number(env.TRANSLATE_DAILY_USD ?? TRANSLATE_LIMITS.dailyUsd);
  return Math.round((Number.isFinite(usd) && usd >= 0 ? usd : TRANSLATE_LIMITS.dailyUsd) * 1_000_000);
}

async function spentToday(db, now) {
  return (await db.prepare("SELECT micro_usd FROM translate_cost WHERE day = ?").bind(day(now)).first("micro_usd")) ?? 0;
}

export async function addCost(db, now, micro) {
  await db.prepare("INSERT INTO translate_cost (day, micro_usd) VALUES (?, ?) ON CONFLICT(day) DO UPDATE SET micro_usd = micro_usd + excluded.micro_usd")
    .bind(day(now), Math.max(0, Math.round(micro))).run();
}

/**
 * Claude yalnız bu oyunlarda para harcar (anında çeviri ve gözden geçirme); env.TRANSLATE_GAMES virgülle ayrılmış
 * parçalar ("grand-theft-auto-vi,gta-vi,mafia"): oyun kimliği bunlardan birini içeriyorsa açık. "*" hepsi.
 * Öbür oyunlar hazır paket ve cihazın ücretsiz çevirisiyle devam eder; havuzdaki çeviriler yine okunur.
 */
export function gameAllowed(env, game) {
  const list = String(env.TRANSLATE_GAMES ?? "*").split(",").map((g) => g.trim().toLowerCase()).filter(Boolean);
  if (list.includes("*")) return true;
  const id = String(game ?? "").toLowerCase();
  return id !== "" && list.some((part) => id.includes(part));
}

/**
 * Oyun kimliği gelmeyen (PS5 çoğu zaman bildirmez, hazır paketi olmayan oyunda paketten de tanınamaz) satırlardan oyunu
 * tanır: oyuna özgü isimler (karakter, şehir) satırda ya da bağlamında geçiyorsa. Tanınan oyun kuruluma birkaç saat
 * yazılır; o kurulumun sonraki satırları da o oyundan sayılır.
 */
const GAME_SIGNATURES = [
  ["grand-theft-auto-vi", /\b(grand theft auto vi|gta ?(vi|6)|leonida|vice city|port gellhorn|ambrosia|grassrivers|kalaga|lucia|jason duval|dre'?quan|real dimez|boobie ike)\b/i],
];
export const GAME_MEMORY_SECONDS = 4 * 3600;

export function detectGame(texts) {
  const joined = texts.filter(Boolean).join(" \n ");
  for (const [game, pattern] of GAME_SIGNATURES) if (pattern.test(joined)) return game;
  return "";
}

export function translateEnabled(env) {
  return env.TRANSLATE_ENABLED !== "0" && Boolean(env.ANTHROPIC_API_KEY);
}

function clean(text) {
  return typeof text === "string" ? text.replace(CONTROL, " ").replace(/\s+/gu, " ").trim() : "";
}

/** Modelin cevabı kullanılabilir mi: boş değil, makul uzunlukta, ret/özür değil. */
export function usable(source, translation) {
  const t = clean(translation);
  if (!t) return false;
  if ([...t].length > Math.max(40, [...source].length * 4)) return false;
  if (/\b(I can(?:not|'t)|I'm sorry|as an AI|I won't)\b/i.test(t) && !/\b(I can(?:not|'t)|sorry|won't)\b/i.test(source)) return false;
  return true;
}

// Sunucu örneği içi kaba sınır: kurulum → [saat, satır].
const installHits = new Map();

/**
 * POST /v1/translate
 * { v:1, install, app, platform, lang, game?, lines:[text…], context?:[text…] }
 * → { ok, translations:[{ text: string|null, tier }] } (sıra aynı; çevrilemeyen null, uygulama kendi çevirisini kullanır)
 */
export async function handleTranslate(db, env, body, now, live = askLive) {
  if (!body || typeof body !== "object" || body.v !== 1) return { status: 400, body: { ok: false, error: "bad_request" } };
  if (typeof body.install !== "string" || !UUID.test(body.install)) return { status: 400, body: { ok: false, error: "bad_install" } };
  const lang = typeof body.lang === "string" ? body.lang.toLowerCase().split(/[-_]/)[0] : "";
  if (!LANGUAGES[lang]) return { status: 400, body: { ok: false, error: "bad_lang" } };
  if (!Array.isArray(body.lines) || body.lines.length === 0) return { status: 400, body: { ok: false, error: "no_lines" } };
  if (body.lines.length > TRANSLATE_LIMITS.maxLines) return { status: 413, body: { ok: false, error: "too_many_lines" } };
  // "Mafia: The Old Country" uygulamada "mafia--the-old-country" olur; aynı oyun tek adla tutulsun.
  let game = typeof body.game === "string" && GAME.test(body.game) ? body.game.replace(/-{2,}/g, "-") : "";
  const context = (Array.isArray(body.context) ? body.context : []).slice(-TRANSLATE_LIMITS.maxContext)
    .map(clean).filter((c) => c && [...c].length <= TRANSLATE_LIMITS.maxText);
  // Oyun bilinmiyorsa: satırdan/bağlamdan tanınır ya da bu kurulumun son saatlerde tanınan oyunu kullanılır.
  let detected = "";
  if (!game) {
    const installKey = await saltedDigest(body.install.toLowerCase(), env.INSTALL_SALT ?? "");
    detected = detectGame([...body.lines.map(clean), ...context]);
    if (detected) {
      game = detected;
      await db.prepare(
        `INSERT INTO installs (install, platform, app, first_seen, last_seen, playing, game, lang) VALUES (?1, '', '', ?2, ?2, ?2, ?3, '')
         ON CONFLICT (install) DO UPDATE SET last_seen = ?2, playing = ?2, game = ?3`,
      ).bind(installKey, now, detected).run().catch(() => {});
    } else {
      const remembered = await db.prepare("SELECT game, playing FROM installs WHERE install = ?").bind(installKey).first().catch(() => null);
      if (remembered?.game && now - (remembered.playing ?? 0) < GAME_MEMORY_SECONDS && gameAllowed(env, remembered.game)) {
        game = remembered.game;
      }
    }
  }

  // Satırlar ve anahtarları.
  const items = [];
  for (const raw of body.lines) {
    const text = clean(raw);
    const ok = text && [...text].length <= TRANSLATE_LIMITS.maxText && LETTER.test(text);
    items.push({ text, key: ok ? await lineKey(text) : null, result: null, tier: 0 });
  }
  const keys = [...new Set(items.map((i) => i.key).filter(Boolean))];
  if (keys.length > 0) {
    const { results } = await db.prepare(`SELECT key, text, tier, game FROM translations WHERE lang = ? AND key IN (SELECT value FROM json_each(?))`)
      .bind(lang, JSON.stringify(keys)).all();
    const known = new Map(results.map((r) => [r.key, r]));
    // Nino: oyun hâlâ bilinmiyorsa havuzdaki satırdan tanınır (satır daha önce bir oyunda görülüp çevrilmişse; kısa ve
    // her oyunda geçebilecek satırlar sayılmaz). Kuruluma yazılır, sonraki satırlar da o oyundan sayılır.
    // Uygulama başka bir oyun sanıyorsa (ör. benzer satırlı paketten) ama satır havuz öncelikli bir oyunun (GTA 6) uzun bir
    // satırıysa o oyun döner: uygulama cevaptaki oyuna bakıp çeviriyi yalnız havuzdan almaya geçer.
    const firstGame = (id) => poolFirstGames(env).some((part) => String(id ?? "").toLowerCase().includes(part));
    if (!game || !firstGame(game)) {
      const telling = results.find((r) => r.game && r.text && gameAllowed(env, r.game) && [...String(r.text)].length >= 25
        && (!game || firstGame(r.game)));
      if (telling) {
        game = telling.game;
        const installKey = await saltedDigest(body.install.toLowerCase(), env.INSTALL_SALT ?? "");
        await db.prepare(
          `INSERT INTO installs (install, platform, app, first_seen, last_seen, playing, game, lang) VALUES (?1, '', '', ?2, ?2, ?2, ?3, '')
           ON CONFLICT (install) DO UPDATE SET last_seen = ?2, playing = ?2, game = ?3`,
        ).bind(installKey, now, game).run().catch(() => {});
      }
    }
    for (const item of items) {
      const hit = item.key && known.get(item.key);
      // Boş metin: daha önce çevrilemedi (ret ya da bozuk cevap); yeniden ücretlendirilmez, uygulama kendi çevirisini kullanır.
      if (hit) { item.result = hit.text || null; item.tier = hit.text ? hit.tier : 0; item.known = true; }
    }
  }

  // Bilinmeyenler: hızlı model (sınır ve kota içindeyse).
  const missing = [];
  const seen = new Set();
  for (const item of items) {
    if (item.key && item.result === null && !item.known && !seen.has(item.key)) { seen.add(item.key); missing.push(item); }
  }
  let limited = null;
  if (missing.length > 0) {
    if (!translateEnabled(env)) limited = "disabled";
    else if (!gameAllowed(env, game)) limited = "game";
    else if ((await spentToday(db, now)) >= capMicro(env)) limited = "daily_cap";
    else {
      const install = await saltedDigest(body.install.toLowerCase(), env.INSTALL_SALT ?? "");
      const hour = Math.floor(now / 3600);
      const prev = installHits.get(install);
      const used = prev && prev[0] === hour ? prev[1] : 0;
      if (used + missing.length > TRANSLATE_LIMITS.perInstallHour) limited = "install_rate";
      else {
        installHits.set(install, [hour, used + missing.length]);
        if (installHits.size > 5000) installHits.clear();
      }
    }
    if (!limited) {
      let answer = { texts: null, cost: 0 };
      try {
        answer = await live(env, lang, missing.map((m) => m.text), context);
      } catch (error) {
        console.error("çeviri hatası", error);
      }
      if (answer.cost) await addCost(db, now, answer.cost);
      const texts = answer.texts && answer.texts.length === missing.length ? answer.texts : null;
      if (texts) {
        const rows = [];
        missing.forEach((m, i) => {
          if (usable(m.text, texts[i])) {
            m.result = clean(texts[i]);
            m.tier = 1;
            rows.push({ k: m.key, s: m.text, t: m.result, r: 1 });
          } else {
            rows.push({ k: m.key, s: m.text, t: "", r: 0 });
          }
        });
        if (rows.length > 0) {
          await db.prepare(
            `INSERT OR IGNORE INTO translations (key, lang, game, source, text, tier, created, updated)
             SELECT json_extract(value, '$.k'), ?, ?, json_extract(value, '$.s'), json_extract(value, '$.t'), json_extract(value, '$.r'), ?, ?
             FROM json_each(?)`,
          ).bind(lang, game, now, now, JSON.stringify(rows)).run();
        }
        // Aynı satır aynı istekte birden çok kez geçtiyse.
        const byKey = new Map(missing.filter((m) => m.result !== null).map((m) => [m.key, m]));
        for (const item of items) {
          if (item.result === null && item.key && byKey.has(item.key)) { item.result = byKey.get(item.key).result; item.tier = 1; }
        }
      }
    }
  }

  return {
    status: 200,
    body: {
      ok: true,
      ...(limited ? { limited } : {}),
      ...(game ? { game } : {}),
      translations: items.map((i) => ({ text: i.result, tier: i.tier })),
    },
  };
}

/**
 * GET /v1/translations?lang=tr&game=gta-vi&since=0
 * Oyunun (game boşsa bütün) çevirileri, `since`ten sonra değişenler. Sayfalı: next varsa since=next.updated, after=next.key.
 * → { ok, now, items:[[key, text, updated, tier]], next }
 */
export async function listTranslations(db, params, now) {
  const lang = (params.get("lang") ?? "").toLowerCase().split(/[-_]/)[0];
  if (!LANGUAGES[lang]) return { status: 400, body: { ok: false, error: "bad_lang" } };
  const game = params.get("game") ?? "";
  if (game && !GAME.test(game)) return { status: 400, body: { ok: false, error: "bad_game" } };
  const since = Math.max(0, Number.parseInt(params.get("since") ?? "0", 10) || 0);
  const after = /^[0-9a-f]{16}$/.test(params.get("after") ?? "") ? params.get("after") : "";
  const limit = TRANSLATE_LIMITS.pageSize;
  // Aynı oyun platformlara göre farklı adla gelebiliyor (gta-v / grand-theft-auto-v); havuz küçükken dilin bütün
  // çevirileri verilir. TRANSLATIONS_BY_GAME=1 ile oyuna göre süzülür.
  const byGame = game && params.get("_byGame") === "1";
  const gameFilter = byGame ? "AND (t.game = ?4 OR EXISTS (SELECT 1 FROM lines l WHERE l.game = ?4 AND l.key = t.key))" : "";
  const { results } = await db.prepare(
    `SELECT t.key, t.text, t.updated, t.tier FROM translations t
     WHERE t.lang = ?1 AND t.text <> '' AND (t.updated > ?2 OR (?3 <> '' AND t.updated = ?2 AND t.key > ?3)) ${gameFilter}
     ORDER BY t.updated, t.key LIMIT ${limit}`,
  ).bind(...(byGame ? [lang, since, after, game] : [lang, since, after])).all();
  const items = results.map((r) => [r.key, r.text, r.updated, r.tier]);
  const last = results[results.length - 1];
  return {
    status: 200,
    body: { ok: true, now, items, next: results.length === limit ? { since: last.updated, after: last.key } : null },
  };
}

/**
 * Gözden geçirme turu (zamanlanmış): en eski gözden geçirilmemiş çeviriler, oyun ve dile göre, görüldükleri sırayla
 * güçlü modele gider. Değişen çeviri `updated`i yenilenir; uygulamalar bir sonraki çekişte alır.
 */
export async function reviewTranslations(db, env, now, review = askReview, delay = TRANSLATE_LIMITS.reviewDelay) {
  if (!translateEnabled(env)) return { reviewed: 0, changed: 0, cost: 0 };
  const cap = capMicro(env) * TRANSLATE_LIMITS.reviewShare;
  let reviewed = 0;
  let changed = 0;
  let cost = 0;
  let failed = 0;
  for (let run = 0; run < TRANSLATE_LIMITS.reviewChunksPerRun; run++) {
    if ((await spentToday(db, now)) >= cap) break;
    const group = await db.prepare(
      `SELECT lang, game FROM translations WHERE tier = 1 AND text <> '' AND created < ? GROUP BY lang, game ORDER BY MIN(created) LIMIT 1`,
    ).bind(now - delay).first();
    if (!group) break;
    if (!gameAllowed(env, group.game)) {
      // İzinli olmayan oyunun satırları gözden geçirilmez (para harcanmaz); bir daha seçilmesin diye işaretlenir.
      await db.prepare("UPDATE translations SET tier = 2 WHERE tier = 1 AND lang = ? AND game = ?").bind(group.lang, group.game).run();
      continue;
    }
    const { results } = await db.prepare(
      `SELECT t.key, t.source, t.text,
              COALESCE((SELECT MIN(l.first_seen) FROM lines l WHERE l.key = t.key AND (l.game = t.game OR t.game = '')), t.created) AS seen
       FROM translations t
       WHERE t.tier = 1 AND t.text <> '' AND t.lang = ? AND t.game = ? AND t.created < ?
       ORDER BY seen, t.key LIMIT ${TRANSLATE_LIMITS.reviewChunk}`,
    ).bind(group.lang, group.game, now - delay).all();
    if (results.length === 0) break;
    let answer = { texts: null, cost: 0 };
    try {
      answer = await review(env, group.lang, group.game, results.map((r) => ({ source: r.source, text: r.text })));
    } catch (error) {
      console.error("gözden geçirme hatası", error);
    }
    if (answer.cost) { await addCost(db, now, answer.cost); cost += answer.cost; }
    if (!answer.texts) {
      // Ret ya da bozuk cevap: bu satırlar olduğu gibi kalır, bir daha gönderilmez (her turda yeniden ücretlendirilmesin).
      await db.prepare(`UPDATE translations SET tier = 2 WHERE lang = ?1 AND key IN (SELECT value FROM json_each(?2))`)
        .bind(group.lang, JSON.stringify(results.map((r) => r.key))).run();
      failed++;
      continue;
    }
    const rows = results.map((r, i) => {
      const better = usable(r.source, answer.texts[i]) ? clean(answer.texts[i]) : r.text;
      if (better !== r.text) changed++;
      return { k: r.key, t: better, c: better !== r.text ? 1 : 0 };
    });
    await db.prepare(
      `UPDATE translations SET
         tier = 2,
         text = (SELECT json_extract(value, '$.t') FROM json_each(?1) WHERE json_extract(value, '$.k') = translations.key),
         updated = CASE WHEN (SELECT json_extract(value, '$.c') FROM json_each(?1) WHERE json_extract(value, '$.k') = translations.key) = 1
                        THEN ?2 ELSE updated END
       WHERE lang = ?3 AND key IN (SELECT json_extract(value, '$.k') FROM json_each(?1))`,
    ).bind(JSON.stringify(rows), now, group.lang).run();
    reviewed += results.length;
  }
  return { reviewed, changed, cost, ...(failed ? { failed } : {}) };
}

/** GET /v1/config: uygulamaların uzaktan ayarı (yeni sürüm gerekmeden açılıp kapanır). */
/** Havuz öncelikli oyunlar: env.POOL_FIRST_GAMES (virgüllü), yoksa GTA 6'nın adları. */
export const POOL_FIRST_DEFAULT = Object.freeze(["grand-theft-auto-vi", "gta-vi", "gta-6", "gta6"]);

export function poolFirstGames(env) {
  if (env.POOL_FIRST_GAMES === undefined) return [...POOL_FIRST_DEFAULT];
  return String(env.POOL_FIRST_GAMES).split(",").map((g) => g.trim().toLowerCase().replace(/-{2,}/g, "-")).filter(Boolean);
}

export function remoteConfig(env) {
  const num = (v, d) => (Number.isFinite(Number(v)) && v !== undefined && v !== "" ? Number(v) : d);
  return {
    ok: true,
    translate: {
      enabled: translateEnabled(env),
      deadlineMs: num(env.TRANSLATE_DEADLINE_MS, 900),
      syncSeconds: num(env.TRANSLATE_SYNC_SECONDS, 180),
      contextLines: TRANSLATE_LIMITS.maxContext,
      maxLines: TRANSLATE_LIMITS.maxLines,
    },
    // Nino: bu oyunlarda uygulama satırı önce sunucuya sorar, kullanıcının kendi motorunu (Gemini, DeepL, yapay zekâ)
    // hiç çağırmaz; sunucu `deadlineMs` içinde cevap vermezse yalnız cihazın ücretsiz çevirisine düşer. Kimlikler
    // NinoPool.gameId biçiminde; eşleşme TRANSLATE_GAMES gibi "kimlik bu parçayı içeriyor" kuralıyla.
    poolFirst: {
      games: poolFirstGames(env),
      deadlineMs: num(env.POOL_FIRST_DEADLINE_MS, 1500),
    },
    minVersion: {
      mac: env.MIN_VERSION_MAC ?? "",
      windows: env.MIN_VERSION_WINDOWS ?? "",
      android: env.MIN_VERSION_ANDROID ?? "",
      ios: env.MIN_VERSION_IOS ?? "",
    },
  };
}
