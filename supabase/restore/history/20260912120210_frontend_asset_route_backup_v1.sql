-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912120210  Name: frontend_asset_route_backup_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.frontend_asset_route_backup (
  asset_type text not null,
  asset_key text not null,
  old_url text not null,
  new_url text not null,
  migrated_at timestamptz not null default now(),
  primary key(asset_type,asset_key)
);
alter table private.frontend_asset_route_backup enable row level security;
revoke all on private.frontend_asset_route_backup from public, anon, authenticated;
comment on table private.frontend_asset_route_backup is 'Rollback map for frontend asset route migrations; server-side only.';
