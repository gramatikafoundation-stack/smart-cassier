-- ADMIN Batch 2: performance/runtime release alignment
-- Scope: release metadata only. No business data, auth, UI behavior, or public-site changes.

with desired(component_key,expected_version,expected_sha256,deployment_ref,rollback_ref) as (
  values
    ('admin_renderer','v63','d390d0da6c94bebc79076e17dc2280ba50b5e5d358720ad8bc716bf30e7ddc76','edge-version:v63','edge-version:v62'),
    ('admin_runtime','v55','e0cfa5eb43b632caa94c3f9698e4750b29c9d0882c6ebd7a89a0e55c5acf8956','edge-version:v55','edge-version:v54'),
    ('admin_visual_editor','v19','682251bf55c10da851e8a87e5e5a200513462493878c3623934690ec216a0b7e','edge-version:v19','edge-version:v18'),
    ('admin_theme_preview','v9','47a34e9bdcc7e515bfb32041ed0d0baef66d5d742004fc2474a68ded18851884','edge-version:v9','edge-version:v8'),
    ('admin_cashier_loader','v31','2db518a6c1ab5317fbee0dee1657933bcb7bb5dbcf1eeaf84c81cd0c6078e31f','edge-version:v31','edge-version:v30')
)
update private.release_component_registry r
set expected_version=d.expected_version,
    expected_sha256=d.expected_sha256,
    deployment_ref=d.deployment_ref,
    rollback_ref=d.rollback_ref,
    last_verified_at=now(),
    notes=coalesce(r.notes,'') || case when coalesce(r.notes,'')='' then '' else ' ' end ||
      'ADMIN Batch 2 performance/runtime optimization aligned to active production artifact on 2026-09-18.'
from desired d
where r.component_key=d.component_key;

update private.release_component_registry
set expected_version='dpl_2NKD7L6hC9JRZGdq9fBjantUb4Do',
    deployment_ref='dpl_2NKD7L6hC9JRZGdq9fBjantUb4Do',
    rollback_ref='vercel:dpl_DMJ47Ry2N1nMMShzhFXmU5STAL53',
    last_verified_at=now(),
    notes='ADMIN Batch 2 optimized gateway production deployment; previous production deployment retained as rollback.'
where component_key='admin_site';

with desired(component,baseline_version,baseline_sha256,canonical_target) as (
  values
    ('admin-renderer','v63','d390d0da6c94bebc79076e17dc2280ba50b5e5d358720ad8bc716bf30e7ddc76','rohmat-admin-render'),
    ('admin-runtime','v55','e0cfa5eb43b632caa94c3f9698e4750b29c9d0882c6ebd7a89a0e55c5acf8956','rohmat-admin-style-runtime-v59'),
    ('admin-visual-editor','v19','682251bf55c10da851e8a87e5e5a200513462493878c3623934690ec216a0b7e','rohmat-admin-visual-editor-v1'),
    ('admin-theme-preview','v9','47a34e9bdcc7e515bfb32041ed0d0baef66d5d742004fc2474a68ded18851884','rohmat-admin-theme-preview-v1'),
    ('admin-cashier-loader','v31','2db518a6c1ab5317fbee0dee1657933bcb7bb5dbcf1eeaf84c81cd0c6078e31f','rohmat-admin-cashier-loader-v1')
)
update private.production_change_control c
set baseline_version=d.baseline_version,
    baseline_sha256=d.baseline_sha256,
    canonical_target=d.canonical_target,
    updated_at=now()
from desired d
where c.component=d.component;

update private.production_change_control
set baseline_version='dpl_2NKD7L6hC9JRZGdq9fBjantUb4Do',
    baseline_sha256=null,
    canonical_target='https://studio-pengelola-rohmat.vercel.app',
    updated_at=now()
where component='admin-site';
