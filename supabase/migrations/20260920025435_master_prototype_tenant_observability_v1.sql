-- ROHMAT MASTER PROTOTIPE v1
-- Phase 11: tenant-scoped reliability/performance observability.

create table if not exists private.tenant_reliability_probe_state (
  tenant_id uuid not null references private.platform_tenants(id) on delete cascade,
  service_key text not null,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  last_checked_at timestamptz not null default now(),
  last_http_status integer,
  last_latency_ms integer,
  consecutive_failures integer not null default 0,
  last_error text,
  updated_at timestamptz not null default now(),
  primary key(tenant_id,service_key)
);
alter table private.tenant_reliability_probe_state enable row level security;
revoke all on private.tenant_reliability_probe_state from anon,authenticated;
drop policy if exists tenant_reliability_probe_state_service_role_all on private.tenant_reliability_probe_state;
create policy tenant_reliability_probe_state_service_role_all
on private.tenant_reliability_probe_state for all to service_role using(true) with check(true);

insert into private.tenant_reliability_probe_state(
  tenant_id,service_key,last_success_at,last_failure_at,last_checked_at,last_http_status,
  last_latency_ms,consecutive_failures,last_error,updated_at
)
select private.reference_tenant_id(),service_key,last_success_at,last_failure_at,last_checked_at,last_http_status,
       last_latency_ms,consecutive_failures,last_error,updated_at
from private.reliability_probe_state
on conflict(tenant_id,service_key) do nothing;

alter table private.reliability_probe_events add column if not exists tenant_id uuid;
update private.reliability_probe_events set tenant_id=private.reference_tenant_id() where tenant_id is null;
alter table private.reliability_probe_events alter column tenant_id set default private.reference_tenant_id();
alter table private.reliability_probe_events alter column tenant_id set not null;
do $$ begin
  begin alter table private.reliability_probe_events
    add constraint reliability_probe_events_tenant_id_fkey foreign key(tenant_id)
    references private.platform_tenants(id) on delete cascade;
  exception when duplicate_object then null; end;
end $$;
create index if not exists reliability_probe_events_tenant_checked_idx
  on private.reliability_probe_events(tenant_id,service_key,checked_at desc);

create or replace function public.reliability_record_probe_tenant(
  p_tenant_id uuid,p_service_key text,p_ok boolean,p_http_status integer,p_latency_ms integer,p_error text default null
)
returns void language plpgsql security definer set search_path='' as $$
begin
  if coalesce(p_service_key,'') not in ('public_web','admin_web','kds_web','order_gateway')
    then raise exception 'invalid_service_key'; end if;
  if not exists(select 1 from private.platform_tenants where id=p_tenant_id and status='active')
    then raise exception 'tenant_unavailable'; end if;

  insert into private.tenant_reliability_probe_state(
    tenant_id,service_key,last_success_at,last_failure_at,last_checked_at,last_http_status,
    last_latency_ms,consecutive_failures,last_error,updated_at
  ) values(
    p_tenant_id,p_service_key,case when p_ok then now() end,case when not p_ok then now() end,
    now(),p_http_status,p_latency_ms,case when p_ok then 0 else 1 end,
    case when p_ok then null else left(coalesce(p_error,'probe_failed'),500) end,now()
  )
  on conflict(tenant_id,service_key) do update set
    last_success_at=case when p_ok then now() else private.tenant_reliability_probe_state.last_success_at end,
    last_failure_at=case when not p_ok then now() else private.tenant_reliability_probe_state.last_failure_at end,
    last_checked_at=now(),last_http_status=p_http_status,last_latency_ms=p_latency_ms,
    consecutive_failures=case when p_ok then 0 else private.tenant_reliability_probe_state.consecutive_failures+1 end,
    last_error=case when p_ok then null else left(coalesce(p_error,'probe_failed'),500) end,updated_at=now();

  insert into private.reliability_probe_events(
    tenant_id,service_key,ok,http_status,latency_ms,error,checked_at
  ) values(
    p_tenant_id,p_service_key,p_ok,p_http_status,p_latency_ms,
    case when p_ok then null else left(coalesce(p_error,'probe_failed'),500) end,now()
  );
  delete from private.reliability_probe_events where checked_at<now()-interval '30 days';
end $$;
revoke all on function public.reliability_record_probe_tenant(uuid,text,boolean,integer,integer,text) from public,anon,authenticated;
grant execute on function public.reliability_record_probe_tenant(uuid,text,boolean,integer,integer,text) to service_role;

-- Legacy public.reliability_record_probe remains unchanged for the reference-tenant SLO pipeline.

create or replace function public.frontend_performance_record_tenant(
  p_tenant_id uuid,p_service_key text,p_status_code integer,p_latency_ms integer,
  p_payload_bytes integer,p_cache_control text default null
)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if current_user not in ('service_role','postgres') then raise exception 'forbidden'; end if;
  if not exists(select 1 from private.platform_tenants where id=p_tenant_id and status='active')
    then raise exception 'tenant_unavailable'; end if;
  insert into private.frontend_performance_samples(
    tenant_id,service_key,status_code,latency_ms,payload_bytes,cache_control
  ) values(
    p_tenant_id,p_service_key,p_status_code,greatest(0,p_latency_ms),greatest(0,p_payload_bytes),
    left(p_cache_control,300)
  );
  delete from private.frontend_performance_samples where measured_at<now()-interval '30 days';
  return true;
end $$;
revoke all on function public.frontend_performance_record_tenant(uuid,text,integer,integer,integer,text) from public,anon,authenticated;
grant execute on function public.frontend_performance_record_tenant(uuid,text,integer,integer,integer,text) to service_role;

create or replace function public.frontend_performance_record(
  p_service_key text,p_status_code integer,p_latency_ms integer,p_payload_bytes integer,p_cache_control text default null
)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  return public.frontend_performance_record_tenant(
    private.reference_tenant_id(),p_service_key,p_status_code,p_latency_ms,p_payload_bytes,p_cache_control
  );
end $$;

create or replace function private.reliability_summary_tenant(p_tenant_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
with s as (
 select service_key,last_success_at,last_failure_at,last_checked_at,last_http_status,last_latency_ms,
        consecutive_failures,last_error
 from private.tenant_reliability_probe_state
 where tenant_id=p_tenant_id
), agg as (
 select count(*) count_services,
        count(*) filter(where last_checked_at>now()-interval '15 minutes') fresh_services,
        count(*) filter(where consecutive_failures=0 and last_http_status between 200 and 399) healthy_services
 from s
)
select jsonb_build_object(
 'ok',count_services=4 and fresh_services=4 and healthy_services=4,
 'tenant_id',p_tenant_id,
 'expected_services',4,
 'service_count',count_services,
 'fresh_services',fresh_services,
 'healthy_services',healthy_services,
 'services',coalesce((select jsonb_object_agg(service_key,to_jsonb(s)-'service_key') from s),'{}'::jsonb)
) from agg
$$;
revoke all on function private.reliability_summary_tenant(uuid) from public,anon,authenticated;
grant execute on function private.reliability_summary_tenant(uuid) to service_role;

create or replace function private.frontend_performance_summary_tenant(p_tenant_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
with latest as (
 select distinct on(service_key) service_key,status_code,latency_ms,payload_bytes,cache_control,measured_at
 from private.frontend_performance_samples
 where tenant_id=p_tenant_id and status_code between 200 and 399
 order by service_key,measured_at desc
), rolling as (
 select service_key,
   round(percentile_cont(0.5) within group(order by latency_ms)::numeric,1) median_latency_ms,
   count(*) samples
 from private.frontend_performance_samples
 where tenant_id=p_tenant_id and measured_at>now()-interval '30 minutes'
   and status_code between 200 and 399
 group by service_key
), x as (
 select l.*,r.median_latency_ms,r.samples from latest l left join rolling r using(service_key)
), a as (
 select count(*) count_services,
   count(*) filter(where measured_at>now()-interval '15 minutes') fresh_services,
   count(*) filter(where coalesce(samples,0)>=2) sampled_services,
   count(*) filter(where coalesce(median_latency_ms,999999)<=5000) latency_ok
 from x
)
select jsonb_build_object(
 'ok',count_services=3 and fresh_services=3 and sampled_services=3 and latency_ok=3,
 'tenant_id',p_tenant_id,
 'expected_services',3,'service_count',count_services,'fresh_services',fresh_services,
 'sampled_services',sampled_services,'median_latency_budget_ok',latency_ok,
 'latest',coalesce((select jsonb_object_agg(service_key,to_jsonb(x)-'service_key') from x),'{}'::jsonb)
) from a
$$;
revoke all on function private.frontend_performance_summary_tenant(uuid) from public,anon,authenticated;
grant execute on function private.frontend_performance_summary_tenant(uuid) to service_role;
