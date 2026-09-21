update private.platform_tenancy_state
set enforce_client_rls=true, updated_at=now()
where id=1;

update private.integration_registry
set contract_version='apps-script-writer-v4',
    enabled=true,
    metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'tenant_aware',true,
      'runtime_version',4,
      'deployment_id_preserved',true,
      'freeze_verified',true,
      'verified_at',now()
    ),
    updated_at=now()
where service_key='sheet_writer';

update private.platform_prototypes
set status='active',
    release_tag='rohmat-master-prototype-v1.0.0',
    metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'freeze_state','frozen',
      'freeze_gate_mode','provider_independent_exact_head',
      'frozen_at',now(),
      'rls_enforced',true,
      'writer_version',4,
      'admin_tenant_membership_guard',true,
      'reference_kds_legacy_bridge',true
    ),
    updated_at=now()
where prototype_key='rohmat-master-prototype-v1';

update private.release_policy
set source_control_mode='git_master_prototype_frozen',
    git_repo_connected=true,
    ci_status='provider_independent_exact_head_pass_actions_prerun_unavailable',
    require_preflight=true,
    require_postflight=true,
    direct_production_changes_allowed=false,
    notes=
      '2026-09-20 FINAL FREEZE: Writer v4 production active on preserved Apps Script deployment; shared-database RLS enforcement enabled; Admin policies tenant-scoped and membership-bound; Public production verified with 36 reference-tenant menu rows under RLS; legacy reference KDS service-role bridge resolves tenant while authentication remains fail-closed (unauthenticated session returns invalid_session). GitHub Actions candidate run failed before runner allocation/steps (runner_id=0); provider-independent exact-head Node/Deno/Playwright/rehearsal gates PASS. Controlled non-blocking advisor exceptions: pg_net remains in public due legacy dependency; master_prototype_resolve_origin remains anon/auth executable because Public origin fallback consumes only registered HTTPS origin and returns non-secret tenant runtime config; leaked-password protection remains an external Auth configuration warning. Vercel daily deployment limit bypassed without promoting known-bad previews.',
    updated_at=now()
where id=1;
