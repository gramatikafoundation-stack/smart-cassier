const FALLBACK = Object.freeze({
  locale: 'id-ID',
  cuisine: 'Food & Beverage'
});

function clean(value, fallback, max = 180) {
  const v = String(value || '').trim();
  return v ? v.slice(0, max) : fallback;
}

function origin(value) {
  try {
    const u = new URL(String(value || '').trim());
    if (u.protocol !== 'https:' || u.username || u.password) throw new Error('https_required');
    return u.origin;
  } catch {
    return '';
  }
}

export function getPublicTenantConfig(env = process.env) {
  const strict = env.MASTER_PROTOTYPE_STRICT === '1' || env.MASTER_CLONE_STRICT === '1';
  const required = ['SDB_TENANT_ID','PUBLIC_ORIGIN','BUSINESS_NAME'];
  const missing = required.filter(key => !String(env[key] || '').trim());
  const tenantId = clean(env.SDB_TENANT_ID, '', 64);
  const businessName = clean(env.BUSINESS_NAME, 'Business', 100);
  const publicOrigin = origin(env.PUBLIC_ORIGIN);
  if (!publicOrigin && !missing.includes('PUBLIC_ORIGIN')) missing.push('PUBLIC_ORIGIN');
  const locale = clean(env.TENANT_LOCALE, FALLBACK.locale, 32);
  const description = clean(
    env.PUBLIC_DESCRIPTION,
    `Pesan menu ${businessName} secara online dengan cepat, praktis, dan aman.`,
    220
  );
  const cuisine = clean(env.PUBLIC_CUISINE, FALLBACK.cuisine, 80);
  return {
    tenantId,
    ok: missing.length === 0,
    missing,
    strict,
    origin: publicOrigin,
    canonical: publicOrigin + '/',
    businessName,
    title: `${businessName} — Pesan & Bayar`,
    description,
    locale,
    ogLocale: locale.replace('-', '_'),
    cuisine,
    socialImage: publicOrigin + '/og-image.png'
  };
}

export function failTenantConfig(res, missing = []) {
  res.statusCode = 503;
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  return res.end('tenant_configuration_incomplete' + (missing.length ? ':' + missing.join(',') : ''));
}

export function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, ch => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[ch]));
}


function requestOrigin(req) {
  const proto = String(req?.headers?.['x-forwarded-proto'] || 'https').split(',')[0].trim().toLowerCase();
  const host = String(req?.headers?.['x-forwarded-host'] || req?.headers?.host || '').split(',')[0].trim().toLowerCase();
  if (proto !== 'https' || !host || !/^[a-z0-9.-]+(?::\d{1,5})?$/.test(host)) return '';
  return 'https://' + host;
}

export async function resolvePublicTenantConfig(req, env = process.env) {
  const direct = getPublicTenantConfig(env);
  if (direct.ok && direct.tenantId) return direct;

  const supabaseUrl = origin(env.SUPABASE_URL);
  const publishableKey = clean(env.SUPABASE_PUBLISHABLE_KEY || env.SUPABASE_ANON_KEY, '', 500);
  const requestedOrigin = requestOrigin(req);
  if (!supabaseUrl || !publishableKey || !requestedOrigin) {
    return { ...direct, ok:false, missing:[...new Set([...(direct.missing||[]), !publishableKey?'SUPABASE_PUBLISHABLE_KEY':'', !requestedOrigin?'REQUEST_ORIGIN':''].filter(Boolean))] };
  }

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 1800);
    let response;
    try {
      response = await fetch(supabaseUrl + '/rest/v1/rpc/master_prototype_resolve_origin', {
        method:'POST',
        cache:'no-store',
        signal:controller.signal,
        headers:{
          apikey:publishableKey,
          Authorization:'Bearer ' + publishableKey,
          'Content-Type':'application/json'
        },
        body:JSON.stringify({ p_origin:requestedOrigin, p_app_kind:'public' })
      });
    } finally {
      clearTimeout(timer);
    }
    const resolved = await response.json().catch(() => null);
    if (!response.ok || !resolved?.ok || !resolved?.tenant_id || !resolved?.business_name) {
      return { ...direct, ok:false, missing:['TENANT_ORIGIN_MAPPING'] };
    }
    const canonicalOrigin = origin(resolved.public_origin) || requestedOrigin;
    const locale = clean(resolved.locale, FALLBACK.locale, 32);
    const businessName = clean(resolved.business_name, 'Business', 100);
    const description = clean(
      env.PUBLIC_DESCRIPTION,
      `Pesan menu ${businessName} secara online dengan cepat, praktis, dan aman.`,
      220
    );
    const cuisine = clean(env.PUBLIC_CUISINE, FALLBACK.cuisine, 80);
    return {
      tenantId:String(resolved.tenant_id),
      tenantSlug:String(resolved.tenant_slug||''),
      ok:true,
      missing:[],
      strict:true,
      origin:canonicalOrigin,
      requestOrigin:requestedOrigin,
      canonical:canonicalOrigin + '/',
      businessName,
      title:`${businessName} — Pesan & Bayar`,
      description,
      locale,
      ogLocale:locale.replace('-', '_'),
      cuisine,
      socialImage:canonicalOrigin + '/og-image.png',
      resolvedBy:'origin'
    };
  } catch {
    return { ...direct, ok:false, missing:['TENANT_ORIGIN_RESOLUTION'] };
  }
}
