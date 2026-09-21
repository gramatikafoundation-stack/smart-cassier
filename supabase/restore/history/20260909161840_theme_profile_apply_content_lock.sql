-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909161840  Name: theme_profile_apply_content_lock
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.admin_theme_apply_profile(
  p_token text,
  p_theme_id text,
  p_mode text default 'published'
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_profile jsonb;
  v_state jsonb;
  v_pub jsonb;
  v_payload jsonb;
  v_meta jsonb;
  v_general jsonb;
  v_sites jsonb;
  v_pages jsonb;
  v_elements jsonb;
  v_eff jsonb;
  v_colors jsonb;
  v_typo jsonb;
  v_layout jsonb;
  v_id bigint;
  v_admin jsonb;
  v_kds jsonb;
  v_old_typo jsonb;
  v_legacy_pub jsonb;
  v_legacy_gen jsonb := '{}'::jsonb;
  v_arr jsonb;
  v_gen_colors jsonb;
  v_gen_typo jsonb;
  v_gen_layout jsonb;
  v_gen_density jsonb;
  v_gen_radius jsonb;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_mode not in ('draft','published') then return jsonb_build_object('ok',false,'error','invalid_mode'); end if;

  select profile into v_profile from private.theme_profiles where id=lower(trim(coalesce(p_theme_id,'')));
  if v_profile is null then return jsonb_build_object('ok',false,'error','theme_not_found'); end if;
  if not (v_profile ?& array['colors','typography','layout','composition','spacing','components','radius','effects','navigation','density','forms','visual','motion','images']) then
    return jsonb_build_object('ok',false,'error','incomplete_theme_profile');
  end if;

  select design_system,admin_design,kds_design,typography
    into v_state,v_admin,v_kds,v_old_typo
  from public.site_settings where id=1 for update;

  v_state := coalesce(v_state,'{}'::jsonb);
  v_pub := coalesce(v_state->'published','{}'::jsonb);
  v_general := coalesce(v_pub->'general','{}'::jsonb);
  v_sites := coalesce(v_pub->'sites','{}'::jsonb);
  v_pages := coalesce(v_pub->'pages','{}'::jsonb);
  v_elements := coalesce(v_pub->'elements','{}'::jsonb);
  v_meta := private.jsonb_deep_merge(
    coalesce(v_pub->'meta','{}'::jsonb),
    jsonb_build_object(
      'themeSchema',3,
      'themeScopeLocked',true,
      'contentElementsImmutableOnThemeChange',true,
      'mutableCategories',jsonb_build_array('colors','typography','layout','composition','spacing','components','radius','effects','navigation','density','forms','visual','motion','images'),
      'updatedAt',now()
    )
  );

  v_payload := jsonb_build_object(
    'schemaVersion',2,
    'theme',v_profile,
    'general',v_general,
    'sites',v_sites,
    'pages',v_pages,
    'elements',v_elements,
    'meta',v_meta
  );

  if p_mode='draft' then
    insert into public.design_system_versions(kind,theme_id,theme_name,payload,created_by)
    values('draft',v_profile->>'id',v_profile->>'name',v_payload,v_email::text)
    returning id into v_id;
    update public.site_settings
      set design_system=v_state || jsonb_build_object(
        'version',2,
        'draft',v_payload || jsonb_build_object('status','draft','draftVersionId',v_id,'updatedAt',now()),
        'updatedAt',now()
      ), updated_at=now()
    where id=1;
    return jsonb_build_object('ok',true,'mode','draft','versionId',v_id,'themeId',v_profile->>'id','contentLocked',true);
  end if;

  insert into public.design_system_versions(kind,theme_id,theme_name,payload,created_by)
  values('published',v_profile->>'id',v_profile->>'name',v_payload,v_email::text)
  returning id into v_id;

  v_eff := private.jsonb_deep_merge(v_profile,v_general);
  v_colors := coalesce(v_eff->'colors','{}'::jsonb);
  v_typo := coalesce(v_eff->'typography','{}'::jsonb);
  v_layout := coalesce(v_eff->'layout','{}'::jsonb);
  v_arr := jsonb_build_array(
    coalesce(v_colors->>'background','#F3EFE8'),
    coalesce(v_colors->>'panel','#FFFDF9'),
    coalesce(v_colors->>'primary','#264B3E'),
    coalesce(v_colors->>'accent','#C86D4D'),
    coalesce(v_colors->>'text','#23372F'),
    coalesce(v_colors->>'muted','#718078')
  );

  v_legacy_pub := jsonb_build_object(
    'version',3,'status','published','themeId',v_profile->>'id','themeName',v_profile->>'name',
    'tokens',jsonb_build_object(
      'id',v_profile->>'id','name',v_profile->>'name','colors',v_arr,
      'font',coalesce(v_typo->>'family','system-ui'),'layout',coalesce(v_layout->>'width','balanced'),
      'radius',coalesce((v_profile#>>'{radius,card}')::numeric,18),'tag',coalesce(v_profile->>'tag','')
    ),'updatedAt',now()
  );

  v_gen_colors := coalesce(v_general->'colors','{}'::jsonb);
  if v_gen_colors <> '{}'::jsonb then
    v_legacy_gen := v_legacy_gen || jsonb_build_object('colors',jsonb_build_array(
      v_gen_colors->>'background',v_gen_colors->>'panel',v_gen_colors->>'primary',v_gen_colors->>'accent',v_gen_colors->>'text',v_gen_colors->>'muted'
    ));
  end if;
  v_gen_typo := coalesce(v_general->'typography','{}'::jsonb);
  if v_gen_typo <> '{}'::jsonb then
    v_legacy_gen := v_legacy_gen || jsonb_build_object('typography',jsonb_strip_nulls(jsonb_build_object(
      'font',v_gen_typo->>'family',
      'size',case when coalesce(v_gen_typo->>'size','') ~ '^\d+(\.\d+)?$' then to_jsonb((v_gen_typo->>'size')::numeric) else null end
    )));
  end if;
  v_gen_layout := coalesce(v_general->'layout','{}'::jsonb);
  if coalesce(v_gen_layout->>'width','')<>'' then v_legacy_gen:=v_legacy_gen||jsonb_build_object('layout',v_gen_layout->>'width'); end if;
  v_gen_density := coalesce(v_general->'density','{}'::jsonb);
  if coalesce(v_gen_density->>'mode','')<>'' then v_legacy_gen:=v_legacy_gen||jsonb_build_object('density',initcap(v_gen_density->>'mode')); end if;
  v_gen_radius := coalesce(v_general->'radius','{}'::jsonb);
  if coalesce(v_gen_radius->>'card','') ~ '^\d+(\.\d+)?$' then v_legacy_gen:=v_legacy_gen||jsonb_build_object('radius',(v_gen_radius->>'card')::numeric); end if;

  update public.site_settings s set
    design_system=jsonb_build_object(
      'version',2,
      'published',v_payload||jsonb_build_object('status','published','publishedAt',now(),'publishedBy',v_email::text),
      'draft',null,
      'publishedVersionId',v_id,
      'updatedAt',now()
    ),
    theme_preset='custom',
    color_outer=case when (v_colors->>'background')~'^#[0-9A-Fa-f]{6}$' then v_colors->>'background' else s.color_outer end,
    color_panel=case when (v_colors->>'panel')~'^#[0-9A-Fa-f]{6}$' then v_colors->>'panel' else s.color_panel end,
    color_primary=case when (v_colors->>'primary')~'^#[0-9A-Fa-f]{6}$' then v_colors->>'primary' else s.color_primary end,
    color_accent=case when (v_colors->>'accent')~'^#[0-9A-Fa-f]{6}$' then v_colors->>'accent' else s.color_accent end,
    color_text=case when (v_colors->>'text')~'^#[0-9A-Fa-f]{6}$' then v_colors->>'text' else s.color_text end,
    color_muted=case when (v_colors->>'muted')~'^#[0-9A-Fa-f]{6}$' then v_colors->>'muted' else s.color_muted end,
    content_width=case when coalesce(v_layout->>'width','') in ('compact','balanced','wide') then v_layout->>'width' else s.content_width end,
    typography=private.jsonb_deep_merge(coalesce(v_old_typo,'{}'::jsonb),jsonb_build_object('_general',v_typo)),
    admin_design=private.jsonb_deep_merge(coalesce(v_admin,'{}'::jsonb),jsonb_build_object('_system',jsonb_build_object(
      'version',3,'activeTheme',v_profile->>'id','publishedVersionId',v_id,'published',v_legacy_pub,'general',v_legacy_gen,'designV2',v_payload,'themeScopeLocked',true
    ))),
    kds_design=private.jsonb_deep_merge(coalesce(v_kds,'{}'::jsonb),jsonb_build_object('_system',jsonb_build_object(
      'version',3,'activeTheme',v_profile->>'id','publishedVersionId',v_id,'published',v_legacy_pub,'general',v_legacy_gen,'designV2',v_payload,'themeScopeLocked',true
    ))),
    updated_at=now(),updated_by=null
  where s.id=1;

  return jsonb_build_object('ok',true,'mode','published','versionId',v_id,'themeId',v_profile->>'id','categoriesApplied',14,'contentLocked',true);
end;
$$;

revoke all on function public.admin_theme_apply_profile(text,text,text) from public,anon,authenticated;
grant execute on function public.admin_theme_apply_profile(text,text,text) to service_role;
