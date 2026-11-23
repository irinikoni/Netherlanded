// Copyright (c) 2026 Eirini Konidari. All rights reserved.
// Edge adapter security tests (Deno). No network, no remote imports.
// Run: deno test --allow-env --allow-read edge/tests/edge.test.ts
//
// Each case loads a fresh copy of an edge module with its own environment, captures the
// handler passed to Deno.serve, and replaces fetch with a recording mock upstream.

type Handler = (req: Request) => Promise<Response> | Response;
type Upstream = { url: string; init: RequestInit & { headers: Record<string, string> } };

const ENV_KEYS = [
  "ALLOWED_ORIGINS", "SUPABASE_URL", "SUPABASE_ANON_KEY", "NL_PROXY_SECRET",
  "NL_INGEST_SECRET", "NL_ALLOW_DIRECT_DEV",
];
const BASE_ENV = {
  ALLOWED_ORIGINS: "https://app.netherlanded.test",
  SUPABASE_URL: "http://upstream.test",
  SUPABASE_ANON_KEY: "anon-key-value",
  NL_PROXY_SECRET: "proxy-secret-value",
  NL_INGEST_SECRET: "ingest-secret-value",
};
const ORIGIN = "https://app.netherlanded.test";
const PROXY = { "x-nl-proxy-secret": "proxy-secret-value" };
let loadCounter = 0;

function fail(msg: string): never {
  throw new Error(msg);
}
function eq<T>(actual: T, expected: T, msg: string) {
  if (actual !== expected) fail(`${msg}: expected ${String(expected)}, got ${String(actual)}`);
}
function ok(cond: unknown, msg: string) {
  if (!cond) fail(msg);
}

async function load(name: string, env: Record<string, string>): Promise<Handler> {
  for (const k of ENV_KEYS) Deno.env.delete(k);
  for (const [k, v] of Object.entries(env)) Deno.env.set(k, v);
  let handler: Handler | null = null;
  // @ts-ignore: test stub for Deno.serve
  Deno.serve = (h: Handler) => {
    handler = h;
    return {};
  };
  await import(new URL(`../${name}/index.ts?case=${loadCounter++}`, import.meta.url).href);
  return handler ?? fail(`${name} did not call Deno.serve`);
}

function mockUpstream(respond: (u: Upstream) => Response | Promise<Response>): Upstream[] {
  const calls: Upstream[] = [];
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const call = { url: String(input), init: { ...(init ?? {}), headers: { ...(init?.headers as Record<string, string>) } } };
    calls.push(call);
    return await respond(call);
  }) as typeof fetch;
  return calls;
}

function req(path: string, opts: { method?: string; headers?: Record<string, string>; body?: BodyInit | null } = {}) {
  const init: RequestInit & { duplex?: string } = {
    method: opts.method ?? "POST",
    headers: opts.headers ?? {},
    body: opts.body ?? null,
  };
  if (opts.body instanceof ReadableStream) init.duplex = "half";
  return new Request(`https://edge.test${path}`, init);
}

const JSON_HDR = { "content-type": "application/json", ...PROXY };
const goodEvent = JSON.stringify({ institution: "thuas", intake: "2026-sep", event: "cohort_joined", app_version: "abcd1234" });

function assertSecurityHeaders(r: Response, ctx: string) {
  eq(r.headers.get("x-content-type-options"), "nosniff", `${ctx} nosniff`);
  eq(r.headers.get("cache-control"), "no-store", `${ctx} no-store`);
  eq(r.headers.get("referrer-policy"), "no-referrer", `${ctx} referrer-policy`);
  eq(r.headers.get("content-security-policy"), "frame-ancestors 'none'", `${ctx} CSP`);
}

// ---------------------------------------------------------------- shared: fail-closed secret
for (const fn of ["ingest", "stats", "editor"]) {
  Deno.test(`${fn}: refuses every request when NL_PROXY_SECRET is unset (fail closed)`, async () => {
    const env: Record<string, string> = { ...BASE_ENV };
    delete env.NL_PROXY_SECRET;
    const h = await load(fn, env);
    const calls = mockUpstream(() => new Response("{}"));
    const r = await h(req(fn === "ingest" ? "/t1" : "/editor", { method: fn === "ingest" ? "POST" : "GET",
      headers: { "content-type": "application/json", authorization: "Bearer x" }, body: fn === "ingest" ? goodEvent : null }));
    eq(r.status, 403, "status");
    eq(calls.length, 0, "no upstream call");
  });

  Deno.test(`${fn}: NL_ALLOW_DIRECT_DEV opens direct access only when exactly "1"`, async () => {
    for (const [val, expectOpen] of [["true", false], ["yes", false], ["1 ", false], ["1", true]] as const) {
      const env: Record<string, string> = { ...BASE_ENV, NL_ALLOW_DIRECT_DEV: val };
      delete env.NL_PROXY_SECRET;
      const h = await load(fn, env);
      mockUpstream(() => new Response(fn === "ingest" ? null : "{}", { status: fn === "ingest" ? 204 : 200 }));
      const r = await h(req(fn === "ingest" ? "/t1" : "/editor", { method: fn === "ingest" ? "POST" : "GET",
        headers: { "content-type": "application/json", authorization: "Bearer x" }, body: fn === "ingest" ? goodEvent : null }));
      eq(r.status === 403, !expectOpen, `NL_ALLOW_DIRECT_DEV=${JSON.stringify(val)}`);
    }
  });

  Deno.test(`${fn}: wrong or missing proxy secret is refused`, async () => {
    const h = await load(fn, BASE_ENV);
    const calls = mockUpstream(() => new Response("{}"));
    for (const secret of [undefined, "", "proxy-secret-valuX", "proxy-secret-value-longer", "PROXY-SECRET-VALUE"]) {
      const headers: Record<string, string> = { "content-type": "application/json", authorization: "Bearer x" };
      if (secret !== undefined) headers["x-nl-proxy-secret"] = secret;
      const r = await h(req(fn === "ingest" ? "/t1" : "/editor", { method: fn === "ingest" ? "POST" : "GET", headers,
        body: fn === "ingest" ? goodEvent : null }));
      eq(r.status, 403, `secret ${JSON.stringify(secret)}`);
      assertSecurityHeaders(r, `secret ${JSON.stringify(secret)}`);
    }
    eq(calls.length, 0, "no upstream call");
  });

  Deno.test(`${fn}: CORS matrix (allowed, disallowed, null, absent origin)`, async () => {
    const h = await load(fn, BASE_ENV);
    mockUpstream(() => new Response(fn === "ingest" ? null : "{}", { status: fn === "ingest" ? 204 : 200 }));
    const mk = (origin?: string) => {
      const headers: Record<string, string> = { ...JSON_HDR, authorization: "Bearer x" };
      if (origin !== undefined) headers.origin = origin;
      return req(fn === "ingest" ? "/t1" : "/editor", { method: fn === "ingest" ? "POST" : "GET", headers,
        body: fn === "ingest" ? goodEvent : null });
    };
    const allowed = await h(mk(ORIGIN));
    eq(allowed.headers.get("access-control-allow-origin"), ORIGIN, "allowed origin echoed");
    ok((allowed.headers.get("vary") ?? "").includes("Origin"), "Vary: Origin");
    for (const bad of ["https://evil.test", "null", "https://app.netherlanded.test.evil.test", "https://APP.netherlanded.test"]) {
      const r = await h(mk(bad));
      eq(r.status, 403, `origin ${bad} refused`);
      eq(r.headers.get("access-control-allow-origin"), null, `no ACAO for ${bad}`);
    }
    const none = await h(mk(undefined));
    ok(none.status !== 403, "server-to-server request without Origin is not blocked by CORS");
    eq(none.headers.get("access-control-allow-origin"), null, "no ACAO without Origin");
  });

  Deno.test(`${fn}: preflight answers before the secret check and leaks nothing`, async () => {
    const h = await load(fn, BASE_ENV);
    const calls = mockUpstream(() => new Response("{}"));
    const r = await h(req(fn === "ingest" ? "/t1" : "/editor", { method: "OPTIONS", headers: { origin: ORIGIN } }));
    eq(r.status, 204, "preflight 204");
    eq(r.headers.get("access-control-allow-origin"), ORIGIN, "preflight ACAO");
    ok(!(r.headers.get("access-control-allow-headers") ?? "").toLowerCase().includes("x-nl"), "no secret header advertised");
    eq(calls.length, 0, "no upstream call on preflight");
  });
}

// ---------------------------------------------------------------- ingest
Deno.test("ingest: forwards only the parsed body, the anon key and the gateway secret", async () => {
  const h = await load("ingest", BASE_ENV);
  const calls = mockUpstream(() => new Response(null, { status: 204 }));
  const r = await h(req("/t2", { headers: { ...JSON_HDR, authorization: "Bearer attacker-jwt", cookie: "a=b",
    "x-nl-ingest-secret": "client-supplied", "x-forwarded-for": "203.0.113.9" }, body: goodEvent }));
  eq(r.status, 204, "accepted");
  eq(calls.length, 1, "one upstream call");
  const up = calls[0];
  eq(up.url, "http://upstream.test/rest/v1/rpc/ingest_t2_rpc", "routes /t2 to tier 2");
  eq(up.init.headers["Authorization"], "Bearer anon-key-value", "client Authorization replaced by anon key");
  eq(up.init.headers["x-nl-ingest-secret"], "ingest-secret-value", "server-side gateway secret, not the client's");
  for (const k of Object.keys(up.init.headers)) {
    ok(!["cookie", "x-forwarded-for", "origin", "user-agent"].includes(k.toLowerCase()), `header ${k} must not be forwarded`);
  }
  eq(up.init.body, JSON.stringify({ p: JSON.parse(goodEvent) }), "body wrapped as {p: ...}");
});

Deno.test("ingest: omits the gateway header when NL_INGEST_SECRET is unset", async () => {
  const env: Record<string, string> = { ...BASE_ENV };
  delete env.NL_INGEST_SECRET;
  const h = await load("ingest", env);
  const calls = mockUpstream(() => new Response(null, { status: 204 }));
  await h(req("/t1", { headers: JSON_HDR, body: goodEvent }));
  ok(!("x-nl-ingest-secret" in calls[0].init.headers), "no empty secret header sent");
});

Deno.test("ingest: method, media type and route checks", async () => {
  const h = await load("ingest", BASE_ENV);
  const calls = mockUpstream(() => new Response(null, { status: 204 }));
  eq((await h(req("/t1", { method: "GET", headers: PROXY }))).status, 405, "GET refused");
  eq((await h(req("/t1", { method: "PUT", headers: JSON_HDR, body: goodEvent }))).status, 405, "PUT refused");
  for (const ct of ["text/plain", "application/x-www-form-urlencoded", "multipart/form-data; boundary=x", ""]) {
    eq((await h(req("/t1", { headers: { ...PROXY, "content-type": ct }, body: goodEvent }))).status, 415, `content-type ${ct}`);
  }
  eq((await h(req("/t1", { headers: { ...PROXY, "content-type": "application/json; charset=utf-8" }, body: goodEvent }))).status,
    204, "charset parameter accepted");
  for (const p of ["/t3", "/t1x", "/xt1", "/", "/t1/extra"]) {
    eq((await h(req(p, { headers: JSON_HDR, body: goodEvent }))).status, 404, `path ${p}`);
  }
  eq((await h(req("/t1/", { headers: JSON_HDR, body: goodEvent }))).status, 204, "trailing slash tolerated");
  ok(calls.every((c) => c.url.endsWith("/ingest_t1_rpc")), "only valid routes reached upstream");
});

Deno.test("ingest: body limits (declared, streamed, lying Content-Length, empty)", async () => {
  const h = await load("ingest", BASE_ENV);
  const calls = mockUpstream(() => new Response(null, { status: 204 }));
  const big = "x".repeat(64 * 1024 + 1);
  eq((await h(req("/t1", { headers: { ...JSON_HDR, "content-length": String(64 * 1024 + 1) }, body: big }))).status, 413, "declared too large");
  const stream = new ReadableStream<Uint8Array>({
    start(c) {
      for (let i = 0; i < 80; i++) c.enqueue(new Uint8Array(1024).fill(32));
      c.close();
    },
  });
  eq((await h(req("/t1", { headers: JSON_HDR, body: stream }))).status, 413, "chunked stream over 64 KB without Content-Length");
  eq((await h(req("/t1", { headers: { ...JSON_HDR, "content-length": "-5" }, body: goodEvent }))).status, 400, "negative length");
  eq((await h(req("/t1", { headers: { ...JSON_HDR, "content-length": "abc" }, body: goodEvent }))).status, 400, "non-numeric length");
  eq((await h(req("/t1", { headers: JSON_HDR, body: "" }))).status, 400, "empty body");
  eq(calls.length, 0, "nothing oversized or empty reached upstream");
});

Deno.test("ingest: malformed and hostile JSON never crashes the adapter", async () => {
  const h = await load("ingest", BASE_ENV);
  mockUpstream(() => new Response(JSON.stringify({ code: "22023", message: "bad" }), { status: 400 }));
  const deep = "[".repeat(30000) + "]".repeat(30000); // 60 KB, under the cap
  for (const [label, body] of [["truncated", '{"a":'], ["not json", "hello"], ["invalid utf-8", new Uint8Array([0x7b, 0xff, 0xfe, 0x7d])],
    ["deep nesting", deep], ["proto pollution", '{"__proto__":{"polluted":true}}']] as const) {
    const r = await h(req("/t1", { headers: JSON_HDR, body: body as BodyInit }));
    ok([400, 204].includes(r.status), `${label}: status ${r.status}`);
    assertSecurityHeaders(r, label);
  }
  ok(({} as Record<string, unknown>).polluted === undefined, "Object prototype not polluted");
});

Deno.test("ingest: upstream errors are mapped without leaking upstream bodies", async () => {
  const h = await load("ingest", BASE_ENV);
  const cases: [Response | Error, number, string | null][] = [
    [new Response(JSON.stringify({ code: "P0001", message: "rate_limit_exceeded" }), { status: 400 }), 429, null],
    [new Response("", { status: 429 }), 429, null],
    [new Response(JSON.stringify({ code: "22023", message: "field sid is not accepted: SECRET-DETAIL" }), { status: 400 }), 400, "invalid_payload"],
    [new Response(JSON.stringify({ code: "42501", message: "direct_access_forbidden SECRET-DETAIL" }), { status: 403 }), 502, "upstream_error"],
    [new Response("<html>SECRET-DETAIL stack trace</html>", { status: 500 }), 502, "upstream_error"],
    [new Error("timeout SECRET-DETAIL"), 502, "upstream_unavailable"],
  ];
  for (const [upstream, status, error] of cases) {
    mockUpstream(() => {
      if (upstream instanceof Error) throw upstream;
      return upstream.clone();
    });
    const r = await h(req("/t1", { headers: JSON_HDR, body: goodEvent }));
    eq(r.status, status, `mapped status for upstream ${upstream instanceof Error ? "error" : upstream.status}`);
    const text = await r.text();
    ok(!text.includes("SECRET-DETAIL"), `upstream detail leaked: ${text}`);
    if (error) eq(JSON.parse(text).error, error, "error code");
  }
});

// ---------------------------------------------------------------- stats
Deno.test("stats: bearer token required; institution validated before any upstream call", async () => {
  const h = await load("stats", BASE_ENV);
  const calls = mockUpstream(() => new Response("{}"));
  const get = (path: string, auth?: string) => h(req(path, { method: "GET", headers: auth ? { ...PROXY, authorization: auth } : PROXY }));
  eq((await get("/stats?institution=thuas")).status, 401, "no token");
  eq((await get("/stats?institution=thuas", "Bearer ")).status, 401, "empty bearer");
  eq((await get("/stats?institution=thuas", "Basic abc")).status, 401, "wrong scheme");
  for (const inst of ["../uva", "THUAS", "a", "x".repeat(33), "thuas%00", "thuas;drop", "thu as"]) {
    eq((await get(`/stats?institution=${encodeURIComponent(inst)}`, "Bearer t")).status, 400, `institution ${inst}`);
  }
  eq((await h(req("/stats", { method: "POST", headers: { ...PROXY, authorization: "Bearer t" } }))).status, 405, "POST refused");
  eq(calls.length, 0, "no upstream call for invalid requests");
});

Deno.test("stats: forwards the caller's JWT (never the anon key as bearer) and maps upstream errors", async () => {
  const h = await load("stats", BASE_ENV);
  const calls = mockUpstream(() => new Response(JSON.stringify({ tables: [] }), { status: 200 }));
  const r = await h(req("/stats?institution=thuas", { method: "GET", headers: { ...PROXY, authorization: "Bearer caller.jwt.value" } }));
  eq(r.status, 200, "ok");
  eq(calls[0].init.headers["Authorization"], "Bearer caller.jwt.value", "caller JWT forwarded");
  eq(calls[0].init.body, JSON.stringify({ p_institution: "thuas", p_snapshot: null }), "latest snapshot only (p_snapshot null)");
  for (const [st, expect] of [[401, 401], [403, 403], [400, 400], [500, 502]] as const) {
    mockUpstream(() => new Response(`SECRET-DETAIL ${st}`, { status: st }));
    const rr = await h(req("/stats?institution=thuas", { method: "GET", headers: { ...PROXY, authorization: "Bearer t" } }));
    eq(rr.status, expect, `upstream ${st}`);
    ok(!(await rr.text()).includes("SECRET-DETAIL"), `upstream ${st} body leaked`);
  }
});

Deno.test("stats: forged JWT institution claim only picks a default; scope is enforced upstream", async () => {
  const h = await load("stats", BASE_ENV);
  const calls = mockUpstream(() => new Response(JSON.stringify({ code: "42501" }), { status: 403 }));
  const payload = btoa(JSON.stringify({ app_metadata: { institution_id: "uva", role: "super_admin" } }))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const forged = `eyJhbGciOiJub25lIn0.${payload}.`;
  const r = await h(req("/stats", { method: "GET", headers: { ...PROXY, authorization: `Bearer ${forged}` } }));
  eq(r.status, 403, "upstream (PostgREST JWT verification + SQL scope) decides");
  eq(calls[0].init.headers["Authorization"], `Bearer ${forged}`, "token passed through untouched for verification");
});

// ---------------------------------------------------------------- editor
Deno.test("editor: echoes only messages raised by our own RPCs", async () => {
  const h = await load("editor", BASE_ENV);
  const post = (body: unknown) => h(req("/editor/service", { headers: { ...JSON_HDR, authorization: "Bearer t" }, body: JSON.stringify(body) }));
  const cases: [number, string, string, boolean][] = [
    [400, "22023", "invalid service_id", true],
    [403, "42501", "forbidden: shared city", true],
    [400, "23514", 'new row violates check constraint "service_url_check" SECRET-DETAIL', false],
    [400, "22P02", "invalid input syntax for type date SECRET-DETAIL", false],
    [400, "22007", "invalid date SECRET-DETAIL", false],
  ];
  for (const [status, code, message, echoed] of cases) {
    mockUpstream(() => new Response(JSON.stringify({ code, message }), { status }));
    const r = await post({ payload: { service_id: "x" }, reason: "test" });
    const body = await r.json();
    eq(body.detail === message, echoed, `code ${code} echo`);
    ok(!JSON.stringify(body).includes("SECRET-DETAIL"), `code ${code} leaked schema detail`);
  }
});

Deno.test("editor: routes, payload shapes and verify coercion", async () => {
  const h = await load("editor", BASE_ENV);
  const calls = mockUpstream(() => new Response("{}", { status: 200 }));
  const auth = { ...JSON_HDR, authorization: "Bearer t" };
  eq((await h(req("/editor/unknown", { headers: auth, body: "{}" }))).status, 404, "unknown route");
  eq((await h(req("/editor/servicex", { headers: auth, body: "{}" }))).status, 404, "suffix route");
  eq((await h(req("/editor/service", { headers: auth, body: "[1,2]" }))).status, 400, "array body refused");
  eq((await h(req("/editor/service", { headers: auth, body: "null" }))).status, 400, "null body refused");
  eq((await h(req("/editor?institution=..%2Fuva", { method: "GET", headers: auth }))).status, 400, "bad institution param");
  await h(req("/editor/verify", { headers: auth, body: JSON.stringify({ entity_type: { $ne: 1 }, entity_key: ["a"], reason: 5 }) }));
  const last = calls[calls.length - 1];
  eq(last.url, "http://upstream.test/rest/v1/rpc/editor_mark_verified", "verify route");
  eq(last.init.body, JSON.stringify({ p_entity_type: "", p_entity_key: "", p_reason: "" }), "non-strings coerced to empty strings");
  eq(last.init.headers["Content-Profile"], "nl_content", "nl_content schema profile");
});
