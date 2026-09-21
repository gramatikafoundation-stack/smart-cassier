-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260907200951  Name: admin_internal_auth_v4_support
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.admin_console_snapshot(p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_settings jsonb;
  v_menu jsonb;
  v_orders jsonb;
  v_team jsonb;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select to_jsonb(s) into v_settings from public.site_settings s where s.id=1;
  select coalesce(jsonb_agg(to_jsonb(m) order by m.display_order asc,m.name asc),'[]'::jsonb) into v_menu from public.menu_items m;
  select coalesce(jsonb_agg(to_jsonb(o) order by o.created_at desc),'[]'::jsonb) into v_orders from (select * from public.order_archive_7d order by created_at desc limit 500) o;
  select coalesce(jsonb_agg(jsonb_build_object('email',a.email::text,'display_name',a.display_name,'role',a.role,'is_active',a.is_active,'is_protected',a.is_protected,'created_at',a.created_at) order by a.created_at asc),'[]'::jsonb) into v_team from public.admin_users a;
  return jsonb_build_object('ok',true,'email',v_email::text,'settings',coalesce(v_settings,'{}'::jsonb),'menu',v_menu,'orders',v_orders,'team',v_team);
end;
$$;

grant execute on function public.admin_console_snapshot(text) to anon, authenticated;
grant execute on function public.admin_password_change(text,text,text) to anon, authenticated;
grant execute on function public.admin_password_set_for_admin(text,text,text) to anon, authenticated;

create or replace function public.admin_console_transfer_superadmin(p_token text,p_new_email text,p_new_password text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_current extensions.citext;
  v_target extensions.citext;
  v_pw jsonb;
begin
  v_current := private.admin_email_from_token(p_token);
  if v_current is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if not private.admin_is_super_from_token(p_token) then return jsonb_build_object('ok',false,'error','forbidden'); end if;
  v_target := lower(trim(coalesce(p_new_email,'')))::extensions.citext;
  if position('@' in v_target::text)=0 then return jsonb_build_object('ok',false,'error','email_invalid'); end if;
  if not exists(select 1 from public.admin_users where email=v_target) then
    if p_new_password is null or length(p_new_password)<12 then return jsonb_build_object('ok',false,'error','password_required_for_new_admin'); end if;
    insert into public.admin_users(email,display_name,role,is_active,is_protected) values(v_target,split_part(v_target::text,'@',1),'admin',true,false);
    v_pw := public.admin_password_set_for_admin(p_token,v_target::text,p_new_password);
    if coalesce((v_pw->>'ok')::boolean,false) is not true then return jsonb_build_object('ok',false,'error',coalesce(v_pw->>'error','password_set_failed')); end if;
  end if;
  update public.admin_users set role='admin',is_protected=false where email=v_current and email<>v_target;
  update public.admin_users set role='superadmin',is_active=true,is_protected=true where email=v_target;
  delete from private.admin_sessions where email in (v_current,v_target);
  return jsonb_build_object('ok',true,'previous_superadmin',v_current::text,'new_superadmin',v_target::text);
end;
$$;
grant execute on function public.admin_console_transfer_superadmin(text,text,text) to anon, authenticated;
