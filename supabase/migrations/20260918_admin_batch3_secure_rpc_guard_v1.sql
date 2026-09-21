-- ADMIN Batch 3: secure RPC bootstrap guard + renderer v68 registry alignment.
-- Scope: prevent unauthenticated background Admin RPC traffic before login.
-- Login RPC remains allowed; authenticated RPCs continue through rohmat-secure-api-v1.

update private.release_component_registry
set expected_version='v68',
    expected_sha256='6b348d62f821421e1eeeb33d4a2135b634d4437632ffc79a33ef72f3856e6518',
    deployment_ref='edge-version:v68',
    rollback_ref='edge-version:v67',
    last_verified_at=now(),
    notes=coalesce(notes,'') ||
      case when coalesce(notes,'')='' then '' else ' ' end ||
      'Batch 3 final browser hardening: secure RPC wrapper now suppresses unauthenticated non-login RPC network calls locally; login path remains unchanged. CSP inline-script hash updated. v67 retained as rollback.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v68',
    baseline_sha256='6b348d62f821421e1eeeb33d4a2135b634d4437632ffc79a33ef72f3856e6518',
    updated_at=now()
where component='admin-renderer';
