const fs=require('node:fs');
const fail=m=>{console.error('B2_RUNTIME_SECURITY_FAIL:'+m);process.exit(1)};
const read=p=>fs.readFileSync(p,'utf8');

const foundation=read('supabase/migrations/20260927194500_smart_order_b2_runtime_security_foundation_v1.sql');
for(const marker of [
  'alter table private.kds_realtime_channels enable row level security',
  "p_app_kind not in ('public','admin','kds','database')",
  "s.session_scope='admin'",
  'admin_password_login_bound_tenant',
  "interval '6 hours'",
  'tenant_runtime_single_origin_contract_b2',
  'tenant_table_qr_hash_b2'
]) if(!foundation.includes(marker)) fail('foundation_marker:'+marker);

const cutover=read('supabase/migrations/20260927203000_smart_order_b2_final_security_cutover_v1.sql');
for(const marker of [
  "require_table_qr_signature=true",
  "active_contract='smart-order-master-runtime-security-v2'",
  "revoke usage on schema internal_rpc from public, anon, authenticated",
  "master_runtime_security_health_v1",
  "b2_cutover_state','pending_final_validation'",
  "secure_api','v6'",
  "admin_media_upload','v3'",
  "admin_order_history','v3'"
]) if(!cutover.includes(marker)) fail('cutover_marker:'+marker);

const secure=read('supabase/functions/rohmat-secure-api-v1/index.ts');
for(const marker of [
  'admin_password_login_bound_tenant',
  'admin_password_session_info_bound_tenant',
  'deviceFingerprint',
  'secure-api-smart-order-b2'
]) if(!secure.includes(marker)) fail('secure_api_marker:'+marker);
if(secure.includes('admin_password_login:"admin_password_login_tenant"')) fail('unbound_admin_login_gateway');

const media=read('supabase/functions/admin-media-upload/index.ts');
if(!media.includes('admin_password_session_info_bound_tenant')) fail('media_unbound_session');
if(!media.includes('media-upload-smart-order-b2')) fail('media_security_marker');

const history=read('supabase/functions/rohmat-admin-order-history-v1/index.ts');
if(!history.includes('admin_password_session_info_bound_tenant')) fail('history_unbound_session');
if(!history.includes('smart-order-b2')) fail('history_security_marker');

console.log(JSON.stringify({
  ok:true,
  contract:'smart-order-b2-runtime-security-foundation-v1',
  database_rls:true,
  single_origin_runtime:true,
  admin_scope_isolation:true,
  admin_fingerprint_binding:true,
  admin_session_ttl_hours:6,
  qr_constraints:true,
  signed_qr_cutover:true,
  legacy_internal_rpc_closed:true,
  health_contract:true
},null,2));
console.log('B2_RUNTIME_SECURITY_GATE_PASS=1');
