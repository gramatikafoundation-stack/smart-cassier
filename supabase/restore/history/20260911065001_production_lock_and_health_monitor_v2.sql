-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911065001  Name: production_lock_and_health_monitor_v2
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table private.production_change_control
  drop constraint if exists production_change_control_locked_chk;
alter table private.production_change_control
  add constraint production_change_control_locked_chk check (locked is true);

insert into private.production_change_control(component,component_type,locked,baseline_version,canonical_target,allowed_change_scope,note)
values
 ('database-core','postgres-production',true,'current-schema','yybhpmjuywjxqurrrrxl','database-target-only','Production database schema and operational data are protected from unrelated UI/design changes.'),
 ('smart-cashier','edge-function',true,'v3','rohmat-smart-cashier-v1','cashier-target-only','Cashier flow, session validation, origin validation, rate limiting and order creation are isolated from unrelated changes.'),
 ('google-writer','apps-script-production',true,'event-driven-v2','https://script.google.com/macros/s/AKfycbwJgyD676R8PcLnETjhPKGHwm56e0k5EkqMz23OPNWhxMf-MOrUwEDR0waxKbYcjizz/exec','sheets-only','Google Writer is the event-driven reporting mirror endpoint; do not alter for unrelated site work.'),
 ('sheet-sync','postgres-edge-pipeline',true,'event-driven','sheet_sync_outbox','sheets-only','Event-driven outbox is primary; worker and reconciliation are recovery layers only.')
on conflict(component) do update set
  component_type=excluded.component_type,
  locked=true,
  baseline_version=coalesce(excluded.baseline_version,private.production_change_control.baseline_version),
  canonical_target=excluded.canonical_target,
  allowed_change_scope=excluded.allowed_change_scope,
  note=excluded.note,
  updated_at=now();

create table if not exists private.production_health_state(
  id smallint primary key default 1 check(id=1),
  healthy boolean not null default false,
  checks jsonb not null default '{}'::jsonb,
  checked_at timestamptz not null default now()
);
revoke all on private.production_health_state from public, anon, authenticated;

create or replace function private.refresh_production_health_state()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_routes boolean;
  v_writer boolean;
  v_locks boolean;
  v_outbox boolean;
  v_failed bigint;
  v_dead bigint;
  v_stale bigint;
  v_sensitive bigint;
  v_checks jsonb;
  v_healthy boolean;
begin
  select (public_url='https://rohmat-pesan-bayar-publik.vercel.app/'
      and admin_url='https://studio-pengelola-rohmat.vercel.app'
      and kds_url='https://rohmat-kds-printer.vercel.app')
    into v_routes from public.site_settings where id=1;

  select coalesce(enabled,false) and coalesce(writer_url,'') like 'https://script.google.com/macros/s/%/exec'
    into v_writer from public.sheet_sync_config where id=1;

  select coalesce(bool_and(locked),false) into v_locks from private.production_change_control;

  select count(*) filter(where status='failed'),
         count(*) filter(where status='dead'),
         count(*) filter(where status in ('pending','processing') and created_at < now()-interval '5 minutes')
    into v_failed,v_dead,v_stale
  from public.sheet_sync_outbox;
  v_outbox := (v_failed=0 and v_dead=0 and v_stale=0);

  select count(*) into v_sensitive
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef
    and pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE');

  v_checks:=jsonb_build_object(
    'canonical_routes',coalesce(v_routes,false),
    'writer_enabled',coalesce(v_writer,false),
    'change_control_locked',coalesce(v_locks,false),
    'sheet_outbox_clean',coalesce(v_outbox,false),
    'sheet_failed',coalesce(v_failed,0),
    'sheet_dead',coalesce(v_dead,0),
    'sheet_stale',coalesce(v_stale,0),
    'anon_public_security_definer',coalesce(v_sensitive,0)
  );
  v_healthy:=coalesce(v_routes,false) and coalesce(v_writer,false) and coalesce(v_locks,false) and coalesce(v_outbox,false) and coalesce(v_sensitive,0)=0;

  insert into private.production_health_state(id,healthy,checks,checked_at)
  values(1,v_healthy,v_checks,now())
  on conflict(id) do update set healthy=excluded.healthy,checks=excluded.checks,checked_at=excluded.checked_at;
  return jsonb_build_object('healthy',v_healthy,'checks',v_checks,'checked_at',now());
end $$;
revoke all on function private.refresh_production_health_state() from public, anon, authenticated, service_role;
grant execute on function private.refresh_production_health_state() to postgres;

select cron.unschedule(jobid) from cron.job where jobname='rohmat_production_health_monitor';
select cron.schedule('rohmat_production_health_monitor','*/10 * * * *','select private.refresh_production_health_state();');

select private.refresh_production_health_state();
