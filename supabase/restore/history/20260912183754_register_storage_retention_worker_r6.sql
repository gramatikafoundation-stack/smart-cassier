-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912183754  Name: register_storage_retention_worker_r6
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

update private.release_component_registry
set component_key='storage_retention_worker',
    display_name='Storage Retention Worker',
    expected_version='v3',
    expected_sha256='9df7c728d2cded572c72c7ea7a7887c12cc9a07efe3a1c4f76e1fcb9677e7530',
    rollback_ref='edge-version:v2-retired-410',
    lifecycle='compatibility',
    critical=false,
    change_control_component='storage-retention-worker',
    last_verified_at=now(),
    notes='Internal Vault-authenticated maintenance worker. External GET/HEAD remains HTTP 410; authenticated POST enforces 90-day payment-proof Storage retention and removes obsolete static test artifact.'
where component_key='retired_html_test';

insert into private.production_change_control(component,component_type,locked,baseline_version,baseline_sha256,canonical_target,allowed_change_scope,note,updated_at)
values('storage-retention-worker','edge-function',true,'v3','9df7c728d2cded572c72c7ea7a7887c12cc9a07efe3a1c4f76e1fcb9677e7530','rohmat-html-test-v1','privacy-storage-maintenance-only','Internal maintenance worker; public GET/HEAD remains 410. Changes require retention acceptance checks.',now())
on conflict(component) do update set component_type=excluded.component_type,locked=excluded.locked,baseline_version=excluded.baseline_version,baseline_sha256=excluded.baseline_sha256,canonical_target=excluded.canonical_target,allowed_change_scope=excluded.allowed_change_scope,note=excluded.note,updated_at=excluded.updated_at;

update private.release_policy
set expected_components=25,
    notes='Git repository is not currently accessible. Production remains guarded by manifest snapshots, migration history, hashes, rollback refs and health contracts. Storage Retention Worker v3 is now an explicit compatibility component.',
    updated_at=now()
where id=1;

update private.remediation_program
set status='in_progress',
    blocker='Historical Edge Function sprawl remains; mass deletion is intentionally deferred until dependency mapping proves each function orphaned. Unused indexes are retained pending longer observation.',
    evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('static_test_html','REMOVED physically via authenticated Storage worker','unused_indexes','REVIEWED; no mass drop','storage_retention_worker','v3 active / external GET remains 410','retired_cleanup_policy','dependency-proof required before deletion'),
    updated_at=now()
where stage_no=14;

update private.remediation_program
set evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('storage_physical_retention','ACTIVE daily worker / 90 days','storage_worker_last_run','PASS due=0 errors=0','external_enforcement_pending',1),
    blocker='Google Sheets PII retention still requires writer-side enforcement; physical Supabase Storage retention is now automated.',
    updated_at=now()
where stage_no=11;
