// master-prototype-final-preview-marker: 2026-09-20
import { randomBytes } from 'node:crypto';
import { resolvePublicTenantConfig, escapeHtml } from '../lib/tenant-config.js';

const REQUIRED_PLATFORM_ENV = ['SUPABASE_URL','PUBLIC_LKG_PATH'];
const MIN_LKG_BYTES = 78000;
const REQUIRED_MARKERS = [
  'rohmat-public-element-runtime-v64',
  'rohmat-cart-qris-runtime-v72',
  'rohmat-ocr-smart-v6',
  'OCR_HARD_DEADLINE_MS=4950',
  'ocr-working-feedback-v77',
  'verification-ui-v77',
  'rohmat-public-bundle-v29',
  'rohmat-checkout-snapshot-v30',
  'menu-image-natural-full-v59',
  'menu-image-full-precision-v61',
  'payment-verification-generic-v62',
  'menu-image-safe-inset-v63',
  'menu-image-gallery-v65',
  'verification-copy-v66',
  'Bukti pembayaran lulus uji verifikasi.'
];

const OCR_PRECONNECT = '<link data-rohmat-ocr-preconnect="v4" rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin><link rel="dns-prefetch" href="//cdn.jsdelivr.net"><link rel="preconnect" href="https://tessdata.projectnaptha.com" crossorigin><link rel="dns-prefetch" href="//tessdata.projectnaptha.com">';
const MENU_IMG_EAGER = `<img src="'+esc(pic(m))+'" alt="'+esc(m.name)+'">`;
const MENU_IMG_LAZY = `<img src="'+esc(pic(m))+'" alt="'+esc(m.name)+'" loading="lazy" decoding="async">`;
const DIALOG_TIMER_OLD = `let intentionalOpen=false;\nfunction hardenMenu(){\n  const dlg=document.getElementById('dlg');\n  if(dlg&&!dlg.classList.contains('user-open')&&dlg.hasAttribute('open')){try{dlg.close()}catch{dlg.removeAttribute('open')}}\n  const confirm=document.getElementById('confirm');\n  if(confirm&&!confirm.dataset.safeBound){confirm.dataset.safeBound='1';confirm.addEventListener('click',()=>{intentionalOpen=true;setTimeout(()=>{intentionalOpen=false},1200)},{capture:true})}\n}`;
const DIALOG_TIMER_NEW = `function hardenMenu(){\n  const dlg=document.getElementById('dlg');\n  if(dlg&&!dlg.classList.contains('user-open')&&dlg.hasAttribute('open')){try{dlg.close()}catch{dlg.removeAttribute('open')}}\n}`;
const DEAD_PROOF_GATE = 'let pending=false,criticalBad=false,amountDiff=0;';

const PUBLIC_UX_PATCH = String.raw`<style id="rohmat-menu-single-media-v6-style">
.grid{align-items:stretch!important;gap:16px!important}
.grid .card{display:flex!important;flex-direction:column!important;height:100%!important;padding:6px!important;overflow:hidden!important;border-radius:13px!important;background:#fffdf8!important;border:1px solid rgba(49,83,67,.10)!important;box-shadow:0 4px 14px rgba(35,55,47,.055)!important}
.grid .food{display:block!important;overflow:hidden!important;width:100%!important;height:auto!important;aspect-ratio:70/41!important;padding:0!important;margin:0!important;background:#c79666!important;border:0!important;border-radius:9px!important}
.grid .food::before,.grid .food::after{display:none!important;content:none!important}
.grid .food img{display:block!important;position:static!important;width:100%!important;height:100%!important;max-width:none!important;max-height:none!important;aspect-ratio:auto!important;object-fit:cover!important;object-position:center!important;margin:0!important;padding:0!important;border:0!important;border-radius:9px!important;box-shadow:none!important;filter:none!important;transform:none!important;background:#c79666!important;background-image:none!important}
.grid .body{display:flex!important;flex-direction:column!important;flex:1 1 auto!important;padding:10px 5px 5px!important}
.grid .body h3{margin:0 0 8px!important;line-height:1.25!important}
.grid .foot{margin-top:auto!important;gap:8px!important;align-items:center!important}
.grid .foot .btn{min-height:36px!important;padding:7px 10px!important;border-radius:9px!important}
.grid .qty{border-radius:9px!important}
.grid .qty button{width:34px!important;height:34px!important}
@media(max-width:560px){.grid .card{padding:5px!important}.grid .body{padding:9px 5px 5px!important}.grid .food{aspect-ratio:70/41!important}}
</style><script id="rohmat-menu-single-media-v6">(()=>{'use strict';if(window.__rohmatMenuSingleMediaV6)return;window.__rohmatMenuSingleMediaV6=1;const NAME_KEY='rohmat-customer-name-v2';function readName(){try{return String(localStorage.getItem(NAME_KEY)||'').trim().slice(0,60)}catch{return''}}function saveName(v){v=String(v||'').trim().slice(0,60);if(!v)return;try{localStorage.setItem(NAME_KEY,v)}catch{}}function bindName(){const n=document.getElementById('name');if(!n)return;const saved=readName();if(!String(n.value||'').trim()&&saved){n.value=saved;n.dispatchEvent(new Event('input',{bubbles:true}));n.dispatchEvent(new Event('change',{bubbles:true}))}if(n.dataset.rohmatRememberName==='1')return;n.dataset.rohmatRememberName='1';const persist=()=>saveName(n.value);n.addEventListener('input',persist);n.addEventListener('change',persist);n.addEventListener('blur',persist)}function cleanMedia(){document.querySelectorAll('.grid .food').forEach(food=>{food.style.setProperty('aspect-ratio','70 / 41','important');food.style.setProperty('padding','0','important');food.style.setProperty('overflow','hidden','important');food.style.setProperty('background','#c79666','important');food.style.removeProperty('--rohmat-menu-bg')});document.querySelectorAll('.grid .food img').forEach(img=>{img.style.setProperty('background-image','none','important');img.style.setProperty('background','#c79666','important');img.style.setProperty('object-fit','cover','important');img.style.setProperty('object-position','center','important');img.style.setProperty('width','100%','important');img.style.setProperty('height','100%','important');img.style.setProperty('padding','0','important');img.style.setProperty('margin','0','important')})}function patch(){bindName();cleanMedia();document.documentElement.dataset.rohmatMenuReference='v6-reference-70x41'}let queued=false;function schedule(){if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;setTimeout(patch,0)})}const app=document.getElementById('app')||document.documentElement;new MutationObserver(schedule).observe(app,{childList:true,subtree:true});document.addEventListener('rohmat:dom-updated',schedule);document.addEventListener('click',e=>{if(e.target.closest('#confirm,#pay,#close,.cat,[data-id]'))schedule();if(e.target.closest('#pay')){const n=document.getElementById('name');if(n)saveName(n.value)}},true);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(patch,0),{once:true});else setTimeout(patch,0)})();</script><!-- rohmat-menu-single-media-v6 -->`;

function countOccurrences(text, needle) {
  if (!needle) return 0;
  return text.split(needle).length - 1;
}

function removeScriptContaining(html, needle) {
  const at = html.indexOf(needle);
  if (at < 0) return { html, removed: false };
  const start = html.lastIndexOf('<script', at);
  const end = html.indexOf('</script>', at);
  if (start < 0 || end < 0) return { html, removed: false };
  return { html: html.slice(0, start) + html.slice(end + '</script>'.length), removed: true };
}

function optimizeHtml(html) {
  const flags = [];
  let out = html;
  if (countOccurrences(out, OCR_PRECONNECT) === 1) { out = out.replace(OCR_PRECONNECT, ''); flags.push('ocr-preconnect-deferred'); }
  if (countOccurrences(out, MENU_IMG_EAGER) === 1) { out = out.replace(MENU_IMG_EAGER, MENU_IMG_LAZY); flags.push('menu-images-lazy'); }
  if (countOccurrences(out, DIALOG_TIMER_OLD) === 1) { out = out.replace(DIALOG_TIMER_OLD, DIALOG_TIMER_NEW); flags.push('dead-dialog-timer-removed'); }
  if (countOccurrences(out, DEAD_PROOF_GATE) === 1) { const result = removeScriptContaining(out, DEAD_PROOF_GATE); if (result.removed) { out = result.html; flags.push('dead-proof-gate-removed'); } }
  return { html: out, flags };
}

function injectPublicPatch(html) {
  if (html.includes('rohmat-menu-single-media-v6')) return html;
  const at = html.lastIndexOf('</body>');
  return at >= 0 ? html.slice(0, at) + PUBLIC_UX_PATCH + html.slice(at) : html + PUBLIC_UX_PATCH;
}

function secureHtml(html, nonce) {
  return html.replace(/<script(?=\s|>)/g, `<script nonce="${nonce}"`).replace(/<style(?=\s|>)/g, `<style nonce="${nonce}"`);
}

function tenantizeRuntimeHtml(html, tenantId, businessName, heroImageUrl = '') {
  const safeTenant = String(tenantId || '').trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(safeTenant)) {
    throw new Error('invalid_tenant_id');
  }
  const safeBusiness = String(businessName || 'Business').trim() || 'Business';
  const tenantBusinessMarker = '<span data-tenant-business hidden>' + escapeHtml(safeBusiness) + '</span>';
  let out = html;
  if (/<span\s+data-tenant-business\s+hidden>[^<]*<\/span>/i.test(out)) {
    out = out.replace(/<span\s+data-tenant-business\s+hidden>[^<]*<\/span>/i, tenantBusinessMarker);
  } else {
    out = out.replace(/(<body\b[^>]*>)/i, match => match + tenantBusinessMarker);
  }
  out = out.replace(/"merchant_name":"[^"]*"/, '"merchant_name":' + JSON.stringify(safeBusiness));
  const hero = String(heroImageUrl || '').trim();
  if (/^https:\/\//i.test(hero)) {
    out = out.replace(/"hero_image_url":"[^"]*"/, '"hero_image_url":' + JSON.stringify(hero));
  }
  out = out.replace(
    /site_settings_public_v2\?select=([^"'\s]+?)&id=eq\.1&limit=1/g,
    (_m, fields) => `tenant_site_settings_public_v1?select=${fields}&tenant_id=eq.${safeTenant}&limit=1`
  );
  out = out.replace(
    /headers:\{apikey:K,Authorization:'Bearer '\+K(?=,|\})/g,
    `headers:{apikey:K,Authorization:'Bearer '+K,'x-sdb-tenant-id':'${safeTenant}'`
  );
  out = out.replace(
    /(src=["'][^"']*\/functions\/v1\/rohmat-public-element-runtime-v64)(\?[^"']*)?(["'])/g,
    (_m, base, query, quote) => {
      const q = String(query || '');
      if (/([?&])tenant=/.test(q)) return base + q + quote;
      return base + (q ? q + '&tenant=' + safeTenant : '?tenant=' + safeTenant) + quote;
    }
  );
  return out;
}

function securityHeaders(nonce, supabaseOrigin) {
  return {
    'Content-Security-Policy': [
      "default-src 'self'",
      `script-src 'self' 'nonce-${nonce}' 'wasm-unsafe-eval' ${supabaseOrigin} https://cdn.jsdelivr.net`,
      "script-src-attr 'none'",
      `style-src 'self' 'nonce-${nonce}'`,
      "style-src-attr 'unsafe-inline'",
      `img-src 'self' data: blob: ${supabaseOrigin}`,
      `connect-src 'self' ${supabaseOrigin} https://cdn.jsdelivr.net https://tessdata.projectnaptha.com`,
      "worker-src 'self' blob:",
      "child-src blob:",
      "font-src 'self' data:",
      "media-src 'none'",
      "object-src 'none'",
      "frame-src 'none'",
      "base-uri 'self'",
      "frame-ancestors 'none'",
      "form-action 'self'",
      "upgrade-insecure-requests"
    ].join('; '),
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Origin-Agent-Cluster': '?1',
    'X-Permitted-Cross-Domain-Policies': 'none'
  };
}

export default async function handler(req, res) {
  const missingPlatform = REQUIRED_PLATFORM_ENV.filter(key => !String(process.env[key] || '').trim());
  if (missingPlatform.length) {
    res.statusCode = 503;
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    return res.end('platform_configuration_incomplete:' + missingPlatform.join(','));
  }
  const tenant = await resolvePublicTenantConfig(req);
  if (!tenant.ok || !tenant.tenantId) {
    res.statusCode = 503;
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    return res.end('tenant_resolution_failed:' + (tenant.missing || []).join(','));
  }
  const tenantId = String(tenant.tenantId);
  const base = String(process.env.SUPABASE_URL).trim().replace(/\/$/, '');
  const lkgPath = String(process.env.PUBLIC_LKG_PATH).trim();
  const businessName = String(tenant.businessName || 'Business').trim();
  const heroImageUrl = String(tenant.heroImageUrl || '').trim();
  const supabaseOrigin = new URL(base).origin;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 2500);
  const nonce = randomBytes(18).toString('base64url');
  try {
    const upstream = await fetch(base + lkgPath, { cache: 'no-store', signal: controller.signal });
    const html = await upstream.text();
    const valid = upstream.ok && html.length >= MIN_LKG_BYTES && REQUIRED_MARKERS.every(marker => html.includes(marker));
    if (!valid) throw new Error('invalid_lkg');
    const tenantized = tenantizeRuntimeHtml(html, tenantId, businessName, heroImageUrl);
    const optimized = optimizeHtml(tenantized);
    const patched = injectPublicPatch(optimized.html);
    const body = secureHtml(patched, nonce);
    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=0, must-revalidate');
    res.setHeader('CDN-Cache-Control', 'public, s-maxage=60, stale-while-revalidate=60');
    res.setHeader('Vercel-CDN-Cache-Control', 'public, s-maxage=60, stale-while-revalidate=60');
    res.setHeader('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=(), usb=(), serial=()');
    for (const [key, value] of Object.entries(securityHeaders(nonce, supabaseOrigin))) res.setHeader(key, value);
    res.setHeader('X-Rohmat-Public', 'master-prototype-lkg-v1');
    res.setHeader('X-SDB-Tenant-ID', tenantId);
    res.setHeader('X-Rohmat-Public-OCR', 'smart-v6-target4s-fallback4.5-hard4.95-v77');
    res.setHeader('X-Rohmat-Public-CSP', 'nonce-v2-script-style');
    res.setHeader('X-Rohmat-Public-Bundle-Min', String(MIN_LKG_BYTES));
    res.setHeader('X-Rohmat-Public-CDN', 'vercel-60-swr60');
    res.setHeader('X-Rohmat-Public-Fix', 'menu-reference-v6-70x41-natural-juice-v7');
    res.setHeader('X-Rohmat-Public-Perf', optimized.flags.join(',') || 'baseline');
    res.setHeader('X-Rohmat-Public-Canonical-Identity', heroImageUrl ? 'resolver-brand+hero-v2' : 'resolver-brand-v2');
    res.setHeader('X-Rohmat-Public-Bytes-Saved', String(Math.max(0, html.length - optimized.html.length)));
    if (req.method === 'HEAD') return res.end();
    return res.end(body);
  } catch {
    res.statusCode = 503;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'");
    res.setHeader('X-Rohmat-Public', 'recovery-v14');
    if (req.method === 'HEAD') return res.end();
    const safeName = String(businessName).replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
    return res.end(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${safeName}</title><main style="font:16px system-ui;padding:32px;max-width:680px;margin:auto"><h1>${safeName}</h1><p>Situs sedang memulihkan koneksi. Silakan muat ulang beberapa saat lagi.</p></main>`);
  } finally { clearTimeout(timer); }
}
