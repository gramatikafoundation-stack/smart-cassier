import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const SUPABASE_URL=Deno.env.get("SUPABASE_URL")||"";
const DEFAULT_BUCKET=Deno.env.get("PAYMENT_PROOF_BUCKET")||"payment-proofs";
const COOKIE="__Host-rohmat_kds";
const TOKEN_RE=/^[a-f0-9]{64}$/i;
const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_BODY=65536;
const enc=new TextEncoder();
let PROJECT_ORIGIN="";
try{PROJECT_ORIGIN=SUPABASE_URL?new URL(SUPABASE_URL).origin:""}catch{}

type TenantContext={
  tenant_id:string;
  tenant_slug:string;
  business_name:string;
  merchant_name:string;
  kds_origin:string;
  storage_payment_bucket?:string|null;
};

function cookie(req:Request,name:string){
  const c=req.headers.get("cookie")||"";
  for(const p of c.split(";")){
    const i=p.indexOf("=");
    if(i>0&&p.slice(0,i).trim()===name)return decodeURIComponent(p.slice(i+1).trim());
  }
  return "";
}
function setCookie(token:string,maxAge=14400){
  return `${COOKIE}=${encodeURIComponent(token)}; Path=/; Max-Age=${maxAge}; HttpOnly; Secure; SameSite=Strict`;
}
function clearCookie(){
  return `${COOKIE}=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Strict`;
}
async function sha256(s:string){
  const b=await crypto.subtle.digest("SHA-256",enc.encode(s));
  return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,"0")).join("");
}
function ip(req:Request){
  return(req.headers.get("cf-connecting-ip")||req.headers.get("x-real-ip")||req.headers.get("x-forwarded-for")||"unknown")
    .split(",")[0].trim().slice(0,80);
}
function ua(req:Request){return(req.headers.get("user-agent")||"unknown").slice(0,240)}
async function deviceFingerprint(req:Request){
  const lang=(req.headers.get("accept-language")||"unknown").slice(0,120);
  const platform=(req.headers.get("sec-ch-ua-platform")||"unknown").slice(0,80);
  return sha256(ua(req)+"|"+lang+"|"+platform);
}
function allowedOrigins(ctx:TenantContext){
  return new Set([PROJECT_ORIGIN,ctx.kds_origin].filter(Boolean));
}
function secHeaders(origin:string|null,requestId:string,ctx?:TenantContext){
  const h=new Headers({
    "Content-Type":"application/json; charset=utf-8",
    "Cache-Control":"no-store, max-age=0, must-revalidate",
    "Pragma":"no-cache",
    "X-Content-Type-Options":"nosniff",
    "X-Frame-Options":"DENY",
    "Referrer-Policy":"no-referrer",
    "Permissions-Policy":"camera=(), microphone=(), geolocation=(), payment=(), usb=(), serial=()",
    "Cross-Origin-Resource-Policy":"same-origin",
    "Vary":"Origin, X-SDB-Tenant-ID",
    "X-Rohmat-KDS-Security":"cookie-bff-v4-tenant-bound",
    "X-Rohmat-Contract":"kds-api-master-prototype-v1",
    "X-Request-ID":requestId,
    "Access-Control-Expose-Headers":"X-Request-ID, X-Rohmat-Contract, X-Rohmat-KDS-Security, X-SDB-Tenant-ID"
  });
  if(ctx){
    h.set("X-SDB-Tenant-ID",ctx.tenant_id);
    if(origin&&allowedOrigins(ctx).has(origin))h.set("Access-Control-Allow-Origin",origin);
  }
  return h;
}
function out(origin:string|null,status:number,body:any,requestId:string,ctx?:TenantContext,extra?:Record<string,string>){
  const h=secHeaders(origin,requestId,ctx);
  for(const[k,v]of Object.entries(extra||{}))h.append(k,v);
  return new Response(JSON.stringify(body&&typeof body==="object"?{...body,requestId}:body),{status,headers:h});
}
function validOrigin(origin:string|null,ctx:TenantContext){
  return !!origin&&allowedOrigins(ctx).has(origin);
}
function secureSameOrigin(req:Request,ctx:TenantContext){
  const o=req.headers.get("origin")||"";
  const s=req.headers.get("sec-fetch-site")||"";
  return allowedOrigins(ctx).has(o)&&(s==="same-origin"||s==="same-site"||s==="");
}
async function resolveTenant(sb:any,req:Request):Promise<TenantContext|null>{
  const raw=String(req.headers.get("x-sdb-tenant-id")||"").trim();
  const tenantId=UUID_RE.test(raw)?raw:null;
  if(!tenantId)return null;
  const r=await sb.rpc("master_prototype_tenant_context",{p_tenant_id:tenantId});
  if(r.error||!r.data?.ok||r.data?.enabled===false)return null;
  return r.data as TenantContext;
}
async function integration(
  sb:any,ctx:TenantContext,requestId:string,operation:string,outcome:string,status:number,
  started:number,metadata:any={},entityId:string|null=null,errorCode:string|null=null
){
  try{
    await sb.rpc("integration_record_event_tenant",{
      p_tenant_id:ctx.tenant_id,
      p_request_id:requestId,
      p_service_key:"kds_api",
      p_operation:operation,
      p_direction:"inbound",
      p_outcome:outcome,
      p_http_status:status,
      p_latency_ms:Date.now()-started,
      p_entity_type:entityId?"order":null,
      p_entity_id:entityId,
      p_error_code:errorCode,
      p_metadata:{...metadata,tenant_id:ctx.tenant_id}
    });
  }catch{}
}
function later(p:Promise<any>){
  try{
    const er=(globalThis as any).EdgeRuntime;
    if(er&&typeof er.waitUntil==="function"){er.waitUntil(p);return}
  }catch{}
  p.catch(()=>{});
}

Deno.serve(async(req:Request)=>{
  const started=Date.now();
  const origin=req.headers.get("origin");
  const incoming=req.headers.get("x-request-id")||"";
  const requestId=UUID_RE.test(incoming)?incoming:crypto.randomUUID();

  if(!SUPABASE_URL||!PROJECT_ORIGIN){
    return out(origin,503,{ok:false,error:"service_unavailable"},requestId);
  }
  const K=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(!K)return out(origin,503,{ok:false,error:"service_unavailable"},requestId);
  const sb=createClient(SUPABASE_URL,K,{auth:{persistSession:false,autoRefreshToken:false}});
  const ctx=await resolveTenant(sb,req);
  if(!ctx)return out(origin,400,{ok:false,error:"tenant_required_or_invalid"},requestId);

  if(req.method==="OPTIONS"){
    if(!validOrigin(origin,ctx))return out(origin,403,{ok:false,error:"origin_not_allowed"},requestId,ctx);
    const h=secHeaders(origin,requestId,ctx);
    h.set("Access-Control-Allow-Methods","POST, OPTIONS");
    h.set("Access-Control-Allow-Headers","content-type, x-request-id, x-sdb-tenant-id");
    h.set("Access-Control-Allow-Credentials","true");
    h.set("Access-Control-Max-Age","600");
    return new Response(null,{status:204,headers:h});
  }
  if(req.method!=="POST")return out(origin,405,{ok:false,error:"method_not_allowed"},requestId,ctx,{"Allow":"POST, OPTIONS"});
  if(!validOrigin(origin,ctx))return out(origin,403,{ok:false,error:"origin_not_allowed"},requestId,ctx);

  const ct=(req.headers.get("content-type")||"").toLowerCase();
  if(!ct.startsWith("application/json"))return out(origin,415,{ok:false,error:"unsupported_media_type"},requestId,ctx);
  const len=Number(req.headers.get("content-length")||0);
  if(len>MAX_BODY)return out(origin,413,{ok:false,error:"request_too_large"},requestId,ctx);
  const raw=await req.text();
  if(raw.length>MAX_BODY)return out(origin,413,{ok:false,error:"request_too_large"},requestId,ctx);
  let body:any={};
  try{body=raw?JSON.parse(raw):{}}catch{return out(origin,400,{ok:false,error:"invalid_json"},requestId,ctx)}

  const action=String(body?.action||"");
  const fp=await deviceFingerprint(req);

  if(action==="login"){
    if(!secureSameOrigin(req,ctx))return out(origin,403,{ok:false,error:"csrf_rejected"},requestId,ctx);
    const email=String(body?.email||"").trim().toLowerCase().slice(0,254);
    const password=String(body?.password||"");
    if(email.length<5||password.length<1||password.length>256){
      return out(origin,401,{ok:false,error:"invalid_credentials"},requestId,ctx);
    }
    const keyHash=await sha256(ctx.tenant_id+"|"+ip(req)+"|"+email);
    const rl=await sb.rpc("security_consume_rate_limit",{
      p_bucket:"kds-bff-login:"+ctx.tenant_id,
      p_key_hash:keyHash,p_limit:6,p_window_seconds:900,p_lock_seconds:900
    });
    if(rl.error)return out(origin,503,{ok:false,error:"rate_limit_unavailable"},requestId,ctx);
    if(rl.data?.allowed===false){
      return out(origin,429,{ok:false,error:"rate_limited",retry_after:rl.data.retry_after||900},requestId,ctx,{"Retry-After":String(rl.data.retry_after||900)});
    }
    const r=await sb.rpc("kds_bff_login_bound_tenant",{
      p_tenant_id:ctx.tenant_id,p_email:email,p_password:password,p_fingerprint_hash:fp
    });
    if(r.error||!r.data?.ok||!TOKEN_RE.test(String(r.data?.token||""))){
      later(integration(sb,ctx,requestId,"login","rejected",401,started,{origin},null,"invalid_credentials"));
      return out(origin,401,{ok:false,error:r.data?.error||"invalid_credentials"},requestId,ctx);
    }
    const token=String(r.data.token);
    later(integration(sb,ctx,requestId,"login","success",200,started,{origin,role:r.data.role,scope:"kds"}));
    return out(origin,200,{
      ok:true,email:r.data.email,display_name:r.data.display_name,role:r.data.role,
      expires_at:r.data.expires_at,session_scope:"kds",tenant_id:ctx.tenant_id
    },requestId,ctx,{"Set-Cookie":setCookie(token)});
  }

  const sessionToken=cookie(req,COOKIE);
  const cookieValid=TOKEN_RE.test(sessionToken);
  const legacyToken=String(body?.token||"");
  const isReferenceTenant=ctx.tenant_slug==="rohmat-nasi-uduk";
  const isLegacyProof=isReferenceTenant&&action==="proof"&&TOKEN_RE.test(legacyToken);
  const token=cookieValid?sessionToken:(isLegacyProof?legacyToken:"");
  if(!TOKEN_RE.test(token))return out(origin,401,{ok:false,error:"invalid_session"},requestId,ctx);

  const sess=await sb.rpc("admin_password_session_info_bound_tenant",{
    p_tenant_id:ctx.tenant_id,p_token:token,p_fingerprint_hash:fp
  });
  if(sess.error||!sess.data?.ok){
    later(integration(sb,ctx,requestId,action||"unknown","rejected",401,started,{origin},null,"invalid_session"));
    return out(origin,401,{ok:false,error:"invalid_session"},requestId,ctx,{"Set-Cookie":clearCookie()});
  }

  if(action==="session"){
    if(!secureSameOrigin(req,ctx))return out(origin,403,{ok:false,error:"csrf_rejected"},requestId,ctx);
    later(integration(sb,ctx,requestId,"session","success",200,started,{role:sess.data.role}));
    return out(origin,200,{ok:true,email:sess.data.email,display_name:sess.data.display_name,role:sess.data.role,tenant_id:ctx.tenant_id},requestId,ctx);
  }

  if(action==="logout"){
    if(!secureSameOrigin(req,ctx))return out(origin,403,{ok:false,error:"csrf_rejected"},requestId,ctx);
    await sb.rpc("admin_password_logout_tenant",{p_tenant_id:ctx.tenant_id,p_token:token});
    later(integration(sb,ctx,requestId,"logout","success",200,started,{}));
    return out(origin,200,{ok:true,tenant_id:ctx.tenant_id},requestId,ctx,{"Set-Cookie":clearCookie()});
  }

  if(action==="rpc"){
    if(!secureSameOrigin(req,ctx))return out(origin,403,{ok:false,error:"csrf_rejected"},requestId,ctx);
    const rpc=String(body?.rpc||"");
    const rpcMap:Record<string,string>={
      kds_snapshot:"kds_snapshot_tenant",
      kds_update_order:"kds_update_order_tenant",
      kds_set_availability:"kds_set_availability_tenant"
    };
    const mapped=rpcMap[rpc];
    if(!mapped)return out(origin,400,{ok:false,error:"rpc_not_allowed"},requestId,ctx);
    const args=(body?.args&&typeof body.args==="object"&&!Array.isArray(body.args))?{...body.args}:{};
    delete args.p_token;
    delete args.p_tenant_id;
    args.p_token=token;
    args.p_tenant_id=ctx.tenant_id;
    const r=await sb.rpc(mapped,args);
    if(r.error){
      later(integration(sb,ctx,requestId,"rpc:"+rpc,"failed",400,started,{origin},String(args.p_id||"")||null,"rpc_failed"));
      return out(origin,400,{ok:false,error:"rpc_failed"},requestId,ctx);
    }
    later(integration(sb,ctx,requestId,"rpc:"+rpc,"success",200,started,{origin,order_request_id:r.data?.request_id||null},String(args.p_id||"")||null));
    return out(origin,200,r.data,requestId,ctx);
  }

  if(action==="cashier"){
    if(!secureSameOrigin(req,ctx))return out(origin,403,{ok:false,error:"csrf_rejected"},requestId,ctx);
    const p=(body?.payload&&typeof body.payload==="object"&&!Array.isArray(body.payload))?body.payload:{};
    if(p.action==="snapshot"){
      const r=await sb.rpc("smart_cashier_snapshot_tenant",{p_tenant_id:ctx.tenant_id,p_token:token});
      if(r.error)return out(origin,500,{ok:false,error:"cashier_snapshot_failed"},requestId,ctx);
      later(integration(sb,ctx,requestId,"cashier_snapshot",r.data?.ok?"success":"failed",r.data?.ok?200:400,started,{}));
      return out(origin,r.data?.ok?200:400,r.data||{ok:false,error:"cashier_snapshot_failed"},requestId,ctx);
    }
    if(p.action==="create_order"){
      const items=Array.isArray(p.items)?p.items:[];
      if(items.length<1||items.length>30)return out(origin,400,{ok:false,error:"invalid_items"},requestId,ctx);
      const r=await sb.rpc("smart_cashier_create_tenant",{
        p_tenant_id:ctx.tenant_id,p_token:token,p_source:"cashier_kds",
        p_customer_name:String(p.customerName||"").slice(0,80),
        p_service_mode:String(p.serviceMode||""),
        p_table_number:p.serviceMode==="dine-in"?Number(p.tableNumber||0):null,
        p_items:items,p_payment_method:String(p.paymentMethod||""),
        p_cash_received:p.paymentMethod==="cash"?Number(p.cashReceived||0):null,
        p_note:String(p.note||"").slice(0,500)
      });
      if(r.error)return out(origin,500,{ok:false,error:"cashier_create_failed"},requestId,ctx);
      const chain=UUID_RE.test(String(r.data?.request_id||""))?String(r.data.request_id):requestId;
      later(integration(sb,ctx,chain,"cashier_create_order",r.data?.ok?"success":"failed",r.data?.ok?201:400,started,{edge_request_id:requestId},String(r.data?.order?.id||"")||null,r.data?.ok?null:(r.data?.error||"cashier_create_failed")));
      return out(origin,r.data?.ok?201:400,r.data||{ok:false,error:"cashier_create_failed"},chain,ctx);
    }
    return out(origin,400,{ok:false,error:"invalid_cashier_action"},requestId,ctx);
  }

  if(action==="proof"){
    if(cookieValid&&!secureSameOrigin(req,ctx))return out(origin,403,{ok:false,error:"csrf_rejected"},requestId,ctx);
    const path=String(body?.path||"");
    const tenantPrefix=`tenants/${ctx.tenant_slug}/orders/`;
    const tenantPattern=new RegExp("^"+tenantPrefix.replace(/[.*+?^$()|[\]\\]/g,"\\$&")+"[0-9a-f-]{36}/[A-Za-z0-9._-]+$","i");
    const legacyPattern=/^orders\/[0-9a-f-]{36}\/[A-Za-z0-9._-]+$/i;
    const validPath=tenantPattern.test(path)||(isReferenceTenant&&legacyPattern.test(path));
    if(!validPath)return out(origin,400,{ok:false,error:"invalid_proof_path"},requestId,ctx);
    const bucket=ctx.storage_payment_bucket||DEFAULT_BUCKET;
    const s=await sb.storage.from(bucket).createSignedUrl(path,180);
    if(s.error||!s.data?.signedUrl)return out(origin,404,{ok:false,error:"proof_not_found"},requestId,ctx);
    later(integration(sb,ctx,requestId,"proof","success",200,started,{}));
    return out(origin,200,{ok:true,url:s.data.signedUrl,tenant_id:ctx.tenant_id},requestId,ctx);
  }

  return out(origin,400,{ok:false,error:"unknown_action"},requestId,ctx);
});
