import fs from 'node:fs';
import assert from 'node:assert/strict';

const root=new URL('../../../',import.meta.url);
const read=p=>fs.readFileSync(new URL(p,root),'utf8');
const vercel=JSON.parse(read('vercel.json'));
const index=read('apps/kds/index.html');
const login=read('apps/kds/login.html');
const app=read('apps/kds/app.js');
const realtime=read('apps/kds/realtime.js');
const vendor=read('apps/kds/realtime-vendor.js');
const tenant=read('apps/kds/tenant-runtime.js');
const styles=read('apps/kds/styles.css');
const edge=read('supabase/functions/rohmat-kds-api/index.ts');
const migration=read('supabase/migrations/20260925024613_kds_realtime_hybrid_v1.sql');

assert.deepEqual(vercel.regions,['sin1']);
const rewrites=new Map(vercel.rewrites.map(x=>[x.source,x.destination]));
assert.equal(rewrites.get('/kds'),'/apps/kds/index.html');
assert.equal(rewrites.get('/kds/login'),'/apps/kds/login.html');
assert.equal(rewrites.get('/realtime-vendor.js'),'/apps/kds/realtime-vendor.js');
assert.equal(rewrites.get('/realtime.js'),'/apps/kds/realtime.js');

const headerMap=new Map(vercel.headers.map(x=>[x.source,new Map(x.headers.map(h=>[h.key.toLowerCase(),h.value]))]));
for(const p of ['/kds','/kds/(.*)','/dapur','/dapur/(.*)']){
  const h=headerMap.get(p);assert.ok(h,p);
  assert.match(h.get('content-security-policy')||'',/script-src 'self'/);
  assert.doesNotMatch(h.get('content-security-policy')||'',/script-src[^;]*unsafe-inline/);
  assert.match(h.get('content-security-policy')||'',/wss:\/\/xrepmvbccalzhlcznrff\.supabase\.co/);
  assert.match(h.get('x-robots-tag')||'',/noindex/);
  assert.match(h.get('cache-control')||'',/no-store/);
  assert.equal(h.get('cross-origin-resource-policy'),'same-origin');
}
for(const p of ['/styles.css','/app.js','/tenant-runtime.js','/realtime-vendor.js','/realtime.js','/design-runtime.js','/login.js']){
  const h=headerMap.get(p);assert.ok(h,p);assert.match(h.get('cache-control')||'',/max-age=31536000/);assert.match(h.get('cache-control')||'',/immutable/);
}

assert.match(index,/name="robots" content="noindex,nofollow,noarchive"/);
assert.match(login,/name="robots" content="noindex,nofollow,noarchive"/);
assert.match(index,/data-tenant-business/);
assert.match(index,/tenant-runtime\.js\?v=2/);
assert.match(index,/realtime-vendor\.js\?v=1/);
assert.match(index,/realtime\.js\?v=1/);
assert.match(index,/role="tablist"/);
assert.match(index,/role="tabpanel"/);
assert.match(index,/class="skipLink"/);
assert.match(login,/tenant-runtime\.js\?v=2/);

for(const old of ['POLL_ACTIVE_MS=2000','POLL_CASHIER_MS=5000','POLL_IDLE_MS=8000','POLL_STOCK_MS=10000'])assert.ok(!app.includes(old),old);
assert.match(app,/POLL_REALTIME_MS=45000/);
assert.match(app,/POLL_REALTIME_CASHIER_MS=60000/);
assert.match(app,/__ROHMAT_KDS_REALTIME__/);
assert.match(app,/rohmat:kds-snapshot/);
assert.match(app,/rohmat:kds-session-ready/);
assert.doesNotMatch(app,/<script>onload=\(\)=>print\(\)<\\\/script>/);

assert.match(realtime,/RohmatRealtimeClient/);
assert.match(realtime,/action:'realtime'/);
assert.match(realtime,/mode:'connecting'/);
assert.match(realtime,/staleAfterMs/);
assert.match(realtime,/reconnectAfterMs/);
assert.doesNotThrow(()=>new Function(realtime));
assert.match(vendor,/2\.117\.1/);
assert.match(vendor,/realtime-js\//);
assert.match(vendor,/window\.RohmatRealtimeClient/);
assert.doesNotThrow(()=>new Function(vendor));

assert.match(tenant,/action:'brand'/);
assert.match(styles,/min-height:44px/);
assert.match(styles,/:focus-visible/);
assert.match(styles,/prefers-reduced-motion/);
assert.match(styles,/data-sync-state="stale"/);

assert.match(edge,/action==="brand"/);
assert.match(edge,/action==="realtime"/);
assert.match(edge,/kds_realtime_ticket_tenant/);
assert.match(migration,/create table if not exists private\.kds_realtime_channels/i);
assert.match(migration,/trg_kds_realtime_orders/);
assert.match(migration,/trg_kds_realtime_menu_items/);
assert.match(migration,/revoke all on function public\.kds_realtime_ticket_tenant\(uuid,text\) from public, anon, authenticated/i);
assert.match(migration,/grant execute on function public\.kds_realtime_ticket_tenant\(uuid,text\) to service_role/i);

console.log('BATCH4_KDS_HARDENING_SOURCE_PASS=1');
