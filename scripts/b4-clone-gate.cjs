const fs=require('node:fs');
const fail=m=>{console.error('B4_CLONE_GATE_FAIL:'+m);process.exit(1)};
const m=fs.readFileSync('supabase/migrations/20260927160000_smart_order_b4_clone_foundation_v1.sql','utf8');
const r=fs.readFileSync('scripts/b4-clone-rehearsal.sql','utf8');

for(const marker of [
  'master_template_snapshots',
  'master_template_snapshot_immutable',
  'provision_tenant_from_master_v1',
  "'spreadsheet_ids'",
  "'writer_secret'",
  "'table_qr_signature_hashes'",
  "source_template_key,source_prototype_key,metadata",
  "p_prototype_key,p_prototype_key",
  "writer_url,max_attempts",
  "v_tenant,false,null",
  "provision://google-drive/",
  "extensions.gen_random_bytes(32)",
  "source_edits_required',false",
  "database_project_clone_required',false"
]) if(!m.includes(marker)) fail('foundation_marker:'+marker);

for(const forbidden of [
  'insert into public.orders',
  'insert into public.order_events',
  'insert into public.order_history_archive',
  'insert into public.sheet_sync_outbox',
  'insert into private.admin_sessions'
]) if(m.toLowerCase().includes(forbidden)) fail('forbidden_clone_history:'+forbidden);

for(const marker of [
  'rollback;',
  'b4_master_sheet_id_leaked',
  'b4_master_qr_signature_leaked',
  'b4_operational_history_cloned',
  'b4_clone_origin_resolution_failed',
  "'fixture_persistence','rollback'"
]) if(!r.includes(marker)) fail('rehearsal_marker:'+marker);

console.log(JSON.stringify({
  ok:true,
  contract:'smart-order-b4-clone-source-gate-v1',
  immutable_snapshot:true,
  secrets_excluded:true,
  history_excluded:true,
  unique_qr_required:true,
  unique_sheet_targets_required:true,
  disposable_clone_rehearsal:true
},null,2));
console.log('B4_CLONE_SOURCE_GATE_PASS=1');
