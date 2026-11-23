// Copyright (c) 2026 Eirini Konidari. All rights reserved.
// Netherlanded Edge Ingest Adapter (Deno / Supabase Edge Function)
// Routes POST /t1 -> nl.ingest_t1_rpc and POST /t2 -> nl.ingest_t2_rpc.
// Privacy invariants: never logs client IP addresses, headers, or request bodies.

const MAX_BYTES = 64 * 1024;
const UPSTREAM_TIMEOUT_MS = 10000;
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const PROXY_SECRET = Deno.env.get("NL_PROXY_SECRET") ?? "";
// Forwarded to PostgREST and checked by nl.check_ingest_gateway(), so the public
// anon key alone cannot call the ingest RPCs directly around this function.
const INGEST_SECRET = Deno.env.get("NL_INGEST_SECRET") ?? "";

// Fail closed: without NL_PROXY_SECRET every request is refused, unless the
// deployment explicitly opts into direct access for local development.
const ALLOW_DIRECT_DEV = Deno.env.get("NL_ALLOW_DIRECT_DEV") === "1";

function checkProxySecret(req: Request): boolean {
  if (!PROXY_SECRET) return ALLOW_DIRECT_DEV;
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

function securityHeaders(origin: string | null, includeContentType = true): Headers {
  const h = new Headers({
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "frame-ancestors 'none'",
    "Vary": "Origin",
  });
  if (includeContentType) {
    h.set("Content-Type", "application/json; charset=utf-8");
  }
  if (isOriginAllowed(origin)) {
    h.set("Access-Control-Allow-Origin", origin!);
    h.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    h.set("Access-Control-Allow-Headers", "Content-Type");
  }
  return h;
}

async function readBodyLimited(req: Request, maxBytes: number): Promise<{ ok: true; text: string } | { ok: false; status: number; error: string }> {
  const cl = req.headers.get("content-length");
  if (cl !== null) {
    const declared = Number(cl);
    if (!Number.isFinite(declared) || declared < 0) {
      return { ok: false, status: 400, error: "invalid_content_length" };
    }
    if (declared > maxBytes) {
      return { ok: false, status: 413, error: "payload_too_large" };
    }
    if (declared === 0) {
      return { ok: false, status: 400, error: "empty_body" };
    }
  }
  if (!req.body) {
    return { ok: false, status: 400, error: "empty_body" };
  }

  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value) {
        total += value.byteLength;
        if (total > maxBytes) {
          await reader.cancel().catch(() => {});
          return { ok: false, status: 413, error: "payload_too_large" };
        }
        chunks.push(value);
      }
    }
  } catch {
    return { ok: false, status: 400, error: "read_error" };
  }

  if (total === 0) {
    return { ok: false, status: 400, error: "empty_body" };
  }

  const combined = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    combined.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { ok: true, text: new TextDecoder().decode(combined) };
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
    return new Response(null, { status: 204, headers: securityHeaders(origin, false) });
  }
  if (!checkProxySecret(req)) {
    return new Response(JSON.stringify({ error: "direct_access_forbidden" }), { status: 403, headers });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405, headers });
  }

  const ctype = (req.headers.get("content-type") ?? "").toLowerCase();
  if (!ctype.includes("application/json")) {
    return new Response(JSON.stringify({ error: "unsupported_media_type" }), { status: 415, headers });
  }

  const path = new URL(req.url).pathname.replace(/\/+$/, "");
  const rpc = path.endsWith("/t1") ? "ingest_t1_rpc" : path.endsWith("/t2") ? "ingest_t2_rpc" : null;
  if (!rpc) {
    return new Response(JSON.stringify({ error: "not_found" }), { status: 404, headers });
  }

  const bodyRes = await readBodyLimited(req, MAX_BYTES);
  if (!bodyRes.ok) {
    return new Response(JSON.stringify({ error: bodyRes.error }), { status: bodyRes.status, headers });
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(bodyRes.text);
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), { status: 400, headers });
  }

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return new Response(JSON.stringify({ error: "server_not_configured" }), { status: 500, headers });
  }

  let resp: Response;
  try {
    resp = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${rpc}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Profile": "nl",
        "Accept-Profile": "nl",
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": `Bearer ${SUPABASE_ANON_KEY}`,
        ...(INGEST_SECRET ? { "x-nl-ingest-secret": INGEST_SECRET } : {}),
      },
      body: JSON.stringify({ p: parsed }),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch {
    return new Response(JSON.stringify({ error: "upstream_unavailable" }), { status: 502, headers });
  }

  if (resp.ok) {
    await resp.body?.cancel().catch(() => {});
    return new Response(null, { status: 204, headers: securityHeaders(origin, false) });
  }

  const errText = await resp.text().catch(() => "");
  let errJson: { code?: string; message?: string } | null = null;
  try {
    errJson = JSON.parse(errText);
  } catch {
    errJson = null;
  }

  if (resp.status === 429 || (errJson?.code === "P0001" && errJson?.message === "rate_limit_exceeded")) {
    return new Response(null, { status: 429, headers: securityHeaders(origin, false) });
  }
  if (resp.status === 400 && (errJson?.code === "22023" || errJson?.code === "22P02")) {
    return new Response(JSON.stringify({ error: "invalid_payload" }), { status: 400, headers });
  }
  return new Response(JSON.stringify({ error: "upstream_error" }), { status: 502, headers });
});
