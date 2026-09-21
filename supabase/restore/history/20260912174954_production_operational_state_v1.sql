-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912174954  Name: production_operational_state_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table private.production_health_state add column if not exists operational_state text not null default 'unknown';
do $$ begin
  alter table private.production_health_state add constraint production_health_state_operational_state_chk check(operational_state in ('healthy','degraded','critical','unknown'));
exception when duplicate_object then null; end $$;

create or replace function private.refresh_production_health_state()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_routes boolean; v_writer boolean; v_locks boolean; v_outbox boolean; v_failed bigint; v_dead bigint; v_stale bigint; v_sensitive bigint;
  v_checks jsonb; v_healthy boolean; v_state text; v_integration jsonb; v_integration_ok boolean; v_consistency jsonb; v_consistency_ok boolean;
  v_reliability jsonb; v_reliability_ok boolean; v_reliability_state text; v_performance jsonb; v_performance_ok boolean; v_ux jsonb; v_ux_ok boolean; v_maint jsonb; v_maint_ok boolean;
begin
  select (public_url='https://rohmat-pesan-bayar-publik.vercel.app/' and admin_url='https://studio-pengelola-rohmat.vercel.app' and kds_url='https://rohmat-kds-printer.vercel.app') into v_routes from public.site_settings where id=1;
  select coalesce(enabled,false) and coalesce(writer_url,'') like 'https://script.google.com/macros/s/%/exec' into v_writer from public.sheet_sync_config where id=1;
  select coalesce(bool_and(locked),false) into v_locks from private.production_change_control;
  select count(*) filter(where status='failed'),count(*) filter(where status='dead'),count(*) filter(where status in ('pending','processing') and created_at<now()-interval '5 minutes') into v_failed,v_dead,v_stale from public.sheet_sync_outbox;
  v_outbox:=(v_failed=0 and v_dead=0 and v_stale=0);
  select count(*) into v_sensitive from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE');
  v_integration:=private.integration_contract_status(); v_integration_ok:=coalesce((v_integration->>'ok')::boolean,false);
  v_consistency:=private.sheet_sync_consistency_summary(); v_consistency_ok:=coalesce((v_consistency->>'ok')::boolean,false);
  v_reliability:=private.reliability_status(); v_reliability_ok:=coalesce((v_reliability->>'ok')::boolean,false); v_reliability_state:=coalesce(v_reliability->>'state','degraded');
  v_performance:=private.frontend_performance_summary(); v_performance_ok:=coalesce((v_performance->>'ok')::boolean,false);
  v_ux:=private.frontend_ux_contract_status(); v_ux_ok:=coalesce((v_ux->>'ok')::boolean,false);
  v_maint:=private.release_engineering_status(); v_maint_ok:=coalesce((v_maint->>'ok')::boolean,false);
  v_checks:=jsonb_build_object('canonical_routes',coalesce(v_routes,false),'writer_enabled',coalesce(v_writer,false),'change_control_locked',coalesce(v_locks,false),'sheet_outbox_clean',coalesce(v_outbox,false),'sheet_failed',coalesce(v_failed,0),'sheet_dead',coalesce(v_dead,0),'sheet_stale',coalesce(v_stale,0),'sheet_consistency',v_consistency,'sheet_consistency_ok',v_consistency_ok,'anon_public_security_definer',coalesce(v_sensitive,0),'integration_contracts',v_integration,'integration_contracts_ok',v_integration_ok,'reliability',v_reliability,'reliability_ok',v_reliability_ok,'frontend_performance',v_performance,'frontend_performance_ok',v_performance_ok,'frontend_ux',v_ux,'frontend_ux_ok',v_ux_ok,'maintainability',v_maint,'maintainability_ok',v_maint_ok);
  v_healthy:=coalesce(v_routes,false) and coalesce(v_writer,false) and coalesce(v_locks,false) and coalesce(v_outbox,false) and coalesce(v_sensitive,0)=0 and v_integration_ok and v_consistency_ok and v_reliability_ok and v_performance_ok and v_ux_ok and v_maint_ok;
  v_state:=case
    when v_healthy then 'healthy'
    when v_reliability_state='critical' or coalesce(v_dead,0)>0 or current_setting('transaction_read_only')='on' then 'critical'
    else 'degraded'
  end;
  insert into private.production_health_state(id,healthy,operational_state,checks,checked_at) values(1,v_healthy,v_state,v_checks,now())
  on conflict(id) do update set healthy=excluded.healthy,operational_state=excluded.operational_state,checks=excluded.checks,checked_at=excluded.checked_at;
  return jsonb_build_object('healthy',v_healthy,'state',v_state,'checks',v_checks,'checked_at',now());
end;
$$;
revoke all on function private.refresh_production_health_state() from public,anon,authenticated;
grant execute on function private.refresh_production_health_state() to service_role;
