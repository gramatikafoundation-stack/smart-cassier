-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912165559  Name: frontend_ux_functional_accuracy_contract_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.frontend_ux_contract_status()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_visible bigint; v_invalid_menu bigint; v_missing_image bigint; v_invalid_service bigint; v_active_admin bigint;
  v_qris boolean; v_qris_image text; v_merchant text; v_signed boolean; v_pub text; v_adm text; v_kds text;
  v_routes boolean; v_qris_ok boolean; v_table_mode_ok boolean; v_ok boolean;
begin
  select s.qris_enabled,s.qris_image_url,s.merchant_name,s.require_table_qr_signature,s.public_url,s.admin_url,s.kds_url
  into v_qris,v_qris_image,v_merchant,v_signed,v_pub,v_adm,v_kds
  from public.site_settings s where s.id=1;

  select count(*) filter(where m.is_visible),
         count(*) filter(where m.is_visible and (nullif(trim(m.name),'') is null or nullif(trim(m.category),'') is null or m.price is null or m.price<0)),
         count(*) filter(where m.is_visible and (m.image_url is null or nullif(trim(m.image_url),'') is null))
    into v_visible,v_invalid_menu,v_missing_image
  from public.menu_items m;

  select count(*) into v_invalid_service
  from public.orders o
  where (o.service_mode='dine-in' and (o.table_number is null or o.table_number not between 1 and 20))
     or (o.service_mode='take-away' and o.table_number is not null);

  select count(*) into v_active_admin from public.admin_users a where a.is_active;

  v_routes := coalesce(v_pub,'')='https://rohmat-pesan-bayar-publik.vercel.app/'
          and coalesce(v_adm,'')='https://studio-pengelola-rohmat.vercel.app'
          and coalesce(v_kds,'')='https://rohmat-kds-printer.vercel.app';
  v_qris_ok := not coalesce(v_qris,false) or (nullif(trim(coalesce(v_qris_image,'')),'') is not null and nullif(trim(coalesce(v_merchant,'')),'') is not null);
  -- Current public production intentionally operates in manual/trial table selection mode.
  -- If signed-table enforcement is enabled before the static public client is migrated, health must fail.
  v_table_mode_ok := not coalesce(v_signed,false);
  v_ok := coalesce(v_visible,0)>0 and coalesce(v_invalid_menu,0)=0 and coalesce(v_missing_image,0)=0
       and coalesce(v_invalid_service,0)=0 and coalesce(v_active_admin,0)>0 and v_routes and v_qris_ok and v_table_mode_ok;

  return jsonb_build_object(
    'ok',v_ok,
    'canonical_navigation_targets',v_routes,
    'visible_menu',coalesce(v_visible,0),
    'invalid_visible_menu',coalesce(v_invalid_menu,0),
    'visible_menu_missing_image',coalesce(v_missing_image,0),
    'invalid_service_table_orders',coalesce(v_invalid_service,0),
    'qris_configuration_ok',v_qris_ok,
    'manual_table_trial_mode_ok',v_table_mode_ok,
    'active_admins',coalesce(v_active_admin,0),
    'expected_public_ux_runtime','public-v17',
    'expected_admin_ux_runtime','admin-v48'
  );
end$$;
revoke all on function private.frontend_ux_contract_status() from public,anon,authenticated;

create or replace function private.refresh_production_health_state()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_routes boolean; v_writer boolean; v_locks boolean; v_outbox boolean; v_failed bigint; v_dead bigint; v_stale bigint; v_sensitive bigint;
  v_checks jsonb; v_healthy boolean; v_integration jsonb; v_integration_ok boolean; v_consistency jsonb; v_consistency_ok boolean;
  v_reliability jsonb; v_reliability_ok boolean; v_performance jsonb; v_performance_ok boolean; v_ux jsonb; v_ux_ok boolean;
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
  v_ux:=private.frontend_ux_contract_status(); v_ux_ok:=coalesce((v_ux->>'ok')::boolean,false);
  v_checks:=jsonb_build_object('canonical_routes',coalesce(v_routes,false),'writer_enabled',coalesce(v_writer,false),'change_control_locked',coalesce(v_locks,false),'sheet_outbox_clean',coalesce(v_outbox,false),'sheet_failed',coalesce(v_failed,0),'sheet_dead',coalesce(v_dead,0),'sheet_stale',coalesce(v_stale,0),'sheet_consistency',v_consistency,'sheet_consistency_ok',v_consistency_ok,'anon_public_security_definer',coalesce(v_sensitive,0),'integration_contracts',v_integration,'integration_contracts_ok',v_integration_ok,'reliability',v_reliability,'reliability_ok',v_reliability_ok,'frontend_performance',v_performance,'frontend_performance_ok',v_performance_ok,'frontend_ux',v_ux,'frontend_ux_ok',v_ux_ok);
  v_healthy:=coalesce(v_routes,false) and coalesce(v_writer,false) and coalesce(v_locks,false) and coalesce(v_outbox,false) and coalesce(v_sensitive,0)=0 and v_integration_ok and v_consistency_ok and v_reliability_ok and v_performance_ok and v_ux_ok;
  insert into private.production_health_state(id,healthy,checks,checked_at) values(1,v_healthy,v_checks,now()) on conflict(id) do update set healthy=excluded.healthy,checks=excluded.checks,checked_at=excluded.checked_at;
  return jsonb_build_object('healthy',v_healthy,'checks',v_checks,'checked_at',now());
end$$;
