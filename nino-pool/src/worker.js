// SPDX-License-Identifier: AGPL-3.0-only
// Nino ortak altyazı havuzu: Cloudflare Worker girişi.
//   POST /v1/batches            satır parçası (uygulamalar)
//   GET  /v1/health             durum
//   GET  /v1/games              oyunlar           (Authorization: Bearer EXPORT_TOKEN)
//   GET  /v1/export?game=…      oyunun satırları  (Authorization: Bearer EXPORT_TOKEN)
//   GET  /v1/sessions           oyunu bilinmeyen oturumlar (Authorization: Bearer EXPORT_TOKEN)
//   POST /v1/reports            Nino: "Sorun Bildir" (uygulamalar; açıklama, günlük, en çok 3 fotoğraf)
//   GET  /v1/reports[/id[/images/i]], POST /v1/reports/id/status   bildirimler (Authorization: Bearer EXPORT_TOKEN)
//   GET  /reports               bildirimleri okuma sayfası (veri içermez; anahtarla /v1/reports'tan çeker)
// IP adresi hiçbir yere yazılmaz.

import { receiveBatch, listGames, exportLines, listUnknownSessions, prune } from "./pool.js";
import { LIMITS } from "./validate.js";
import { REPORT_LIMITS, receiveReport, listReports, getReport, getReportImage, setReportStatus } from "./reports.js";
import { REPORTS_PAGE } from "./reports-page.js";

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

export async function handle(request, env, now = Math.floor(Date.now() / 1000)) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "");

  if (path === "/v1/health" && request.method === "GET") return json(200, { ok: true });

  if (path === "/v1/batches") {
    if (request.method !== "POST") return json(405, { ok: false, error: "method" });
    const body = await readBody(request);
    if (body.tooLarge) return json(413, { ok: false, error: "too_large" });
    if (body.bad) return json(400, { ok: false, error: "bad_json" });
    const result = await receiveBatch(env.DB, env, body.value, now);
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
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (error) {
      // 5xx: istemci parçayı saklar ve artan aralıklarla yeniden dener.
      console.error("havuz hatası", error);
      return json(503, { ok: false, error: "server" }, { "retry-after": "60" });
    }
  },
  async scheduled(_event, env) {
    await prune(env.DB, Math.floor(Date.now() / 1000));
  },
};
