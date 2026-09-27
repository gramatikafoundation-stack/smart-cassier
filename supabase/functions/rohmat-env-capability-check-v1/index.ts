import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const CRON_TOKEN_SHA256=Deno.env.get("CRON_TOKEN_SHA256")||"19c2c128ec9a9e5686019b44279e70d1266ed5b650c94b82488a464a444041fb";
const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const enc=new TextEncoder();
type TenantCtx={tenant_id:string;public_origin:string;admin_origin:string;kds_origin:string;enabled?:boolean};

async function sha256(s:string){
  const b=await crypto.subtle.digest("SHA-256",enc.encode(s));
  return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,"0")).join("");
}
const H={
  "content-type":"application/json; charset=utf-8",
  "cache-control":"no-store, max-age=0",
  "x-content-type-options":"nosniff",
  "x-frame-options":"DENY",
  "referrer-policy":"no-referrer",
  "permissions-policy":"camera=(), microphone=(), geolocation=()",
  "x-rohmat-contract":"reliability-probe-smart-order-b3-v2"
};
function json(v:any,status=200,tenantId?:string){
  return new Response(JSON.stringify(v),{
    status,headers:{...H,...(tenantId?{"x-sdb-tenant-id":tenantId}:{}),vary:"X-SDB-Tenant-ID"}
  });
}
async function tenantContext(sb:any,req:Request):Promise<TenantCtx|null>{
  const id=String(req.headers.get("x-sdb-tenant-id")||"").trim();
  if(!UUID_RE.test(id))return null;
  const r=await sb.rpc("master_prototype_tenant_context",{p_tenant_id:id});
  if(r.error||!r.data?.ok||r.data?.enabled===false)return null;
  return r.data as TenantCtx;
}
async function one(
  sb:any,ctx:TenantCtx,key:string,url:string,method="GET",headers:Record<string,string>={}
){
  const t=Date.now();let status=0,ok=false,err:string|null=null,bytes=0,cache:string|null=null;
  try{
    const r=await fetch(url,{method,redirect:"follow",signal:AbortSignal.timeout(8000),headers});
    status=r.status;cache=r.headers.get("cache-control");
    ok=key==="order_gateway"?status===204:status>=200&&status<400;
    if(method==="GET"&&key!=="order_gateway"){const b=await r.arrayBuffer();bytes=b.byteLength}
    if(!ok)err="unexpected_http_status";
  }catch(e:any){err=e?.name==="TimeoutError"?"timeout":"fetch_failed"}
  const latency=Math.max(0,Date.now()-t);
  try{
    await sb.rpc("reliability_record_probe_tenant",{
      p_tenant_id:ctx.tenant_id,p_service_key:key,p_ok:ok,p_http_status:status||null,
      p_latency_ms:latency,p_error:err
    });
  }catch{}
  if(["public_web","admin_web","kds_web","database_web"].includes(key)){
    try{
      await sb.rpc("frontend_performance_record_tenant",{
        p_tenant_id:ctx.tenant_id,p_service_key:key,p_status_code:status||null,
        p_latency_ms:latency,p_payload_bytes:bytes,p_cache_control:cache
      });
    }catch{}
  }
  if(key==="kds_web"){
    try{
      await sb.rpc("kds_record_observability",{
        p_metric:"NAV_TTFB",p_value:latency,p_action:"reliability_probe",
        p_http_status:status||null,p_rating:latency<=800?"good":latency<=1800?"needs-improvement":"poor",
        p_release_id:"batch1-shared-foundation-v1",p_request_id:null,
        p_metadata:{tenant_id:ctx.tenant_id,synthetic:true}
      });
    }catch{}
  }
  return{service:key,ok,status,latency_ms:latency,payload_bytes:bytes,error:err};
}

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return json({ok:false,error:"method_not_allowed"},405);
  const token=req.headers.get("x-rohmat-cron-token")||"";
  if(!token||(await sha256(token))!==CRON_TOKEN_SHA256)return json({ok:false,error:"unauthorized"},401);

  const U=Deno.env.get("SUPABASE_URL")||"";
  const K=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(!U||!K)return json({ok:false,error:"service_unavailable"},503);
  const sb=createClient(U,K,{auth:{persistSession:false,autoRefreshToken:false}});
  const ctx=await tenantContext(sb,req);
  if(!ctx)return json({ok:false,error:"tenant_required_or_invalid"},400);

  const publicBase=String(ctx.public_origin||"").replace(/\/$/,"");
  const adminBase=String(ctx.admin_origin||"").replace(/\/$/,"");
  const kdsBase=String(ctx.kds_origin||"").replace(/\/$/,"");
  const adminUrl=adminBase===publicBase?adminBase+"/admin":adminBase+"/";
  const kdsUrl=kdsBase===publicBase?kdsBase+"/kds/login":kdsBase+"/login";
  const databaseUrl=publicBase+"/database";
  const results=await Promise.all([
    one(sb,ctx,"public_web",publicBase+"/"),
    one(sb,ctx,"admin_web",adminUrl),
    one(sb,ctx,"kds_web",kdsUrl),
    one(sb,ctx,"database_web",databaseUrl),
    one(sb,ctx,"order_gateway",U+"/functions/v1/create-order","OPTIONS",{
      "Origin":ctx.public_origin,
      "Access-Control-Request-Method":"POST",
      "Access-Control-Request-Headers":"content-type,apikey,authorization,x-sdb-tenant-id",
      "X-SDB-Tenant-ID":ctx.tenant_id
    })
  ]);
  const ok=results.every(x=>x.ok);
  return json({
    ok,contract:"reliability-probe-smart-order-b3-v2",
    tenant_id:ctx.tenant_id,checked_at:new Date().toISOString(),results
  },ok?200:503,ctx.tenant_id);
});
