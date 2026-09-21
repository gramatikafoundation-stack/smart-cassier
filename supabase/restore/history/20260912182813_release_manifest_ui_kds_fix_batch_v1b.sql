-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912182813  Name: release_manifest_ui_kds_fix_batch_v1b
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

update private.release_component_registry
set expected_version='v7',
    expected_sha256='c1e7b9e8c99b3eca2adc369823c5dae58a1a1fd62cad86b39fcd0926be128a6d',
    rollback_ref='edge-version:6',
    last_verified_at=now(),
    notes='Admin KDS UI: force canonical three-status monitor view and fluid Admin Login preview.'
where component_key='admin_kds_ui';

update private.release_component_registry
set expected_version='v11',
    expected_sha256='684dd6311104e497eddcccbfe9f8668bfb6bae57a9bd1e173f1d72bd605e7f2a',
    rollback_ref='edge-version:10',
    last_verified_at=now(),
    notes='Admin Database UI: remove Riwayat Pesanan heading/subtitle while retaining live indicator and transaction table.'
where component_key='admin_database_ui';

update private.production_change_control
set baseline_version='v7',
    baseline_sha256='c1e7b9e8c99b3eca2adc369823c5dae58a1a1fd62cad86b39fcd0926be128a6d',
    updated_at=now()
where component='admin-kds-ui';

update private.production_change_control
set baseline_version='v11',
    baseline_sha256='684dd6311104e497eddcccbfe9f8668bfb6bae57a9bd1e173f1d72bd605e7f2a',
    updated_at=now()
where component='admin-database-ui';

update private.remediation_program
set status='in_progress',
    blocker='Static KDS still uses browser-side session storage; backend session stability and missing snapshot execute grant have been repaired.',
    evidence=jsonb_build_object(
      'snapshot_internal_execute','RESTORED',
      'menu_source_count',36,
      'menu_cache_count',36,
      'mobile_fingerprint','device-stable v2 without IP binding',
      'session_quota','isolated per scope admin/kds',
      'admin_kds_ui','v7 three-status view'
    ),
    updated_at=now()
where stage_no=4;

update private.remediation_program
set evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
      'admin_login_preview','fluid full-width override installed in admin-kds-ui v7',
      'admin_kds_orders','canonical 3 statuses only',
      'database_history_heading','removed by admin-database-ui v11'
    ),
    updated_at=now()
where stage_no=10;
