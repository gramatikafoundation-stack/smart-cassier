-- ROHMAT MASTER PROTOTIPE v1
-- Writer v2 compatibility bridge reconciliation.
-- A newer full all-years RECONCILE has already succeeded through writer-data v7.
-- Older failed all-years reconciliations are therefore obsolete, not deleted.

update private.release_component_registry
set expected_version='v7',
    expected_sha256='48135eb29efa11d6d26af2f0b0023c2dbe62e02dc241f0c39e3f5f320f4cbcdb',
    deployment_ref='edge-version:v7',
    rollback_ref='edge-version:v6',
    last_verified_at=now(),
    notes=coalesce(notes,'')||E'\nWriter v2 compatibility bridge: missing tenant context is resolved only through master_prototype_runtime_context while client RLS enforcement remains disabled. Explicit tenant context remains canonical.'
where component_key='sheet_writer_data';

update private.production_change_control
set baseline_version='v7',
    baseline_sha256='48135eb29efa11d6d26af2f0b0023c2dbe62e02dc241f0c39e3f5f320f4cbcdb',
    note='Writer data v7 compatibility bridge for active Writer v2. Fallback is fail-closed automatically when tenant RLS enforcement is enabled. v6 is immediate rollback.',
    updated_at=now()
where component='sheet-writer-data';

with latest_success as (
  select tenant_id,max(created_at) as created_at
  from public.sheet_sync_outbox
  where entity_type='system'
    and entity_id='all-years'
    and operation='RECONCILE'
    and status='synced'
  group by tenant_id
)
update public.sheet_sync_outbox o
set status='superseded',
    locked_until=null,
    locked_by=null,
    last_error='Superseded after newer authoritative all-years RECONCILE succeeded through writer-data v7 compatibility bridge; historical failure retained.'
from latest_success s
where o.tenant_id=s.tenant_id
  and o.entity_type='system'
  and o.entity_id='all-years'
  and o.operation='RECONCILE'
  and o.status='failed'
  and o.created_at<s.created_at;

update private.remediation_program
set evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
      'writer_v2_bridge_version','sheet_writer_data_v7',
      'writer_v2_bridge_sha256','48135eb29efa11d6d26af2f0b0023c2dbe62e02dc241f0c39e3f5f320f4cbcdb',
      'compatibility_reconcile_verified',true,
      'compatibility_reconcile_verified_at',now(),
      'historical_failures_preserved_as_superseded',true
    ),
    updated_at=now()
where stage_no=11;

update private.release_policy
set notes=coalesce(notes,'')||E'\n2026-09-20: active Writer v2 compatibility restored by sheet-writer-data v7. Missing tenant context may resolve only while enforce_client_rls=false; Writer v4 activation remains mandatory before hard RLS enforcement/freeze.',
    updated_at=now()
where id=1;
