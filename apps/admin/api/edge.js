const DEFAULT_RENDERER='https://xrepmvbccalzhlcznrff.supabase.co/functions/v1/rohmat-admin-render?mode=optimized';
const RENDERER=process.env.ADMIN_RENDERER_URL||DEFAULT_RENDERER;
const SUPABASE_ORIGIN=process.env.SUPABASE_ORIGIN||new URL(RENDERER).origin;
const TENANT_ID=String(process.env.SDB_TENANT_ID||'').trim();
const API_KEY=String(process.env.SUPABASE_ANON_KEY||process.env.SUPABASE_PUBLISHABLE_KEY||'').trim();
const MAX_BODY=6*1024*1024;
const UPSTREAM=Object.freeze({
  'order-history':'rohmat-admin-order-history-v1',
  'smart-cashier':'rohmat-smart-cashier-v1',
  'media-upload':'admin-media-upload'
});
function kindOf(req){
  const q=Array.isArray(req?.query?.kind)?req.query.kind[0]:req?.query?.kind;
  return String(q||'');
}
function canonicalOrigin(req){
  const proto=String(req?.headers?.['x-forwarded-proto']||'https').split(',')[0].trim().toLowerCase();
  const host=String(req?.headers?.['x-forwarded-host']||req?.headers?.host||'').split(',')[0].trim().toLowerCase();
  if(proto!=='https'||!/^[a-z0-9.-]+(?::\d{1,5})?$/.test(host))return '';
  return 'https://'+host;
}
function copyHeader(req,name){return String(req?.headers?.[name]||req?.headers?.[name.toLowerCase()]||'').slice(0,2048)}
export default async function handler(req,res){
  if(req.method!=='POST'&&req.method!=='OPTIONS'){
    res.statusCode=405;res.setHeader('Allow','POST, OPTIONS');return res.end();
  }
  const kind=kindOf(req),slug=UPSTREAM[kind];
  if(!slug){res.statusCode=404;return res.end('not_found')}
  if(!TENANT_ID||!SUPABASE_ORIGIN||!API_KEY){res.statusCode=503;res.setHeader('Cache-Control','no-store');return res.end('admin_proxy_configuration_unavailable')}
  if(req.method==='OPTIONS'){res.statusCode=204;res.setHeader('Allow','POST, OPTIONS');return res.end()}
  const raw=typeof req.body==='string'?req.body:Buffer.isBuffer(req.body)?req.body.toString('utf8'):JSON.stringify(req.body??{});
  if(Buffer.byteLength(raw)>MAX_BODY){res.statusCode=413;res.setHeader('Cache-Control','no-store');return res.end(JSON.stringify({ok:false,error:'request_too_large'}))}
  const origin=canonicalOrigin(req);
  if(!origin){res.statusCode=400;res.setHeader('Cache-Control','no-store');return res.end(JSON.stringify({ok:false,error:'invalid_origin'}))}
  const headers={
    'Content-Type':copyHeader(req,'content-type')||'application/json',
    Accept:'application/json',
    apikey:API_KEY,
    Authorization:'Bearer '+API_KEY,
    Origin:origin,
    'X-SDB-Tenant-ID':TENANT_ID
  };
  for(const name of ['x-admin-session','x-kds-session','x-request-id','user-agent','accept-language','sec-ch-ua-platform','x-forwarded-for','x-real-ip']){
    const value=copyHeader(req,name);if(value)headers[name]=value;
  }
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),12000);
  try{
    const upstream=await fetch(SUPABASE_ORIGIN+'/functions/v1/'+slug,{method:'POST',cache:'no-store',signal:controller.signal,headers,body:raw});
    const body=await upstream.text();
    res.statusCode=upstream.status;
    res.setHeader('Content-Type',upstream.headers.get('content-type')||'application/json; charset=utf-8');
    res.setHeader('Cache-Control','no-store, max-age=0, must-revalidate');
    res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('X-Robots-Tag','noindex, nofollow, noarchive');
    res.setHeader('X-Rohmat-Admin-Proxy','same-origin-v60');
    const requestId=upstream.headers.get('x-request-id');if(requestId)res.setHeader('X-Request-ID',requestId);
    return res.end(body);
  }catch(error){
    res.statusCode=502;
    res.setHeader('Content-Type','application/json; charset=utf-8');
    res.setHeader('Cache-Control','no-store');
    return res.end(JSON.stringify({ok:false,error:'admin_upstream_unavailable'}));
  }finally{clearTimeout(timer)}
}
