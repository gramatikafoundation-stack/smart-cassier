-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912174814  Name: reliability_slo_rolling_health_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.reliability_slo_config (
  service_key text primary key references private.reliability_probe_state(service_key) on update cascade on delete restrict,
  min_1h_percent numeric(6,3) not null check(min_1h_percent between 0 and 100),
  min_24h_percent numeric(6,3) not null check(min_24h_percent between 0 and 100),
  critical_below_percent numeric(6,3) not null check(critical_below_percent between 0 and 100),
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table private.reliability_slo_config enable row level security;
drop policy if exists reliability_slo_config_deny_clients on private.reliability_slo_config;
create policy reliability_slo_config_deny_clients on private.reliability_slo_config for all to anon, authenticated using (false) with check (false);
revoke all on private.reliability_slo_config from public, anon, authenticated;
grant select on private.reliability_slo_config to service_role;

insert into private.reliability_slo_config(service_key,min_1h_percent,min_24h_percent,critical_below_percent,enabled)
values
 ('public_web',99.000,99.900,95.000,true),
 ('admin_web',99.000,99.900,95.000,true),
 ('kds_web',99.000,99.900,95.000,true),
 ('order_gateway',99.500,99.950,97.000,true)
on conflict(service_key) do update set min_1h_percent=excluded.min_1h_percent,min_24h_percent=excluded.min_24h_percent,critical_below_percent=excluded.critical_below_percent,enabled=excluded.enabled,updated_at=now();

create or replace function private.reliability_slo_summary()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
with cfg as (
  select * from private.reliability_slo_config where enabled
), stats as (
  select c.service_key,c.min_1h_percent,c.min_24h_percent,c.critical_below_percent,
         count(e.event_id) filter(where e.checked_at>=now()-interval '1 hour') as samples_1h,
         count(e.event_id) filter(where e.checked_at>=now()-interval '1 hour' and e.ok) as success_1h,
         count(e.event_id) filter(where e.checked_at>=now()-interval '24 hours') as samples_24h,
         count(e.event_id) filter(where e.checked_at>=now()-interval '24 hours' and e.ok) as success_24h
  from cfg c
  left join private.reliability_probe_events e on e.service_key=c.service_key and e.checked_at>=now()-interval '24 hours'
  group by c.service_key,c.min_1h_percent,c.min_24h_percent,c.critical_below_percent
), scored as (
  select s.*,
    case when samples_1h>0 then round(100.0*success_1h/samples_1h,3) end as pct_1h,
    case when samples_24h>0 then round(100.0*success_24h/samples_24h,3) end as pct_24h
  from stats s
), rows as (
  select service_key,samples_1h,success_1h,samples_24h,success_24h,pct_1h,pct_24h,min_1h_percent,min_24h_percent,critical_below_percent,
         (samples_1h>=6 and pct_1h>=min_1h_percent and samples_24h>=12 and pct_24h>=min_24h_percent) as slo_ok,
         case
           when samples_1h=0 or samples_24h=0 then 'unknown'
           when pct_1h<critical_below_percent or pct_24h<critical_below_percent then 'critical'
           when pct_1h<min_1h_percent or pct_24h<min_24h_percent then 'degraded'
           else 'healthy'
         end as state
  from scored
)
select jsonb_build_object(
  'ok',coalesce(bool_and(slo_ok),false),
  'state',case when bool_or(state='critical') then 'critical' when bool_or(state in ('degraded','unknown')) then 'degraded' else 'healthy' end,
  'services',coalesce(jsonb_agg(jsonb_build_object(
    'service_key',service_key,'state',state,'slo_ok',slo_ok,
    'samples_1h',samples_1h,'success_1h',success_1h,'availability_1h',pct_1h,'target_1h',min_1h_percent,
    'samples_24h',samples_24h,'success_24h',success_24h,'availability_24h',pct_24h,'target_24h',min_24h_percent
  ) order by service_key),'[]'::jsonb)
) from rows;
$$;
revoke all on function private.reliability_slo_summary() from public, anon, authenticated;
grant execute on function private.reliability_slo_summary() to service_role;

create or replace function private.reliability_status()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_expected int:=4; v_registered int; v_recent int; v_healthy int; v_stuck bigint; v_terminal_due bigint;
  v_drill_ok boolean; v_drill_at timestamptz; v_drill_ms integer; v_checkpoint_at timestamptz; v_checkpoint_hash text; v_checkpoint_ok boolean;
  v_probe_cron boolean; v_drill_cron boolean; v_checkpoint_cron boolean; v_readonly boolean;
  v_samples bigint; v_success bigint; v_availability numeric; v_slo jsonb; v_slo_ok boolean; v_state text; v_ok boolean;
begin
  select count(*),count(*) filter(where last_checked_at>=now()-interval '15 minutes'),count(*) filter(where last_checked_at>=now()-interval '15 minutes' and consecutive_failures<2 and last_success_at>=now()-interval '15 minutes')
  into v_registered,v_recent,v_healthy from private.reliability_probe_state where service_key in ('public_web','admin_web','kds_web','order_gateway');
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
  v_slo:=private.reliability_slo_summary(); v_slo_ok:=coalesce((v_slo->>'ok')::boolean,false); v_state:=coalesce(v_slo->>'state','degraded');
  v_ok:=v_registered=v_expected and v_recent=v_expected and v_healthy=v_expected and v_slo_ok and coalesce(v_stuck,0)=0 and coalesce(v_terminal_due,0)=0
        and coalesce(v_drill_ok,false) and v_drill_at>=now()-interval '8 days' and v_checkpoint_ok and v_probe_cron and v_drill_cron and v_checkpoint_cron and not v_readonly;
  return jsonb_build_object(
    'ok',v_ok,'state',case when not v_ok and v_state='healthy' then 'degraded' else v_state end,
    'slo',v_slo,'expected_services',v_expected,'registered_services',v_registered,'recent_services',v_recent,'healthy_services',v_healthy,
    'probe_interval_minutes',5,'probe_stale_after_minutes',15,'availability_samples_24h',v_samples,'availability_success_24h',v_success,'availability_percent_24h',v_availability,
    'stuck_orders_older_7d',coalesce(v_stuck,0),'terminal_orders_unarchived_older_8d',coalesce(v_terminal_due,0),
    'recovery_drill_ok',coalesce(v_drill_ok,false),'last_recovery_drill_at',v_drill_at,'recovery_drill_duration_ms',v_drill_ms,
    'recovery_checkpoint_ok',v_checkpoint_ok,'last_recovery_checkpoint_at',v_checkpoint_at,'last_recovery_checkpoint_hash',v_checkpoint_hash,
    'probe_cron',v_probe_cron,'recovery_drill_cron',v_drill_cron,'recovery_checkpoint_cron',v_checkpoint_cron,'database_read_only',v_readonly
  );
end
$$;
revoke all on function private.reliability_status() from public, anon, authenticated;
grant execute on function private.reliability_status() to service_role;
