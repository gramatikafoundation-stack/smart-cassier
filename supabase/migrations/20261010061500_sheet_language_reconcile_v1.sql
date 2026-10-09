create or replace function private.enqueue_sheet_language_reconciliation()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_old_locale text := coalesce(old.settings->'language_settings'->>'default', old.settings->'language'->>'code', 'id-ID');
  v_new_locale text := coalesce(new.settings->'language_settings'->>'default', new.settings->'language'->>'code', 'id-ID');
  v_request uuid := gen_random_uuid();
begin
  if v_new_locale is not distinct from v_old_locale then
    return new;
  end if;
  if not new.enabled then
    return new;
  end if;
  insert into public.sheet_sync_outbox(
    request_id,idempotency_key,entity_type,entity_id,operation,target_year,
    affected_tabs,payload,source_updated_at,tenant_id
  ) values (
    v_request,
    'locale-reconcile:'||new.tenant_id::text||':'||v_new_locale||':'||replace(extract(epoch from clock_timestamp())::text,'.',''),
    'system','language:'||v_new_locale,'RECONCILE',null,
    '["DASHBOARD","PEMESAN","PESANAN","MENU & STOK","KEUANGAN"]'::jsonb,
    jsonb_build_object(
      'reason','language_changed',
      'tenant_id',new.tenant_id,
      'locale',v_new_locale,
      'contract','sheet-i18n-v1'
    ),
    now(),new.tenant_id
  );
  return new;
end
$function$;

drop trigger if exists trg_sheet_language_reconcile on private.tenant_runtime_config;
create trigger trg_sheet_language_reconcile
after update of settings on private.tenant_runtime_config
for each row execute function private.enqueue_sheet_language_reconciliation();

comment on function private.enqueue_sheet_language_reconciliation()
is 'Enqueues a tenant-scoped full Sheets reconciliation whenever the canonical language locale changes; technical tab contracts remain stable.';