import { resolvePublicTenantConfig } from '../lib/tenant-config.js';

export default async function handler(req,res){
  if(req.method!=='GET'){res.statusCode=405;res.setHeader('Allow','GET');return res.end('method_not_allowed')}
  const cfg=await resolvePublicTenantConfig(req);
  if(!cfg?.ok){res.statusCode=503;res.setHeader('Cache-Control','no-store');return res.end('id-ID')}
  res.statusCode=200;
  res.setHeader('Content-Type','text/plain; charset=utf-8');
  res.setHeader('Cache-Control','no-store, max-age=0, must-revalidate');
  res.setHeader('X-Content-Type-Options','nosniff');
  res.end(String(cfg.locale||'id-ID'));
}
