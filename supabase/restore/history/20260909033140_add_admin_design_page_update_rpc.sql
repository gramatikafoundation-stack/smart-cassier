-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909033140  Name: add_admin_design_page_update_rpc
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.admin_console_update_admin_design_page(p_token text, p_page text, p_config jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_email extensions.citext;
  v_design jsonb;
  v_cfg jsonb;
  v_bg text;
  v_panel text;
  v_primary text;
  v_accent text;
  v_text text;
  v_font text;
  v_layout text;
  v_radius int;
  v_typography jsonb;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session');
  end if;

  if p_page not in ('login','control','design','orders','qris','team','security') then
    return jsonb_build_object('ok', false, 'error', 'invalid_page');
  end if;
  if p_config is null or jsonb_typeof(p_config) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid_config');
  end if;

  v_bg := case when coalesce(p_config->>'bg','') ~ '^#[0-9A-Fa-f]{6}$' then p_config->>'bg' else '#f3f0e8' end;
  v_panel := case when coalesce(p_config->>'panel','') ~ '^#[0-9A-Fa-f]{6}$' then p_config->>'panel' else '#fffefa' end;
  v_primary := case when coalesce(p_config->>'primary','') ~ '^#[0-9A-Fa-f]{6}$' then p_config->>'primary' else '#153f33' end;
  v_accent := case when coalesce(p_config->>'accent','') ~ '^#[0-9A-Fa-f]{6}$' then p_config->>'accent' else '#dc613e' end;
  v_text := case when coalesce(p_config->>'text','') ~ '^#[0-9A-Fa-f]{6}$' then p_config->>'text' else '#173f33' end;
  v_font := left(coalesce(nullif(p_config->>'font',''),'system-ui'),80);
  v_layout := case when p_config->>'layout' in ('compact','balanced','wide') then p_config->>'layout' else 'balanced' end;
  v_radius := greatest(8, least(40, coalesce((p_config->>'radius')::int,22)));
  v_typography := case when jsonb_typeof(p_config->'typography')='object' then p_config->'typography' else null end;

  v_cfg := jsonb_build_object(
    'bg', v_bg,
    'panel', v_panel,
    'primary', v_primary,
    'accent', v_accent,
    'text', v_text,
    'font', v_font,
    'layout', v_layout,
    'radius', v_radius
  );
  if v_typography is not null then
    v_cfg := v_cfg || jsonb_build_object('typography', v_typography);
  end if;

  select coalesce(admin_design,'{}'::jsonb) into v_design from public.site_settings where id=1 for update;
  v_design := jsonb_set(v_design, array[p_page], v_cfg, true);

  update public.site_settings
     set admin_design = v_design,
         updated_by = null,
         updated_at = now()
   where id=1;

  return jsonb_build_object('ok', true, 'page', p_page, 'config', v_cfg, 'admin_design', v_design, 'updated_at', now());
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$function$;

grant execute on function public.admin_console_update_admin_design_page(text,text,jsonb) to anon, authenticated;
