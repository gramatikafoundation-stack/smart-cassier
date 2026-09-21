// master-prototype-final-preview-marker: 2026-09-20
// navigation-runtime-coherence-20260918
import { createHash } from 'node:crypto';
const DEFAULT_RENDERER = 'https://yybhpmjuywjxqurrrrxl.supabase.co/functions/v1/rohmat-admin-render?mode=optimized'; // compatibility fallback
const DEFAULT_BUSINESS_NAME = 'Business'; // compatibility fallback; strict prototype mode requires explicit value
const RENDERER = process.env.ADMIN_RENDERER_URL || DEFAULT_RENDERER;
const SUPABASE_ORIGIN = process.env.SUPABASE_ORIGIN || new URL(RENDERER).origin;
const CASHIER_LOADER_URL = process.env.ADMIN_CASHIER_LOADER_URL || `${SUPABASE_ORIGIN}/functions/v1/rohmat-admin-cashier-loader-v1?v=36`;
const BUSINESS_NAME = process.env.BUSINESS_NAME || DEFAULT_BUSINESS_NAME;
const CASHIER_LOADER = `<script id="rohmat-admin-cashier-loader-v30" src="${CASHIER_LOADER_URL}" defer></script><!-- rohmat-admin-smart-cashier-subnav-v30 -->`;
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
    `script-src 'self' ${SUPABASE_ORIGIN} ${hashes}`,
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
  out = out.replace(/<script id="rohmat-admin-cashier-loader-v\d+"[\s\S]*?<\/script><!-- rohmat-admin-smart-cashier-subnav-v\d+ -->/g, '');
  if (!out.includes('rohmat-admin-smart-cashier-subnav-v30')) {
    const at = out.lastIndexOf('</body>');
    out = at >= 0 ? out.slice(0, at) + CASHIER_LOADER + out.slice(at) : out + CASHIER_LOADER;
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
    const upstream = await fetch(renderer, {
      method: 'GET',
      cache: 'no-store',
      signal: controller.signal,
      headers: {
        Accept: 'application/json',
        'x-sdb-tenant-id': tenantId
      }
    });
    const payload = await upstream.json();
    const html = String(payload?.html || '');
    if (!validateRendererPayload(upstream.ok, payload, html)) {
      throw new Error('invalid_admin_renderer_response');
    }
    const body = ensureCashierIntegration(html);
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
  if (strict && (!tenantId || !process.env.ADMIN_RENDERER_URL || !process.env.ADMIN_CASHIER_LOADER_URL || !process.env.SUPABASE_ORIGIN || !process.env.BUSINESS_NAME)) {
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
    res.setHeader('X-Rohmat-Admin-Cashier', 'canonical-subnav-v30');
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
    return res.end(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Studio Pengelola ${safeName}</title><main style="font:16px system-ui;padding:32px;max-width:680px;margin:auto"><h1>Studio Pengelola ${safeName}</h1><p>Admin sedang memulihkan koneksi. Silakan muat ulang halaman.</p></main>`);
  }
}
