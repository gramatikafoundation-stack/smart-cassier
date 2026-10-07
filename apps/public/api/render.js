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
export const FUTURE_PUBLIC_UI_PATCH = String.raw`<style id="smart-order-public-foodcode-v1">
:root{
 --so-bg:#f5f7f6;--so-surface:#fff;--so-soft:#eef3f1;--so-dark:#091317;--so-dark2:#10201d;
 --so-ink:#14231e;--so-muted:#70807a;--so-line:#dfe7e3;--so-teal:#00bfae;--so-mint:#31d6a6;
 --so-warm:#c87942;--so-ok:#23976e;--so-shadow:0 18px 48px rgba(9,19,23,.08);--so-shadow-sm:0 8px 24px rgba(9,19,23,.055)
}
html{background:var(--so-bg)!important}
body{
 background:radial-gradient(circle at 86% -10%,rgba(0,191,174,.08),transparent 31rem),linear-gradient(180deg,#fafcfb 0%,var(--so-bg) 100%)!important;
 color:var(--so-ink)!important;font-family:Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif!important;letter-spacing:-.005em
}
button,input,select,textarea{font-family:inherit!important}
button{transition:transform .16s ease,box-shadow .16s ease,background-color .16s ease,border-color .16s ease}
button:not(:disabled):hover{transform:translateY(-1px)}
button:focus-visible,input:focus-visible,textarea:focus-visible,select:focus-visible{outline:3px solid rgba(0,191,174,.2)!important;outline-offset:2px!important}
.w{width:min(1180px,calc(100% - 32px))!important}
.hero{min-height:100svh!important;padding:28px!important;background:transparent!important}
.welcome{
 width:min(1180px,100%)!important;grid-template-columns:minmax(0,1.08fr) minmax(420px,.92fr)!important;
 border:1px solid rgba(16,32,29,.08)!important;border-radius:30px!important;overflow:hidden!important;background:var(--so-surface)!important;
 box-shadow:0 32px 80px rgba(9,19,23,.11)!important
}
.photo{min-height:600px!important;background:var(--so-dark)!important;position:relative!important;isolation:isolate}
.photo:after{content:"";position:absolute;inset:0;z-index:2;pointer-events:none;background:linear-gradient(180deg,transparent 45%,rgba(9,19,23,.2) 100%)}
.photo img{filter:saturate(.94) contrast(1.02)!important}
.copy{padding:clamp(34px,5vw,62px)!important;justify-content:center!important;gap:5px!important;background:#fff!important}
.brand{
 font-family:Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif!important;color:var(--so-dark)!important;
 font-size:clamp(42px,5.3vw,68px)!important;line-height:.98!important;letter-spacing:-.055em!important;font-weight:800!important;margin:0 0 16px!important
}
.ey{color:var(--so-warm)!important;font-size:.7rem!important;letter-spacing:.18em!important;font-weight:900!important}
.muted{color:var(--so-muted)!important}
.opts{gap:10px!important;margin:22px 0 14px!important}
.opt{border:1px solid var(--so-line)!important;border-radius:15px!important;padding:14px 15px!important;background:#fff!important}
.opt:hover{border-color:#c8d5cf!important;box-shadow:var(--so-shadow-sm)!important}
.opt.on{border-color:rgba(0,191,174,.5)!important;background:#effaf7!important;box-shadow:inset 3px 0 var(--so-teal)!important}
.field{gap:7px!important;margin:13px 0!important}
.field label{font-size:.82rem!important;color:#40524b!important;font-weight:780!important}
.field input,.field textarea,.field select{border:1px solid var(--so-line)!important;border-radius:12px!important;background:#fff!important;color:var(--so-ink)!important;min-height:46px!important;padding:11px 13px!important}
.btn{border-radius:12px!important;min-height:44px!important;padding:11px 15px!important;font-weight:820!important}
.pri{background:var(--so-dark2)!important;color:#fff!important;box-shadow:0 8px 18px rgba(9,19,23,.14)!important}
.accent{background:var(--so-teal)!important;color:#052823!important;box-shadow:0 8px 18px rgba(0,191,174,.16)!important}
.soft{background:#f2f5f3!important;color:var(--so-dark2)!important;border:1px solid var(--so-line)!important}
.head{background:rgba(255,255,255,.91)!important;backdrop-filter:blur(18px) saturate(150%)!important;border-bottom:1px solid rgba(16,32,29,.08)!important;position:sticky!important;top:0!important;z-index:28!important}
.headin{min-height:76px!important;gap:14px!important}
.headin .brand{font-size:clamp(22px,3vw,31px)!important;letter-spacing:-.04em!important;margin:0!important}
.badge{background:var(--so-dark2)!important;color:#fff!important;border:1px solid var(--so-dark2)!important;padding:8px 12px!important;border-radius:999px!important;font-size:.78rem!important}
.cats{top:76px!important;background:rgba(245,247,246,.91)!important;backdrop-filter:blur(16px)!important;border-bottom:1px solid rgba(16,32,29,.07)!important}
.catin{gap:8px!important;padding:11px 0!important}
.cat{background:rgba(255,255,255,.94)!important;border:1px solid var(--so-line)!important;color:#42534d!important;padding:9px 15px!important;border-radius:999px!important;font-weight:760!important}
.cat.on{background:var(--so-dark2)!important;border-color:var(--so-dark2)!important;color:#fff!important;box-shadow:0 6px 16px rgba(9,19,23,.10)!important}
.grid{grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:18px!important;padding:26px 0 130px!important}
.grid .card{
 background:var(--so-surface)!important;border:1px solid rgba(16,32,29,.085)!important;border-radius:20px!important;
 box-shadow:var(--so-shadow-sm)!important;transition:transform .18s ease,box-shadow .18s ease,border-color .18s ease!important
}
.grid .card:hover{transform:translateY(-3px)!important;box-shadow:var(--so-shadow)!important;border-color:rgba(0,191,174,.22)!important}
.grid .food,.grid .food img{border-radius:15px!important;background:#e7ece9!important}
.grid .body{padding:14px 10px 9px!important}
.grid .body h3{font-size:1.02rem!important;letter-spacing:-.015em!important;color:var(--so-dark)!important}
.price{color:var(--so-warm)!important;font-weight:900!important}
.grid .foot{gap:10px!important}
.grid .foot .btn{min-height:38px!important;border-radius:10px!important}
.grid .qty{border:1px solid var(--so-line)!important;background:#f6f8f7!important;border-radius:10px!important}
.grid .qty button{background:#eef4f1!important;color:var(--so-dark2)!important}
.cart{background:transparent!important;padding:0 14px 14px!important;pointer-events:none!important}
.cartgo{
 pointer-events:auto!important;width:min(760px,100%)!important;background:rgba(9,19,23,.97)!important;color:#fff!important;
 border:1px solid rgba(255,255,255,.10)!important;border-radius:17px!important;padding:14px 18px!important;
 box-shadow:0 20px 48px rgba(9,19,23,.28)!important;backdrop-filter:blur(18px)!important
}
.modal::backdrop{background:rgba(3,10,12,.72)!important;backdrop-filter:blur(7px)!important}
.box{background:#fff!important;border:1px solid rgba(255,255,255,.2)!important;border-radius:22px!important;padding:22px!important;box-shadow:0 30px 90px rgba(0,0,0,.28)!important}
.line{border-color:var(--so-line)!important}
.checkout{padding:28px 0 58px!important}
.steps{gap:8px!important}.step{background:#e8eeeb!important;color:#77837e!important;border-radius:12px!important}
.step.on{background:#e6faf4!important;color:#087b6f!important;font-weight:900!important}.step.done{background:var(--so-dark2)!important;color:#fff!important}
.panel{background:#fff!important;border:1px solid rgba(16,32,29,.08)!important;border-radius:20px!important;padding:22px!important;box-shadow:var(--so-shadow-sm)!important}
.panel h2{color:var(--so-dark)!important;letter-spacing:-.035em!important}
.identity{background:#f4f7f5!important;border-color:var(--so-line)!important;border-radius:14px!important}
.totalbig{border-color:var(--so-line)!important}
.payroom{background:linear-gradient(145deg,#0a171a 0%,#102c27 100%)!important;color:#fff!important;border-color:#163e36!important;box-shadow:0 24px 56px rgba(9,19,23,.18)!important}
.qrisbox{border-radius:16px!important;background:#fff!important;color:var(--so-dark)!important}
.num{background:var(--so-teal)!important;color:#062521!important}
.confirm,.proof{background:rgba(255,255,255,.075)!important;border:1px solid rgba(255,255,255,.08)!important}
.status{background:#e9f7f1!important;color:#155a47!important;border:1px solid #cdeade!important}
.success .code{color:var(--so-dark)!important;letter-spacing:-.04em!important}
@media(max-width:900px){.welcome{grid-template-columns:1fr!important}.photo{min-height:360px!important}.copy{padding:30px!important}.grid{grid-template-columns:repeat(2,minmax(0,1fr))!important}}
@media(max-width:560px){
 .hero{padding:12px!important}.welcome{border-radius:22px!important}.photo{min-height:240px!important}.copy{padding:24px 20px 26px!important}
 .brand{font-size:clamp(36px,12vw,50px)!important}.w{width:min(100% - 20px,1180px)!important}.headin{min-height:68px!important}.cats{top:68px!important}
 .grid{grid-template-columns:1fr!important;gap:14px!important;padding-top:18px!important}.grid .card{border-radius:17px!important}
 .grid .food,.grid .food img{border-radius:12px!important}.cart{padding:0 10px 10px!important}.cartgo{border-radius:14px!important}.panel{padding:18px!important;border-radius:18px!important}
}
@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important;transition:none!important;animation:none!important}}

/* smart-order-reference-exact-public-v2 */
:root{
 --so-bg:#f3e6de!important;--so-surface:#fffaf7!important;--so-soft:#f8efe9!important;
 --so-dark:#1c1714!important;--so-dark2:#211b18!important;--so-ink:#2d2521!important;
 --so-muted:#8b7d76!important;--so-line:#eadbd2!important;--so-teal:#ff5a24!important;
 --so-mint:#ff7b45!important;--so-warm:#ff4f1f!important;--so-ok:#52a55a!important;
}
html{background:#f3e6de!important}
body{
  background:
    radial-gradient(circle at 50% -10%,rgba(255,255,255,.82),transparent 24rem),
    linear-gradient(180deg,#f6ece6 0%,#f1dfd5 100%)!important;
  color:#2d2521!important
}
.w{width:min(1040px,calc(100% - 24px))!important}
.hero{padding:18px!important;background:transparent!important}
.welcome{
  width:min(980px,100%)!important;grid-template-columns:minmax(0,.9fr) minmax(360px,1.1fr)!important;
  border:1px solid rgba(115,76,58,.10)!important;border-radius:22px!important;background:#fffaf7!important;
  box-shadow:0 24px 60px rgba(105,67,49,.15)!important
}
.photo{min-height:500px!important;background:#eadbd1!important}
.photo:after{background:linear-gradient(180deg,transparent 58%,rgba(86,48,32,.10) 100%)!important}
.copy{padding:38px!important;background:#fffaf7!important}
.brand{
  color:#271f1b!important;font-size:clamp(38px,5vw,58px)!important;letter-spacing:-.05em!important;line-height:.98!important
}
.ey{color:#ff5a24!important}.muted{color:#8c7f78!important}
.opt{border-color:#eadfd8!important;border-radius:12px!important;background:#fff!important}
.opt.on{border-color:#ff8b63!important;background:#fff4ee!important;box-shadow:inset 3px 0 #ff5a24!important}
.field input,.field textarea,.field select{border-color:#eadfd8!important;border-radius:10px!important;background:#fff!important;color:#2d2521!important}
.btn{border-radius:10px!important}
.pri,.accent{background:#ff5a24!important;color:#fff!important;box-shadow:none!important}
.soft{background:#fff!important;color:#4e4039!important;border-color:#eadfd8!important}
.head{background:rgba(255,250,247,.95)!important;border-color:#eadfd8!important;backdrop-filter:blur(12px)!important}
.headin{min-height:66px!important}.headin .brand{font-size:24px!important;color:#251e1a!important}
.badge{background:#fff0e8!important;color:#d84b1d!important;border-color:#ffd6c6!important}
.cats{top:66px!important;background:rgba(246,236,230,.96)!important;border-color:#eadfd8!important}
.catin{padding:8px 0!important;gap:6px!important}
.cat{padding:7px 11px!important;border-radius:8px!important;background:#fff!important;border-color:#eadfd8!important;color:#6a5b53!important;font-size:12px!important}
.cat.on{background:#ff5a24!important;border-color:#ff5a24!important;color:#fff!important;box-shadow:none!important}
.grid{
  grid-template-columns:repeat(4,minmax(0,1fr))!important;gap:10px!important;padding:15px 0 100px!important
}
.grid .card{
  background:#fffaf7!important;border:1px solid #eadfd8!important;border-radius:14px!important;
  box-shadow:0 7px 18px rgba(97,61,45,.06)!important;padding:9px!important
}
.grid .card:hover{transform:translateY(-2px)!important;border-color:#f1c7b7!important;box-shadow:0 10px 22px rgba(97,61,45,.09)!important}
.grid .food{
  width:min(100%,116px)!important;aspect-ratio:1!important;margin:3px auto 7px!important;border-radius:999px!important;
  background:#f2e7e0!important;overflow:hidden!important
}
.grid .food img{
  width:100%!important;height:100%!important;aspect-ratio:1!important;border-radius:999px!important;
  object-fit:cover!important
}
.grid .body{padding:3px 3px 1px!important;text-align:left!important}
.grid .body h3{font-size:12px!important;line-height:1.25!important;color:#2a221e!important;margin:0 0 3px!important}
.grid .body p{font-size:10px!important;color:#8e817a!important;line-height:1.35!important}
.price{color:#ff5a24!important;font-size:11px!important}
.grid .foot{gap:5px!important;margin-top:6px!important}.grid .foot .btn{min-height:30px!important;padding:5px 7px!important;font-size:10px!important}
.grid .qty{border-color:#eadfd8!important;background:#fff!important;border-radius:7px!important}
.grid .qty button{background:#fff3ed!important;color:#d84b1d!important}
.cart{padding:7px 10px 10px!important;background:transparent!important}
.cartgo{
  width:min(540px,100%)!important;background:#ff5a24!important;color:#fff!important;border:0!important;border-radius:10px!important;
  padding:11px 14px!important;box-shadow:0 12px 28px rgba(214,70,20,.24)!important
}
.box,.panel{background:#fffaf7!important;border-color:#eadfd8!important;border-radius:16px!important;box-shadow:0 16px 36px rgba(97,61,45,.10)!important}
.step{background:#f2e8e2!important;color:#91817a!important;border-radius:9px!important}.step.on{background:#fff0e8!important;color:#d84b1d!important}.step.done{background:#ffe1d4!important;color:#b53b15!important}
.identity{background:#f8efe9!important;border-color:#eadfd8!important;border-radius:10px!important}
.payroom{
  background:#fffaf7!important;color:#2d2521!important;border-color:#eadfd8!important;box-shadow:0 16px 36px rgba(97,61,45,.10)!important
}
.payroom h2,.payroom h3{color:#2d2521!important}.payroom p{color:#8a7c74!important}
.qrisbox{background:#fff!important;color:#2d2521!important;border:1px solid #eadfd8!important;border-radius:12px!important}
.num{background:#ff5a24!important;color:#fff!important}.confirm,.proof{background:#fff4ee!important;border-color:#ffd8c8!important}
.status{background:#eff8ef!important;color:#3f7c45!important;border-color:#cfe8d1!important}
@media(max-width:900px){.welcome{grid-template-columns:1fr!important}.photo{min-height:320px!important}.grid{grid-template-columns:repeat(3,minmax(0,1fr))!important}}
@media(max-width:560px){
 .hero{padding:10px!important}.welcome{border-radius:18px!important}.photo{min-height:220px!important}.copy{padding:22px 18px!important}
 .headin{min-height:60px!important}.cats{top:60px!important}.grid{grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:8px!important;padding-top:12px!important}
 .grid .card{padding:7px!important;border-radius:12px!important}.grid .food{width:min(100%,104px)!important}
 .grid .body h3{font-size:11px!important}.grid .body p{font-size:9px!important}.cartgo{border-radius:9px!important}
}

</style><!-- smart-order-public-foodcode-v1 -->`;

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

/* smart-order-mobile-checkout-scroll-v1 */
html.soCheckoutScrollFix,body.soCheckoutScrollFix{
 height:auto!important;min-height:100%!important;max-height:none!important;
 overflow-x:hidden!important;overflow-y:auto!important;
 position:static!important;inset:auto!important;
 touch-action:pan-y!important;overscroll-behavior-y:auto!important;
 -webkit-overflow-scrolling:touch!important
}
html.soCheckoutScrollFix #app,body.soCheckoutScrollFix #app{
 height:auto!important;min-height:100dvh!important;max-height:none!important;
 overflow:visible!important;touch-action:pan-y!important
}
body.soCheckoutScrollFix .checkout{
 height:auto!important;min-height:100dvh!important;max-height:none!important;
 overflow:visible!important;touch-action:pan-y!important
}

/* smart-order-premium-public-v3 */
body{background:linear-gradient(180deg,#fbf8f6 0%,#f3e8e2 100%)!important}
.head{box-shadow:0 8px 24px rgba(61,42,33,.055)!important}
.headin{min-height:70px!important}.headin .brand{font-size:26px!important;font-weight:850!important}
.badge{padding:8px 12px!important;font-size:12px!important;font-weight:800!important}
.cats{top:70px!important}.cat{min-height:38px!important;padding:8px 13px!important;border-radius:10px!important;font-size:12px!important}
.grid{gap:14px!important;padding-top:20px!important}
.grid .card{border-radius:16px!important;padding:7px!important;box-shadow:0 8px 22px rgba(72,49,38,.07)!important}
.grid .food,.grid .food img{border-radius:11px!important}
.grid .body{padding:11px 7px 7px!important}.grid .body h3{font-size:14px!important;letter-spacing:-.012em!important;margin-bottom:6px!important}
.grid .body p{font-size:11px!important;line-height:1.45!important}.price{font-size:13px!important}
.grid .foot .btn{min-height:40px!important;padding:8px 11px!important;font-size:12px!important;font-weight:800!important}
.grid .qty button{width:38px!important;height:38px!important}
.cartgo{border-radius:15px!important;padding:13px 16px!important;background:#211b18!important;box-shadow:0 18px 42px rgba(57,36,27,.23)!important}
.box,.panel{border-radius:18px!important;box-shadow:0 18px 44px rgba(76,51,39,.10)!important}
.field input,.field textarea,.field select{min-height:46px!important;font-size:14px!important}
@media(max-width:560px){.headin{min-height:62px!important}.cats{top:62px!important}.grid{gap:10px!important}.grid .body h3{font-size:13px!important}.grid .foot .btn{min-height:38px!important}}
</style><script id="rohmat-menu-single-media-v6">(()=>{'use strict';if(window.__rohmatMenuSingleMediaV6)return;window.__rohmatMenuSingleMediaV6=1;const NAME_KEY='rohmat-customer-name-v2';function readName(){try{return String(localStorage.getItem(NAME_KEY)||'').trim().slice(0,60)}catch{return''}}function saveName(v){v=String(v||'').trim().slice(0,60);if(!v)return;try{localStorage.setItem(NAME_KEY,v)}catch{}}function bindName(){const n=document.getElementById('name');if(!n)return;const saved=readName();if(!String(n.value||'').trim()&&saved){n.value=saved;n.dispatchEvent(new Event('input',{bubbles:true}));n.dispatchEvent(new Event('change',{bubbles:true}))}if(n.dataset.rohmatRememberName==='1')return;n.dataset.rohmatRememberName='1';const persist=()=>saveName(n.value);n.addEventListener('input',persist);n.addEventListener('change',persist);n.addEventListener('blur',persist)}function cleanMedia(){document.querySelectorAll('.grid .food').forEach(food=>{food.style.setProperty('aspect-ratio','70 / 41','important');food.style.setProperty('padding','0','important');food.style.setProperty('overflow','hidden','important');food.style.setProperty('background','#c79666','important');food.style.removeProperty('--rohmat-menu-bg')});document.querySelectorAll('.grid .food img').forEach(img=>{img.style.setProperty('background-image','none','important');img.style.setProperty('background','#c79666','important');img.style.setProperty('object-fit','cover','important');img.style.setProperty('object-position','center','important');img.style.setProperty('width','100%','important');img.style.setProperty('height','100%','important');img.style.setProperty('padding','0','important');img.style.setProperty('margin','0','important')})}function patch(){bindName();cleanMedia();const checkout=!!document.querySelector('.checkout');document.documentElement.classList.toggle('soCheckoutScrollFix',checkout);document.body?.classList.toggle('soCheckoutScrollFix',checkout);document.documentElement.dataset.rohmatMenuReference='v6-reference-70x41'}let queued=false;function schedule(){if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;setTimeout(patch,0)})}document.addEventListener('rohmat:dom-updated',schedule);window.addEventListener('pageshow',schedule);const app=document.getElementById('app');if(app)new MutationObserver(schedule).observe(app,{childList:true,subtree:true});document.addEventListener('click',e=>{if(e.target.closest('#confirm,#pay,#close,.cat,[data-id]')){schedule();setTimeout(schedule,80);setTimeout(schedule,300)};if(e.target.closest('#pay')){const n=document.getElementById('name');if(n)saveName(n.value)}},true);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(patch,0),{once:true});else setTimeout(patch,0)})();</script><!-- rohmat-menu-single-media-v6 -->`;

const SDB_PARENT_SIGNATURE = String.raw`<style id="sdb-parent-brand-public-v1">
.sdbParentSignaturePublic{display:flex;justify-content:center;align-items:center;padding:18px 16px 24px;border-top:1px solid rgba(20,35,30,.08);background:transparent}
.sdbParentSignaturePublic a{display:inline-flex;align-items:center;gap:10px;min-height:44px;padding:5px 10px;border-radius:12px;color:color-mix(in srgb,var(--ds-muted,var(--so-muted,#70807a)) 80%,var(--ds-text,#24362F) 20%);font-size:11px;font-weight:760;letter-spacing:.01em;opacity:1;transition:transform .18s ease,background-color .18s ease}
.sdbParentSignaturePublic a:hover{transform:translateY(-1px);background:rgba(255,255,255,.62)}
.sdbParentSignaturePublic a:focus-visible{outline:3px solid rgba(0,191,174,.22);outline-offset:2px}
.sdbParentSignaturePublic img{width:54px;height:54px;object-fit:contain;border-radius:11px;display:block;background:#fff;box-shadow:0 5px 18px rgba(9,19,23,.08)}
@media(max-width:560px){.sdbParentSignaturePublic{padding:14px 12px 20px}.sdbParentSignaturePublic img{width:48px;height:48px}}
@media(prefers-reduced-motion:reduce){.sdbParentSignaturePublic a{transition:none}}
</style><footer class="sdbParentSignaturePublic" data-sdb-parent-signature="public"><a href="https://smart-digital-for-business.vercel.app/" target="_blank" rel="noopener noreferrer" aria-label="Kunjungi Smart Digital for Business"><span>Bagian dari</span><img src="/sdb-parent-brand.jpg?v=20261007-official-logo" alt="Smart Digital for Business" loading="lazy" decoding="async"></a></footer><!-- sdb-parent-brand-public-v1 -->`;

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
  let out = html;
  const add = (source, patch) => {
    const at = source.lastIndexOf('</body>');
    return at >= 0 ? source.slice(0, at) + patch + source.slice(at) : source + patch;
  };
  if (!out.includes('rohmat-menu-single-media-v6')) out = add(out, PUBLIC_UX_PATCH);
  if (!out.includes('smart-order-public-foodcode-v1')) out = add(out, FUTURE_PUBLIC_UI_PATCH);
  if (!out.includes('sdb-parent-brand-public-v1')) out = add(out, SDB_PARENT_SIGNATURE);
  return out;
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
  out = out.replace(/"business_name":"[^"]*"/, '"business_name":' + JSON.stringify(safeBusiness));
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
  const tenant = req?.__sdbPublicTenantConfig || await resolvePublicTenantConfig(req);
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
    res.setHeader('CDN-Cache-Control', 'public, s-maxage=300, stale-while-revalidate=60');
    res.setHeader('Vercel-CDN-Cache-Control', 'public, s-maxage=300, stale-while-revalidate=60');
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
    res.setHeader('X-Rohmat-Public-CDN', 'vercel-300-swr60');
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
