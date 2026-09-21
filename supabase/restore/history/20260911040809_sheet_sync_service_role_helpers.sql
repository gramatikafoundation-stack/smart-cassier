-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911040809  Name: sheet_sync_service_role_helpers
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

create or replace function public.run_sheet_sync_outbox(p_batch_size integer default 50)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if coalesce(auth.jwt() ->> 'role','') <> 'service_role' then
    raise exception 'forbidden' using errcode='42501';
  end if;
  return private.process_sheet_sync_outbox(p_batch_size);
end
$function$;
revoke all on function public.run_sheet_sync_outbox(integer) from public, anon, authenticated;
grant execute on function public.run_sheet_sync_outbox(integer) to service_role;
