-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911063037  Name: sheet_sync_async_retry_cron_v1b
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

DO $outer$
DECLARE v_jobid bigint;
BEGIN
  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname='rohmat_sheet_sync_worker' LIMIT 1;
  IF v_jobid IS NOT NULL THEN PERFORM cron.unschedule(v_jobid); END IF;
  PERFORM cron.schedule(
    'rohmat_sheet_sync_worker',
    '* * * * *',
    $cmd$select net.http_post(url := 'http://127.0.0.1:54321/functions/v1/rohmat-sheet-sync-worker-v1', body := '{}'::jsonb, headers := jsonb_build_object('Content-Type','application/json','X-Rohmat-Cron-Token','rohmat-sheet-cron-2026-v1'), timeout_milliseconds := 1000);$cmd$
  );

  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname='rohmat_sheet_sync_reconcile' LIMIT 1;
  IF v_jobid IS NOT NULL THEN PERFORM cron.unschedule(v_jobid); END IF;
  PERFORM cron.schedule('rohmat_sheet_sync_reconcile','7,37 * * * *','select private.enqueue_sheet_reconciliation();');
END
$outer$;
