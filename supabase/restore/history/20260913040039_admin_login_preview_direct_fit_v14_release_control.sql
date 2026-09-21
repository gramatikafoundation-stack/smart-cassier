-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260913040039  Name: admin_login_preview_direct_fit_v14_release_control
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

update private.release_component_registry
set expected_version='v14',
    expected_sha256='c2bdec0f70f75e1b3950f423c7d0d1b0a6169884b42f0e6406e5ec1a5e5c1a9d',
    deployment_ref='edge-version:v14',
    rollback_ref='edge-version:v13',
    last_verified_at=now(),
    notes='Admin Visual Editor v14. Login preview uses direct runtime canvas measurement and inline important sizing instead of relying on container queries. Roll back to v13 if needed.'
where component_key='admin_visual_editor';

update private.production_change_control
set baseline_version='v14',
    baseline_sha256='c2bdec0f70f75e1b3950f423c7d0d1b0a6169884b42f0e6406e5ec1a5e5c1a9d',
    note='Admin login preview direct-fit v14; deterministic canvas-width sizing.',
    updated_at=now()
where component='admin-visual-editor';

update private.remediation_program
set evidence=coalesce(evidence,'{}'::jsonb) || jsonb_build_object(
      'admin_login_preview','Visual Editor v14 direct canvas-fit active; container-query dependency removed',
      'visual_editor_sha256','c2bdec0f70f75e1b3950f423c7d0d1b0a6169884b42f0e6406e5ec1a5e5c1a9d'
    ),
    updated_at=now()
where stage_key='ux_e2e';
