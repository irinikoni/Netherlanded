// Copyright (c) 2026 Eirini Konidari. All rights reserved.
// Netherlanded Edge Content Editor Adapter (Deno / Supabase Edge Function)
// Routes GET /editor -> nl_content.editor_list, POST /editor/{service,step-local,fact,verify} -> nl_content RPCs.
// Privacy & security invariants: fail-closed CORS, 64 KB body cap, never logs IPs, headers, JWTs, or bodies.

const MAX_BYTES = 64 * 1024;
const UPSTREAM_TIMEOUT_MS = 10000;
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
// Prefer the new publishable key (SUPABASE_PUBLISHABLE_KEYS is a JSON object keyed by name);
// fall back to the legacy anon JWT only while that key still exists on the project.
function publishableKey(): string {
  try {
    const k = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}")?.default;
    if (typeof k === "string" && k) return k;
  } catch {
    // malformed JSON: fall through to the legacy key
  }
  return Deno.env.get("SUPABASE_ANON_KEY") ?? "";
}
const SUPABASE_ANON_KEY = publishableKey();
const PROXY_SECRET = Deno.env.get("NL_PROXY_SECRET") ?? "";
// Forwarded to PostgREST and checked by nl.check_ingest_gateway(), so callers with a
// staff JWT cannot bypass Edge body caps, rate limits, and error sanitization via /rest/v1/rpc.
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
    "Vary": "Origin, Authorization",
  });
  if (includeContentType) {
    h.set("Content-Type", "application/json; charset=utf-8");
  }
  if (isOriginAllowed(origin)) {
    h.set("Access-Control-Allow-Origin", origin!);
    h.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    h.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  }
  return h;
}

async function readBodyLimited(
  req: Request,
  maxBytes: number,
): Promise<{ ok: true; text: string } | { ok: false; status: number; error: string }> {
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

async function callEditorRpc(
  rpcName: string,
  rpcBody: Record<string, unknown>,
  jwt: string,
  headers: Headers,
): Promise<Response> {
  let resp: Response;
  try {
    resp = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${rpcName}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Profile": "nl_content",
        "Accept-Profile": "nl_content",
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": `Bearer ${jwt}`,
        ...(INGEST_SECRET ? { "x-nl-ingest-secret": INGEST_SECRET } : {}),
      },
      body: JSON.stringify(rpcBody),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch {
    return new Response(JSON.stringify({ error: "upstream_unavailable" }), { status: 502, headers });
  }

  if (resp.ok) {
    const body = await resp.text();
    return new Response(body, { status: 200, headers });
  }

  const errText = await resp.text().catch(() => "");
  let errJson: { code?: string; message?: string } | null = null;
  try {
    errJson = JSON.parse(errText);
  } catch {
    errJson = null;
  }

  if (resp.status === 401) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401, headers });
  }
  // Only messages raised by our own RPCs (22023 / 42501) are safe to echo; other
  // database errors (constraint names, casts) would reveal schema internals.
  const ownMessage = (errJson?.code === "22023" || errJson?.code === "42501") ? errJson?.message : undefined;
  if (resp.status === 403 || errJson?.code === "42501") {
    return new Response(JSON.stringify({ error: "forbidden", detail: ownMessage ?? "forbidden" }), {
      status: 403,
      headers,
    });
  }
  if (
    resp.status === 400 ||
    errJson?.code === "22023" ||
    errJson?.code === "22P02" ||
    errJson?.code === "22007" ||
    errJson?.code === "23514"
  ) {
    return new Response(JSON.stringify({ error: "invalid_payload", detail: ownMessage ?? "invalid_payload" }), {
      status: 400,
      headers,
    });
  }
  return new Response(JSON.stringify({ error: "upstream_error" }), { status: 502, headers });
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

  if (req.method !== "GET" && req.method !== "POST") {
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

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return new Response(JSON.stringify({ error: "server_not_configured" }), { status: 500, headers });
  }

  const url = new URL(req.url);
  const path = url.pathname.replace(/\/+$/, "");

  if (req.method === "GET") {
    if (!path.endsWith("/editor")) {
      return new Response(JSON.stringify({ error: "not_found" }), { status: 404, headers });
    }
    const instParam = url.searchParams.get("institution");
    if (instParam && !/^[a-z0-9_-]{2,32}$/.test(instParam)) {
      return new Response(JSON.stringify({ error: "invalid_institution" }), { status: 400, headers });
    }
    return callEditorRpc("editor_list", { p_institution: instParam || null }, jwt, headers);
  }

  const ctype = (req.headers.get("content-type") ?? "").toLowerCase();
  if (!ctype.includes("application/json")) {
    return new Response(JSON.stringify({ error: "unsupported_media_type" }), { status: 415, headers });
  }

  const bodyRes = await readBodyLimited(req, MAX_BYTES);
  if (!bodyRes.ok) {
    return new Response(JSON.stringify({ error: bodyRes.error }), { status: bodyRes.status, headers });
  }

  let parsed: Record<string, unknown>;
  try {
    const raw = JSON.parse(bodyRes.text);
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      return new Response(JSON.stringify({ error: "invalid_json" }), { status: 400, headers });
    }
    parsed = raw as Record<string, unknown>;
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), { status: 400, headers });
  }

  const reason = typeof parsed.reason === "string" ? parsed.reason : "";

  if (path.endsWith("/editor/service")) {
    const payload = (parsed.payload && typeof parsed.payload === "object") ? parsed.payload : parsed;
    return callEditorRpc("editor_upsert_service", { p_payload: payload, p_reason: reason }, jwt, headers);
  }
  if (path.endsWith("/editor/step-local")) {
    const payload = (parsed.payload && typeof parsed.payload === "object") ? parsed.payload : parsed;
    return callEditorRpc("editor_upsert_step_local", { p_payload: payload, p_reason: reason }, jwt, headers);
  }
  if (path.endsWith("/editor/fact")) {
    const payload = (parsed.payload && typeof parsed.payload === "object") ? parsed.payload : parsed;
    return callEditorRpc("editor_publish_fact", { p_payload: payload, p_reason: reason }, jwt, headers);
  }
  if (path.endsWith("/editor/verify")) {
    return callEditorRpc(
      "editor_mark_verified",
      {
        p_entity_type: typeof parsed.entity_type === "string" ? parsed.entity_type : "",
        p_entity_key: typeof parsed.entity_key === "string" ? parsed.entity_key : "",
        p_reason: reason,
      },
      jwt,
      headers,
    );
  }

  return new Response(JSON.stringify({ error: "not_found" }), { status: 404, headers });
});
