-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911063100  Name: sheet_sync_cron_vault_secret_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

DO $outer$
DECLARE v_secret text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name='rohmat_sheet_sync_cron_token_v2') THEN
    v_secret := encode(extensions.gen_random_bytes(32),'hex');
    PERFORM vault.create_secret(v_secret,'rohmat_sheet_sync_cron_token_v2','Private retry-worker cron credential.');
  END IF;
END
$outer$;

CREATE OR REPLACE FUNCTION private.invoke_sheet_sync_worker()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_token text;
  v_request_id bigint;
BEGIN
  SELECT decrypted_secret INTO v_token
  FROM vault.decrypted_secrets
  WHERE name='rohmat_sheet_sync_cron_token_v2'
  LIMIT 1;
  IF coalesce(v_token,'')='' THEN
    RAISE EXCEPTION 'cron credential unavailable';
  END IF;
  SELECT net.http_post(
    url := 'http://127.0.0.1:54321/functions/v1/rohmat-sheet-sync-worker-v1',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','X-Rohmat-Cron-Token',v_token),
    timeout_milliseconds := 1000
  ) INTO v_request_id;
  RETURN v_request_id;
END
$fn$;
REVOKE ALL ON FUNCTION private.invoke_sheet_sync_worker() FROM PUBLIC, anon, authenticated, service_role;
