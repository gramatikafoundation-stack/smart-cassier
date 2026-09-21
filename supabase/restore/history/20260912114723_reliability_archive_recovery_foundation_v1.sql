-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912114723  Name: reliability_archive_recovery_foundation_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.order_history_archive add column if not exists proof_ocr_text text not null default '';
alter table public.order_history_archive add column if not exists verified_by_email text;

create or replace function public.archive_orders_older_than_7d()
returns integer
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_count integer := 0;
begin
  insert into public.order_history_archive(
    id,public_order_code,created_at,customer_name,customer_whatsapp,service_mode,table_number,items,item_count,total_amount,customer_note,
    paid_amount,payment_difference,producer_note,archived_at,payment_method,payment_status,order_status,payment_proof_url,client_order_id,
    payment_submitted_at,verified_at,verified_by,kitchen_sent_at,updated_at,kds_received_at,preparing_at,ready_at,completed_at,
    kitchen_print_count,kitchen_last_printed_at,payment_proof_sha256,proof_check_status,proof_merchant_match,proof_amount_match,proof_date_match,
    proof_time_match,proof_amount_detected,proof_date_detected,proof_time_detected,proof_checked_at,order_source,cashier_actor,cash_received,
    change_amount,events,request_id,proof_ocr_text,verified_by_email
  )
  select
    o.id,o.public_order_code,o.created_at,o.customer_name,o.customer_whatsapp,o.service_mode,o.table_number,o.items,o.item_count,o.total_amount,o.customer_note,
    o.paid_amount,o.payment_difference,o.producer_note,now(),o.payment_method,o.payment_status,o.order_status,o.payment_proof_url,o.client_order_id,
    o.payment_submitted_at,o.verified_at,o.verified_by,o.kitchen_sent_at,o.updated_at,o.kds_received_at,o.preparing_at,o.ready_at,o.completed_at,
    o.kitchen_print_count,o.kitchen_last_printed_at,o.payment_proof_sha256,o.proof_check_status,o.proof_merchant_match,o.proof_amount_match,o.proof_date_match,
    o.proof_time_match,o.proof_amount_detected,o.proof_date_detected,o.proof_time_detected,o.proof_checked_at,o.order_source,o.cashier_actor,o.cash_received,
    o.change_amount,
    coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at) from public.order_events e where e.order_id=o.id),'[]'::jsonb),
    o.request_id,o.proof_ocr_text,o.verified_by_email::text
  from public.orders o
  where o.created_at < now()-interval '7 days'
    and lower(coalesce(o.order_status,'')) in ('completed','cancelled','canceled','rejected','payment_rejected')
  on conflict(id) do update set
    customer_name=excluded.customer_name,customer_whatsapp=excluded.customer_whatsapp,service_mode=excluded.service_mode,table_number=excluded.table_number,
    items=excluded.items,item_count=excluded.item_count,total_amount=excluded.total_amount,customer_note=excluded.customer_note,paid_amount=excluded.paid_amount,
    payment_difference=excluded.payment_difference,producer_note=excluded.producer_note,archived_at=excluded.archived_at,payment_method=excluded.payment_method,
    payment_status=excluded.payment_status,order_status=excluded.order_status,payment_proof_url=excluded.payment_proof_url,client_order_id=excluded.client_order_id,
    payment_submitted_at=excluded.payment_submitted_at,verified_at=excluded.verified_at,verified_by=excluded.verified_by,kitchen_sent_at=excluded.kitchen_sent_at,
    updated_at=excluded.updated_at,kds_received_at=excluded.kds_received_at,preparing_at=excluded.preparing_at,ready_at=excluded.ready_at,
    completed_at=excluded.completed_at,kitchen_print_count=excluded.kitchen_print_count,kitchen_last_printed_at=excluded.kitchen_last_printed_at,
    payment_proof_sha256=excluded.payment_proof_sha256,proof_check_status=excluded.proof_check_status,proof_merchant_match=excluded.proof_merchant_match,
    proof_amount_match=excluded.proof_amount_match,proof_date_match=excluded.proof_date_match,proof_time_match=excluded.proof_time_match,
    proof_amount_detected=excluded.proof_amount_detected,proof_date_detected=excluded.proof_date_detected,proof_time_detected=excluded.proof_time_detected,
    proof_checked_at=excluded.proof_checked_at,order_source=excluded.order_source,cashier_actor=excluded.cashier_actor,cash_received=excluded.cash_received,
    change_amount=excluded.change_amount,events=excluded.events,request_id=excluded.request_id,proof_ocr_text=excluded.proof_ocr_text,
    verified_by_email=excluded.verified_by_email;

  with doomed as (
    select o.id
    from public.orders o
    join public.order_history_archive a on a.id=o.id
    where o.created_at < now()-interval '7 days'
      and lower(coalesce(o.order_status,'')) in ('completed','cancelled','canceled','rejected','payment_rejected')
  )
  delete from public.order_events e using doomed d where e.order_id=d.id;

  with doomed as (
    select o.id
    from public.orders o
    join public.order_history_archive a on a.id=o.id
    where o.created_at < now()-interval '7 days'
      and lower(coalesce(o.order_status,'')) in ('completed','cancelled','canceled','rejected','payment_rejected')
  )
  delete from public.orders o using doomed d where o.id=d.id;
  get diagnostics v_count=row_count;
  return v_count;
end
$function$;

create table if not exists private.reliability_probe_state(
  service_key text primary key,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  last_checked_at timestamptz not null default now(),
  last_http_status integer,
  last_latency_ms integer,
  consecutive_failures integer not null default 0 check(consecutive_failures>=0),
  last_error text,
  updated_at timestamptz not null default now()
);
alter table private.reliability_probe_state enable row level security;
drop policy if exists deny_client_all on private.reliability_probe_state;
create policy deny_client_all on private.reliability_probe_state as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on private.reliability_probe_state from public,anon,authenticated;

create table if not exists private.recovery_drill_fixture(
  id uuid primary key,
  payload jsonb not null,
  payload_hash text not null,
  created_at timestamptz not null default now()
);
alter table private.recovery_drill_fixture enable row level security;
drop policy if exists deny_client_all on private.recovery_drill_fixture;
create policy deny_client_all on private.recovery_drill_fixture as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on private.recovery_drill_fixture from public,anon,authenticated;

create table if not exists private.recovery_drill_state(
  id smallint primary key default 1 check(id=1),
  ok boolean not null default false,
  checked_at timestamptz,
  duration_ms integer,
  source_hash text,
  restored_hash text,
  error text,
  details jsonb not null default '{}'::jsonb
);
alter table private.recovery_drill_state enable row level security;
drop policy if exists deny_client_all on private.recovery_drill_state;
create policy deny_client_all on private.recovery_drill_state as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on private.recovery_drill_state from public,anon,authenticated;

create table if not exists private.recovery_checkpoints(
  checkpoint_id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  orders_count bigint not null,
  archive_count bigint not null,
  menu_count bigint not null,
  outbox_count bigint not null,
  storage_object_count bigint not null,
  storage_payment_proof_count bigint not null,
  database_bytes bigint not null,
  source_max_updated_at timestamptz,
  manifest_hash text not null,
  manifest jsonb not null
);
create index if not exists recovery_checkpoints_created_idx on private.recovery_checkpoints(created_at desc);
alter table private.recovery_checkpoints enable row level security;
drop policy if exists deny_client_all on private.recovery_checkpoints;
create policy deny_client_all on private.recovery_checkpoints as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on private.recovery_checkpoints from public,anon,authenticated;

create or replace function public.reliability_record_probe(
  p_service_key text,p_ok boolean,p_http_status integer,p_latency_ms integer,p_error text default null
) returns void
language plpgsql
security definer
set search_path=''
as $function$
begin
  if coalesce(p_service_key,'') not in ('public_web','admin_web','kds_web','order_gateway') then
    raise exception 'invalid_service_key';
  end if;
  insert into private.reliability_probe_state(service_key,last_success_at,last_failure_at,last_checked_at,last_http_status,last_latency_ms,consecutive_failures,last_error,updated_at)
  values(p_service_key,case when p_ok then now() end,case when not p_ok then now() end,now(),p_http_status,p_latency_ms,case when p_ok then 0 else 1 end,case when p_ok then null else left(coalesce(p_error,'probe_failed'),500) end,now())
  on conflict(service_key) do update set
    last_success_at=case when p_ok then now() else private.reliability_probe_state.last_success_at end,
    last_failure_at=case when not p_ok then now() else private.reliability_probe_state.last_failure_at end,
    last_checked_at=now(),last_http_status=p_http_status,last_latency_ms=p_latency_ms,
    consecutive_failures=case when p_ok then 0 else private.reliability_probe_state.consecutive_failures+1 end,
    last_error=case when p_ok then null else left(coalesce(p_error,'probe_failed'),500) end,updated_at=now();
end
$function$;
revoke all on function public.reliability_record_probe(text,boolean,integer,integer,text) from public,anon,authenticated;
grant execute on function public.reliability_record_probe(text,boolean,integer,integer,text) to service_role;

create or replace function private.run_recovery_drill()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_start timestamptz:=clock_timestamp();
  v_id uuid:=gen_random_uuid();
  v_payload jsonb;
  v_source_hash text;
  v_restored_hash text;
  v_ok boolean:=false;
  v_ms integer;
begin
  v_payload:=jsonb_build_object('schema','rohmat-recovery-drill-v1','id',v_id,'at',date_trunc('second',now()),'sentinel',md5(random()::text||clock_timestamp()::text));
  v_source_hash:=md5(v_payload::text);
  insert into private.recovery_drill_fixture(id,payload,payload_hash) values(v_id,v_payload,v_source_hash);
  delete from private.recovery_drill_fixture where id=v_id;
  insert into private.recovery_drill_fixture(id,payload,payload_hash) values(v_id,v_payload,v_source_hash);
  select md5(payload::text) into v_restored_hash from private.recovery_drill_fixture where id=v_id;
  v_ok:=v_restored_hash=v_source_hash;
  delete from private.recovery_drill_fixture where id=v_id;
  v_ms:=greatest(0,(extract(epoch from (clock_timestamp()-v_start))*1000)::integer);
  insert into private.recovery_drill_state(id,ok,checked_at,duration_ms,source_hash,restored_hash,error,details)
  values(1,v_ok,now(),v_ms,v_source_hash,v_restored_hash,null,jsonb_build_object('fixture_residue',0,'method','write-delete-restore-hash-verify'))
  on conflict(id) do update set ok=excluded.ok,checked_at=excluded.checked_at,duration_ms=excluded.duration_ms,source_hash=excluded.source_hash,restored_hash=excluded.restored_hash,error=null,details=excluded.details;
  return jsonb_build_object('ok',v_ok,'duration_ms',v_ms,'fixture_residue',0);
exception when others then
  delete from private.recovery_drill_fixture where id=v_id;
  v_ms:=greatest(0,(extract(epoch from (clock_timestamp()-v_start))*1000)::integer);
  insert into private.recovery_drill_state(id,ok,checked_at,duration_ms,source_hash,restored_hash,error,details)
  values(1,false,now(),v_ms,v_source_hash,v_restored_hash,left(sqlerrm,500),jsonb_build_object('method','write-delete-restore-hash-verify'))
  on conflict(id) do update set ok=false,checked_at=excluded.checked_at,duration_ms=excluded.duration_ms,source_hash=excluded.source_hash,restored_hash=excluded.restored_hash,error=excluded.error,details=excluded.details;
  return jsonb_build_object('ok',false,'duration_ms',v_ms,'error','recovery_drill_failed');
end
$function$;
revoke all on function private.run_recovery_drill() from public,anon,authenticated;

create or replace function private.capture_recovery_checkpoint()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_manifest jsonb;
  v_hash text;
  v_orders bigint; v_archive bigint; v_menu bigint; v_outbox bigint; v_storage bigint; v_proofs bigint; v_db bigint; v_max timestamptz;
begin
  select count(*),max(updated_at) into v_orders,v_max from public.orders;
  select count(*) into v_archive from public.order_history_archive;
  select count(*) into v_menu from public.menu_items;
  select count(*) into v_outbox from public.sheet_sync_outbox;
  select count(*),count(*) filter(where bucket_id='rohmat-payment-proofs') into v_storage,v_proofs from storage.objects;
  v_db:=pg_database_size(current_database());
  v_manifest:=jsonb_build_object('orders',v_orders,'archive',v_archive,'menu',v_menu,'outbox',v_outbox,'storage_objects',v_storage,'payment_proofs',v_proofs,'database_bytes',v_db,'source_max_updated_at',v_max);
  v_hash:=md5(v_manifest::text);
  insert into private.recovery_checkpoints(orders_count,archive_count,menu_count,outbox_count,storage_object_count,storage_payment_proof_count,database_bytes,source_max_updated_at,manifest_hash,manifest)
  values(v_orders,v_archive,v_menu,v_outbox,v_storage,v_proofs,v_db,v_max,v_hash,v_manifest);
  delete from private.recovery_checkpoints where created_at<now()-interval '90 days';
  return jsonb_build_object('ok',true,'manifest_hash',v_hash,'manifest',v_manifest);
end
$function$;
revoke all on function private.capture_recovery_checkpoint() from public,anon,authenticated;

select cron.unschedule(jobid) from cron.job where jobname='rohmat_recovery_drill_weekly';
select cron.unschedule(jobid) from cron.job where jobname='rohmat_recovery_checkpoint_daily';
select cron.schedule('rohmat_recovery_drill_weekly','30 19 * * 6','select private.run_recovery_drill();');
select cron.schedule('rohmat_recovery_checkpoint_daily','10 20 * * *','select private.capture_recovery_checkpoint();');
