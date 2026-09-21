-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912175643  Name: privacy_retention_governance_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.data_retention_policy (
  policy_key text primary key,
  data_class text not null,
  location text not null,
  retention_days integer check(retention_days is null or retention_days>0),
  action text not null check(action in ('retain','delete','anonymize','external_delete_required')),
  enabled boolean not null default true,
  rationale text not null,
  updated_at timestamptz not null default now()
);
alter table private.data_retention_policy enable row level security;
drop policy if exists data_retention_policy_deny_clients on private.data_retention_policy;
create policy data_retention_policy_deny_clients on private.data_retention_policy for all to anon,authenticated using(false) with check(false);
revoke all on private.data_retention_policy from public,anon,authenticated;
grant select on private.data_retention_policy to service_role;

insert into private.data_retention_policy(policy_key,data_class,location,retention_days,action,rationale) values
('active_orders','operational_transaction','public.orders',null,'retain','Active orders are governed by terminal-state archive logic rather than age-only deletion.'),
('archive_customer_pii','personal_data','public.order_history_archive.customer_name/customer_whatsapp/customer_note/verified_by_email',365,'anonymize','Retain financial/order facts while removing directly identifying customer/staff contact fields after one year.'),
('payment_proof_db_metadata','sensitive_payment_evidence','public.order_history_archive.payment_proof_url/proof_ocr_text/payment_proof_sha256',365,'anonymize','Remove proof references and OCR/hash metadata from long-term relational archive after one year.'),
('payment_proof_storage','sensitive_payment_evidence','storage:rohmat-payment-proofs',90,'external_delete_required','Physical object deletion must use Supabase Storage API; database metadata nulling is not treated as file deletion.'),
('security_audit_hot','security_telemetry','public.security_audit_events',90,'delete','Existing hot audit retention.'),
('sheet_outbox_terminal','integration_telemetry','public.sheet_sync_outbox:synced/superseded',30,'delete','Existing terminal outbox retention.'),
('integration_events','integration_telemetry','private.integration_events',90,'delete','Retain correlation evidence long enough for operational investigations.'),
('reliability_probe_events','availability_telemetry','private.reliability_probe_events',30,'delete','Keep one month of raw availability samples; higher-level SLO state remains derived.'),
('frontend_performance_samples','performance_telemetry','private.frontend_performance_samples',30,'delete','Keep one month of frontend performance samples.'),
('release_validation_runs','deployment_telemetry','private.release_validation_runs',365,'delete','Retain release certification evidence for one year.'),
('google_sheets_pii','reporting_mirror','Google Sheets yearly workbooks',365,'external_delete_required','Sheets is a reporting mirror; PII retention needs writer-side enforcement and cannot be claimed from PostgreSQL alone.')
on conflict(policy_key) do update set data_class=excluded.data_class,location=excluded.location,retention_days=excluded.retention_days,action=excluded.action,rationale=excluded.rationale,updated_at=now();

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
  select count(*) into v_perf_due from private.frontend_performance_samples where observed_at<now()-interval '30 days';
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
  delete from private.frontend_performance_samples where observed_at<now()-interval '30 days'; get diagnostics v_perf=row_count;
  delete from private.release_validation_runs where created_at<now()-interval '365 days'; get diagnostics v_release=row_count;
  return jsonb_build_object('archive_anonymized',v_archive,'audit_deleted',v_audit,'rate_limit_deleted',v_rl,'outbox_deleted',v_outbox,'integration_deleted',v_integration,'reliability_deleted',v_reliability,'performance_deleted',v_perf,'release_validation_deleted',v_release);
end
$$;
revoke all on function private.maintenance_retention_cleanup() from public,anon,authenticated;
grant execute on function private.maintenance_retention_cleanup() to service_role;
