-- ROHMAT MASTER PROTOTIPE v1
-- Compatibility repair: keep the legacy production Writer path reference-tenant scoped
-- while the tenant-native worker deployment is being certified.

create or replace function private.sheet_sync_expected_rows(p_year integer)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select private.sheet_sync_expected_rows_tenant(private.reference_tenant_id(),p_year)
$$;

create or replace function private.sheet_sync_source_max_updated_at(p_year integer)
returns timestamptz
language sql
stable
security definer
set search_path=''
as $$
  select private.sheet_sync_source_max_updated_at_tenant(private.reference_tenant_id(),p_year)
$$;

create or replace function public.record_sheet_sync_ack(
  p_request_id uuid,p_http_status integer,p_ack jsonb
)
returns jsonb
language sql
security definer
set search_path=''
as $$
  select public.record_sheet_sync_ack_tenant(
    private.reference_tenant_id(),p_request_id,p_http_status,p_ack
  )
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
  v_tenant uuid:=private.reference_tenant_id();
  active_count integer;
  checked_count integer;
  good_count integer;
  bad_count integer;
  stale_count integer;
  advanced_count integer;
  mins integer;
  win integer;
  actual_schedule text;
  expected_schedule text;
  cadence_ok boolean;
begin
  select count(*)::integer into active_count
  from private.tenant_sheet_targets
  where tenant_id=v_tenant and enabled;

  select coalesce(reconciliation_minutes,10) into mins
  from public.sheet_sync_config where id=1;

  win:=greatest(35,mins*3+5);
  expected_schedule:=case mins
    when 5 then '2,7,12,17,22,27,32,37,42,47,52,57 * * * *'
    when 10 then '7,17,27,37,47,57 * * * *'
    when 15 then '7,22,37,52 * * * *'
    when 20 then '7,27,47 * * * *'
    when 30 then '7,37 * * * *'
    when 60 then '7 * * * *'
    else null end;

  select schedule into actual_schedule
  from cron.job
  where jobname='rohmat_sheet_sync_reconcile' and active
  limit 1;
  cadence_ok:=expected_schedule is not null and actual_schedule=expected_schedule;

  select count(*)::integer,
         count(*) filter(where s.consistent)::integer,
         count(*) filter(where not s.consistent)::integer,
         count(*) filter(where s.checked_at<now()-make_interval(mins=>win))::integer,
         count(*) filter(
           where private.sheet_sync_source_max_updated_at_tenant(v_tenant,s.year)>s.source_max_updated_at
         )::integer
  into checked_count,good_count,bad_count,stale_count,advanced_count
  from private.sheet_sync_consistency_state s
  join private.tenant_sheet_targets t
    on t.tenant_id=s.tenant_id and t.year=s.year and t.enabled
  where s.tenant_id=v_tenant;

  return jsonb_build_object(
    'ok',active_count>0 and checked_count=active_count and good_count=active_count
      and bad_count=0 and stale_count=0 and cadence_ok,
    'tenant_id',v_tenant,
    'compatibility_scope','reference_tenant_only',
    'active_targets',active_count,
    'checked_targets',checked_count,
    'consistent_targets',good_count,
    'inconsistent_targets',bad_count,
    'stale_targets',stale_count,
    'source_advanced_targets',advanced_count,
    'reconciliation_minutes',mins,
    'cron_schedule',actual_schedule,
    'cadence_aligned',cadence_ok,
    'freshness_window_minutes',win
  );
end
$$;

comment on function public.record_sheet_sync_ack(uuid,integer,jsonb) is
  'Legacy compatibility wrapper restricted to the Rohmat reference tenant. Tenant-native workers must call record_sheet_sync_ack_tenant.';
