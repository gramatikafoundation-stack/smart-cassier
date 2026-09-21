-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260913201302  Name: temporary_dr_migration_export_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.dr_export_migration_history_v1(p_offset integer default 0, p_limit integer default 25)
returns jsonb
language sql
security definer
set search_path = ''
as $fn$
with rows as (
  select m.version,
         m.name,
         replace(
           replace(
             replace(
               replace(array_to_string(m.statements, E'\n'),
                 '$2a$06$00000000000000000000000000000000000000000000000000000',
                 '$2a$06$00000000000000000000000000000000000000000000000000000'),
               'restore-superadmin@example.invalid','restore-superadmin@example.invalid'),
             'restore-admin@example.invalid','restore-admin@example.invalid'),
           'http://127.0.0.1:54321','http://127.0.0.1:54321') as sql
  from supabase_migrations.schema_migrations m
  order by m.version
  offset greatest(coalesce(p_offset,0),0)
  limit least(greatest(coalesce(p_limit,25),1),50)
)
select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name,'sql',sql) order by version),'[]'::jsonb)
from rows;
$fn$;
revoke all on function public.dr_export_migration_history_v1(integer,integer) from public, anon, authenticated;
grant execute on function public.dr_export_migration_history_v1(integer,integer) to service_role;
