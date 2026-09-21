-- ADMIN Batch 1: atomic release-registry completion
-- Adds production-active ADMIN runtime atoms previously absent from release control.

insert into private.production_change_control
  (component,component_type,locked,baseline_version,baseline_sha256,canonical_target,allowed_change_scope,note,updated_at)
values
  ('admin-renderer','edge-function',true,'v56','36dbf8ba2464d59ecd8c14e8f52dda4582aa850f320d86beda07dbdec92747ed','rohmat-admin-render','explicit-target-only','Canonical ADMIN renderer; active source mirrored to immutable Git commit during Batch 1.',now()),
  ('admin-theme-preview','edge-function',true,'v8','a43295f3495ee779ee46bf68ee5bb15f87e392b61f6daf6d698a22f2199d2e23','rohmat-admin-theme-preview-v1','explicit-target-only','Canonical ADMIN theme preview runtime; active source mirrored to immutable Git commit during Batch 1.',now()),
  ('admin-cashier-embed','edge-function',true,'v7','31f3d64bffe18009f8d5f6aef155b9f2952fe817cdb766de1b0cd270f848ced9','rohmat-smart-cashier-embed-v1','explicit-target-only','Canonical ADMIN cashier embed runtime; active source mirrored to immutable Git commit during Batch 1.',now())
on conflict(component) do update set
  component_type=excluded.component_type,
  locked=true,
  baseline_version=excluded.baseline_version,
  baseline_sha256=excluded.baseline_sha256,
  canonical_target=excluded.canonical_target,
  allowed_change_scope=excluded.allowed_change_scope,
  note=excluded.note,
  updated_at=now();

insert into private.release_component_registry
  (component_key,display_name,component_type,canonical_target,expected_version,expected_sha256,deployment_ref,rollback_ref,lifecycle,critical,change_control_component,source_mode,last_verified_at,notes)
values
  ('admin_renderer','Admin Renderer','edge-function','rohmat-admin-render','v56','36dbf8ba2464d59ecd8c14e8f52dda4582aa850f320d86beda07dbdec92747ed','edge-version:v56','git:f300e1171878d54585bf5029bc8245cd10562eed#supabase/functions/rohmat-admin-render/index.ts','canonical',true,'admin-renderer','supabase-edge-version',now(),'Active production renderer registered atomically; immutable Git source is the recovery reference for the current known-good implementation.'),
  ('admin_theme_preview','Admin Theme Preview','edge-function','rohmat-admin-theme-preview-v1','v8','a43295f3495ee779ee46bf68ee5bb15f87e392b61f6daf6d698a22f2199d2e23','edge-version:v8','git:f300e1171878d54585bf5029bc8245cd10562eed#supabase/functions/rohmat-admin-theme-preview-v1/index.ts','canonical',true,'admin-theme-preview','supabase-edge-version',now(),'Previously deployment-only runtime is now tracked in release control and mirrored to immutable Git source.'),
  ('admin_cashier_embed','Admin Cashier Embed','edge-function','rohmat-smart-cashier-embed-v1','v7','31f3d64bffe18009f8d5f6aef155b9f2952fe817cdb766de1b0cd270f848ced9','edge-version:v7','git:f300e1171878d54585bf5029bc8245cd10562eed#supabase/functions/rohmat-smart-cashier-embed-v1/index.ts','canonical',true,'admin-cashier-embed','supabase-edge-version',now(),'Previously deployment-only runtime is now tracked in release control and mirrored to immutable Git source.')
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

update private.release_policy
set expected_components=28,
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'ADMIN Batch 1 adds three previously untracked active runtime atoms: admin renderer, theme preview, and cashier embed.',
    updated_at=now()
where id=1;
