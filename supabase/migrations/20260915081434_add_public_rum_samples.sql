create table if not exists public.public_rum_samples (
  id bigint generated always as identity primary key,
  metric text not null check (metric = any (array['LCP','CLS','INP','FCP','TTFB']::text[])),
  value double precision not null check (value >= 0 and value < 1000000),
  rating text not null check (rating = any (array['good','needs-improvement','poor']::text[])),
  path text not null default '/' check (char_length(path) between 1 and 160 and path like '/%'),
  runtime_version text not null default 'unknown' check (char_length(runtime_version) between 1 and 40),
  effective_type text null check (effective_type is null or effective_type = any (array['slow-2g','2g','3g','4g','unknown']::text[])),
  save_data boolean not null default false,
  measured_at timestamptz not null default now()
);
comment on table public.public_rum_samples is 'Anonymous Real User Monitoring samples for the Rohmat public ordering site. Stores only coarse performance metrics; no user/order identity.';
alter table public.public_rum_samples enable row level security;
revoke all on table public.public_rum_samples from anon, authenticated;
grant select, insert, delete on table public.public_rum_samples to service_role;
create index if not exists public_rum_samples_metric_measured_idx on public.public_rum_samples(metric, measured_at desc);
create index if not exists public_rum_samples_measured_idx on public.public_rum_samples(measured_at desc);
create or replace function private.prune_public_rum_samples(p_keep interval default interval '30 days') returns integer
language plpgsql security definer set search_path = pg_catalog, public, private as $$
declare n integer;
begin
  delete from public.public_rum_samples where measured_at < now() - p_keep;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function private.prune_public_rum_samples(interval) from public, anon, authenticated;
grant execute on function private.prune_public_rum_samples(interval) to service_role;