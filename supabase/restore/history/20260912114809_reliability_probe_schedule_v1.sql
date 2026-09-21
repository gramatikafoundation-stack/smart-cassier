-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912114809  Name: reliability_probe_schedule_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.invoke_reliability_probe()
returns bigint
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_token text;
  v_request_id bigint;
begin
  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name='rohmat_sheet_sync_cron_token_v2'
  limit 1;
  if coalesce(v_token,'')='' then raise exception 'cron credential unavailable'; end if;
  select net.http_post(
    url := 'http://127.0.0.1:54321/functions/v1/rohmat-env-capability-check-v1',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','X-Rohmat-Cron-Token',v_token),
    timeout_milliseconds := 1000
  ) into v_request_id;
  return v_request_id;
end
$function$;
revoke all on function private.invoke_reliability_probe() from public,anon,authenticated;
select cron.unschedule(jobid) from cron.job where jobname='rohmat_reliability_probe';
select cron.schedule('rohmat_reliability_probe','*/5 * * * *','select private.invoke_reliability_probe();');
