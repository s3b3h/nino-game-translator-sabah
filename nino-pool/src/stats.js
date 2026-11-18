// SPDX-License-Identifier: AGPL-3.0-only
// Nino paneli: kaç kişi şu an oynuyor, kaç kurulum var, kaç indirme, kaç satır ve kelime çevrildi, ne harcandı.
// Kurulum kimliği yalnız tuzlanmış özetiyle tutulur; IP ve kişisel veri yok.

import { saltedDigest } from "./key.js";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PLATFORMS = new Set(["mac", "windows", "linux", "android", "ios", "tv"]);
const GAME = /^[a-z0-9][a-z0-9._-]{0,63}$/;
/** "Şu an oynuyor": son "buradayım" bu kadar saniye içindeyse (uygulama dakikada bir bildirir). */
export const PLAYING_WINDOW = 150;

/** Kurulumu kaydeder ya da son görülme zamanını yeniler. `playing`: çeviri sürüyor. */
export async function touchInstall(db, env, raw, now, { platform = "", app = "", playing = false, game = "", lang = "" } = {}) {
  if (typeof raw !== "string" || !UUID.test(raw)) return;
  const install = await saltedDigest(raw.toLowerCase(), env.INSTALL_SALT ?? "");
  const plat = PLATFORMS.has(platform) ? platform : "";
  const version = typeof app === "string" ? app.slice(0, 40) : "";
  const g = typeof game === "string" && GAME.test(game) ? game.replace(/-{2,}/g, "-") : "";
  const l = typeof lang === "string" ? lang.toLowerCase().slice(0, 8) : "";
  await db.prepare(
    `INSERT INTO installs (install, platform, app, first_seen, last_seen, playing, game, lang) VALUES (?1, ?2, ?3, ?4, ?4, ?5, ?6, ?7)
     ON CONFLICT (install) DO UPDATE SET
       platform = CASE WHEN ?2 <> '' THEN ?2 ELSE platform END,
       app = CASE WHEN ?3 <> '' THEN ?3 ELSE app END,
       last_seen = max(last_seen, ?4),
       playing = CASE WHEN ?5 > 0 THEN ?5 ELSE playing END,
       game = CASE WHEN ?5 > 0 AND ?6 <> '' THEN ?6 ELSE game END,
       lang = CASE WHEN ?7 <> '' THEN ?7 ELSE lang END`,
  ).bind(install, plat, version, now, playing ? now : 0, g, l).run();
}

/** GET /v1/ping: uygulama çeviri sürerken dakikada bir "buradayım" der. */
export async function handlePing(db, env, params, now) {
  await touchInstall(db, env, params.get("install") ?? "", now, {
    platform: params.get("platform") ?? "", app: params.get("app") ?? "", playing: true,
    game: params.get("game") ?? "", lang: params.get("lang") ?? "",
  });
  return { status: 204 };
}

// GitHub indirme sayıları (sürüm dosyaları); sunucu örneği içinde 10 dakika tutulur.
let downloadsCache = { at: 0, value: null };

async function githubDownloads(now, fetcher = fetch) {
  if (downloadsCache.value && now - downloadsCache.at < 600) return downloadsCache.value;
  try {
    const response = await fetcher("https://api.github.com/repos/yunusdemirbag/nino-game-translator/releases?per_page=100", {
      headers: { "user-agent": "nino-pool", accept: "application/vnd.github+json" },
    });
    if (!response.ok) return downloadsCache.value;
    const releases = await response.json();
    const byFile = { mac: 0, windows: 0, android: 0, tv: 0 };
    let latest = null;
    for (const release of releases) {
      if (!latest && !release.draft && !release.prerelease) latest = release.tag_name;
      for (const asset of release.assets ?? []) {
        const name = String(asset.name ?? "");
        const n = Number(asset.download_count) || 0;
        if (/mac\.zip$/i.test(name)) byFile.mac += n;
        else if (/setup\.exe$/i.test(name)) byFile.windows += n;
        else if (/telefon\.apk$|mobile.*\.apk$/i.test(name)) byFile.android += n;
        else if (/tv\.apk$|androidtv.*\.apk$/i.test(name)) byFile.tv += n;
      }
    }
    const value = { ...byFile, total: byFile.mac + byFile.windows + byFile.android + byFile.tv, latest };
    downloadsCache = { at: now, value };
    return value;
  } catch {
    return downloadsCache.value;
  }
}

function dayStart(now) {
  return now - (now % 86400);
}

/** GET /v1/stats (yönetici): panelin bütün sayıları. */
export async function collectStats(db, env, now, fetcher) {
  const today = dayStart(now);
  const day = (t) => new Date(t * 1000).toISOString().slice(0, 10);
  const first = (sql, ...args) => db.prepare(sql).bind(...args).first();
  const all = async (sql, ...args) => (await db.prepare(sql).bind(...args).all()).results;

  const [playing, byPlatformNow, games, active24, newToday, total, byPlatform, versions] = await Promise.all([
    first("SELECT COUNT(*) AS n FROM installs WHERE playing > ?", now - PLAYING_WINDOW),
    all("SELECT platform, COUNT(*) AS n FROM installs WHERE playing > ? GROUP BY platform ORDER BY n DESC", now - PLAYING_WINDOW),
    all("SELECT game, COUNT(*) AS n FROM installs WHERE playing > ? GROUP BY game ORDER BY n DESC LIMIT 8", now - PLAYING_WINDOW),
    first("SELECT COUNT(*) AS n FROM installs WHERE last_seen > ?", now - 86400),
    first("SELECT COUNT(*) AS n FROM installs WHERE first_seen >= ?", today),
    first("SELECT COUNT(*) AS n FROM installs"),
    all("SELECT platform, COUNT(*) AS n FROM installs GROUP BY platform ORDER BY n DESC"),
    all("SELECT app, COUNT(*) AS n FROM installs WHERE last_seen > ? AND app <> '' GROUP BY app ORDER BY n DESC LIMIT 6", now - 7 * 86400),
  ]);

  const [tr, trToday, byLang, lines, cost, assistantCost, questions, reports, hourly] = await Promise.all([
    first(`SELECT COUNT(*) AS n, SUM(tier = 2) AS reviewed,
                  SUM(length(source) - length(replace(source, ' ', '')) + 1) AS words FROM translations WHERE text <> ''`),
    first(`SELECT COUNT(*) AS n, SUM(length(source) - length(replace(source, ' ', '')) + 1) AS words
           FROM translations WHERE created >= ? AND text <> ''`, today),
    all("SELECT lang, COUNT(*) AS n FROM translations GROUP BY lang ORDER BY n DESC"),
    first("SELECT COUNT(*) AS n, COALESCE(SUM(seen), 0) AS seen FROM lines"),
    all("SELECT day, micro_usd FROM translate_cost WHERE day >= ? ORDER BY day", day(now - 6 * 86400)),
    first("SELECT micro_usd FROM assistant_cost WHERE day = ?", day(now)),
    first("SELECT COALESCE(SUM(count), 0) AS n FROM assistant_usage WHERE day = ?", Math.floor(now / 86400)),
    first("SELECT COUNT(*) AS n, SUM(status = 'new') AS fresh FROM reports"),
    all(`SELECT (created / 3600) * 3600 AS hour, COUNT(*) AS n FROM translations WHERE created > ? GROUP BY hour ORDER BY hour`,
      now - 24 * 3600),
  ]);

  const translateCap = Number(env.TRANSLATE_DAILY_USD ?? 6);
  const spentToday = (cost.find((c) => c.day === day(now))?.micro_usd ?? 0) / 1e6;
  return {
    ok: true,
    now,
    players: {
      now: playing?.n ?? 0,
      byPlatform: byPlatformNow,
      games,
      active24h: active24?.n ?? 0,
      newToday: newToday?.n ?? 0,
      installs: total?.n ?? 0,
      installsByPlatform: byPlatform,
      versions,
    },
    downloads: env.STATS_GITHUB === "0" ? null : await githubDownloads(now, fetcher),
    translations: {
      lines: tr?.n ?? 0,
      words: tr?.words ?? 0,
      reviewed: tr?.reviewed ?? 0,
      today: trToday?.n ?? 0,
      wordsToday: trToday?.words ?? 0,
      byLang,
      hourly,
    },
    pool: { lines: lines?.n ?? 0, seen: lines?.seen ?? 0 },
    spend: {
      translateToday: spentToday,
      translateCap,
      assistantToday: (assistantCost?.micro_usd ?? 0) / 1e6,
      week: cost.map((c) => ({ day: c.day, usd: c.micro_usd / 1e6 })),
    },
    assistant: { questionsToday: questions?.n ?? 0 },
    reports: { total: reports?.n ?? 0, fresh: reports?.fresh ?? 0 },
  };
}
