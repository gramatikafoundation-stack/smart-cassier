-- ROHMAT MASTER PROTOTIPE v1
-- Reconcile release-control metadata to the tenant-aware Edge versions deployed during the controlled cutover.
-- No application/business data is changed.

with v(component_key,expected_version,expected_sha256,deployment_ref,rollback_ref,notes) as (
  values
  ('admin_renderer','v90','333bd64b786c3f406663ee4e58612dc3d430c8e446b8284df7ce3a5bb68db33a','edge-version:v90','edge-version:v89','MASTER PROTOTIPE tenant-aware renderer; v89 immediate rollback.'),
  ('admin_cashier_loader','v37','0f16307709a27fa91ece28decacf3862e8a31b79d5bc5f70e50f756e65c24e59','edge-version:v37','edge-version:v36','MASTER PROTOTIPE tenant-bound Admin cashier loader; v36 rollback.'),
  ('admin_database_ui','v20','b1feb657d4d0060243a6d95667cae722498d9ee86d6cedb043dab167b3090fa0','edge-version:v20','edge-version:v19','MASTER PROTOTIPE tenant-bound database UI; v19 rollback.'),
  ('admin_runtime','v59','7a766551f3c28ddd3aca675324fe8a91f5a31877c9977a0cc7560182924e28a0','edge-version:v59','edge-version:v58','MASTER PROTOTIPE tenant asset propagation; v58 rollback.'),
  ('admin_cashier_embed','v8','eb231551df424a5c8e5bd1eeb76902c1a8de7d9791d04d97f736c816fbba206c','edge-version:v8','edge-version:v7','MASTER PROTOTIPE tenant-bound cashier embed; v7 rollback.'),
  ('sheet_worker','v11','af51672fac1ac224b7eb7b4b8aa39cea7e360db0a9482e81f3ac503ce9834174','edge-version:v11','edge-version:v10','MASTER PROTOTIPE tenant-scoped Sheet worker; v10 rollback.'),
  ('sheet_dispatch','v5','a807d22f152cd1f37903817ee0fc43a12acf1bfa26aca1b7fee15a9e302cb0fd','edge-version:v5','edge-version:v4','MASTER PROTOTIPE tenant-scoped Sheet dispatcher; v4 rollback.'),
  ('public_runtime','v60','5c2d98fe1f060d505a802e0c4c1cda48ef0c144385c39d80d8413537d2711a03','edge-version:v60','edge-version:v59','MASTER PROTOTIPE tenant-aware public runtime; v59 rollback.'),
  ('kds_api','v11','a8a26d9923511ae9baafb60d3c99b7fc7818a023099723bec34001f71764f819','edge-version:v11','edge-version:v10','MASTER PROTOTIPE tenant-bound KDS API; v10 rollback.'),
  ('order_core','v8','6a7089a70266d3ca8db7232fba5a1c7d42741588142f5df06045a6616de2896e','edge-version:v8','edge-version:v7','MASTER PROTOTIPE tenant-scoped order core; v7 rollback.'),
  ('secure_api','v13','8a504df9250d781da5b7f40c1b0d02944dae7e11fb9d38e0f1e09946ad8598f1','edge-version:v13','edge-version:v12','MASTER PROTOTIPE tenant-bound secure RPC gateway; v12 rollback.'),
  ('smart_cashier','v7','fb4689929aec1dad5da96b9364c06384341ae1072c38d9aae610fa573204ca19','edge-version:v7','edge-version:v6','MASTER PROTOTIPE tenant-bound Smart Cashier; v6 rollback.')
)
update private.release_component_registry r
set expected_version=v.expected_version,
    expected_sha256=v.expected_sha256,
    deployment_ref=v.deployment_ref,
    rollback_ref=v.rollback_ref,
    last_verified_at=now(),
    notes=coalesce(r.notes,'')||E'\n'||v.notes
from v
where r.component_key=v.component_key;

insert into private.release_component_registry(
  component_key,display_name,component_type,canonical_target,expected_version,expected_sha256,
  deployment_ref,rollback_ref,lifecycle,critical,change_control_component,source_mode,last_verified_at,notes
) values
('admin_media_upload','Admin Media Upload','edge-function','admin-media-upload','v5',
 '167bd61027c2b0d729657d70b366d845f62bcd20aef95f84c8acfa2da69090d4',
 'edge-version:v5','edge-version:v4','canonical',true,'admin-media-upload','supabase-edge-version',now(),
 'Tenant-bound Admin media upload promoted from candidate to canonical for MASTER PROTOTIPE.'),
('admin_order_history','Admin Order History','edge-function','rohmat-admin-order-history-v1','v3',
 'ab0f20cdd1ba155df17ebdd9dd1208306343bbb8d2a8e84e87d15eb9fea90556',
 'edge-version:v3','edge-version:v2','canonical',true,'admin-order-history','supabase-edge-version',now(),
 'Tenant-bound Admin order-history endpoint tracked as canonical.'),
('sheet_writer_data','Sheets Writer Data','edge-function','rohmat-sheet-writer-data-v1','v6',
 '356c127f011ca368e9a858d55891afa1d4e479155448c5639d74655d95e81aec',
 'edge-version:v6','edge-version:v5','canonical',true,'sheet-writer-data','supabase-edge-version',now(),
 'Tenant-bound authoritative Sheets snapshot endpoint tracked as canonical.')
on conflict(component_key) do update set
  display_name=excluded.display_name,
  component_type=excluded.component_type,
  canonical_target=excluded.canonical_target,
  expected_version=excluded.expected_version,
  expected_sha256=excluded.expected_sha256,
  deployment_ref=excluded.deployment_ref,
  rollback_ref=excluded.rollback_ref,
  lifecycle=excluded.lifecycle,
  critical=excluded.critical,
  change_control_component=excluded.change_control_component,
  source_mode=excluded.source_mode,
  last_verified_at=now(),
  notes=excluded.notes;

with v(component,baseline_version,baseline_sha256,canonical_target,scope,note) as (
  values
  ('admin-renderer','v90','333bd64b786c3f406663ee4e58612dc3d430c8e446b8284df7ce3a5bb68db33a','rohmat-admin-render','explicit-target-only','Tenant-aware MASTER PROTOTIPE renderer; v89 rollback.'),
  ('admin-cashier-loader','v37','0f16307709a27fa91ece28decacf3862e8a31b79d5bc5f70e50f756e65c24e59','rohmat-admin-cashier-loader-v1','admin-cashier-only','Tenant-bound cashier loader; v36 rollback.'),
  ('admin-database-ui','v20','b1feb657d4d0060243a6d95667cae722498d9ee86d6cedb043dab167b3090fa0','rohmat-admin-database-ui-v1','admin-database-only','Tenant-bound database UI; v19 rollback.'),
  ('admin-runtime','v59','7a766551f3c28ddd3aca675324fe8a91f5a31877c9977a0cc7560182924e28a0','rohmat-admin-style-runtime-v59','admin-target-only','Tenant asset propagation runtime; v58 rollback.'),
  ('admin-cashier-embed','v8','eb231551df424a5c8e5bd1eeb76902c1a8de7d9791d04d97f736c816fbba206c','rohmat-smart-cashier-embed-v1','explicit-target-only','Tenant-bound cashier embed; v7 rollback.'),
  ('sheets-worker','v11','af51672fac1ac224b7eb7b4b8aa39cea7e360db0a9482e81f3ac503ce9834174','rohmat-sheet-sync-worker-v1','sheets-only','Tenant-scoped Sheet worker; v10 rollback.'),
  ('sheet-dispatch','v5','a807d22f152cd1f37903817ee0fc43a12acf1bfa26aca1b7fee15a9e302cb0fd','rohmat-sheet-sync-dispatch-v1','sheets-only','Tenant-scoped Sheet dispatcher; v4 rollback.'),
  ('public-runtime','v60','5c2d98fe1f060d505a802e0c4c1cda48ef0c144385c39d80d8413537d2711a03','rohmat-public-element-runtime-v64','public-target-only','Tenant-aware public runtime; v59 rollback.'),
  ('kds-api','v11','a8a26d9923511ae9baafb60d3c99b7fc7818a023099723bec34001f71764f819','rohmat-kds-api','kds-only','Tenant-bound KDS API; v10 rollback.'),
  ('order-core','v8','6a7089a70266d3ca8db7232fba5a1c7d42741588142f5df06045a6616de2896e','create-order-v6','public-order-only','Tenant-scoped order core; v7 rollback.'),
  ('secure-api','v13','8a504df9250d781da5b7f40c1b0d02944dae7e11fb9d38e0f1e09946ad8598f1','rohmat-secure-api-v1','privileged-api-only','Tenant-bound secure API; v12 rollback.'),
  ('smart-cashier','v7','fb4689929aec1dad5da96b9364c06384341ae1072c38d9aae610fa573204ca19','rohmat-smart-cashier-v1','cashier-only','Tenant-bound Smart Cashier; v6 rollback.'),
  ('admin-media-upload','v5','167bd61027c2b0d729657d70b366d845f62bcd20aef95f84c8acfa2da69090d4','admin-media-upload','admin-media-only','Tenant-bound media uploader; v4 rollback.'),
  ('admin-order-history','v3','ab0f20cdd1ba155df17ebdd9dd1208306343bbb8d2a8e84e87d15eb9fea90556','rohmat-admin-order-history-v1','admin-database-only','Tenant-bound history endpoint; v2 rollback.'),
  ('sheet-writer-data','v6','356c127f011ca368e9a858d55891afa1d4e479155448c5639d74655d95e81aec','rohmat-sheet-writer-data-v1','sheets-only','Tenant-bound Writer data endpoint; v5 rollback.')
)
insert into private.production_change_control(
  component,component_type,locked,baseline_version,baseline_sha256,canonical_target,allowed_change_scope,note,updated_at
)
select component,'edge-function',true,baseline_version,baseline_sha256,canonical_target,scope,note,now()
from v
on conflict(component) do update set
  component_type='edge-function',
  locked=true,
  baseline_version=excluded.baseline_version,
  baseline_sha256=excluded.baseline_sha256,
  canonical_target=excluded.canonical_target,
  allowed_change_scope=excluded.allowed_change_scope,
  note=excluded.note,
  updated_at=now();

update private.release_policy
set expected_components=31,
    ci_status='current_candidate_ci_pending_external_runner_and_vercel_rate_limit',
    notes=coalesce(notes,'')||E'\n2026-09-20: tenant-aware Edge deployment registry reconciled; three previously untracked canonical endpoints added. CI remains fail-closed until a real current-head run executes.',
    updated_at=now()
where id=1;
