-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911045347  Name: optimize_sheet_reconciliation_single_global_event
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.enqueue_sheet_reconciliation()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_enabled boolean;
  v_bucket text;
begin
  select enabled into v_enabled from public.sheet_sync_config where id=1;
  if coalesce(v_enabled,false) is false then return 0; end if;

  v_bucket := to_char(
    date_trunc('hour',now()) + floor(extract(minute from now())/10)*interval '10 minutes',
    'YYYYMMDDHH24MI'
  );

  insert into public.sheet_sync_outbox(
    idempotency_key,entity_type,entity_id,operation,target_year,affected_tabs,payload,source_updated_at
  ) values (
    'reconcile:all:'||v_bucket,
    'system','all-years','RECONCILE',null,
    '["DASHBOARD","PEMESAN","PESANAN","MENU & STOK","KEUANGAN"]'::jsonb,
    jsonb_build_object('reason','periodic_reconciliation','target_year',null,'bucket',v_bucket),
    now()
  ) on conflict (idempotency_key) do nothing;

  return case when found then 1 else 0 end;
end
$function$;
