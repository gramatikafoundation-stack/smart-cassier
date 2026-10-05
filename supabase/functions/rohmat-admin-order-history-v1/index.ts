import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const enc=new TextEncoder();
type TenantCtx={tenant_id:string;admin_origin:string;enabled?:boolean};

async function sha256(v:string){
  const b=await crypto.subtle.digest("SHA-256",enc.encode(v));
  return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,"0")).join("");
}
function ua(req:Request){return(req.headers.get("user-agent")||"unknown").slice(0,240)}
async function fingerprint(req:Request){
  const lang=(req.headers.get("accept-language")||"unknown").slice(0,120);
  const platform=(req.headers.get("sec-ch-ua-platform")||"unknown").slice(0,80);
  return sha256(ua(req)+"|"+lang+"|"+platform);
}
function headers(origin:string,ctx?:TenantCtx){
  const h=new Headers({
    "content-type":"application/json; charset=utf-8",
    "cache-control":"no-store, max-age=0, must-revalidate",
    "pragma":"no-cache",
    "x-content-type-options":"nosniff",
    "referrer-policy":"no-referrer",
    "vary":"Origin, X-SDB-Tenant-ID",
    "x-rohmat-admin-history":"smart-order-b2"
  });
  if(ctx){
    h.set("x-sdb-tenant-id",ctx.tenant_id);
    if(origin===ctx.admin_origin)h.set("access-control-allow-origin",origin);
  }
  return h;
}
function json(origin:string,body:any,status=200,ctx?:TenantCtx){
  return new Response(JSON.stringify(body),{status,headers:headers(origin,ctx)});
}
async function tenantContext(sb:any,req:Request):Promise<TenantCtx|null>{
  const tenantId=String(req.headers.get("x-sdb-tenant-id")||"").trim();
  if(!UUID_RE.test(tenantId))return null;
  const r=await sb.rpc("master_prototype_tenant_context",{p_tenant_id:tenantId});
  if(r.error||!r.data?.ok||r.data?.enabled===false)return null;
  return r.data as TenantCtx;
}

Deno.serve(async(req:Request)=>{
  const origin=req.headers.get("origin")||"";
  const su=Deno.env.get("SUPABASE_URL")||"";
  const sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(!su||!sk)return json(origin,{ok:false,error:"service_unavailable"},503);

  const sb=createClient(su,sk,{auth:{persistSession:false,autoRefreshToken:false}});
  const ctx=await tenantContext(sb,req);
  if(!ctx)return json(origin,{ok:false,error:"tenant_required_or_invalid"},400);

  if(req.method==="OPTIONS"){
    if(origin!==ctx.admin_origin)return json(origin,{ok:false,error:"origin_not_allowed"},403,ctx);
    const h=headers(origin,ctx);
    h.set("access-control-allow-headers","content-type,x-admin-session,cache-control,pragma,x-sdb-tenant-id");
    h.set("access-control-allow-methods","POST,OPTIONS");
    h.set("access-control-max-age","600");
    return new Response(null,{status:204,headers:h});
  }
  if(req.method!=="POST")return json(origin,{ok:false,error:"method_not_allowed"},405,ctx);
  if(origin!==ctx.admin_origin)return json(origin,{ok:false,error:"origin_not_allowed"},403,ctx);

  const token=String(req.headers.get("x-admin-session")||"").trim();
  if(!/^[a-f0-9]{64}$/i.test(token))return json(origin,{ok:false,error:"missing_session"},401,ctx);
  const fp=await fingerprint(req);
  const session=await sb.rpc("admin_password_session_info_bound_tenant",{
    p_tenant_id:ctx.tenant_id,p_token:token,p_fingerprint_hash:fp
  });
  if(session.error||!session.data?.ok||session.data?.session_scope!=="admin"){
    return json(origin,{ok:false,error:"invalid_session"},401,ctx);
  }

  let body:any={};
  try{body=await req.json()}catch{}
  const action=String(body.action||"snapshot");
  const limit=Math.max(1,Math.min(1000,Number(body.limit||500)||500));
  const offset=Math.max(0,Number(body.offset||0)||0);

  try{
    if(action==="realtime"){
      const {data,error}=await sb.rpc("kds_realtime_ticket_tenant",{p_tenant_id:ctx.tenant_id,p_token:token});
      if(error||!data?.ok||!String(data?.topic||"").startsWith("kds:")){
        return json(origin,{ok:false,error:"realtime_unavailable"},503,ctx);
      }
      return json(origin,{ok:true,tenant_id:ctx.tenant_id,realtime:{
        topic:String(data.topic),event:String(data.event||"kds_change"),
        safety_poll_seconds:45,stale_after_seconds:75
      }},200,ctx);
    }
    if(action!=="snapshot")return json(origin,{ok:false,error:"invalid_action"},400,ctx);
    const {data,error}=await sb.rpc("admin_order_history_snapshot_tenant",{
      p_tenant_id:ctx.tenant_id,p_token:token,p_limit:limit,p_offset:offset
    });
    if(error)return json(origin,{ok:false,error:"history_query_failed"},500,ctx);
    if(!data?.ok)return json(origin,data||{ok:false,error:"invalid_session"},data?.error==="invalid_session"?401:400,ctx);
    return json(origin,data,200,ctx);
  }catch{
    return json(origin,{ok:false,error:action==="realtime"?"realtime_service_failed":"history_service_failed"},500,ctx);
  }
});
