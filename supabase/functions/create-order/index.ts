import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const SUPABASE_URL=Deno.env.get("SUPABASE_URL")||"";
const TARGET=Deno.env.get("ORDER_CORE_URL")||(SUPABASE_URL?SUPABASE_URL.replace(/\/$/,"")+"/functions/v1/create-order-v6":"");
const MAX=4_900_000;
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type TenantCtx={tenant_id:string;public_origin:string;enabled?:boolean};

function h(o:string|null,requestId:string,ctx?:TenantCtx){
  return{
    "Access-Control-Allow-Origin":o&&ctx&&o===ctx.public_origin?o:"",
    "Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info, x-request-id, x-sdb-tenant-id",
    "Access-Control-Allow-Methods":"POST, OPTIONS",
    "Access-Control-Expose-Headers":"X-Request-ID, X-Rohmat-Contract, X-SDB-Tenant-ID",
    "Content-Type":"application/json; charset=utf-8",
    "Cache-Control":"no-store, max-age=0",
    "X-Content-Type-Options":"nosniff",
    "Referrer-Policy":"no-referrer",
    "Vary":"Origin, X-SDB-Tenant-ID",
    "X-Request-ID":requestId,
    "X-Rohmat-Contract":"order-gateway-master-prototype-v1",
    "X-SDB-Tenant-ID":ctx?.tenant_id||""
  };
}
function out(o:string|null,status:number,error:string,requestId:string,ctx?:TenantCtx){
  return new Response(JSON.stringify({error,requestId}),{status,headers:h(o,requestId,ctx)});
}
function validImageSignature(value:unknown){
  const m=String(value||"").match(/^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/);
  if(!m)return false;
  let raw="";try{raw=atob(m[2])}catch{return false}
  if(!raw.length||raw.length>3*1024*1024)return false;
  const b=(i:number)=>raw.charCodeAt(i)||0;
  if(m[1]==="image/jpeg")return raw.length>=3&&b(0)===0xff&&b(1)===0xd8&&b(2)===0xff;
  if(m[1]==="image/png")return raw.length>=8&&[0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a].every((x,i)=>b(i)===x);
  if(m[1]==="image/webp")return raw.length>=12&&raw.slice(0,4)==="RIFF"&&raw.slice(8,12)==="WEBP";
  return false;
}
async function resolveTenant(req:Request){
  const tenantId=String(req.headers.get("x-sdb-tenant-id")||"").trim();
  if(!UUID.test(tenantId))return null;
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(!SUPABASE_URL||!service)return null;
  const sb=createClient(SUPABASE_URL,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const r=await sb.rpc("master_prototype_tenant_context",{p_tenant_id:tenantId});
  if(r.error||!r.data?.ok||r.data?.enabled===false)return null;
  return r.data as TenantCtx;
}

Deno.serve(async(req:Request)=>{
  const o=req.headers.get("origin");
  const incoming=req.headers.get("x-request-id")||"";
  const requestId=UUID.test(incoming)?incoming:crypto.randomUUID();
  if(!TARGET||!SUPABASE_URL)return out(o,503,"Konfigurasi platform belum lengkap.",requestId);

  const ctx=await resolveTenant(req);
  if(!ctx)return out(o,400,"Tenant wajib dan harus valid.",requestId);

  if(req.method==="OPTIONS"){
    return new Response(null,{status:o&&o===ctx.public_origin?204:403,headers:h(o,requestId,ctx)});
  }
  if(req.method!=="POST")return out(o,405,"Metode tidak diizinkan.",requestId,ctx);
  if(!o||o!==ctx.public_origin)return out(o,403,"Asal permintaan tidak diizinkan.",requestId,ctx);
  if(Number(req.headers.get("content-length")||0)>MAX)return out(o,413,"Ukuran permintaan terlalu besar.",requestId,ctx);

  const body=await req.text();
  if(body.length>MAX)return out(o,413,"Ukuran permintaan terlalu besar.",requestId,ctx);
  let payload:any;
  try{payload=JSON.parse(body)}catch{return out(o,400,"Format permintaan tidak valid.",requestId,ctx)}
  if(!validImageSignature(payload?.paymentProof)){
    return out(o,400,"Bukti pembayaran tidak valid. File harus benar-benar berupa JPG, PNG, atau WebP yang sesuai dengan tipe filenya.",requestId,ctx);
  }

  try{
    const r=await fetch(TARGET,{
      method:"POST",
      headers:{
        Origin:o,
        apikey:req.headers.get("apikey")||"",
        Authorization:req.headers.get("authorization")||"",
        "Content-Type":"application/json",
        "X-Request-ID":requestId,
        "X-SDB-Tenant-ID":ctx.tenant_id
      },
      body,cache:"no-store"
    });
    const text=await r.text();
    const downstream=r.headers.get("x-request-id")||requestId;
    const finalId=UUID.test(downstream)?downstream:requestId;
    return new Response(text,{status:r.status,headers:h(o,finalId,ctx)});
  }catch{
    return out(o,503,"Layanan pesanan belum dapat dihubungi.",requestId,ctx);
  }
});
