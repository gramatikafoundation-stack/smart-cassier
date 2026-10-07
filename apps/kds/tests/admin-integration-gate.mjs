import assert from 'node:assert/strict';
import fs from 'node:fs';

const app=fs.readFileSync(new URL('../app.js',import.meta.url),'utf8');
const perf=fs.readFileSync(new URL('../perf.js',import.meta.url),'utf8');
const html=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');

assert.ok(app.includes("const d=await rpc('kds_snapshot')"),'canonical app refresh must read kds_snapshot');
assert.ok(app.includes("x.payment_status==='verified'&&x.order_status==='confirmed'"),'confirmed verified orders must classify into Pesanan Baru');
assert.ok(app.includes("await refresh(false,true);"),'realtime invalidation must refresh canonical snapshot');
assert.ok(!app.includes("rpc('kds_delta'"),'KDS must not call unsupported kds_delta RPC');
assert.ok(!app.includes("rpc('kds_ack_visible'"),'KDS must not call unsupported kds_ack_visible RPC');
assert.ok(!perf.includes('refresh = async function'),'performance layer must not override canonical refresh owner');
assert.ok(!perf.includes('fastOrderSig'),'orphan fastOrderSig must not exist');
assert.ok(!perf.includes('fastMenuSig'),'orphan fastMenuSig must not exist');
assert.ok(html.includes('/kds-assets/v4/app.js?v=20261007-admin-kds-integration'),'KDS app cache-buster must ship the integration fix');
assert.ok(html.includes('/kds-assets/v4/perf.js?v=14-admin-kds-integration'),'KDS perf cache-buster must ship the refresh-owner fix');
console.log('KDS_ADMIN_INTEGRATION_GATE_PASS=1');
