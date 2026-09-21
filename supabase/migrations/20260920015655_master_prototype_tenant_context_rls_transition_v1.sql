-- ROHMAT MASTER PROTOTIPE v1
-- Phase 2: tenant context + transitional RLS. Hard enforcement remains OFF until candidate runtime is verified.

create table if not exists private.platform_tenancy_state (
  id smallint primary key default 1 check(id=1),
  enforce_client_rls boolean not null default false,
  active_contract text not null default 'master-prototype-tenant-v1',
  updated_at timestamptz not null default now()
);
alter table private.platform_tenancy_state enable row level security;
revoke all on private.platform_tenancy_state from anon,authenticated;
drop policy if exists platform_tenancy_state_service_role_all on private.platform_tenancy_state;
create policy platform_tenancy_state_service_role_all on private.platform_tenancy_state
for all to service_role using(true) with check(true);
insert into private.platform_tenancy_state(id,enforce_client_rls,active_contract)
values(1,false,'master-prototype-tenant-v1')
on conflict(id) do update
set active_contract=excluded.active_contract,updated_at=now();

create or replace function private.request_tenant_id()
returns uuid
language plpgsql
stable
security definer
set search_path=private,public
as $$
declare raw text; v uuid;
begin
  begin
    raw := nullif(trim(coalesce((current_setting('request.headers',true)::jsonb->>'x-sdb-tenant-id'),'')),'');
  exception when others then
    raw := null;
  end;
  if raw is null then return null; end if;
  begin v := raw::uuid; exception when invalid_text_representation then return null; end;
  if exists(
    select 1 from private.platform_tenants t
    join private.tenant_runtime_config c on c.tenant_id=t.id
    where t.id=v and t.status='active' and c.enabled
  ) then return v; end if;
  return null;
end
$$;
revoke all on function private.request_tenant_id() from public;
grant execute on function private.request_tenant_id() to anon,authenticated,service_role;

create or replace function private.client_tenant_id()
returns uuid
language plpgsql
stable
security definer
set search_path=private,public
as $$
declare v uuid; enforce boolean;
begin
  v := private.request_tenant_id();
  if v is not null then return v; end if;
  select enforce_client_rls into enforce from private.platform_tenancy_state where id=1;
  if coalesce(enforce,false)=false then return private.reference_tenant_id(); end if;
  return null;
end
$$;
revoke all on function private.client_tenant_id() from public;
grant execute on function private.client_tenant_id() to anon,authenticated,service_role;

create table if not exists public.tenant_site_settings_public_v1 (
  tenant_id uuid primary key references private.platform_tenants(id) on delete cascade,
  business_name text not null,
  welcome_text text,
  motto text,
  hero_image_url text,
  public_url text not null,
  merchant_name text not null,
  payment_instructions text,
  qris_image_url text,
  qris_enabled boolean not null default false,
  require_table_qr_signature boolean not null default true,
  typography jsonb not null default '{}'::jsonb,
  design_system jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.tenant_site_settings_public_v1 enable row level security;
revoke all on public.tenant_site_settings_public_v1 from anon,authenticated;
grant select on public.tenant_site_settings_public_v1 to anon,authenticated;
drop policy if exists tenant_site_settings_public_select on public.tenant_site_settings_public_v1;
create policy tenant_site_settings_public_select
on public.tenant_site_settings_public_v1
for select to anon,authenticated
using(tenant_id=private.client_tenant_id());

insert into public.tenant_site_settings_public_v1(
  tenant_id,business_name,welcome_text,motto,hero_image_url,public_url,
  merchant_name,payment_instructions,qris_image_url,qris_enabled,
  require_table_qr_signature,typography,design_system,updated_at
)
select private.reference_tenant_id(),business_name,welcome_text,motto,hero_image_url,public_url,
       merchant_name,payment_instructions,qris_image_url,qris_enabled,
       require_table_qr_signature,typography,design_system,updated_at
from public.site_settings_public_v2
where id=1
on conflict(tenant_id) do update
set business_name=excluded.business_name,
    welcome_text=excluded.welcome_text,
    motto=excluded.motto,
    hero_image_url=excluded.hero_image_url,
    public_url=excluded.public_url,
    merchant_name=excluded.merchant_name,
    payment_instructions=excluded.payment_instructions,
    qris_image_url=excluded.qris_image_url,
    qris_enabled=excluded.qris_enabled,
    require_table_qr_signature=excluded.require_table_qr_signature,
    typography=excluded.typography,
    design_system=excluded.design_system,
    updated_at=excluded.updated_at;

create or replace function private.sync_reference_public_settings_cache()
returns trigger
language plpgsql
security definer
set search_path=private,public
as $$
begin
  if new.id<>1 then return new; end if;
  insert into public.tenant_site_settings_public_v1(
    tenant_id,business_name,welcome_text,motto,hero_image_url,public_url,
    merchant_name,payment_instructions,qris_image_url,qris_enabled,
    require_table_qr_signature,typography,design_system,updated_at
  )
  values(
    private.reference_tenant_id(),new.business_name,new.welcome_text,new.motto,new.hero_image_url,new.public_url,
    coalesce(nullif(new.merchant_name,''),new.business_name),new.payment_instructions,new.qris_image_url,new.qris_enabled,
    new.require_table_qr_signature,new.typography,new.design_system,new.updated_at
  )
  on conflict(tenant_id) do update
  set business_name=excluded.business_name,welcome_text=excluded.welcome_text,motto=excluded.motto,
      hero_image_url=excluded.hero_image_url,public_url=excluded.public_url,merchant_name=excluded.merchant_name,
      payment_instructions=excluded.payment_instructions,qris_image_url=excluded.qris_image_url,
      qris_enabled=excluded.qris_enabled,require_table_qr_signature=excluded.require_table_qr_signature,
      typography=excluded.typography,design_system=excluded.design_system,updated_at=excluded.updated_at;
  return new;
end
$$;
revoke all on function private.sync_reference_public_settings_cache() from public,anon,authenticated;

drop trigger if exists trg_sync_reference_public_settings_cache on public.site_settings;
create trigger trg_sync_reference_public_settings_cache
after insert or update on public.site_settings
for each row execute function private.sync_reference_public_settings_cache();

drop policy if exists "Public reads visible menu" on public.menu_items;
create policy "Public reads visible menu"
on public.menu_items
for select to anon
using(is_visible and tenant_id=private.client_tenant_id());

drop policy if exists "Authenticated reads visible menu tenant scoped" on public.menu_items;
create policy "Authenticated reads visible menu tenant scoped"
on public.menu_items
for select to authenticated
using(
  tenant_id=private.client_tenant_id()
  and ((select private.is_admin()) or is_visible)
);

create or replace function private.master_prototype_rls_status()
returns jsonb
language sql
stable
security definer
set search_path=private,public
as $$
select jsonb_build_object(
  'enforce_client_rls',(select enforce_client_rls from private.platform_tenancy_state where id=1),
  'request_tenant_id',private.request_tenant_id(),
  'effective_tenant_id',private.client_tenant_id(),
  'reference_tenant_id',private.reference_tenant_id(),
  'public_settings_rows',(select count(*) from public.tenant_site_settings_public_v1),
  'menu_null_tenant_rows',(select count(*) from public.menu_items where tenant_id is null),
  'phase','transitional_rls_candidate_runtime_must_be_verified_before_enforcement'
)
$$;
revoke all on function private.master_prototype_rls_status() from public,anon,authenticated;
grant execute on function private.master_prototype_rls_status() to service_role;

comment on table private.platform_tenancy_state is
  'Fail-closed cutover switch. Keep enforce_client_rls=false until all current runtimes send explicit tenant context and regression passes.';
comment on function private.client_tenant_id() is
  'Transitional tenant resolver. Reference fallback exists only while enforce_client_rls=false; final freeze requires true.';
