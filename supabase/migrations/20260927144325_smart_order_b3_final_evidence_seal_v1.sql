-- SMART ORDER B3 final evidence seal.
-- Data/control-plane reconciliation only. Candidate remains DRAFT; this is not final master promotion.
begin;

do $$
declare
  v_tenant uuid;
begin
  select reference_tenant_id into v_tenant
  from private.platform_prototypes
  where prototype_key='smart-order-sdb-platform-v1' and status='draft'
  limit 1;

  if v_tenant is null then raise exception 'b3_candidate_draft_missing'; end if;
  if not coalesce((private.smart_order_b3_reliability_readiness_v1(v_tenant)->>'ok')::boolean,false)
    then raise exception 'b3_release_reliability_not_ready'; end if;
  if not coalesce((private.frontend_performance_summary()->>'ok')::boolean,false)
    then raise exception 'b3_performance_not_ready'; end if;
  if not coalesce((private.frontend_ux_contract_status()->>'ok')::boolean,false)
    then raise exception 'b3_ux_not_ready'; end if;
  if not coalesce((private.integration_contract_status()->>'ok')::boolean,false)
    then raise exception 'b3_integration_not_ready'; end if;
  if not coalesce((private.smart_order_sheet_readiness_v1(v_tenant)->>'ok')::boolean,false)
    then raise exception 'b3_sheet_readiness_not_ready'; end if;
  if not coalesce((public.master_runtime_security_health_v1(v_tenant)->>'ok')::boolean,false)
    then raise exception 'b3_runtime_security_not_ready'; end if;

  if exists(
    select 1 from public.sheet_sync_outbox
    where tenant_id=v_tenant
      and (
        status in ('failed','dead')
        or (status in ('pending','processing') and created_at<now()-interval '5 minutes')
      )
  ) then raise exception 'b3_outbox_blocker_present'; end if;
end $$;

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
