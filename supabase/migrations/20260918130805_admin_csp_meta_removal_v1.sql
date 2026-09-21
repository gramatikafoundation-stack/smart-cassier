-- Admin CSP hotfix: remove stale renderer meta-CSP and align release metadata.
-- The Vercel Admin gateway is the sole CSP authority and computes script hashes
-- from the final post-integration HTML body.

update private.release_component_registry
set expected_version='v71',
    expected_sha256='1f9d53372c994c2ff04009c05308df0985b7c19cd21095f7d773fcad2738dd67',
    deployment_ref='edge-version:v71',
    rollback_ref='edge-version:v70',
    last_verified_at=now(),
    notes=coalesce(notes,'') ||
      case when coalesce(notes,'')='' then '' else ' ' end ||
      'Hotfix: removed stale renderer meta-CSP. Vercel gateway remains the sole CSP authority and hashes the final post-integration body, preventing hash drift after shell mutations. Browser QA: login rendered and CSP/runtime errors=0.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v71',
    baseline_sha256='1f9d53372c994c2ff04009c05308df0985b7c19cd21095f7d773fcad2738dd67',
    updated_at=now()
where component='admin-renderer';
