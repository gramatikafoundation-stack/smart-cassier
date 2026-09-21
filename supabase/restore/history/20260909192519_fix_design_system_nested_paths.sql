-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909192519  Name: fix_design_system_nested_paths
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.admin_design_system_set_element(
  p_token text,
  p_site text,
  p_page text,
  p_element text,
  p_config jsonb,
  p_publish boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  em extensions.citext;
  st jsonb;
  base jsonb;
  clean jsonb;
  path text[];
  existing jsonb;
  merged jsonb;
  res jsonb;
begin
  em := private.admin_email_from_token(p_token);
  if em is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;

  if not exists (
    select 1
    from public.design_element_registry r
    where r.site=p_site and r.page=p_page and r.element_id=p_element
  ) then
    return jsonb_build_object('ok',false,'error','element_not_allowed');
  end if;

  clean := private.design_sanitize_element_config(p_config);
  if clean='{}'::jsonb then
    return jsonb_build_object('ok',false,'error','empty_or_invalid_config');
  end if;

  select design_system into st
  from public.site_settings
  where id=1
  for update;

  base := case
    when coalesce(p_publish,false) then coalesce(st->'published','{}'::jsonb)
    else coalesce(st->'draft',st->'published','{}'::jsonb)
  end;

  /* jsonb_set does not create missing intermediate objects. Build every parent
     so element overrides work on a fresh design_system for every site/page. */
  base := jsonb_set(base,'{elements}',coalesce(base->'elements','{}'::jsonb),true);
  base := jsonb_set(
    base,
    array['elements',p_site],
    coalesce(base #> array['elements',p_site],'{}'::jsonb),
    true
  );
  base := jsonb_set(
    base,
    array['elements',p_site,p_page],
    coalesce(base #> array['elements',p_site,p_page],'{}'::jsonb),
    true
  );

  path := array['elements',p_site,p_page,p_element];
  existing := coalesce(base #> path,'{}'::jsonb);
  merged := existing;

  /* Deep-merge supported element sections so typography edits never erase
     an existing content/color/layout override, and vice versa. */
  if clean ? 'content' then
    merged := jsonb_set(
      merged,'{content}',
      coalesce(merged->'content','{}'::jsonb) || (clean->'content'),true
    );
  end if;
  if clean ? 'typography' then
    merged := jsonb_set(
      merged,'{typography}',
      coalesce(merged->'typography','{}'::jsonb) || (clean->'typography'),true
    );
  end if;
  if clean ? 'colors' then
    merged := jsonb_set(
      merged,'{colors}',
      coalesce(merged->'colors','{}'::jsonb) || (clean->'colors'),true
    );
  end if;
  if clean ? 'layout' then
    merged := jsonb_set(
      merged,'{layout}',
      coalesce(merged->'layout','{}'::jsonb) || (clean->'layout'),true
    );
  end if;

  base := jsonb_set(base,path,merged,true);

  if coalesce(p_publish,false) then
    res := private.design_system_apply_payload(em::text,base,'published',null);
    return res;
  end if;

  return public.admin_design_system_save_draft(p_token,base);
end
$function$;

create or replace function public.admin_design_system_set_scope(
  p_token text,
  p_scope text,
  p_site text,
  p_page text,
  p_config jsonb,
  p_publish boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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

  select coalesce(design_system,'{}'::jsonb) into v_ds
  from public.site_settings where id=1 for update;

  if p_publish then
    v_base := coalesce(v_ds->'published','{}'::jsonb);
  else
    v_base := case
      when jsonb_typeof(v_ds->'draft')='object' and coalesce(v_ds->'draft','{}'::jsonb) <> '{}'::jsonb then v_ds->'draft'
      else coalesce(v_ds->'published','{}'::jsonb)
    end;
  end if;

  if p_scope='site' then
    v_base := jsonb_set(v_base,'{sites}',coalesce(v_base->'sites','{}'::jsonb),true);
    v_path := array['sites',p_site];
  else
    v_base := jsonb_set(v_base,'{pages}',coalesce(v_base->'pages','{}'::jsonb),true);
    v_base := jsonb_set(
      v_base,array['pages',p_site],
      coalesce(v_base #> array['pages',p_site],'{}'::jsonb),true
    );
    v_path := array['pages',p_site,p_page];
  end if;

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
end
$function$;

create or replace function public.admin_design_system_reset_scope(
  p_token text,
  p_scope text,
  p_site text,
  p_page text,
  p_publish boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
  if coalesce((v_session->>'ok')::boolean,false) is not true then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  if p_scope not in ('site','page') or p_site not in ('public','admin','kds','database') then
    return jsonb_build_object('ok',false,'error','invalid_scope');
  end if;
  if p_scope='page' and (coalesce(p_page,'') !~ '^[a-z0-9][a-z0-9-]{0,63}$') then
    return jsonb_build_object('ok',false,'error','invalid_page');
  end if;

  select coalesce(design_system,'{}'::jsonb) into v_ds
  from public.site_settings where id=1 for update;

  if p_publish then
    v_base := coalesce(v_ds->'published','{}'::jsonb);
  else
    v_base := case
      when jsonb_typeof(v_ds->'draft')='object' and coalesce(v_ds->'draft','{}'::jsonb)<>'{}'::jsonb then v_ds->'draft'
      else coalesce(v_ds->'published','{}'::jsonb)
    end;
  end if;

  if p_scope='site' then
    v_base := jsonb_set(v_base,'{sites}',coalesce(v_base->'sites','{}'::jsonb),true);
    v_path := array['sites',p_site];
  else
    v_base := jsonb_set(v_base,'{pages}',coalesce(v_base->'pages','{}'::jsonb),true);
    v_base := jsonb_set(
      v_base,array['pages',p_site],
      coalesce(v_base #> array['pages',p_site],'{}'::jsonb),true
    );
    v_path := array['pages',p_site,p_page];
  end if;

  v_target := coalesce(v_base #> v_path,'{}'::jsonb) - 'typography' - 'colors';
  v_base := jsonb_set(v_base,v_path,v_target,true);
  v_email := coalesce(v_session->>'email','admin');

  if p_publish then
    v_base := v_base || jsonb_build_object('status','published','publishedAt',now(),'publishedBy',v_email);
    insert into public.design_system_versions(kind,theme_id,theme_name,payload,created_by)
    values('published',coalesce(v_base#>>'{theme,id}','custom'),coalesce(v_base#>>'{theme,name}','Custom'),v_base,v_email)
    returning id into v_id;
    v_ds := jsonb_set(v_ds,'{published}',v_base,true);
    v_ds := jsonb_set(v_ds,'{publishedVersionId}',to_jsonb(v_id),true);
  else
    v_base := v_base || jsonb_build_object('status','draft','draftUpdatedAt',now(),'draftUpdatedBy',v_email);
    v_ds := jsonb_set(v_ds,'{draft}',v_base,true);
  end if;

  update public.site_settings set design_system=v_ds where id=1;
  return jsonb_build_object('ok',true,'published',p_publish,'scope',p_scope,'site',p_site,'page',p_page);
end
$function$;
