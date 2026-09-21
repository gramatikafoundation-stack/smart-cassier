-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911063214  Name: sheet_sync_cron_private_invoker_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

DO $outer$
DECLARE v_jobid bigint;
BEGIN
  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname='rohmat_sheet_sync_worker' LIMIT 1;
  IF v_jobid IS NOT NULL THEN PERFORM cron.unschedule(v_jobid); END IF;
  PERFORM cron.schedule('rohmat_sheet_sync_worker','* * * * *','select private.invoke_sheet_sync_worker();');
END
$outer$;
