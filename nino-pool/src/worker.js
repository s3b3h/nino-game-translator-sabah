// SPDX-License-Identifier: AGPL-3.0-only
// Nino ortak altyazı havuzu: Cloudflare Worker girişi.
//   POST /v1/batches            satır parçası (uygulamalar)
//   GET  /v1/health             durum
//   GET  /v1/games              oyunlar           (Authorization: Bearer EXPORT_TOKEN)
//   GET  /v1/export?game=…      oyunun satırları  (Authorization: Bearer EXPORT_TOKEN)
//   GET  /v1/sessions           oyunu bilinmeyen oturumlar (Authorization: Bearer EXPORT_TOKEN)
// IP adresi hiçbir yere yazılmaz.

import { receiveBatch, listGames, exportLines, listUnknownSessions, prune } from "./pool.js";
import { LIMITS } from "./validate.js";

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

async function readBody(request) {
  const declared = Number.parseInt(request.headers.get("content-length") ?? "", 10);
  if (Number.isFinite(declared) && declared > LIMITS.maxBodyBytes) return { tooLarge: true };
  const buffer = await request.arrayBuffer();
  if (buffer.byteLength > LIMITS.maxBodyBytes) return { tooLarge: true };
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
