-- ROHMAT MASTER PROTOTIPE v1
-- Controlled compatibility bridge for zero-downtime Edge cutover.
-- Implicit reference fallback is permitted only while enforce_client_rls=false.

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
  v_enforce boolean;
  v_ref uuid;
begin
  if p_tenant_id is not null then
    select public.master_prototype_tenant_context(p_tenant_id) into v;
    if coalesce((v->>'ok')::boolean,false) then
      return v || jsonb_build_object('resolution','explicit_tenant_id','compat_fallback',false);
    end if;
    return jsonb_build_object('ok',false,'error','tenant_not_resolved');
  end if;

  if nullif(trim(coalesce(p_origin,'')),'') is not null then
    select public.master_prototype_resolve_origin(p_origin,p_app_kind) into v;
    if coalesce((v->>'ok')::boolean,false) then
      return v || jsonb_build_object('resolution','registered_origin','compat_fallback',false);
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
      'compat_fallback',true
    );
  end if;
  return jsonb_build_object('ok',false,'error','reference_tenant_unavailable');
end
$$;

revoke all on function public.master_prototype_runtime_context(uuid,text,text) from public,anon,authenticated;
grant execute on function public.master_prototype_runtime_context(uuid,text,text) to service_role;

comment on function public.master_prototype_runtime_context(uuid,text,text) is
  'Service-role runtime resolver for staged Edge cutover. Reference fallback exists only while private.platform_tenancy_state.enforce_client_rls=false and becomes fail-closed automatically after final enforcement.';
