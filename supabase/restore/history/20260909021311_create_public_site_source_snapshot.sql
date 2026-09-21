-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909021311  Name: create_public_site_source_snapshot
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists public.public_site_source_snapshots (
  snapshot_key text primary key,
  html text not null,
  source_url text not null,
  created_at timestamptz not null default now()
);
alter table public.public_site_source_snapshots enable row level security;
revoke all on table public.public_site_source_snapshots from anon, authenticated;
comment on table public.public_site_source_snapshots is 'Internal HTML snapshots for the Rohmat public-site deployment proxy. No client access.';
