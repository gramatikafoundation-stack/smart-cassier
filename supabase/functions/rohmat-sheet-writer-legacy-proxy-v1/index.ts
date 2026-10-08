import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
const LEGACY_TENANT="ad126431-b148-471d-ba62-a7b3a5d0a8c1";
const CANONICAL_TENANT="d8bb901c-7399-485b-8743-b319fde148ac";
const FEED="https://xrepmvbccalzhlcznrff.supabase.co/functions/v1/rohmat-sheet-writer-data-v1";
const enc=new TextEncoder();
async function hash(v:string){const b=await crypto.subtle.digest("SHA-256",enc.encode(v));return[...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,"0")).join("")}
const json=(v:any,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{"content-type":"application/json; charset=utf-8","cache-control":"no-store","x-content-type-options":"nosniff"}});
Deno.serve(async(req:Request)=>{
 if(req.method!=="GET"&&req.method!=="HEAD")return json({ok:false,error:"method_not_allowed"},405);
 const U=Deno.env.get("SUPABASE_URL")||"",K=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
 if(!U||!K)return json({ok:false,error:"service_unavailable"},503);
 const u=new URL(req.url),tenant=String(req.headers.get("x-sdb-tenant-id")||u.searchParams.get("tenant")||"");
 if(tenant!==LEGACY_TENANT)return json({ok:false,error:"tenant_mismatch"},403);
 const writerToken=String(req.headers.get("x-rohmat-writer-token")||"");
 const sb=createClient(U,K,{auth:{persistSession:false,autoRefreshToken:false}});
 const secret=await sb.rpc("sheet_sync_writer_credential_tenant",{p_tenant_id:LEGACY_TENANT});
 if(secret.error||typeof secret.data!=="string"||secret.data.length<32)return json({ok:false,error:"writer_auth_unavailable"},503);
 if(!writerToken||(await hash(writerToken))!==(await hash(secret.data)))return json({ok:false,error:"unauthorized"},401);
 const q=new URL(FEED);for(const [k,v] of u.searchParams.entries()){if(k!=="tenant")q.searchParams.set(k,v)}q.searchParams.set("year",String(u.searchParams.get("year")||""));
 const res=await fetch(q,{method:req.method,headers:{"x-sdb-tenant-id":CANONICAL_TENANT,"x-rohmat-writer-token":writerToken},signal:AbortSignal.timeout(30000)});
 if(req.method==="HEAD")return new Response(null,{status:res.status,headers:{"cache-control":"no-store","x-sdb-tenant-id":LEGACY_TENANT}});
 const payload=await res.json().catch(()=>null);
 if(!res.ok||!payload)return json(payload||{ok:false,error:"canonical_feed_failed"},res.status||502);
 payload.tenant_id=LEGACY_TENANT;
 return json(payload,200);
});