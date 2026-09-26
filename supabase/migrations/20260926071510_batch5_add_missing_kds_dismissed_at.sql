alter table public.orders
  add column if not exists kds_dismissed_at timestamptz;
