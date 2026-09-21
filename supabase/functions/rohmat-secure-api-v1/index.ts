import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const TOKEN_RE=/^[a-f0-9]{64}$/i;
const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const enc=new TextEncoder();

const RPC_MAP:Record<string,string>={
  admin_password_login:"admin_password_login_tenant",
  admin_password_logout:"admin_password_logout_tenant",
  admin_password_session_info:"admin_password_session_info_tenant",
  admin_password_change:"admin_password_change_tenant",
  admin_password_set_for_admin:"admin_password_set_for_admin_tenant",

  admin_console_snapshot:"admin_console_snapshot_tenant",
  admin_console_update_settings:"admin_console_update_settings_tenant",
  admin_console_save_menu:"admin_console_save_menu_tenant",
  admin_console_set_menu_visible:"admin_console_set_menu_visible_tenant",
  admin_console_update_order:"admin_console_update_order_tenant",
  admin_console_add_admin:"admin_console_add_admin_tenant",
  admin_console_remove_admin:"admin_console_remove_admin_tenant",
  admin_console_transfer_superadmin:"admin_console_transfer_superadmin_tenant",
  admin_console_update_admin_design_page:"admin_console_update_admin_design_page_tenant",

  admin_design_system_history:"admin_design_system_history_tenant",
  admin_design_system_publish:"admin_design_system_publish_tenant",
  admin_design_system_rollback:"admin_design_system_rollback_tenant",
  admin_design_system_save_draft:"admin_design_system_save_draft_tenant",
  admin_design_system_registry:"admin_design_system_registry_tenant",
  admin_design_system_set_element:"admin_design_system_set_element_tenant",
  admin_design_system_reset_element:"admin_design_system_reset_element_tenant",
  admin_design_system_set_scope:"admin_design_system_set_scope_tenant",
  admin_design_system_reset_scope:"admin_design_system_reset_scope_tenant",
  admin_theme_profile_catalog:"admin_theme_profile_catalog_tenant",

  kds_snapshot:"kds_snapshot_tenant",
  kds_update_order:"kds_update_order_tenant",
  kds_set_availability:"kds_set_availability_tenant",
  kds_console_snapshot:"kds_console_snapshot_tenant",
  kds_console_order_action:"kds_console_order_action_tenant",
  kds_console_set_available:"kds_console_set_available_tenant",

  smart_cashier_snapshot:"smart_cashier_snapshot_tenant",
  smart_cashier_create:"smart_cashier_create_tenant"
};

const READ_RPC=new Set([
  "admin_password_session_info","admin_console_snapshot","admin_design_system_history",
  "admin_design_system_registry","admin_theme_profile_catalog",
  "kds_snapshot","kds_console_snapshot","smart_cashier_snapshot"
]);
const SENSITIVE_RPC=new Set([
  "admin_password_login","admin_password_change","admin_password_set_for_admin",
  "admin_console_add_admin","admin_console_remove_admin","admin_console_transfer_superadmin",
  "admin_design_system_publish","admin_design_system_rollback"
]);
const SUPERADMIN_RPC=new Set([
  "admin_password_set_for_admin","admin_console_add_admin",
  "admin_console_remove_admin","admin_console_transfer_superadmin"
]);

type TenantContext={
  tenant_id:string;
  tenant_slug:string;
  admin_origin:string;
  kds_origin:string;
  enabled:boolean;
};

async function sha256(s:string){
  const b=await crypto.subtle.digest("SHA-256",enc.encode(s));
  return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,"0")).join("");
}
function clientIp(req:Request){
  return(req.headers.get("cf-connecting-ip")||req.headers.get("x-real-ip")||req.headers.get("x-forwarded-for")||"unknown")
    .split(",")[0].trim().slice(0,80);
}
function allowedOrigins(ctx:TenantContext){
  return new Set([ctx.admin_origin,ctx.kds_origin].filter(Boolean));
}
function baseHeaders(origin:string,ctx?:TenantContext){
  const h=new Headers({
    "content-type":"application/json; charset=utf-8",
    "cache-control":"no-store, max-age=0, must-revalidate",
    "pragma":"no-cache",
    "x-content-type-options":"nosniff",
    "x-frame-options":"DENY",
    "referrer-policy":"no-referrer",
    "permissions-policy":"camera=(), microphone=(), geolocation=(), payment=(), usb=()",
    "cross-origin-resource-policy":"cross-origin",
    "vary":"Origin, X-SDB-Tenant-ID",
    "x-rohmat-security":"secure-api-master-prototype-v1"
  });
  if(ctx){
    h.set("x-sdb-tenant-id",ctx.tenant_id);
    if(allowedOrigins(ctx).has(origin))h.set("access-control-allow-origin",origin);
  }
  return h;
}
function json(origin:string,data:unknown,status=200,ctx?:TenantContext,extra?:Record<string,string>){
  const h=baseHeaders(origin,ctx);
  for(const[k,v]of Object.entries(extra||{}))h.set(k,v);
  return new Response(JSON.stringify(data),{status,headers:h});
}
async function resolveTenant(sb:any,req:Request):Promise<TenantContext|null>{
  const raw=String(req.headers.get("x-sdb-tenant-id")||"").trim();
  const tenantId=UUID_RE.test(raw)?raw:null;
  const requestOrigin=String(req.headers.get("origin")||"").trim()||null;
  const r=await sb.rpc("master_prototype_runtime_context",{
    p_tenant_id:tenantId,
    p_origin:requestOrigin,
    p_app_kind:null
  });
  if(r.error||!r.data?.ok||r.data?.enabled===false)return null;
  return r.data as TenantContext;
}
async function audit(
  sb:any,ctx:TenantContext,eventType:string,action:string,
  principalHash:string|null,ipHash:string,success:boolean,metadata:any
){
  try{
    await sb.from("security_audit_events").insert({
      event_type:eventType,action,principal_hash:principalHash,ip_hash:ipHash,success,
      metadata:{...metadata,tenant_id:ctx.tenant_id,tenant_slug:ctx.tenant_slug}
    });
  }catch{}
}

Deno.serve(async(req:Request)=>{
  const origin=req.headers.get("origin")||"";
  const U=Deno.env.get("SUPABASE_URL")||"";
  const K=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(!U||!K)return json(origin,{ok:false,error:"service_unavailable"},503);

  const sb=createClient(U,K,{auth:{persistSession:false,autoRefreshToken:false}});
  const ctx=await resolveTenant(sb,req);
  if(!ctx)return json(origin,{ok:false,error:"tenant_required_or_invalid"},400);
  const origins=allowedOrigins(ctx);

  if(req.method==="OPTIONS"){
    if(!origins.has(origin))return json(origin,{ok:false,error:"origin_not_allowed"},403,ctx);
    const h=baseHeaders(origin,ctx);
    h.set("access-control-allow-methods","POST, OPTIONS");
    h.set("access-control-allow-headers","content-type, x-requested-with, x-sdb-tenant-id");
    h.set("access-control-max-age","600");
    return new Response(null,{status:204,headers:h});
  }
  if(req.method!=="POST")return json(origin,{ok:false,error:"method_not_allowed"},405,ctx,{"allow":"POST, OPTIONS"});
  if(!origins.has(origin))return json(origin,{ok:false,error:"origin_not_allowed"},403,ctx);

  const ct=(req.headers.get("content-type")||"").toLowerCase();
  if(!ct.startsWith("application/json"))return json(origin,{ok:false,error:"unsupported_media_type"},415,ctx);
  const len=Number(req.headers.get("content-length")||0);
  if(len>65536)return json(origin,{ok:false,error:"request_too_large"},413,ctx);
  const raw=await req.text();
  if(raw.length>65536)return json(origin,{ok:false,error:"request_too_large"},413,ctx);

  let body:any;
  try{body=JSON.parse(raw)}catch{return json(origin,{ok:false,error:"invalid_json"},400,ctx)}
  const rpc=String(body?.rpc||"");
  const mapped=RPC_MAP[rpc];
  if(!mapped)return json(origin,{ok:false,error:"rpc_not_allowed"},403,ctx);

  const args=body?.args&&typeof body.args==="object"&&!Array.isArray(body.args)?{...body.args}:{};
  delete args.p_tenant_id;
  args.p_tenant_id=ctx.tenant_id;

  const ip=clientIp(req);
  const ipHash=await sha256(ip);
  const email=String(args.p_email||"").trim().toLowerCase().slice(0,180);
  const token=String(args.p_token||"").trim();

  if(rpc!=="admin_password_login"&&!TOKEN_RE.test(token)){
    await audit(sb,ctx,"auth",rpc,null,ipHash,false,{reason:"invalid_token_format",origin});
    return json(origin,{ok:false,error:"session_required"},401,ctx);
  }
  if(rpc==="admin_password_login"&&(!email||email.length>180||String(args.p_password||"").length>256)){
    return json(origin,{ok:false,error:"invalid_credentials"},401,ctx);
  }

  let bucket="read",limit=240,windowSec=60,lockSec=60;
  let keyMaterial=ctx.tenant_id+"|"+ip+"|"+(token||email||"guest");
  if(rpc==="admin_password_login"){
    bucket="login:"+ctx.tenant_id;limit=6;windowSec=900;lockSec=900;
    keyMaterial=ctx.tenant_id+"|"+ip+"|"+email;
  }else if(SENSITIVE_RPC.has(rpc)){
    bucket="sensitive:"+ctx.tenant_id;limit=20;windowSec=900;lockSec=900;
  }else if(!READ_RPC.has(rpc)){
    bucket="mutation:"+ctx.tenant_id;limit=90;windowSec=60;lockSec=120;
  }

  const keyHash=await sha256(keyMaterial);
  const {data:rl,error:rle}=await sb.rpc("security_consume_rate_limit",{
    p_bucket:bucket,p_key_hash:keyHash,p_limit:limit,p_window_seconds:windowSec,p_lock_seconds:lockSec
  });
  if(rle)return json(origin,{ok:false,error:"rate_limit_unavailable"},503,ctx);
  if(rl?.allowed===false){
    return json(origin,{ok:false,error:"rate_limited",retry_after:rl.retry_after||60},429,ctx,{"retry-after":String(rl.retry_after||60)});
  }

  let session:any=null;
  if(rpc!=="admin_password_login"){
    const s=await sb.rpc("admin_password_session_info_tenant",{p_tenant_id:ctx.tenant_id,p_token:token});
    if(s.error||!s.data?.ok){
      await audit(sb,ctx,"auth",rpc,await sha256(token),ipHash,false,{reason:"invalid_session",origin});
      return json(origin,{ok:false,error:"invalid_session"},401,ctx);
    }
    session=s.data;
    if(SUPERADMIN_RPC.has(rpc)&&session.role!=="superadmin"){
      await audit(sb,ctx,"rpc",rpc,await sha256(token),ipHash,false,{reason:"forbidden_role",role:session.role,origin});
      return json(origin,{ok:false,error:"forbidden"},403,ctx);
    }
    if(rpc==="admin_password_session_info")return json(origin,session,200,ctx);
  }

  const started=Date.now();
  const {data,error}=await sb.rpc(mapped,args);
  const success=!error&&!(data&&typeof data==="object"&&data.ok===false);
  const principalHash=token?await sha256(token):email?await sha256(email):null;
  await audit(
    sb,ctx,rpc==="admin_password_login"?"auth":"rpc",rpc,principalHash,ipHash,success,
    {bucket,duration_ms:Date.now()-started,origin,role:session?.role||null,mapped_rpc:mapped}
  );

  if(rpc==="admin_password_login"&&success){
    try{await sb.from("security_rate_limits").delete().eq("bucket",bucket).eq("key_hash",keyHash)}catch{}
  }
  if(error)return json(origin,{ok:false,error:"request_failed"},400,ctx);
  return json(origin,data,200,ctx);
});
