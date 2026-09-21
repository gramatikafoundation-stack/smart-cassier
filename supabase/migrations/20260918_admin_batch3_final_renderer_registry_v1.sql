-- ADMIN Batch 3 final qualification: canonical renderer v67.
-- Scope is release-control metadata only. No business data or runtime behavior changes.

update private.release_component_registry
set expected_version='v67',
    expected_sha256='a5c2157bd35bb21a2b4c16f1be4247d9284a921c0abe20013be5936ef4246c8a',
    deployment_ref='edge-version:v67',
    rollback_ref='edge-version:v66',
    last_verified_at=now(),
    notes=coalesce(notes,'') ||
      case when coalesce(notes,'')='' then '' else ' ' end ||
      'Batch 3 final hardening: session-scoped ADMIN token storage, accessibility runtime, contrast guard, and early SHA-256 CSP meta policy. v66 retained as immediate rollback.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v67',
    baseline_sha256='a5c2157bd35bb21a2b4c16f1be4247d9284a921c0abe20013be5936ef4246c8a',
    canonical_target='rohmat-admin-render',
    updated_at=now()
where component='admin-renderer';
