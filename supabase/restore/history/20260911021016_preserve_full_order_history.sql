-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911021016  Name: preserve_full_order_history
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.order_history_archive
  add column if not exists payment_method text,
  add column if not exists payment_status text,
  add column if not exists order_status text,
  add column if not exists payment_proof_url text,
  add column if not exists client_order_id text,
  add column if not exists payment_submitted_at timestamptz,
  add column if not exists verified_at timestamptz,
  add column if not exists verified_by uuid,
  add column if not exists kitchen_sent_at timestamptz,
  add column if not exists updated_at timestamptz,
  add column if not exists kds_received_at timestamptz,
  add column if not exists preparing_at timestamptz,
  add column if not exists ready_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists kitchen_print_count integer,
  add column if not exists kitchen_last_printed_at timestamptz,
  add column if not exists payment_proof_sha256 text,
  add column if not exists proof_check_status text,
  add column if not exists proof_merchant_match boolean,
  add column if not exists proof_amount_match boolean,
  add column if not exists proof_date_match boolean,
  add column if not exists proof_time_match boolean,
  add column if not exists proof_amount_detected integer,
  add column if not exists proof_date_detected text,
  add column if not exists proof_time_detected text,
  add column if not exists proof_checked_at timestamptz,
  add column if not exists order_source text,
  add column if not exists cashier_actor text,
  add column if not exists cash_received integer,
  add column if not exists change_amount integer,
  add column if not exists events jsonb not null default '[]'::jsonb;

create unique index if not exists order_history_archive_client_order_id_key
  on public.order_history_archive(client_order_id)
  where client_order_id is not null;
create unique index if not exists order_history_archive_payment_proof_sha256_key
  on public.order_history_archive(payment_proof_sha256)
  where payment_proof_sha256 is not null and payment_proof_sha256 <> '';
create index if not exists order_history_archive_source_created_idx
  on public.order_history_archive(order_source, created_at desc);
create index if not exists order_history_archive_payment_created_idx
  on public.order_history_archive(payment_method, created_at desc);

create or replace function public.archive_orders_older_than_7d()
returns integer
language plpgsql
security definer
set search_path=''
as $function$
declare v_count integer:=0;
begin
  insert into public.order_history_archive(
    id, public_order_code, created_at, customer_name, customer_whatsapp, service_mode, table_number,
    items, item_count, total_amount, customer_note, paid_amount, payment_difference, producer_note, archived_at,
    payment_method, payment_status, order_status, payment_proof_url, client_order_id,
    payment_submitted_at, verified_at, verified_by, kitchen_sent_at, updated_at, kds_received_at,
    preparing_at, ready_at, completed_at, kitchen_print_count, kitchen_last_printed_at,
    payment_proof_sha256, proof_check_status, proof_merchant_match, proof_amount_match, proof_date_match,
    proof_time_match, proof_amount_detected, proof_date_detected, proof_time_detected, proof_checked_at,
    order_source, cashier_actor, cash_received, change_amount, events
  )
  select
    o.id,o.public_order_code,o.created_at,o.customer_name,o.customer_whatsapp,o.service_mode,o.table_number,
    o.items,o.item_count,o.total_amount,o.customer_note,o.paid_amount,o.payment_difference,o.producer_note,now(),
    o.payment_method,o.payment_status,o.order_status,o.payment_proof_url,o.client_order_id,
    o.payment_submitted_at,o.verified_at,o.verified_by,o.kitchen_sent_at,o.updated_at,o.kds_received_at,
    o.preparing_at,o.ready_at,o.completed_at,o.kitchen_print_count,o.kitchen_last_printed_at,
    o.payment_proof_sha256,o.proof_check_status,o.proof_merchant_match,o.proof_amount_match,o.proof_date_match,
    o.proof_time_match,o.proof_amount_detected,o.proof_date_detected,o.proof_time_detected,o.proof_checked_at,
    o.order_source,o.cashier_actor,o.cash_received,o.change_amount,
    coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at) from public.order_events e where e.order_id=o.id),'[]'::jsonb)
  from public.orders o
  where o.created_at < now()-interval '7 days'
  on conflict (id) do update set
    customer_name=excluded.customer_name,
    customer_whatsapp=excluded.customer_whatsapp,
    service_mode=excluded.service_mode,
    table_number=excluded.table_number,
    items=excluded.items,
    item_count=excluded.item_count,
    total_amount=excluded.total_amount,
    customer_note=excluded.customer_note,
    paid_amount=excluded.paid_amount,
    payment_difference=excluded.payment_difference,
    producer_note=excluded.producer_note,
    archived_at=excluded.archived_at,
    payment_method=excluded.payment_method,
    payment_status=excluded.payment_status,
    order_status=excluded.order_status,
    payment_proof_url=excluded.payment_proof_url,
    client_order_id=excluded.client_order_id,
    payment_submitted_at=excluded.payment_submitted_at,
    verified_at=excluded.verified_at,
    verified_by=excluded.verified_by,
    kitchen_sent_at=excluded.kitchen_sent_at,
    updated_at=excluded.updated_at,
    kds_received_at=excluded.kds_received_at,
    preparing_at=excluded.preparing_at,
    ready_at=excluded.ready_at,
    completed_at=excluded.completed_at,
    kitchen_print_count=excluded.kitchen_print_count,
    kitchen_last_printed_at=excluded.kitchen_last_printed_at,
    payment_proof_sha256=excluded.payment_proof_sha256,
    proof_check_status=excluded.proof_check_status,
    proof_merchant_match=excluded.proof_merchant_match,
    proof_amount_match=excluded.proof_amount_match,
    proof_date_match=excluded.proof_date_match,
    proof_time_match=excluded.proof_time_match,
    proof_amount_detected=excluded.proof_amount_detected,
    proof_date_detected=excluded.proof_date_detected,
    proof_time_detected=excluded.proof_time_detected,
    proof_checked_at=excluded.proof_checked_at,
    order_source=excluded.order_source,
    cashier_actor=excluded.cashier_actor,
    cash_received=excluded.cash_received,
    change_amount=excluded.change_amount,
    events=excluded.events;
  get diagnostics v_count = row_count;

  delete from public.order_events e
  using public.orders o
  where e.order_id=o.id and o.created_at < now()-interval '7 days';

  delete from public.orders where created_at < now()-interval '7 days';
  return v_count;
end;
$function$;

