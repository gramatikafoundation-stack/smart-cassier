-- SMART ORDER Golden Master v12 hardening: tenant-aware health/readiness + KDS durable handover idempotency.
-- Scope: no pricing/auth/role/payment semantic changes. Existing manual reprint action remains available.

create unique index if not exists order_events_kds_completion_once_uidx
  on public.order_events(order_id,event_type)
  where event_type='kds_completed';

create unique index if not exists order_events_kds_auto_print_once_uidx
  on public.order_events(order_id,event_type)
  where event_type in ('kds_auto_print_claimed','kds_auto_print_dispatched');

create or replace function private.integration_contract_status()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_tenant uuid:=private.reference_tenant_id();
  v_public text; v_admin text; v_kds text; v_database text;
  v_writer_enabled boolean; v_writer text; v_writer_secret uuid; v_writer_targets integer;
  v_registry_ok boolean; v_routes_ok boolean; v_writer_ok boolean; v_writer_template_ok boolean;
  v_legacy_worker boolean; v_drain_worker boolean; v_cron_worker boolean;
  v_reconcile_cron boolean; v_health_cron boolean;
  v_corr_orders boolean; v_corr_outbox boolean; v_corr_events boolean;
  v_critical_count integer; v_expected integer:=9;
begin
  select public_url,admin_url,kds_url into v_public,v_admin,v_kds
  from public.site_settings where id=1;

  select settings->>'database_url' into v_database
  from private.tenant_runtime_config where tenant_id=v_tenant;

  select coalesce(enabled,false),writer_url,writer_secret_id
    into v_writer_enabled,v_writer,v_writer_secret
  from private.tenant_writer_config where tenant_id=v_tenant;

  select count(*) into v_writer_targets
  from private.tenant_sheet_targets
  where tenant_id=v_tenant and enabled;

  select count(*) into v_critical_count
  from private.integration_registry
  where critical and enabled and canonical_url<>'' and contract_version<>'';

  v_registry_ok:=v_critical_count=v_expected
    and not exists(
      select 1 from unnest(array[
        'admin_web','database_web','kds_api','kds_web','order_gateway',
        'postgres_core','public_web','sheet_worker','smart_cashier'
      ]) req(service_key)
      where not exists(
        select 1 from private.integration_registry r
        where r.service_key=req.service_key
          and r.critical and r.enabled
          and coalesce(r.canonical_url,'')<>''
          and coalesce(r.contract_version,'')<>''
      )
    );

  select exists(
    select 1 from private.integration_registry
    where service_key='sheet_writer'
      and coalesce(metadata->>'tenant_aware','false')='true'
      and coalesce(canonical_url,'')<>''
      and coalesce(contract_version,'')<>''
  ) into v_writer_template_ok;

  v_writer_ok:=case when v_writer_enabled then
    coalesce(v_writer,'') like 'https://%'
    and v_writer_secret is not null
    and exists(select 1 from vault.secrets where id=v_writer_secret)
    and v_writer_targets>0
    and v_writer_template_ok
  else
    exists(
      select 1 from private.integration_registry
      where service_key='sheet_writer'
        and not enabled and not critical
        and canonical_url='provision://google-sheets-writer-v4'
        and coalesce(metadata->>'tenant_aware','false')='true'
    )
  end;

  v_routes_ok:=
    exists(select 1 from private.integration_registry where service_key='public_web' and enabled and rtrim(canonical_url,'/')=rtrim(v_public,'/'))
    and exists(select 1 from private.integration_registry where service_key='admin_web' and enabled and rtrim(canonical_url,'/')=rtrim(v_admin,'/'))
    and exists(select 1 from private.integration_registry where service_key='kds_web' and enabled and rtrim(canonical_url,'/')=rtrim(v_kds,'/'))
    and exists(select 1 from private.integration_registry where service_key='database_web' and enabled and rtrim(canonical_url,'/')=rtrim(v_database,'/'));

  select exists(select 1 from cron.job where jobname='rohmat_sheet_sync_worker' and active)
    into v_legacy_worker;
  select exists(
    select 1 from cron.job
    where jobname='rohmat-sheet-sync-drain-10s' and active
      and schedule ~ '^[1-5]?[0-9] seconds$'
      and command ilike '%private.invoke_sheet_sync_worker()%'
  ) into v_drain_worker;
  v_cron_worker:=v_legacy_worker or v_drain_worker;

  select exists(
    select 1 from cron.job where jobname='rohmat_sheet_sync_reconcile' and active
      and command ilike '%private.enqueue_sheet_reconciliation()%'
  ) into v_reconcile_cron;
  select exists(select 1 from cron.job where jobname='rohmat_production_health_monitor' and active)
    into v_health_cron;

  select exists(
    select 1 from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid=a.attrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='orders' and a.attname='request_id' and not a.attisdropped
  ) into v_corr_orders;
  select exists(
    select 1 from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid=a.attrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='sheet_sync_outbox' and a.attname='request_id' and not a.attisdropped
  ) into v_corr_outbox;
  select exists(
    select 1 from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid=a.attrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='order_events' and a.attname='request_id' and not a.attisdropped
  ) into v_corr_events;

  return jsonb_build_object(
    'ok',v_registry_ok and v_routes_ok and v_writer_ok and v_cron_worker and v_reconcile_cron
      and v_health_cron and v_corr_orders and v_corr_outbox and v_corr_events,
    'registry_ok',v_registry_ok,
    'critical_services',v_critical_count,
    'expected_services',v_expected,
    'canonical_four_surface_routes_ok',v_routes_ok,
    'sheet_writer_mode',case when v_writer_enabled then 'live_sync' else 'prototype_template' end,
    'sheet_writer_contract_ok',v_writer_ok,
    'sheet_writer_template_contract_ok',v_writer_template_ok,
    'sheet_writer_target_count',v_writer_targets,
    'sheet_worker_cron',v_cron_worker,
    'sheet_worker_mode',case when v_drain_worker then 'subminute-drain' when v_legacy_worker then 'legacy-cron' else 'missing' end,
    'sheet_drain_cron',v_drain_worker,
    'sheet_reconcile_cron',v_reconcile_cron,
    'health_cron',v_health_cron,
    'orders_request_id',v_corr_orders,
    'outbox_request_id',v_corr_outbox,
    'order_events_request_id',v_corr_events
  );
end
$function$;

create or replace function private.sheet_sync_consistency_summary()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_tenant uuid:=private.reference_tenant_id();
  active_count integer;
  checked_count integer;
  good_count integer;
  bad_count integer;
  stale_count integer;
  advanced_count integer;
  mins integer:=60;
  win integer:=75;
  actual_schedule text;
  cadence_ok boolean:=false;
begin
  select count(*)::integer into active_count
  from private.tenant_sheet_targets
  where tenant_id=v_tenant and enabled;

  select schedule into actual_schedule
  from cron.job
  where jobname='rohmat_sheet_sync_reconcile' and active
  limit 1;

  if actual_schedule='17 * * * *' then
    mins:=60;
    win:=75;
    cadence_ok:=true;
  elsif actual_schedule ~ '^[0-9,*/-]+ \* \* \* \*$' then
    -- Compatibility for prior minute-based schedules; use the configured legacy interval only as a cadence hint.
    select greatest(5,least(60,coalesce(reconciliation_minutes,10))) into mins
    from public.sheet_sync_config where id=1;
    mins:=coalesce(mins,10);
    win:=greatest(35,mins*3+5);
    cadence_ok:=true;
  end if;

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
$function$;

create or replace function private.smart_order_sheet_readiness_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_enabled boolean:=false; v_url text; v_secret uuid;
  v_targets integer; v_checked integer; v_consistent integer; v_fresh integer;
  v_pending bigint; v_processing bigint; v_failed bigint; v_dead bigint; v_superseded bigint;
  v_registry_template boolean; v_registry_contract boolean; v_ok boolean; v_mode text;
  v_schedule text; v_fresh_minutes integer:=75;
begin
  select coalesce(enabled,false),writer_url,writer_secret_id
    into v_enabled,v_url,v_secret
  from private.tenant_writer_config where tenant_id=p_tenant_id;

  select schedule into v_schedule
  from cron.job where jobname='rohmat_sheet_sync_reconcile' and active limit 1;
  if v_schedule is distinct from '17 * * * *' then
    v_fresh_minutes:=95;
  end if;

  select count(*) into v_targets
  from private.tenant_sheet_targets where tenant_id=p_tenant_id and enabled;

  select count(*),
         count(*) filter(where consistent),
         count(*) filter(where consistent and checked_at>now()-make_interval(mins=>v_fresh_minutes))
    into v_checked,v_consistent,v_fresh
  from private.sheet_sync_consistency_state
  where tenant_id=p_tenant_id;

  select count(*) filter(where status='pending'),
         count(*) filter(where status='processing'),
         count(*) filter(where status='failed'),
         count(*) filter(where status='dead'),
         count(*) filter(where status='superseded')
    into v_pending,v_processing,v_failed,v_dead,v_superseded
  from public.sheet_sync_outbox where tenant_id=p_tenant_id;

  select exists(
    select 1 from private.integration_registry
    where service_key='sheet_writer'
      and not enabled and not critical
      and canonical_url='provision://google-sheets-writer-v4'
  ) into v_registry_template;

  select exists(
    select 1 from private.integration_registry
    where service_key='sheet_writer'
      and coalesce(metadata->>'tenant_aware','false')='true'
      and coalesce(contract_version,'')<>''
  ) into v_registry_contract;

  if v_enabled then
    v_mode:='live_sync';
    v_ok:=coalesce(v_url,'') like 'https://%'
      and v_secret is not null
      and exists(select 1 from vault.secrets where id=v_secret)
      and v_targets=5 and v_checked=5 and v_consistent=5 and v_fresh=5
      and v_pending=0 and v_processing=0 and v_failed=0 and v_dead=0
      and v_registry_contract;
  else
    v_mode:='prototype_template';
    v_ok:=v_targets=5 and v_pending=0 and v_processing=0 and v_failed=0 and v_dead=0
      and v_registry_template and v_registry_contract;
  end if;

  return jsonb_build_object(
    'ok',v_ok,
    'tenant_id',p_tenant_id,
    'mode',v_mode,
    'writer_enabled',v_enabled,
    'writer_url_https',coalesce(v_url,'') like 'https://%',
    'writer_secret_configured',v_secret is not null,
    'writer_contract_tenant_aware',v_registry_contract,
    'active_targets',v_targets,
    'checked_targets',v_checked,
    'consistent_targets',v_consistent,
    'fresh_consistent_targets',v_fresh,
    'freshness_window_minutes',v_fresh_minutes,
    'queue',jsonb_build_object(
      'pending',v_pending,'processing',v_processing,'failed',v_failed,'dead',v_dead,'superseded',v_superseded
    ),
    'reconciliation_required_on_provision',not v_enabled and v_superseded>0,
    'activation_contract',case when v_enabled then null else jsonb_build_array(
      'configure tenant writer HTTPS URL',
      'configure writer secret',
      'enable writer',
      'enqueue full reconciliation',
      'verify 5/5 consistency'
    ) end
  );
end
$function$;

create or replace function private.refresh_production_health_state()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_tenant uuid:=private.reference_tenant_id();
  v_routes boolean; v_writer boolean; v_locks boolean; v_outbox boolean;
  v_failed bigint; v_dead bigint; v_stale bigint; v_sensitive bigint;
  v_checks jsonb; v_healthy boolean; v_state text;
  v_integration jsonb; v_integration_ok boolean;
  v_consistency jsonb; v_consistency_ok boolean;
  v_reliability jsonb; v_reliability_ok boolean; v_reliability_state text;
  v_performance jsonb; v_performance_ok boolean;
  v_ux jsonb; v_ux_ok boolean;
  v_maint jsonb; v_maint_ok boolean;
begin
  select (
    rtrim(public_url,'/')=rtrim((select public_origin from private.tenant_runtime_config where tenant_id=v_tenant),'/')
    and rtrim(admin_url,'/')=rtrim((select case when admin_origin=public_origin then rtrim(admin_origin,'/')||'/admin' else admin_origin end from private.tenant_runtime_config where tenant_id=v_tenant),'/')
    and rtrim(kds_url,'/')=rtrim((select case when kds_origin=public_origin then rtrim(kds_origin,'/')||'/kds' else kds_origin end from private.tenant_runtime_config where tenant_id=v_tenant),'/')
  ) into v_routes from public.site_settings where id=1;

  select coalesce(w.enabled,false)
      and coalesce(w.writer_url,'') like 'https://%'
      and w.writer_secret_id is not null
      and exists(select 1 from vault.secrets s where s.id=w.writer_secret_id)
      and exists(select 1 from private.tenant_sheet_targets t where t.tenant_id=w.tenant_id and t.enabled)
    into v_writer
  from private.tenant_writer_config w
  where w.tenant_id=v_tenant;

  select coalesce(bool_and(locked),false) into v_locks
  from private.production_change_control;

  select count(*) filter(where status='failed'),
         count(*) filter(where status='dead'),
         count(*) filter(where status in ('pending','processing') and created_at<now()-interval '5 minutes')
    into v_failed,v_dead,v_stale
  from public.sheet_sync_outbox
  where tenant_id=v_tenant;

  v_outbox:=(v_failed=0 and v_dead=0 and v_stale=0);

  select count(*) into v_sensitive
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef
    and pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE');

  v_integration:=private.integration_contract_status();
  v_integration_ok:=coalesce((v_integration->>'ok')::boolean,false);
  v_consistency:=private.sheet_sync_consistency_summary();
  v_consistency_ok:=coalesce((v_consistency->>'ok')::boolean,false);
  v_reliability:=private.reliability_status();
  v_reliability_ok:=coalesce((v_reliability->>'ok')::boolean,false);
  v_reliability_state:=coalesce(v_reliability->>'state','degraded');
  v_performance:=private.frontend_performance_summary();
  v_performance_ok:=coalesce((v_performance->>'ok')::boolean,false);
  v_ux:=private.frontend_ux_contract_status();
  v_ux_ok:=coalesce((v_ux->>'ok')::boolean,false);
  v_maint:=private.release_engineering_status();
  v_maint_ok:=coalesce((v_maint->>'ok')::boolean,false);

  v_checks:=jsonb_build_object(
    'canonical_routes',coalesce(v_routes,false),
    'writer_enabled',coalesce(v_writer,false),
    'writer_contract_source','private.tenant_writer_config',
    'change_control_locked',coalesce(v_locks,false),
    'sheet_outbox_clean',coalesce(v_outbox,false),
    'sheet_failed',coalesce(v_failed,0),
    'sheet_dead',coalesce(v_dead,0),
    'sheet_stale',coalesce(v_stale,0),
    'sheet_consistency',v_consistency,
    'sheet_consistency_ok',v_consistency_ok,
    'anon_public_security_definer',coalesce(v_sensitive,0),
    'integration_contracts',v_integration,
    'integration_contracts_ok',v_integration_ok,
    'reliability',v_reliability,
    'reliability_ok',v_reliability_ok,
    'frontend_performance',v_performance,
    'frontend_performance_ok',v_performance_ok,
    'frontend_ux',v_ux,
    'frontend_ux_ok',v_ux_ok,
    'maintainability',v_maint,
    'maintainability_ok',v_maint_ok
  );

  v_healthy:=coalesce(v_routes,false)
    and coalesce(v_writer,false)
    and coalesce(v_locks,false)
    and coalesce(v_outbox,false)
    and coalesce(v_sensitive,0)=0
    and v_integration_ok
    and v_consistency_ok
    and v_reliability_ok
    and v_performance_ok
    and v_ux_ok
    and v_maint_ok;

  v_state:=case
    when v_healthy then 'healthy'
    when v_reliability_state='critical' or coalesce(v_dead,0)>0 or current_setting('transaction_read_only')='on' then 'critical'
    else 'degraded'
  end;

  insert into private.production_health_state(id,healthy,operational_state,checks,checked_at)
  values(1,v_healthy,v_state,v_checks,now())
  on conflict(id) do update set
    healthy=excluded.healthy,
    operational_state=excluded.operational_state,
    checks=excluded.checks,
    checked_at=excluded.checked_at;

  return jsonb_build_object('healthy',v_healthy,'state',v_state,'checks',v_checks,'checked_at',now());
end
$function$;

create or replace function internal_rpc.kds_update_order(p_token text, p_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_email extensions.citext; v_actor_id uuid; v_role text;
  v_old public.orders%rowtype; v_row public.orders%rowtype;
  v_now timestamptz:=now(); v_to text; v_event text; v_note text;
  v_auto_claim_exists boolean:=false; v_auto_dispatch_exists boolean:=false;
begin
  select a.email,a.actor_id,a.role into v_email,v_actor_id,v_role
  from private.admin_actor_context(p_token) a;
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  select * into v_old from public.orders where id=p_id for update;
  if v_old.id is null then return jsonb_build_object('ok',false,'error','order_not_found'); end if;

  if p_action='verify_start' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_payment_state'); end if;
    update public.orders
      set payment_status='verified',order_status='preparing',verified_at=coalesce(verified_at,v_now),
          verified_by=v_actor_id,verified_by_email=v_email,kitchen_sent_at=coalesce(kitchen_sent_at,v_now),
          kds_received_at=coalesce(kds_received_at,v_now),preparing_at=coalesce(preparing_at,v_now),updated_at=v_now
      where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id)
      values(p_id,'payment_verified_and_kds_started',v_old.order_status,'preparing','Pembayaran diverifikasi dan pesanan langsung masuk tahap Sedang Diproses.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
    return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row));
  elsif p_action='verify_payment' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_payment_state'); end if;
    update public.orders
      set payment_status='verified',order_status='confirmed',verified_at=coalesce(verified_at,v_now),
          verified_by=v_actor_id,verified_by_email=v_email,kitchen_sent_at=coalesce(kitchen_sent_at,v_now),updated_at=v_now
      where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id)
      values(p_id,'payment_verified_kds',v_old.order_status,'confirmed','Pembayaran diverifikasi oleh petugas KDS.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
    return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row));
  elsif p_action='reject_payment' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_payment_state'); end if;
    update public.orders
      set payment_status='rejected',order_status='awaiting_payment',verified_at=null,verified_by=null,
          verified_by_email=null,kitchen_sent_at=null,updated_at=v_now
      where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id)
      values(p_id,'payment_rejected_kds',v_old.order_status,'awaiting_payment','Bukti pembayaran ditolak oleh petugas KDS untuk diperiksa atau diulang.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
    return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row));
  end if;

  if v_old.payment_status<>'verified' then return jsonb_build_object('ok',false,'error','payment_not_verified'); end if;

  if p_action='start' then
    if v_old.order_status not in ('confirmed','preparing') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='preparing',kds_received_at=coalesce(kds_received_at,v_now),
      preparing_at=coalesce(preparing_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    v_to:='preparing';v_event:='kds_preparing';v_note:='Pesanan diterima dapur dan mulai diproses.';

  elsif p_action='finish' then
    if v_old.order_status not in ('preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='completed',kds_received_at=coalesce(kds_received_at,v_now),
      preparing_at=coalesce(preparing_at,v_now),completed_at=coalesce(completed_at,v_now),updated_at=v_now
      where id=p_id returning * into v_row;
    v_to:='completed';v_event:='kds_completed';v_note:='Pesanan selesai dari alur KDS tiga tahap.';

  elsif p_action='ready' then
    if v_old.order_status not in ('confirmed','preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='ready',kds_received_at=coalesce(kds_received_at,v_now),
      preparing_at=coalesce(preparing_at,v_now),ready_at=coalesce(ready_at,v_now),updated_at=v_now
      where id=p_id returning * into v_row;
    v_to:='ready';v_event:='kds_ready';v_note:='Pesanan siap disajikan atau diserahkan.';

  elsif p_action='complete' then
    if v_old.order_status='completed' then
      return jsonb_build_object(
        'ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_old),
        'idempotent',true,'state_changed',false,'auto_print_required',false
      );
    end if;
    if v_old.order_status<>'ready' then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders
      set order_status='completed',completed_at=coalesce(completed_at,v_now),updated_at=v_now
      where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id)
      values(p_id,'kds_completed',v_old.order_status,'completed','Pesanan selesai.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id)
      values(p_id,'kds_auto_print_claimed','completed','completed','Hak auto-print handover diklaim satu kali.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
    return jsonb_build_object(
      'ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row),
      'idempotent',false,'state_changed',true,'auto_print_required',true
    );

  elsif p_action='print_auto_dispatch' then
    if v_old.order_status<>'completed' then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    select exists(select 1 from public.order_events where order_id=p_id and event_type='kds_auto_print_claimed')
      into v_auto_claim_exists;
    if not v_auto_claim_exists then return jsonb_build_object('ok',false,'error','auto_print_not_claimed'); end if;
    select exists(select 1 from public.order_events where order_id=p_id and event_type='kds_auto_print_dispatched')
      into v_auto_dispatch_exists;
    if v_auto_dispatch_exists then
      return jsonb_build_object(
        'ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_old),
        'idempotent',true,'auto_print_dispatched',true
      );
    end if;
    update public.orders
      set kitchen_print_count=kitchen_print_count+1,kitchen_last_printed_at=v_now,
          kds_received_at=coalesce(kds_received_at,v_now),updated_at=v_now
      where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id)
      values(p_id,'kds_auto_print_dispatched',v_old.order_status,v_old.order_status,'Perintah auto-print handover diteruskan ke runtime printer.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
    return jsonb_build_object(
      'ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row),
      'idempotent',false,'auto_print_dispatched',true
    );

  elsif p_action='reopen' then
    if v_old.order_status<>'completed' then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='ready',completed_at=null,updated_at=v_now
      where id=p_id returning * into v_row;
    v_to:='ready';v_event:='kds_reopened';v_note:='Pesanan dibuka kembali ke status siap disajikan.';

  elsif p_action='print' then
    update public.orders
      set kitchen_print_count=kitchen_print_count+1,kitchen_last_printed_at=v_now,
          kds_received_at=coalesce(kds_received_at,v_now),updated_at=v_now
      where id=p_id returning * into v_row;
    v_to:=v_old.order_status;v_event:='kitchen_ticket_printed';v_note:='Kitchen ticket dicetak ulang secara eksplisit.';

  else
    return jsonb_build_object('ok',false,'error','invalid_action');
  end if;

  insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id)
    values(p_id,v_event,v_old.order_status,v_to,v_note,v_actor_id,v_email,v_role,'kds',v_old.request_id);

  return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row));
end
$function$;

create or replace function public.kds_update_order(p_token text, p_id uuid, p_action text)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  h jsonb:='{}'::jsonb;
  o text:='';
  r text:=coalesce(current_setting('request.jwt.claim.role',true),'');
begin
  if p_token is null or p_token !~* '^[a-f0-9]{64}$' then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  if p_action not in (
    'verify_start','verify_payment','reject_payment','start','finish','ready',
    'complete','reopen','print','print_auto_dispatch'
  ) then
    return jsonb_build_object('ok',false,'error','invalid_action');
  end if;
  if r='anon' then
    begin
      h:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb);
    exception when others then
      h:='{}'::jsonb;
    end;
    o:=coalesce(h->>'origin','');
    if o not in (
      'https://smart-order-sdb.vercel.app',
      'https://smart-cassier.vercel.app',
      'https://rohmat-kds-printer.vercel.app',
      'https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app'
    ) then
      return jsonb_build_object('ok',false,'error','origin_not_allowed');
    end if;
  end if;
  return internal_rpc.kds_update_order(p_token,p_id,p_action);
end
$function$;

comment on index public.order_events_kds_completion_once_uidx is
  'Golden Master v12: canonical KDS completion event is exactly-once per order.';
comment on index public.order_events_kds_auto_print_once_uidx is
  'Golden Master v12: auto handover print claim/dispatch events are exactly-once; explicit manual reprints remain separate.';
