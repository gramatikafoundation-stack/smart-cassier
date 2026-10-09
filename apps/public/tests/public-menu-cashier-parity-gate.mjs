import fs from 'node:fs';
import assert from 'node:assert/strict';

const pub=fs.readFileSync(new URL('../api/render.js',import.meta.url),'utf8');
const admin=fs.readFileSync(new URL('../../admin/api/render.js',import.meta.url),'utf8');
const kds=fs.readFileSync(new URL('../../kds/menu-media.css',import.meta.url),'utf8');

for(const token of [
  'smart-order-menu-square-v1',
  '--so-admin-card:222px!important',
  'aspect-ratio:1/1!important',
  'grid-template-columns:repeat(3,var(--so-admin-card))!important',
  '-webkit-line-clamp:2!important',
  'body #rohmatCashierSafe .rc6Btn{min-height:36px!important;padding:7px 10px!important;border-radius:8px!important;font-size:10px!important}'
]) assert.ok(admin.includes(token),'SMART ORDER ADMIN square visual reference missing: '+token);

for(const token of [
  'smart-order-public-menu-cashier-parity-v3',
  '--so-menu-card:272px',
  'grid-template-columns:repeat(3,var(--so-menu-card))!important',
  'width:var(--so-menu-card)!important;height:var(--so-menu-card)!important;aspect-ratio:1/1!important',
  'width:min(48%,150px)!important;height:auto!important;aspect-ratio:1/1!important',
  '-webkit-line-clamp:2!important',
  "el.style.setProperty('aspect-ratio','1 / 1','important')",
  "document.documentElement.dataset.rohmatMenuReference='cashier-square-1x1-v3'",
  '@media(max-width:650px)'
]) assert.ok(pub.includes(token),'PUBLIC square parity token missing: '+token);

for(const token of [
  '--so-kds-card:207px!important',
  'width:var(--so-kds-card)!important;height:var(--so-kds-card)!important;aspect-ratio:1/1!important',
  'width:45%!important;height:auto!important;aspect-ratio:1/1!important',
  '-webkit-line-clamp:2!important'
]) assert.ok(kds.includes(token),'KDS square geometry token missing: '+token);

assert.ok(pub.includes("e.target.closest('#confirm,#pay,#close,.cat,[data-id]')"),'public functional menu click contract changed');
assert.ok(pub.includes('window.__rohmatPublicCoreRealtimeSync'),'public realtime contract missing');
assert.doesNotMatch(pub,/smart-order-public-menu-cashier-parity-v3[\s\S]{0,7000}(cashierActor|stockTools|adminOnly)/i,'administrative control leaked into PUBLIC parity layer');

console.log('PUBLIC_MENU_CASHIER_VISUAL_PARITY_GATE_PASS=1');
console.log('PUBLIC_MENU_FUNCTIONAL_BOUNDARY_GATE_PASS=1');
console.log('SMART_ORDER_MENU_SQUARE_GEOMETRY_GATE_PASS=1');
