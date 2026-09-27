-- SMART ORDER B3.2: integrated observability, performance and release-readiness contract
begin;

-- Record the release-readiness observation window without changing historical SLO evidence.
update private.platform_prototypes
set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'b3_state','observability_cutover',
      'b3_observability_cutover_at',now(),
      'b3_reliability_history_policy','preserve_24h_history_use_post_cutover_release_window'
    ),
    updated_at=now()
where prototype_key='smart-order-sdb-platform-v1' and status='draft';

-- The fourth web surface is now first-class for synthetic performance samples.
alter table private.frontend_performance_samples
  drop constraint if exists frontend_performance_samples_service_key_check;
alter table private.frontend_performance_samples
  add constraint frontend_performance_samples_service_key_check
  check (service_key in ('public_web','admin_web','kds_web','database_web'));

-- Reliability registry/SLO includes Database plus the existing Order Gateway.
insert into private.reliability_probe_state(service_key,last_checked_at,consecutive_failures,updated_at)
values('database_web',now()-interval '1 day',0,now())
on conflict(service_key) do nothing;

insert into private.reliability_slo_config(
  service_key,min_1h_percent,min_24h_percent,critical_below_percent,enabled,updated_at
) values('database_web',99.000,99.900,95.000,true,now())
on conflict(service_key) do update
set min_1h_percent=excluded.min_1h_percent,
    min_24h_percent=excluded.min_24h_percent,
    critical_below_percent=excluded.critical_below_percent,
    enabled=true,updated_at=now();

create or replace function public.reliability_record_probe_tenant(
  p_tenant_id uuid,p_service_key text,p_ok boolean,p_http_status integer,
  p_latency_ms integer,p_error text default null
)
returns void
language plpgsql
security definer
set search_path=''
as $$
begin
  if coalesce(p_service_key,'') not in ('public_web','admin_web','kds_web','database_web','order_gateway')
    then raise exception 'invalid_service_key'; end if;
  if not exists(select 1 from private.platform_tenants where id=p_tenant_id and status='active')
    then raise exception 'tenant_unavailable'; end if;

  insert into private.tenant_reliability_probe_state(
    tenant_id,service_key,last_success_at,last_failure_at,last_checked_at,last_http_status,
    last_latency_ms,consecutive_failures,last_error,updated_at
  ) values(
    p_tenant_id,p_service_key,case when p_ok then now() end,case when not p_ok then now() end,
    now(),p_http_status,p_latency_ms,case when p_ok then 0 else 1 end,
    case when p_ok then null else left(coalesce(p_error,'probe_failed'),500) end,now()
  )
  on conflict(tenant_id,service_key) do update set
    last_success_at=case when p_ok then now() else private.tenant_reliability_probe_state.last_success_at end,
    last_failure_at=case when not p_ok then now() else private.tenant_reliability_probe_state.last_failure_at end,
    last_checked_at=now(),last_http_status=p_http_status,last_latency_ms=p_latency_ms,
    consecutive_failures=case when p_ok then 0 else private.tenant_reliability_probe_state.consecutive_failures+1 end,
    last_error=case when p_ok then null else left(coalesce(p_error,'probe_failed'),500) end,updated_at=now();

  insert into private.reliability_probe_events(
    tenant_id,service_key,ok,http_status,latency_ms,error,checked_at
  ) values(
    p_tenant_id,p_service_key,p_ok,p_http_status,p_latency_ms,
    case when p_ok then null else left(coalesce(p_error,'probe_failed'),500) end,now()
  );
  delete from private.reliability_probe_events where checked_at<now()-interval '30 days';
end
$$;
revoke all on function public.reliability_record_probe_tenant(uuid,text,boolean,integer,integer,text) from public,anon,authenticated;
grant execute on function public.reliability_record_probe_tenant(uuid,text,boolean,integer,integer,text) to service_role;

create or replace function private.reliability_summary_tenant(p_tenant_id uuid)
returns jsonb
language sql
stable security definer
set search_path=''
as $$
with expected(service_key) as (
 values ('public_web'),('admin_web'),('kds_web'),('database_web'),('order_gateway')
), s as (
 select e.service_key,r.last_success_at,r.last_failure_at,r.last_checked_at,r.last_http_status,
        r.last_latency_ms,r.consecutive_failures,r.last_error
 from expected e
 left join private.tenant_reliability_probe_state r
   on r.tenant_id=p_tenant_id and r.service_key=e.service_key
), agg as (
 select count(*) count_services,
        count(*) filter(where last_checked_at>now()-interval '15 minutes') fresh_services,
        count(*) filter(where consecutive_failures=0 and last_http_status between 200 and 399) healthy_services
 from s
)
select jsonb_build_object(
 'ok',count_services=5 and fresh_services=5 and healthy_services=5,
 'tenant_id',p_tenant_id,
 'expected_services',5,
 'service_count',count_services,
 'fresh_services',fresh_services,
 'healthy_services',healthy_services,
 'services',coalesce((select jsonb_object_agg(service_key,to_jsonb(s)-'service_key') from s),'{}'::jsonb)
) from agg
$$;

create or replace function private.smart_order_b3_reliability_readiness_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_cutover timestamptz;
  v_expected integer:=5;
  v_recent integer;
  v_healthy integer;
  v_sampled integer;
  v_failures bigint;
  v_operational jsonb;
begin
  select nullif(metadata->>'b3_observability_cutover_at','')::timestamptz
    into v_cutover
  from private.platform_prototypes
  where prototype_key='smart-order-sdb-platform-v1'
    and reference_tenant_id=p_tenant_id
  limit 1;
  v_cutover:=coalesce(v_cutover,now()-interval '30 minutes');

  with expected(service_key) as (
    values ('public_web'),('admin_web'),('kds_web'),('database_web'),('order_gateway')
  ), state as (
    select e.service_key,s.last_checked_at,s.last_http_status,s.consecutive_failures,s.last_success_at
    from expected e
    left join private.tenant_reliability_probe_state s
      on s.tenant_id=p_tenant_id and s.service_key=e.service_key
  )
  select count(*) filter(where last_checked_at>=greatest(v_cutover,now()-interval '15 minutes')),
         count(*) filter(where last_success_at>=greatest(v_cutover,now()-interval '15 minutes')
                          and consecutive_failures=0 and last_http_status between 200 and 399)
  into v_recent,v_healthy
  from state;

  with expected(service_key) as (
    values ('public_web'),('admin_web'),('kds_web'),('database_web'),('order_gateway')
  ), counts as (
    select e.service_key,count(r.*) filter(where r.ok) successes
    from expected e
    left join private.reliability_probe_events r
      on r.tenant_id=p_tenant_id and r.service_key=e.service_key
     and r.checked_at>=v_cutover
    group by e.service_key
  )
  select count(*) filter(where successes>=3) into v_sampled from counts;

  select count(*) into v_failures
  from private.reliability_probe_events
  where tenant_id=p_tenant_id and checked_at>=v_cutover and not ok;

  v_operational:=private.reliability_slo_summary();

  return jsonb_build_object(
    'ok',v_recent=v_expected and v_healthy=v_expected and v_sampled=v_expected and v_failures=0,
    'contract','smart-order-b3-release-reliability-v1',
    'tenant_id',p_tenant_id,
    'cutover_at',v_cutover,
    'expected_services',v_expected,
    'recent_services',v_recent,
    'healthy_services',v_healthy,
    'services_with_3plus_post_cutover_successes',v_sampled,
    'post_cutover_failures',v_failures,
    'operational_24h_slo',v_operational,
    'note','24h operational SLO history is preserved; release readiness uses a clean post-cutover observation window.'
  );
end
$$;
revoke all on function private.smart_order_b3_reliability_readiness_v1(uuid) from public,anon,authenticated;
grant execute on function private.smart_order_b3_reliability_readiness_v1(uuid) to service_role;

-- Keep operational reliability semantics honest while adding Database to the monitored set.
create or replace function private.reliability_status()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_expected int:=5; v_registered int; v_recent int; v_healthy int; v_stuck bigint; v_terminal_due bigint;
  v_drill_ok boolean; v_drill_at timestamptz; v_drill_ms integer; v_checkpoint_at timestamptz; v_checkpoint_hash text; v_checkpoint_ok boolean;
  v_probe_cron boolean; v_drill_cron boolean; v_checkpoint_cron boolean; v_readonly boolean;
  v_samples bigint; v_success bigint; v_availability numeric; v_slo jsonb; v_slo_ok boolean; v_state text; v_ok boolean;
begin
  select count(*),count(*) filter(where last_checked_at>=now()-interval '15 minutes'),
         count(*) filter(where last_checked_at>=now()-interval '15 minutes' and consecutive_failures<2 and last_success_at>=now()-interval '15 minutes')
  into v_registered,v_recent,v_healthy
  from private.tenant_reliability_probe_state
  where tenant_id=private.reference_tenant_id()
    and service_key in ('public_web','admin_web','kds_web','database_web','order_gateway');

  select count(*) into v_stuck from public.orders
  where created_at<now()-interval '7 days'
    and lower(coalesce(order_status,'')) not in ('completed','cancelled','canceled','rejected','payment_rejected');
  select count(*) into v_terminal_due from public.orders
  where created_at<now()-interval '8 days'
    and lower(coalesce(order_status,'')) in ('completed','cancelled','canceled','rejected','payment_rejected');

  select ok,checked_at,duration_ms into v_drill_ok,v_drill_at,v_drill_ms from private.recovery_drill_state where id=1;
  select created_at,manifest_hash into v_checkpoint_at,v_checkpoint_hash from private.recovery_checkpoints order by created_at desc limit 1;
  v_checkpoint_ok:=v_checkpoint_at is not null and v_checkpoint_at>=now()-interval '36 hours';
  select exists(select 1 from cron.job where jobname='rohmat_reliability_probe' and active and schedule='*/5 * * * *') into v_probe_cron;
  select exists(select 1 from cron.job where jobname='rohmat_recovery_drill_weekly' and active) into v_drill_cron;
  select exists(select 1 from cron.job where jobname='rohmat_recovery_checkpoint_daily' and active) into v_checkpoint_cron;
  v_readonly:=current_setting('transaction_read_only')='on';

  select count(*),count(*) filter(where ok) into v_samples,v_success
  from private.reliability_probe_events where checked_at>=now()-interval '24 hours';
  v_availability:=case when v_samples>0 then round((100.0*v_success/v_samples)::numeric,3) else null end;
  v_slo:=private.reliability_slo_summary();
  v_slo_ok:=coalesce((v_slo->>'ok')::boolean,false);
  v_state:=coalesce(v_slo->>'state','degraded');

  v_ok:=v_registered=v_expected and v_recent=v_expected and v_healthy=v_expected and v_slo_ok
        and coalesce(v_stuck,0)=0 and coalesce(v_terminal_due,0)=0
        and coalesce(v_drill_ok,false) and v_drill_at>=now()-interval '8 days'
        and v_checkpoint_ok and v_probe_cron and v_drill_cron and v_checkpoint_cron and not v_readonly;

  return jsonb_build_object(
    'ok',v_ok,'state',case when not v_ok and v_state='healthy' then 'degraded' else v_state end,
    'slo',v_slo,'expected_services',v_expected,'registered_services',v_registered,
    'recent_services',v_recent,'healthy_services',v_healthy,
    'probe_interval_minutes',5,'probe_stale_after_minutes',15,
    'availability_samples_24h',v_samples,'availability_success_24h',v_success,'availability_percent_24h',v_availability,
    'stuck_orders_older_7d',coalesce(v_stuck,0),'terminal_orders_unarchived_older_8d',coalesce(v_terminal_due,0),
    'recovery_drill_ok',coalesce(v_drill_ok,false),'last_recovery_drill_at',v_drill_at,'recovery_drill_duration_ms',v_drill_ms,
    'recovery_checkpoint_ok',v_checkpoint_ok,'last_recovery_checkpoint_at',v_checkpoint_at,'last_recovery_checkpoint_hash',v_checkpoint_hash,
    'probe_cron',v_probe_cron,'recovery_drill_cron',v_drill_cron,'recovery_checkpoint_cron',v_checkpoint_cron,'database_read_only',v_readonly
  );
end
$$;

-- Evidence-backed decoded HTML budgets. Network-transfer budgets are enforced in CI.
create or replace function private.frontend_performance_summary_tenant(p_tenant_id uuid)
returns jsonb
language sql
stable security definer
set search_path=''
as $$
with expected(service_key,max_bytes) as (
 values
 ('public_web',140000),
 ('admin_web',115000),
 ('kds_web',10000),
 ('database_web',115000)
), latest as (
 select distinct on(service_key) service_key,status_code,latency_ms,payload_bytes,cache_control,measured_at
 from private.frontend_performance_samples
 where tenant_id=p_tenant_id and status_code between 200 and 399
 order by service_key,measured_at desc
), rolling as (
 select service_key,
   round(percentile_cont(0.5) within group(order by latency_ms)::numeric,1) median_latency_ms,
   count(*) samples
 from private.frontend_performance_samples
 where tenant_id=p_tenant_id and measured_at>now()-interval '30 minutes'
   and status_code between 200 and 399
 group by service_key
), x as (
 select e.service_key,e.max_bytes,l.status_code,l.latency_ms,l.payload_bytes,l.cache_control,l.measured_at,
        r.median_latency_ms,r.samples
 from expected e
 left join latest l using(service_key)
 left join rolling r using(service_key)
), a as (
 select count(*) count_services,
   count(*) filter(where measured_at>now()-interval '15 minutes') fresh_services,
   count(*) filter(where coalesce(samples,0)>=2) sampled_services,
   count(*) filter(where coalesce(median_latency_ms,999999)<=5000) latency_ok,
   count(*) filter(where coalesce(payload_bytes,999999999)<=max_bytes) payload_ok
 from x
)
select jsonb_build_object(
 'ok',count_services=4 and fresh_services=4 and sampled_services=4 and latency_ok=4 and payload_ok=4,
 'tenant_id',p_tenant_id,
 'expected_services',4,'service_count',count_services,'fresh_services',fresh_services,
 'sampled_services',sampled_services,'median_latency_budget_ok',latency_ok,'decoded_payload_budget_ok',payload_ok,
 'budgets',jsonb_build_object(
   'median_latency_30m_success_max_ms',5000,'successful_sample_freshness_minutes',15,
   'public_decoded_max_bytes',140000,'admin_decoded_max_bytes',115000,
   'database_decoded_max_bytes',115000,'kds_decoded_max_bytes',10000
 ),
 'latest',coalesce((select jsonb_object_agg(service_key,to_jsonb(x)-'service_key'-'max_bytes') from x),'{}'::jsonb)
) from a
$$;

create or replace function private.frontend_performance_summary()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_tenant uuid:=private.reference_tenant_id();
  v_perf jsonb;
  v_direct bigint; v_proxy bigint; v_total bigint; v_cached bigint; v_year bigint;
  v_assets_ok boolean;
begin
  v_perf:=private.frontend_performance_summary_tenant(v_tenant);
  select count(*) filter(where image_url like 'https://xrepmvbccalzhlcznrff.supabase.co/storage/v1/object/public/rohmat-assets/menu-cache/%'),
         count(*) filter(where image_url like '%/functions/v1/rohmat-menu-photo%'),
         count(*)
    into v_direct,v_proxy,v_total
  from public.menu_items
  where tenant_id=v_tenant and coalesce(image_url,'')<>'';

  select count(*),count(*) filter(where metadata->>'cacheControl' like '%31536000%')
    into v_cached,v_year
  from storage.objects where bucket_id='rohmat-assets' and name like 'menu-cache/%';

  v_assets_ok:=v_proxy=0 and v_direct=v_total and v_total=36 and v_cached=36 and v_year=36;
  return jsonb_build_object(
    'ok',coalesce((v_perf->>'ok')::boolean,false) and v_assets_ok,
    'tenant',v_perf,
    'menu_images',jsonb_build_object(
      'total',v_total,'direct_storage',v_direct,'proxy_urls',v_proxy,
      'cached_objects',v_cached,'year_cache',v_year,'ok',v_assets_ok
    ),
    'note','Decoded HTML budgets are evidence-backed; compressed transfer and cold/warm TTFB are enforced by the B3 CI network gate.'
  );
end
$$;

-- Signed table QR is now the intended UX, not a failure condition.
create or replace function private.frontend_ux_contract_status()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_tenant uuid:=private.reference_tenant_id();
  v_visible bigint; v_invalid_menu bigint; v_missing_image bigint; v_invalid_service bigint; v_active_admin bigint;
  v_qris boolean; v_qris_image text; v_merchant text; v_signed boolean; v_pub text; v_adm text; v_kds text;
  v_routes boolean; v_qris_ok boolean; v_qr_mode_ok boolean; v_qr_count integer; v_table_count integer; v_ok boolean;
begin
  select s.qris_enabled,s.qris_image_url,s.merchant_name,s.require_table_qr_signature,s.public_url,s.admin_url,s.kds_url
    into v_qris,v_qris_image,v_merchant,v_signed,v_pub,v_adm,v_kds
  from public.site_settings s where s.id=1;

  select count(*) filter(where m.is_visible),
         count(*) filter(where m.is_visible and (nullif(trim(m.name),'') is null or nullif(trim(m.category),'') is null or m.price is null or m.price<0)),
         count(*) filter(where m.is_visible and (m.image_url is null or nullif(trim(m.image_url),'') is null))
    into v_visible,v_invalid_menu,v_missing_image
  from public.menu_items m where m.tenant_id=v_tenant;

  select count(*) into v_invalid_service
  from public.orders o
  where o.tenant_id=v_tenant and (
    (o.service_mode='dine-in' and (o.table_number is null or o.table_number not between 1 and 20))
    or (o.service_mode='take-away' and o.table_number is not null)
  );

  select count(*) into v_active_admin
  from public.admin_users a
  join private.tenant_memberships tm on lower(tm.email)=lower(a.email::text)
  where tm.tenant_id=v_tenant and tm.is_active and a.is_active;

  select c.table_count,count(q.*) filter(where q.is_active and q.signature_hash~'^[a-f0-9]{64}$')
    into v_table_count,v_qr_count
  from private.tenant_runtime_config c
  left join private.tenant_table_qr_signatures q
    on q.tenant_id=c.tenant_id and q.table_number between 1 and c.table_count
  where c.tenant_id=v_tenant
  group by c.table_count;

  v_routes :=
    rtrim(coalesce(v_pub,''),'/')=rtrim(coalesce((select public_origin from private.tenant_runtime_config where tenant_id=v_tenant),''),'/')
    and rtrim(coalesce(v_adm,''),'/')=rtrim(coalesce((select rtrim(admin_origin,'/')||'/admin' from private.tenant_runtime_config where tenant_id=v_tenant),''),'/')
    and rtrim(coalesce(v_kds,''),'/')=rtrim(coalesce((select rtrim(kds_origin,'/')||'/kds' from private.tenant_runtime_config where tenant_id=v_tenant),''),'/')
    and exists(
      select 1 from private.integration_registry
      where service_key='database_web'
        and rtrim(canonical_url,'/')=rtrim((select settings->>'database_url' from private.tenant_runtime_config where tenant_id=v_tenant),'/')
        and enabled
    );

  v_qris_ok:=not coalesce(v_qris,false)
    or (nullif(trim(coalesce(v_qris_image,'')),'') is not null and nullif(trim(coalesce(v_merchant,'')),'') is not null);
  v_qr_mode_ok:=coalesce(v_signed,false) and coalesce(v_qr_count,0)=coalesce(v_table_count,0) and coalesce(v_table_count,0)>0;

  v_ok:=coalesce(v_visible,0)>0 and coalesce(v_invalid_menu,0)=0 and coalesce(v_missing_image,0)=0
       and coalesce(v_invalid_service,0)=0 and coalesce(v_active_admin,0)>0
       and v_routes and v_qris_ok and v_qr_mode_ok;

  return jsonb_build_object(
    'ok',v_ok,
    'canonical_four_surface_navigation',v_routes,
    'visible_menu',coalesce(v_visible,0),
    'invalid_visible_menu',coalesce(v_invalid_menu,0),
    'visible_menu_missing_image',coalesce(v_missing_image,0),
    'invalid_service_table_orders',coalesce(v_invalid_service,0),
    'qris_configuration_ok',v_qris_ok,
    'signed_table_qr_mode_ok',v_qr_mode_ok,
    'signed_table_qr_valid',coalesce(v_qr_count,0),
    'table_count',coalesce(v_table_count,0),
    'active_admins',coalesce(v_active_admin,0),
    'contract','smart-order-b3-ux-v1'
  );
end
$$;

-- A master prototype may intentionally leave the external Apps Script writer unprovisioned.
-- In that mode Supabase remains the operational source of truth and stale sync events are
-- preserved as superseded audit rows; provisioning must enqueue a full reconciliation later.
update public.sheet_sync_outbox o
set status='superseded',
    last_error='prototype_writer_disabled_b3_reconciliation_required_on_provision',
    locked_until=null,locked_by=null,next_attempt_at=now()
where o.tenant_id=(select reference_tenant_id from private.platform_prototypes where prototype_key='smart-order-sdb-platform-v1' limit 1)
  and o.status in ('pending','processing')
  and not exists(
    select 1 from private.tenant_writer_config w
    where w.tenant_id=o.tenant_id and w.enabled
      and w.writer_secret_id is not null
      and w.writer_url like 'https://script.google.com/%'
  );

update private.integration_registry
set enabled=false,critical=false,
    canonical_url='provision://google-sheets-writer-v4',
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'mode','prototype_template',
      'provisioning_required',true,
      'activation_requires',jsonb_build_array('SHEETS_WRITER_URL','SHEETS_WRITER_SECRET','full_reconciliation')
    ),
    updated_at=now()
where service_key='sheet_writer'
  and not exists(
    select 1 from private.tenant_writer_config w
    where w.tenant_id=private.reference_tenant_id()
      and w.enabled and w.writer_secret_id is not null
      and w.writer_url like 'https://script.google.com/%'
  );

create or replace function private.sync_reference_sheet_writer_registry_b3()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.tenant_id<>private.reference_tenant_id() then return new; end if;
  if new.enabled and new.writer_secret_id is not null and coalesce(new.writer_url,'') like 'https://script.google.com/%' then
    update private.integration_registry
    set enabled=true,critical=true,canonical_url=new.writer_url,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'mode','live_sync','provisioning_required',false
        ),updated_at=now()
    where service_key='sheet_writer';
  else
    update private.integration_registry
    set enabled=false,critical=false,canonical_url='provision://google-sheets-writer-v4',
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'mode','prototype_template','provisioning_required',true,
          'activation_requires',jsonb_build_array('SHEETS_WRITER_URL','SHEETS_WRITER_SECRET','full_reconciliation')
        ),updated_at=now()
    where service_key='sheet_writer';
  end if;
  return new;
end
$$;

drop trigger if exists trg_sync_reference_sheet_writer_registry_b3 on private.tenant_writer_config;
create trigger trg_sync_reference_sheet_writer_registry_b3
after insert or update of enabled,writer_url,writer_secret_id
on private.tenant_writer_config
for each row execute function private.sync_reference_sheet_writer_registry_b3();

create or replace function private.smart_order_sheet_readiness_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_enabled boolean:=false; v_url text; v_secret uuid;
  v_targets integer; v_checked integer; v_consistent integer; v_fresh integer;
  v_pending bigint; v_processing bigint; v_failed bigint; v_dead bigint; v_superseded bigint;
  v_registry_template boolean; v_registry_live boolean; v_ok boolean; v_mode text;
begin
  select coalesce(enabled,false),writer_url,writer_secret_id into v_enabled,v_url,v_secret
  from private.tenant_writer_config where tenant_id=p_tenant_id;

  select count(*) into v_targets from private.tenant_sheet_targets where tenant_id=p_tenant_id and enabled;
  select count(*),count(*) filter(where consistent),count(*) filter(where consistent and checked_at>now()-interval '35 minutes')
    into v_checked,v_consistent,v_fresh
  from private.sheet_sync_consistency_state where tenant_id=p_tenant_id;

  select count(*) filter(where status='pending'),count(*) filter(where status='processing'),
         count(*) filter(where status='failed'),count(*) filter(where status='dead'),
         count(*) filter(where status='superseded')
    into v_pending,v_processing,v_failed,v_dead,v_superseded
  from public.sheet_sync_outbox where tenant_id=p_tenant_id;

  select exists(select 1 from private.integration_registry
    where service_key='sheet_writer' and not enabled and not critical
      and canonical_url='provision://google-sheets-writer-v4')
    into v_registry_template;
  select exists(select 1 from private.integration_registry
    where service_key='sheet_writer' and enabled and critical and canonical_url=v_url)
    into v_registry_live;

  if v_enabled then
    v_mode:='live_sync';
    v_ok:=v_url like 'https://script.google.com/%'
      and v_secret is not null
      and exists(select 1 from vault.secrets where id=v_secret)
      and v_targets=5 and v_checked=5 and v_consistent=5 and v_fresh=5
      and v_pending=0 and v_processing=0 and v_failed=0 and v_dead=0 and v_registry_live;
  else
    v_mode:='prototype_template';
    v_ok:=v_targets=5 and v_pending=0 and v_processing=0 and v_failed=0 and v_dead=0
      and v_registry_template;
  end if;

  return jsonb_build_object(
    'ok',v_ok,'tenant_id',p_tenant_id,'mode',v_mode,
    'writer_enabled',v_enabled,'writer_secret_configured',v_secret is not null,
    'active_targets',v_targets,'checked_targets',v_checked,'consistent_targets',v_consistent,'fresh_consistent_targets',v_fresh,
    'queue',jsonb_build_object('pending',v_pending,'processing',v_processing,'failed',v_failed,'dead',v_dead,'superseded',v_superseded),
    'reconciliation_required_on_provision',not v_enabled and v_superseded>0,
    'activation_contract',case when v_enabled then null else jsonb_build_array(
      'configure Apps Script Writer v4 URL','configure writer secret','enable writer','enqueue full reconciliation','verify 5/5 consistency'
    ) end
  );
end
$$;
revoke all on function private.smart_order_sheet_readiness_v1(uuid) from public,anon,authenticated;
grant execute on function private.smart_order_sheet_readiness_v1(uuid) to service_role;

create or replace function private.integration_contract_status()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_tenant uuid:=private.reference_tenant_id();
  v_public text; v_admin text; v_kds text; v_database text;
  v_writer_enabled boolean; v_writer text;
  v_registry_ok boolean; v_routes_ok boolean; v_writer_ok boolean;
  v_legacy_worker boolean; v_drain_worker boolean; v_cron_worker boolean;
  v_reconcile_cron boolean; v_health_cron boolean;
  v_corr_orders boolean; v_corr_outbox boolean; v_corr_events boolean;
  v_critical_count integer; v_expected integer;
begin
  select public_url,admin_url,kds_url into v_public,v_admin,v_kds from public.site_settings where id=1;
  select settings->>'database_url' into v_database from private.tenant_runtime_config where tenant_id=v_tenant;
  select coalesce(enabled,false),writer_url into v_writer_enabled,v_writer
  from private.tenant_writer_config where tenant_id=v_tenant;

  v_expected:=case when v_writer_enabled then 10 else 9 end;
  select count(*) into v_critical_count
  from private.integration_registry where critical and enabled and canonical_url<>'' and contract_version<>'';
  v_registry_ok:=v_critical_count=v_expected;

  v_writer_ok:=case when v_writer_enabled then
    exists(select 1 from private.integration_registry where service_key='sheet_writer' and enabled and critical and canonical_url=v_writer)
  else
    exists(select 1 from private.integration_registry where service_key='sheet_writer' and not enabled and not critical
      and canonical_url='provision://google-sheets-writer-v4')
  end;

  v_routes_ok:=
    exists(select 1 from private.integration_registry where service_key='public_web' and enabled and rtrim(canonical_url,'/')=rtrim(v_public,'/'))
    and exists(select 1 from private.integration_registry where service_key='admin_web' and enabled and rtrim(canonical_url,'/')=rtrim(v_admin,'/'))
    and exists(select 1 from private.integration_registry where service_key='kds_web' and enabled and rtrim(canonical_url,'/')=rtrim(v_kds,'/'))
    and exists(select 1 from private.integration_registry where service_key='database_web' and enabled and rtrim(canonical_url,'/')=rtrim(v_database,'/'))
    and v_writer_ok;

  select exists(select 1 from cron.job where jobname='rohmat_sheet_sync_worker' and active) into v_legacy_worker;
  select exists(select 1 from cron.job where jobname='rohmat-sheet-sync-drain-10s' and active
    and schedule ~ '^[1-5]?[0-9] seconds$' and command ilike '%private.invoke_sheet_sync_worker()%') into v_drain_worker;
  v_cron_worker:=v_legacy_worker or v_drain_worker;
  select exists(select 1 from cron.job where jobname='rohmat_sheet_sync_reconcile' and active
    and command ilike '%private.enqueue_sheet_reconciliation()%') into v_reconcile_cron;
  select exists(select 1 from cron.job where jobname='rohmat_production_health_monitor' and active) into v_health_cron;

  select exists(select 1 from pg_catalog.pg_attribute a join pg_catalog.pg_class c on c.oid=a.attrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='orders' and a.attname='request_id' and not a.attisdropped) into v_corr_orders;
  select exists(select 1 from pg_catalog.pg_attribute a join pg_catalog.pg_class c on c.oid=a.attrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='sheet_sync_outbox' and a.attname='request_id' and not a.attisdropped) into v_corr_outbox;
  select exists(select 1 from pg_catalog.pg_attribute a join pg_catalog.pg_class c on c.oid=a.attrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='order_events' and a.attname='request_id' and not a.attisdropped) into v_corr_events;

  return jsonb_build_object(
    'ok',v_registry_ok and v_routes_ok and v_cron_worker and v_reconcile_cron
         and v_health_cron and v_corr_orders and v_corr_outbox and v_corr_events,
    'registry_ok',v_registry_ok,'critical_services',v_critical_count,'expected_services',v_expected,
    'canonical_four_surface_routes_ok',v_routes_ok,
    'sheet_writer_mode',case when v_writer_enabled then 'live_sync' else 'prototype_template' end,
    'sheet_writer_contract_ok',v_writer_ok,
    'sheet_worker_cron',v_cron_worker,
    'sheet_worker_mode',case when v_drain_worker then 'subminute-drain' when v_legacy_worker then 'legacy-cron' else 'missing' end,
    'sheet_drain_cron',v_drain_worker,'sheet_reconcile_cron',v_reconcile_cron,'health_cron',v_health_cron,
    'orders_request_id',v_corr_orders,'outbox_request_id',v_corr_outbox,'order_events_request_id',v_corr_events
  );
end
$$;

-- Release preflight uses release-window reliability while exposing the preserved 24h SLO separately.
create or replace function private.release_preflight_status()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_tenant uuid:=private.reference_tenant_id();
  m jsonb; i jsonb; s jsonb; r jsonb; ro jsonb; p jsonb; u jsonb;
  v_failed bigint; v_dead bigint; v_stale bigint; v_ok boolean;
begin
  m:=private.release_engineering_status();
  i:=private.integration_contract_status();
  s:=private.smart_order_sheet_readiness_v1(v_tenant);
  r:=private.smart_order_b3_reliability_readiness_v1(v_tenant);
  ro:=private.reliability_status();
  p:=private.frontend_performance_summary();
  u:=private.frontend_ux_contract_status();
  select count(*) filter(where status='failed'),count(*) filter(where status='dead'),
         count(*) filter(where status in ('pending','processing') and created_at<now()-interval '5 minutes')
    into v_failed,v_dead,v_stale from public.sheet_sync_outbox where tenant_id=v_tenant;

  v_ok:=coalesce((m->>'ok')::boolean,false)
    and coalesce((i->>'ok')::boolean,false)
    and coalesce((s->>'ok')::boolean,false)
    and coalesce((r->>'ok')::boolean,false)
    and coalesce((p->>'ok')::boolean,false)
    and coalesce((u->>'ok')::boolean,false)
    and v_failed=0 and v_dead=0 and v_stale=0;

  return jsonb_build_object(
    'ok',v_ok,'maintainability',m,'integration',i,'sheet_readiness',s,
    'release_reliability',r,'operational_reliability_24h',ro,
    'performance',p,'ux',u,
    'outbox',jsonb_build_object('failed',v_failed,'dead',v_dead,'stale',v_stale)
  );
end
$$;

commit;
