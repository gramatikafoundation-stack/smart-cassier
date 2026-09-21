-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912121320  Name: frontend_performance_health_gate_v2
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.frontend_performance_summary()
returns jsonb language sql stable security definer set search_path='' as $$
with latest as (
 select distinct on(service_key) service_key,status_code,latency_ms,payload_bytes,cache_control,measured_at
 from private.frontend_performance_samples order by service_key,measured_at desc
), a as (
 select count(*) filter(where image_url like 'http://127.0.0.1:54321/storage/v1/object/public/rohmat-assets/menu-cache/%') direct_storage,
 count(*) filter(where image_url like '%/functions/v1/rohmat-menu-photo%') proxy_urls,
 count(*) total_images from public.menu_items where coalesce(image_url,'')<>''
), s as (
 select count(*) cached_objects,count(*) filter(where metadata->>'cacheControl' like '%31536000%') year_cache
 from storage.objects where bucket_id='rohmat-assets' and name like 'menu-cache/%'
), m as (
 select coalesce(jsonb_object_agg(service_key,jsonb_build_object('status',status_code,'latency_ms',latency_ms,'payload_bytes',payload_bytes,'cache_control',cache_control,'measured_at',measured_at)),'{}'::jsonb) metrics,
 count(*) count_services,
 count(*) filter(where measured_at>now()-interval '15 minutes') fresh_services,
 count(*) filter(where status_code between 200 and 399) healthy_services,
 count(*) filter(where latency_ms<=5000) latency_budget_ok,
 count(*) filter(where (service_key='public_web' and payload_bytes<=100000) or (service_key='admin_web' and payload_bytes<=100000) or (service_key='kds_web' and payload_bytes<=10000)) payload_budget_ok
 from latest
)
select jsonb_build_object(
 'ok', a.proxy_urls=0 and a.direct_storage=a.total_images and a.total_images=36 and s.cached_objects=36 and s.year_cache=36 and m.count_services=3 and m.fresh_services=3 and m.healthy_services=3 and m.latency_budget_ok=3 and m.payload_budget_ok=3,
 'menu_images',jsonb_build_object('total',a.total_images,'direct_storage',a.direct_storage,'proxy_urls',a.proxy_urls,'cached_objects',s.cached_objects,'year_cache',s.year_cache),
 'budgets',jsonb_build_object('fresh_services',m.fresh_services,'healthy_services',m.healthy_services,'latency_budget_ok',m.latency_budget_ok,'payload_budget_ok',m.payload_budget_ok,'expected_services',3,'max_latency_ms',5000,'public_max_bytes',100000,'admin_max_bytes',100000,'kds_login_max_bytes',10000),
 'latest',m.metrics
) from a,s,m;
$$;
revoke all on function private.frontend_performance_summary() from public,anon,authenticated;

create or replace function private.refresh_production_health_state()
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_routes boolean; v_writer boolean; v_locks boolean; v_outbox boolean; v_failed bigint; v_dead bigint; v_stale bigint; v_sensitive bigint;
  v_checks jsonb; v_healthy boolean; v_integration jsonb; v_integration_ok boolean; v_consistency jsonb; v_consistency_ok boolean;
  v_reliability jsonb; v_reliability_ok boolean; v_performance jsonb; v_performance_ok boolean;
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
  v_performance:=private.frontend_performance_summary(); v_performance_ok:=coalesce((v_performance->>'ok')::boolean,false);
  v_checks:=jsonb_build_object('canonical_routes',coalesce(v_routes,false),'writer_enabled',coalesce(v_writer,false),'change_control_locked',coalesce(v_locks,false),'sheet_outbox_clean',coalesce(v_outbox,false),'sheet_failed',coalesce(v_failed,0),'sheet_dead',coalesce(v_dead,0),'sheet_stale',coalesce(v_stale,0),'sheet_consistency',v_consistency,'sheet_consistency_ok',v_consistency_ok,'anon_public_security_definer',coalesce(v_sensitive,0),'integration_contracts',v_integration,'integration_contracts_ok',v_integration_ok,'reliability',v_reliability,'reliability_ok',v_reliability_ok,'frontend_performance',v_performance,'frontend_performance_ok',v_performance_ok);
  v_healthy:=coalesce(v_routes,false) and coalesce(v_writer,false) and coalesce(v_locks,false) and coalesce(v_outbox,false) and coalesce(v_sensitive,0)=0 and v_integration_ok and v_consistency_ok and v_reliability_ok and v_performance_ok;
  insert into private.production_health_state(id,healthy,checks,checked_at) values(1,v_healthy,v_checks,now()) on conflict(id) do update set healthy=excluded.healthy,checks=excluded.checks,checked_at=excluded.checked_at;
  return jsonb_build_object('healthy',v_healthy,'checks',v_checks,'checked_at',now());
end$$;
revoke all on function private.refresh_production_health_state() from public,anon,authenticated;

