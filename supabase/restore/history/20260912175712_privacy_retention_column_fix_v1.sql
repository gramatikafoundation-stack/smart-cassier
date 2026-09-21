-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912175712  Name: privacy_retention_column_fix_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.privacy_retention_status()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare v_archive_due bigint; v_audit_due bigint; v_integration_due bigint; v_reliability_due bigint; v_perf_due bigint; v_release_due bigint; v_external int; v_policies int;
begin
  select count(*) into v_archive_due from public.order_history_archive where created_at<now()-interval '365 days' and (customer_name is distinct from 'Pelanggan' or customer_whatsapp is not null or customer_note is not null or verified_by_email is not null or payment_proof_url is not null or proof_ocr_text is not null or payment_proof_sha256 is not null);
  select count(*) into v_audit_due from public.security_audit_events where created_at<now()-interval '90 days';
  select count(*) into v_integration_due from private.integration_events where created_at<now()-interval '90 days';
  select count(*) into v_reliability_due from private.reliability_probe_events where checked_at<now()-interval '30 days';
  select count(*) into v_perf_due from private.frontend_performance_samples where measured_at<now()-interval '30 days';
  select count(*) into v_release_due from private.release_validation_runs where created_at<now()-interval '365 days';
  select count(*) into v_external from private.data_retention_policy where enabled and action='external_delete_required';
  select count(*) into v_policies from private.data_retention_policy where enabled;
  return jsonb_build_object('ok_database',v_archive_due=0 and v_audit_due=0 and v_integration_due=0 and v_reliability_due=0 and v_perf_due=0 and v_release_due=0,
    'policies',v_policies,'external_enforcement_pending',v_external,
    'due',jsonb_build_object('archive_anonymize',v_archive_due,'security_audit',v_audit_due,'integration_events',v_integration_due,'reliability_events',v_reliability_due,'performance_samples',v_perf_due,'release_validation',v_release_due));
end
$$;
revoke all on function private.privacy_retention_status() from public,anon,authenticated;
grant execute on function private.privacy_retention_status() to service_role;

create or replace function private.maintenance_retention_cleanup()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_audit int:=0; v_rl int:=0; v_outbox int:=0; v_archive int:=0; v_integration int:=0; v_reliability int:=0; v_perf int:=0; v_release int:=0;
begin
  update public.order_history_archive set customer_name='Pelanggan',customer_whatsapp=null,customer_note=null,verified_by_email=null,payment_proof_url=null,proof_ocr_text=null,payment_proof_sha256=null
  where created_at<now()-interval '365 days' and (customer_name is distinct from 'Pelanggan' or customer_whatsapp is not null or customer_note is not null or verified_by_email is not null or payment_proof_url is not null or proof_ocr_text is not null or payment_proof_sha256 is not null);
  get diagnostics v_archive=row_count;
  delete from public.security_audit_events where created_at<now()-interval '90 days'; get diagnostics v_audit=row_count;
  delete from public.security_rate_limits where updated_at<now()-interval '2 days' and (locked_until is null or locked_until<now()); get diagnostics v_rl=row_count;
  delete from public.sheet_sync_outbox where status in ('synced','superseded') and created_at<now()-interval '30 days'; get diagnostics v_outbox=row_count;
  delete from private.integration_events where created_at<now()-interval '90 days'; get diagnostics v_integration=row_count;
  delete from private.reliability_probe_events where checked_at<now()-interval '30 days'; get diagnostics v_reliability=row_count;
  delete from private.frontend_performance_samples where measured_at<now()-interval '30 days'; get diagnostics v_perf=row_count;
  delete from private.release_validation_runs where created_at<now()-interval '365 days'; get diagnostics v_release=row_count;
  return jsonb_build_object('archive_anonymized',v_archive,'audit_deleted',v_audit,'rate_limit_deleted',v_rl,'outbox_deleted',v_outbox,'integration_deleted',v_integration,'reliability_deleted',v_reliability,'performance_deleted',v_perf,'release_validation_deleted',v_release);
end
$$;
revoke all on function private.maintenance_retention_cleanup() from public,anon,authenticated;
grant execute on function private.maintenance_retention_cleanup() to service_role;
