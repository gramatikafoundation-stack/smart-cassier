-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909111300  Name: design_system_publish_legacy_mirror
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.design_system_apply_payload(p_email text, p_payload jsonb, p_kind text, p_restored_from bigint default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_id bigint; v_theme jsonb; v_general jsonb; v_eff jsonb; v_colors jsonb; v_typo jsonb; v_layout jsonb; v_state jsonb; v_admin jsonb; v_kds jsonb; v_old_typo jsonb; v_theme_id text; v_theme_name text; v_legacy_pub jsonb; v_legacy_gen jsonb; v_arr jsonb;
begin
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then return jsonb_build_object('ok',false,'error','invalid_payload'); end if;
  v_theme:=coalesce(p_payload->'theme','{}'::jsonb); v_general:=coalesce(p_payload->'general','{}'::jsonb); v_eff:=private.jsonb_deep_merge(v_theme,v_general);
  v_colors:=coalesce(v_eff->'colors','{}'::jsonb); v_typo:=coalesce(v_eff->'typography','{}'::jsonb); v_layout:=coalesce(v_eff->'layout','{}'::jsonb);
  v_theme_id:=left(coalesce(v_theme->>'id',p_payload->>'themeId','custom'),100); v_theme_name:=left(coalesce(v_theme->>'name',p_payload->>'themeName','Custom Theme'),160);
  insert into public.design_system_versions(kind,theme_id,theme_name,payload,created_by,restored_from) values(p_kind,v_theme_id,v_theme_name,p_payload,p_email,p_restored_from) returning id into v_id;
  select admin_design,kds_design,typography into v_admin,v_kds,v_old_typo from public.site_settings where id=1 for update;
  v_state:=jsonb_build_object('version',2,'published',p_payload||jsonb_build_object('status','published','publishedAt',now(),'publishedBy',p_email),'draft',null,'publishedVersionId',v_id,'updatedAt',now());
  v_arr:=jsonb_build_array(coalesce(v_colors->>'background','#F3EFE8'),coalesce(v_colors->>'panel','#FFFDF9'),coalesce(v_colors->>'primary','#264B3E'),coalesce(v_colors->>'accent','#C86D4D'),coalesce(v_colors->>'text','#23372F'),coalesce(v_colors->>'muted','#718078'));
  v_legacy_pub:=jsonb_build_object('version',1,'status','published','themeId',v_theme_id,'themeName',v_theme_name,'tokens',jsonb_build_object('id',v_theme_id,'name',v_theme_name,'colors',v_arr,'font',coalesce(v_typo->>'family','system-ui'),'layout',coalesce(v_layout->>'width','balanced'),'radius',coalesce((v_layout->>'radius')::numeric,18),'tag',coalesce(v_theme->>'tag','')),'updatedAt',now());
  v_legacy_gen:=jsonb_build_object('colors',v_arr,'layout',coalesce(v_layout->>'width','balanced'),'density',coalesce(v_layout->>'density','Balanced'),'radius',coalesce((v_layout->>'radius')::numeric,18),'typography',jsonb_build_object('font',coalesce(v_typo->>'family','system-ui'),'size',coalesce((v_typo->>'size')::numeric,15)));
  update public.site_settings s set
    design_system=v_state,theme_preset='custom',
    color_outer=case when (v_colors->>'background')~'^#[0-9A-Fa-f]{6}$' then v_colors->>'background' else s.color_outer end,
    color_panel=case when (v_colors->>'panel')~'^#[0-9A-Fa-f]{6}$' then v_colors->>'panel' else s.color_panel end,
    color_primary=case when (v_colors->>'primary')~'^#[0-9A-Fa-f]{6}$' then v_colors->>'primary' else s.color_primary end,
    color_accent=case when (v_colors->>'accent')~'^#[0-9A-Fa-f]{6}$' then v_colors->>'accent' else s.color_accent end,
    color_text=case when (v_colors->>'text')~'^#[0-9A-Fa-f]{6}$' then v_colors->>'text' else s.color_text end,
    color_muted=case when (v_colors->>'muted')~'^#[0-9A-Fa-f]{6}$' then v_colors->>'muted' else s.color_muted end,
    content_width=case when coalesce(v_layout->>'width','') in ('compact','balanced','wide') then v_layout->>'width' else s.content_width end,
    typography=private.jsonb_deep_merge(coalesce(v_old_typo,'{}'::jsonb),jsonb_build_object('_general',v_typo)),
    admin_design=private.jsonb_deep_merge(coalesce(v_admin,'{}'::jsonb),jsonb_build_object('_system',jsonb_build_object('version',2,'activeTheme',v_theme_id,'publishedVersionId',v_id,'published',v_legacy_pub,'general',v_legacy_gen,'designV2',p_payload))),
    kds_design=private.jsonb_deep_merge(coalesce(v_kds,'{}'::jsonb),jsonb_build_object('_system',jsonb_build_object('version',2,'activeTheme',v_theme_id,'publishedVersionId',v_id,'published',v_legacy_pub,'general',v_legacy_gen,'designV2',p_payload))),
    updated_at=now(),updated_by=null where s.id=1;
  return jsonb_build_object('ok',true,'versionId',v_id,'designSystem',v_state);
end
$$;
