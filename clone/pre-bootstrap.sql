-- MASTER CLONE v1 pre-bootstrap
-- Runs on a fresh tenant project BEFORE replaying production migration history.
-- Purpose: install non-relocatable pg_net outside public from first creation.
-- Verified provider pattern: existing Lucky Smart Order project has pg_net 0.20.4 in extensions.

create schema if not exists extensions;
create extension if not exists pg_net with schema extensions;

do $$
declare v_schema text;
begin
  select n.nspname into v_schema
  from pg_extension e
  join pg_namespace n on n.oid=e.extnamespace
  where e.extname='pg_net';

  if v_schema is distinct from 'extensions' then
    raise exception 'master_clone_pg_net_schema_invalid: expected extensions, got %', coalesce(v_schema,'missing');
  end if;

  if not exists (select 1 from pg_namespace where nspname='net') then
    raise exception 'master_clone_pg_net_runtime_schema_missing';
  end if;
end
$$;
