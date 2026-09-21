import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async(req:Request)=>{
  if(req.method!=="GET"&&req.method!=="HEAD")return new Response("Method Not Allowed",{status:405});
  const url=Deno.env.get("SUPABASE_URL")||"";
  const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(!url||!key)return new Response("Layanan QRIS belum siap.",{status:503});

  const sb=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const u=new URL(req.url);
  const tenantId=String(req.headers.get("x-sdb-tenant-id")||u.searchParams.get("tenant")||"").trim();
  if(!UUID_RE.test(tenantId))return new Response("Tenant tidak valid.",{status:400,headers:{"cache-control":"no-store"}});

  const ctx=await sb.rpc("master_prototype_tenant_context",{p_tenant_id:tenantId});
  if(ctx.error||!ctx.data?.ok||ctx.data?.enabled===false)return new Response("Tenant tidak tersedia.",{status:404,headers:{"cache-control":"no-store"}});
  const origin=req.headers.get("origin")||"";
  const cors=origin===ctx.data.public_origin?origin:"";

  const {data,error}=await sb.from("tenant_site_settings_public_v1")
    .select("business_name,merchant_name,qris_enabled,qris_image_url")
    .eq("tenant_id",tenantId).maybeSingle();
  if(error||!data?.qris_enabled||!data?.qris_image_url){
    return new Response("QRIS resmi belum tersedia.",{
      status:404,
      headers:{"content-type":"text/plain; charset=utf-8","cache-control":"no-store","x-sdb-tenant-id":tenantId,...(cors?{"access-control-allow-origin":cors}:{})}
    });
  }
  try{
    const r=await fetch(data.qris_image_url,{cache:"no-store"});
    if(!r.ok)throw new Error("image_fetch_failed");
    const blob=await r.blob();
    const type=blob.type||"image/png";
    const ext=type.includes("webp")?"webp":type.includes("jpeg")||type.includes("jpg")?"jpg":"png";
    const name=String(data.merchant_name||data.business_name||"Merchant")
      .replace(/[^a-zA-Z0-9_-]+/g,"-").replace(/^-+|-+$/g,"")||"QRIS";
    return new Response(req.method==="HEAD"?null:blob,{
      status:200,
      headers:{
        "content-type":type,
        "content-disposition":`attachment; filename="QRIS-${name}.${ext}"`,
        "cache-control":"no-store",
        "vary":"Origin, X-SDB-Tenant-ID",
        "x-sdb-tenant-id":tenantId,
        ...(cors?{"access-control-allow-origin":cors}:{})
      }
    });
  }catch{
    return new Response("Gambar QRIS tidak dapat diunduh.",{
      status:502,
      headers:{"content-type":"text/plain; charset=utf-8","cache-control":"no-store","x-sdb-tenant-id":tenantId}
    });
  }
});
