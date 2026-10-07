create or replace function private.enqueue_sheet_reconciliation()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_minutes integer := 10;
  v_bucket text;
  v_epoch bigint;
  v_inserted integer := 0;
begin
  select greatest(5, least(60, coalesce(s.reconciliation_minutes, 10)))
    into v_minutes
  from public.sheet_sync_config s
  where s.id = 1;

  v_minutes := coalesce(v_minutes, 10);
  v_epoch := floor(extract(epoch from now()) / (v_minutes * 60))::bigint;
  v_bucket := to_char(now() at time zone 'UTC', 'YYYYMMDDHH24') || ':' || v_epoch::text;

  insert into public.sheet_sync_outbox(
    request_id,
    idempotency_key,
    entity_type,
    entity_id,
    operation,
    target_year,
    affected_tabs,
    payload,
    source_updated_at,
    tenant_id
  )
  select
    gen_random_uuid(),
    'reconcile:tenant:' || w.tenant_id::text || ':all:' || v_bucket,
    'system',
    'all-years',
    'RECONCILE',
    null,
    '["DASHBOARD","PEMESAN","PESANAN","MENU & STOK","KEUANGAN"]'::jsonb,
    jsonb_build_object(
      'reason', 'periodic_reconciliation',
      'tenant_id', w.tenant_id,
      'target_year', null,
      'bucket', v_bucket,
      'interval_minutes', v_minutes,
      'contract', 'tenant-aware-v1'
    ),
    now(),
    w.tenant_id
  from private.tenant_writer_config w
  join private.platform_tenants t
    on t.id = w.tenant_id
   and t.status = 'active'
  join private.tenant_runtime_config r
    on r.tenant_id = w.tenant_id
   and r.enabled
  where w.enabled
    and coalesce(w.writer_url, '') <> ''
    and exists (
      select 1
      from private.tenant_sheet_targets st
      where st.tenant_id = w.tenant_id
        and st.enabled
    )
  on conflict (idempotency_key) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end
$function$;

comment on function private.enqueue_sheet_reconciliation()
is 'Tenant-aware periodic reconciliation enqueue. Uses active tenant writer/runtime/targets; the deprecated global sheet_sync_config.enabled flag no longer gates production reconciliation.';
