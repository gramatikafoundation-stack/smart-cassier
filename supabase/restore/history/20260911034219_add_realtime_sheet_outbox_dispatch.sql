-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911034219  Name: add_realtime_sheet_outbox_dispatch
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.dispatch_sheet_sync_event()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_enabled boolean;
  v_writer_url text;
begin
  select enabled, writer_url into v_enabled, v_writer_url
  from public.sheet_sync_config where id=1;

  if coalesce(v_enabled,false) is not true or coalesce(v_writer_url,'')='' then
    return new;
  end if;

  perform net.http_post(
    url := 'http://127.0.0.1:54321/functions/v1/rohmat-sheet-sync-dispatch-v1',
    body := jsonb_build_object('event_id',new.event_id,'idempotency_key',new.idempotency_key),
    headers := jsonb_build_object('Content-Type','application/json'),
    timeout_milliseconds := 1000
  );
  return new;
exception when others then
  return new;
end
$function$;

drop trigger if exists trg_sheet_sync_outbox_dispatch on public.sheet_sync_outbox;
create trigger trg_sheet_sync_outbox_dispatch
after insert on public.sheet_sync_outbox
for each row execute function private.dispatch_sheet_sync_event();
