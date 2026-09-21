import { resolvePublicTenantConfig, failTenantConfig } from '../lib/tenant-config.js';

export default async function handler(req,res){
  if(req.method!=='GET'&&req.method!=='HEAD'){res.statusCode=405;res.setHeader('Allow','GET, HEAD');return res.end()}
  const cfg=await resolvePublicTenantConfig(req);
  if(!cfg.ok)return failTenantConfig(res,cfg.missing);
  const manifest={
    name:cfg.title,
    short_name:cfg.businessName,
    description:cfg.description,
    start_url:'/',
    scope:'/',
    display:'standalone',
    background_color:'#F5EFE3',
    theme_color:'#315343',
    lang:cfg.locale,
    dir:'ltr',
    categories:['food','shopping'],
    icons:[
      {src:cfg.origin+'/icon-192.png',sizes:'192x192',type:'image/png',purpose:'any maskable'},
      {src:cfg.origin+'/icon-512.png',sizes:'512x512',type:'image/png',purpose:'any maskable'}
    ]
  };
  res.statusCode=200;
  res.setHeader('Content-Type','application/manifest+json; charset=utf-8');
  res.setHeader('Cache-Control','public, max-age=3600');
  res.setHeader('X-Content-Type-Options','nosniff');
  if(req.method==='HEAD')return res.end();
  res.end(JSON.stringify(manifest));
}
