-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260907205320  Name: archive_orders_before_7d_purge_for_analytics
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists public.order_history_archive (
  id uuid primary key,
  public_order_code text not null,
  created_at timestamptz not null,
  customer_name text not null,
  service_mode text,
  table_number integer,
  items jsonb not null default '[]'::jsonb,
  item_count integer not null default 0,
  total_amount integer not null default 0,
  customer_note text not null default '',
  paid_amount integer,
  payment_difference integer not null default 0,
  producer_note text not null default '',
  archived_at timestamptz not null default now()
);

alter table public.order_history_archive enable row level security;
revoke all on table public.order_history_archive from anon, authenticated;

create index if not exists order_history_archive_created_at_idx on public.order_history_archive(created_at);
create index if not exists order_history_archive_customer_idx on public.order_history_archive(lower(customer_name));

create or replace function public.purge_orders_older_than_7_days()
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  deleted_count integer;
begin
  insert into public.order_history_archive(
    id, public_order_code, created_at, customer_name, service_mode, table_number,
    items, item_count, total_amount, customer_note, paid_amount, payment_difference, producer_note, archived_at
  )
  select
    id, public_order_code, created_at, customer_name, service_mode, table_number,
    items, item_count, total_amount, customer_note, paid_amount, payment_difference, producer_note, now()
  from public.orders
  where created_at < now() - interval '7 days'
  on conflict (id) do nothing;

  delete from public.orders
  where created_at < now() - interval '7 days';
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

revoke all on function public.purge_orders_older_than_7_days() from public, anon, authenticated;
grant execute on function public.purge_orders_older_than_7_days() to service_role;
