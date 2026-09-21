-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911014445  Name: rohmat_sheet_writer_authenticated_receiver
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

-- Credential is readable only by the existing server service role.
CREATE OR REPLACE FUNCTION public.sheet_sync_writer_credential()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT v.decrypted_secret
  FROM public.sheet_sync_config c
  JOIN vault.decrypted_secrets v ON v.id = c.writer_secret_id
  WHERE c.id = 1 AND c.enabled
    AND (auth.jwt() ->> 'role') = 'service_role'
$$;
REVOKE ALL ON FUNCTION public.sheet_sync_writer_credential() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sheet_sync_writer_credential() TO service_role;

