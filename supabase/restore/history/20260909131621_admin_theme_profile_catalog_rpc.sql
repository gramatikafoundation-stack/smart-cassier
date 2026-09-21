-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909131621  Name: admin_theme_profile_catalog_rpc
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.admin_theme_profile_catalog(p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_result jsonb;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select coalesce(jsonb_agg(profile order by name),'[]'::jsonb) into v_result from private.theme_profiles;
  return jsonb_build_object('ok',true,'profiles',v_result);
end $$;
revoke all on function public.admin_theme_profile_catalog(text) from public, anon, authenticated;
grant execute on function public.admin_theme_profile_catalog(text) to service_role;
