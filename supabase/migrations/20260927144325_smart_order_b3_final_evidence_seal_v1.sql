-- SMART ORDER B3 final evidence seal.
-- Data/control-plane reconciliation only. Candidate remains DRAFT; this is not final master promotion.
begin;

-- Live execution is preceded by an external B3 preflight assertion. Keeping live
-- telemetry checks outside this migration makes the seal replayable in an empty DR
-- environment while preserving deterministic control-plane state.


-- Pin the live reliability probe v6 while retaining v5 as rollback.
update private.release_component_registry
set expected_version='v6',
    expected_sha256='dfd0c2361379ce64e8a0180f09a97910131c3a954959db7ef1c74816cfd514ea',
    deployment_ref='edge-version:v6',
    rollback_ref='edge-version:v5',
    last_verified_at=now(),
    notes=coalesce(notes,'') || E'\nB3 four-surface reliability probe: Database added; v5 retained as rollback.'
where component_key='reliability_probe';

update private.production_change_control
set baseline_version='v6',
    baseline_sha256='dfd0c2361379ce64e8a0180f09a97910131c3a954959db7ef1c74816cfd514ea',
    canonical_target='rohmat-env-capability-check-v1',
    locked=true,
    note=coalesce(note,'') || E'\nB3 four-surface reliability probe pin; rollback edge-version:v5.',
    updated_at=now()
where component='reliability-probe';

-- Reconcile the one remaining manifest drift for the KDS compatibility redirect.
update private.production_change_control c
set baseline_version=r.expected_version,
    baseline_sha256=r.expected_sha256,
    canonical_target=r.canonical_target,
    locked=true,
    note=coalesce(c.note,'') || E'\nB3 release-manifest reconciliation to current canonical KDS route deployment.',
    updated_at=now()
from private.release_component_registry r
where r.component_key='kds_redirect'
  and c.component='kds-redirect';

-- B1 added Database as a canonical component, so canonical+compatibility count is now 32.
update private.release_policy
set expected_components=32,
    source_control_mode='git_b3_integrated_qa_freeze_prep',
    ci_status='github_actions_b3_final_gate_pass',
    required_checks=jsonb_build_array(
      'migration_head','schema_fingerprint','cron_fingerprint','manifest_fingerprint',
      'rollback_refs','change_control','integration_contracts','tenant_isolation',
      'integrated_e2e','data_consistency','release_reliability','performance',
      'four_surface_network','ux','dr_restore_rehearsal','production_health'
    ),
    notes=coalesce(notes,'') || E'\n2026-09-27 B3: Integrated QA/E2E/Performance/Recovery gate. Four-surface runtime, rollback-only order→Admin→KDS E2E, tenant isolation, network budgets, live recovery drill, and isolated full-schema restore are required before this seal is applied. Candidate remains draft.',
    updated_at=now()
where id=1;

update private.platform_prototypes
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'freeze_state','candidate_b3',
      'b3_gate','passed',
      'b3_contract','integrated-qa-e2e-performance-recovery-v1',
      'b3_e2e','rollback-only-order-admin-kds-pass',
      'b3_tenant_isolation','cross-tenant-read-write-rejected',
      'b3_performance','four-surface-network-and-decoded-budget-pass',
      'b3_recovery','live-drill-plus-isolated-full-restore-required',
      'b3_reliability_probe_version','v6',
      'b3_reliability_probe_sha256','dfd0c2361379ce64e8a0180f09a97910131c3a954959db7ef1c74816cfd514ea',
      'b3_candidate_status','draft'
    ),
    updated_at=now()
where prototype_key='smart-order-sdb-platform-v1'
  and status='draft';

-- Fingerprints are captured after all manifest-bearing rows above are reconciled.
update private.release_baseline
set release_label='b3-integrated-qa-freeze-prep-20260927',
    migration_head='20260927144325',
    schema_fingerprint=private.release_schema_fingerprint(),
    cron_fingerprint=private.release_cron_fingerprint(),
    manifest_fingerprint=private.release_manifest_fingerprint(),
    captured_at=now(),
    notes='B3 freeze-preparation evidence seal. Candidate remains draft; final master promotion is a separate gate.'
where id=1;

commit;
