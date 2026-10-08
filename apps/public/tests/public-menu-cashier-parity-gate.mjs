import fs from 'node:fs';
import assert from 'node:assert/strict';

const pub=fs.readFileSync(new URL('../api/render.js',import.meta.url),'utf8');
const admin=fs.readFileSync(new URL('../../admin/api/render.js',import.meta.url),'utf8');

for(const token of [
  'body #rohmatCashierSafe .rc6Menu{gap:10px!important}',
  'body #rohmatCashierSafe .rc6Item{border-radius:10px!important;box-shadow:0 5px 16px rgba(14,33,28,.035)!important}',
  'aspect-ratio:16/9!important;object-fit:cover!important',
  'body #rohmatCashierSafe .rc6Item h4{margin:9px 10px 0!important;font-size:12px!important}',
  'body #rohmatCashierSafe .rc6Price{margin:6px 10px!important;font-size:11px!important;color:#d85d30!important}',
  'body #rohmatCashierSafe .rc6Btn{min-height:36px!important;padding:7px 10px!important;border-radius:8px!important;font-size:10px!important}'
]) assert.ok(admin.includes(token),'SMART CASHIER admin visual reference changed: '+token);

for(const token of [
  'smart-order-public-menu-cashier-parity-v2',
  '.grid{grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:10px!important',
  'border-radius:10px!important;box-shadow:0 5px 16px rgba(14,33,28,.035)!important',
  'aspect-ratio:16/9!important;object-fit:cover!important',
  'margin:9px 10px 0!important;font-size:12px!important;line-height:1.25!important',
  'margin:6px 10px!important;font-size:11px!important',
  'min-height:36px!important;padding:7px 10px!important;border-radius:8px!important;font-size:10px!important',
  "food.style.setProperty('aspect-ratio','16 / 9','important')",
  "document.documentElement.dataset.rohmatMenuReference='cashier-parity-16x9-v2'",
  '@media(max-width:760px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))!important}}'
]) assert.ok(pub.includes(token),'PUBLIC cashier parity token missing: '+token);

assert.ok(pub.includes("e.target.closest('#confirm,#pay,#close,.cat,[data-id]')"),'public functional menu click contract changed');
assert.ok(pub.includes('window.__rohmatPublicCoreRealtimeSync'),'public realtime contract missing');
assert.doesNotMatch(pub,/smart-order-public-menu-cashier-parity-v2[\s\S]{0,5000}(cashierActor|stockTools|adminOnly)/i,'administrative control leaked into PUBLIC parity layer');

console.log('PUBLIC_MENU_CASHIER_VISUAL_PARITY_GATE_PASS=1');
console.log('PUBLIC_MENU_FUNCTIONAL_BOUNDARY_GATE_PASS=1');
