-- Fix Admin theme application flow on mobile.
-- Removes dependency on browser native confirm, preserves General overrides,
-- and records renderer v80 as the production baseline.

update private.release_component_registry
set expected_version='v80',
    expected_sha256='4da532aacaa57e5cfea4cb2728d2b8c266813e21a49d9dfd0491557f12bad24b',
    deployment_ref='edge-version:v80',
    rollback_ref='edge-version:v79',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Theme apply hotfix: removes mobile native confirm dependency, adds busy state and publishedVersionId verification, and preserves General overrides while switching Theme.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v80',
    baseline_sha256='4da532aacaa57e5cfea4cb2728d2b8c266813e21a49d9dfd0491557f12bad24b',
    updated_at=now()
where component='admin-renderer';
