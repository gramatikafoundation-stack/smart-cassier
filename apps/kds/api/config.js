const DEFAULTS = Object.freeze({
  tenantId: '',
  businessName: 'Business',
  locale: 'id-ID',
  currency: 'IDR',
  timezone: 'Asia/Jakarta',
  supabaseUrl: '',
  publishableKey: ''
});

function clean(value, fallback, max = 120) {
  const v = String(value || '').trim();
  return v ? v.slice(0, max) : fallback;
}

export default function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store, max-age=0, must-revalidate');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.setHeader('Allow', 'GET, HEAD');
    return res.status(405).end();
  }

  const strict = process.env.MASTER_PROTOTYPE_STRICT === '1' || process.env.MASTER_CLONE_STRICT === '1';
  const required = ['SDB_TENANT_ID','SUPABASE_URL','SUPABASE_PUBLISHABLE_KEY','BUSINESS_NAME','TENANT_LOCALE','TENANT_CURRENCY','TENANT_TIMEZONE'];
  if (strict && required.some(key => !String(process.env[key] || '').trim())) {
    res.statusCode = 503;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    return res.end(JSON.stringify({ ok: false, error: 'tenant_configuration_incomplete' }));
  }

  const tenantId = clean(process.env.SDB_TENANT_ID, DEFAULTS.tenantId, 64);
  const supabaseUrl = clean(process.env.SUPABASE_URL, DEFAULTS.supabaseUrl, 200);
  let normalizedUrl = DEFAULTS.supabaseUrl;
  try { normalizedUrl = new URL(supabaseUrl).origin; } catch {}

  const payload = {
    tenantId,
    businessName: clean(process.env.BUSINESS_NAME, DEFAULTS.businessName),
    locale: clean(process.env.TENANT_LOCALE, DEFAULTS.locale, 32),
    currency: clean(process.env.TENANT_CURRENCY, DEFAULTS.currency, 3).toUpperCase(),
    timezone: clean(process.env.TENANT_TIMEZONE, DEFAULTS.timezone, 64),
    supabaseUrl: normalizedUrl,
    publishableKey: clean(process.env.SUPABASE_PUBLISHABLE_KEY, DEFAULTS.publishableKey, 300)
  };

  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  if (req.method === 'HEAD') return res.end();
  return res.end(JSON.stringify(payload));
}
