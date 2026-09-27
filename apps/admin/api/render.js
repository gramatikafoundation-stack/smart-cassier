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

/* smart-order-reference-exact-admin-v2 */
:root{
  --bg:#f5f5f6!important;--panel:#ffffff!important;--panel2:#f7f7f8!important;
  --ink:#141414!important;--muted:#767676!important;--primary:#171717!important;
  --accent:#ff5a24!important;--line:#e6e7e9!important;--radius:9px!important;
}
html,body{background:#f5f5f6!important;color:#141414!important;font-size:13px!important}
body{background:#f5f5f6!important}
.shell{grid-template-columns:164px minmax(0,1fr)!important;min-height:100vh!important}
.sidebar{
  background:#fff!important;color:#1c1c1c!important;padding:10px 8px!important;gap:8px!important;
  border-right:1px solid #e5e6e8!important;box-shadow:none!important
}
.logo{padding:7px 7px 10px!important;gap:8px!important}
.logoMark{
  width:28px!important;height:28px!important;border-radius:7px!important;background:#0c9b9d!important;color:#fff!important;
  box-shadow:none!important;font-size:13px!important
}
.logo b{color:#111!important;font-size:12px!important}.logo small,.sidebarFoot small{color:#8a8a8a!important}
.mainNav{gap:2px!important}.mainNav button{
  min-height:34px!important;border-radius:6px!important;padding:8px 9px!important;color:#4f4f4f!important;
  background:transparent!important;font-size:12px!important;box-shadow:none!important
}
.mainNav button:hover{background:#f5f5f6!important;color:#111!important}
.mainNav button.on{
  background:#eeeeef!important;color:#111!important;box-shadow:none!important;font-weight:750!important
}
.sidebarFoot{border-top:1px solid #eeeeef!important;padding-top:8px!important}
.topbar{
  min-height:48px!important;background:#fff!important;backdrop-filter:none!important;border-bottom:1px solid #e5e6e8!important;
  padding:7px 14px!important
}
.topbar h2{font-size:14px!important;letter-spacing:0!important;color:#161616!important}
.content{padding:11px 13px 22px!important;max-width:none!important}
.subnav{gap:5px!important;padding-bottom:9px!important}.subnav button{
  min-height:30px!important;border-radius:6px!important;background:#fff!important;border:1px solid #e5e6e8!important;
  color:#585858!important;padding:6px 10px!important;font-size:11px!important
}
.subnav button.on{background:#f0f1f2!important;border-color:#dedfe1!important;color:#111!important;box-shadow:none!important}
.sectionHead{margin:0 0 10px!important;align-items:center!important}
.sectionHead h1{font-size:17px!important;letter-spacing:-.01em!important;color:#111!important;margin:0!important}
.sectionHead p{font-size:11px!important;color:#808080!important}
.card{
  background:#fff!important;border:1px solid #e3e4e6!important;border-radius:8px!important;box-shadow:none!important;padding:11px!important
}
.grid2{gap:9px!important}.grid3{gap:8px!important}.stats{gap:8px!important}
.stat{
  background:#fff!important;border:1px solid #e3e4e6!important;border-radius:7px!important;padding:10px 11px!important;
  box-shadow:none!important
}
.stat:before{display:none!important}.stat b{font-size:18px!important;letter-spacing:0!important;color:#161616!important}
.stat span{font-size:10px!important;color:#7b7b7b!important}
.tableWrap{border:1px solid #e3e4e6!important;border-radius:7px!important;box-shadow:none!important;background:#fff!important}
.table th{background:#f8f8f9!important;color:#565656!important;font-size:10px!important;border-color:#ececef!important;padding:8px!important}
.table td{border-color:#eeeeef!important;color:#292929!important;font-size:11px!important;padding:8px!important}
.themeCard{border-color:#e4e5e7!important;border-radius:8px!important;box-shadow:none!important}
.themeCard.active{border-color:#ff7a50!important;box-shadow:0 0 0 1px #ff7a50!important}
.activeChip{background:#fff0e9!important;color:#e94d1b!important}
.pill{background:#f2f3f4!important;color:#555!important}.notice{background:#fff7f2!important;color:#7c3b24!important}
.modalBack{background:rgba(17,17,17,.35)!important;backdrop-filter:blur(2px)!important}
.modal{background:#fff!important;border:1px solid #e0e1e3!important;border-radius:10px!important;box-shadow:0 18px 55px rgba(0,0,0,.17)!important}
.modalTop{background:#fff!important;backdrop-filter:none!important;border-color:#e6e7e9!important}
.previewStage{background:#f1f1f2!important}.empty{background:#fff!important;border-color:#dfe0e2!important}

/* Smart Cashier / product area: mirror the reference left panel */
#rohmatCashierSafe .cashierSurface,#cashierRoot.cashierSurface,.cashierSurface{
  background:#f6f6f7!important;color:#171717!important;border:0!important;border-radius:0!important;
  padding:0!important;min-height:0!important;box-shadow:none!important
}
.cashTop{
  min-height:44px!important;padding:8px 10px!important;margin:0 0 8px!important;background:#fff!important;
  border:1px solid #e4e5e7!important;border-radius:8px!important
}
.cashTop h2{font-size:14px!important;margin:0!important;color:#111!important;letter-spacing:0!important}
.cashEy{display:none!important}.cashTop .muted{font-size:10px!important;color:#888!important}
.cashLayout{grid-template-columns:minmax(0,1fr) 290px!important;gap:8px!important}
.cashPanel{
  background:#fff!important;color:#171717!important;border:1px solid #e3e4e6!important;border-radius:8px!important;
  padding:10px!important;box-shadow:none!important
}
.cashCats{gap:4px!important;margin-bottom:8px!important}.cashBtn{
  min-height:30px!important;padding:6px 9px!important;background:#fff!important;color:#333!important;
  border:1px solid #e1e2e4!important;border-radius:6px!important;font-size:10px!important;box-shadow:none!important
}
.cashBtn.on{background:#f0f1f2!important;border-color:#d7d8da!important;color:#111!important}
.cashBtn.primary{background:#fff!important;border-color:#d8d9db!important;color:#171717!important}
.cashBtn.primary:hover{background:#f7f7f8!important}
.cashMenu{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:8px!important}
.cashItem{
  background:#fff!important;color:#171717!important;border:1px solid #e2e3e5!important;border-radius:7px!important;
  padding:6px!important;box-shadow:none!important;display:grid!important;gap:5px!important
}
.cashItem img{
  width:100%!important;aspect-ratio:16/9!important;object-fit:cover!important;border-radius:4px!important;background:#eee!important
}
.cashItem>b{font-size:11px!important;line-height:1.25!important;color:#171717!important}
.cashItem>strong{font-size:10px!important;color:#585858!important;font-weight:700!important}
.cashLine{border-color:#eeeeef!important;padding:6px 0!important}.cashLine .muted{color:#888!important;font-size:10px!important}
.cashField{gap:4px!important}.cashField label{font-size:10px!important;color:#666!important}
.cashField input,.cashField select,.cashField textarea{
  min-height:32px!important;padding:6px 8px!important;background:#fff!important;color:#171717!important;
  border:1px solid #dedfe1!important;border-radius:6px!important;font-size:11px!important
}
.cashTotal{border-color:#e5e6e8!important;color:#111!important;padding-top:8px!important;margin-top:8px!important}
.cashQris img{max-width:150px!important}
@media(max-width:1050px){.shell{grid-template-columns:150px minmax(0,1fr)!important}.cashLayout{grid-template-columns:1fr 260px!important}}
@media(max-width:760px){
  .shell{grid-template-columns:1fr!important}.sidebar{position:static!important;padding:6px!important}
  .mainNav{display:flex!important;overflow:auto!important}.mainNav button{min-width:max-content!important}
  .content{padding:9px!important}.cashLayout{grid-template-columns:1fr!important}.cashMenu{grid-template-columns:repeat(2,minmax(0,1fr))!important}
}


/* smart-order-reference-structural-admin-v3 */
body #rohmatCashierSafe{
  --c-bg:#f6f6f7!important;--c-panel:#fff!important;--c-ink:#171717!important;--c-muted:#7a7f84!important;
  --c-primary:#f4f5f6!important;--c-accent:#111!important;--c-line:#e2e4e7!important;
  background:transparent!important;color:#171717!important;border:0!important;border-radius:0!important;
  padding:0!important;margin:0!important;min-height:0!important
}
.refOrderQueue{background:#fff;border:1px solid #e2e4e7;border-radius:8px;padding:10px;margin-bottom:8px}
.refQueueHead{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:8px}
.refQueueHead h2,.refProductHead h2{margin:0;color:#111;font-size:14px;letter-spacing:0}
.refQueueActions{display:flex;gap:5px}.refQueueActions button{width:28px;height:28px;border:1px solid #e0e2e4;background:#fff;border-radius:6px;color:#5a6065}
.refQueueGrid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:7px}
.refQueueCard{background:#fff;border:1px solid #e3e5e7;border-radius:7px;padding:8px;display:grid;gap:6px;min-width:0}
.refQueueTop{display:flex;align-items:center;justify-content:space-between;gap:6px}
.refQueueCode{font-weight:800;font-size:10px;color:#333;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.refQueueStatus{font-size:8px;font-weight:800;padding:3px 6px;border-radius:5px;white-space:nowrap}
.refQueueCard.preparing .refQueueStatus{background:#dff5e6;color:#287d43}
.refQueueCard.cooking .refQueueStatus{background:#fff0d9;color:#b36a12}
.refQueueCard.pending .refQueueStatus{background:#ffe0df;color:#c74a46}
.refQueuePlace{font-size:11px;font-weight:750;color:#222;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.refQueueMeta{font-size:9px;color:#81868a;display:flex;justify-content:space-between;gap:5px}
.refProductHead{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:9px 2px 7px}
.refProductHead .muted{font-size:9px}
body #rohmatCashierSafe .rc6Top{display:none!important}
body #rohmatCashierSafe .rc6Layout{display:grid!important;grid-template-columns:minmax(0,1fr) 286px!important;gap:8px!important}
body #rohmatCashierSafe .rc6Panel{
  padding:8px!important;background:#fff!important;border:1px solid #e2e4e7!important;border-radius:8px!important
}
body #rohmatCashierSafe .rc6Cats{gap:4px!important;margin-bottom:8px!important;overflow:auto!important}
body #rohmatCashierSafe .rc6Btn{
  min-height:29px!important;padding:5px 8px!important;border:1px solid #e0e2e4!important;background:#fff!important;
  color:#3f4549!important;border-radius:6px!important;font-size:9px!important;font-weight:700!important;box-shadow:none!important
}
body #rohmatCashierSafe .rc6Btn.on{background:#f0f1f2!important;border-color:#d9dcdf!important;color:#111!important}
body #rohmatCashierSafe .rc6Btn.primary{background:#eef6f1!important;border-color:#d8e7dd!important;color:#30493b!important}
body #rohmatCashierSafe .rc6Menu{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:8px!important}
body #rohmatCashierSafe .rc6Item{
  background:#fff!important;border:1px solid #e1e3e5!important;border-radius:7px!important;padding:0!important;overflow:hidden!important;
  display:grid!important;grid-template-rows:auto auto auto 1fr!important;gap:0!important;box-shadow:none!important
}
body #rohmatCashierSafe .rc6Item .rc6MediaSolo,
body #rohmatCashierSafe .rc6Item>img{
  width:100%!important;height:auto!important;aspect-ratio:16/9!important;object-fit:cover!important;object-position:center!important;
  border-radius:0!important;background:#eee!important;margin:0!important
}
body #rohmatCashierSafe .rc6Item h4{margin:7px 8px 0!important;font-size:11px!important;line-height:1.25!important;color:#161616!important}
body #rohmatCashierSafe .rc6Price{margin:5px 8px 5px!important;color:#222!important;font-size:10px!important;font-weight:800!important}
body #rohmatCashierSafe .rc6Item>.rc6Btn.primary{margin:0 8px 8px!important;justify-self:end!important;min-height:28px!important}
body #rohmatCashierSafe .rc6Item>.rc6Qty{margin:0 8px 8px!important;gap:4px!important}
body #rohmatCashierSafe .rc6Item>.rc6Qty .rc6Btn{width:29px!important;height:29px!important;min-height:29px!important}
body #rohmatCashierSafe .rc6Item>.rc6Qty>b{
  width:30px!important;height:29px!important;min-height:29px!important;border:1px solid #e1e3e5!important;border-radius:5px!important;
  background:#fff!important;color:#222!important;font-size:10px!important
}
body #rohmatCashierSafe .rc6Line{padding:6px 0!important;border-color:#eceeef!important;font-size:10px!important}
body #rohmatCashierSafe .rc6Qty .rc6Btn{width:28px!important;height:28px!important;min-height:28px!important}
body #rohmatCashierSafe .rc6Field{gap:3px!important;margin-top:6px!important}
body #rohmatCashierSafe .rc6Field label{font-size:9px!important;color:#686e72!important}
body #rohmatCashierSafe .rc6Field input,
body #rohmatCashierSafe .rc6Field select,
body #rohmatCashierSafe .rc6Field textarea{
  min-height:31px!important;padding:6px 7px!important;border:1px solid #dfe2e4!important;border-radius:6px!important;
  background:#fff!important;color:#222!important;font-size:10px!important
}
body #rohmatCashierSafe .rc6Two{gap:5px!important;margin-top:6px!important}
body #rohmatCashierSafe .rc6Total{font-size:14px!important;padding:8px 0!important;border-top:1px solid #e7e9eb!important;margin-top:6px!important}
body #rohmatCashierSafe .rc6Empty{border:1px dashed #dfe2e4!important;color:#8a9094!important;padding:10px!important;border-radius:6px!important;font-size:9px!important}
body #rohmatCashierSafe .rc6GateReason{font-size:8px!important;color:#8a9094!important}
body #rohmatCashierSafe .rc6Qris img{max-width:150px!important;max-height:170px!important}
body #rohmatCashierSafe .rc6Layout:has(aside .rc6Empty)>aside{display:none!important}
body #rohmatCashierSafe .rc6Layout:has(aside .rc6Empty){grid-template-columns:1fr!important}
body .topbar .ey{display:none!important}
body .topbar{min-height:44px!important}
body .topbar h2{font-size:13px!important}
@media(max-width:1050px){
  .refQueueGrid{grid-template-columns:repeat(3,minmax(160px,1fr))}
  body #rohmatCashierSafe .rc6Layout{grid-template-columns:minmax(0,1fr) 250px!important}
}
@media(max-width:760px){
  .refQueueGrid{grid-template-columns:1fr;overflow:auto}
  body #rohmatCashierSafe .rc6Layout{grid-template-columns:1fr!important}
  body #rohmatCashierSafe .rc6Menu{grid-template-columns:repeat(2,minmax(0,1fr))!important}
}

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


function applyReferenceExactStructure(html) {
  let out = String(html || '');
  out = out.replace(
    "let data={settings:{},menu:[],orders:[],team:[],email:'',role:''},main='general',sub='Tema',",
    "let data={settings:{},menu:[],orders:[],team:[],email:'',role:''},main=(location.pathname==='/database'?'database':'admin'),sub=(location.pathname==='/database'?'Spreadsheet':'Smart Cashier'),"
  );
  out = out.replace(
    "const items=[['general','Dashboard'],['admin','Point of Sale'],['public','Menu Management'],['kds','Kitchen'],['database','Reports']];",
    "const items=[['general','GENERAL'],['public','SITUS PUBLIK'],['admin','SITUS ADMIN'],['kds','KDS'],['database','DATABASE']];"
  );
  out = out.replace(
    '<div class="logo"><div class="logoMark">R</div><div><b>Studio Rohmat</b><small>Design System</small></div></div>',
    '<div class="logo"><div class="logoMark">R</div><div><b>SMART ORDER</b><small>Rohmat Nasi Uduk</small></div></div>'
  );
  const cashierNew = "if(sub==='Smart Cashier'){const q=data.orders.slice(0,3);v.innerHTML='<section class=\"refOrderQueue\"><div class=\"refQueueHead\"><h2>Order queue</h2><div class=\"refQueueActions\"><button type=\"button\" aria-label=\"Filter\">⌁</button><button type=\"button\" aria-label=\"Menu\">•••</button></div></div><div class=\"refQueueGrid\">'+q.map((o,i)=>{const raw=String(o.order_status||o.status||o.payment_status||'Pending'),lc=raw.toLowerCase(),cls=(lc.includes('prepar')||lc.includes('confirm')||lc.includes('ready'))?'preparing':(lc.includes('cook')||lc.includes('process'))?'cooking':'pending',label=cls==='preparing'?'Preparing':cls==='cooking'?'Cooking':'Pending',place=o.table_number?'Table '+o.table_number+' · Dine In':(String(o.service_mode||'').toLowerCase().includes('take')?'Takeaway · Pick Up':'Online Order'),mins=Math.max(1,Math.round((Date.now()-new Date(o.created_at||Date.now()).getTime())/60000)),cnt=Array.isArray(o.items)?o.items.reduce((a,x)=>a+Number(x.quantity||1),0):1;return '<article class=\"refQueueCard '+cls+'\"><div class=\"refQueueTop\"><span class=\"refQueueCode\">#'+esc(o.order_code||o.public_order_code||o.id||('ORD-'+String(i+1).padStart(3,'0')))+'</span><span class=\"refQueueStatus\">'+label+'</span></div><div class=\"refQueuePlace\">'+esc(place)+'</div><div class=\"refQueueMeta\"><span>'+cnt+' items · '+mins+' min</span><span>'+esc(o.payment_method||o.service_mode||'Order')+'</span></div></article>'}).join('')+'</div></section><div class=\"refProductHead\"><h2>Product List</h2><span class=\"muted\">Menu aktif · cari dan tambahkan ke pesanan</span></div><section id=\"rohmatCashierSafe\"><div class=\"empty\">Memuat menu Smart Cashier…</div></section>';";
  const cashierAt = out.indexOf("if(sub==='Smart Cashier'){v.innerHTML=");
  if (cashierAt >= 0) {
    const runAt = out.indexOf('requestAnimationFrame', cashierAt);
    if (runAt > cashierAt) out = out.slice(0, cashierAt) + cashierNew + out.slice(runAt);
  }
  return out;
}

export function canonicalizeAdminShell(html) {
  let out = ensureCashierIntegration(String(html || ''));
  out = out.split('Warung Nasi').join(BUSINESS_NAME);
  out = out.split(SUPABASE_ORIGIN + '/functions/v1/admin-media-upload').join('/admin/api/media-upload');
  out = out.replace(/MEDIA=U\+'\/functions\/v1\/admin-media-upload'/g, "MEDIA='/admin/api/media-upload'");
  out = out.split('https://smart-cassier.vercel.app/login').join('/kds/login');
  out = consolidateCss(out);
  out = applyReferenceExactStructure(out);

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
