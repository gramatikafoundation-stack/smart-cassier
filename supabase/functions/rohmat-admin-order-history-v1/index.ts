import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type TenantCtx={tenant_id:string;admin_origin:string;enabled?:boolean};

function headers(origin:string,ctx?:TenantCtx){
  const h=new Headers({
    "content-type":"application/json; charset=utf-8",
    "cache-control":"no-store, max-age=0, must-revalidate",
    "pragma":"no-cache",
    "x-content-type-options":"nosniff",
    "referrer-policy":"no-referrer",
    "vary":"Origin, X-SDB-Tenant-ID",
    "x-rohmat-admin-history":"master-prototype-v1"
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

  let body:any={};
  try{body=await req.json()}catch{}
  const limit=Math.max(1,Math.min(1000,Number(body.limit||500)||500));
  const offset=Math.max(0,Number(body.offset||0)||0);

  try{
    const {data,error}=await sb.rpc("admin_order_history_snapshot_tenant",{
      p_tenant_id:ctx.tenant_id,p_token:token,p_limit:limit,p_offset:offset
    });
    if(error)return json(origin,{ok:false,error:"history_query_failed"},500,ctx);
    if(!data?.ok)return json(origin,data||{ok:false,error:"invalid_session"},data?.error==="invalid_session"?401:400,ctx);
    return json(origin,data,200,ctx);
  }catch{
    return json(origin,{ok:false,error:"history_service_failed"},500,ctx);
  }
});
