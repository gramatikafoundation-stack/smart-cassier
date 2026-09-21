-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912113338  Name: sheet_sync_consistency_hardening_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.sheet_sync_consistency_state (
  year integer primary key,
  expected_rows jsonb not null default '{}'::jsonb,
  observed_rows jsonb not null default '{}'::jsonb,
  consistent boolean not null default false,
  last_request_id uuid,
  last_http_status integer,
  last_error text,
  source_max_updated_at timestamptz,
  checked_at timestamptz not null default now()
);
alter table private.sheet_sync_consistency_state enable row level security;
drop policy if exists deny_client_all on private.sheet_sync_consistency_state;
create policy deny_client_all on private.sheet_sync_consistency_state as restrictive for all to anon, authenticated using (false) with check (false);
revoke all on private.sheet_sync_consistency_state from public, anon, authenticated;

create or replace function private.sheet_sync_expected_rows(p_year integer)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
with bounds as (
  select make_timestamptz(p_year,1,1,0,0,0,'Asia/Jakarta') as s,
         make_timestamptz(p_year+1,1,1,0,0,0,'Asia/Jakarta') as e
), ids as (
  select o.id from public.orders o, bounds b where o.created_at>=b.s and o.created_at<b.e
  union
  select a.id from public.order_history_archive a, bounds b where a.created_at>=b.s and a.created_at<b.e
), c as (
  select count(*)::integer as orders_count from ids
), m as (
  select count(*)::integer as menu_count from public.menu_items
)
select jsonb_build_object(
  'PEMESAN',c.orders_count,
  'PESANAN',c.orders_count,
  'MENU & STOK',m.menu_count,
  'KEUANGAN',c.orders_count
) from c,m
$$;
revoke all on function private.sheet_sync_expected_rows(integer) from public, anon, authenticated;

create or replace function private.sheet_sync_source_max_updated_at(p_year integer)
returns timestamptz
language sql
stable
security definer
set search_path=''
as $$
with bounds as (
  select make_timestamptz(p_year,1,1,0,0,0,'Asia/Jakarta') as s,
         make_timestamptz(p_year+1,1,1,0,0,0,'Asia/Jakarta') as e
), x as (
  select max(o.updated_at) as t from public.orders o,bounds b where o.created_at>=b.s and o.created_at<b.e
  union all
  select max(coalesce(a.updated_at,a.archived_at)) from public.order_history_archive a,bounds b where a.created_at>=b.s and a.created_at<b.e
  union all
  select max(m.updated_at) from public.menu_items m
)
select max(t) from x
$$;
revoke all on function private.sheet_sync_source_max_updated_at(integer) from public, anon, authenticated;

create or replace function public.record_sheet_sync_ack(p_request_id uuid,p_http_status integer,p_ack jsonb)
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
  if p_ack is null or p_ack->>'ok'<>'true' or coalesce((p_ack->>'version')::integer,0)<>2 or jsonb_typeof(p_ack->'result')<>'array' then
    return jsonb_build_object('ok',false,'error','invalid_ack_shape');
  end if;
  for r in select value from jsonb_array_elements(p_ack->'result') loop
    y:=nullif(r->>'year','')::integer;
    if y is null then continue; end if;
    select spreadsheet_id into target_id from public.sheet_sync_targets where year=y and enabled=true;
    if target_id is null then continue; end if;
    total:=total+1;
    ack_id:=coalesce(r->>'spreadsheetId','');
    expected:=private.sheet_sync_expected_rows(y);
    observed:=coalesce(r->'rows','{}'::jsonb);
    ok := ack_id=target_id
      and coalesce((observed->>'PEMESAN')::integer,-1)=coalesce((expected->>'PEMESAN')::integer,-2)
      and coalesce((observed->>'PESANAN')::integer,-1)=coalesce((expected->>'PESANAN')::integer,-2)
      and coalesce((observed->>'MENU & STOK')::integer,-1)=coalesce((expected->>'MENU & STOK')::integer,-2)
      and coalesce((observed->>'KEUANGAN')::integer,-1)=coalesce((expected->>'KEUANGAN')::integer,-2);
    if ok then good:=good+1; end if;
    insert into private.sheet_sync_consistency_state(year,expected_rows,observed_rows,consistent,last_request_id,last_http_status,last_error,source_max_updated_at,checked_at)
    values(y,expected,observed,ok,p_request_id,p_http_status,case when ok then null else 'writer_row_count_mismatch' end,private.sheet_sync_source_max_updated_at(y),now())
    on conflict(year) do update set
      expected_rows=excluded.expected_rows,
      observed_rows=excluded.observed_rows,
      consistent=excluded.consistent,
      last_request_id=excluded.last_request_id,
      last_http_status=excluded.last_http_status,
      last_error=excluded.last_error,
      source_max_updated_at=excluded.source_max_updated_at,
      checked_at=excluded.checked_at;
  end loop;
  return jsonb_build_object('ok',total>0 and good=total,'checked',total,'consistent',good);
end
$$;
revoke all on function public.record_sheet_sync_ack(uuid,integer,jsonb) from public,anon,authenticated;
grant execute on function public.record_sheet_sync_ack(uuid,integer,jsonb) to service_role;

create or replace function private.sheet_sync_consistency_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  active_count integer;
  checked_count integer;
  good_count integer;
  bad_count integer;
  stale_count integer;
  mins integer;
begin
  select count(*)::integer into active_count from public.sheet_sync_targets where enabled;
  select coalesce(reconciliation_minutes,10) into mins from public.sheet_sync_config where id=1;
  select count(*)::integer,
         count(*) filter(where s.consistent)::integer,
         count(*) filter(where not s.consistent)::integer,
         count(*) filter(where s.checked_at < now() - make_interval(mins => greatest(35,mins*3+5)))::integer
    into checked_count,good_count,bad_count,stale_count
  from private.sheet_sync_consistency_state s
  join public.sheet_sync_targets t on t.year=s.year and t.enabled;
  return jsonb_build_object(
    'ok',active_count>0 and checked_count=active_count and good_count=active_count and bad_count=0 and stale_count=0,
    'active_targets',active_count,
    'checked_targets',checked_count,
    'consistent_targets',good_count,
    'inconsistent_targets',bad_count,
    'stale_targets',stale_count,
    'freshness_window_minutes',greatest(35,mins*3+5)
  );
end
$$;
revoke all on function private.sheet_sync_consistency_summary() from public,anon,authenticated;

create or replace function public.get_sheet_sync_health()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
select jsonb_build_object(
  'enabled',coalesce((select enabled from public.sheet_sync_config where id=1),false),
  'writer_configured',coalesce((select writer_url is not null and writer_url<>'' from public.sheet_sync_config where id=1),false),
  'active_targets',(select count(*) from public.sheet_sync_targets where enabled),
  'pending',(select count(*) from public.sheet_sync_outbox where status='pending'),
  'failed',(select count(*) from public.sheet_sync_outbox where status='failed'),
  'dead',(select count(*) from public.sheet_sync_outbox where status='dead'),
  'processing',(select count(*) from public.sheet_sync_outbox where status='processing'),
  'synced',(select count(*) from public.sheet_sync_outbox where status='synced'),
  'superseded',(select count(*) from public.sheet_sync_outbox where status='superseded'),
  'oldest_pending_at',(select min(created_at) from public.sheet_sync_outbox where status in ('pending','failed')),
  'last_event_at',(select max(created_at) from public.sheet_sync_outbox),
  'last_synced_at',(select max(synced_at) from public.sheet_sync_outbox where status='synced'),
  'consistency',private.sheet_sync_consistency_summary()
)
$$;

create or replace function private.refresh_production_health_state()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_routes boolean; v_writer boolean; v_locks boolean; v_outbox boolean; v_failed bigint; v_dead bigint; v_stale bigint; v_sensitive bigint;
  v_checks jsonb; v_healthy boolean; v_integration jsonb; v_integration_ok boolean; v_consistency jsonb; v_consistency_ok boolean;
begin
  select (public_url='https://rohmat-pesan-bayar-publik.vercel.app/' and admin_url='https://studio-pengelola-rohmat.vercel.app' and kds_url='https://rohmat-kds-printer.vercel.app') into v_routes from public.site_settings where id=1;
  select coalesce(enabled,false) and coalesce(writer_url,'') like 'https://script.google.com/macros/s/%/exec' into v_writer from public.sheet_sync_config where id=1;
  select coalesce(bool_and(locked),false) into v_locks from private.production_change_control;
  select count(*) filter(where status='failed'),count(*) filter(where status='dead'),count(*) filter(where status in ('pending','processing') and created_at<now()-interval '5 minutes') into v_failed,v_dead,v_stale from public.sheet_sync_outbox;
  v_outbox:=(v_failed=0 and v_dead=0 and v_stale=0);
  select count(*) into v_sensitive from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE');
  v_integration:=private.integration_contract_status(); v_integration_ok:=coalesce((v_integration->>'ok')::boolean,false);
  v_consistency:=private.sheet_sync_consistency_summary(); v_consistency_ok:=coalesce((v_consistency->>'ok')::boolean,false);
  v_checks:=jsonb_build_object('canonical_routes',coalesce(v_routes,false),'writer_enabled',coalesce(v_writer,false),'change_control_locked',coalesce(v_locks,false),'sheet_outbox_clean',coalesce(v_outbox,false),'sheet_failed',coalesce(v_failed,0),'sheet_dead',coalesce(v_dead,0),'sheet_stale',coalesce(v_stale,0),'sheet_consistency',v_consistency,'sheet_consistency_ok',v_consistency_ok,'anon_public_security_definer',coalesce(v_sensitive,0),'integration_contracts',v_integration,'integration_contracts_ok',v_integration_ok);
  v_healthy:=coalesce(v_routes,false) and coalesce(v_writer,false) and coalesce(v_locks,false) and coalesce(v_outbox,false) and coalesce(v_sensitive,0)=0 and v_integration_ok and v_consistency_ok;
  insert into private.production_health_state(id,healthy,checks,checked_at) values(1,v_healthy,v_checks,now()) on conflict(id) do update set healthy=excluded.healthy,checks=excluded.checks,checked_at=excluded.checked_at;
  return jsonb_build_object('healthy',v_healthy,'checks',v_checks,'checked_at',now());
end
$$;

create or replace function private.enqueue_sheet_reconciliation()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  v_enabled boolean;
  v_minutes integer;
  v_bucket text;
  v_epoch bigint;
begin
  select enabled,coalesce(reconciliation_minutes,10) into v_enabled,v_minutes from public.sheet_sync_config where id=1;
  if coalesce(v_enabled,false) is false then return 0; end if;
  v_minutes:=greatest(5,least(60,v_minutes));
  v_epoch:=floor(extract(epoch from now())/(v_minutes*60))::bigint;
  v_bucket:=to_char(now() at time zone 'UTC','YYYYMMDDHH24')||':'||v_epoch::text;
  insert into public.sheet_sync_outbox(idempotency_key,entity_type,entity_id,operation,target_year,affected_tabs,payload,source_updated_at)
  values('reconcile:all:'||v_bucket,'system','all-years','RECONCILE',null,'["DASHBOARD","PEMESAN","PESANAN","MENU & STOK","KEUANGAN"]'::jsonb,jsonb_build_object('reason','periodic_reconciliation','target_year',null,'bucket',v_bucket,'interval_minutes',v_minutes),now())
  on conflict(idempotency_key) do nothing;
  return case when found then 1 else 0 end;
end
$$;

do $$
begin
  if exists(select 1 from cron.job where jobname='rohmat_sheet_sync_reconcile') then
    perform cron.unschedule('rohmat_sheet_sync_reconcile');
  end if;
end $$;
select cron.schedule('rohmat_sheet_sync_reconcile','7,17,27,37,47,57 * * * *','select private.enqueue_sheet_reconciliation();');
