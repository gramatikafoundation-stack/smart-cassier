import { resolvePublicTenantConfig, failTenantConfig } from '../lib/tenant-config.js';

function methodNotAllowed(res) {
  res.statusCode = 405;
  res.setHeader('Allow', 'GET, HEAD');
  res.setHeader('Cache-Control', 'no-store');
  return res.end();
}

export default async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'HEAD') return methodNotAllowed(res);
  const cfg=await resolvePublicTenantConfig(req);
  if(!cfg.ok)return failTenantConfig(res,cfg.missing);
  const body=`User-agent: *
Allow: /
Disallow: /api/
Sitemap: ${cfg.origin}/sitemap.xml
`;
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=3600, s-maxage=86400, stale-while-revalidate=604800');
  res.setHeader('X-Rohmat-SEO', 'robots-v2-tenant');
  if (req.method === 'HEAD') return res.end();
  return res.end(body);
}
