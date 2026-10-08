import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const CRON_TOKEN_SHA256 = "19c2c128ec9a9e5686019b44279e70d1266ed5b650c94b82488a464a444041fb";
const LEGACY_WRITER_TOKEN_SHA256 = "d3616fa4d6ca975d1b23f0b3195c26165d66d1a8ee7b51f53509a9b2ba2c855d";
const CANONICAL_TENANT = "d8bb901c-7399-485b-8743-b319fde148ac";

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

  const body = await req.json().catch(() => null);
  if (!body) return json({ ok: false, error: "invalid_request" }, 400, fallbackId);

  if (body.action === "delegated_ack") {
    const writerToken = req.headers.get("x-rohmat-writer-token") || "";
    if (!writerToken || await sha256(writerToken) !== LEGACY_WRITER_TOKEN_SHA256) {
      return json({ ok: false, error: "unauthorized" }, 401, fallbackId);
    }
    const requestId = UUID_RE.test(String(body.request_id || "")) ? String(body.request_id) : fallbackId;
    const ack = body.ack;
    if (!ack?.ok || Number(ack.writer_version) !== 4 || ack.tenant_id !== CANONICAL_TENANT || !Array.isArray(ack.years) || !Array.isArray(ack.result)) {
      return json({ ok: false, error: "invalid_delegated_ack" }, 400, requestId);
    }
    const su = Deno.env.get("SUPABASE_URL");
    const sk = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!su || !sk) return json({ ok: false, error: "service_unavailable" }, 503, requestId);
    const sb = createClient(su, sk, { auth: { persistSession: false, autoRefreshToken: false } });
    const cr = await sb.rpc("record_sheet_sync_ack_tenant", {
      p_tenant_id: CANONICAL_TENANT,
      p_request_id: requestId,
      p_http_status: Number(body.http_status || 200),
      p_ack: ack,
    });
    if (cr.error || !cr.data?.ok) return json({ ok: false, error: "canonical_consistency_mismatch", consistency: cr.data || null }, 409, requestId);

    const years = [...new Set(ack.years.map((x:any)=>Number(x)).filter((x:number)=>Number.isInteger(x)))];
    const pending = await sb.from("sheet_sync_outbox")
      .select("event_id,target_year")
      .eq("tenant_id", CANONICAL_TENANT)
      .in("status", ["pending","failed"]);
    if (pending.error) return json({ ok: false, error: "canonical_outbox_read_failed" }, 500, requestId);
    const ids = (pending.data || []).filter((e:any)=>e.target_year == null || years.includes(Number(e.target_year))).map((e:any)=>e.event_id);
    let synced = 0;
    if (ids.length) {
      const upd = await sb.from("sheet_sync_outbox")
        .update({ status:"synced", synced_at:new Date().toISOString(), last_http_status:Number(body.http_status || 200), last_error:null, locked_until:null, locked_by:null })
        .eq("tenant_id", CANONICAL_TENANT)
        .in("event_id", ids)
        .in("status", ["pending","failed"])
        .select("event_id");
      if (upd.error) return json({ ok:false,error:"canonical_outbox_ack_failed" },500,requestId);
      synced = upd.data?.length || 0;
    }
    try {
      await sb.rpc("integration_record_event_tenant", {
        p_tenant_id:CANONICAL_TENANT,p_request_id:requestId,p_service_key:"sheet_writer",
        p_operation:"delegated_ack",p_direction:"inbound",p_outcome:"success",
        p_http_status:Number(body.http_status || 200),p_latency_ms:0,p_error_code:null,
        p_metadata:{years,synced,mode:"legacy-google-writer-proxy",consistency:cr.data}
      });
    } catch {}
    return json({ ok:true,state:"delegated_ack",tenant_id:CANONICAL_TENANT,synced,consistency:cr.data,requestId },200,requestId);
  }

  const token = req.headers.get("x-rohmat-cron-token") || "";
  if (!token || await sha256(token) !== CRON_TOKEN_SHA256) return json({ ok: false, error: "unauthorized" }, 401, fallbackId);

  const eventId = String(body?.event_id || "");
  const idem = String(body?.idempotency_key || "");
  const requestId = UUID_RE.test(String(body?.request_id || "")) ? String(body.request_id) : fallbackId;
  if (!UUID_RE.test(eventId) || idem.length < 8) return json({ ok: false, error: "invalid_request" }, 400, requestId);

  const su = Deno.env.get("SUPABASE_URL");
  const sk = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!su || !sk) return json({ ok: false, error: "service_unavailable" }, 503, requestId);
  const sb = createClient(su, sk, { auth: { persistSession: false, autoRefreshToken: false } });
  const ev = await sb.from("sheet_sync_outbox").select("tenant_id,idempotency_key,target_year").eq("event_id", eventId).maybeSingle();
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
    let workerBody:any=null; try{workerBody=text?JSON.parse(text):null}catch{}
    if(response.ok&&workerBody?.state==="delegated_external"){
      const gateway=await fetch("https://yybhpmjuywjxqurrrrxl.supabase.co/functions/v1/rohmat-sheet-sync-dispatch-v1",{
        method:"POST",signal:AbortSignal.timeout(100000),
        headers:{"content-type":"application/json","x-rohmat-cron-token":token},
        body:JSON.stringify({
          source:"canonical_delegate",event_id:eventId,idempotency_key:idem,request_id:requestId,
          target_year:ev.data.target_year??null,canonical_tenant_id:tenantId
        })
      });
      const gatewayText=await gateway.text();
      return new Response(gatewayText||JSON.stringify({ok:gateway.ok}),{
        status:gateway.status,headers:{...headers(requestId),"x-sdb-tenant-id":tenantId,"x-rohmat-dispatch":"delegated-google-writer"}
      });
    }
    return new Response(text || JSON.stringify({ ok: response.ok }), { status: response.status, headers: {...headers(requestId),"x-sdb-tenant-id":tenantId} });
  } catch (e: any) {
    const error = e?.name === "TimeoutError" ? "worker_timeout" : "worker_unavailable";
    return json({ ok: false, error }, 502, requestId);
  }
});