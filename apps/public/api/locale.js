import { resolvePublicTenantConfig } from '../lib/tenant-config.js';

export default async function handler(req,res){
  if(req.method!=='GET'){res.statusCode=405;res.setHeader('Allow','GET');return res.end('method_not_allowed')}
  const cfg=await resolvePublicTenantConfig(req);
  if(!cfg?.ok||!cfg.tenantId){res.statusCode=503;res.setHeader('Cache-Control','no-store');return res.end('id-ID')}
  const sb=String(process.env.SUPABASE_URL||'').replace(/\/$/,'');
  const key=String(process.env.SUPABASE_PUBLISHABLE_KEY||process.env.SUPABASE_ANON_KEY||'');
  let locale=String(cfg.locale||'id-ID');
  if(sb&&key){
    try{
      const u=sb+'/rest/v1/tenant_site_settings_public_v1?select=language_settings&tenant_id=eq.'+encodeURIComponent(cfg.tenantId)+'&limit=1';
      const r=await fetch(u,{cache:'no-store',headers:{apikey:key,Authorization:'Bearer '+key,'X-SDB-Tenant-ID':cfg.tenantId}});
      if(r.ok){
        const rows=await r.json();
        const saved=String(rows?.[0]?.language_settings?.default||'').trim();
        if(saved)locale=saved;
      }
    }catch{}
  }
  res.statusCode=200;
  res.setHeader('Content-Type','text/plain; charset=utf-8');
  res.setHeader('Cache-Control','no-store, max-age=0, must-revalidate');
  res.setHeader('X-Content-Type-Options','nosniff');
  res.setHeader('X-SDB-Tenant-ID',String(cfg.tenantId));
  res.end(locale||'id-ID');
}
