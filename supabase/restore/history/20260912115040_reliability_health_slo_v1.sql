-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912115040  Name: reliability_health_slo_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.reliability_probe_events(
  event_id bigint generated always as identity primary key,
  service_key text not null,
  ok boolean not null,
  http_status integer,
  latency_ms integer,
  error text,
  checked_at timestamptz not null default now()
);
create index if not exists reliability_probe_events_service_checked_idx on private.reliability_probe_events(service_key,checked_at desc);
alter table private.reliability_probe_events enable row level security;
drop policy if exists deny_client_all on private.reliability_probe_events;
create policy deny_client_all on private.reliability_probe_events as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on private.reliability_probe_events from public,anon,authenticated;

create or replace function public.reliability_record_probe(
  p_service_key text,p_ok boolean,p_http_status integer,p_latency_ms integer,p_error text default null
) returns void
language plpgsql
security definer
set search_path=''
as $function$
begin
  if coalesce(p_service_key,'') not in ('public_web','admin_web','kds_web','order_gateway') then raise exception 'invalid_service_key'; end if;
  insert into private.reliability_probe_state(service_key,last_success_at,last_failure_at,last_checked_at,last_http_status,last_latency_ms,consecutive_failures,last_error,updated_at)
  values(p_service_key,case when p_ok then now() end,case when not p_ok then now() end,now(),p_http_status,p_latency_ms,case when p_ok then 0 else 1 end,case when p_ok then null else left(coalesce(p_error,'probe_failed'),500) end,now())
  on conflict(service_key) do update set
    last_success_at=case when p_ok then now() else private.reliability_probe_state.last_success_at end,
    last_failure_at=case when not p_ok then now() else private.reliability_probe_state.last_failure_at end,
    last_checked_at=now(),last_http_status=p_http_status,last_latency_ms=p_latency_ms,
    consecutive_failures=case when p_ok then 0 else private.reliability_probe_state.consecutive_failures+1 end,
    last_error=case when p_ok then null else left(coalesce(p_error,'probe_failed'),500) end,updated_at=now();
  insert into private.reliability_probe_events(service_key,ok,http_status,latency_ms,error,checked_at)
  values(p_service_key,p_ok,p_http_status,p_latency_ms,case when p_ok then null else left(coalesce(p_error,'probe_failed'),500) end,now());
  delete from private.reliability_probe_events where checked_at<now()-interval '30 days';
end
$function$;
revoke all on function public.reliability_record_probe(text,boolean,integer,integer,text) from public,anon,authenticated;
grant execute on function public.reliability_record_probe(text,boolean,integer,integer,text) to service_role;

create or replace function private.reliability_status()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_expected int:=4;
  v_registered int;
  v_recent int;
  v_healthy int;
  v_stuck bigint;
  v_terminal_due bigint;
  v_drill_ok boolean;
  v_drill_at timestamptz;
  v_drill_ms integer;
  v_checkpoint_at timestamptz;
  v_checkpoint_hash text;
  v_checkpoint_ok boolean;
  v_probe_cron boolean;
  v_drill_cron boolean;
  v_checkpoint_cron boolean;
  v_readonly boolean;
  v_samples bigint;
  v_success bigint;
  v_availability numeric;
  v_ok boolean;
begin
  select count(*),
         count(*) filter(where last_checked_at>=now()-interval '15 minutes'),
         count(*) filter(where last_checked_at>=now()-interval '15 minutes' and consecutive_failures<2 and last_success_at>=now()-interval '15 minutes')
  into v_registered,v_recent,v_healthy
  from private.reliability_probe_state
  where service_key in ('public_web','admin_web','kds_web','order_gateway');

  select count(*) into v_stuck from public.orders where created_at<now()-interval '7 days' and lower(coalesce(order_status,'')) not in ('completed','cancelled','canceled','rejected','payment_rejected');
  select count(*) into v_terminal_due from public.orders where created_at<now()-interval '8 days' and lower(coalesce(order_status,'')) in ('completed','cancelled','canceled','rejected','payment_rejected');
  select ok,checked_at,duration_ms into v_drill_ok,v_drill_at,v_drill_ms from private.recovery_drill_state where id=1;
  select created_at,manifest_hash into v_checkpoint_at,v_checkpoint_hash from private.recovery_checkpoints order by created_at desc limit 1;
  v_checkpoint_ok:=v_checkpoint_at is not null and v_checkpoint_at>=now()-interval '36 hours';
  select exists(select 1 from cron.job where jobname='rohmat_reliability_probe' and active and schedule='*/5 * * * *') into v_probe_cron;
  select exists(select 1 from cron.job where jobname='rohmat_recovery_drill_weekly' and active) into v_drill_cron;
  select exists(select 1 from cron.job where jobname='rohmat_recovery_checkpoint_daily' and active) into v_checkpoint_cron;
  v_readonly:=current_setting('transaction_read_only')='on';
  select count(*),count(*) filter(where ok) into v_samples,v_success from private.reliability_probe_events where checked_at>=now()-interval '24 hours';
  v_availability:=case when v_samples>0 then round((100.0*v_success/v_samples)::numeric,3) else null end;
  v_ok:=v_registered=v_expected and v_recent=v_expected and v_healthy=v_expected and coalesce(v_stuck,0)=0 and coalesce(v_terminal_due,0)=0
        and coalesce(v_drill_ok,false) and v_drill_at>=now()-interval '8 days' and v_checkpoint_ok
        and v_probe_cron and v_drill_cron and v_checkpoint_cron and not v_readonly;
  return jsonb_build_object(
    'ok',v_ok,'expected_services',v_expected,'registered_services',v_registered,'recent_services',v_recent,'healthy_services',v_healthy,
    'probe_interval_minutes',5,'probe_stale_after_minutes',15,'availability_samples_24h',v_samples,'availability_success_24h',v_success,'availability_percent_24h',v_availability,
    'stuck_orders_older_7d',coalesce(v_stuck,0),'terminal_orders_unarchived_older_8d',coalesce(v_terminal_due,0),
    'recovery_drill_ok',coalesce(v_drill_ok,false),'last_recovery_drill_at',v_drill_at,'recovery_drill_duration_ms',v_drill_ms,
    'recovery_checkpoint_ok',v_checkpoint_ok,'last_recovery_checkpoint_at',v_checkpoint_at,'last_recovery_checkpoint_hash',v_checkpoint_hash,
    'probe_cron',v_probe_cron,'recovery_drill_cron',v_drill_cron,'recovery_checkpoint_cron',v_checkpoint_cron,'database_read_only',v_readonly
  );
end
$function$;
revoke all on function private.reliability_status() from public,anon,authenticated;

create or replace function private.refresh_production_health_state()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_routes boolean; v_writer boolean; v_locks boolean; v_outbox boolean; v_failed bigint; v_dead bigint; v_stale bigint; v_sensitive bigint;
  v_checks jsonb; v_healthy boolean; v_integration jsonb; v_integration_ok boolean; v_consistency jsonb; v_consistency_ok boolean;
  v_reliability jsonb; v_reliability_ok boolean;
begin
  select (public_url='https://rohmat-pesan-bayar-publik.vercel.app/' and admin_url='https://studio-pengelola-rohmat.vercel.app' and kds_url='https://rohmat-kds-printer.vercel.app') into v_routes from public.site_settings where id=1;
  select coalesce(enabled,false) and coalesce(writer_url,'') like 'https://script.google.com/macros/s/%/exec' into v_writer from public.sheet_sync_config where id=1;
  select coalesce(bool_and(locked),false) into v_locks from private.production_change_control;
  select count(*) filter(where status='failed'),count(*) filter(where status='dead'),count(*) filter(where status in ('pending','processing') and created_at<now()-interval '5 minutes') into v_failed,v_dead,v_stale from public.sheet_sync_outbox;
  v_outbox:=(v_failed=0 and v_dead=0 and v_stale=0);
  select count(*) into v_sensitive from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE');
  v_integration:=private.integration_contract_status(); v_integration_ok:=coalesce((v_integration->>'ok')::boolean,false);
  v_consistency:=private.sheet_sync_consistency_summary(); v_consistency_ok:=coalesce((v_consistency->>'ok')::boolean,false);
  v_reliability:=private.reliability_status(); v_reliability_ok:=coalesce((v_reliability->>'ok')::boolean,false);
  v_checks:=jsonb_build_object('canonical_routes',coalesce(v_routes,false),'writer_enabled',coalesce(v_writer,false),'change_control_locked',coalesce(v_locks,false),'sheet_outbox_clean',coalesce(v_outbox,false),'sheet_failed',coalesce(v_failed,0),'sheet_dead',coalesce(v_dead,0),'sheet_stale',coalesce(v_stale,0),'sheet_consistency',v_consistency,'sheet_consistency_ok',v_consistency_ok,'anon_public_security_definer',coalesce(v_sensitive,0),'integration_contracts',v_integration,'integration_contracts_ok',v_integration_ok,'reliability',v_reliability,'reliability_ok',v_reliability_ok);
  v_healthy:=coalesce(v_routes,false) and coalesce(v_writer,false) and coalesce(v_locks,false) and coalesce(v_outbox,false) and coalesce(v_sensitive,0)=0 and v_integration_ok and v_consistency_ok and v_reliability_ok;
  insert into private.production_health_state(id,healthy,checks,checked_at) values(1,v_healthy,v_checks,now()) on conflict(id) do update set healthy=excluded.healthy,checks=excluded.checks,checked_at=excluded.checked_at;
  return jsonb_build_object('healthy',v_healthy,'checks',v_checks,'checked_at',now());
end
$function$;
revoke all on function private.refresh_production_health_state() from public,anon,authenticated;
