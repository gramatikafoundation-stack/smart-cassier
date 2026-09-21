-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260908033934  Name: preserve_customer_phone_for_yearly_sheet_archive
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.order_history_archive add column if not exists customer_whatsapp text;

create index if not exists idx_order_history_archive_created_at on public.order_history_archive(created_at);

create or replace function public.purge_orders_older_than_7_days()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  deleted_count integer;
begin
  insert into public.order_history_archive(
    id, public_order_code, created_at, customer_name, customer_whatsapp, service_mode, table_number,
    items, item_count, total_amount, customer_note, paid_amount, payment_difference, producer_note, archived_at
  )
  select
    id, public_order_code, created_at, customer_name, customer_whatsapp, service_mode, table_number,
    items, item_count, total_amount, customer_note, paid_amount, payment_difference, producer_note, now()
  from public.orders
  where created_at < now() - interval '7 days'
  on conflict (id) do update set
    customer_whatsapp = excluded.customer_whatsapp,
    items = excluded.items,
    total_amount = excluded.total_amount,
    paid_amount = excluded.paid_amount,
    payment_difference = excluded.payment_difference,
    producer_note = excluded.producer_note;

  delete from public.orders
  where created_at < now() - interval '7 days';
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

create or replace function public.archive_orders_older_than_7d()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare v_count integer:=0;
begin
  insert into public.order_history_archive(
    id, public_order_code, created_at, customer_name, customer_whatsapp, service_mode, table_number,
    items, item_count, total_amount, customer_note, paid_amount, payment_difference, producer_note, archived_at
  )
  select
    o.id,o.public_order_code,o.created_at,o.customer_name,o.customer_whatsapp,o.service_mode,o.table_number,
    o.items,o.item_count,o.total_amount,o.customer_note,o.paid_amount,o.payment_difference,o.producer_note,now()
  from public.orders o
  where o.created_at < now()-interval '7 days'
  on conflict (id) do update set
    customer_whatsapp = excluded.customer_whatsapp,
    items = excluded.items,
    total_amount = excluded.total_amount,
    paid_amount = excluded.paid_amount,
    payment_difference = excluded.payment_difference,
    producer_note = excluded.producer_note;
  get diagnostics v_count = row_count;
  delete from public.order_events e using public.orders o where e.order_id=o.id and o.created_at < now()-interval '7 days';
  delete from public.orders where created_at < now()-interval '7 days';
  return v_count;
end;
$$;
