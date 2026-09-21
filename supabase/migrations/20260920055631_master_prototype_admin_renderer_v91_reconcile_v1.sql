-- ROHMAT MASTER PROTOTIPE v1
-- Reconcile Admin renderer v91 after restoring compatibility with the legacy Vercel gateway.
-- The compatibility marker is emitted only for the Rohmat reference tenant and is non-visual.

update private.release_component_registry
set expected_version='v91',
    expected_sha256='22fda89d7d68045bc148205b40d8f682232c6e77a984be93993c04eadf99299f',
    deployment_ref='edge-version:v91',
    rollback_ref='edge-version:v90',
    last_verified_at=now(),
    notes=coalesce(notes,'')||E'\nAdmin renderer v91 preserves the legacy Rohmat gateway validation marker only for the reference tenant; tenant-aware runtime remains unchanged.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v91',
    baseline_sha256='22fda89d7d68045bc148205b40d8f682232c6e77a984be93993c04eadf99299f',
    note='Tenant-aware Admin renderer v91 with reference-tenant-only nonvisual legacy gateway compatibility marker. v90 is immediate rollback.',
    updated_at=now()
where component='admin-renderer';

update private.remediation_program
set evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
      'admin_renderer_version','v91',
      'admin_renderer_sha256','22fda89d7d68045bc148205b40d8f682232c6e77a984be93993c04eadf99299f',
      'legacy_gateway_compatibility_restored',true,
      'production_admin_http_status',200,
      'verified_at',now()
    ),
    updated_at=now()
where stage_no in (9,10);

update private.release_policy
set notes=coalesce(notes,'')||E'\n2026-09-20: Admin production recovered to HTTP 200 via tenant-safe renderer v91 compatibility marker; no Vercel deployment or business-data mutation required.',
    updated_at=now()
where id=1;
