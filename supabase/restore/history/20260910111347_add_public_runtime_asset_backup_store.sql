-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260910111347  Name: add_public_runtime_asset_backup_store
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists public.runtime_asset_backups (
  name text primary key,
  content text not null,
  updated_at timestamptz not null default now()
);
alter table public.runtime_asset_backups enable row level security;
grant select on public.runtime_asset_backups to anon, authenticated;
drop policy if exists runtime_asset_public_read on public.runtime_asset_backups;
create policy runtime_asset_public_read
on public.runtime_asset_backups
for select
to anon, authenticated
using (name like 'public:%');
