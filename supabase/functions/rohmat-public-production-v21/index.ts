import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const BUCKET = Deno.env.get('PUBLIC_STATIC_BUCKET') || 'merchant-static';
const PATH = Deno.env.get('PUBLIC_LKG_PATH') || 'public-lkg-v1.html';
const U = Deno.env.get('SUPABASE_URL') || '';

const CSP = [
  "default-src 'self'",
  "base-uri 'self'",
  "object-src 'none'",
  "frame-ancestors 'none'",
  "form-action 'self'",
  "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://*.supabase.co",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https:",
  "font-src 'self' data: https:",
  "connect-src 'self' https://*.supabase.co wss://*.supabase.co https://cdn.jsdelivr.net",
  "worker-src 'self' blob: https://cdn.jsdelivr.net",
  "media-src 'self' blob: https:"
].join('; ');

function headers(extra: Record<string,string> = {}) {
  return {
    'content-type':'text/html; charset=utf-8',
    'cache-control':'public, max-age=60, s-maxage=300, stale-while-revalidate=86400',
    'x-rohmat-public':'v51-lkg-primary',
    'x-rohmat-render':'lkg-primary-delivery',
    'x-content-type-options':'nosniff',
    'referrer-policy':'strict-origin-when-cross-origin',
    'permissions-policy':'camera=(), microphone=(), geolocation=(), payment=()',
    'x-frame-options':'DENY',
    'content-security-policy':CSP,
    ...extra
  };
}

async function loadLkg(){
  const r = await fetch(`${U}/storage/v1/object/public/${BUCKET}/${PATH}`, {cache:'no-store'});
  if(!r.ok) throw new Error(`lkg_http_${r.status}`);
  const html = await r.text();
  if(html.length < 70000 || !html.includes('rohmat-public-element-runtime-v64') || !html.includes('rohmat-cart-qris-runtime-v72')) throw new Error('lkg_validation_failed');
  return html;
}

Deno.serve(async (req: Request) => {
  if(req.method !== 'GET' && req.method !== 'HEAD') return new Response('Method Not Allowed',{status:405});
  try{
    const html = await loadLkg();
    return new Response(req.method === 'HEAD' ? null : html, {status:200, headers:headers()});
  }catch(e){
    return new Response('Public LKG unavailable: '+String((e as Error)?.message||e), {status:503,headers:{'content-type':'text/plain; charset=utf-8','cache-control':'no-store','x-rohmat-public':'v51-lkg-primary','x-rohmat-render':'lkg-error','x-content-type-options':'nosniff','referrer-policy':'no-referrer','x-frame-options':'DENY'}});
  }
});