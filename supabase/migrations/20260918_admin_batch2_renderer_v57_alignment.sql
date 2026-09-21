-- ADMIN Batch 2: canonicalize embedded renderer v57 performance release.
update private.release_component_registry
set expected_version='v57',
    expected_sha256='a4b099abf7154dc9819e815e1680bb97b586dd63117cf0b3533192e93a34fb11',
    deployment_ref='edge-version:v57',
    rollback_ref='edge-version:v56',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Batch 2 embedded-shell renderer removes cold-path DB snapshot fetch while preserving the current Vercel >=100000-character gateway contract; v56 retained as rollback.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v57',
    baseline_sha256='a4b099abf7154dc9819e815e1680bb97b586dd63117cf0b3533192e93a34fb11',
    canonical_target='rohmat-admin-render',
    updated_at=now(),
    note='Batch 2 embedded-shell renderer v57; rollback edge version v56.'
where component='admin-renderer';
