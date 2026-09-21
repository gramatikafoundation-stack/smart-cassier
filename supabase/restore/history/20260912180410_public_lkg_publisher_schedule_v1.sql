-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912180410  Name: public_lkg_publisher_schedule_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.invoke_public_lkg_publisher()
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare v_token text; v_id bigint;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name='rohmat_sheet_sync_cron_token_v2' limit 1;
  if coalesce(v_token,'')='' then raise exception 'internal_credential_unavailable'; end if;
  select net.http_get(
    url=>'http://127.0.0.1:54321/functions/v1/rohmat-static-publisher-v1',
    headers=>jsonb_build_object('x-rohmat-maintenance-token',v_token,'User-Agent','Rohmat-LKG-Cron/1.0'),
    timeout_milliseconds=>20000
  ) into v_id;
  return v_id;
end
$$;
revoke all on function private.invoke_public_lkg_publisher() from public,anon,authenticated;
grant execute on function private.invoke_public_lkg_publisher() to service_role;

do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname='rohmat_public_lkg_publish';
exception when others then null; end $$;
select cron.schedule('rohmat_public_lkg_publish','2,7,12,17,22,27,32,37,42,47,52,57 * * * *','select private.invoke_public_lkg_publisher();');

update private.release_component_registry
set display_name='Public Last-Known-Good Publisher', expected_version='v6', expected_sha256='ddb236f8d967624699978faeeeb312cd953d46f85b29bc16071bd308a5355125', rollback_ref='edge:rohmat-static-publisher-v1:v5-retired-410', lifecycle='compatibility', critical=true, last_verified_at=now(), notes='Internal Vault-authenticated publisher refreshes public-lkg-v1.html only from a validated primary renderer response.'
where component_key='retired_static_publisher';

update private.remediation_program
set status='in_progress', blocker='Full static/CDN primary delivery still requires editable Vercel source; however live renderer now has validated Storage LKG fallback.', evidence=jsonb_build_object('lkg_db','active','lkg_storage','rohmat-static/public-lkg-v1.html','forced_fallback','PASS HTTP 200 / 80946 bytes','publisher','internal Vault-authenticated v6 / 5-minute schedule'), updated_at=now()
where stage_no=2;

update private.remediation_program
set status='in_progress', blocker='Physical payment-proof deletion and Google Sheets PII retention still require external-system enforcement.', evidence=jsonb_build_object('policies',11,'database_retention','PASS','external_enforcement_pending',2,'cleanup_latest','20 expired rate-limit rows removed; no transactional PII due'), updated_at=now()
where stage_no=11;
