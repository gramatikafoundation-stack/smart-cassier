-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909111846  Name: design_system_general_delta_bridge
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.site_settings_sync_design_system_legacy()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_sys jsonb; v_old_sys jsonb; v_tokens jsonb; v_gen_old jsonb; v_prev_gen_old jsonb; v_gen jsonb; v_theme jsonb; v_payload jsonb; v_colors jsonb; v_gc jsonb; v_typo jsonb; v_layout jsonb; v_theme_id text; v_theme_name text; v_id bigint; v_changed boolean; v_draft jsonb; v_theme_changed boolean; v_eff jsonb; v_ec jsonb; v_et jsonb; v_el jsonb; v_layout_patch jsonb;
begin
  if new.design_system is distinct from old.design_system then return new; end if;
  v_sys:=coalesce(new.admin_design->'_system','{}'::jsonb);
  v_old_sys:=coalesce(old.admin_design->'_system','{}'::jsonb);

  -- Draft-only update: never publish.
  if new.admin_design is distinct from old.admin_design
     and (v_sys-'draft')=(v_old_sys-'draft')
     and coalesce(v_sys->'draft','null'::jsonb) is distinct from coalesce(v_old_sys->'draft','null'::jsonb) then
    v_draft:=v_sys->'draft';
    if v_draft is null or v_draft='null'::jsonb then
      new.design_system:=jsonb_set(coalesce(old.design_system,'{}'::jsonb),'{draft}','null'::jsonb,true);
      return new;
    end if;
    v_tokens:=coalesce(v_draft->'tokens','{}'::jsonb);
    if jsonb_typeof(v_tokens->'colors')='array' then
      v_colors:=jsonb_build_object('background',v_tokens#>>'{colors,0}','panel',v_tokens#>>'{colors,1}','primary',v_tokens#>>'{colors,2}','accent',v_tokens#>>'{colors,3}','text',v_tokens#>>'{colors,4}','muted',v_tokens#>>'{colors,5}');
    else v_colors:='{}'::jsonb; end if;
    v_theme_id:=coalesce(v_draft->>'themeId',v_tokens->>'id','custom');
    v_theme_name:=coalesce(v_draft->>'themeName',v_tokens->>'name','Custom Theme');
    v_payload:=jsonb_build_object(
      'schemaVersion',2,
      'theme',jsonb_build_object('id',v_theme_id,'name',v_theme_name,'tag',coalesce(v_tokens->>'tag',''),'colors',v_colors,'typography',jsonb_build_object('family',coalesce(v_tokens->>'font','system-ui'),'size',15),'layout',jsonb_build_object('width',coalesce(v_tokens->>'layout','balanced'),'density','Balanced','radius',coalesce((v_tokens->>'radius')::numeric,18),'shadow','soft','motion','subtle')),
      'general',coalesce(old.design_system#>'{published,general}','{}'::jsonb),
      'sites',coalesce(old.design_system#>'{published,sites}','{}'::jsonb),
      'pages',coalesce(old.design_system#>'{published,pages}','{}'::jsonb),
      'elements',coalesce(old.design_system#>'{published,elements}','{}'::jsonb),
      'meta',jsonb_build_object('source','legacy-draft-bridge','updatedAt',now()));
    insert into public.design_system_versions(kind,theme_id,theme_name,payload,created_by)
    values('draft',v_theme_id,v_theme_name,v_payload,'legacy-admin-bridge') returning id into v_id;
    new.design_system:=coalesce(old.design_system,'{}'::jsonb)||jsonb_build_object('version',2,'draft',v_payload||jsonb_build_object('status','draft','draftVersionId',v_id,'updatedAt',now()),'updatedAt',now());
    return new;
  end if;

  v_changed:=new.admin_design is distinct from old.admin_design
    or new.color_outer is distinct from old.color_outer or new.color_panel is distinct from old.color_panel
    or new.color_primary is distinct from old.color_primary or new.color_accent is distinct from old.color_accent
    or new.color_text is distinct from old.color_text or new.color_muted is distinct from old.color_muted
    or new.content_width is distinct from old.content_width or new.typography is distinct from old.typography;
  if not v_changed then return new; end if;

  v_theme_changed:=coalesce(v_sys->>'activeTheme','') is distinct from coalesce(v_old_sys->>'activeTheme','')
    or coalesce(v_sys->'published','{}'::jsonb) is distinct from coalesce(v_old_sys->'published','{}'::jsonb);
  v_tokens:=coalesce(v_sys#>'{published,tokens}','{}'::jsonb);
  v_gen_old:=coalesce(v_sys->'general','{}'::jsonb);
  v_prev_gen_old:=coalesce(v_old_sys->'general','{}'::jsonb);
  v_theme_id:=coalesce(nullif(v_sys->>'activeTheme',''),nullif(v_tokens->>'id',''),coalesce(old.design_system#>>'{published,theme,id}','custom'));
  v_theme_name:=coalesce(nullif(v_tokens->>'name',''),coalesce(old.design_system#>>'{published,theme,name}',initcap(replace(v_theme_id,'-',' '))));

  if jsonb_typeof(v_tokens->'colors')='array' then
    v_colors:=jsonb_build_object('background',coalesce(v_tokens#>>'{colors,0}',new.color_outer),'panel',coalesce(v_tokens#>>'{colors,1}',new.color_panel),'primary',coalesce(v_tokens#>>'{colors,2}',new.color_primary),'accent',coalesce(v_tokens#>>'{colors,3}',new.color_accent),'text',coalesce(v_tokens#>>'{colors,4}',new.color_text),'muted',coalesce(v_tokens#>>'{colors,5}',new.color_muted));
  else
    v_colors:=jsonb_build_object('background',new.color_outer,'panel',new.color_panel,'primary',new.color_primary,'accent',new.color_accent,'text',new.color_text,'muted',new.color_muted);
  end if;
  v_typo:=jsonb_build_object('family',coalesce(nullif(v_tokens->>'font',''),new.typography#>>'{_general,family}','system-ui'),'size',coalesce((new.typography#>>'{_general,size}')::numeric,15));
  v_layout:=jsonb_build_object('width',coalesce(nullif(v_tokens->>'layout',''),new.content_width),'density','Balanced','radius',coalesce((v_tokens->>'radius')::numeric,18),'shadow','soft','motion','subtle');
  v_theme:=jsonb_build_object('id',v_theme_id,'name',v_theme_name,'tag',coalesce(v_tokens->>'tag',''),'colors',v_colors,'typography',v_typo,'layout',v_layout);

  -- Theme publish preserves only true central General overrides.
  if v_theme_changed then
    v_gen:=coalesce(old.design_system#>'{published,general}','{}'::jsonb);
  else
    -- General save is delta-based: only the field actually changed becomes/updates an override.
    v_gen:=coalesce(old.design_system#>'{published,general}','{}'::jsonb);
    if coalesce(v_gen_old->'colors','null'::jsonb) is distinct from coalesce(v_prev_gen_old->'colors','null'::jsonb) then
      if jsonb_typeof(v_gen_old->'colors')='array' then
        v_gc:=jsonb_build_object('background',v_gen_old#>>'{colors,0}','panel',v_gen_old#>>'{colors,1}','primary',v_gen_old#>>'{colors,2}','accent',v_gen_old#>>'{colors,3}','text',v_gen_old#>>'{colors,4}','muted',v_gen_old#>>'{colors,5}');
        v_gen:=jsonb_set(v_gen,'{colors}',v_gc,true);
      end if;
    end if;
    if coalesce(v_gen_old->'typography','null'::jsonb) is distinct from coalesce(v_prev_gen_old->'typography','null'::jsonb) then
      v_gen:=jsonb_set(v_gen,'{typography}',jsonb_strip_nulls(jsonb_build_object('family',v_gen_old#>>'{typography,font}','size',case when (v_gen_old#>>'{typography,size}')~'^\d+(\.\d+)?$' then to_jsonb((v_gen_old#>>'{typography,size}')::numeric) else null end)),true);
    end if;
    v_layout_patch:='{}'::jsonb;
    if coalesce(v_gen_old->>'layout','') is distinct from coalesce(v_prev_gen_old->>'layout','') then v_layout_patch:=v_layout_patch||jsonb_build_object('width',v_gen_old->>'layout'); end if;
    if coalesce(v_gen_old->>'density','') is distinct from coalesce(v_prev_gen_old->>'density','') then v_layout_patch:=v_layout_patch||jsonb_build_object('density',v_gen_old->>'density'); end if;
    if coalesce(v_gen_old->>'radius','') is distinct from coalesce(v_prev_gen_old->>'radius','') then v_layout_patch:=v_layout_patch||jsonb_build_object('radius',case when (v_gen_old->>'radius')~'^\d+(\.\d+)?$' then to_jsonb((v_gen_old->>'radius')::numeric) else 'null'::jsonb end); end if;
    if v_layout_patch<>'{}'::jsonb then v_gen:=jsonb_set(v_gen,'{layout}',private.jsonb_deep_merge(coalesce(v_gen->'layout','{}'::jsonb),v_layout_patch),true); end if;
  end if;

  v_payload:=jsonb_build_object('schemaVersion',2,'theme',v_theme,'general',v_gen,'sites',coalesce(old.design_system#>'{published,sites}','{}'::jsonb),'pages',coalesce(old.design_system#>'{published,pages}','{}'::jsonb),'elements',coalesce(old.design_system#>'{published,elements}','{}'::jsonb),'meta',jsonb_build_object('source','legacy-bridge','updatedAt',now()));
  v_eff:=private.jsonb_deep_merge(v_theme,v_gen); v_ec:=coalesce(v_eff->'colors','{}'::jsonb); v_et:=coalesce(v_eff->'typography','{}'::jsonb); v_el:=coalesce(v_eff->'layout','{}'::jsonb);

  if (v_ec->>'background')~'^#[0-9A-Fa-f]{6}$' then new.color_outer:=v_ec->>'background'; end if;
  if (v_ec->>'panel')~'^#[0-9A-Fa-f]{6}$' then new.color_panel:=v_ec->>'panel'; end if;
  if (v_ec->>'primary')~'^#[0-9A-Fa-f]{6}$' then new.color_primary:=v_ec->>'primary'; end if;
  if (v_ec->>'accent')~'^#[0-9A-Fa-f]{6}$' then new.color_accent:=v_ec->>'accent'; end if;
  if (v_ec->>'text')~'^#[0-9A-Fa-f]{6}$' then new.color_text:=v_ec->>'text'; end if;
  if (v_ec->>'muted')~'^#[0-9A-Fa-f]{6}$' then new.color_muted:=v_ec->>'muted'; end if;
  if coalesce(v_el->>'width','') in ('compact','balanced','wide') then new.content_width:=v_el->>'width'; end if;
  new.typography:=private.jsonb_deep_merge(coalesce(new.typography,'{}'::jsonb),jsonb_build_object('_general',v_et));

  insert into public.design_system_versions(kind,theme_id,theme_name,payload,created_by)
  values('published',v_theme_id,v_theme_name,v_payload,'legacy-admin-bridge') returning id into v_id;
  new.design_system:=jsonb_build_object('version',2,'published',v_payload||jsonb_build_object('status','published','publishedAt',now(),'publishedBy','legacy-admin-bridge'),'draft',old.design_system->'draft','publishedVersionId',v_id,'updatedAt',now());
  return new;
end
$$;
