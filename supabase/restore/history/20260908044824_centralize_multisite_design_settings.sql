-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260908044824  Name: centralize_multisite_design_settings
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.site_settings
  add column if not exists admin_design jsonb not null default '{"login":{"bg":"#f3f0e8","panel":"#fffefa","primary":"#153f33","accent":"#dc613e","text":"#173f33","font":"system-ui","layout":"balanced","radius":22},"control":{"bg":"#f3f0e8","panel":"#fffefa","primary":"#153f33","accent":"#dc613e","text":"#173f33","font":"system-ui","layout":"balanced","radius":22},"design":{"bg":"#f3f0e8","panel":"#fffefa","primary":"#153f33","accent":"#dc613e","text":"#173f33","font":"system-ui","layout":"balanced","radius":22},"orders":{"bg":"#f3f0e8","panel":"#fffefa","primary":"#153f33","accent":"#dc613e","text":"#173f33","font":"system-ui","layout":"balanced","radius":22},"qris":{"bg":"#f3f0e8","panel":"#fffefa","primary":"#153f33","accent":"#dc613e","text":"#173f33","font":"system-ui","layout":"balanced","radius":22},"team":{"bg":"#f3f0e8","panel":"#fffefa","primary":"#153f33","accent":"#dc613e","text":"#173f33","font":"system-ui","layout":"balanced","radius":22},"security":{"bg":"#f3f0e8","panel":"#fffefa","primary":"#153f33","accent":"#dc613e","text":"#173f33","font":"system-ui","layout":"balanced","radius":22}}'::jsonb,
  add column if not exists kds_design jsonb not null default '{"login":{"bg":"#f3efe6","panel":"#fffdf8","primary":"#153f33","accent":"#27634e","text":"#173f33","font":"system-ui","layout":"balanced","radius":22},"orders":{"bg":"#0f130f","panel":"#171c16","primary":"#244f40","accent":"#42a27d","text":"#f6f4ef","font":"system-ui","layout":"wide","radius":18},"stock":{"bg":"#0f130f","panel":"#171c16","primary":"#244f40","accent":"#42a27d","text":"#f6f4ef","font":"system-ui","layout":"wide","radius":18}}'::jsonb;

create or replace function public.admin_console_update_settings(p_token text, p_patch jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_email extensions.citext;
  v_row public.site_settings%rowtype;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then return jsonb_build_object('ok',false,'error','invalid_patch'); end if;

  update public.site_settings s set
    business_name = case when p_patch ? 'business_name' then left(coalesce(p_patch->>'business_name',''),120) else s.business_name end,
    welcome_text = case when p_patch ? 'welcome_text' then left(coalesce(p_patch->>'welcome_text',''),240) else s.welcome_text end,
    motto = case when p_patch ? 'motto' then left(coalesce(p_patch->>'motto',''),240) else s.motto end,
    hero_image_url = case when p_patch ? 'hero_image_url' then nullif(left(coalesce(p_patch->>'hero_image_url',''),1000),'') else s.hero_image_url end,
    photo_position = case when p_patch ? 'photo_position' and (p_patch->>'photo_position') in ('left','right','top') then p_patch->>'photo_position' else s.photo_position end,
    content_position = case when p_patch ? 'content_position' and (p_patch->>'content_position') in ('left','center','right') then p_patch->>'content_position' else s.content_position end,
    content_width = case when p_patch ? 'content_width' and (p_patch->>'content_width') in ('compact','balanced','wide') then p_patch->>'content_width' else s.content_width end,
    element_order = case when p_patch ? 'element_order' and jsonb_typeof(p_patch->'element_order')='array' then p_patch->'element_order' else s.element_order end,
    theme_preset = case when p_patch ? 'theme_preset' then left(coalesce(p_patch->>'theme_preset',''),60) else s.theme_preset end,
    color_outer = case when p_patch ? 'color_outer' then left(coalesce(p_patch->>'color_outer',''),20) else s.color_outer end,
    color_panel = case when p_patch ? 'color_panel' then left(coalesce(p_patch->>'color_panel',''),20) else s.color_panel end,
    color_primary = case when p_patch ? 'color_primary' then left(coalesce(p_patch->>'color_primary',''),20) else s.color_primary end,
    color_accent = case when p_patch ? 'color_accent' then left(coalesce(p_patch->>'color_accent',''),20) else s.color_accent end,
    color_text = case when p_patch ? 'color_text' then left(coalesce(p_patch->>'color_text',''),20) else s.color_text end,
    color_muted = case when p_patch ? 'color_muted' then left(coalesce(p_patch->>'color_muted',''),20) else s.color_muted end,
    typography = case when p_patch ? 'typography' and jsonb_typeof(p_patch->'typography')='object' then p_patch->'typography' else s.typography end,
    merchant_name = case when p_patch ? 'merchant_name' then left(coalesce(p_patch->>'merchant_name',''),120) else s.merchant_name end,
    payment_instructions = case when p_patch ? 'payment_instructions' then left(coalesce(p_patch->>'payment_instructions',''),500) else s.payment_instructions end,
    qris_image_url = case when p_patch ? 'qris_image_url' then nullif(left(coalesce(p_patch->>'qris_image_url',''),1000),'') else s.qris_image_url end,
    qris_enabled = case when p_patch ? 'qris_enabled' then coalesce((p_patch->>'qris_enabled')::boolean,false) else s.qris_enabled end,
    admin_design = case when p_patch ? 'admin_design' and jsonb_typeof(p_patch->'admin_design')='object' then p_patch->'admin_design' else s.admin_design end,
    kds_design = case when p_patch ? 'kds_design' and jsonb_typeof(p_patch->'kds_design')='object' then p_patch->'kds_design' else s.kds_design end,
    updated_by = null,
    updated_at = now()
  where s.id=1
  returning s.* into v_row;

  return jsonb_build_object('ok',true,'settings',to_jsonb(v_row));
end;
$function$;
