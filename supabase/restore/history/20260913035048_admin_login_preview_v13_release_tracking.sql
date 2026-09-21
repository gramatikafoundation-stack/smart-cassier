-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260913035048  Name: admin_login_preview_v13_release_tracking
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

update private.release_component_registry
set expected_version='v13',
    expected_sha256='05e8ba6aa7f36abc0bb946c3ed1f28caaafebe2e2457e87f200fb1935aaf9bad',
    last_verified_at=now(),
    notes='Visual Editor v13 owns Admin Login preview responsiveness using container-based layout; replaces cross-addon login fitting.'
where component_key='admin_visual_editor';

update private.production_change_control
set baseline_version='v13',
    baseline_sha256='05e8ba6aa7f36abc0bb946c3ed1f28caaafebe2e2457e87f200fb1935aaf9bad',
    updated_at=now(),
    note='Admin Login preview renderer made container-responsive in canonical Visual Editor.'
where component='admin-visual-editor';

update private.release_component_registry
set expected_version='v9',
    expected_sha256='2ee0c67f08fdd25833cd915973f1b8f4798de3cff0e89500db7dd52559df137a',
    last_verified_at=now(),
    notes='Admin KDS addon v9 restricted to KDS three-status behavior only; login-preview CSS removed to prevent ownership conflict.'
where component_key='admin_kds_ui';

update private.production_change_control
set baseline_version='v9',
    baseline_sha256='2ee0c67f08fdd25833cd915973f1b8f4798de3cff0e89500db7dd52559df137a',
    updated_at=now(),
    note='KDS addon no longer patches Admin Login preview; three-status KDS behavior retained.'
where component='admin-kds-ui';

update private.remediation_program
set evidence = coalesce(evidence,'{}'::jsonb) || jsonb_build_object(
      'admin_login_preview','canonical Visual Editor v13 container-responsive layout',
      'admin_login_preview_conflict','removed from KDS addon v9',
      'admin_visual_editor_sha256','05e8ba6aa7f36abc0bb946c3ed1f28caaafebe2e2457e87f200fb1935aaf9bad',
      'admin_kds_ui_sha256','2ee0c67f08fdd25833cd915973f1b8f4798de3cff0e89500db7dd52559df137a'
    ),
    updated_at=now()
where stage_key='ux_e2e';
