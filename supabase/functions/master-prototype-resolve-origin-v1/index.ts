import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const MAX_BODY=4096;
function headers(){
  return {
    "content-type":"application/json; charset=utf-8",
    "cache-control":"public, max-age=30, s-maxage=30, stale-while-revalidate=60",
    "x-content-type-options":"nosniff",
    "referrer-policy":"no-referrer",
    "x-frame-options":"DENY",
    "permissions-policy":"camera=(), microphone=(), geolocation=(), payment=(), usb=()",
    "x-sdb-contract":"tenant-origin-resolver-v1"
  };
}
function json(body:unknown,status=200){
  return new Response(JSON.stringify(body),{status,headers:headers()});
}
Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return json({ok:false,error:"method_not_allowed"},405);
  const ct=(req.headers.get("content-type")||"").toLowerCase();
  if(!ct.startsWith("application/json"))return json({ok:false,error:"unsupported_media_type"},415);
  if(Number(req.headers.get("content-length")||0)>MAX_BODY)return json({ok:false,error:"request_too_large"},413);
  const raw=await req.text();
  if(raw.length>MAX_BODY)return json({ok:false,error:"request_too_large"},413);
  let body:any;
  try{body=JSON.parse(raw)}catch{return json({ok:false,error:"invalid_json"},400)}
  const origin=String(body?.origin||"").trim();
  const appKind=String(body?.app_kind||"").trim();
  if(!origin||!["public","admin","kds"].includes(appKind))return json({ok:false,error:"invalid_request"},400);

  const U=Deno.env.get("SUPABASE_URL")||"";
  const K=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(!U||!K)return json({ok:false,error:"service_unavailable"},503);
  const sb=createClient(U,K,{auth:{persistSession:false,autoRefreshToken:false}});
  const r=await sb.rpc("master_prototype_resolve_origin",{p_origin:origin,p_app_kind:appKind});
  if(r.error)return json({ok:false,error:"resolver_unavailable"},503);
  if(!r.data?.ok)return json(r.data||{ok:false,error:"tenant_not_resolved"},404);
  return json(r.data,200);
});
