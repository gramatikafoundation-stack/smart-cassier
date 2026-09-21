-- ADMIN Batch 1: Stability, Canonicalization & Security Foundation
-- Scope: release-control metadata and integration-contract validation only.
-- No business data, menu, order, auth policy, or UI layout changes.

create or replace function private.integration_contract_status()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_public text; v_admin text; v_kds text; v_writer text;
  v_registry_ok boolean; v_routes_ok boolean;
  v_legacy_worker boolean; v_drain_worker boolean; v_cron_worker boolean;
  v_reconcile_cron boolean; v_health_cron boolean;
  v_corr_orders boolean; v_corr_outbox boolean; v_corr_events boolean;
  v_critical_count integer; v_expected integer:=9;
begin
  select public_url,admin_url,kds_url
    into v_public,v_admin,v_kds
  from public.site_settings where id=1;

  select writer_url into v_writer
  from public.sheet_sync_config where id=1;

  select count(*) into v_critical_count
  from private.integration_registry
  where critical and enabled and canonical_url<>'' and contract_version<>'';

  v_registry_ok := v_critical_count=v_expected;

  v_routes_ok :=
    exists(select 1 from private.integration_registry where service_key='public_web' and rtrim(canonical_url,'/')=rtrim(v_public,'/')) and
    exists(select 1 from private.integration_registry where service_key='admin_web' and rtrim(canonical_url,'/')=rtrim(v_admin,'/')) and
    exists(select 1 from private.integration_registry where service_key='kds_web' and rtrim(canonical_url,'/')=rtrim(v_kds,'/')) and
    exists(select 1 from private.integration_registry where service_key='sheet_writer' and canonical_url=v_writer);

  select exists(
    select 1 from cron.job
    where jobname='rohmat_sheet_sync_worker'
      and active
  ) into v_legacy_worker;

  select exists(
    select 1 from cron.job
    where jobname='rohmat-sheet-sync-drain-10s'
      and active
      and schedule ~ '^[1-5]?[0-9] seconds$'
      and command ilike '%private.invoke_sheet_sync_worker()%'
  ) into v_drain_worker;

  v_cron_worker := v_legacy_worker or v_drain_worker;

  select exists(
    select 1 from cron.job
    where jobname='rohmat_sheet_sync_reconcile'
      and active
      and command ilike '%private.enqueue_sheet_reconciliation()%'
  ) into v_reconcile_cron;

  select exists(
    select 1 from cron.job
    where jobname='rohmat_production_health_monitor'
      and active
  ) into v_health_cron;

  select exists(
    select 1
    from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid=a.attrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='orders'
      and a.attname='request_id' and not a.attisdropped
  ) into v_corr_orders;

  select exists(
    select 1
    from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid=a.attrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='sheet_sync_outbox'
      and a.attname='request_id' and not a.attisdropped
  ) into v_corr_outbox;

  select exists(
    select 1
    from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid=a.attrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='order_events'
      and a.attname='request_id' and not a.attisdropped
  ) into v_corr_events;

  return jsonb_build_object(
    'ok',v_registry_ok and v_routes_ok and v_cron_worker and v_reconcile_cron
         and v_health_cron and v_corr_orders and v_corr_outbox and v_corr_events,
    'registry_ok',v_registry_ok,
    'critical_services',v_critical_count,
    'expected_services',v_expected,
    'canonical_routes_ok',v_routes_ok,
    'sheet_worker_cron',v_cron_worker,
    'sheet_worker_mode',case when v_drain_worker then 'subminute-drain'
                             when v_legacy_worker then 'legacy-cron'
                             else 'missing' end,
    'sheet_drain_cron',v_drain_worker,
    'sheet_reconcile_cron',v_reconcile_cron,
    'health_cron',v_health_cron,
    'orders_request_id',v_corr_orders,
    'outbox_request_id',v_corr_outbox,
    'order_events_request_id',v_corr_events
  );
end
$function$;

with desired(component_key,expected_version,expected_sha256,deployment_ref) as (
  values
    ('admin_cashier_loader','v30','f0776472af2421aaed42e033e1fdc078c6a406b32a0c0b74ccd359ad2bc5bb01','edge-version:v30'),
    ('admin_database_ui','v15','951d8b1163984d58bd037ff76b63ce74c15280ffbb14b5be3fdd8cfab658f493','edge-version:v15'),
    ('admin_kds_ui','v11','9e78c46646070d4b533bf4bcc61b49e6ec414417304614507e987b1918b18b8f','edge-version:v11'),
    ('admin_runtime','v54','1d23889673b38233d83a4ad28e3bf97b8ee4d17a5d04e48c19b1fe9430b342b5','edge-version:v54'),
    ('admin_visual_editor','v18','3211d4db72ce8f9699baa17b86ea53934e56e13a930eaab97765dea18f021662','edge-version:v18'),
    ('secure_api','v11','362c992053056dc319d5667771fdecb542ce5c82f64a5adef23c6c470480cb97','edge-version:v11'),
    ('sheet_dispatch','v3','e758bfb7cc4fd75e4fba0d31cb91060ad09f9a4565fc9364d93c0dc32f426c7e','edge-version:v3'),
    ('sheet_worker','v10','4c30fd1ffd6128f4a9ffbf85ad01037700f534120e14442638d1515a3d8d4667','edge-version:v10')
)
update private.release_component_registry r
set expected_version=d.expected_version,
    expected_sha256=d.expected_sha256,
    deployment_ref=d.deployment_ref,
    last_verified_at=now(),
    notes=coalesce(r.notes,'') ||
      case when coalesce(r.notes,'')='' then '' else ' ' end ||
      'Canonicalized to the active production artifact during ADMIN Batch 1 on 2026-09-18; existing rollback reference retained.'
from desired d
where r.component_key=d.component_key;

with desired(component,baseline_version,baseline_sha256,canonical_target) as (
  values
    ('admin-cashier-loader','v30','f0776472af2421aaed42e033e1fdc078c6a406b32a0c0b74ccd359ad2bc5bb01','rohmat-admin-cashier-loader-v1'),
    ('admin-database-ui','v15','951d8b1163984d58bd037ff76b63ce74c15280ffbb14b5be3fdd8cfab658f493','rohmat-admin-database-ui-v1'),
    ('admin-kds-ui','v11','9e78c46646070d4b533bf4bcc61b49e6ec414417304614507e987b1918b18b8f','rohmat-admin-kds-ui-v1'),
    ('admin-runtime','v54','1d23889673b38233d83a4ad28e3bf97b8ee4d17a5d04e48c19b1fe9430b342b5','rohmat-admin-style-runtime-v59'),
    ('admin-visual-editor','v18','3211d4db72ce8f9699baa17b86ea53934e56e13a930eaab97765dea18f021662','rohmat-admin-visual-editor-v1'),
    ('secure-api','v11','362c992053056dc319d5667771fdecb542ce5c82f64a5adef23c6c470480cb97','rohmat-secure-api-v1'),
    ('sheet-dispatch','v3','e758bfb7cc4fd75e4fba0d31cb91060ad09f9a4565fc9364d93c0dc32f426c7e','rohmat-sheet-sync-dispatch-v1'),
    ('sheets-worker','v10','4c30fd1ffd6128f4a9ffbf85ad01037700f534120e14442638d1515a3d8d4667','rohmat-sheet-sync-worker-v1')
)
update private.production_change_control c
set baseline_version=d.baseline_version,
    baseline_sha256=d.baseline_sha256,
    canonical_target=d.canonical_target,
    updated_at=now()
from desired d
where c.component=d.component;

update private.release_component_registry
set expected_version='dpl_DMJ47Ry2N1nMMShzhFXmU5STAL53',
    deployment_ref='dpl_DMJ47Ry2N1nMMShzhFXmU5STAL53',
    rollback_ref='vercel:dpl_BLvG6kGuskbENMy3LzMFvNDvgbPN',
    last_verified_at=now(),
    notes='Current immutable Vercel production deployment verified during ADMIN Batch 1 on 2026-09-18; previous production deployment retained as rollback candidate.'
where component_key='admin_site';

update private.production_change_control
set baseline_version='dpl_DMJ47Ry2N1nMMShzhFXmU5STAL53',
    baseline_sha256=null,
    canonical_target='https://studio-pengelola-rohmat.vercel.app',
    updated_at=now()
where component='admin-site';
