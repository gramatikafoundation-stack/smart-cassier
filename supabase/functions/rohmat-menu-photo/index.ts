import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const U=Deno.env.get('SUPABASE_URL')||'';
const IDS=new Set(['nasi-uduk','nasi-putih','bebek-super','ayam-goreng','ampela-ati','usus-ayam','kepala-bebek','kepala-ayam','bandeng-presto','telor-dadar','pete','terong','tahu','tempe','babat-sapi','paru-sapi','limpa-sapi','empal-sapi','teh-hangat','es-teh','jeruk-hangat','es-jeruk','kopi','aqua','jus-alpukat','jus-jambu','jus-melon','jus-sirsat','jus-belimbing','jus-buah-naga','jus-mangga','jus-apel','jus-stroberi','jus-wortel','jus-tomat','jus-mix']);
const H={'access-control-allow-origin':'*','cross-origin-resource-policy':'cross-origin','x-content-type-options':'nosniff','cache-control':'public, max-age=31536000, s-maxage=31536000, immutable','x-rohmat-image':'hd-static-v11-locked'};

Deno.serve(async(req:Request)=>{
  if(req.method!=='GET'&&req.method!=='HEAD')return new Response('Method Not Allowed',{status:405,headers:{...H,'allow':'GET, HEAD'}});
  const k=new URL(req.url).searchParams.get('k')||'nasi-uduk';
  if(!IDS.has(k))return new Response('Not Found',{status:404,headers:H});
  try{
    const src=`${U}/storage/v1/object/public/rohmat-assets/menu-hd-v1/${k}.jpg`;
    const r=await fetch(src,{redirect:'follow',signal:AbortSignal.timeout(9000)});
    if(!r.ok)throw new Error('source_'+r.status);
    const ct=(r.headers.get('content-type')||'image/jpeg').split(';')[0];
    if(req.method==='HEAD')return new Response(null,{status:200,headers:{...H,'content-type':ct,'content-length':r.headers.get('content-length')||'','x-rohmat-menu-key':k,'x-rohmat-source':'hd-static'}});
    return new Response(await r.arrayBuffer(),{status:200,headers:{...H,'content-type':ct,'x-rohmat-menu-key':k,'x-rohmat-source':'hd-static'}});
  }catch(e){return new Response('Image unavailable',{status:502,headers:{...H,'x-rohmat-error':String((e as Error)?.message||e).slice(0,80)}})}
});
