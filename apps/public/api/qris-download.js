import { resolvePublicTenantConfig, failTenantConfig } from '../lib/tenant-config.js';

function cleanOrigin(value) {
  try {
    const u = new URL(String(value || '').trim());
    return u.protocol === 'https:' && !u.username && !u.password ? u.origin : '';
  } catch {
    return '';
  }
}

function slug(value) {
  return String(value || 'Merchant')
    .normalize('NFKD')
    .replace(/[^a-zA-Z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || 'Merchant';
}

function methodNotAllowed(res) {
  res.statusCode = 405;
  res.setHeader('Allow', 'GET, HEAD');
  res.setHeader('Cache-Control', 'no-store');
  return res.end();
}

export default async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'HEAD') return methodNotAllowed(res);

  const cfg = await resolvePublicTenantConfig(req);
  if (!cfg.ok) return failTenantConfig(res, cfg.missing);

  const supabaseUrl = cleanOrigin(process.env.SUPABASE_URL);
  const publishableKey = String(process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '').trim();
  if (!supabaseUrl || !publishableKey) {
    res.statusCode = 503;
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    return res.end('Layanan unduh QRIS belum siap.');
  }

  try {
    const upstream = await fetch(supabaseUrl + '/functions/v1/rohmat-qris-download', {
      method: req.method,
      cache: 'no-store',
      headers: {
        apikey: publishableKey,
        Authorization: 'Bearer ' + publishableKey,
        'x-sdb-tenant-id': cfg.tenantId
      }
    });

    if (!upstream.ok) {
      const message = req.method === 'HEAD' ? '' : await upstream.text().catch(() => 'QRIS tidak dapat diunduh.');
      res.statusCode = upstream.status;
      res.setHeader('Content-Type', 'text/plain; charset=utf-8');
      res.setHeader('Cache-Control', 'no-store');
      res.setHeader('X-SDB-QRIS-Download', 'same-origin-v1');
      return res.end(message || 'QRIS tidak dapat diunduh.');
    }

    const type = String(upstream.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
    if (!/^image\/(png|jpe?g|webp)$/.test(type)) {
      res.statusCode = 502;
      res.setHeader('Content-Type', 'text/plain; charset=utf-8');
      res.setHeader('Cache-Control', 'no-store');
      res.setHeader('X-SDB-QRIS-Download', 'same-origin-v1');
      return res.end('Format gambar QRIS tidak didukung.');
    }

    const ext = type.includes('webp') ? 'webp' : type.includes('jpeg') || type.includes('jpg') ? 'jpg' : 'png';
    res.statusCode = 200;
    res.setHeader('Content-Type', type);
    res.setHeader('Content-Disposition', 'attachment; filename="QRIS-' + slug(cfg.businessName) + '.' + ext + '"');
    res.setHeader('Cache-Control', 'private, no-store, max-age=0');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-SDB-Tenant-ID', cfg.tenantId);
    res.setHeader('X-SDB-QRIS-Download', 'same-origin-v1');

    if (req.method === 'HEAD') return res.end();

    const body = Buffer.from(await upstream.arrayBuffer());
    res.setHeader('Content-Length', String(body.byteLength));
    return res.end(body);
  } catch {
    res.statusCode = 502;
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-SDB-QRIS-Download', 'same-origin-v1');
    return res.end('Gambar QRIS tidak dapat diunduh.');
  }
}
