-- Local DR replay intentionally starts Supabase without application migrations and
-- replays the sanitized production history manually. Reconstruct the Supabase
-- migration ledger so migrations/functions that legitimately reference it see the
-- same control-plane relation they see in production.

create schema if not exists supabase_migrations;

create table if not exists supabase_migrations.schema_migrations (
  version text primary key,
  statements text[],
  name text,
  created_by text,
  idempotency_key text unique,
  rollback text[]
);
