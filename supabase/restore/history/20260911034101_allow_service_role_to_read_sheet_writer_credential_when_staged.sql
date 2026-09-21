-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911034101  Name: allow_service_role_to_read_sheet_writer_credential_when_staged
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.sheet_sync_writer_credential()
returns text
language sql
stable security definer
set search_path to ''
as $function$
  select v.decrypted_secret
  from public.sheet_sync_config c
  join vault.decrypted_secrets v on v.id = c.writer_secret_id
  where c.id = 1
    and (auth.jwt() ->> 'role') = 'service_role'
$function$;

revoke all on function public.sheet_sync_writer_credential() from public, anon, authenticated;
grant execute on function public.sheet_sync_writer_credential() to service_role;
