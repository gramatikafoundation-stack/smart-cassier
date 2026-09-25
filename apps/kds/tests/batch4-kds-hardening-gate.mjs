import fs from 'node:fs';
import assert from 'node:assert/strict';

const read=p=>fs.readFileSync(new URL(p,import.meta.url),'utf8');
const index=read('../index.html');
const login=read('../login.html');
const app=read('../app.js');
const tenant=read('../tenant-runtime.js');
const css=read('../styles.css');
const vercel=JSON.parse(read('../../../vercel.json'));

assert.doesNotThrow(()=>new Function(app));
assert.doesNotThrow(()=>new Function(tenant));
assert.match(index,/name="robots" content="noindex,nofollow,noarchive"/);
assert.match(login,/name="robots" content="noindex,nofollow,noarchive"/);
assert.match(index,/role="tablist"/);
assert.match(index,/role="tabpanel"/);
assert.match(index,/aria-live="polite"/);
assert.match(index,/data-tenant-business/);
assert.match(login,/data-tenant-business/);

for(const asset of ['styles.css','tenant-runtime.js','quantity2.js','fast-nav.js','design-runtime.js','app.js','menu-media.js','cashier-required-receipt.js','print-hide.js']){
  assert.ok(index.includes('/kds-assets/v4/'+asset),asset);
}
for(const asset of ['styles.css','tenant-runtime.js','design-runtime.js','login.js']){
  assert.ok(login.includes('/kds-assets/v4/'+asset),asset);
}
assert.match(tenant,/fetch\('\/api\/kds\/config'/);
assert.match(tenant,/action:'brand'/);
assert.doesNotMatch(tenant,/fetch\('\/api\/config'/);

assert.match(app,/FALLBACK_POLL_MS=8000/);
assert.match(app,/DEFAULT_SAFETY_POLL_MS=45000/);
assert.match(app,/DEFAULT_STALE_AFTER_MS=75000/);
assert.match(app,/startRealtimeHybrid/);
assert.match(app,/new WebSocket/);
assert.match(app,/phx_join/);
assert.match(app,/heartbeat/);
assert.match(app,/kds_change/);
assert.match(app,/sync-stale/);
assert.doesNotMatch(app,/POLL_ACTIVE_MS|POLL_CASHIER_MS|POLL_STOCK_MS/);
assert.doesNotMatch(app,/onload=\(\)=>print\(\)/);

assert.match(css,/--kds-touch:48px/);
assert.match(css,/focus-visible/);
assert.match(css,/prefers-reduced-motion/);
assert.match(css,/sync-reconnecting/);
assert.match(css,/srOnly/);

assert.deepEqual(vercel.regions,['sin1']);
const rewrites=new Map(vercel.rewrites.map(x=>[x.source,x.destination]));
assert.equal(rewrites.get('/kds-assets/v4/app.js'),'/apps/kds/app.js');
assert.equal(rewrites.get('/kds-assets/v4/styles.css'),'/apps/kds/styles.css');
assert.equal(rewrites.get('/kds-assets/v4/tenant-runtime.js'),'/apps/kds/tenant-runtime.js');

const headers=new Map(vercel.headers.map(x=>[x.source,new Map(x.headers.map(h=>[h.key.toLowerCase(),h.value]))]));
for(const path of ['/kds','/kds/(.*)','/dapur','/dapur/(.*)']){
  const h=headers.get(path);assert.ok(h,path);
  assert.match(h.get('content-security-policy')||'',/script-src 'self'/);
  assert.match(h.get('content-security-policy')||'',/wss:\/\/\*\.supabase\.co/);
  assert.match(h.get('x-robots-tag')||'',/noindex/);
  assert.match(h.get('cache-control')||'',/no-store/);
}
const ah=headers.get('/kds-assets/v4/(.*)');
assert.ok(ah);
assert.equal(ah.get('cache-control'),'public, max-age=31536000, immutable');
const api=headers.get('/api/kds');
assert.ok(api);
assert.equal(api.get('x-rohmat-kds-region'),'sin1');

console.log('BATCH4_KDS_HARDENING_SOURCE_GATE_PASS=1');
