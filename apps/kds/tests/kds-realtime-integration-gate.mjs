import assert from 'node:assert/strict';
import fs from 'node:fs';

const kds=fs.readFileSync(new URL('../app.js',import.meta.url),'utf8');
const api=fs.readFileSync(new URL('../../../supabase/functions/rohmat-kds-api/index.ts',import.meta.url),'utf8');
const cashier=fs.readFileSync(new URL('../../../supabase/functions/rohmat-smart-cashier-v1/index.ts',import.meta.url),'utf8');
const adminHistory=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-order-history-v1/index.ts',import.meta.url),'utf8');
const adminDb=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-database-ui-v1/index.ts',import.meta.url),'utf8');
const realtimeSql=fs.readFileSync(new URL('../../../supabase/migrations/20261006001500_kds_realtime_delta_v1.sql',import.meta.url),'utf8');
const idemSql=fs.readFileSync(new URL('../../../supabase/migrations/20261006002500_smart_cashier_idempotency_v1.sql',import.meta.url),'utf8');

for(const marker of [
  "rpc('kds_delta'","rpc('kds_ack_visible'","m.payload?.payload||{}","private:false",
  "refresh(false,true).catch","cashClientOrderId='cashier-kds-'","Promise.all([orders,cashLoad(manual)])"
]) assert.ok(kds.includes(marker),'KDS realtime/idempotency marker missing: '+marker);
assert.ok(kds.includes('const rtVersions=new Map(),rtDeltaTimers=new Map()'),'KDS stale-event protection missing');
assert.ok(kds.includes("rtVersions.set(key,resolvedVersion)"),'KDS event version tracking missing');
assert.ok(kds.includes("FALLBACK_POLL_MS=8000"),'KDS fallback polling contract missing');
assert.ok(kds.includes("DEFAULT_SAFETY_POLL_MS=45000"),'KDS safety reconciliation contract missing');

for(const marker of ['kds_delta:"kds_delta_tenant"','kds_ack_visible:"kds_ack_visible_tenant"','smart_cashier_create_idempotent_tenant','p_client_order_id:clientOrderId']){
  assert.ok(api.includes(marker),'KDS API marker missing: '+marker);
}
for(const marker of ['smart_cashier_create_idempotent_tenant','clientOrderId','p_client_order_id:clientOrderId']){
  assert.ok(cashier.includes(marker),'Smart Cashier idempotency marker missing: '+marker);
}
assert.ok(adminHistory.includes('action==="realtime"'),'Admin realtime ticket endpoint missing');
assert.ok(adminHistory.includes('kds_realtime_ticket_tenant'),'Admin realtime must reuse tenant-scoped topic contract');
for(const marker of ['new WebSocket','rohmat:orders-changed','action:\'realtime\'','private:false']){
  assert.ok(adminDb.includes(marker),'Admin order realtime marker missing: '+marker);
}
for(const marker of ['entity_id','tenant_id','version','kds_delta_tenant','kds_ack_visible_tenant','realtime.send']){
  assert.ok(realtimeSql.includes(marker),'Realtime SQL marker missing: '+marker);
}
for(const marker of ['smart_cashier_create_idempotent_tenant','pg_advisory_xact_lock','p_client_order_id','duplicate']){
  assert.ok(idemSql.includes(marker),'Cashier idempotency SQL marker missing: '+marker);
}
console.log('KDS_REALTIME_INTEGRATION_GATE_PASS=1');
