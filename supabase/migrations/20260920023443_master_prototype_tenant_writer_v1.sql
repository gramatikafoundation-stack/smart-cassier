-- ROHMAT MASTER PROTOTIPE v1
-- Phase 8: tenant-scoped Google Writer routing and consistency ledger.
-- Legacy reference-tenant writer configuration stays intact for backward compatibility.

create table if not exists private.tenant_writer_config (
  tenant_id uuid primary key references private.platform_tenants(id) on delete cascade,
  enabled boolean not null default false,
  writer_url text,
  max_attempts integer not null default 10 check(max_attempts between 1 and 50),
  expected_writer_version integer not null default 4 check(expected_writer_version>=1),
  pii_retention_days integer not null default 365 check(pii_retention_days between 1 and 3650),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table private.tenant_writer_config enable row level security;
revoke all on private.tenant_writer_config from anon,authenticated;
drop policy if exists tenant_writer_config_service_role_all on private.tenant_writer_config;
create policy tenant_writer_config_service_role_all
on private.tenant_writer_config for all to service_role using(true) with check(true);
drop trigger if exists trg_tenant_writer_config_updated_at on private.tenant_writer_config;
create trigger trg_tenant_writer_config_updated_at
before update on private.tenant_writer_config
for each row execute function public.set_updated_at();

insert into private.tenant_writer_config(
  tenant_id,enabled,writer_url,max_attempts,expected_writer_version,pii_retention_days
)
select private.reference_tenant_id(),
       coalesce(c.enabled,false),
       c.writer_url,
       coalesce(c.max_attempts,10),
       4,
       365
from public.sheet_sync_config c
where c.id=1
on conflict(tenant_id) do update
set enabled=excluded.enabled,
    writer_url=excluded.writer_url,
    max_attempts=excluded.max_attempts,
    expected_writer_version=4,
    pii_retention_days=365,
    updated_at=now();

alter table private.sheet_sync_consistency_state
  add column if not exists tenant_id uuid;
update private.sheet_sync_consistency_state
set tenant_id=private.reference_tenant_id()
where tenant_id is null;
alter table private.sheet_sync_consistency_state
  alter column tenant_id set default private.reference_tenant_id(),
  alter column tenant_id set not null;

do $$
declare r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid='private.sheet_sync_consistency_state'::regclass
      and contype='p'
  loop
    execute format('alter table private.sheet_sync_consistency_state drop constraint %I',r.conname);
  end loop;
end $$;

do $$
begin
  begin
    alter table private.sheet_sync_consistency_state
      add constraint sheet_sync_consistency_state_tenant_fkey
      foreign key(tenant_id) references private.platform_tenants(id) on delete cascade;
  exception when duplicate_object then null;
  end;
end $$;

alter table private.sheet_sync_consistency_state
  add constraint sheet_sync_consistency_state_pkey
  primary key(tenant_id,year);

create index if not exists sheet_sync_consistency_state_tenant_checked_idx
  on private.sheet_sync_consistency_state(tenant_id,checked_at desc);

create or replace function public.tenant_sheet_sync_config(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
select jsonb_build_object(
  'ok',true,
  'tenant_id',t.id,
  'tenant_slug',t.slug,
  'business_name',c.business_name,
  'timezone',c.timezone,
  'enabled',coalesce(w.enabled,false),
  'writer_url',w.writer_url,
  'max_attempts',coalesce(w.max_attempts,10),
  'expected_writer_version',coalesce(w.expected_writer_version,4),
  'pii_retention_days',coalesce(w.pii_retention_days,365),
  'targets',coalesce((
    select jsonb_agg(jsonb_build_object(
      'year',x.year,
      'spreadsheet_id',x.spreadsheet_id,
      'label',x.label,
      'enabled',x.enabled,
      'expected_tabs',x.expected_tabs
    ) order by x.year)
    from private.tenant_sheet_targets x
    where x.tenant_id=p_tenant_id and x.enabled
  ),'[]'::jsonb)
)
from private.platform_tenants t
join private.tenant_runtime_config c on c.tenant_id=t.id and c.enabled
left join private.tenant_writer_config w on w.tenant_id=t.id
where t.id=p_tenant_id and t.status='active'
limit 1
$$;
revoke all on function public.tenant_sheet_sync_config(uuid) from public,anon,authenticated;
grant execute on function public.tenant_sheet_sync_config(uuid) to service_role;

create or replace function public.record_sheet_sync_ack_tenant(
  p_tenant_id uuid,p_request_id uuid,p_http_status integer,p_ack jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r jsonb;
  y integer;
  expected jsonb;
  observed jsonb;
  target_id text;
  ack_id text;
  ok boolean;
  total integer:=0;
  good integer:=0;
begin
  if not exists(
    select 1 from private.platform_tenants t
    join private.tenant_runtime_config c on c.tenant_id=t.id
    where t.id=p_tenant_id and t.status='active' and c.enabled
  ) then return jsonb_build_object('ok',false,'error','tenant_unavailable'); end if;

  if p_ack is null
     or p_ack->>'ok'<>'true'
     or coalesce((p_ack->>'version')::integer,0)<>2
     or jsonb_typeof(p_ack->'result')<>'array' then
    return jsonb_build_object('ok',false,'error','invalid_ack_shape');
  end if;

  if nullif(p_ack->>'tenant_id','') is not null
     and (p_ack->>'tenant_id')::uuid<>p_tenant_id then
    return jsonb_build_object('ok',false,'error','tenant_ack_mismatch');
  end if;

  for r in select value from jsonb_array_elements(p_ack->'result')
  loop
    y:=nullif(r->>'year','')::integer;
    if y is null then continue; end if;

    select spreadsheet_id into target_id
    from private.tenant_sheet_targets
    where tenant_id=p_tenant_id and year=y and enabled=true;

    if target_id is null then continue; end if;
    total:=total+1;
    ack_id:=coalesce(r->>'spreadsheetId','');
    expected:=private.sheet_sync_expected_rows_tenant(p_tenant_id,y);
    observed:=coalesce(r->'rows','{}'::jsonb);

    ok:=ack_id=target_id
      and coalesce((observed->>'PEMESAN')::integer,-1)=coalesce((expected->>'PEMESAN')::integer,-2)
      and coalesce((observed->>'PESANAN')::integer,-1)=coalesce((expected->>'PESANAN')::integer,-2)
      and coalesce((observed->>'MENU & STOK')::integer,-1)=coalesce((expected->>'MENU & STOK')::integer,-2)
      and coalesce((observed->>'KEUANGAN')::integer,-1)=coalesce((expected->>'KEUANGAN')::integer,-2);

    if ok then good:=good+1; end if;

    insert into private.sheet_sync_consistency_state(
      tenant_id,year,expected_rows,observed_rows,consistent,last_request_id,
      last_http_status,last_error,source_max_updated_at,checked_at
    )
    values(
      p_tenant_id,y,expected,observed,ok,p_request_id,p_http_status,
      case when ok then null else 'writer_row_count_mismatch' end,
      private.sheet_sync_source_max_updated_at_tenant(p_tenant_id,y),now()
    )
    on conflict(tenant_id,year) do update
    set expected_rows=excluded.expected_rows,
        observed_rows=excluded.observed_rows,
        consistent=excluded.consistent,
        last_request_id=excluded.last_request_id,
        last_http_status=excluded.last_http_status,
        last_error=excluded.last_error,
        source_max_updated_at=excluded.source_max_updated_at,
        checked_at=excluded.checked_at;
  end loop;

  return jsonb_build_object(
    'ok',total>0 and good=total,
    'tenant_id',p_tenant_id,
    'checked',total,
    'consistent',good
  );
end
$$;
revoke all on function public.record_sheet_sync_ack_tenant(uuid,uuid,integer,jsonb) from public,anon,authenticated;
grant execute on function public.record_sheet_sync_ack_tenant(uuid,uuid,integer,jsonb) to service_role;

create or replace function private.sheet_sync_consistency_summary_tenant(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
select jsonb_build_object(
  'ok',coalesce(bool_and(consistent),true),
  'tenant_id',p_tenant_id,
  'targets',count(*),
  'consistent_targets',count(*) filter(where consistent),
  'inconsistent_targets',count(*) filter(where not consistent),
  'oldest_checked_at',min(checked_at),
  'last_checked_at',max(checked_at),
  'rows',coalesce(jsonb_agg(jsonb_build_object(
    'year',year,
    'expected',expected_rows,
    'observed',observed_rows,
    'consistent',consistent,
    'last_error',last_error,
    'checked_at',checked_at
  ) order by year),'[]'::jsonb)
)
from private.sheet_sync_consistency_state
where tenant_id=p_tenant_id
$$;
revoke all on function private.sheet_sync_consistency_summary_tenant(uuid) from public,anon,authenticated;
grant execute on function private.sheet_sync_consistency_summary_tenant(uuid) to service_role;

create or replace function public.get_sheet_sync_health_tenant(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
select jsonb_build_object(
  'tenant_id',p_tenant_id,
  'enabled',coalesce((select enabled from private.tenant_writer_config where tenant_id=p_tenant_id),false),
  'writer_configured',coalesce((select writer_url is not null and writer_url<>'' from private.tenant_writer_config where tenant_id=p_tenant_id),false),
  'active_targets',(select count(*) from private.tenant_sheet_targets where tenant_id=p_tenant_id and enabled),
  'pending',(select count(*) from public.sheet_sync_outbox where tenant_id=p_tenant_id and status='pending'),
  'failed',(select count(*) from public.sheet_sync_outbox where tenant_id=p_tenant_id and status='failed'),
  'dead',(select count(*) from public.sheet_sync_outbox where tenant_id=p_tenant_id and status='dead'),
  'processing',(select count(*) from public.sheet_sync_outbox where tenant_id=p_tenant_id and status='processing'),
  'synced',(select count(*) from public.sheet_sync_outbox where tenant_id=p_tenant_id and status='synced'),
  'superseded',(select count(*) from public.sheet_sync_outbox where tenant_id=p_tenant_id and status='superseded'),
  'oldest_pending_at',(select min(created_at) from public.sheet_sync_outbox where tenant_id=p_tenant_id and status in ('pending','failed')),
  'last_event_at',(select max(created_at) from public.sheet_sync_outbox where tenant_id=p_tenant_id),
  'last_synced_at',(select max(synced_at) from public.sheet_sync_outbox where tenant_id=p_tenant_id and status='synced'),
  'consistency',private.sheet_sync_consistency_summary_tenant(p_tenant_id)
)
$$;
revoke all on function public.get_sheet_sync_health_tenant(uuid) from public,anon,authenticated;
grant execute on function public.get_sheet_sync_health_tenant(uuid) to service_role;

comment on table private.tenant_writer_config is
  'Per-tenant Google Writer routing. Same canonical Code.gs may be deployed independently per tenant; shared Supabase remains the source of truth.';
