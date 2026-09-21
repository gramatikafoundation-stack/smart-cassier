-- ADMIN Batch 2 final canonical renderer alignment.
-- Scope: release metadata only. No UI, auth, order, public-site, or business-data changes.

update private.release_component_registry
set expected_version='v65',
    expected_sha256='09c53bd4e6b758a9cb4d2a0a956b6f3bf7bebffd21f97beb97d3a1add80ec924',
    deployment_ref='edge-version:v65',
    rollback_ref='edge-version:v64',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Batch 2 final renderer alignment after bootstrap request dedup; source and active deployment verified identical.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v65',
    baseline_sha256='09c53bd4e6b758a9cb4d2a0a956b6f3bf7bebffd21f97beb97d3a1add80ec924',
    canonical_target='rohmat-admin-render',
    updated_at=now()
where component='admin-renderer';
