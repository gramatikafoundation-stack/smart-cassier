-- SMART ORDER B2.3 final cutover: fail-closed tenancy, signed QR, legacy RPC closure and health gate
begin;

-- Resolve the master candidate by stable prototype key; do not hardcode generated tenant IDs.
do $$
declare
  v_tenant uuid;
  v_table_count integer;
  v_signature_count integer;
  v_site_id integer;
begin
  select reference_tenant_id into v_tenant
  from private.platform_prototypes
  where prototype_key='smart-order-sdb-platform-v1'
  limit 1;

  if v_tenant is null then raise exception 'smart_order_candidate_missing'; end if;

  select table_count into v_table_count
  from private.tenant_runtime_config
  where tenant_id=v_tenant and enabled;

  if v_table_count is null or v_table_count<1 then
    raise exception 'tenant_runtime_unavailable';
  end if;

  select count(*) into v_signature_count
  from private.tenant_table_qr_signatures q
  where q.tenant_id=v_tenant
    and q.is_active
    and q.table_number between 1 and v_table_count
    and q.signature_hash ~ '^[a-f0-9]{64}$';

  if v_signature_count<>v_table_count then
    raise exception 'signed_qr_precondition_failed expected %, got %',v_table_count,v_signature_count;
  end if;

  update private.tenant_runtime_config
  set require_table_qr_signature=true,
      settings=coalesce(settings,'{}'::jsonb)
        || jsonb_build_object('require_table_qr_signature',true)
        || jsonb_build_object(
          'security_contract',jsonb_build_object(
            'version','smart-order-master-runtime-security-v2',
            'hardened_at',now(),
            'client_rls','required',
            'admin_session_ttl_hours',6,
            'kds_session_ttl_hours',4,
            'admin_gateway_fingerprint_binding',true,
            'kds_fingerprint_binding',true,
            'signed_table_qr',true,
            'legacy_internal_rpc_direct_access',false
          )
        ),
      updated_at=now()
  where tenant_id=v_tenant;

  select nullif(t.metadata->>'legacy_site_settings_id','')::integer into v_site_id
  from private.platform_tenants t where t.id=v_tenant;

  if v_site_id is null then raise exception 'legacy_site_settings_id_missing'; end if;

  update public.site_settings
  set require_table_qr_signature=true,updated_at=now()
  where id=v_site_id;

  if not exists(
    select 1 from public.tenant_site_settings_public_v1
    where tenant_id=v_tenant and require_table_qr_signature
  ) then raise exception 'tenant_public_settings_qr_sync_failed'; end if;

  if not exists(
    select 1 from public.site_settings_public_v2
    where id=v_site_id and require_table_qr_signature
  ) then raise exception 'public_v2_qr_sync_failed'; end if;

  update private.platform_prototypes
  set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'freeze_state','candidate_b2',
        'b2_cutover_state','pending_final_validation',
        'b2_security_contract','smart-order-master-runtime-security-v2',
        'b2_signed_table_qr',true,
        'b2_edge_versions',jsonb_build_object(
          'secure_api','v6',
          'admin_media_upload','v3',
          'admin_order_history','v3'
        )
      ),
      updated_at=now()
  where prototype_key='smart-order-sdb-platform-v1'
    and status='draft';
end $$;

-- Freeze tenant RLS in fail-closed mode.
update private.platform_tenancy_state
set enforce_client_rls=true,
    active_contract='smart-order-master-runtime-security-v2',
    updated_at=now()
where id=1;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='private.platform_tenancy_state'::regclass
      and conname='platform_tenancy_enforced_b2'
  ) then
    alter table private.platform_tenancy_state
      add constraint platform_tenancy_enforced_b2
      check (enforce_client_rls is true);
  end if;
end $$;

-- Remove direct anonymous access to legacy privileged internals.
revoke usage on schema internal_rpc from public, anon, authenticated;
revoke execute on all functions in schema internal_rpc from public, anon, authenticated;
grant usage on schema internal_rpc to service_role;
grant execute on all functions in schema internal_rpc to service_role;
alter default privileges in schema internal_rpc revoke execute on functions from public;

-- Pin the B2 Edge runtime versions that were deployed and verified before this cutover.
update private.production_change_control
set baseline_version=case component
      when 'secure-api' then 'v6'
      when 'admin-media-upload' then 'v3'
      when 'admin-order-history' then 'v3'
      else baseline_version end,
    baseline_sha256=case component
      when 'secure-api' then '8ac9fb58b974bebb1ddeb9fd7ee4f4a12c85ed1eeb5c4f052b75880cefa9983c'
      when 'admin-media-upload' then '537c05722bda48791e4a39aabd34a92df2692ef93207b8372f2dc80986b5183f'
      when 'admin-order-history' then 'e06762359fb344751915575afc3c71b3381c82f66366de147ec7cb60d0f7043a'
      else baseline_sha256 end,
    note=coalesce(note,'') || E'\nB2 runtime/security hardening: fingerprint-bound Admin auth and scope isolation.',
    updated_at=now()
where component in ('secure-api','admin-media-upload','admin-order-history');

update private.release_component_registry
set expected_version=case component_key
      when 'secure_api' then 'v6'
      when 'admin_media_upload' then 'v3'
      when 'admin_order_history' then 'v3'
      else expected_version end,
    expected_sha256=case component_key
      when 'secure_api' then '8ac9fb58b974bebb1ddeb9fd7ee4f4a12c85ed1eeb5c4f052b75880cefa9983c'
      when 'admin_media_upload' then '537c05722bda48791e4a39aabd34a92df2692ef93207b8372f2dc80986b5183f'
      when 'admin_order_history' then 'e06762359fb344751915575afc3c71b3381c82f66366de147ec7cb60d0f7043a'
      else expected_sha256 end,
    deployment_ref=case component_key
      when 'secure_api' then 'edge-version:v6'
      when 'admin_media_upload' then 'edge-version:v3'
      when 'admin_order_history' then 'edge-version:v3'
      else deployment_ref end,
    rollback_ref=case component_key
      when 'secure_api' then 'edge-version:v5'
      when 'admin_media_upload' then 'edge-version:v2'
      when 'admin_order_history' then 'edge-version:v2'
      else rollback_ref end,
    last_verified_at=now(),
    notes=coalesce(notes,'') || E'\nB2 fingerprint/session-scope hardening runtime pin.'
where component_key in ('secure_api','admin_media_upload','admin_order_history');

-- Service-role-only executable freeze health contract.
create or replace function public.master_runtime_security_health_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  c private.tenant_runtime_config%rowtype;
  v_hardened_at timestamptz;
  v_rls_off integer;
  v_anon_internal integer;
  v_canonical_aliases integer;
  v_enabled_previews integer;
  v_qr_valid integer;
  v_tenant_null_sessions integer;
  v_bad_kds_fp integer;
  v_new_admin_unbound integer;
  v_new_bad_ttl integer;
  v_routes_ok boolean;
  v_candidate_draft boolean;
  v_client_rls boolean;
  v_ok boolean;
begin
  select * into c from private.tenant_runtime_config
  where tenant_id=p_tenant_id and enabled;

  if c.tenant_id is null then
    return jsonb_build_object('ok',false,'error','tenant_unavailable');
  end if;

  begin
    v_hardened_at:=(c.settings->'security_contract'->>'hardened_at')::timestamptz;
  exception when others then
    v_hardened_at:=null;
  end;

  select count(*) into v_rls_off
  from pg_class pc join pg_namespace pn on pn.oid=pc.relnamespace
  where pn.nspname in ('public','private')
    and pc.relkind='r'
    and not pc.relrowsecurity;

  select count(*) into v_anon_internal
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='internal_rpc'
    and p.prokind='f'
    and has_function_privilege('anon',p.oid,'EXECUTE');

  select count(*) into v_canonical_aliases
  from private.tenant_origin_aliases
  where tenant_id=p_tenant_id and enabled and alias_kind='canonical';

  select count(*) into v_enabled_previews
  from private.tenant_origin_aliases
  where tenant_id=p_tenant_id and enabled and alias_kind='preview';

  select count(*) into v_qr_valid
  from private.tenant_table_qr_signatures
  where tenant_id=p_tenant_id
    and is_active
    and table_number between 1 and c.table_count
    and signature_hash ~ '^[a-f0-9]{64}$';

  select count(*) into v_tenant_null_sessions
  from private.admin_sessions where tenant_id is null;

  select count(*) into v_bad_kds_fp
  from private.admin_sessions
  where expires_at>now() and session_scope='kds' and client_fingerprint_hash is null;

  select count(*) into v_new_admin_unbound
  from private.admin_sessions
  where v_hardened_at is not null
    and created_at>=v_hardened_at
    and session_scope='admin'
    and client_fingerprint_hash is null;

  select count(*) into v_new_bad_ttl
  from private.admin_sessions
  where v_hardened_at is not null
    and created_at>=v_hardened_at
    and expires_at>created_at+interval '6 hours';

  select enforce_client_rls into v_client_rls
  from private.platform_tenancy_state where id=1;

  v_routes_ok :=
    coalesce((public.master_prototype_runtime_context(null,c.public_origin,'public')->>'ok')::boolean,false)
    and public.master_prototype_runtime_context(null,c.public_origin,'public')->>'surface_route'='/'
    and coalesce((public.master_prototype_runtime_context(null,c.public_origin,'admin')->>'ok')::boolean,false)
    and public.master_prototype_runtime_context(null,c.public_origin,'admin')->>'surface_route'='/admin'
    and coalesce((public.master_prototype_runtime_context(null,c.public_origin,'kds')->>'ok')::boolean,false)
    and public.master_prototype_runtime_context(null,c.public_origin,'kds')->>'surface_route'='/kds'
    and coalesce((public.master_prototype_runtime_context(null,c.public_origin,'database')->>'ok')::boolean,false)
    and public.master_prototype_runtime_context(null,c.public_origin,'database')->>'surface_route'='/database';

  select exists(
    select 1 from private.platform_prototypes
    where reference_tenant_id=p_tenant_id
      and prototype_key='smart-order-sdb-platform-v1'
      and status='draft'
  ) into v_candidate_draft;

  v_ok :=
    v_rls_off=0
    and v_anon_internal=0
    and coalesce(v_client_rls,false)
    and c.public_origin=c.admin_origin
    and c.public_origin=c.kds_origin
    and c.public_origin=c.settings->>'canonical_origin'
    and c.require_table_qr_signature
    and coalesce((c.settings->>'require_table_qr_signature')::boolean,false)
    and v_canonical_aliases=1
    and v_enabled_previews=0
    and v_qr_valid=c.table_count
    and v_tenant_null_sessions=0
    and v_bad_kds_fp=0
    and v_new_admin_unbound=0
    and v_new_bad_ttl=0
    and v_routes_ok
    and v_candidate_draft
    and v_hardened_at is not null;

  return jsonb_build_object(
    'ok',v_ok,
    'contract','smart-order-master-runtime-security-v2',
    'tenant_id',p_tenant_id,
    'checks',jsonb_build_object(
      'rls_off_tables',v_rls_off,
      'anon_internal_rpc_execute',v_anon_internal,
      'client_rls_enforced',coalesce(v_client_rls,false),
      'single_canonical_origin',c.public_origin=c.admin_origin and c.public_origin=c.kds_origin and c.public_origin=c.settings->>'canonical_origin',
      'canonical_aliases',v_canonical_aliases,
      'enabled_preview_aliases',v_enabled_previews,
      'signed_table_qr_required',c.require_table_qr_signature,
      'valid_active_table_signatures',v_qr_valid,
      'table_count',c.table_count,
      'tenant_null_sessions',v_tenant_null_sessions,
      'active_kds_without_fingerprint',v_bad_kds_fp,
      'post_cutover_admin_without_fingerprint',v_new_admin_unbound,
      'post_cutover_sessions_over_6h',v_new_bad_ttl,
      'four_surface_routes',v_routes_ok,
      'candidate_still_draft',v_candidate_draft,
      'hardened_at',v_hardened_at
    )
  );
end
$$;
revoke all on function public.master_runtime_security_health_v1(uuid) from public,anon,authenticated;
grant execute on function public.master_runtime_security_health_v1(uuid) to service_role;

commit;
