-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912183519  Name: storage_retention_enforcement_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.storage_retention_runs(
  id bigint generated always as identity primary key,
  run_at timestamptz not null default now(),
  due_count integer not null default 0 check (due_count>=0),
  deleted_count integer not null default 0 check (deleted_count>=0),
  error_count integer not null default 0 check (error_count>=0),
  test_object_deleted boolean not null default false
);
alter table private.storage_retention_runs enable row level security;
drop policy if exists storage_retention_runs_deny_all on private.storage_retention_runs;
create policy storage_retention_runs_deny_all on private.storage_retention_runs for all to public using (false) with check (false);
revoke all on private.storage_retention_runs from public, anon, authenticated;

create or replace function public.storage_retention_due_paths()
returns jsonb
language sql
security definer
set search_path=''
as $$
  select jsonb_build_object('paths',coalesce(jsonb_agg(x.name order by x.created_at),'[]'::jsonb))
  from (
    select o.name,o.created_at
    from storage.objects o
    where o.bucket_id='rohmat-payment-proofs'
      and o.created_at < now()-interval '90 days'
    order by o.created_at
    limit 500
  ) x
$$;
revoke all on function public.storage_retention_due_paths() from public,anon,authenticated;
grant execute on function public.storage_retention_due_paths() to service_role;

create or replace function public.storage_retention_record_run(p_due integer,p_deleted integer,p_errors integer,p_test_deleted boolean default false)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  insert into private.storage_retention_runs(due_count,deleted_count,error_count,test_object_deleted)
  values(greatest(coalesce(p_due,0),0),greatest(coalesce(p_deleted,0),0),greatest(coalesce(p_errors,0),0),coalesce(p_test_deleted,false));
  return jsonb_build_object('ok',true);
end
$$;
revoke all on function public.storage_retention_record_run(integer,integer,integer,boolean) from public,anon,authenticated;
grant execute on function public.storage_retention_record_run(integer,integer,integer,boolean) to service_role;

create or replace function private.invoke_storage_retention_worker()
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare v_token text; v_id bigint;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name='rohmat_sheet_sync_cron_token_v2' limit 1;
  if coalesce(v_token,'')='' then raise exception 'internal_credential_unavailable'; end if;
  select net.http_post(
    url=>'http://127.0.0.1:54321/functions/v1/rohmat-html-test-v1',
    headers=>jsonb_build_object('x-rohmat-maintenance-token',v_token,'content-type','application/json','User-Agent','Rohmat-Storage-Retention/1.0'),
    body=>'{}'::jsonb,
    timeout_milliseconds=>20000
  ) into v_id;
  return v_id;
end
$$;
revoke all on function private.invoke_storage_retention_worker() from public,anon,authenticated;

update private.data_retention_policy
set action='delete',
    rationale='Physical payment-proof objects are deleted through the authenticated Supabase Storage retention worker after 90 days.',
    updated_at=now()
where policy_key='payment_proof_storage';

create or replace function private.privacy_retention_status()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare v_archive_due bigint; v_audit_due bigint; v_integration_due bigint; v_reliability_due bigint; v_perf_due bigint; v_release_due bigint; v_storage_due bigint; v_external int; v_policies int; v_storage_last timestamptz; v_storage_errors int; v_storage_fresh boolean;
begin
  select count(*) into v_archive_due from public.order_history_archive where created_at<now()-interval '365 days' and (customer_name is distinct from 'Pelanggan' or customer_whatsapp is not null or customer_note is not null or verified_by_email is not null or payment_proof_url is not null or proof_ocr_text is not null or payment_proof_sha256 is not null);
  select count(*) into v_audit_due from public.security_audit_events where created_at<now()-interval '90 days';
  select count(*) into v_integration_due from private.integration_events where created_at<now()-interval '90 days';
  select count(*) into v_reliability_due from private.reliability_probe_events where checked_at<now()-interval '30 days';
  select count(*) into v_perf_due from private.frontend_performance_samples where measured_at<now()-interval '30 days';
  select count(*) into v_release_due from private.release_validation_runs where created_at<now()-interval '365 days';
  select count(*) into v_storage_due from storage.objects where bucket_id='rohmat-payment-proofs' and created_at<now()-interval '90 days';
  select run_at,error_count into v_storage_last,v_storage_errors from private.storage_retention_runs order by run_at desc limit 1;
  v_storage_fresh:=coalesce(v_storage_last>now()-interval '48 hours',false) and coalesce(v_storage_errors,1)=0;
  select count(*) into v_external from private.data_retention_policy where enabled and action='external_delete_required';
  select count(*) into v_policies from private.data_retention_policy where enabled;
  return jsonb_build_object(
    'ok_database',v_archive_due=0 and v_audit_due=0 and v_integration_due=0 and v_reliability_due=0 and v_perf_due=0 and v_release_due=0,
    'ok_storage',v_storage_due=0 and v_storage_fresh,
    'policies',v_policies,'external_enforcement_pending',v_external,
    'storage_last_run_at',v_storage_last,'storage_worker_fresh',v_storage_fresh,
    'due',jsonb_build_object('archive_anonymize',v_archive_due,'security_audit',v_audit_due,'integration_events',v_integration_due,'reliability_events',v_reliability_due,'performance_samples',v_perf_due,'release_validation',v_release_due,'payment_proof_storage',v_storage_due));
end
$$;

DO $$
declare j bigint;
begin
  select jobid into j from cron.job where jobname='rohmat_storage_retention_daily' limit 1;
  if j is not null then perform cron.unschedule(j); end if;
  perform cron.schedule('rohmat_storage_retention_daily','47 3 * * *','select private.invoke_storage_retention_worker();');
end $$;
