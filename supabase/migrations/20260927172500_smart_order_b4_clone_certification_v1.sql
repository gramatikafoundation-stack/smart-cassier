-- SMART ORDER B4.2: persisted clone-certification evidence.
-- Candidate remains DRAFT. No master promotion in this migration.

begin;

do $$
declare v_status text;
begin
  select status into v_status
  from private.platform_prototypes
  where prototype_key='smart-order-sdb-platform-v1'
    and metadata->>'b3_gate'='passed'
  limit 1;

  if v_status is distinct from 'draft' then raise exception 'b4_candidate_must_remain_draft'; end if;
  if not coalesce((private.release_engineering_status()->>'ok')::boolean,false) then
    raise exception 'b4_release_engineering_not_ready';
  end if;
  if not exists(
    select 1 from private.master_template_snapshots
    where prototype_key='smart-order-sdb-platform-v1'
      and frozen
      and snapshot_version='v1'
  ) then raise exception 'b4_master_snapshot_missing'; end if;
end $$;

create table if not exists private.master_clone_rehearsal_evidence (
  id uuid primary key default extensions.gen_random_uuid(),
  prototype_id uuid not null references private.platform_prototypes(id) on delete restrict,
  prototype_key text not null,
  template_snapshot_sha256 text not null check (template_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  source_git_sha text not null check (source_git_sha ~ '^[0-9a-f]{40}$'),
  source_migration_head text not null check (source_migration_head ~ '^[0-9]{14}$'),
  clone_contract text not null,
  clone_tenant_id uuid not null,
  clone_origin text not null,
  passed boolean not null check (passed is true),
  residue_zero boolean not null check (residue_zero is true),
  evidence jsonb not null check (jsonb_typeof(evidence)='object'),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  checked_at timestamptz not null default now()
);

alter table private.master_clone_rehearsal_evidence enable row level security;
revoke all on private.master_clone_rehearsal_evidence from public,anon,authenticated;
grant select on private.master_clone_rehearsal_evidence to service_role;

create or replace function private.master_clone_rehearsal_evidence_guard_b4()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  raise exception 'master_clone_rehearsal_evidence_immutable';
end
$$;
revoke all on function private.master_clone_rehearsal_evidence_guard_b4()
from public,anon,authenticated;

drop trigger if exists trg_master_clone_rehearsal_evidence_immutable_b4
on private.master_clone_rehearsal_evidence;
create trigger trg_master_clone_rehearsal_evidence_immutable_b4
before update or delete on private.master_clone_rehearsal_evidence
for each row execute function private.master_clone_rehearsal_evidence_guard_b4();

create or replace function private.run_master_clone_rehearsal_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_proto private.platform_prototypes%rowtype;
  v_snap private.master_template_snapshots%rowtype;
  v_clone jsonb;
  v_clone_id uuid;
  v_ref uuid;
  v_nonce text:=substr(replace(extensions.gen_random_uuid()::text,'-',''),1,12);
  v_slug text;
  v_origin text;
  v_ref_menu_sig text;
  v_clone_menu_sig text;
  v_sheet_reuse integer;
  v_qr_reuse integer;
  v_history_rows integer;
  v_residue integer;
  v_evidence jsonb;
  v_evidence_sha text;
  v_evidence_id uuid:=extensions.gen_random_uuid();
begin
  select * into v_proto
  from private.platform_prototypes
  where prototype_key='smart-order-sdb-platform-v1'
    and status='draft'
    and metadata->>'b3_gate'='passed'
  limit 1;
  if v_proto.id is null then raise exception 'b4_candidate_not_draft'; end if;

  if not coalesce((private.release_engineering_status()->>'ok')::boolean,false) then
    raise exception 'b4_release_engineering_not_ready';
  end if;

  select * into v_snap
  from private.master_template_snapshots
  where prototype_key=v_proto.prototype_key and frozen
  limit 1;
  if v_snap.prototype_key is null then raise exception 'b4_master_snapshot_unavailable'; end if;

  v_ref:=v_proto.reference_tenant_id;
  v_slug:='b4-cert-'||v_nonce;
  v_origin:='https://'||v_slug||'.invalid';

  v_clone:=private.provision_tenant_from_master_v1(
    v_proto.prototype_key,
    v_slug,
    'B4 Clone Certification '||v_nonce,
    v_origin,
    'b4.cert.'||v_nonce||'@example.invalid',
    jsonb_build_object(
      '2026','b4-cert-'||v_nonce||'-2026',
      '2027','b4-cert-'||v_nonce||'-2027',
      '2028','b4-cert-'||v_nonce||'-2028',
      '2029','b4-cert-'||v_nonce||'-2029',
      '2030','b4-cert-'||v_nonce||'-2030'
    ),
    null
  );

  if not coalesce((v_clone->>'ok')::boolean,false) then raise exception 'b4_clone_provision_failed'; end if;
  v_clone_id:=(v_clone->>'tenant_id')::uuid;

  if v_clone_id=v_ref then raise exception 'b4_clone_identity_collision'; end if;

  if not exists(
    select 1 from private.platform_tenants
    where id=v_clone_id and status='active'
      and isolation_mode='shared_database_rls'
      and source_prototype_key=v_proto.prototype_key
  ) then raise exception 'b4_clone_tenant_contract_failed'; end if;

  if not exists(
    select 1 from private.tenant_runtime_config c
    where c.tenant_id=v_clone_id and c.enabled
      and c.public_origin=v_origin and c.admin_origin=v_origin and c.kds_origin=v_origin
      and c.settings->>'canonical_origin'=v_origin
      and c.settings->>'database_url'=v_origin||'/database'
      and c.settings->'surface_routes'->>'public'='/'
      and c.settings->'surface_routes'->>'admin'='/admin'
      and c.settings->'surface_routes'->>'kds'='/kds'
      and c.settings->'surface_routes'->>'database'='/database'
  ) then raise exception 'b4_clone_runtime_contract_failed'; end if;

  if (select count(*) from public.menu_items where tenant_id=v_clone_id) <>
     (select count(*) from public.menu_items where tenant_id=v_ref)
  then raise exception 'b4_clone_menu_count_mismatch'; end if;

  select md5(string_agg(name||'|'||category||'|'||price||'|'||display_order,';' order by display_order,name))
    into v_ref_menu_sig from public.menu_items where tenant_id=v_ref;
  select md5(string_agg(name||'|'||category||'|'||price||'|'||display_order,';' order by display_order,name))
    into v_clone_menu_sig from public.menu_items where tenant_id=v_clone_id;
  if v_ref_menu_sig is distinct from v_clone_menu_sig then raise exception 'b4_clone_menu_semantics_mismatch'; end if;

  if exists(
    select 1 from public.menu_items c
    join public.menu_items m on m.id=c.id
    where c.tenant_id=v_clone_id and m.tenant_id=v_ref
  ) then raise exception 'b4_clone_menu_id_collision'; end if;

  if (select count(*) from private.tenant_sheet_targets where tenant_id=v_clone_id and enabled)<>5
  then raise exception 'b4_clone_sheet_target_count_mismatch'; end if;

  select count(*) into v_sheet_reuse
  from private.tenant_sheet_targets c
  join private.tenant_sheet_targets m
    on m.tenant_id=v_ref and m.spreadsheet_id=c.spreadsheet_id
  where c.tenant_id=v_clone_id;
  if v_sheet_reuse<>0 then raise exception 'b4_master_sheet_id_leaked'; end if;

  if not exists(
    select 1 from private.tenant_writer_config
    where tenant_id=v_clone_id
      and not enabled
      and writer_url is null
      and writer_secret_id is null
  ) then raise exception 'b4_writer_secret_or_url_cloned'; end if;

  if (select count(*) from private.tenant_table_qr_signatures where tenant_id=v_clone_id and is_active) <>
     (select table_count from private.tenant_runtime_config where tenant_id=v_clone_id)
  then raise exception 'b4_clone_qr_count_mismatch'; end if;

  select count(*) into v_qr_reuse
  from private.tenant_table_qr_signatures c
  join private.tenant_table_qr_signatures m
    on m.tenant_id=v_ref
   and m.table_number=c.table_number
   and m.signature_hash=c.signature_hash
  where c.tenant_id=v_clone_id;
  if v_qr_reuse<>0 then raise exception 'b4_master_qr_signature_leaked'; end if;

  select
    (select count(*) from public.orders where tenant_id=v_clone_id)
    +(select count(*) from public.order_events where tenant_id=v_clone_id)
    +(select count(*) from public.order_history_archive where tenant_id=v_clone_id)
    +(select count(*) from public.sheet_sync_outbox where tenant_id=v_clone_id)
    +(select count(*) from private.admin_sessions where tenant_id=v_clone_id)
  into v_history_rows;
  if v_history_rows<>0 then raise exception 'b4_operational_history_cloned'; end if;

  if (select qris_asset from private.tenant_runtime_config where tenant_id=v_clone_id) is not null
  then raise exception 'b4_qris_asset_cloned'; end if;

  if not coalesce((public.master_prototype_runtime_context(null,v_origin,'public')->>'ok')::boolean,false)
     or (public.master_prototype_runtime_context(null,v_origin,'public')->>'tenant_id')::uuid<>v_clone_id
  then raise exception 'b4_clone_origin_resolution_failed'; end if;

  if (public.master_prototype_runtime_context(
        null,
        (select public_origin from private.tenant_runtime_config where tenant_id=v_ref),
        'public'
      )->>'tenant_id')::uuid<>v_ref
  then raise exception 'b4_master_origin_isolation_failed'; end if;

  v_evidence:=jsonb_build_object(
    'ok',true,
    'contract','smart-order-b4-clone-certification-v1',
    'prototype_key',v_proto.prototype_key,
    'template_snapshot_sha256',v_snap.snapshot_sha256,
    'clone_tenant_id',v_clone_id,
    'clone_origin',v_origin,
    'identity_unique',true,
    'single_domain_four_surface',true,
    'shared_database_rls',true,
    'menu_semantics_preserved',true,
    'menu_ids_isolated',true,
    'sheet_targets',5,
    'master_sheet_ids_reused',false,
    'writer_secret_cloned',false,
    'writer_url_cloned',false,
    'qris_asset_cloned',false,
    'qr_signatures_unique',true,
    'operational_history_cloned',false,
    'origin_isolation',true,
    'source_edits_required',false,
    'source_clone_required',false,
    'database_project_clone_required',false
  );
  v_evidence_sha:=encode(extensions.digest(convert_to(v_evidence::text,'UTF8'),'sha256'),'hex');

  -- Explicit disposable cleanup. Delete tenant-local public rows first because
  -- several historical foreign keys intentionally use ON DELETE RESTRICT.
  delete from public.menu_items where tenant_id=v_clone_id;
  delete from public.sheet_sync_outbox where tenant_id=v_clone_id;
  delete from public.orders where tenant_id=v_clone_id;
  delete from public.order_events where tenant_id=v_clone_id;
  delete from public.order_history_archive where tenant_id=v_clone_id;
  delete from public.public_rum_samples where tenant_id=v_clone_id;

  delete from private.frontend_performance_samples where tenant_id=v_clone_id;
  delete from private.integration_events where tenant_id=v_clone_id;
  delete from private.kds_observability_samples where tenant_id=v_clone_id;
  delete from private.order_identity_registry where tenant_id=v_clone_id;
  delete from private.order_rate_limits where tenant_id=v_clone_id;

  delete from private.platform_tenants where id=v_clone_id;

  select
    (select count(*) from private.platform_tenants where id=v_clone_id)
    +(select count(*) from private.tenant_origin_aliases where origin=v_origin)
    +(select count(*) from public.menu_items where tenant_id=v_clone_id)
    +(select count(*) from public.sheet_sync_outbox where tenant_id=v_clone_id)
  into v_residue;
  if v_residue<>0 then raise exception 'b4_clone_cleanup_residue'; end if;

  insert into private.master_clone_rehearsal_evidence(
    id,prototype_id,prototype_key,template_snapshot_sha256,
    source_git_sha,source_migration_head,clone_contract,
    clone_tenant_id,clone_origin,passed,residue_zero,
    evidence,evidence_sha256,checked_at
  ) values(
    v_evidence_id,v_proto.id,v_proto.prototype_key,v_snap.snapshot_sha256,
    '51d1da293a849ae94312cfe5c255de1ce9b692c1',
    '20260927160000',
    'smart-order-b4-clone-certification-v1',
    v_clone_id,v_origin,true,true,
    v_evidence || jsonb_build_object('cleanup_residue',0),
    v_evidence_sha,now()
  );

  return jsonb_build_object(
    'ok',true,
    'contract','smart-order-b4-clone-certification-v1',
    'evidence_id',v_evidence_id,
    'evidence_sha256',v_evidence_sha,
    'clone_tenant_id',v_clone_id,
    'clone_origin',v_origin,
    'cleanup_residue',0,
    'candidate_status','draft'
  );
exception when others then
  raise;
end
$$;

revoke all on function private.run_master_clone_rehearsal_v1()
from public,anon,authenticated;
grant execute on function private.run_master_clone_rehearsal_v1()
to service_role;

update private.release_policy
set source_control_mode='git_b4_clone_certification',
    ci_status='github_actions_b4_clone_certification_candidate',
    notes=coalesce(notes,'') || E'\n2026-09-27 B4.2: persisted immutable clone-certification evidence. Candidate remains draft; no promotion.',
    updated_at=now()
where id=1;

insert into private.release_baseline(
  id,release_label,migration_head,schema_fingerprint,cron_fingerprint,
  manifest_fingerprint,captured_at,notes
)
values(
  1,'b4-clone-certification-20260927','20260927172500',
  private.release_schema_fingerprint(),private.release_cron_fingerprint(),
  private.release_manifest_fingerprint(),now(),
  'B4.2 clone certification evidence baseline. Candidate remains draft.'
)
on conflict(id) do update
set release_label=excluded.release_label,
    migration_head=excluded.migration_head,
    schema_fingerprint=excluded.schema_fingerprint,
    cron_fingerprint=excluded.cron_fingerprint,
    manifest_fingerprint=excluded.manifest_fingerprint,
    captured_at=excluded.captured_at,
    notes=excluded.notes;

commit;
