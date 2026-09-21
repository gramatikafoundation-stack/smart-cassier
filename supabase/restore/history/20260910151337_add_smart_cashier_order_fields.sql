-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260910151337  Name: add_smart_cashier_order_fields
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.orders drop constraint if exists orders_payment_method_check;

alter table public.orders
  add column if not exists order_source text not null default 'public',
  add column if not exists cashier_actor text,
  add column if not exists cash_received integer,
  add column if not exists change_amount integer not null default 0;

alter table public.orders
  add constraint orders_payment_method_check check (payment_method = any (array['qris'::text,'cash'::text,'qris_cashier'::text])),
  add constraint orders_order_source_check check (order_source = any (array['public'::text,'cashier_admin'::text,'cashier_kds'::text])),
  add constraint orders_cash_received_nonnegative check (cash_received is null or cash_received >= 0),
  add constraint orders_change_amount_nonnegative check (change_amount >= 0),
  add constraint orders_cashier_payment_shape check (
    (payment_method='cash' and cash_received is not null and cash_received >= total_amount and change_amount = cash_received-total_amount)
    or (payment_method in ('qris','qris_cashier') and cash_received is null and change_amount=0)
  );

create index if not exists orders_source_created_idx on public.orders(order_source, created_at desc);
create index if not exists orders_payment_method_created_idx on public.orders(payment_method, created_at desc);
