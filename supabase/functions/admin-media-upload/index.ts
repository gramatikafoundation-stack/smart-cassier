import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const MAX_BYTES=5*1024*1024;
const MAX_BODY=7_200_000;
const TOKEN_RE=/^[a-f0-9]{64}$/i;
const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const enc=new TextEncoder();

type TenantContext={
  tenant_id:string;
  tenant_slug:string;
  admin_origin:string;
  storage_static_bucket?:string|null;
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
function headers(origin:string|null,ctx?:TenantContext){
  const h=new Headers({
    "Content-Type":"application/json; charset=utf-8",
    "Cache-Control":"no-store, max-age=0, must-revalidate",
    "Pragma":"no-cache",
    "Vary":"Origin, X-SDB-Tenant-ID",
    "X-Content-Type-Options":"nosniff",
    "X-Frame-Options":"DENY",
    "Referrer-Policy":"no-referrer",
    "Permissions-Policy":"camera=(), microphone=(), geolocation=()",
    "Cross-Origin-Resource-Policy":"cross-origin",
    "X-Rohmat-Security":"media-upload-master-prototype-v1"
  });
  if(ctx){
    h.set("X-SDB-Tenant-ID",ctx.tenant_id);
    if(origin===ctx.admin_origin)h.set("Access-Control-Allow-Origin",origin);
  }
  return h;
}
function out(origin:string|null,status:number,body:Record<string,unknown>,ctx?:TenantContext){
  return new Response(JSON.stringify(body),{status,headers:headers(origin,ctx)});
}
function signatureOk(bytes:Uint8Array,mime:string){
  if(mime==="image/jpeg")return bytes.length>=3&&bytes[0]===0xff&&bytes[1]===0xd8&&bytes[2]===0xff;
  if(mime==="image/png")return bytes.length>=8&&[0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a].every((v,i)=>bytes[i]===v);
  if(mime==="image/webp")return bytes.length>=12&&String.fromCharCode(...bytes.slice(0,4))==="RIFF"&&String.fromCharCode(...bytes.slice(8,12))==="WEBP";
  return false;
}
function decode(value:unknown){
  const raw=String(value||"");
  const match=raw.match(/^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/);
  if(!match)throw new Error("invalid_type");
  const decoded=atob(match[2]);
  if(!decoded.length||decoded.length>MAX_BYTES)throw new Error("invalid_size");
  const bytes=new Uint8Array(decoded.length);
  for(let i=0;i<decoded.length;i++)bytes[i]=decoded.charCodeAt(i);
  if(!signatureOk(bytes,match[1]))throw new Error("invalid_signature");
  const ext=match[1]==="image/jpeg"?"jpg":match[1].split("/")[1];
  return{bytes,mime:match[1],ext};
}
function safeKind(value:unknown){
  const kind=String(value||"menu").toLowerCase();
  return["menu","hero","qris"].includes(kind)?kind:"menu";
}
async function resolveTenant(sb:any,req:Request):Promise<TenantContext|null>{
  const raw=String(req.headers.get("x-sdb-tenant-id")||"").trim();
  const tenantId=UUID_RE.test(raw)?raw:null;
  const requestOrigin=String(req.headers.get("origin")||"").trim()||null;
  const r=await sb.rpc("master_prototype_runtime_context",{
    p_tenant_id:tenantId,
    p_origin:tenantId?null:requestOrigin,
    p_app_kind:"admin"
  });
  if(r.error||!r.data?.ok||r.data?.enabled===false)return null;
  return r.data as TenantContext;
}
async function audit(sb:any,ctx:TenantContext,token:string,req:Request,success:boolean,metadata:any){
  try{
    await sb.from("security_audit_events").insert({
      event_type:"media",
      action:"admin_media_upload",
      principal_hash:await sha256(token),
      ip_hash:await sha256(ip(req)),
      success,
      metadata:{...metadata,tenant_id:ctx.tenant_id,tenant_slug:ctx.tenant_slug}
    });
  }catch{}
}

Deno.serve(async(req:Request)=>{
  const origin=req.headers.get("origin");
  const url=Deno.env.get("SUPABASE_URL")||"";
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(!url||!service)return out(origin,503,{ok:false,error:"service_unavailable"});

  const sb=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const ctx=await resolveTenant(sb,req);
  if(!ctx)return out(origin,400,{ok:false,error:"tenant_required_or_invalid"});

  if(req.method==="OPTIONS"){
    if(!origin||origin!==ctx.admin_origin)return out(origin,403,{ok:false,error:"origin_not_allowed"},ctx);
    const h=headers(origin,ctx);
    h.set("Access-Control-Allow-Headers","content-type,x-admin-session,apikey,authorization,x-sdb-tenant-id");
    h.set("Access-Control-Allow-Methods","POST,OPTIONS");
    h.set("Access-Control-Max-Age","600");
    return new Response(null,{status:204,headers:h});
  }
  if(req.method!=="POST")return out(origin,405,{ok:false,error:"method_not_allowed"},ctx);
  if(!origin||origin!==ctx.admin_origin)return out(origin,403,{ok:false,error:"origin_not_allowed"},ctx);

  const ct=(req.headers.get("content-type")||"").toLowerCase();
  if(!ct.startsWith("application/json"))return out(origin,415,{ok:false,error:"unsupported_media_type"},ctx);
  const len=Number(req.headers.get("content-length")||0);
  if(len>MAX_BODY)return out(origin,413,{ok:false,error:"request_too_large"},ctx);

  const token=(req.headers.get("x-admin-session")||"").trim();
  if(!TOKEN_RE.test(token))return out(origin,401,{ok:false,error:"invalid_session"},ctx);

  const rlKey=await sha256(ctx.tenant_id+"|"+ip(req)+"|"+token);
  const rl=await sb.rpc("security_consume_rate_limit",{
    p_bucket:"admin-media-upload:"+ctx.tenant_id,
    p_key_hash:rlKey,p_limit:30,p_window_seconds:600,p_lock_seconds:600
  });
  if(rl.error)return out(origin,503,{ok:false,error:"rate_limit_unavailable"},ctx);
  if(rl.data?.allowed===false)return out(origin,429,{ok:false,error:"rate_limited",retry_after:rl.data.retry_after||600},ctx);

  const session=await sb.rpc("admin_password_session_info_tenant",{p_tenant_id:ctx.tenant_id,p_token:token});
  if(session.error||!session.data?.ok){
    await audit(sb,ctx,token,req,false,{reason:"invalid_session",origin});
    return out(origin,401,{ok:false,error:"invalid_session"},ctx);
  }

  try{
    const raw=await req.text();
    if(raw.length>MAX_BODY)return out(origin,413,{ok:false,error:"request_too_large"},ctx);
    let body:any;
    try{body=JSON.parse(raw)}catch{return out(origin,400,{ok:false,error:"invalid_json"},ctx)}
    const kind=safeKind(body?.kind);
    const file=decode(body?.dataUrl);
    const bucket=String(ctx.storage_static_bucket||"merchant-static");
    const path=`tenants/${ctx.tenant_slug}/${kind}/${new Date().toISOString().slice(0,10)}/${crypto.randomUUID()}.${file.ext}`;
    const uploaded=await sb.storage.from(bucket).upload(path,file.bytes,{
      contentType:file.mime,cacheControl:"31536000",upsert:false
    });
    if(uploaded.error)throw new Error("storage_failed");
    const pub=sb.storage.from(bucket).getPublicUrl(path);
    await audit(sb,ctx,token,req,true,{origin,kind,bytes:file.bytes.length,role:session.data.role,bucket});
    return out(origin,201,{ok:true,path,url:pub.data.publicUrl,tenant_id:ctx.tenant_id},ctx);
  }catch(e){
    const code=e instanceof Error?e.message:"upload_failed";
    const safe=code==="invalid_type"?"File harus JPG, PNG, atau WebP.":
      code==="invalid_size"?"Ukuran gambar maksimal 5 MB.":
      code==="invalid_signature"?"Isi file gambar tidak valid.":"Upload gagal.";
    await audit(sb,ctx,token,req,false,{origin,reason:code});
    return out(origin,400,{ok:false,error:safe},ctx);
  }
});
