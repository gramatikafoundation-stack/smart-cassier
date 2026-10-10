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
  '-webkit-line-clamp:2!important'
]) assert.ok(admin.includes(token),'SMART ORDER ADMIN visual reference missing: '+token);

for(const token of [
  'smart-order-public-menu-four-column-v4',
  'grid-template-columns:repeat(4,minmax(0,1fr))!important',
  'grid-template-rows:minmax(0,78fr) minmax(0,22fr)!important',
  'object-fit:contain!important',
  'object-position:center!important',
  'text-align:center!important',
  '-webkit-line-clamp:2!important',
  "document.documentElement.dataset.rohmatMenuReference='four-column-contain-v4'",
  '@media(max-width:900px)',
  '@media(max-width:700px)',
  '@media(max-width:420px)'
]) assert.ok(pub.includes(token),'PUBLIC four-column/contain parity token missing: '+token);

for(const token of [
  '--so-kds-card:207px!important',
  'grid-template-columns:repeat(3,var(--so-kds-card))!important',
  'aspect-ratio:4/5!important',
  'grid-template-rows:minmax(0,78fr) auto auto!important',
  'object-fit:contain!important',
  'object-position:center!important',
  'text-align:center!important',
  '-webkit-line-clamp:2!important'
]) assert.ok(kds.includes(token),'KDS public-card anatomy parity token missing: '+token);

assert.ok(pub.includes("e.target.closest('#confirm,#pay,#close,.cat,[data-id]')"),'public functional menu click contract changed');
assert.ok(pub.includes('window.__rohmatPublicCoreRealtimeSync'),'public realtime contract missing');
assert.doesNotMatch(pub,/smart-order-public-menu-four-column-v4[\s\S]{0,7000}(cashierActor|stockTools|adminOnly)/i,'administrative control leaked into PUBLIC parity layer');

console.log('PUBLIC_MENU_CASHIER_VISUAL_PARITY_GATE_PASS=1');
console.log('PUBLIC_MENU_FUNCTIONAL_BOUNDARY_GATE_PASS=1');
console.log('SMART_ORDER_PUBLIC_MENU_FOUR_COLUMN_CONTAIN_GATE_PASS=1');
