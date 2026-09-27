-- SMART ORDER B4.3: final master-promotion foundation + immutable freeze contract.
-- This migration installs the one-shot finalizer but does NOT promote by itself.

begin;

do $$
declare v_status text;
begin
  select status into v_status
  from private.platform_prototypes
  where prototype_key='smart-order-sdb-platform-v1'
    and metadata->>'b3_gate'='passed'
  limit 1;

  if v_status is distinct from 'draft' then raise exception 'b4_final_candidate_must_be_draft'; end if;
  if not coalesce((private.release_engineering_status()->>'ok')::boolean,false) then
    raise exception 'b4_final_release_engineering_not_ready';
  end if;
end $$;

create table if not exists private.master_freeze_manifests (
  id uuid primary key,
  prototype_id uuid not null references private.platform_prototypes(id) on delete restrict,
  prototype_key text not null,
  release_tag text not null unique,
  release_git_sha text not null check (release_git_sha ~ '^[0-9a-f]{40}$'),
  promotion_base_sha text not null check (promotion_base_sha ~ '^[0-9a-f]{40}$'),
  migration_head text not null check (migration_head ~ '^[0-9]{14}$'),
  template_snapshot_sha256 text not null check (template_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  clone_evidence_id uuid not null references private.master_clone_rehearsal_evidence(id) on delete restrict,
  clone_evidence_sha256 text not null check (clone_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  schema_fingerprint text not null check (schema_fingerprint ~ '^[0-9a-f]{64}$'),
  cron_fingerprint text not null check (cron_fingerprint ~ '^[0-9a-f]{64}$'),
  release_manifest_fingerprint text not null check (release_manifest_fingerprint ~ '^[0-9a-f]{64}$'),
  canonical_origin text not null,
  vercel_deployment text,
  supabase_project_ref text not null,
  tenancy_mode text not null check (tenancy_mode='shared_database_rls'),
  architecture text not null check (architecture='single_domain_four_surface_v1'),
  previous_master_key text,
  manifest jsonb not null check (jsonb_typeof(manifest)='object'),
  manifest_sha256 text not null check (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  promoted_at timestamptz not null default now()
);

alter table private.master_freeze_manifests enable row level security;
revoke all on private.master_freeze_manifests from public,anon,authenticated;
grant select on private.master_freeze_manifests to service_role;

create or replace function private.master_freeze_manifest_guard_b4()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  raise exception 'master_freeze_manifest_immutable';
end
$$;
revoke all on function private.master_freeze_manifest_guard_b4()
from public,anon,authenticated;

drop trigger if exists trg_master_freeze_manifest_immutable_b4
on private.master_freeze_manifests;
create trigger trg_master_freeze_manifest_immutable_b4
before update or delete on private.master_freeze_manifests
for each row execute function private.master_freeze_manifest_guard_b4();

-- At most one active prototype and one active clone template per organization.
create unique index if not exists platform_prototypes_one_active_per_org_b4
  on private.platform_prototypes(organization_id)
  where status='active';

create unique index if not exists platform_clone_templates_one_active_per_org_b4
  on private.platform_clone_templates(organization_id)
  where status='active';

-- Once SMART ORDER becomes active, its identity row becomes immutable.
create or replace function private.smart_order_master_prototype_guard_b4()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if old.prototype_key='smart-order-sdb-platform-v1' and old.status='active' then
    raise exception 'smart_order_master_prototype_immutable';
  end if;
  return new;
end
$$;
revoke all on function private.smart_order_master_prototype_guard_b4()
from public,anon,authenticated;

drop trigger if exists trg_smart_order_master_prototype_immutable_b4
on private.platform_prototypes;
create trigger trg_smart_order_master_prototype_immutable_b4
before update or delete on private.platform_prototypes
for each row execute function private.smart_order_master_prototype_guard_b4();

create or replace function private.smart_order_master_clone_template_guard_b4()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if old.template_key='smart-order-sdb-master-v1' and old.status='active' then
    raise exception 'smart_order_master_clone_template_immutable';
  end if;
  return new;
end
$$;
revoke all on function private.smart_order_master_clone_template_guard_b4()
from public,anon,authenticated;

drop trigger if exists trg_smart_order_master_clone_template_immutable_b4
on private.platform_clone_templates;
create trigger trg_smart_order_master_clone_template_immutable_b4
before update or delete on private.platform_clone_templates
for each row execute function private.smart_order_master_clone_template_guard_b4();

-- Evolve the B2 security health contract so final ACTIVE master state is valid while
-- retaining the same security checks. Draft remains valid only during pre-promotion.
create or replace function public.master_runtime_security_health_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  c private.tenant_runtime_config%rowtype;
  v_hardened_at timestamptz;
  v_rls_off integer;
  v_anon_internal integer;
  v_canonical_aliases integer;
  v_enabled_previews integer;
  v_qr_valid integer;
  v_tenant_null_sessions integer;
  v_bad_kds_fp integer;
  v_new_admin_unbound integer;
  v_new_bad_ttl integer;
  v_routes_ok boolean;
  v_prototype_status text;
  v_prototype_state_valid boolean;
  v_client_rls boolean;
  v_ok boolean;
begin
  select * into c from private.tenant_runtime_config
  where tenant_id=p_tenant_id and enabled;

  if c.tenant_id is null then
    return jsonb_build_object('ok',false,'error','tenant_unavailable');
  end if;

  begin
    v_hardened_at:=(c.settings->'security_contract'->>'hardened_at')::timestamptz;
  exception when others then
    v_hardened_at:=null;
  end;

  select count(*) into v_rls_off
  from pg_class pc join pg_namespace pn on pn.oid=pc.relnamespace
  where pn.nspname in ('public','private')
    and pc.relkind='r'
    and not pc.relrowsecurity;

  select count(*) into v_anon_internal
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='internal_rpc'
    and p.prokind='f'
    and has_function_privilege('anon',p.oid,'EXECUTE');

  select count(*) into v_canonical_aliases
  from private.tenant_origin_aliases
  where tenant_id=p_tenant_id and enabled and alias_kind='canonical';

  select count(*) into v_enabled_previews
  from private.tenant_origin_aliases
  where tenant_id=p_tenant_id and enabled and alias_kind='preview';

  select count(*) into v_qr_valid
  from private.tenant_table_qr_signatures
  where tenant_id=p_tenant_id
    and is_active
    and table_number between 1 and c.table_count
    and signature_hash ~ '^[a-f0-9]{64}$';

  select count(*) into v_tenant_null_sessions
  from private.admin_sessions where tenant_id is null;

  select count(*) into v_bad_kds_fp
  from private.admin_sessions
  where expires_at>now() and session_scope='kds' and client_fingerprint_hash is null;

  select count(*) into v_new_admin_unbound
  from private.admin_sessions
  where v_hardened_at is not null
    and created_at>=v_hardened_at
    and session_scope='admin'
    and client_fingerprint_hash is null;

  select count(*) into v_new_bad_ttl
  from private.admin_sessions
  where v_hardened_at is not null
    and created_at>=v_hardened_at
    and expires_at>created_at+interval '6 hours';

  select enforce_client_rls into v_client_rls
  from private.platform_tenancy_state where id=1;

  v_routes_ok :=
    coalesce((public.master_prototype_runtime_context(null,c.public_origin,'public')->>'ok')::boolean,false)
    and public.master_prototype_runtime_context(null,c.public_origin,'public')->>'surface_route'='/'
    and coalesce((public.master_prototype_runtime_context(null,c.public_origin,'admin')->>'ok')::boolean,false)
    and public.master_prototype_runtime_context(null,c.public_origin,'admin')->>'surface_route'='/admin'
    and coalesce((public.master_prototype_runtime_context(null,c.public_origin,'kds')->>'ok')::boolean,false)
    and public.master_prototype_runtime_context(null,c.public_origin,'kds')->>'surface_route'='/kds'
    and coalesce((public.master_prototype_runtime_context(null,c.public_origin,'database')->>'ok')::boolean,false)
    and public.master_prototype_runtime_context(null,c.public_origin,'database')->>'surface_route'='/database';

  select status into v_prototype_status
  from private.platform_prototypes
  where reference_tenant_id=p_tenant_id
    and prototype_key='smart-order-sdb-platform-v1'
  limit 1;

  v_prototype_state_valid:=v_prototype_status in ('draft','active');

  v_ok :=
    v_rls_off=0
    and v_anon_internal=0
    and coalesce(v_client_rls,false)
    and c.public_origin=c.admin_origin
    and c.public_origin=c.kds_origin
    and c.public_origin=c.settings->>'canonical_origin'
    and c.require_table_qr_signature
    and coalesce((c.settings->>'require_table_qr_signature')::boolean,false)
    and v_canonical_aliases=1
    and v_enabled_previews=0
    and v_qr_valid=c.table_count
    and v_tenant_null_sessions=0
    and v_bad_kds_fp=0
    and v_new_admin_unbound=0
    and v_new_bad_ttl=0
    and v_routes_ok
    and v_prototype_state_valid
    and v_hardened_at is not null;

  return jsonb_build_object(
    'ok',v_ok,
    'contract','smart-order-master-runtime-security-v2',
    'tenant_id',p_tenant_id,
    'checks',jsonb_build_object(
      'rls_off_tables',v_rls_off,
      'anon_internal_rpc_execute',v_anon_internal,
      'client_rls_enforced',coalesce(v_client_rls,false),
      'single_canonical_origin',c.public_origin=c.admin_origin and c.public_origin=c.kds_origin and c.public_origin=c.settings->>'canonical_origin',
      'canonical_aliases',v_canonical_aliases,
      'enabled_preview_aliases',v_enabled_previews,
      'signed_table_qr_required',c.require_table_qr_signature,
      'valid_active_table_signatures',v_qr_valid,
      'table_count',c.table_count,
      'tenant_null_sessions',v_tenant_null_sessions,
      'active_kds_without_fingerprint',v_bad_kds_fp,
      'post_cutover_admin_without_fingerprint',v_new_admin_unbound,
      'post_cutover_sessions_over_6h',v_new_bad_ttl,
      'four_surface_routes',v_routes_ok,
      'prototype_status',v_prototype_status,
      'prototype_state_valid',v_prototype_state_valid,
      'candidate_still_draft',v_prototype_status='draft',
      'master_active',v_prototype_status='active',
      'hardened_at',v_hardened_at
    )
  );
end
$$;
revoke all on function public.master_runtime_security_health_v1(uuid)
from public,anon,authenticated;
grant execute on function public.master_runtime_security_health_v1(uuid) to service_role;

create or replace function private.finalize_master_promotion_v1(
  p_release_tag text,
  p_release_git_sha text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_proto private.platform_prototypes%rowtype;
  v_old private.platform_prototypes%rowtype;
  v_snap private.master_template_snapshots%rowtype;
  v_ev private.master_clone_rehearsal_evidence%rowtype;
  v_manifest_id uuid:=extensions.gen_random_uuid();
  v_schema text;
  v_cron text;
  v_release_manifest text;
  v_manifest jsonb;
  v_manifest_sha text;
  v_deployment text;
begin
  if coalesce(p_release_tag,'') !~ '^smart-order-sdb-master-v[0-9]+\.[0-9]+\.[0-9]+$' then
    raise exception 'invalid_master_release_tag';
  end if;
  if coalesce(p_release_git_sha,'') !~ '^[0-9a-f]{40}$' then
    raise exception 'invalid_master_release_git_sha';
  end if;

  select * into v_proto
  from private.platform_prototypes
  where prototype_key='smart-order-sdb-platform-v1'
    and status='draft'
    and metadata->>'b3_gate'='passed'
  limit 1;
  if v_proto.id is null then raise exception 'master_candidate_not_draft'; end if;

  if not coalesce((private.release_engineering_status()->>'ok')::boolean,false) then
    raise exception 'master_release_engineering_not_ready';
  end if;

  select * into v_snap
  from private.master_template_snapshots
  where prototype_key=v_proto.prototype_key and frozen
  limit 1;
  if v_snap.prototype_key is null then raise exception 'master_snapshot_unavailable'; end if;

  select e.* into v_ev
  from private.master_clone_rehearsal_evidence e
  where e.prototype_id=v_proto.id
    and e.prototype_key=v_proto.prototype_key
    and e.template_snapshot_sha256=v_snap.snapshot_sha256
    and e.passed and e.residue_zero
    and e.checked_at>=now()-interval '24 hours'
  order by e.checked_at desc
  limit 1;
  if v_ev.id is null then raise exception 'fresh_clone_certification_missing'; end if;

  if exists(select 1 from private.platform_tenants where slug like 'b4-cert-%')
     or exists(select 1 from private.tenant_origin_aliases where origin like 'https://b4-cert-%.invalid')
  then raise exception 'clone_rehearsal_residue_present'; end if;

  select * into v_old
  from private.platform_prototypes
  where prototype_key='rohmat-master-prototype-v1'
  limit 1;

  -- Update release policy first so its final state is included in the manifest fingerprint.
  update private.release_policy
  set source_control_mode='git_master_frozen',
      ci_status='github_actions_b4_final_freeze_pass',
      required_checks=jsonb_build_array(
        'migration_head','schema_fingerprint','cron_fingerprint','manifest_fingerprint',
        'rollback_refs','change_control','integration_contracts','tenant_isolation',
        'integrated_e2e','data_consistency','release_reliability','performance',
        'four_surface_network','ux','dr_restore_rehearsal','production_health',
        'clone_certification','single_active_master','immutable_master_manifest',
        'source_release_tag','postfreeze_clone_rehearsal'
      ),
      notes=coalesce(notes,'') || E'\n2026-09-27 B4 FINAL: SMART ORDER SDB promoted from certified cloneable candidate to immutable master v1.0.0.',
      updated_at=now()
  where id=1;

  v_schema:=private.release_schema_fingerprint();
  v_cron:=private.release_cron_fingerprint();
  v_release_manifest:=private.release_manifest_fingerprint();
  v_deployment:=v_proto.metadata->>'b1_deployment_id';

  v_manifest:=jsonb_build_object(
    'contract','smart-order-master-freeze-v1',
    'prototype_key',v_proto.prototype_key,
    'release_tag',p_release_tag,
    'release_git_sha',p_release_git_sha,
    'promotion_base_sha','2aeade8495c73639d4cac01fce9906daea738313',
    'migration_head','20260927174000',
    'template_snapshot_sha256',v_snap.snapshot_sha256,
    'clone_evidence_id',v_ev.id,
    'clone_evidence_sha256',v_ev.evidence_sha256,
    'schema_fingerprint',v_schema,
    'cron_fingerprint',v_cron,
    'release_manifest_fingerprint',v_release_manifest,
    'canonical_origin',v_proto.metadata->>'canonical_origin',
    'vercel_deployment',v_deployment,
    'supabase_project_ref',v_proto.supabase_project_ref,
    'tenancy_mode','shared_database_rls',
    'architecture','single_domain_four_surface_v1',
    'previous_master_key',case when v_old.id is null then null else v_old.prototype_key end,
    'immutable',true
  );
  v_manifest_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  if v_old.id is not null and v_old.status='active' then
    update private.platform_prototypes
    set status='deprecated',
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'superseded_by','smart-order-sdb-platform-v1',
          'superseded_at',now(),
          'replacement_release_tag',p_release_tag
        )
    where id=v_old.id;
  end if;

  insert into private.platform_clone_templates(
    organization_id,template_key,name,source_tenant_id,status,
    github_repo,github_branch,supabase_isolation_mode,vercel_topology,metadata
  )
  values(
    v_proto.organization_id,
    'smart-order-sdb-master-v1',
    'SMART ORDER SDB Master v1.0.0',
    v_proto.reference_tenant_id,
    'active',
    v_proto.github_repo,
    v_proto.github_branch,
    'shared_database_rls',
    'single_domain_four_surface',
    jsonb_build_object(
      'prototype_key',v_proto.prototype_key,
      'release_tag',p_release_tag,
      'release_git_sha',p_release_git_sha,
      'freeze_manifest_id',v_manifest_id,
      'freeze_manifest_sha256',v_manifest_sha,
      'architecture','single_domain_four_surface_v1',
      'surface_routes',jsonb_build_object('public','/','admin','/admin','kds','/kds','database','/database'),
      'spreadsheet_provider','google_drive',
      'immutable',true
    )
  )
  on conflict(organization_id,template_key) do nothing;

  if not exists(
    select 1 from private.platform_clone_templates
    where organization_id=v_proto.organization_id
      and template_key='smart-order-sdb-master-v1'
      and status='active'
      and metadata->>'release_git_sha'=p_release_git_sha
  ) then raise exception 'active_clone_template_conflict'; end if;

  update private.platform_prototypes
  set name='SMART ORDER SDB Master v1.0.0',
      status='active',
      release_tag=p_release_tag,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'freeze_state','master_frozen',
        'master_version','v1.0.0',
        'promoted_at',now(),
        'immutable',true,
        'release_git_sha',p_release_git_sha,
        'freeze_manifest_id',v_manifest_id,
        'freeze_manifest_sha256',v_manifest_sha,
        'clone_certification_id',v_ev.id,
        'clone_certification_sha256',v_ev.evidence_sha256,
        'supersedes_master_key',case when v_old.id is null then null else v_old.prototype_key end
      )
  where id=v_proto.id and status='draft';

  if not found then raise exception 'master_promotion_update_failed'; end if;

  insert into private.master_freeze_manifests(
    id,prototype_id,prototype_key,release_tag,release_git_sha,promotion_base_sha,
    migration_head,template_snapshot_sha256,clone_evidence_id,clone_evidence_sha256,
    schema_fingerprint,cron_fingerprint,release_manifest_fingerprint,
    canonical_origin,vercel_deployment,supabase_project_ref,tenancy_mode,
    architecture,previous_master_key,manifest,manifest_sha256,promoted_at
  )
  values(
    v_manifest_id,v_proto.id,v_proto.prototype_key,p_release_tag,p_release_git_sha,
    '2aeade8495c73639d4cac01fce9906daea738313',
    '20260927174000',v_snap.snapshot_sha256,v_ev.id,v_ev.evidence_sha256,
    v_schema,v_cron,v_release_manifest,
    v_proto.metadata->>'canonical_origin',v_deployment,v_proto.supabase_project_ref,
    'shared_database_rls','single_domain_four_surface_v1',
    case when v_old.id is null then null else v_old.prototype_key end,
    v_manifest,v_manifest_sha,now()
  );

  insert into private.release_baseline(
    id,release_label,migration_head,schema_fingerprint,cron_fingerprint,
    manifest_fingerprint,captured_at,notes
  )
  values(
    1,'smart-order-sdb-master-v1.0.0','20260927174000',
    v_schema,v_cron,v_release_manifest,now(),
    'B4 final immutable master freeze. Source is pinned by release tag + git SHA.'
  )
  on conflict(id) do update
  set release_label=excluded.release_label,
      migration_head=excluded.migration_head,
      schema_fingerprint=excluded.schema_fingerprint,
      cron_fingerprint=excluded.cron_fingerprint,
      manifest_fingerprint=excluded.manifest_fingerprint,
      captured_at=excluded.captured_at,
      notes=excluded.notes;

  return jsonb_build_object(
    'ok',true,
    'contract','smart-order-master-freeze-v1',
    'prototype_key',v_proto.prototype_key,
    'status','active',
    'release_tag',p_release_tag,
    'release_git_sha',p_release_git_sha,
    'freeze_manifest_id',v_manifest_id,
    'freeze_manifest_sha256',v_manifest_sha,
    'clone_evidence_id',v_ev.id,
    'clone_evidence_sha256',v_ev.evidence_sha256,
    'previous_master_key',case when v_old.id is null then null else v_old.prototype_key end,
    'previous_master_status',case when v_old.id is null then null else 'deprecated' end,
    'immutable',true
  );
end
$$;
revoke all on function private.finalize_master_promotion_v1(text,text)
from public,anon,authenticated;
grant execute on function private.finalize_master_promotion_v1(text,text) to service_role;

create or replace function private.run_postfreeze_clone_rehearsal_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $
declare
  v_proto private.platform_prototypes%rowtype;
  v_manifest private.master_freeze_manifests%rowtype;
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
    and status='active'
    and release_tag is not null
    and metadata->>'freeze_state'='master_frozen'
    and coalesce((metadata->>'immutable')::boolean,false)
  limit 1;
  if v_proto.id is null then raise exception 'frozen_master_not_active'; end if;

  select * into v_manifest
  from private.master_freeze_manifests
  where prototype_id=v_proto.id
    and prototype_key=v_proto.prototype_key
    and release_tag=v_proto.release_tag
  order by promoted_at desc
  limit 1;
  if v_manifest.id is null then raise exception 'freeze_manifest_unavailable'; end if;

  if v_manifest.release_git_sha is distinct from v_proto.metadata->>'release_git_sha'
  then raise exception 'freeze_manifest_git_sha_mismatch'; end if;

  select * into v_snap
  from private.master_template_snapshots
  where prototype_key=v_proto.prototype_key
    and frozen
    and snapshot_sha256=v_manifest.template_snapshot_sha256
  limit 1;
  if v_snap.prototype_key is null then raise exception 'frozen_master_snapshot_unavailable'; end if;

  v_ref:=v_proto.reference_tenant_id;
  v_slug:='b4-postfreeze-'||v_nonce;
  v_origin:='https://'||v_slug||'.invalid';

  v_clone:=private.provision_tenant_from_master_v1(
    v_proto.prototype_key,
    v_slug,
    'B4 Post-Freeze Clone '||v_nonce,
    v_origin,
    'b4.postfreeze.'||v_nonce||'@example.invalid',
    jsonb_build_object(
      '2026','b4-postfreeze-'||v_nonce||'-2026',
      '2027','b4-postfreeze-'||v_nonce||'-2027',
      '2028','b4-postfreeze-'||v_nonce||'-2028',
      '2029','b4-postfreeze-'||v_nonce||'-2029',
      '2030','b4-postfreeze-'||v_nonce||'-2030'
    ),
    null
  );

  if not coalesce((v_clone->>'ok')::boolean,false) then
    raise exception 'postfreeze_clone_provision_failed';
  end if;
  v_clone_id:=(v_clone->>'tenant_id')::uuid;

  if v_clone_id=v_ref then raise exception 'postfreeze_clone_identity_collision'; end if;

  if not exists(
    select 1 from private.platform_tenants
    where id=v_clone_id
      and status='active'
      and isolation_mode='shared_database_rls'
      and source_prototype_key=v_proto.prototype_key
  ) then raise exception 'postfreeze_clone_tenant_contract_failed'; end if;

  if not exists(
    select 1 from private.tenant_runtime_config c
    where c.tenant_id=v_clone_id
      and c.enabled
      and c.public_origin=v_origin
      and c.admin_origin=v_origin
      and c.kds_origin=v_origin
      and c.settings->>'canonical_origin'=v_origin
      and c.settings->>'database_url'=v_origin||'/database'
      and c.settings->'surface_routes'->>'public'='/'
      and c.settings->'surface_routes'->>'admin'='/admin'
      and c.settings->'surface_routes'->>'kds'='/kds'
      and c.settings->'surface_routes'->>'database'='/database'
  ) then raise exception 'postfreeze_clone_runtime_contract_failed'; end if;

  if (select count(*) from public.menu_items where tenant_id=v_clone_id) <>
     (select count(*) from public.menu_items where tenant_id=v_ref)
  then raise exception 'postfreeze_clone_menu_count_mismatch'; end if;

  select md5(string_agg(name||'|'||category||'|'||price||'|'||display_order,';' order by display_order,name))
    into v_ref_menu_sig
  from public.menu_items where tenant_id=v_ref;

  select md5(string_agg(name||'|'||category||'|'||price||'|'||display_order,';' order by display_order,name))
    into v_clone_menu_sig
  from public.menu_items where tenant_id=v_clone_id;

  if v_ref_menu_sig is distinct from v_clone_menu_sig
  then raise exception 'postfreeze_clone_menu_semantics_mismatch'; end if;

  if exists(
    select 1 from public.menu_items c
    join public.menu_items m on m.id=c.id
    where c.tenant_id=v_clone_id and m.tenant_id=v_ref
  ) then raise exception 'postfreeze_clone_menu_id_collision'; end if;

  if (select count(*) from private.tenant_sheet_targets where tenant_id=v_clone_id and enabled)<>5
  then raise exception 'postfreeze_clone_sheet_target_count_mismatch'; end if;

  select count(*) into v_sheet_reuse
  from private.tenant_sheet_targets c
  join private.tenant_sheet_targets m
    on m.tenant_id=v_ref and m.spreadsheet_id=c.spreadsheet_id
  where c.tenant_id=v_clone_id;
  if v_sheet_reuse<>0 then raise exception 'postfreeze_master_sheet_id_leaked'; end if;

  if not exists(
    select 1 from private.tenant_writer_config
    where tenant_id=v_clone_id
      and not enabled
      and writer_url is null
      and writer_secret_id is null
  ) then raise exception 'postfreeze_writer_secret_or_url_cloned'; end if;

  if (select count(*) from private.tenant_table_qr_signatures where tenant_id=v_clone_id and is_active) <>
     (select table_count from private.tenant_runtime_config where tenant_id=v_clone_id)
  then raise exception 'postfreeze_clone_qr_count_mismatch'; end if;

  select count(*) into v_qr_reuse
  from private.tenant_table_qr_signatures c
  join private.tenant_table_qr_signatures m
    on m.tenant_id=v_ref
   and m.table_number=c.table_number
   and m.signature_hash=c.signature_hash
  where c.tenant_id=v_clone_id;
  if v_qr_reuse<>0 then raise exception 'postfreeze_master_qr_signature_leaked'; end if;

  select
    (select count(*) from public.orders where tenant_id=v_clone_id)
    +(select count(*) from public.order_events where tenant_id=v_clone_id)
    +(select count(*) from public.order_history_archive where tenant_id=v_clone_id)
    +(select count(*) from public.sheet_sync_outbox where tenant_id=v_clone_id)
    +(select count(*) from private.admin_sessions where tenant_id=v_clone_id)
  into v_history_rows;
  if v_history_rows<>0 then raise exception 'postfreeze_operational_history_cloned'; end if;

  if (select qris_asset from private.tenant_runtime_config where tenant_id=v_clone_id) is not null
  then raise exception 'postfreeze_qris_asset_cloned'; end if;

  if not coalesce((public.master_prototype_runtime_context(null,v_origin,'public')->>'ok')::boolean,false)
     or (public.master_prototype_runtime_context(null,v_origin,'public')->>'tenant_id')::uuid<>v_clone_id
  then raise exception 'postfreeze_clone_origin_resolution_failed'; end if;

  v_evidence:=jsonb_build_object(
    'ok',true,
    'contract','smart-order-b4-postfreeze-certification-v1',
    'prototype_key',v_proto.prototype_key,
    'release_tag',v_manifest.release_tag,
    'release_git_sha',v_manifest.release_git_sha,
    'migration_head',v_manifest.migration_head,
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
  if v_residue<>0 then raise exception 'postfreeze_clone_cleanup_residue'; end if;

  insert into private.master_clone_rehearsal_evidence(
    id,prototype_id,prototype_key,template_snapshot_sha256,
    source_git_sha,source_migration_head,clone_contract,
    clone_tenant_id,clone_origin,passed,residue_zero,
    evidence,evidence_sha256,checked_at
  ) values(
    v_evidence_id,v_proto.id,v_proto.prototype_key,v_snap.snapshot_sha256,
    v_manifest.release_git_sha,v_manifest.migration_head,
    'smart-order-b4-postfreeze-certification-v1',
    v_clone_id,v_origin,true,true,
    v_evidence||jsonb_build_object('cleanup_residue',0),
    v_evidence_sha,now()
  );

  return jsonb_build_object(
    'ok',true,
    'contract','smart-order-b4-postfreeze-certification-v1',
    'release_tag',v_manifest.release_tag,
    'release_git_sha',v_manifest.release_git_sha,
    'migration_head',v_manifest.migration_head,
    'evidence_id',v_evidence_id,
    'evidence_sha256',v_evidence_sha,
    'clone_tenant_id',v_clone_id,
    'clone_origin',v_origin,
    'cleanup_residue',0,
    'master_status','active'
  );
end
$;
revoke all on function private.run_postfreeze_clone_rehearsal_v1()
from public,anon,authenticated;
grant execute on function private.run_postfreeze_clone_rehearsal_v1()
to service_role;

create or replace function private.master_freeze_status_v1()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  p private.platform_prototypes%rowtype;
  m private.master_freeze_manifests%rowtype;
  v_active_prototypes integer;
  v_active_templates integer;
  v_old_deprecated boolean;
  v_snapshot_frozen boolean;
  v_evidence_ok boolean;
  v_postfreeze_clone_ok boolean;
  v_guards integer;
  v_engineering jsonb;
  v_preflight jsonb;
  v_runtime jsonb;
  v_ok boolean;
begin
  select * into p from private.platform_prototypes
  where prototype_key='smart-order-sdb-platform-v1'
  limit 1;

  select * into m from private.master_freeze_manifests
  where prototype_key='smart-order-sdb-platform-v1'
  order by promoted_at desc limit 1;

  select count(*) into v_active_prototypes
  from private.platform_prototypes
  where organization_id=p.organization_id and status='active';

  select count(*) into v_active_templates
  from private.platform_clone_templates
  where organization_id=p.organization_id and status='active';

  select exists(
    select 1 from private.platform_prototypes
    where prototype_key='rohmat-master-prototype-v1' and status='deprecated'
  ) into v_old_deprecated;

  select exists(
    select 1 from private.master_template_snapshots
    where prototype_key=p.prototype_key and frozen
  ) into v_snapshot_frozen;

  select exists(
    select 1 from private.master_clone_rehearsal_evidence e
    where e.id=m.clone_evidence_id and e.passed and e.residue_zero
      and e.evidence_sha256=m.clone_evidence_sha256
  ) into v_evidence_ok;

  select exists(
    select 1
    from private.master_clone_rehearsal_evidence e
    where e.prototype_id=p.id
      and e.prototype_key=p.prototype_key
      and e.template_snapshot_sha256=m.template_snapshot_sha256
      and e.clone_contract='smart-order-b4-postfreeze-certification-v1'
      and e.source_git_sha=m.release_git_sha
      and e.source_migration_head=m.migration_head
      and e.passed
      and e.residue_zero
      and e.checked_at>=m.promoted_at
  ) into v_postfreeze_clone_ok;

  select count(*) into v_guards
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal
    and n.nspname='private'
    and t.tgname in (
      'trg_master_template_snapshot_immutable_b4',
      'trg_master_clone_rehearsal_evidence_immutable_b4',
      'trg_master_freeze_manifest_immutable_b4',
      'trg_smart_order_master_prototype_immutable_b4',
      'trg_smart_order_master_clone_template_immutable_b4'
    );

  v_engineering:=private.release_engineering_status();
  v_preflight:=private.release_preflight_status();
  v_runtime:=public.master_runtime_security_health_v1(p.reference_tenant_id);

  v_ok:=
    p.id is not null
    and p.status='active'
    and p.release_tag=m.release_tag
    and p.metadata->>'freeze_state'='master_frozen'
    and coalesce((p.metadata->>'immutable')::boolean,false)
    and m.id is not null
    and m.release_git_sha ~ '^[0-9a-f]{40}$'
    and m.manifest_sha256 ~ '^[0-9a-f]{64}$'
    and v_active_prototypes=1
    and v_active_templates=1
    and v_old_deprecated
    and v_snapshot_frozen
    and v_evidence_ok
    and v_postfreeze_clone_ok
    and v_guards=5
    and coalesce((v_engineering->>'ok')::boolean,false)
    and coalesce((v_runtime->>'ok')::boolean,false);

  return jsonb_build_object(
    'ok',v_ok,
    'contract','smart-order-master-freeze-v1',
    'prototype_key',p.prototype_key,
    'status',p.status,
    'release_tag',p.release_tag,
    'release_git_sha',m.release_git_sha,
    'freeze_manifest_id',m.id,
    'freeze_manifest_sha256',m.manifest_sha256,
    'active_prototypes',v_active_prototypes,
    'active_clone_templates',v_active_templates,
    'old_master_deprecated',v_old_deprecated,
    'snapshot_frozen',v_snapshot_frozen,
    'clone_evidence_ok',v_evidence_ok,
    'postfreeze_clone_ok',v_postfreeze_clone_ok,
    'immutable_guards',v_guards,
    'release_engineering',v_engineering,
    'runtime_security',v_runtime,
    'live_preflight_ok',coalesce((v_preflight->>'ok')::boolean,false)
  );
end
$$;
revoke all on function private.master_freeze_status_v1()
from public,anon,authenticated;
grant execute on function private.master_freeze_status_v1() to service_role;

-- Promotion-foundation baseline. Candidate is still draft until the one-shot finalizer is called.
update private.release_policy
set source_control_mode='git_b4_promotion_foundation',
    ci_status='github_actions_b4_promotion_foundation_candidate',
    notes=coalesce(notes,'') || E'\n2026-09-27 B4.3 foundation: immutable guards + one-shot promotion finalizer installed; candidate still draft until release tag is externally verified.',
    updated_at=now()
where id=1;

insert into private.release_baseline(
  id,release_label,migration_head,schema_fingerprint,cron_fingerprint,
  manifest_fingerprint,captured_at,notes
)
values(
  1,'b4-promotion-foundation-20260927','20260927174000',
  private.release_schema_fingerprint(),private.release_cron_fingerprint(),
  private.release_manifest_fingerprint(),now(),
  'B4.3 promotion foundation. No promotion occurs until finalize_master_promotion_v1 is called.'
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
