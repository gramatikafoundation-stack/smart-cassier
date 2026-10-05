-- Optimistic concurrency for tenant Design System publishes.
-- Prevent stale full-payload publishes from silently overwriting newer changes.

create or replace function private.tenant_design_system_apply_payload(
  p_tenant_id uuid,p_actor text,p_payload jsonb,p_kind text,p_restored_from bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_id bigint;
  v_theme jsonb;
  v_state jsonb;
  v_payload jsonb;
  v_expected bigint;
  v_current bigint;
begin
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    return jsonb_build_object('ok',false,'error','invalid_payload');
  end if;
  if p_kind not in ('published','rollback') then
    return jsonb_build_object('ok',false,'error','invalid_kind');
  end if;

  select coalesce(settings->'design_system','{}'::jsonb)
    into v_state
    from private.tenant_runtime_config
   where tenant_id=p_tenant_id and enabled
   for update;

  if not found then
    return jsonb_build_object('ok',false,'error','tenant_unavailable');
  end if;

  v_current:=case
    when coalesce(v_state->>'publishedVersionId','')~'^[0-9]+$'
      then (v_state->>'publishedVersionId')::bigint
    else 0
  end;

  if p_kind='published' and not (p_payload ? 'expectedPublishedVersionId') then
    return jsonb_build_object('ok',false,'error','design_system_expected_version_required','currentVersion',v_current);
  end if;

  if p_payload ? 'expectedPublishedVersionId' then
    if coalesce(p_payload->>'expectedPublishedVersionId','')!~'^[0-9]+$' then
      return jsonb_build_object('ok',false,'error','invalid_expected_version','currentVersion',v_current);
    end if;
    v_expected:=(p_payload->>'expectedPublishedVersionId')::bigint;
    if v_expected<>v_current then
      return jsonb_build_object(
        'ok',false,
        'error','design_system_conflict',
        'expectedVersion',v_expected,
        'currentVersion',v_current
      );
    end if;
  end if;

  v_payload:=(p_payload-'expectedPublishedVersionId')||jsonb_build_object(
    'status','published','publishedAt',now(),'publishedBy',coalesce(p_actor,'admin')
  );
  v_theme:=coalesce(v_payload->'theme','{}'::jsonb);

  insert into private.tenant_design_system_versions(
    tenant_id,kind,theme_id,theme_name,payload,created_by,restored_from
  ) values(
    p_tenant_id,p_kind,left(coalesce(v_theme->>'id','custom'),100),
    left(coalesce(v_theme->>'name','Custom Theme'),160),
    v_payload,left(coalesce(p_actor,'admin'),200),p_restored_from
  ) returning id into v_id;

  v_state:=v_state||jsonb_build_object(
    'version',3,
    'published',v_payload,
    'publishedVersionId',v_id,
    'updatedAt',now()
  );

  update private.tenant_runtime_config
     set settings=jsonb_set(coalesce(settings,'{}'::jsonb),'{design_system}',v_state,true),
         updated_at=now()
   where tenant_id=p_tenant_id and enabled;

  perform private.sync_tenant_public_settings_projection(p_tenant_id);
  return jsonb_build_object(
    'ok',true,
    'tenant_id',p_tenant_id,
    'versionId',v_id,
    'previousVersionId',v_current,
    'designSystem',v_state
  );
end
$$;

revoke all on function private.tenant_design_system_apply_payload(uuid,text,jsonb,text,bigint)
  from public,anon,authenticated;
grant execute on function private.tenant_design_system_apply_payload(uuid,text,jsonb,text,bigint)
  to service_role;

create or replace function private.tenant_design_base(p_tenant_id uuid,p_publish boolean)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
with s as (
  select coalesce(private.tenant_design_system_state(p_tenant_id),'{}'::jsonb) as state
)
select case
  when coalesce(p_publish,false) then
    coalesce(state->'published','{}'::jsonb)
    || jsonb_build_object(
      'expectedPublishedVersionId',
      case
        when coalesce(state->>'publishedVersionId','')~'^[0-9]+$'
          then (state->>'publishedVersionId')::bigint
        else 0
      end
    )
  else case
    when jsonb_typeof(state->'draft')='object'
      and coalesce(state->'draft','{}'::jsonb)<>'{}'::jsonb
      then state->'draft'
    else coalesce(state->'published','{}'::jsonb)
  end
end
from s
$$;

revoke all on function private.tenant_design_base(uuid,boolean)
  from public,anon,authenticated;
grant execute on function private.tenant_design_base(uuid,boolean)
  to service_role;
