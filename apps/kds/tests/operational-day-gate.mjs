import assert from 'node:assert/strict';
import fs from 'node:fs';
const sql=fs.readFileSync(new URL('../../../supabase/migrations/20261007053100_kds_operational_day_snapshot.sql',import.meta.url),'utf8');
assert.ok(sql.includes("(o.created_at at time zone v_tz)::date=v_today"),'KDS snapshot must be limited to the tenant operational day');
assert.ok(sql.includes("o.payment_status='verified' and o.order_status in ('confirmed','preparing','ready')"),'KDS active workflow statuses must remain supported');
assert.ok(sql.includes("o.payment_status='submitted' and o.order_status='payment_review'"),'KDS payment-review workflow must remain supported');
console.log('KDS_OPERATIONAL_DAY_GATE_PASS=1');
