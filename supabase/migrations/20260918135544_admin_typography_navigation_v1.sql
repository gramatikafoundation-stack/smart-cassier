-- Admin typography + navigation hotfix (intermediate registry state).
-- This migration was applied before the patch was rebased on the latest freeze-prep.

update private.release_component_registry
set expected_version='v76',
    expected_sha256='83e997d664974820722e8951be3f1b16f2b1156b2b6c099f37e09fcafa8b1d6a',
    deployment_ref='edge-version:v76',
    rollback_ref='edge-version:v71',
    last_verified_at=now(),
    notes=coalesce(notes,'') ||
      case when coalesce(notes,'')='' then '' else ' ' end ||
      'Typography/navigation hotfix: General publish now sends p_token explicitly, verifies publishedVersionId advances before success, supports 5-72px round-trip, and navigation uses one delegated handler resilient to DOM re-render. Static route audit covers 23/23 subnavigation targets.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v76',
    baseline_sha256='83e997d664974820722e8951be3f1b16f2b1156b2b6c099f37e09fcafa8b1d6a',
    updated_at=now()
where component='admin-renderer';
