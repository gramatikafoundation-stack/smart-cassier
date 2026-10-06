-- Preserve existing Design System top-level scopes on partial published writes.
-- Rollbacks remain exact historical restores.
create or replace function private.tenant_design_system_apply_payload(
  p_tenant_id uuid,
  p_actor text,
  p_payload jsonb,
  p_kind text,
  p_restored_from bigint default null
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

  v_payload:=p_payload-'expectedPublishedVersionId';

  -- A normal publish may be scoped/partial. Preserve top-level scopes that
  -- were not supplied by the writer. Explicitly supplied keys still replace
  -- their corresponding scope. Rollback must remain an exact restore.
  if p_kind='published' then
    v_payload:=coalesce(v_state->'published','{}'::jsonb) || v_payload;
  end if;

  v_payload:=v_payload||jsonb_build_object(
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

-- Surgical recovery for Rohmat Nasi Uduk:
-- preserve current theme, restore the last validated General typography and
-- Admin Login brand-title override that were lost by the partial publish.
do $$
declare
  v_tenant constant uuid:='d8bb901c-7399-485b-8743-b319fde148ac'::uuid;
  v_state jsonb;
  v_current bigint;
  v_hist_general jsonb;
  v_hist_brand jsonb;
  v_patch jsonb;
  v_result jsonb;
  v_changed boolean:=false;
begin
  select coalesce(settings->'design_system','{}'::jsonb)
    into v_state
    from private.tenant_runtime_config
   where tenant_id=v_tenant and enabled
   for update;

  if v_state is null then return; end if;

  v_current:=case
    when coalesce(v_state->>'publishedVersionId','')~'^[0-9]+$'
      then (v_state->>'publishedVersionId')::bigint
    else 0
  end;

  select payload->'general'
    into v_hist_general
    from private.tenant_design_system_versions
   where tenant_id=v_tenant
     and kind='published'
     and jsonb_typeof(payload->'general')='object'
     and coalesce(payload#>>'{general,typography,family}','')<>''
   order by id desc
   limit 1;

  select payload#>'{elements,admin,login,brand_title}'
    into v_hist_brand
    from private.tenant_design_system_versions
   where tenant_id=v_tenant
     and kind='published'
     and jsonb_typeof(payload#>'{elements,admin,login,brand_title,typography}')='object'
   order by id desc
   limit 1;

  v_patch:=jsonb_build_object('expectedPublishedVersionId',v_current);

  if coalesce(v_state#>'{published,general}','{}'::jsonb)='{}'::jsonb
     and coalesce(v_hist_general,'{}'::jsonb)<>'{}'::jsonb then
    v_patch:=v_patch||jsonb_build_object('general',v_hist_general);
    v_changed:=true;
  end if;

  if jsonb_typeof(v_state#>'{published,elements,admin,login,brand_title,typography}') is null
     and coalesce(v_hist_brand,'{}'::jsonb)<>'{}'::jsonb then
    v_patch:=jsonb_set(
      v_patch,
      '{elements}',
      jsonb_build_object(
        'admin',jsonb_build_object(
          'login',jsonb_build_object(
            'brand_title',v_hist_brand
          )
        )
      ),
      true
    );
    v_changed:=true;
  end if;

  if v_changed then
    v_result:=private.tenant_design_system_apply_payload(
      v_tenant,
      'system-repair-preserve-scopes-v1',
      v_patch,
      'published',
      null
    );
    if coalesce((v_result->>'ok')::boolean,false) is not true then
      raise exception 'design system repair failed: %',v_result;
    end if;
  end if;
end
$$;
