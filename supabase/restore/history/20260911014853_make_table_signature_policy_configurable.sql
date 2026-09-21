-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911014853  Name: make_table_signature_policy_configurable
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.verify_table_qr_signature(p_table integer, p_signature text)
returns boolean
language sql
security definer
set search_path to ''
as $function$
  select case
    when coalesce((select require_table_qr_signature from public.site_settings where id=1), false) = false
      then p_table between 1 and 20
    else exists(
      select 1
      from private.table_qr_signatures q
      where q.table_number=p_table
        and q.is_active
        and q.signature_hash=encode(extensions.digest(coalesce(p_signature,''),'sha256'),'hex')
        and coalesce(p_signature,'') ~ '^[a-f0-9]{32}$'
    )
  end;
$function$;
