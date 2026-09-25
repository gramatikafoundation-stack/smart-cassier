import { createHash } from 'node:crypto';

const DEFAULT_RENDERER = 'https://xrepmvbccalzhlcznrff.supabase.co/functions/v1/rohmat-admin-render?mode=optimized';
const RENDERER = process.env.ADMIN_RENDERER_URL || DEFAULT_RENDERER;
const SUPABASE_ORIGIN = process.env.SUPABASE_ORIGIN || new URL(RENDERER).origin;
const TENANT_ID = String(process.env.SDB_TENANT_ID || '').trim();
const API_KEY = String(process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_PUBLISHABLE_KEY || '').trim();
const CLIENT_KEY = String(process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '').trim();
const TTL_MS = 60_000;
const cache = new Map();

function escapeRe(value) {
  return String(value).replace(/[.*+?^$\u007b\u007d()|[\]\\]/g, '\\$&');
}
function inlineScript(html, id) {
  const re = new RegExp('<script\\b[^>]*\\bid=["\\\']' + escapeRe(id) + '["\\\'][^>]*>([\\s\\S]*?)<\\/script>', 'i');
  const m = String(html || '').match(re);
  return m ? m[1] : '';
}
function upstreamHeaders(accept = 'application/javascript') {
  const h = { Accept: accept, 'x-sdb-tenant-id': TENANT_ID };
  if (API_KEY) {
    h.apikey = API_KEY;
    h.Authorization = 'Bearer ' + API_KEY;
  }
  return h;
}
async function fetchWithTimeout(url, accept = 'application/javascript') {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch(url, {
      cache: 'no-store',
      signal: controller.signal,
      headers: upstreamHeaders(accept)
    });
    const body = await response.text();
    if (!response.ok) throw new Error('upstream_' + response.status);
    return { body, headers: response.headers };
  } finally {
    clearTimeout(timer);
  }
}

function normalizeLegacyClientRuntime(body) {
  let out = String(body || '');
  out = out.split('https://yybhpmjuywjxqurrrrxl.supabase.co').join(SUPABASE_ORIGIN);
  if (CLIENT_KEY) out = out.replace(/sb_publishable_[A-Za-z0-9_-]+/g, CLIENT_KEY);
  return out;
}
function normalizeStyleRuntime(body) {
  let out = normalizeLegacyClientRuntime(body);
  out = out.replace(/add\('rohmat-admin-cashier-safe-v7',[\s\S]*?\);/g, '');
  out = out.replace(/add\('rohmat-admin-database-safe-v10',[\s\S]*?\);/g, "add('rohmat-admin-database-safe-v10','/admin/runtime/database-ui.js');");
  out = out.replace(/add\('rohmat-admin-kds-safe-v6',[\s\S]*?\);/g, '');
  out = out.split("const PUB='https://rohmat-pesan-bayar-publik.vercel.app/';const KDS='https://rohmat-kds-printer.vercel.app';").join("const PUB='/';const KDS='/kds';");
  return out;
}
function normalizeModuleRuntime(kind, body) {
  let out = normalizeLegacyClientRuntime(body);
  if (kind === 'database-ui') {
    out = out.replace(/https:\/\/[A-Za-z0-9.-]+\.supabase\.co\/functions\/v1\/rohmat-admin-order-history-v1/g, '/admin/api/order-history');
  } else if (kind === 'cashier') {
    out = out.replace(/https:\/\/[A-Za-z0-9.-]+\.supabase\.co\/functions\/v1\/rohmat-smart-cashier-v1/g, '/admin/api/smart-cashier');
  }
  return out;
}

const NAVIGATION_RUNTIME = "(()=>{'use strict';if(window.__rohmatAdminCanonicalNavigationV60)return;window.__rohmatAdminCanonicalNavigationV60=1;let queued=false;" +
"function patchLinks(){document.querySelectorAll('a[href]').forEach(a=>{const raw=a.getAttribute('href')||'',txt=(a.textContent||'').trim().toLowerCase();let u;try{u=new URL(raw,location.origin)}catch{return}const path=u.pathname.toLowerCase(),parts=path.split('/').filter(Boolean),kds=txt.includes('kds')||parts.includes('kds')||parts.includes('dapur');if(!kds)return;const login=path.endsWith('/login')||txt.includes('login');const next=login?'/kds/login':'/kds';if(a.getAttribute('href')!==next)a.setAttribute('href',next);if(a.target==='_blank')a.setAttribute('rel','noopener noreferrer')})}" +
"function active(b){const nav=b&&b.closest('.subnav');if(!nav)return;nav.querySelectorAll('button[data-sub]').forEach(x=>x.classList.toggle('on',x===b))}" +
"function fire(){if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;patchLinks();document.dispatchEvent(new CustomEvent('rohmat:navigation'))})}" +
"document.addEventListener('pointerdown',e=>{const b=e.target.closest&&e.target.closest('.subnav button[data-sub]');if(b)active(b)},true);" +
"document.addEventListener('click',e=>{if(e.target.closest&&e.target.closest('[data-main],[data-sub]'))fire()},false);" +
"document.addEventListener('rohmat:navigation',patchLinks);" +
"const start=()=>{patchLinks();const root=document.getElementById('root');if(root){let p=false;new MutationObserver(()=>{if(p)return;p=true;requestAnimationFrame(()=>{p=false;patchLinks()})}).observe(root,{childList:true,subtree:true})}};" +
"if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();})();";

export function buildCanonicalCoreFromHtml(html, styleRuntime) {
  const v41 = inlineScript(html, 'admin-design-system-runtime-v41');
  const v50 = inlineScript(html, 'admin-theme14-runtime-v50');
  if (!v41 || !v50) throw new Error('admin_runtime_source_missing');
  if (!String(styleRuntime || '').trim()) throw new Error('admin_style_runtime_missing');
  return [
    '/* Rohmat Admin canonical runtime v60: design-system v41 + theme v50 + style v59 + navigation */',
    v41,
    v50,
    String(styleRuntime),
    NAVIGATION_RUNTIME,
    ';document.documentElement.dataset.rohmatAdminCanonicalRuntime="v60";'
  ].join('\n;\n');
}

async function coreBody() {
  const renderer = await fetchWithTimeout(RENDERER, 'application/json');
  let payload;
  try { payload = JSON.parse(renderer.body); } catch { throw new Error('renderer_json_invalid'); }
  const html = String(payload?.html || '');
  if (payload?.ok !== true || html.length < 60000) throw new Error('renderer_payload_invalid');
  const styleUrl = SUPABASE_ORIGIN + '/functions/v1/rohmat-admin-style-runtime-v59?tenant=' + encodeURIComponent(TENANT_ID) + '&v=58';
  const style = await fetchWithTimeout(styleUrl);
  if (style.body.includes('admin runtime baseline unavailable')) throw new Error('style_runtime_unavailable');
  return buildCanonicalCoreFromHtml(html, normalizeStyleRuntime(style.body));
}
async function moduleBody(kind) {
  if (kind === 'core') return coreBody();
  const map = {
    'visual-editor': 'rohmat-admin-visual-editor-v1?tenant=' + encodeURIComponent(TENANT_ID) + '&v=20',
    cashier: 'rohmat-admin-cashier-loader-v1?tenant=' + encodeURIComponent(TENANT_ID) + '&v=36',
    'database-ui': 'rohmat-admin-database-ui-v1?tenant=' + encodeURIComponent(TENANT_ID) + '&v=19'
  };
  const path = map[kind];
  if (!path) throw new Error('unknown_runtime_kind');
  const body = (await fetchWithTimeout(SUPABASE_ORIGIN + '/functions/v1/' + path)).body;
  return normalizeModuleRuntime(kind, body);
}
async function cached(kind) {
  const now = Date.now();
  const hit = cache.get(kind);
  if (hit && now - hit.at < TTL_MS) return { ...hit, state: 'memory-hit' };
  const body = await moduleBody(kind);
  const next = {
    body,
    at: now,
    etag: '"' + createHash('sha256').update(body).digest('hex').slice(0, 32) + '"'
  };
  cache.set(kind, next);
  return { ...next, state: 'upstream' };
}
function kindOf(req) {
  const q = Array.isArray(req?.query?.kind) ? req.query.kind[0] : req?.query?.kind;
  if (q) return String(q);
  const path = new URL(req?.url || '/', 'https://admin.invalid').pathname;
  if (path.endsWith('/core.js')) return 'core';
  if (path.endsWith('/visual-editor.js')) return 'visual-editor';
  if (path.endsWith('/cashier.js')) return 'cashier';
  if (path.endsWith('/database-ui.js')) return 'database-ui';
  return '';
}

export default async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.statusCode = 405;
    res.setHeader('Allow', 'GET, HEAD');
    return res.end();
  }
  if (!TENANT_ID || !SUPABASE_ORIGIN || !API_KEY) {
    res.statusCode = 503;
    res.setHeader('Cache-Control', 'no-store');
    return res.end('/* admin runtime configuration unavailable */');
  }
  const kind = kindOf(req);
  if (!['core', 'visual-editor', 'cashier', 'database-ui'].includes(kind)) {
    res.statusCode = 404;
    return res.end('not_found');
  }
  try {
    const runtime = await cached(kind);
    if (String(req.headers?.['if-none-match'] || '') === runtime.etag) {
      res.statusCode = 304;
      res.setHeader('ETag', runtime.etag);
      return res.end();
    }
    res.statusCode = 200;
    res.setHeader('Content-Type', 'application/javascript; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=60, s-maxage=300, stale-while-revalidate=600');
    res.setHeader('CDN-Cache-Control', 'public, s-maxage=300, stale-while-revalidate=600');
    res.setHeader('Vercel-CDN-Cache-Control', 'public, s-maxage=300, stale-while-revalidate=600');
    res.setHeader('ETag', runtime.etag);
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Robots-Tag', 'noindex, nofollow, noarchive');
    res.setHeader('X-Rohmat-Admin-Runtime', kind === 'core' ? 'canonical-core-v60' : 'same-origin-proxy-v60');
    res.setHeader('X-Rohmat-Admin-Runtime-Cache', runtime.state);
    if (req.method === 'HEAD') return res.end();
    return res.end(runtime.body);
  } catch (error) {
    res.statusCode = 503;
    res.setHeader('Content-Type', 'application/javascript; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Rohmat-Admin-Runtime-Error', String(error?.message || error).slice(0, 120));
    return res.end('/* admin canonical runtime unavailable */');
  }
}
