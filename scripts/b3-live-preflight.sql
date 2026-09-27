-- SMART ORDER B3 live preflight. Read-only assertions before the final evidence seal.

do $$
declare
  v_tenant uuid;
begin
  select reference_tenant_id into v_tenant
  from private.platform_prototypes
  where prototype_key='smart-order-sdb-platform-v1' and status='draft'
  limit 1;

  if v_tenant is null then raise exception 'b3_candidate_draft_missing'; end if;
  if not coalesce((private.smart_order_b3_reliability_readiness_v1(v_tenant)->>'ok')::boolean,false)
    then raise exception 'b3_release_reliability_not_ready'; end if;
  if not coalesce((private.frontend_performance_summary()->>'ok')::boolean,false)
    then raise exception 'b3_performance_not_ready'; end if;
  if not coalesce((private.frontend_ux_contract_status()->>'ok')::boolean,false)
    then raise exception 'b3_ux_not_ready'; end if;
  if not coalesce((private.integration_contract_status()->>'ok')::boolean,false)
    then raise exception 'b3_integration_not_ready'; end if;
  if not coalesce((private.smart_order_sheet_readiness_v1(v_tenant)->>'ok')::boolean,false)
    then raise exception 'b3_sheet_readiness_not_ready'; end if;
  if not coalesce((public.master_runtime_security_health_v1(v_tenant)->>'ok')::boolean,false)
    then raise exception 'b3_runtime_security_not_ready'; end if;
  if exists(
    select 1 from public.sheet_sync_outbox
    where tenant_id=v_tenant
      and (
        status in ('failed','dead')
        or (status in ('pending','processing') and created_at<now()-interval '5 minutes')
      )
  ) then raise exception 'b3_outbox_blocker_present'; end if;
end $$;

select jsonb_build_object(
  'ok',true,
  'contract','smart-order-b3-live-preflight-v1',
  'candidate_status',(select status from private.platform_prototypes where prototype_key='smart-order-sdb-platform-v1'),
  'release_reliability',private.smart_order_b3_reliability_readiness_v1(
    (select reference_tenant_id from private.platform_prototypes where prototype_key='smart-order-sdb-platform-v1')
  ),
  'performance',private.frontend_performance_summary(),
  'ux',private.frontend_ux_contract_status(),
  'integration',private.integration_contract_status(),
  'sheet_readiness',private.smart_order_sheet_readiness_v1(
    (select reference_tenant_id from private.platform_prototypes where prototype_key='smart-order-sdb-platform-v1')
  ),
  'runtime_security',public.master_runtime_security_health_v1(
    (select reference_tenant_id from private.platform_prototypes where prototype_key='smart-order-sdb-platform-v1')
  )
) b3_live_preflight;
