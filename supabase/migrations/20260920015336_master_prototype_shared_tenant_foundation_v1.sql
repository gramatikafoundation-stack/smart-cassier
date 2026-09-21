-- ROHMAT MASTER PROTOTIPE v1
-- Phase 1: additive shared-tenant foundation. No existing production route is switched here.
-- Rohmat stays operational as the reference tenant while tenant ownership metadata is introduced.

do $$
declare c record;
begin
  select conname, pg_get_constraintdef(oid) as def
    into c
  from pg_constraint
  where conrelid='private.platform_tenants'::regclass
    and contype='c'
    and pg_get_constraintdef(oid) ilike '%isolation_mode%';
  if c.conname is not null then
    execute format('alter table private.platform_tenants drop constraint %I',c.conname);
  end if;
end $$;

alter table private.platform_tenants
  add column if not exists source_prototype_key text;

alter table private.platform_tenants
  add constraint platform_tenants_isolation_mode_chk
  check (isolation_mode in ('project_per_tenant','shared_project','shared_database_rls'));

create table if not exists private.platform_prototypes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references private.platform_organizations(id) on delete restrict,
  prototype_key text not null,
  name text not null,
  reference_tenant_id uuid not null references private.platform_tenants(id) on delete restrict,
  status text not null default 'active' check (status in ('draft','active','deprecated')),
  github_repo text not null,
  github_branch text not null,
  release_tag text,
  supabase_project_ref text not null,
  tenancy_mode text not null default 'shared_database_rls'
    check (tenancy_mode='shared_database_rls'),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, prototype_key)
);

alter table private.platform_prototypes enable row level security;
revoke all on private.platform_prototypes from anon, authenticated;
drop policy if exists platform_prototypes_service_role_all on private.platform_prototypes;
create policy platform_prototypes_service_role_all
  on private.platform_prototypes for all to service_role
  using (true) with check (true);

drop trigger if exists trg_platform_prototypes_updated_at on private.platform_prototypes;
create trigger trg_platform_prototypes_updated_at
before update on private.platform_prototypes
for each row execute function public.set_updated_at();

update private.platform_organizations
set slug='smart-digital-for-business',
    name='SMART DIGITAL FOR BUSINESS',
    metadata=(metadata - 'architecture' - 'target_provider_name')
      || jsonb_build_object(
        'architecture','shared_database_multi_tenant',
        'platform_name','SMART DIGITAL FOR BUSINESS',
        'reference_tenant','rohmat-nasi-uduk'
      ),
    updated_at=now()
where slug='smart-digital-indonesia';

update private.platform_tenants t
set isolation_mode='shared_database_rls',
    source_prototype_key='rohmat-master-prototype-v1',
    source_template_key=null,
    metadata=t.metadata || jsonb_build_object(
      'role','reference_tenant',
      'production',true,
      'prototype_version','1.0.0'
    ),
    updated_at=now()
from private.platform_organizations o
where t.organization_id=o.id
  and o.slug='smart-digital-for-business'
  and t.slug='rohmat-nasi-uduk';

insert into private.platform_prototypes(
  organization_id,prototype_key,name,reference_tenant_id,status,
  github_repo,github_branch,supabase_project_ref,tenancy_mode,metadata
)
select o.id,'rohmat-master-prototype-v1','Rohmat Master Prototipe',t.id,'active',
       'gramatikafoundation-stack/Rohmat-Master',
       'release/master-clone-v1-freeze-20260919',
       'yybhpmjuywjxqurrrrxl','shared_database_rls',
       jsonb_build_object(
         'apps',jsonb_build_array('public','admin','kds'),
         'source_of_truth','github',
         'operational_source_of_truth','supabase',
         'tenant_provisioning','logical_tenant_no_source_clone',
         'final_tag','rohmat-master-prototype-v1.0.0'
       )
from private.platform_organizations o
join private.platform_tenants t on t.organization_id=o.id
where o.slug='smart-digital-for-business' and t.slug='rohmat-nasi-uduk'
on conflict (organization_id,prototype_key) do update
set name=excluded.name,
    reference_tenant_id=excluded.reference_tenant_id,
    status='active',
    github_repo=excluded.github_repo,
    github_branch=excluded.github_branch,
    supabase_project_ref=excluded.supabase_project_ref,
    tenancy_mode='shared_database_rls',
    metadata=private.platform_prototypes.metadata || excluded.metadata,
    updated_at=now();

update private.platform_clone_templates ct
set status='deprecated',
    metadata=ct.metadata || jsonb_build_object(
      'superseded_by','rohmat-master-prototype-v1',
      'superseded_reason','shared database logical tenancy replaces project-per-tenant clone model'
    ),
    updated_at=now()
from private.platform_organizations o
where ct.organization_id=o.id
  and o.slug='smart-digital-for-business'
  and ct.template_key='rohmat-master-v1';

create or replace function private.reference_tenant_id()
returns uuid
language sql
stable
security definer
set search_path=private,public
as $$
  select id
  from private.platform_tenants
  where slug='rohmat-nasi-uduk'
    and status='active'
  order by created_at
  limit 1
$$;
revoke all on function private.reference_tenant_id() from public, anon, authenticated;
grant execute on function private.reference_tenant_id() to service_role;

create table if not exists private.tenant_runtime_config (
  tenant_id uuid primary key references private.platform_tenants(id) on delete cascade,
  business_name text not null,
  merchant_name text not null,
  locale text not null default 'id-ID',
  currency text not null default 'IDR',
  timezone text not null default 'Asia/Jakarta',
  public_origin text not null,
  admin_origin text not null,
  kds_origin text not null,
  qris_asset text,
  storage_static_bucket text,
  storage_payment_bucket text,
  settings jsonb not null default '{}'::jsonb,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(public_origin),
  unique(admin_origin),
  unique(kds_origin)
);
alter table private.tenant_runtime_config enable row level security;
revoke all on private.tenant_runtime_config from anon, authenticated;
drop policy if exists tenant_runtime_config_service_role_all on private.tenant_runtime_config;
create policy tenant_runtime_config_service_role_all on private.tenant_runtime_config
for all to service_role using(true) with check(true);
drop trigger if exists trg_tenant_runtime_config_updated_at on private.tenant_runtime_config;
create trigger trg_tenant_runtime_config_updated_at
before update on private.tenant_runtime_config
for each row execute function public.set_updated_at();

create table if not exists private.tenant_memberships (
  tenant_id uuid not null references private.platform_tenants(id) on delete cascade,
  email text not null,
  role text not null check(role in ('superadmin','admin')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(tenant_id,email)
);
alter table private.tenant_memberships enable row level security;
revoke all on private.tenant_memberships from anon, authenticated;
drop policy if exists tenant_memberships_service_role_all on private.tenant_memberships;
create policy tenant_memberships_service_role_all on private.tenant_memberships
for all to service_role using(true) with check(true);
drop trigger if exists trg_tenant_memberships_updated_at on private.tenant_memberships;
create trigger trg_tenant_memberships_updated_at
before update on private.tenant_memberships
for each row execute function public.set_updated_at();

create table if not exists private.tenant_sheet_targets (
  tenant_id uuid not null references private.platform_tenants(id) on delete cascade,
  year integer not null,
  spreadsheet_id text not null,
  label text not null,
  enabled boolean not null default true,
  expected_tabs jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(tenant_id,year)
);
alter table private.tenant_sheet_targets enable row level security;
revoke all on private.tenant_sheet_targets from anon, authenticated;
drop policy if exists tenant_sheet_targets_service_role_all on private.tenant_sheet_targets;
create policy tenant_sheet_targets_service_role_all on private.tenant_sheet_targets
for all to service_role using(true) with check(true);
drop trigger if exists trg_tenant_sheet_targets_updated_at on private.tenant_sheet_targets;
create trigger trg_tenant_sheet_targets_updated_at
before update on private.tenant_sheet_targets
for each row execute function public.set_updated_at();

create table if not exists private.tenant_table_qr_signatures (
  tenant_id uuid not null references private.platform_tenants(id) on delete cascade,
  table_number integer not null,
  signature_hash text not null,
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key(tenant_id,table_number)
);
alter table private.tenant_table_qr_signatures enable row level security;
revoke all on private.tenant_table_qr_signatures from anon, authenticated;
drop policy if exists tenant_table_qr_signatures_service_role_all on private.tenant_table_qr_signatures;
create policy tenant_table_qr_signatures_service_role_all on private.tenant_table_qr_signatures
for all to service_role using(true) with check(true);

insert into private.tenant_runtime_config(
  tenant_id,business_name,merchant_name,locale,currency,timezone,
  public_origin,admin_origin,kds_origin,qris_asset,
  storage_static_bucket,storage_payment_bucket,settings
)
select private.reference_tenant_id(),
       s.business_name,
       coalesce(nullif(s.merchant_name,''),s.business_name),
       'id-ID','IDR','Asia/Jakarta',
       s.public_url,s.admin_url,s.kds_url,s.qris_image_url,
       'merchant-static','payment-proofs',
       to_jsonb(s)-'id'
from public.site_settings s
where s.id=1
on conflict(tenant_id) do update
set business_name=excluded.business_name,
    merchant_name=excluded.merchant_name,
    public_origin=excluded.public_origin,
    admin_origin=excluded.admin_origin,
    kds_origin=excluded.kds_origin,
    qris_asset=excluded.qris_asset,
    settings=excluded.settings,
    updated_at=now();

insert into private.tenant_memberships(tenant_id,email,role,is_active)
select private.reference_tenant_id(),lower(email),role,is_active
from public.admin_users
on conflict(tenant_id,email) do update
set role=excluded.role,is_active=excluded.is_active,updated_at=now();

insert into private.tenant_sheet_targets(
  tenant_id,year,spreadsheet_id,label,enabled,expected_tabs,created_at,updated_at
)
select private.reference_tenant_id(),year,spreadsheet_id,label,enabled,expected_tabs,created_at,updated_at
from public.sheet_sync_targets
on conflict(tenant_id,year) do update
set spreadsheet_id=excluded.spreadsheet_id,
    label=excluded.label,
    enabled=excluded.enabled,
    expected_tabs=excluded.expected_tabs,
    updated_at=now();

insert into private.tenant_table_qr_signatures(
  tenant_id,table_number,signature_hash,is_active,updated_at
)
select private.reference_tenant_id(),table_number,signature_hash,is_active,updated_at
from private.table_qr_signatures
on conflict(tenant_id,table_number) do update
set signature_hash=excluded.signature_hash,
    is_active=excluded.is_active,
    updated_at=excluded.updated_at;

do $$
declare tbl text;
begin
  foreach tbl in array array[
    'public.menu_items',
    'public.orders',
    'public.order_events',
    'public.order_history_archive',
    'public.sheet_sync_outbox',
    'public.public_rum_samples',
    'private.order_identity_registry',
    'private.order_rate_limits',
    'private.integration_events',
    'private.kds_observability_samples',
    'private.frontend_performance_samples'
  ]
  loop
    execute format('alter table %s add column if not exists tenant_id uuid',tbl);
    execute format('update %s set tenant_id=private.reference_tenant_id() where tenant_id is null',tbl);
    execute format('alter table %s alter column tenant_id set default private.reference_tenant_id()',tbl);
    execute format('alter table %s alter column tenant_id set not null',tbl);
    begin
      execute format(
        'alter table %s add constraint %I foreign key(tenant_id) references private.platform_tenants(id) on delete restrict',
        tbl, replace(replace(tbl,'.','_'),'"','') || '_tenant_id_fkey'
      );
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

create index if not exists menu_items_tenant_idx on public.menu_items(tenant_id);
create index if not exists orders_tenant_created_idx on public.orders(tenant_id,created_at desc);
create index if not exists order_events_tenant_order_idx on public.order_events(tenant_id,order_id,created_at);
create index if not exists order_history_tenant_created_idx on public.order_history_archive(tenant_id,created_at desc);
create index if not exists sheet_sync_outbox_tenant_status_idx on public.sheet_sync_outbox(tenant_id,status,next_attempt_at);
create index if not exists public_rum_tenant_measured_idx on public.public_rum_samples(tenant_id,measured_at desc);
create index if not exists order_identity_registry_tenant_idx on private.order_identity_registry(tenant_id);
create index if not exists order_rate_limits_tenant_idx on private.order_rate_limits(tenant_id,attempted_at desc);
create index if not exists integration_events_tenant_created_idx on private.integration_events(tenant_id,created_at desc);
create index if not exists kds_observability_tenant_measured_idx on private.kds_observability_samples(tenant_id,measured_at desc);
create index if not exists frontend_performance_tenant_measured_idx on private.frontend_performance_samples(tenant_id,measured_at desc);

create or replace function private.resolve_platform_tenant(
  p_tenant_id uuid default null,
  p_origin text default null,
  p_slug text default null
)
returns uuid
language plpgsql
stable
security definer
set search_path=private,public
as $$
declare v_id uuid;
begin
  if p_tenant_id is not null then
    select t.id into v_id
    from private.platform_tenants t
    join private.tenant_runtime_config c on c.tenant_id=t.id
    where t.id=p_tenant_id and t.status='active' and c.enabled;
  elsif nullif(trim(coalesce(p_slug,'')),'') is not null then
    select t.id into v_id
    from private.platform_tenants t
    join private.tenant_runtime_config c on c.tenant_id=t.id
    where t.slug=p_slug and t.status='active' and c.enabled;
  elsif nullif(trim(coalesce(p_origin,'')),'') is not null then
    select c.tenant_id into v_id
    from private.tenant_runtime_config c
    join private.platform_tenants t on t.id=c.tenant_id
    where t.status='active' and c.enabled
      and p_origin in (c.public_origin,c.admin_origin,c.kds_origin);
  end if;
  if v_id is null then
    raise exception 'tenant_not_resolved' using errcode='22023';
  end if;
  return v_id;
end
$$;
revoke all on function private.resolve_platform_tenant(uuid,text,text) from public,anon,authenticated;
grant execute on function private.resolve_platform_tenant(uuid,text,text) to service_role;

create or replace function private.master_prototype_tenant_audit()
returns jsonb
language sql
stable
security definer
set search_path=private,public
as $$
  with ref as (select private.reference_tenant_id() id),
  checks as (
    select 'menu_items' k,count(*) filter(where tenant_id is null) n from public.menu_items
    union all select 'orders',count(*) filter(where tenant_id is null) from public.orders
    union all select 'order_events',count(*) filter(where tenant_id is null) from public.order_events
    union all select 'order_history_archive',count(*) filter(where tenant_id is null) from public.order_history_archive
    union all select 'sheet_sync_outbox',count(*) filter(where tenant_id is null) from public.sheet_sync_outbox
  )
  select jsonb_build_object(
    'ok', not exists(select 1 from checks where n<>0)
      and exists(select 1 from private.platform_prototypes p where p.prototype_key='rohmat-master-prototype-v1' and p.status='active')
      and exists(select 1 from private.tenant_runtime_config c where c.tenant_id=(select id from ref) and c.enabled),
    'reference_tenant_id',(select id from ref),
    'null_tenant_counts',(select jsonb_object_agg(k,n) from checks),
    'prototype_active',exists(select 1 from private.platform_prototypes p where p.prototype_key='rohmat-master-prototype-v1' and p.status='active'),
    'reference_runtime_config',exists(select 1 from private.tenant_runtime_config c where c.tenant_id=(select id from ref) and c.enabled),
    'phase','ownership_metadata_ready_rls_not_yet_enforced'
  )
$$;
revoke all on function private.master_prototype_tenant_audit() from public,anon,authenticated;
grant execute on function private.master_prototype_tenant_audit() to service_role;

comment on table private.platform_prototypes is
  'Canonical MASTER PROTOTIPE definitions. Rohmat is the reference tenant; tenant onboarding does not clone source or Supabase projects.';
comment on table private.tenant_runtime_config is
  'Tenant-specific runtime identity/configuration for the shared SMART DIGITAL FOR BUSINESS platform.';
comment on function private.master_prototype_tenant_audit() is
  'Phase-1 shared-tenant audit. PASS here means tenant ownership metadata is complete; RLS enforcement is a separate later gate.';
