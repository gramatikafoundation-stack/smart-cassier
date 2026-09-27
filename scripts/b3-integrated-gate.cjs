const fs=require('node:fs');
const fail=m=>{console.error('B3_INTEGRATED_GATE_FAIL:'+m);process.exit(1)};
const probe=fs.readFileSync('supabase/functions/rohmat-env-capability-check-v1/index.ts','utf8');
const migration=fs.readFileSync('supabase/migrations/20260927212000_smart_order_b3_integrated_observability_v1.sql','utf8');

for(const marker of [
  '"database_web"',
  'reliability-probe-smart-order-b3-v2',
  '19c2c128ec9a9e5686019b44279e70d1266ed5b650c94b82488a464a444041fb',
  'databaseUrl=publicBase+"/database"'
]) if(!probe.includes(marker)) fail('probe_marker:'+marker);

for(const marker of [
  "service_key in ('public_web','admin_web','kds_web','database_web')",
  'smart_order_b3_reliability_readiness_v1',
  'smart_order_sheet_readiness_v1',
  'signed_table_qr_mode_ok',
  "prototype_writer_disabled_b3_reconciliation_required_on_provision",
  "provision://google-sheets-writer-v4",
  "expected_services',5",
  "expected_services',4"
]) if(!migration.includes(marker)) fail('migration_marker:'+marker);

if(migration.includes("delete from public.sheet_sync_outbox")) fail('outbox_delete_forbidden');
console.log(JSON.stringify({
  ok:true,
  contract:'smart-order-b3-integrated-source-gate-v1',
  database_surface_observed:true,
  historical_slo_preserved:true,
  sheet_template_mode_explicit:true,
  outbox_audit_rows_preserved:true
},null,2));
console.log('B3_INTEGRATED_SOURCE_GATE_PASS=1');
