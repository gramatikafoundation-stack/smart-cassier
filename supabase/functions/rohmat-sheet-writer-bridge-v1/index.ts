import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
const BRIDGE_TOKEN_SHA256="0481f7beb5eef34dea5f8c23da7894eb614c0dadd6815a3d4c0e72154e1730fc";
const CANONICAL_TENANT="d8bb901c-7399-485b-8743-b319fde148ac";
const LEGACY_TENANT="ad126431-b148-471d-ba62-a7b3a5d0a8c1";
const APPS_SCRIPT="https://script.google.com/macros/s/AKfycbwJgyD676R8PcLnETjhPKGHwm56e0k5EkqMz23OPNWhxMf-MOrUwEDR0waxKbYcjizz/exec";
const enc=new TextEncoder();
async function hash(v:string){const b=await crypto.subtle.digest("SHA-256",enc.encode(v));return[...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,"0")).join("")}
const json=(v:any,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{"content-type":"application/json; charset=utf-8","cache-control":"no-store","x-content-type-options":"nosniff"}});
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return json({ok:false,error:"method_not_allowed"},405);
 const U=Deno.env.get("SUPABASE_URL")||"",K=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
 if(!U||!K)return json({ok:false,error:"service_unavailable"},503);
 let body:any={};try{body=await req.json()}catch{return json({ok:false,error:"invalid_request"},400)}
 if(String(body.tenant_id||"")!==CANONICAL_TENANT)return json({ok:false,error:"tenant_mismatch"},403);
 const bridgeToken=String(body.writer_token||"");
 if(!bridgeToken||await hash(bridgeToken)!==BRIDGE_TOKEN_SHA256)return json({ok:false,error:"unauthorized"},401);
 const sb=createClient(U,K,{auth:{persistSession:false,autoRefreshToken:false}});
 const secret=await sb.rpc("sheet_sync_writer_credential_tenant",{p_tenant_id:LEGACY_TENANT});
 if(secret.error||typeof secret.data!=="string"||secret.data.length<32)return json({ok:false,error:"legacy_writer_auth_unavailable"},503);
 const incoming=Array.isArray(body.events)?body.events:[];
 if(!incoming.length)return json({ok:false,error:"invalid_request"},400);
 const years=[...new Set(incoming.map((e:any)=>e.target_year).filter((y:any)=>y!==null&&y!==undefined).map(Number))];
 const reconcile=(years.length?years:[null]).map((year:any)=>({event_id:crypto.randomUUID(),target_year:year,entity_type:"reconcile",entity_id:"canonical-full",operation:"RECONCILE"}));
 const upstream=await fetch(APPS_SCRIPT,{method:"POST",redirect:"follow",signal:AbortSignal.timeout(90000),headers:{"content-type":"application/json"},body:JSON.stringify({schema_version:1,tenant_id:LEGACY_TENANT,writer_token:secret.data,sent_at:new Date().toISOString(),force_full:true,events:reconcile})});
 const ack=await upstream.json().catch(()=>null);
 if(!upstream.ok||!ack?.ok)return json(ack||{ok:false,error:"writer_http_error"},upstream.status||502);
 ack.tenant_id=CANONICAL_TENANT;
 return json(ack,200);
});