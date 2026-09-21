-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909171711  Name: add_design_system_scope_overrides
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.admin_design_system_set_scope(
  p_token text,
  p_scope text,
  p_site text,
  p_page text,
  p_config jsonb,
  p_publish boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session jsonb;
  v_ds jsonb;
  v_base jsonb;
  v_target jsonb;
  v_typ jsonb := '{}'::jsonb;
  v_col jsonb := '{}'::jsonb;
  v_clean jsonb := '{}'::jsonb;
  v_path text[];
  v_email text;
  v_id bigint;
  v_family text;
  v_align text;
  v_color text;
  v_num numeric;
begin
  v_session := public.admin_password_session_info(p_token);
  if coalesce((v_session->>'ok')::boolean,false) is not true then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  if p_scope not in ('site','page') or p_site not in ('public','admin','kds','database') then
    return jsonb_build_object('ok',false,'error','invalid_scope');
  end if;
  if p_scope='page' and (coalesce(p_page,'') !~ '^[a-z0-9][a-z0-9-]{0,63}$') then
    return jsonb_build_object('ok',false,'error','invalid_page');
  end if;

  p_config := coalesce(p_config,'{}'::jsonb);
  v_family := p_config#>>'{typography,family}';
  if v_family in ('system-ui','Inter','Manrope','Segoe UI','Arial','Helvetica','Calibri','Georgia','Times New Roman','Garamond','Palatino Linotype','Courier New') then
    v_typ := v_typ || jsonb_build_object('family',v_family);
  end if;
  if (p_config#>>'{typography,size}') ~ '^-?[0-9]+([.][0-9]+)?$' then
    v_num := greatest(10,least(72,(p_config#>>'{typography,size}')::numeric));
    v_typ := v_typ || jsonb_build_object('size',v_num);
  end if;
  if (p_config#>>'{typography,weight}') ~ '^[0-9]+$' then
    v_num := greatest(300,least(900,(p_config#>>'{typography,weight}')::numeric));
    v_typ := v_typ || jsonb_build_object('weight',v_num);
  end if;
  if p_config#>'{typography,italic}' is not null then
    v_typ := v_typ || jsonb_build_object('italic',coalesce((p_config#>>'{typography,italic}')::boolean,false));
  end if;
  v_align := p_config#>>'{typography,align}';
  if v_align in ('left','center','right','justify') then
    v_typ := v_typ || jsonb_build_object('align',v_align);
  end if;
  if (p_config#>>'{typography,lineHeight}') ~ '^-?[0-9]+([.][0-9]+)?$' then
    v_num := greatest(1,least(2,(p_config#>>'{typography,lineHeight}')::numeric));
    v_typ := v_typ || jsonb_build_object('lineHeight',v_num);
  end if;
  if (p_config#>>'{typography,letterSpacing}') ~ '^-?[0-9]+([.][0-9]+)?$' then
    v_num := greatest(-2,least(6,(p_config#>>'{typography,letterSpacing}')::numeric));
    v_typ := v_typ || jsonb_build_object('letterSpacing',v_num);
  end if;

  foreach v_align in array array['text','background','primary','accent','panel','muted'] loop
    v_color := p_config#>>array['colors',v_align];
    if v_color ~* '^#[0-9a-f]{6}$' then
      v_col := v_col || jsonb_build_object(v_align,upper(v_color));
    end if;
  end loop;
  if v_typ <> '{}'::jsonb then v_clean := v_clean || jsonb_build_object('typography',v_typ); end if;
  if v_col <> '{}'::jsonb then v_clean := v_clean || jsonb_build_object('colors',v_col); end if;
  if v_clean='{}'::jsonb then return jsonb_build_object('ok',false,'error','empty_config'); end if;

  select coalesce(design_system,'{}'::jsonb) into v_ds from public.site_settings where id=1 for update;
  if p_publish then
    v_base := coalesce(v_ds->'published','{}'::jsonb);
  else
    v_base := case when jsonb_typeof(v_ds->'draft')='object' and coalesce(v_ds->'draft','{}'::jsonb) <> '{}'::jsonb then v_ds->'draft' else coalesce(v_ds->'published','{}'::jsonb) end;
  end if;
  v_path := case when p_scope='site' then array['sites',p_site] else array['pages',p_site,p_page] end;
  v_target := coalesce(v_base #> v_path,'{}'::jsonb);
  if v_clean ? 'typography' then
    v_target := jsonb_set(v_target,'{typography}',coalesce(v_target->'typography','{}'::jsonb) || (v_clean->'typography'),true);
  end if;
  if v_clean ? 'colors' then
    v_target := jsonb_set(v_target,'{colors}',coalesce(v_target->'colors','{}'::jsonb) || (v_clean->'colors'),true);
  end if;
  v_base := jsonb_set(v_base,v_path,v_target,true);
  v_email := coalesce(v_session->>'email','admin');

  if p_publish then
    v_base := v_base || jsonb_build_object('status','published','publishedAt',now(),'publishedBy',v_email);
    insert into public.design_system_versions(kind,theme_id,theme_name,payload,created_by)
    values('published',coalesce(v_base#>>'{theme,id}','custom'),coalesce(v_base#>>'{theme,name}','Custom'),v_base,v_email)
    returning id into v_id;
    v_ds := jsonb_set(v_ds,'{published}',v_base,true);
    v_ds := jsonb_set(v_ds,'{publishedVersionId}',to_jsonb(v_id),true);
    update public.site_settings set design_system=v_ds where id=1;
    return jsonb_build_object('ok',true,'published',true,'versionId',v_id,'scope',p_scope,'site',p_site,'page',p_page,'config',v_clean);
  else
    v_base := v_base || jsonb_build_object('status','draft','draftUpdatedAt',now(),'draftUpdatedBy',v_email);
    v_ds := jsonb_set(v_ds,'{draft}',v_base,true);
    update public.site_settings set design_system=v_ds where id=1;
    return jsonb_build_object('ok',true,'published',false,'scope',p_scope,'site',p_site,'page',p_page,'config',v_clean);
  end if;
end;
$$;

create or replace function public.admin_design_system_reset_scope(
  p_token text,
  p_scope text,
  p_site text,
  p_page text,
  p_publish boolean default true
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session jsonb;
  v_ds jsonb;
  v_base jsonb;
  v_target jsonb;
  v_path text[];
  v_email text;
  v_id bigint;
begin
  v_session := public.admin_password_session_info(p_token);
  if coalesce((v_session->>'ok')::boolean,false) is not true then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_scope not in ('site','page') or p_site not in ('public','admin','kds','database') then return jsonb_build_object('ok',false,'error','invalid_scope'); end if;
  if p_scope='page' and (coalesce(p_page,'') !~ '^[a-z0-9][a-z0-9-]{0,63}$') then return jsonb_build_object('ok',false,'error','invalid_page'); end if;
  select coalesce(design_system,'{}'::jsonb) into v_ds from public.site_settings where id=1 for update;
  if p_publish then v_base:=coalesce(v_ds->'published','{}'::jsonb); else v_base:=case when jsonb_typeof(v_ds->'draft')='object' and coalesce(v_ds->'draft','{}'::jsonb)<>'{}'::jsonb then v_ds->'draft' else coalesce(v_ds->'published','{}'::jsonb) end; end if;
  v_path := case when p_scope='site' then array['sites',p_site] else array['pages',p_site,p_page] end;
  v_target := coalesce(v_base #> v_path,'{}'::jsonb) - 'typography' - 'colors';
  v_base := jsonb_set(v_base,v_path,v_target,true);
  v_email:=coalesce(v_session->>'email','admin');
  if p_publish then
    v_base:=v_base||jsonb_build_object('status','published','publishedAt',now(),'publishedBy',v_email);
    insert into public.design_system_versions(kind,theme_id,theme_name,payload,created_by)
    values('published',coalesce(v_base#>>'{theme,id}','custom'),coalesce(v_base#>>'{theme,name}','Custom'),v_base,v_email) returning id into v_id;
    v_ds:=jsonb_set(v_ds,'{published}',v_base,true); v_ds:=jsonb_set(v_ds,'{publishedVersionId}',to_jsonb(v_id),true);
  else
    v_base:=v_base||jsonb_build_object('status','draft','draftUpdatedAt',now(),'draftUpdatedBy',v_email); v_ds:=jsonb_set(v_ds,'{draft}',v_base,true);
  end if;
  update public.site_settings set design_system=v_ds where id=1;
  return jsonb_build_object('ok',true,'published',p_publish,'scope',p_scope,'site',p_site,'page',p_page);
end;
$$;

revoke all on function public.admin_design_system_set_scope(text,text,text,text,jsonb,boolean) from public, anon, authenticated;
revoke all on function public.admin_design_system_reset_scope(text,text,text,text,boolean) from public, anon, authenticated;
grant execute on function public.admin_design_system_set_scope(text,text,text,text,jsonb,boolean) to service_role;
grant execute on function public.admin_design_system_reset_scope(text,text,text,text,boolean) to service_role;
