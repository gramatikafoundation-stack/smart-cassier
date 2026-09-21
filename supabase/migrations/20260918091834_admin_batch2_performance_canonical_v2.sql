update private.release_component_registry
set expected_version='v65',
    expected_sha256='09c53bd4e6b758a9cb4d2a0a956b6f3bf7bebffd21f97beb97d3a1add80ec924',
    deployment_ref='edge-version:v65',
    rollback_ref='edge-version:v64',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Batch 2 canonical renderer: embedded optimized shell, 78.5KB payload, CDN-aware gateway compatibility, shared bootstrap dedup; v64 retained as rollback.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v65',
    baseline_sha256='09c53bd4e6b758a9cb4d2a0a956b6f3bf7bebffd21f97beb97d3a1add80ec924',
    canonical_target='rohmat-admin-render',
    updated_at=now()
where component='admin-renderer';

update private.release_component_registry
set expected_version='dpl_2NKD7L6hC9JRZGdq9fBjantUb4Do',
    deployment_ref='dpl_2NKD7L6hC9JRZGdq9fBjantUb4Do',
    rollback_ref='vercel:dpl_DMJ47Ry2N1nMMShzhFXmU5STAL53',
    last_verified_at=now(),
    notes='Batch 2 production gateway with optimized renderer mode, marker-based validation, stale-memory fallback, and CDN-only shell caching. Previous production deployment retained as rollback candidate.'
where component_key='admin_site';

update private.production_change_control
set baseline_version='dpl_2NKD7L6hC9JRZGdq9fBjantUb4Do',
    baseline_sha256=null,
    canonical_target='https://studio-pengelola-rohmat.vercel.app',
    updated_at=now()
where component='admin-site';
