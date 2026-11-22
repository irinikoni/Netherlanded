// Copyright (c) 2026 Eirini Konidari. All rights reserved.
// Netherlanded Edge Stats Adapter (Deno / Supabase Edge Function)
// Serves GET /stats?institution=<id> via nl.release_json_for_institution using caller JWT.
// Privacy invariants: never logs client IP addresses or JWTs.

const UPSTREAM_TIMEOUT_MS = 10000;
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const PROXY_SECRET = Deno.env.get("NL_PROXY_SECRET") ?? "";

function checkProxySecret(req: Request): boolean {
  if (!PROXY_SECRET) return true;
  const supplied = req.headers.get("x-nl-proxy-secret") ?? "";
  const a = new TextEncoder().encode(supplied);
  const b = new TextEncoder().encode(PROXY_SECRET);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a[i] ^ b[i];
  return diff === 0;
}

function isOriginAllowed(origin: string | null): boolean {
  return Boolean(origin && ALLOWED_ORIGINS.length > 0 && ALLOWED_ORIGINS.includes(origin));
}

function securityHeaders(origin: string | null): Headers {
  const h = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "frame-ancestors 'none'",
    "Vary": "Origin, Authorization",
  });
  if (isOriginAllowed(origin)) {
    h.set("Access-Control-Allow-Origin", origin!);
    h.set("Access-Control-Allow-Methods", "GET, OPTIONS");
    h.set("Access-Control-Allow-Headers", "Authorization");
  }
  return h;
}

function decodeJwtInstitution(token: string): string | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const rawB64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = rawB64 + "=".repeat((4 - (rawB64.length % 4)) % 4);
    const bytes = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
    const json = JSON.parse(new TextDecoder().decode(bytes));
    return typeof json?.app_metadata?.institution_id === "string"
      ? json.app_metadata.institution_id
      : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  if (origin && !isOriginAllowed(origin)) {
    return new Response(JSON.stringify({ error: "origin_not_allowed" }), {
      status: 403,
      headers: securityHeaders(null),
    });
  }

  const headers = securityHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers });
  }
  if (!checkProxySecret(req)) {
    return new Response(JSON.stringify({ error: "direct_access_forbidden" }), { status: 403, headers });
  }
  if (req.method !== "GET") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405, headers });
  }

  const auth = req.headers.get("authorization") ?? "";
  if (!auth.toLowerCase().startsWith("bearer ")) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401, headers });
  }
  const jwt = auth.slice(7).trim();
  if (!jwt) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401, headers });
  }

  const url = new URL(req.url);
  const inst = url.searchParams.get("institution") || decodeJwtInstitution(jwt);
  if (!inst || !/^[a-z0-9_-]{2,32}$/.test(inst)) {
    return new Response(JSON.stringify({ error: "invalid_institution" }), { status: 400, headers });
  }

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return new Response(JSON.stringify({ error: "server_not_configured" }), { status: 500, headers });
  }

  let resp: Response;
  try {
    resp = await fetch(`${SUPABASE_URL}/rest/v1/rpc/release_json_for_institution`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Profile": "nl",
        "Accept-Profile": "nl",
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": `Bearer ${jwt}`,
      },
      body: JSON.stringify({ p_institution: inst, p_snapshot: null }),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch {
    return new Response(JSON.stringify({ error: "upstream_unavailable" }), { status: 502, headers });
  }

  if (resp.status === 401) {
    await resp.body?.cancel().catch(() => {});
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401, headers });
  }
  if (resp.status === 403) {
    await resp.body?.cancel().catch(() => {});
    return new Response(JSON.stringify({ error: "forbidden" }), { status: 403, headers });
  }
  if (resp.status === 400) {
    await resp.body?.cancel().catch(() => {});
    return new Response(JSON.stringify({ error: "invalid_institution" }), { status: 400, headers });
  }
  if (!resp.ok) {
    await resp.body?.cancel().catch(() => {});
    return new Response(JSON.stringify({ error: "upstream_error" }), { status: 502, headers });
  }

  const body = await resp.text();
  return new Response(body, { status: 200, headers });
});
