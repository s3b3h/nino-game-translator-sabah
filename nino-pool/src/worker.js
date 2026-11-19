// SPDX-License-Identifier: AGPL-3.0-only
// Nino ortak altyazı havuzu: Cloudflare Worker girişi.
//   POST /v1/batches            satır parçası (uygulamalar)
//   GET  /v1/health             durum
//   GET  /v1/games              oyunlar           (Authorization: Bearer EXPORT_TOKEN)
//   GET  /v1/export?game=…      oyunun satırları  (Authorization: Bearer EXPORT_TOKEN)
//   GET  /v1/sessions           oyunu bilinmeyen oturumlar (Authorization: Bearer EXPORT_TOKEN)
//   POST /v1/reports            Nino: "Sorun Bildir" (uygulamalar; açıklama, günlük, en çok 3 fotoğraf)
//   GET  /v1/reports[/id[/images/i]], POST /v1/reports/id/status   bildirimler (Authorization: Bearer EXPORT_TOKEN)
//   POST /v1/assistant          Nino yardımcısı (kurulum sohbeti; model sunucu ayarıyla seçilir)
//   GET  /v1/assistant          yardımcı açık mı ({ok, enabled})
//   POST /v1/translate          çeviri havuzu: satırların çevirisi (yoksa o an çevrilir)
//   GET  /v1/translations       çeviri havuzu: oyunun çevirileri, ?since= sonrası değişenler
//   POST /v1/identify           oyunu ekrandan tanır (Remote Play karesi → oyun adı)
//   GET  /v1/config             uygulamaların uzaktan ayarı (çeviri havuzu açık mı, bekleme süresi, en düşük sürüm)
//   GET  /v1/ping               uygulama çeviri sürerken dakikada bir "buradayım" (panelde şu an oynayan)
//   GET  /v1/stats              panelin sayıları (Authorization: Bearer EXPORT_TOKEN)
//   GET  /panel                 Nino paneli (veri içermez; anahtarla /v1/stats'tan çeker)
//   GET  /reports               bildirimleri okuma sayfası (veri içermez; anahtarla /v1/reports'tan çeker)
// IP adresi hiçbir yere yazılmaz.

import { receiveBatch, listGames, exportLines, listUnknownSessions, prune } from "./pool.js";
import { LIMITS } from "./validate.js";
import { REPORT_LIMITS, receiveReport, listReports, getReport, getReportImage, setReportStatus } from "./reports.js";
import { REPORTS_PAGE } from "./reports-page.js";
import { ASSISTANT_LIMITS, handleAssistant, assistantEnabled } from "./assistant.js";
import { touchInstall, handlePing, handleTv, collectStats, samplePlayers, storedDownloadTotal, refreshDownloads } from "./stats.js";
import { ADMIN_PAGE } from "./admin-page.js";
import { IDENTIFY_LIMITS, handleIdentify } from "./identify.js";
import { TRANSLATE_LIMITS, LANGUAGES, handleTranslate, listTranslations, reviewTranslations, remoteConfig, addCost, askLiveModel, askReview } from "./translate.js";

function json(status, body, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });
}

function authorized(request, env) {
  const token = env.EXPORT_TOKEN;
  if (!token) return false;
  const header = request.headers.get("authorization") ?? "";
  const given = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (given.length !== token.length) return false;
  let diff = 0;
  for (let i = 0; i < token.length; i++) diff |= token.charCodeAt(i) ^ given.charCodeAt(i);
  return diff === 0;
}

async function readBody(request, max = LIMITS.maxBodyBytes) {
  const declared = Number.parseInt(request.headers.get("content-length") ?? "", 10);
  if (Number.isFinite(declared) && declared > max) return { tooLarge: true };
  const buffer = await request.arrayBuffer();
  if (buffer.byteLength > max) return { tooLarge: true };
  try {
    return { value: JSON.parse(new TextDecoder().decode(buffer)) };
  } catch {
    return { bad: true };
  }
}

export async function handle(request, env, now = Math.floor(Date.now() / 1000), ask, translateLive, identifyAsk) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "");

  if (path === "/v1/health" && request.method === "GET") return json(200, { ok: true });

  if (path === "/v1/batches") {
    if (request.method !== "POST") return json(405, { ok: false, error: "method" });
    const body = await readBody(request);
    if (body.tooLarge) return json(413, { ok: false, error: "too_large" });
    if (body.bad) return json(400, { ok: false, error: "bad_json" });
    const result = await receiveBatch(env.DB, env, body.value, now);
    if (result.status === 200) {
      await touchInstall(env.DB, env, body.value?.install, now, { platform: body.value?.platform, app: body.value?.app }).catch(() => {});
    }
    const headers = result.retryAfter ? { "retry-after": String(result.retryAfter) } : {};
    return json(result.status, result.body, headers);
  }

  if (path === "/v1/ping" && request.method === "GET") {
    await handlePing(env.DB, env, url.searchParams, now);
    return new Response(null, { status: 204, headers: { "cache-control": "no-store" } });
  }

  if (path === "/v1/tv" && request.method === "GET") {
    await handleTv(env.DB, env, url.searchParams, now);
    return new Response(null, { status: 204, headers: { "cache-control": "no-store", "access-control-allow-origin": "*" } });
  }

  if (path === "/v1/stats" && request.method === "GET") {
    if (!env.EXPORT_TOKEN) return json(503, { ok: false, error: "export_disabled" });
    if (!authorized(request, env)) return json(401, { ok: false, error: "unauthorized" });
    return json(200, await collectStats(env.DB, env, now));
  }

  if (path === "/panel" && request.method === "GET") {
    return new Response(ADMIN_PAGE, {
      headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-robots-tag": "noindex",
        "content-security-policy": "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'" },
    });
  }

  if (path === "/v1/config" && request.method === "GET") {
    // Nino: toplam indirme (ana ekrandaki sayaç); saklanan son değer, yoksa alan hiç gönderilmez.
    const downloads = await storedDownloadTotal(env.DB);
    return json(200, { ...remoteConfig(env), ...(downloads ? { downloads } : {}) }, { "cache-control": "public, max-age=300" });
  }

  if (path === "/v1/identify" && request.method === "POST") {
    const body = await readBody(request, IDENTIFY_LIMITS.maxBodyBytes);
    if (body.tooLarge) return json(413, { ok: false, error: "too_large" });
    if (body.bad) return json(400, { ok: false, error: "bad_json" });
    const result = await handleIdentify(env.DB, env, body.value, now, identifyAsk, addCost);
    return json(result.status, result.body);
  }

  if (path === "/v1/translate") {
    if (request.method !== "POST") return json(405, { ok: false, error: "method" });
    const body = await readBody(request, TRANSLATE_LIMITS.maxBodyBytes);
    if (body.tooLarge) return json(413, { ok: false, error: "too_large" });
    if (body.bad) return json(400, { ok: false, error: "bad_json" });
    const result = await handleTranslate(env.DB, env, body.value, now, translateLive);
    if (result.status === 200) {
      await touchInstall(env.DB, env, body.value?.install, now, {
        platform: body.value?.platform, app: body.value?.app, playing: true, game: body.value?.game, lang: body.value?.lang,
      }).catch(() => {});
    }
    return json(result.status, result.body);
  }

  // Yönetici: gözden geçirmeyi hemen çalıştırır (?delay=saniye, varsayılan zamanlanmışla aynı).
  if (path === "/v1/review" && request.method === "POST") {
    if (!env.EXPORT_TOKEN) return json(503, { ok: false, error: "export_disabled" });
    if (!authorized(request, env)) return json(401, { ok: false, error: "unauthorized" });
    const delay = Number.parseInt(url.searchParams.get("delay") ?? "", 10);
    return json(200, { ok: true, ...(await reviewTranslations(env.DB, env, now, undefined, Number.isFinite(delay) ? delay : undefined)) });
  }

  // Yönetici: model kıyası (veritabanına yazmaz, harcama sayacına eklemez). Gövde:
  // { kind:"live", model, effort, lang, lines, context } ya da { kind:"review", model, effort, lang, game, items }.
  if (path === "/v1/eval" && request.method === "POST") {
    if (!env.EXPORT_TOKEN) return json(503, { ok: false, error: "export_disabled" });
    if (!authorized(request, env)) return json(401, { ok: false, error: "unauthorized" });
    const body = await request.json().catch(() => null);
    if (!body || !LANGUAGES[body.lang]) return json(400, { ok: false, error: "bad_request" });
    const started = Date.now();
    try {
      const answer = body.kind === "review"
        ? await askReview(env, body.lang, body.game ?? "", body.items ?? [], { model: body.model, effort: body.effort })
        : await askLiveModel(env, body.model, body.lang, body.lines ?? [], body.context ?? [], 60_000, body.effort);
      return json(200, { ok: true, ms: Date.now() - started, ...answer });
    } catch (error) {
      return json(200, { ok: false, ms: Date.now() - started, error: String(error?.message ?? error).slice(0, 300) });
    }
  }

  if (path === "/v1/translations" && request.method === "GET") {
    const result = await listTranslations(env.DB, url.searchParams, now);
    return json(result.status, result.body, result.status === 200 ? { "cache-control": "public, max-age=60" } : {});
  }

  if (path === "/v1/assistant") {
    if (request.method === "GET") return json(200, { ok: true, enabled: assistantEnabled(env) });
    if (request.method !== "POST") return json(405, { ok: false, error: "method" });
    const body = await readBody(request, ASSISTANT_LIMITS.maxBodyBytes);
    if (body.tooLarge) return json(413, { ok: false, error: "too_large" });
    if (body.bad) return json(400, { ok: false, error: "bad_json" });
    const result = await handleAssistant(env.DB, env, body.value, now, ask);
    await touchInstall(env.DB, env, body.value?.install, now, { platform: body.value?.platform, app: body.value?.app }).catch(() => {});
    const headers = result.retryAfter ? { "retry-after": String(result.retryAfter) } : {};
    return json(result.status, result.body, headers);
  }

  if (path === "/reports" && request.method === "GET") {
    return new Response(REPORTS_PAGE, {
      headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-robots-tag": "noindex",
        "content-security-policy": "default-src 'self'; img-src 'self' blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'" },
    });
  }

  if (path === "/v1/reports" && request.method === "POST") {
    const body = await readBody(request, REPORT_LIMITS.maxBodyBytes);
    if (body.tooLarge) return json(413, { ok: false, error: "too_large" });
    if (body.bad) return json(400, { ok: false, error: "bad_json" });
    const result = await receiveReport(env.DB, env, body.value, now);
    const headers = result.retryAfter ? { "retry-after": String(result.retryAfter) } : {};
    return json(result.status, result.body, headers);
  }

  if (path === "/v1/reports" || path.startsWith("/v1/reports/")) {
    if (!env.EXPORT_TOKEN) return json(503, { ok: false, error: "export_disabled" });
    if (!authorized(request, env)) return json(401, { ok: false, error: "unauthorized" });
    const parts = path.split("/").slice(3); // [id, "images", i] | [id, "status"] | [id] | []
    if (parts.length === 0 && request.method === "GET") {
      return json(200, { ok: true, reports: await listReports(env.DB, { limit: url.searchParams.get("limit"), before: url.searchParams.get("before") }) });
    }
    const [id, kind, index] = parts;
    if (kind === undefined && request.method === "GET") {
      const report = await getReport(env.DB, id);
      return report ? json(200, { ok: true, report }) : json(404, { ok: false, error: "not_found" });
    }
    if (kind === "images" && request.method === "GET") {
      const image = await getReportImage(env.DB, id, Number.parseInt(index, 10));
      if (!image) return json(404, { ok: false, error: "not_found" });
      return new Response(image.data, { headers: { "content-type": image.mime, "cache-control": "private, max-age=3600" } });
    }
    if (kind === "status" && request.method === "POST") {
      const ok = await setReportStatus(env.DB, id, (await request.text()).trim());
      return json(ok ? 200 : 400, { ok });
    }
    return json(405, { ok: false, error: "method" });
  }

  if (path === "/v1/games" || path === "/v1/export" || path === "/v1/sessions") {
    if (request.method !== "GET") return json(405, { ok: false, error: "method" });
    if (!env.EXPORT_TOKEN) return json(503, { ok: false, error: "export_disabled" });
    if (!authorized(request, env)) return json(401, { ok: false, error: "unauthorized" });
    const q = url.searchParams;
    if (path === "/v1/games") return json(200, { ok: true, games: await listGames(env.DB) });
    if (path === "/v1/sessions") return json(200, { ok: true, sessions: await listUnknownSessions(env.DB, { limit: q.get("limit") }) });
    const result = await exportLines(env.DB, {
      game: q.get("game") ?? "",
      after: q.get("after") ?? "",
      limit: q.get("limit") ?? 1000,
      minInstalls: q.get("min_installs") ?? 1,
      session: q.get("session"),
    });
    return json(200, { ok: true, ...result });
  }

  return json(404, { ok: false, error: "not_found" });
}

export default {
  async fetch(request, env, ctx) {
    try {
      // Oyunun bütün çevirileri (ilk indirme) kenar önbellekte bir dakika tutulur: yüzlerce oyuncu aynı anda
      // başlasa da veritabanına bir kez gidilir.
      const url = new URL(request.url);
      if (request.method === "GET" && url.pathname === "/v1/translations" && (url.searchParams.get("since") ?? "0") === "0"
          && typeof caches !== "undefined") {
        const cache = caches.default;
        const hit = await cache.match(request);
        if (hit) return hit;
        const response = await handle(request, env);
        if (response.status === 200) ctx?.waitUntil?.(cache.put(request, response.clone()));
        return response;
      }
      return await handle(request, env);
    } catch (error) {
      // 5xx: istemci parçayı saklar ve artan aralıklarla yeniden dener.
      console.error("havuz hatası", error);
      return json(503, { ok: false, error: "server" }, { "retry-after": "60" });
    }
  },
  async scheduled(event, env) {
    const now = Math.floor(Date.now() / 1000);
    // Panel geçmişi: kimse oynamıyorken de o saat 0 olarak yazılsın (yarım saatte bir).
    await samplePlayers(env.DB, now, { force: true });
    // Uygulamalardaki "Toplam indirme" sayacı güncel kalsın (kimse paneli açmasa da).
    if (env.STATS_GITHUB !== "0") await refreshDownloads(env.DB, now).catch(() => null);
    // Gözden geçirme 30 dakikada bir (wrangler.toml), bakım günde bir.
    if (event?.cron === "17 3 * * *") await prune(env.DB, now);
    else console.log("gözden geçirme", JSON.stringify(await reviewTranslations(env.DB, env, now)));
  },
};
