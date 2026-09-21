-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911063743  Name: maintenance_retention_cleanup_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

CREATE OR REPLACE FUNCTION private.maintenance_retention_cleanup()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_audit int:=0;
  v_rl int:=0;
  v_outbox int:=0;
BEGIN
  DELETE FROM public.security_audit_events WHERE created_at < now()-interval '90 days';
  GET DIAGNOSTICS v_audit = ROW_COUNT;

  DELETE FROM public.security_rate_limits
   WHERE updated_at < now()-interval '2 days'
     AND (locked_until IS NULL OR locked_until < now());
  GET DIAGNOSTICS v_rl = ROW_COUNT;

  DELETE FROM public.sheet_sync_outbox
   WHERE status IN ('synced','superseded')
     AND created_at < now()-interval '30 days';
  GET DIAGNOSTICS v_outbox = ROW_COUNT;

  RETURN jsonb_build_object('audit_deleted',v_audit,'rate_limit_deleted',v_rl,'outbox_deleted',v_outbox);
END
$fn$;
REVOKE ALL ON FUNCTION private.maintenance_retention_cleanup() FROM PUBLIC,anon,authenticated,service_role;

DO $outer$
DECLARE v_jobid bigint;
BEGIN
  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname='rohmat_maintenance_retention' LIMIT 1;
  IF v_jobid IS NOT NULL THEN PERFORM cron.unschedule(v_jobid); END IF;
  PERFORM cron.schedule('rohmat_maintenance_retention','41 3 * * *','select private.maintenance_retention_cleanup();');
END
$outer$;
