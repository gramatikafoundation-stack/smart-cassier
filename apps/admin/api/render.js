// master-prototype-final-preview-marker: 2026-09-20
// navigation-runtime-coherence-20260918
import { createHash } from 'node:crypto';
const DEFAULT_RENDERER = 'https://xrepmvbccalzhlcznrff.supabase.co/functions/v1/rohmat-admin-render?mode=optimized'; // compatibility fallback
const DEFAULT_BUSINESS_NAME = 'Business'; // compatibility fallback; strict prototype mode requires explicit value
const RENDERER = process.env.ADMIN_RENDERER_URL || DEFAULT_RENDERER;
const SUPABASE_ORIGIN = process.env.SUPABASE_ORIGIN || new URL(RENDERER).origin;
const BUSINESS_NAME = process.env.BUSINESS_NAME || DEFAULT_BUSINESS_NAME;
const CASHIER_LOADER = '<script id="rohmat-admin-cashier-canonical-v60" src="/admin/runtime/cashier.js" defer></script><!-- rohmat-admin-smart-cashier-subnav-v30 -->';
const CORE_LOADER = '<script id="rohmat-admin-canonical-runtime-v60" src="/admin/runtime/core.js" defer></script>';
const VISUAL_LOADER = '<script id="rohmat-admin-visual-editor-canonical-v60" src="/admin/runtime/visual-editor.js" defer></script>';
const NAV_OLD = "admin:['Login','Dashboard','Pesanan','QRIS','Tim Admin','Keamanan']";
const NAV_NEW = "admin:['Login','Dashboard','Pesanan','Smart Cashier','QRIS','Tim Admin','Keamanan']";
const MEMORY_TTL_MS = 60_000;
const CDN_CACHE = 'public, max-age=60, stale-while-revalidate=300, stale-if-error=86400';
const REQUIRED_MARKERS = [
  'Studio Pengelola',
  'id="view"',
  'mainNav',
  'subnav',
  'admin-foundation-css-v1',
  'rohmat-admin-style-runtime-v59',
  'rohmat-admin-visual-editor-v1',
  'rohmat-admin-theme-preview-v1'
];

let memoryCache = null;
let inflight = null;

async function resolveCanonicalBusinessName(tenantId, signal) {
  const fallback = String(BUSINESS_NAME || DEFAULT_BUSINESS_NAME).trim() || DEFAULT_BUSINESS_NAME;
  const key = String(process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '').trim();
  if (!tenantId || !key) return fallback;
  try {
    const url = new URL('/rest/v1/tenant_site_settings_public_v1', SUPABASE_ORIGIN);
    url.searchParams.set('select', 'business_name');
    url.searchParams.set('tenant_id', 'eq.' + tenantId);
    url.searchParams.set('limit', '1');
    const response = await fetch(url, {
      method: 'GET',
      cache: 'no-store',
      signal,
      headers: { apikey: key, Authorization: 'Bearer ' + key, Accept: 'application/json' }
    });
    if (!response.ok) return fallback;
    const rows = await response.json();
    return String(rows?.[0]?.business_name || fallback).trim().slice(0, 120) || fallback;
  } catch {
    return fallback;
  }
}

function inlineScriptHashes(html) {
  const hashes = [];
  const seen = new Set();
  const re = /<script\b(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi;
  let match;
  while ((match = re.exec(html))) {
    const code = match[1] || '';
    if (!code.trim()) continue;
    const hash = "'sha256-" + createHash('sha256').update(code, 'utf8').digest('base64') + "'";
    if (!seen.has(hash)) { seen.add(hash); hashes.push(hash); }
  }
  return hashes;
}

function contentSecurityPolicy(body) {
  const hashes = inlineScriptHashes(body).join(' ');
  return [
    "default-src 'self'",
    `script-src 'self' ${hashes}`,
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' data: blob: ${SUPABASE_ORIGIN}`,
    `connect-src 'self' ${SUPABASE_ORIGIN}`,
    "font-src 'self' data:",
    "object-src 'none'",
    "base-uri 'self'",
    "frame-ancestors 'none'",
    "form-action 'self'",
    "upgrade-insecure-requests"
  ].join('; ');
}

function ensureCashierIntegration(html) {
  let out = html.includes(NAV_NEW) ? html : html.replace(NAV_OLD, NAV_NEW);
  out = out.replace(/<script\b[^>]*\bid=["']rohmat-admin-cashier-(?:loader|current)-v\d+["'][^>]*>[\s\S]*?<\/script>(?:<!-- rohmat-admin-smart-cashier-subnav-v\d+ -->)?/gi, '');
  const at = out.lastIndexOf('</body>');
  return at >= 0 ? out.slice(0, at) + CASHIER_LOADER + out.slice(at) : out + CASHIER_LOADER;
}

function escRe(value) {
  return String(value).replace(/[.*+?^$\{\}()|[\]\\]/g, '\\$&');
}
function scriptRe(id) {
  return new RegExp('<script\\b[^>]*\\bid=["\\\']' + escRe(id) + '["\\\'][^>]*>[\\s\\S]*?<\\/script>', 'i');
}
function styleRe(id) {
  return new RegExp('<style\\b[^>]*\\bid=["\\\']' + escRe(id) + '["\\\'][^>]*>([\\s\\S]*?)<\\/style>', 'i');
}
function consolidateCss(html) {
  let out = html;
  const extras = [];
  for (const id of ['admin-design-system-v41', 'admin-theme14-v50', 'admin-final-layout-v50']) {
    out = out.replace(styleRe(id), (_m, css) => {
      if (String(css || '').trim()) extras.push('/* ' + id + ' consolidated-v60 */\n' + css);
      return '';
    });
  }
  if (!extras.length) return out;
  const foundation = /(<style\b[^>]*\bid=["']admin-foundation-css-v1["'][^>]*>)([\s\S]*?)(<\/style>)/i;
  return out.replace(foundation, (_m, open, css, close) => open + css + '\n' + extras.join('\n') + close);
}

export function canonicalizeAdminShell(html, businessName = BUSINESS_NAME) {
  let out = ensureCashierIntegration(String(html || ''));
  const canonicalBusinessName = String(businessName || BUSINESS_NAME || DEFAULT_BUSINESS_NAME).trim() || DEFAULT_BUSINESS_NAME;
  out = out.split('Warung Nasi').join(canonicalBusinessName);
  out = out.split(SUPABASE_ORIGIN + '/functions/v1/admin-media-upload').join('/admin/api/media-upload');
  out = out.replace(/MEDIA=U\+'\/functions\/v1\/admin-media-upload'/g, "MEDIA='/admin/api/media-upload'");
  out = out.split('https://smart-cassier.vercel.app/login').join('/kds/login');
  out = consolidateCss(out);

  const v41 = scriptRe('admin-design-system-runtime-v41');
  if (v41.test(out)) out = out.replace(v41, CORE_LOADER);
  else if (!out.includes('rohmat-admin-canonical-runtime-v60')) out = out.replace('</head>', CORE_LOADER + '</head>');

  for (const id of [
    'rohmat-admin-style-runtime-loader-v59',
    'admin-theme14-runtime-v50',
    'admin-fast-navigation-v50',
    'admin-final-links-v50'
  ]) out = out.replace(scriptRe(id), '');

  const visual = /<script\b[^>]*\bid=["']rohmat-visual-editor-loader-v\d+["'][^>]*>[\s\S]*?<\/script>/i;
  out = visual.test(out) ? out.replace(visual, VISUAL_LOADER) : out.replace('</head>', VISUAL_LOADER + '</head>');

  if (!/<meta\s+name=["']robots["']/i.test(out)) {
    out = out.replace(/<head>/i, '<head><meta name="robots" content="noindex,nofollow,noarchive">');
  }
  return out;
}
function validateRendererPayload(upstreamOk, payload, html) {
  if (!upstreamOk || payload?.ok !== true || typeof html !== 'string') return false;
  if (html.length < 60_000) return false;
  if (!REQUIRED_MARKERS.every(marker => html.includes(marker))) return false;
  return true;
}

async function refreshShell(renderer) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8_000);
  try {
    const tenantId = String(process.env.SDB_TENANT_ID || '').trim();
    const key = String(process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '');
    const [upstream, canonicalBusinessName] = await Promise.all([
      fetch(renderer, {
        method: 'GET',
        cache: 'no-store',
        signal: controller.signal,
        headers: {
          Accept: 'application/json',
          'x-sdb-tenant-id': tenantId,
          apikey: key,
          Authorization: 'Bearer ' + key
        }
      }),
      resolveCanonicalBusinessName(tenantId, controller.signal)
    ]);
    const payload = await upstream.json();
    const html = String(payload?.html || '');
    if (!validateRendererPayload(upstream.ok, payload, html)) {
      throw new Error('invalid_admin_renderer_response');
    }
    const body = canonicalizeAdminShell(html, canonicalBusinessName);
    if (!body.includes(NAV_NEW) || !body.includes('rohmat-admin-smart-cashier-subnav-v30')) {
      throw new Error('cashier_integration_missing');
    }
    const next = {
      body,
      source: String(payload?.source || 'renderer-full'),
      contract: String(payload?.contract || 'admin-shell-compatible'),
      rendererIntegrity: String(payload?.integrity || 'legacy-compatible'),
      storedAt: Date.now()
    };
    memoryCache = next;
    return { ...next, cacheState: 'upstream' };
  } finally {
    clearTimeout(timer);
  }
}

async function getShell(renderer) {
  if (memoryCache && Date.now() - memoryCache.storedAt < MEMORY_TTL_MS) {
    return { ...memoryCache, cacheState: 'memory-hit' };
  }
  if (!inflight) {
    inflight = refreshShell(renderer).finally(() => {
      inflight = null;
    });
  }
  try {
    return await inflight;
  } catch (error) {
    if (memoryCache) return { ...memoryCache, cacheState: 'stale-memory' };
    throw error;
  }
}

export default async function handler(req, res) {
  const strict = process.env.MASTER_PROTOTYPE_STRICT === '1' || process.env.MASTER_CLONE_STRICT === '1';
  const tenantId = String(process.env.SDB_TENANT_ID || '').trim();
  if (strict && (!tenantId || !process.env.ADMIN_RENDERER_URL || !process.env.SUPABASE_ORIGIN || !process.env.BUSINESS_NAME)) {
    res.statusCode = 503;
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    return res.end('tenant_configuration_incomplete');
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.setHeader('Allow', 'GET, HEAD');
    return res.status(405).end('method_not_allowed');
  }

  const renderer = RENDERER;

  try {
    const shell = await getShell(renderer);

    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'private, no-store, max-age=0, must-revalidate');
    res.setHeader('CDN-Cache-Control', CDN_CACHE);
    res.setHeader('Vercel-CDN-Cache-Control', CDN_CACHE);
    res.setHeader('Vercel-Cache-Tag', 'rohmat-admin-shell-b2');
    res.setHeader('X-Rohmat-Admin', 'master-prototype-v1');
    res.setHeader('X-SDB-Tenant-ID', tenantId);
    res.setHeader('X-Rohmat-Admin-Source', shell.source);
    res.setHeader('X-Rohmat-Admin-Contract', shell.contract);
    res.setHeader('X-Rohmat-Admin-Integrity', shell.rendererIntegrity);
    res.setHeader('X-Rohmat-Admin-Origin-Cache', shell.cacheState);
    res.setHeader('X-Rohmat-Admin-Cashier', 'canonical-same-origin-v60');
    res.setHeader('X-Rohmat-Admin-Runtime', 'canonical-core-v60');
    res.setHeader('X-Rohmat-Admin-Security', 'secure-api-v5-retained');
    res.setHeader('Content-Security-Policy', contentSecurityPolicy(shell.body));
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
    res.setHeader('Origin-Agent-Cluster', '?1');
    res.setHeader('X-Permitted-Cross-Domain-Policies', 'none');
    if (req.method === 'HEAD') return res.end();
    return res.end(shell.body);
  } catch (error) {
    res.statusCode = 503;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store, max-age=0');
    res.setHeader('X-Rohmat-Admin', 'recovery-b2');
    if (req.method === 'HEAD') return res.end();
    const safeName = String(BUSINESS_NAME).replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
    return res.end(`<!doctype html><meta charset="utf-8"><meta name="robots" content="noindex,nofollow,noarchive"><meta name="viewport" content="width=device-width"><title>Studio Pengelola ${safeName}</title><main style="font:16px system-ui;padding:32px;max-width:680px;margin:auto"><h1>Studio Pengelola ${safeName}</h1><p>Admin sedang memulihkan koneksi. Silakan muat ulang halaman.</p></main>`);
  }
}
