const DEFAULT_UPSTREAM = 'https://yybhpmjuywjxqurrrrxl.supabase.co/functions/v1/rohmat-kds-api';

function firstIp(value) {
  return String(value || '').split(',')[0].trim().slice(0, 80);
}

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store, max-age=0, must-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');

  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ ok: false, error: 'method_not_allowed' });
  }

  const host = String(req.headers.host || '');
  const origin = String(req.headers.origin || '');
  const proto = String(req.headers['x-forwarded-proto'] || 'https');
  const expectedOrigin = `${proto}://${host}`;
  const secFetchSite = String(req.headers['sec-fetch-site'] || '');

  if (origin && origin !== expectedOrigin) {
    return res.status(403).json({ ok: false, error: 'origin_not_allowed' });
  }
  if (secFetchSite && !['same-origin', 'same-site', 'none'].includes(secFetchSite)) {
    return res.status(403).json({ ok: false, error: 'csrf_rejected' });
  }

  const strict = process.env.MASTER_PROTOTYPE_STRICT === '1' || process.env.MASTER_CLONE_STRICT === '1';
  const tenantId = String(process.env.SDB_TENANT_ID || '').trim();
  if (strict && (!process.env.KDS_BFF_URL || !tenantId)) {
    return res.status(503).json({ ok: false, error: 'tenant_configuration_incomplete' });
  }
  const upstream = process.env.KDS_BFF_URL || DEFAULT_UPSTREAM;
  const projectOrigin = new URL(upstream).origin;
  const body = typeof req.body === 'string' ? req.body : JSON.stringify(req.body || {});
  if (Buffer.byteLength(body, 'utf8') > 65536) {
    return res.status(413).json({ ok: false, error: 'request_too_large' });
  }

  let action = '';
  try { action = String(JSON.parse(body)?.action || ''); } catch {}

  const headers = {
    'content-type': 'application/json',
    'apikey': String(process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || ''),
    'authorization': 'Bearer ' + String(process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || ''),
    'origin': projectOrigin,
    'sec-fetch-site': 'same-origin',
    'user-agent': String(req.headers['user-agent'] || 'Master-KDS-Proxy'),
    'accept-language': String(req.headers['accept-language'] || 'unknown'),
    'sec-ch-ua-platform': String(req.headers['sec-ch-ua-platform'] || 'unknown'),
    'x-forwarded-for': firstIp(req.headers['x-forwarded-for'] || req.socket?.remoteAddress || ''),
    'x-request-id': String(req.headers['x-request-id'] || ''),
    'x-sdb-tenant-id': tenantId
  };
  if (req.headers.cookie) headers.cookie = String(req.headers.cookie);

  try {
    const upstreamResponse = await fetch(upstream, {
      method: 'POST',
      headers,
      body,
      redirect: 'manual'
    });
    const text = await upstreamResponse.text();

    const setCookies = typeof upstreamResponse.headers.getSetCookie === 'function'
      ? upstreamResponse.headers.getSetCookie()
      : [];
    const fallbackCookie = upstreamResponse.headers.get('set-cookie');
    if (setCookies.length) {
      res.setHeader('Set-Cookie', setCookies);
    } else if (fallbackCookie) {
      res.setHeader('Set-Cookie', fallbackCookie);
    }

    const requestId = upstreamResponse.headers.get('x-request-id');
    const contract = upstreamResponse.headers.get('x-rohmat-contract');
    const security = upstreamResponse.headers.get('x-rohmat-kds-security');
    if (requestId) res.setHeader('X-Request-ID', requestId);
    if (contract) res.setHeader('X-Rohmat-Contract', contract);
    if (security) res.setHeader('X-Rohmat-KDS-Security', security);
    res.setHeader('X-Rohmat-KDS-Cookie-Forwarded', (setCookies.length || fallbackCookie) ? '1' : '0');

    console.info('[kds-proxy]', JSON.stringify({ action, status: upstreamResponse.status, setCookieCount: setCookies.length || (fallbackCookie ? 1 : 0) }));

    res.status(upstreamResponse.status);
    res.setHeader('Content-Type', upstreamResponse.headers.get('content-type') || 'application/json; charset=utf-8');
    return res.send(text);
  } catch (error) {
    console.error('[kds-proxy]', JSON.stringify({ action, error: 'upstream_unavailable' }));
    return res.status(502).json({ ok: false, error: 'kds_upstream_unavailable' });
  }
}
