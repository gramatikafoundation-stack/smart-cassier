-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912113958  Name: sheet_sync_consistency_cadence_guard_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.sheet_sync_consistency_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  active_count integer; checked_count integer; good_count integer; bad_count integer; stale_count integer; advanced_count integer;
  mins integer; win integer; actual_schedule text; expected_schedule text; cadence_ok boolean;
begin
  select count(*)::integer into active_count from public.sheet_sync_targets where enabled;
  select coalesce(reconciliation_minutes,10) into mins from public.sheet_sync_config where id=1;
  win:=greatest(35,mins*3+5);
  expected_schedule:=case mins
    when 5 then '2,7,12,17,22,27,32,37,42,47,52,57 * * * *'
    when 10 then '7,17,27,37,47,57 * * * *'
    when 15 then '7,22,37,52 * * * *'
    when 20 then '7,27,47 * * * *'
    when 30 then '7,37 * * * *'
    when 60 then '7 * * * *'
    else null end;
  select schedule into actual_schedule from cron.job where jobname='rohmat_sheet_sync_reconcile' and active limit 1;
  cadence_ok:=expected_schedule is not null and actual_schedule=expected_schedule;
  select count(*)::integer,
         count(*) filter(where s.consistent)::integer,
         count(*) filter(where not s.consistent)::integer,
         count(*) filter(where s.checked_at < now()-make_interval(mins=>win))::integer,
         count(*) filter(where private.sheet_sync_source_max_updated_at(s.year)>s.source_max_updated_at)::integer
    into checked_count,good_count,bad_count,stale_count,advanced_count
  from private.sheet_sync_consistency_state s
  join public.sheet_sync_targets t on t.year=s.year and t.enabled;
  return jsonb_build_object(
    'ok',active_count>0 and checked_count=active_count and good_count=active_count and bad_count=0 and stale_count=0 and cadence_ok,
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
revoke all on function private.sheet_sync_consistency_summary() from public,anon,authenticated;
