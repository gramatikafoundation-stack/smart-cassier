-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912113744  Name: sheet_sync_dispatch_auth_binding_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.dispatch_sheet_sync_event()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_enabled boolean;
  v_writer_url text;
  v_token text;
begin
  select enabled,writer_url into v_enabled,v_writer_url from public.sheet_sync_config where id=1;
  if coalesce(v_enabled,false) is not true or coalesce(v_writer_url,'')='' then return new; end if;
  select decrypted_secret into v_token from vault.decrypted_secrets where name='rohmat_sheet_sync_cron_token_v2' limit 1;
  if coalesce(v_token,'')='' then return new; end if;
  perform net.http_post(
    url:='http://127.0.0.1:54321/functions/v1/rohmat-sheet-sync-dispatch-v1',
    body:=jsonb_build_object('event_id',new.event_id,'idempotency_key',new.idempotency_key,'request_id',new.request_id),
    headers:=jsonb_build_object('Content-Type','application/json','X-Rohmat-Cron-Token',v_token),
    timeout_milliseconds:=1000
  );
  return new;
exception when others then return new;
end
$$;
revoke all on function private.dispatch_sheet_sync_event() from public,anon,authenticated;
