-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912094333  Name: private_schema_explicit_deny_policies_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

do $do$
declare r record;
begin
  for r in
    select c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='private' and c.relkind in ('r','p')
  loop
    if not exists (
      select 1 from pg_policies
      where schemaname='private' and tablename=r.table_name and policyname='deny_client_all'
    ) then
      execute format(
        'create policy deny_client_all on private.%I as restrictive for all to anon, authenticated using (false) with check (false)',
        r.table_name
      );
    end if;
  end loop;
end
$do$;
