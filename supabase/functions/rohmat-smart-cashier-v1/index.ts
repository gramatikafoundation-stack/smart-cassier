import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const TOKEN_RE=/^[a-f0-9]{64}$/i;
const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_BODY=65536;
const enc=new TextEncoder();

type TenantContext={
  tenant_id:string;
  tenant_slug:string;
  admin_origin:string;
  kds_origin:string;
  enabled?:boolean;
};

async function sha256(s:string){
  const b=await crypto.subtle.digest("SHA-256",enc.encode(s));
  return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,"0")).join("");
}
function ip(req:Request){
  return(req.headers.get("cf-connecting-ip")||req.headers.get("x-real-ip")||req.headers.get("x-forwarded-for")||"unknown")
    .split(",")[0].trim().slice(0,80);
}
function ua(req:Request){return(req.headers.get("user-agent")||"unknown").slice(0,240)}
async function fingerprint(req:Request){
  const lang=(req.headers.get("accept-language")||"unknown").slice(0,120);
  const platform=(req.headers.get("sec-ch-ua-platform")||"unknown").slice(0,80);
  return sha256(ua(req)+"|"+lang+"|"+platform);
}
function origins(ctx:TenantContext){return new Set([ctx.admin_origin,ctx.kds_origin].filter(Boolean))}
function headers(origin:string,requestId:string,ctx?:TenantContext){
  const h=new Headers({
    "content-type":"application/json; charset=utf-8",
    "cache-control":"no-store, max-age=0, must-revalidate",
    "pragma":"no-cache",
    "x-content-type-options":"nosniff",
    "x-frame-options":"DENY",
    "referrer-policy":"no-referrer",
    "permissions-policy":"camera=(), microphone=(), geolocation=(), payment=()",
    "cross-origin-resource-policy":"cross-origin",
    "vary":"Origin, X-SDB-Tenant-ID",
    "x-rohmat-security":"smart-cashier-master-prototype-v1",
    "x-rohmat-contract":"smart-cashier-master-prototype-v1",
    "x-request-id":requestId,
    "access-control-expose-headers":"X-Request-ID, X-Rohmat-Contract, X-Rohmat-Security, X-SDB-Tenant-ID"
  });
  if(ctx){
    h.set("x-sdb-tenant-id",ctx.tenant_id);
    if(origins(ctx).has(origin))h.set("access-control-allow-origin",origin);
  }
  return h;
}
function json(origin:string,body:any,status=200,requestId:string=crypto.randomUUID(),ctx?:TenantContext,extra?:Record<string,string>){
  const h=headers(origin,requestId,ctx);
  for(const[k,v]of Object.entries(extra||{}))h.set(k,v);
  return new Response(JSON.stringify(body&&typeof body==="object"?{...body,requestId}:body),{status,headers:h});
}
async function resolveTenant(sb:any,req:Request):Promise<TenantContext|null>{
  const raw=String(req.headers.get("x-sdb-tenant-id")||"").trim();
  const tenantId=UUID_RE.test(raw)?raw:null;
  const requestOrigin=String(req.headers.get("origin")||"").trim()||null;
  const r=await sb.rpc("master_prototype_runtime_context",{
    p_tenant_id:tenantId,
    p_origin:tenantId?null:requestOrigin,
    p_app_kind:null
  });
  if(r.error||!r.data?.ok||r.data?.enabled===false)return null;
  return r.data as TenantContext;
}
async function audit(sb:any,ctx:TenantContext,action:string,token:string,req:Request,success:boolean,metadata:any){
  try{
    await sb.from("security_audit_events").insert({
      event_type:"cashier",action,
      principal_hash:await sha256(token),
      ip_hash:await sha256(ip(req)),
      success,
      metadata:{...metadata,tenant_id:ctx.tenant_id,tenant_slug:ctx.tenant_slug}
    });
  }catch{}
}
async function integration(
  sb:any,ctx:TenantContext,requestId:string,operation:string,outcome:string,status:number,
  started:number,metadata:any={},entityId:string|null=null,errorCode:string|null=null
){
  try{
    await sb.rpc("integration_record_event_tenant",{
      p_tenant_id:ctx.tenant_id,p_request_id:requestId,p_service_key:"smart_cashier",
      p_operation:operation,p_direction:"inbound",p_outcome:outcome,p_http_status:status,
      p_latency_ms:Date.now()-started,p_entity_type:entityId?"order":null,p_entity_id:entityId,
      p_error_code:errorCode,p_metadata:{...metadata,tenant_id:ctx.tenant_id}
    });
  }catch{}
}

Deno.serve(async(req:Request)=>{
  const started=Date.now();
  const origin=req.headers.get("origin")||"";
  const incoming=req.headers.get("x-request-id")||"";
  const requestId=UUID_RE.test(incoming)?incoming:crypto.randomUUID();
  const url=Deno.env.get("SUPABASE_URL")||"";
  const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(!url||!key)return json(origin,{ok:false,error:"service_unavailable"},503,requestId);

  const sb=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const ctx=await resolveTenant(sb,req);
  if(!ctx)return json(origin,{ok:false,error:"tenant_required_or_invalid"},400,requestId);
  const allowed=origins(ctx);

  if(req.method==="OPTIONS"){
    if(!allowed.has(origin))return json(origin,{ok:false,error:"origin_not_allowed"},403,requestId,ctx);
    const h=headers(origin,requestId,ctx);
    h.set("access-control-allow-methods","POST, OPTIONS");
    h.set("access-control-allow-headers","content-type,x-admin-session,x-kds-session,x-request-id,x-sdb-tenant-id");
    h.set("access-control-max-age","600");
    return new Response(null,{status:204,headers:h});
  }
  if(req.method!=="POST")return json(origin,{ok:false,error:"method_not_allowed"},405,requestId,ctx,{"allow":"POST, OPTIONS"});
  if(!allowed.has(origin))return json(origin,{ok:false,error:"origin_not_allowed"},403,requestId,ctx);

  const ct=(req.headers.get("content-type")||"").toLowerCase();
  if(!ct.startsWith("application/json"))return json(origin,{ok:false,error:"unsupported_media_type"},415,requestId,ctx);
  const len=Number(req.headers.get("content-length")||0);
  if(len>MAX_BODY)return json(origin,{ok:false,error:"request_too_large"},413,requestId,ctx);
  const raw=await req.text();
  if(raw.length>MAX_BODY)return json(origin,{ok:false,error:"request_too_large"},413,requestId,ctx);

  let body:any={};
  try{body=JSON.parse(raw)}catch{return json(origin,{ok:false,error:"invalid_json"},400,requestId,ctx)}
  const token=String(req.headers.get("x-admin-session")||req.headers.get("x-kds-session")||"").trim();
  if(!TOKEN_RE.test(token))return json(origin,{ok:false,error:"invalid_session"},401,requestId,ctx);

  const action=String(body.action||"snapshot");
  if(!["snapshot","create_order"].includes(action))return json(origin,{ok:false,error:"invalid_action"},400,requestId,ctx);

  const keyHash=await sha256(ctx.tenant_id+"|"+ip(req)+"|"+token+"|"+action);
  const limit=action==="snapshot"?120:30;
  const windowSec=60;
  const lockSec=action==="snapshot"?60:120;
  const rl=await sb.rpc("security_consume_rate_limit",{
    p_bucket:"cashier-"+action+":"+ctx.tenant_id,
    p_key_hash:keyHash,p_limit:limit,p_window_seconds:windowSec,p_lock_seconds:lockSec
  });
  if(rl.error)return json(origin,{ok:false,error:"rate_limit_unavailable"},503,requestId,ctx);
  if(rl.data?.allowed===false)return json(origin,{ok:false,error:"rate_limited",retry_after:rl.data.retry_after||60},429,requestId,ctx,{"retry-after":String(rl.data.retry_after||60)});

  const fp=await fingerprint(req);
  const sess=await sb.rpc("admin_password_session_info_bound_tenant",{
    p_tenant_id:ctx.tenant_id,p_token:token,p_fingerprint_hash:fp
  });
  if(sess.error||!sess.data?.ok){
    await audit(sb,ctx,action,token,req,false,{reason:"invalid_or_mismatched_session",origin});
    await integration(sb,ctx,requestId,action,"rejected",401,started,{origin},null,"invalid_session");
    return json(origin,{ok:false,error:"invalid_session"},401,requestId,ctx);
  }

  try{
    if(action==="snapshot"){
      const {data,error}=await sb.rpc("smart_cashier_snapshot_tenant",{p_tenant_id:ctx.tenant_id,p_token:token});
      if(error)throw error;
      if(!data?.ok){
        await audit(sb,ctx,action,token,req,false,{origin});
        await integration(sb,ctx,requestId,action,"rejected",401,started,{origin},null,"invalid_session");
        return json(origin,{ok:false,error:"invalid_session"},401,requestId,ctx);
      }
      await audit(sb,ctx,action,token,req,true,{origin,role:sess.data.role,fingerprint_bound:true});
      await integration(sb,ctx,requestId,action,"success",200,started,{origin,role:sess.data.role});
      return json(origin,data,200,requestId,ctx);
    }

    const source=String(body.source||"");
    if(!["cashier_admin","cashier_kds"].includes(source))return json(origin,{ok:false,error:"invalid_source"},400,requestId,ctx);
    if(source==="cashier_admin"&&origin!==ctx.admin_origin)return json(origin,{ok:false,error:"source_origin_mismatch"},403,requestId,ctx);
    if(source==="cashier_kds"&&origin!==ctx.kds_origin)return json(origin,{ok:false,error:"source_origin_mismatch"},403,requestId,ctx);

    const items=Array.isArray(body.items)?body.items:[];
    if(items.length<1||items.length>30)return json(origin,{ok:false,error:"invalid_items"},400,requestId,ctx);

    const {data,error}=await sb.rpc("smart_cashier_create_tenant",{
      p_tenant_id:ctx.tenant_id,p_token:token,p_source:source,
      p_customer_name:String(body.customerName||"").slice(0,80),
      p_service_mode:String(body.serviceMode||""),
      p_table_number:body.serviceMode==="dine-in"?Number(body.tableNumber||0):null,
      p_items:items,p_payment_method:String(body.paymentMethod||""),
      p_cash_received:body.paymentMethod==="cash"?Number(body.cashReceived||0):null,
      p_note:String(body.note||"").slice(0,500)
    });
    if(error)throw error;
    if(!data?.ok){
      const code=data?.error==="invalid_session"?401:400;
      await audit(sb,ctx,action,token,req,false,{origin,source,error:data?.error||"create_failed"});
      await integration(sb,ctx,requestId,action,"failed",code,started,{origin,source},null,data?.error||"create_failed");
      return json(origin,data||{ok:false,error:"create_failed"},code,requestId,ctx);
    }
    const chain=UUID_RE.test(String(data.request_id||""))?String(data.request_id):requestId;
    await audit(sb,ctx,action,token,req,true,{origin,source,role:sess.data.role,fingerprint_bound:true,request_id:chain});
    await integration(sb,ctx,chain,action,"success",201,started,{origin,source,edge_request_id:requestId},String(data?.order?.id||"")||null);
    return json(origin,data,201,chain,ctx);
  }catch{
    await audit(sb,ctx,action,token,req,false,{origin,reason:"service_error"});
    await integration(sb,ctx,requestId,action,"failed",500,started,{origin},null,"cashier_service_failed");
    return json(origin,{ok:false,error:"cashier_service_failed"},500,requestId,ctx);
  }
});
