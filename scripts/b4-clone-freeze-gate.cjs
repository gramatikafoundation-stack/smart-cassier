const fs=require('node:fs');
const fail=m=>{console.error('B4_CLONE_FREEZE_GATE_FAIL:'+m);process.exit(1)};

const schema=JSON.parse(fs.readFileSync('prototype/tenant.config.schema.json','utf8'));
const validate=fs.readFileSync('prototype/validate-config.mjs','utf8');
const plan=fs.readFileSync('prototype/provision-plan.mjs','utf8');
const rehearse=fs.readFileSync('prototype/rehearse.mjs','utf8');
const live=fs.readFileSync('scripts/b4-live-clone-rehearsal.sql','utf8');
const freeze=fs.readFileSync('supabase/migrations/20260927152500_smart_order_b4_master_freeze_infrastructure_v1.sql','utf8');

if(schema.properties?.schema_version?.const!==2)fail('schema_version_v2');
for(const k of ['canonical_origin','surface_routes']) if(!schema.properties?.[k])fail('schema_missing_'+k);
for(const legacy of ['public_url','admin_url','kds_url']) if(schema.properties?.[legacy])fail('legacy_multi_domain_property_'+legacy);
const routes=schema.properties.surface_routes.properties;
if(routes.public?.const!=='/'||routes.admin?.const!=='/admin'||routes.kds?.const!=='/kds'||routes.database?.const!=='/database')fail('four_surface_routes');

for(const marker of [
  "platform_supabase_project_ref:'xrepmvbccalzhlcznrff'",
  "smart-order-master-tenant-v2",
  "new tenant must not reuse master canonical origin"
]) if(!validate.includes(marker))fail('validate_marker:'+marker);

for(const marker of [
  "repository:'gramatikafoundation-stack/smart-cassier'",
  "topology:'single_domain_four_surface'",
  "final_release_tag:'smart-order-master-prototype-v1.0.0'",
  "database_url:canonical+routes.database",
  "provider:'google_drive'"
]) if(!plan.includes(marker))fail('plan_marker:'+marker);

for(const marker of [
  "smart-order-two-tenant-static-rehearsal-v2",
  "one_domain_four_surface",
  "google_drive_database"
]) if(!rehearse.includes(marker))fail('rehearse_marker:'+marker);

for(const marker of [
  "smart-order-b4-live-logical-clone-v2",
  "fixture_persistence','rollback'",
  "origin_tenant_mismatch",
  "unknown_origin_fail_closed",
  "google_drive_targets"
]) if(!live.includes(marker))fail('live_rehearsal_marker:'+marker);

for(const marker of [
  "master_clone_rehearsal_attestations",
  "master_freeze_manifests",
  "reject_immutable_master_evidence_mutation",
  "guard_frozen_smart_order_prototype",
  "master_frozen_runtime_security_health_v1",
  "promote_smart_order_master_v1",
  "exact_head_clone_attestation_missing",
  "smart-order-master-prototype-v1.0.0",
  "git_tag_immutable_master_v1"
]) if(!freeze.includes(marker))fail('freeze_marker:'+marker);

if(!freeze.includes("p.status<>'draft'"))fail('promotion_must_require_draft');
if(!freeze.includes("b1_gate")||!freeze.includes("b2_gate")||!freeze.includes("b3_gate"))fail('prior_gates_required');
if(!freeze.includes("release_preflight_status()"))fail('preflight_required');
if(!freeze.includes("direct_production_changes_allowed=false"))fail('direct_production_changes_must_remain_false');

console.log(JSON.stringify({
  ok:true,
  contract:'smart-order-b4-clone-promotion-freeze-source-gate-v1',
  schema_version:2,
  topology:'single_domain_four_surface',
  shared_supabase_project:'xrepmvbccalzhlcznrff',
  immutable_evidence:true,
  promotion_explicit:true
},null,2));
console.log('B4_CLONE_PROMOTION_FREEZE_SOURCE_GATE_PASS=1');
