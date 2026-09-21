create table if not exists private.kds_observability_samples (
  id bigint generated always as identity primary key,
  measured_at timestamptz not null default now(),
  request_id uuid,
  metric text not null check (metric in ('API_MS','JSERR','NAV_TTFB','LONGTASK')),
  value double precision not null check (value >= 0 and value < 1000000),
  action text not null default 'unknown' check (char_length(action) between 1 and 64),
  http_status integer check (http_status is null or http_status between 100 and 599),
  rating text not null default 'good' check (rating in ('good','needs-improvement','poor')),
  release_id text not null default 'unknown' check (char_length(release_id) between 1 and 64),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object')
);

create index if not exists kds_observability_samples_measured_idx
  on private.kds_observability_samples (measured_at desc);

create index if not exists kds_observability_samples_metric_measured_idx
  on private.kds_observability_samples (metric, measured_at desc);

alter table private.kds_observability_samples enable row level security;

revoke all on table private.kds_observability_samples from public, anon, authenticated;
grant select, insert, delete on table private.kds_observability_samples to service_role;
grant usage, select on sequence private.kds_observability_samples_id_seq to service_role;

create or replace function private.kds_observability_prune(p_before timestamptz default now()-interval '30 days')
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare v_count bigint;
begin
  delete from private.kds_observability_samples where measured_at < p_before;
  get diagnostics v_count = row_count;
  return v_count;
end
$$;

revoke all on function private.kds_observability_prune(timestamptz) from public, anon, authenticated;
grant execute on function private.kds_observability_prune(timestamptz) to service_role;
