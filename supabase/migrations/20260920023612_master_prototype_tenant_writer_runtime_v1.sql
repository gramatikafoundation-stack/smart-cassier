-- ROHMAT MASTER PROTOTIPE v1
-- Phase 9: tenant-scoped Writer credential, lease and data-access contract.
-- Legacy writer tables/functions remain for the reference tenant until final cutover.

alter table private.tenant_writer_config
  add column if not exists writer_secret_id uuid;

update private.tenant_writer_config tw
set writer_secret_id=c.writer_secret_id,
    updated_at=now()
from public.sheet_sync_config c
where tw.tenant_id=private.reference_tenant_id()
  and c.id=1
  and tw.writer_secret_id is null;

create table if not exists private.tenant_sheet_writer_lease (
  tenant_id uuid primary key references private.platform_tenants(id) on delete cascade,
  locked_by uuid,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table private.tenant_sheet_writer_lease enable row level security;
revoke all on private.tenant_sheet_writer_lease from anon,authenticated;
drop policy if exists tenant_sheet_writer_lease_service_role_all on private.tenant_sheet_writer_lease;
create policy tenant_sheet_writer_lease_service_role_all
on private.tenant_sheet_writer_lease for all to service_role using(true) with check(true);

insert into private.tenant_sheet_writer_lease(tenant_id)
select id from private.platform_tenants
where status='active'
on conflict(tenant_id) do nothing;

create or replace function public.sheet_sync_writer_credential_tenant(p_tenant_id uuid)
returns text
language sql
stable
security definer
set search_path=''
as $$
  select v.decrypted_secret
  from private.tenant_writer_config c
  join vault.decrypted_secrets v on v.id=c.writer_secret_id
  where c.tenant_id=p_tenant_id
    and c.enabled
    and (auth.jwt()->>'role')='service_role'
  limit 1
$$;
revoke all on function public.sheet_sync_writer_credential_tenant(uuid) from public,anon,authenticated;
grant execute on function public.sheet_sync_writer_credential_tenant(uuid) to service_role;

create or replace function public.sheet_writer_try_acquire_lease_tenant(
  p_tenant_id uuid,p_run_id uuid,p_ttl_seconds integer default 115
)
returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare
  v_acquired boolean:=false;
  v_ttl integer:=greatest(30,least(coalesce(p_ttl_seconds,115),180));
begin
  if p_tenant_id is null or p_run_id is null then return false; end if;
  insert into private.tenant_sheet_writer_lease(tenant_id)
  values(p_tenant_id)
  on conflict(tenant_id) do nothing;

  update private.tenant_sheet_writer_lease
     set locked_by=p_run_id,
         locked_until=now()+pg_catalog.make_interval(secs=>v_ttl),
         updated_at=now()
   where tenant_id=p_tenant_id
     and (locked_until is null or locked_until<=now() or locked_by=p_run_id);
  v_acquired:=found;
  return v_acquired;
end
$$;
revoke all on function public.sheet_writer_try_acquire_lease_tenant(uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.sheet_writer_try_acquire_lease_tenant(uuid,uuid,integer) to service_role;

create or replace function public.sheet_writer_release_lease_tenant(
  p_tenant_id uuid,p_run_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare v_released boolean:=false;
begin
  if p_tenant_id is null or p_run_id is null then return false; end if;
  update private.tenant_sheet_writer_lease
     set locked_by=null,locked_until=null,updated_at=now()
   where tenant_id=p_tenant_id and locked_by=p_run_id;
  v_released:=found;
  return v_released;
end
$$;
revoke all on function public.sheet_writer_release_lease_tenant(uuid,uuid) from public,anon,authenticated;
grant execute on function public.sheet_writer_release_lease_tenant(uuid,uuid) to service_role;

create or replace function public.sheet_writer_due_tenants(p_limit integer default 25)
returns table(tenant_id uuid,oldest_due timestamptz,due_count bigint)
language sql
stable
security definer
set search_path=''
as $$
select o.tenant_id,min(o.next_attempt_at),count(*)
from public.sheet_sync_outbox o
join private.tenant_writer_config c on c.tenant_id=o.tenant_id and c.enabled
where o.status in ('pending','failed')
  and o.next_attempt_at<=now()
group by o.tenant_id
order by min(o.next_attempt_at)
limit greatest(1,least(coalesce(p_limit,25),100))
$$;
revoke all on function public.sheet_writer_due_tenants(integer) from public,anon,authenticated;
grant execute on function public.sheet_writer_due_tenants(integer) to service_role;

create or replace function public.sheet_writer_claim_tenant_events(
  p_tenant_id uuid,p_run_id uuid,p_limit integer default 100,p_lease_seconds integer default 120
)
returns setof public.sheet_sync_outbox
language plpgsql
security definer
set search_path=''
as $$
declare
  v_now timestamptz:=now();
  v_until timestamptz:=now()+pg_catalog.make_interval(secs=>greatest(30,least(coalesce(p_lease_seconds,120),180)));
begin
  update public.sheet_sync_outbox
     set status='failed',
         next_attempt_at=v_now,
         locked_until=null,
         locked_by=null,
         last_error='Previous tenant event-processing lease expired; retrying authoritative refresh.'
   where tenant_id=p_tenant_id
     and status='processing'
     and locked_until<v_now;

  return query
  with candidates as (
    select event_id
    from public.sheet_sync_outbox
    where tenant_id=p_tenant_id
      and status in ('pending','failed')
      and next_attempt_at<=v_now
    order by created_at
    for update skip locked
    limit greatest(1,least(coalesce(p_limit,100),500))
  )
  update public.sheet_sync_outbox o
     set status='processing',
         locked_until=v_until,
         locked_by=p_run_id::text,
         last_attempt_at=v_now
  from candidates c
  where o.event_id=c.event_id
  returning o.*;
end
$$;
revoke all on function public.sheet_writer_claim_tenant_events(uuid,uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.sheet_writer_claim_tenant_events(uuid,uuid,integer,integer) to service_role;

create or replace function private.master_prototype_writer_audit()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
with tenants as (
  select t.id,t.slug,
         coalesce(w.enabled,false) writer_enabled,
         (w.writer_url is not null and w.writer_url<>'') writer_url_configured,
         (w.writer_secret_id is not null) writer_secret_configured,
         (select count(*) from private.tenant_sheet_targets st where st.tenant_id=t.id and st.enabled) target_count
  from private.platform_tenants t
  join private.tenant_runtime_config r on r.tenant_id=t.id and r.enabled
  left join private.tenant_writer_config w on w.tenant_id=t.id
  where t.status='active'
)
select jsonb_build_object(
  'ok',not exists(
    select 1 from tenants
    where writer_enabled and (not writer_url_configured or not writer_secret_configured or target_count=0)
  ),
  'tenants',coalesce(jsonb_agg(jsonb_build_object(
    'tenant_id',id,'slug',slug,'writer_enabled',writer_enabled,
    'writer_url_configured',writer_url_configured,
    'writer_secret_configured',writer_secret_configured,
    'target_count',target_count
  ) order by slug),'[]'::jsonb)
)
from tenants
$$;
revoke all on function private.master_prototype_writer_audit() from public,anon,authenticated;
grant execute on function private.master_prototype_writer_audit() to service_role;
