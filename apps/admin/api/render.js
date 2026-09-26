// master-prototype-final-preview-marker: 2026-09-20
// navigation-runtime-coherence-20260918
import { createHash } from 'node:crypto';
const DEFAULT_RENDERER = 'https://yybhpmjuywjxqurrrrxl.supabase.co/functions/v1/rohmat-admin-render?mode=optimized'; // compatibility fallback
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
const FUTURE_ADMIN_UI_PATCH = String.raw`<style id="smart-order-admin-foodcode-v1">
:root{
 --bg:#f5f7f6;--panel:#fff;--panel2:#f0f4f2;--ink:#15231f;--muted:#70807a;--primary:#10201d;--accent:#00bfae;
 --line:#e1e8e4;--radius:16px;--shadow:0 16px 42px rgba(9,19,23,.065)
}
html,body{background:var(--bg)!important;color:var(--ink)!important;font-family:Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif!important}
body{background:radial-gradient(circle at 82% -10%,rgba(0,191,174,.065),transparent 31rem),var(--bg)!important}
button,input,select,textarea{font-family:inherit!important}
button{transition:transform .15s ease,background-color .15s ease,border-color .15s ease,box-shadow .15s ease}
button:not(:disabled):hover{transform:translateY(-1px)}
.auth{grid-template-columns:minmax(360px,.88fr) minmax(480px,1.12fr)!important;background:var(--bg)!important}
.authBrand{background:linear-gradient(145deg,#091317 0%,#102a25 100%)!important;padding:clamp(38px,7vw,88px)!important}
.authBrand h1{font-family:Inter,ui-sans-serif,system-ui!important;font-weight:800!important;letter-spacing:-.055em!important;line-height:.96!important}
.authBrand p{color:#c5d4cf!important}.authPane{padding:32px!important}
.login{border:1px solid var(--line)!important;border-radius:24px!important;padding:34px!important;box-shadow:0 28px 72px rgba(9,19,23,.10)!important}
.login h2{letter-spacing:-.035em!important}.ey{color:#c87942!important;letter-spacing:.16em!important}
.field input,.field select,.field textarea{min-height:46px!important;border-radius:11px!important;border-color:var(--line)!important}
.btn{min-height:42px!important;border-radius:11px!important;font-weight:820!important}.btn.primary{background:var(--primary)!important;color:#fff!important}
.btn.accent{background:var(--accent)!important;color:#052823!important}.btn.soft{background:#f0f4f2!important;color:var(--ink)!important;border-color:var(--line)!important}
.shell{grid-template-columns:238px minmax(0,1fr)!important;background:var(--bg)!important}
.sidebar{background:linear-gradient(180deg,#091317 0%,#10201d 100%)!important;color:#fff!important;padding:18px 14px!important;gap:16px!important;border-right:1px solid rgba(255,255,255,.05)!important}
.logo{padding:8px 9px 14px!important;gap:10px!important}.logoMark{width:38px!important;height:38px!important;border-radius:11px!important;background:var(--accent)!important;color:#062522!important;box-shadow:0 8px 22px rgba(0,191,174,.18)!important}
.logo small,.sidebarFoot small{color:#92aaa2!important}.mainNav{gap:5px!important}
.mainNav button{min-height:44px!important;border-radius:11px!important;padding:11px 12px!important;color:#c9d8d3!important;position:relative!important}
.mainNav button:hover{background:rgba(255,255,255,.055)!important;color:#fff!important}
.mainNav button.on{background:rgba(255,255,255,.10)!important;color:#fff!important;box-shadow:inset 3px 0 var(--accent)!important}
.topbar{min-height:66px!important;background:rgba(255,255,255,.90)!important;backdrop-filter:blur(18px) saturate(150%)!important;border-bottom:1px solid rgba(16,32,29,.075)!important;padding:10px 24px!important}
.topbar h2{font-size:18px!important;letter-spacing:-.02em!important}.content{padding:22px 28px 32px!important;max-width:1480px!important}
.subnav{gap:7px!important;padding-bottom:16px!important}.subnav button{min-height:38px!important;border-radius:999px!important;background:#fff!important;border-color:var(--line)!important;color:#52625c!important;padding:8px 13px!important}
.subnav button.on{background:var(--primary)!important;border-color:var(--primary)!important;color:#fff!important;box-shadow:0 6px 16px rgba(9,19,23,.08)!important}
.sectionHead{margin:3px 0 17px!important;align-items:flex-end!important}.sectionHead h1{font-size:clamp(27px,3.5vw,38px)!important;letter-spacing:-.045em!important;color:var(--primary)!important}.sectionHead p{color:var(--muted)!important}
.card{background:var(--panel)!important;border:1px solid var(--line)!important;border-radius:var(--radius)!important;box-shadow:0 7px 24px rgba(9,19,23,.035)!important;padding:18px!important}
.grid2{gap:16px!important}.grid3{gap:14px!important}.stats{gap:12px!important}
.stat{background:#fff!important;border:1px solid var(--line)!important;border-radius:15px!important;padding:16px 17px!important;box-shadow:0 6px 18px rgba(9,19,23,.025)!important;position:relative!important;overflow:hidden!important}
.stat:before{content:"";position:absolute;left:0;top:0;bottom:0;width:3px;background:var(--accent);opacity:.85}
.stat b{font-size:27px!important;letter-spacing:-.035em!important;color:var(--primary)!important}.stat span{color:var(--muted)!important}
.tableWrap{border-color:var(--line)!important;border-radius:14px!important;box-shadow:0 4px 14px rgba(9,19,23,.025)!important}
.table th{background:#f4f7f5!important;color:#43544d!important;font-weight:850!important;border-color:var(--line)!important}
.table td{border-color:#edf1ef!important;color:#273a33!important}
.themeCard{border-color:var(--line)!important;border-radius:16px!important;box-shadow:0 6px 18px rgba(9,19,23,.03)!important}
.themeCard.active{border-color:var(--accent)!important;box-shadow:0 0 0 2px rgba(0,191,174,.12)!important}.activeChip{background:#e6faf4!important;color:#087b6f!important}
.pill{background:#eef3f1!important;color:#4a5b54!important}.notice{background:#eaf7f1!important;color:#21624d!important}
.modalBack{background:rgba(3,10,12,.70)!important;backdrop-filter:blur(7px)!important}.modal{background:#f6f8f7!important;border:1px solid rgba(255,255,255,.20)!important;border-radius:22px!important;box-shadow:0 32px 90px rgba(0,0,0,.28)!important}
.modalTop{background:rgba(255,255,255,.92)!important;backdrop-filter:blur(16px)!important;border-color:var(--line)!important}.previewStage{background:linear-gradient(145deg,#e7ece9,#dce5e1)!important}
.empty{background:#fff!important;border-color:#c9d5cf!important}
#rohmatCashierSafe .cashierSurface,#rohmatCashierSafe .cashLayout{border-radius:16px!important}
#rohmatCashierSafe .cashPanel{border-radius:15px!important;box-shadow:0 6px 18px rgba(9,19,23,.035)!important}
#rohmatCashierSafe .cashBtn.primary{background:var(--primary)!important}
@media(max-width:1050px){.shell{grid-template-columns:210px minmax(0,1fr)!important}.content{padding:20px!important}}
@media(max-width:760px){
 .auth{grid-template-columns:1fr!important}.authBrand{display:none!important}.authPane{padding:16px!important}.shell{grid-template-columns:1fr!important}
 .sidebar{position:static!important;height:auto!important;padding:10px!important}.logo{display:flex!important}.mainNav{display:flex!important;overflow:auto!important}.mainNav button{min-width:max-content!important}
 .topbar{min-height:60px!important;padding:9px 14px!important}.content{padding:16px 12px 24px!important}.grid2,.grid3,.stats{grid-template-columns:1fr!important}
}
@media(prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
</style><!-- smart-order-admin-foodcode-v1 -->`;
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

export function canonicalizeAdminShell(html) {
  let out = ensureCashierIntegration(String(html || ''));
  out = out.split('Warung Nasi').join(BUSINESS_NAME);
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
  if (!out.includes('smart-order-admin-foodcode-v1')) {
    out = out.replace(/<\/head>/i, FUTURE_ADMIN_UI_PATCH + '</head>');
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
        'x-sdb-tenant-id': tenantId,
        apikey: String(process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || ''),
        Authorization: 'Bearer ' + String(process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '')
      }
    });
    const payload = await upstream.json();
    const html = String(payload?.html || '');
    if (!validateRendererPayload(upstream.ok, payload, html)) {
      throw new Error('invalid_admin_renderer_response');
    }
    const body = canonicalizeAdminShell(html);
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
