create or replace function public.master_prototype_runtime_context(
  p_tenant_id uuid default null,
  p_origin text default null,
  p_app_kind text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v jsonb;
  v_origin jsonb;
  v_enforce boolean;
  v_ref uuid;
begin
  if p_app_kind is not null and p_app_kind not in ('public','admin','kds') then
    return jsonb_build_object('ok',false,'error','invalid_app_kind');
  end if;

  if p_tenant_id is not null then
    select public.master_prototype_tenant_context(p_tenant_id) into v;
    if not coalesce((v->>'ok')::boolean,false) then
      return jsonb_build_object('ok',false,'error','tenant_not_resolved');
    end if;

    if nullif(trim(coalesce(p_origin,'')),'') is not null then
      select public.master_prototype_resolve_origin(p_origin,p_app_kind) into v_origin;
      if not coalesce((v_origin->>'ok')::boolean,false) then
        return jsonb_build_object('ok',false,'error','origin_not_registered');
      end if;
      if (v_origin->>'tenant_id')::uuid<>p_tenant_id then
        return jsonb_build_object('ok',false,'error','origin_tenant_mismatch');
      end if;
      return v || jsonb_build_object(
        'resolution','explicit_tenant_id+registered_origin',
        'resolved_origin',v_origin->>'resolved_origin',
        'origin_verified',true,
        'compat_fallback',false
      );
    end if;

    return v || jsonb_build_object(
      'resolution','explicit_tenant_id',
      'origin_verified',false,
      'compat_fallback',false
    );
  end if;

  if nullif(trim(coalesce(p_origin,'')),'') is not null then
    select public.master_prototype_resolve_origin(p_origin,p_app_kind) into v;
    if coalesce((v->>'ok')::boolean,false) then
      return v || jsonb_build_object(
        'resolution','registered_origin',
        'origin_verified',true,
        'compat_fallback',false
      );
    end if;
    return v;
  end if;

  select enforce_client_rls into v_enforce
  from private.platform_tenancy_state where id=1;

  if coalesce(v_enforce,false) then
    return jsonb_build_object('ok',false,'error','explicit_tenant_required');
  end if;

  v_ref:=private.reference_tenant_id();
  select public.master_prototype_tenant_context(v_ref) into v;
  if coalesce((v->>'ok')::boolean,false) then
    return v || jsonb_build_object(
      'resolution','reference_compatibility_bridge',
      'origin_verified',false,
      'compat_fallback',true
    );
  end if;
  return jsonb_build_object('ok',false,'error','reference_tenant_unavailable');
end
$$;

revoke all on function public.master_prototype_runtime_context(uuid,text,text) from public,anon,authenticated;
grant execute on function public.master_prototype_runtime_context(uuid,text,text) to service_role;

comment on function public.master_prototype_runtime_context(uuid,text,text) is
  'Service-role runtime resolver. Under client RLS enforcement all runtimes require explicit tenant ID or registered origin; no reference-tenant implicit fallback is permitted.';
