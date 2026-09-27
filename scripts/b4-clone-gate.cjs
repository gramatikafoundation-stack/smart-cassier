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

if(!m.includes("delete from public.sheet_sync_outbox\n  where tenant_id=v_tenant;")) fail('bootstrap_outbox_cleanup_must_be_tenant_scoped');
if((m.match(/delete from public\.sheet_sync_outbox/gi)||[]).length!==1) fail('unexpected_sheet_outbox_delete_scope');

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


const cert=fs.readFileSync('supabase/migrations/20260927172500_smart_order_b4_clone_certification_v1.sql','utf8');
for(const marker of [
  'master_clone_rehearsal_evidence',
  'master_clone_rehearsal_evidence_immutable',
  'run_master_clone_rehearsal_v1',
  'smart-order-b4-clone-certification-v1',
  'cleanup_residue',
  "candidate_status','draft'",
  "source_control_mode='git_b4_clone_certification'"
]) if(!cert.includes(marker)) fail('certification_marker:'+marker);
if(/update\s+private\.platform_prototypes[\s\S]{0,800}?status\s*=\s*'active'/i.test(cert)) fail('b4_2_must_not_promote_candidate');
if(!cert.includes('delete from private.platform_tenants where id=v_clone_id')) fail('certification_cleanup_missing');
console.log('B4_CLONE_CERTIFICATION_SOURCE_GATE_PASS=1');
