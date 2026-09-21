import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const CRON_TOKEN_SHA256 = "36c91cef174eaec3619b67dd16032273842af6e5fa49e4120186a13b51dea747";

async function sha256(s: string) {
  const b = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

function headers(id: string) {
  return {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store, max-age=0, must-revalidate",
    "pragma": "no-cache",
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
    "x-frame-options": "DENY",
    "permissions-policy": "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
    "x-rohmat-contract": "sheet-dispatch-v3-worker-forward",
    "x-rohmat-dispatch": "canonical-worker-only",
    "x-request-id": id,
  };
}

function json(v: unknown, status = 200, id: string = crypto.randomUUID()) {
  return new Response(JSON.stringify(v), { status, headers: headers(id) });
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  const fallbackId = crypto.randomUUID();
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405, fallbackId);

  const ct = (req.headers.get("content-type") || "").toLowerCase();
  if (!ct.startsWith("application/json")) return json({ ok: false, error: "unsupported_media_type" }, 415, fallbackId);

  const token = req.headers.get("x-rohmat-cron-token") || "";
  if (!token || await sha256(token) !== CRON_TOKEN_SHA256) return json({ ok: false, error: "unauthorized" }, 401, fallbackId);

  const body = await req.json().catch(() => null);
  const eventId = String(body?.event_id || "");
  const idem = String(body?.idempotency_key || "");
  const requestId = UUID_RE.test(String(body?.request_id || "")) ? String(body.request_id) : fallbackId;
  if (!UUID_RE.test(eventId) || idem.length < 8) return json({ ok: false, error: "invalid_request" }, 400, requestId);

  const su = Deno.env.get("SUPABASE_URL");
  const sk = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!su || !sk) return json({ ok: false, error: "service_unavailable" }, 503, requestId);
  const sb = createClient(su, sk, { auth: { persistSession: false, autoRefreshToken: false } });
  const ev = await sb.from("sheet_sync_outbox").select("tenant_id,idempotency_key").eq("event_id", eventId).maybeSingle();
  if (ev.error || !ev.data || !UUID_RE.test(String(ev.data.tenant_id || "")) || ev.data.idempotency_key !== idem) {
    return json({ ok: false, error: "event_not_found_or_mismatch" }, 404, requestId);
  }
  const tenantId = String(ev.data.tenant_id);
  const workerUrl = `${su.replace(/\/+$/, "")}/functions/v1/rohmat-sheet-sync-worker-v1`;

  try {
    const response = await fetch(workerUrl, {
      method: "POST",
      signal: AbortSignal.timeout(100000),
      headers: {
        "content-type": "application/json",
        "x-rohmat-cron-token": token,
        "x-sdb-tenant-id": tenantId,
      },
      body: JSON.stringify({ source: "compat_dispatch", event_id: eventId, idempotency_key: idem, request_id: requestId }),
    });
    const text = await response.text();
    return new Response(text || JSON.stringify({ ok: response.ok }), { status: response.status, headers: {...headers(requestId),"x-sdb-tenant-id":tenantId} });
  } catch (e: any) {
    const error = e?.name === "TimeoutError" ? "worker_timeout" : "worker_unavailable";
    return json({ ok: false, error }, 502, requestId);
  }
});