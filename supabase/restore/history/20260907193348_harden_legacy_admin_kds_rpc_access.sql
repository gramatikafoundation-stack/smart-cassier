-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260907193348  Name: harden_legacy_admin_kds_rpc_access
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

do $$
declare
  f regprocedure;
begin
  foreach f in array array[
    'public.admin_console_add_admin(text,text,text)'::regprocedure,
    'public.admin_console_remove_admin(text,text)'::regprocedure,
    'public.admin_console_save_menu(text,jsonb)'::regprocedure,
    'public.admin_console_set_menu_visible(text,text,boolean)'::regprocedure,
    'public.admin_console_snapshot(text)'::regprocedure,
    'public.admin_console_update_order(text,uuid,text)'::regprocedure,
    'public.admin_console_update_settings(text,jsonb)'::regprocedure,
    'public.admin_password_change(text,text,text)'::regprocedure,
    'public.admin_password_login(text,text)'::regprocedure,
    'public.admin_password_logout(text)'::regprocedure,
    'public.admin_password_session_info(text)'::regprocedure,
    'public.admin_password_set_for_admin(text,text,text)'::regprocedure,
    'public.kds_console_order_action(text,uuid,text)'::regprocedure,
    'public.kds_console_set_available(text,text,boolean)'::regprocedure,
    'public.kds_console_snapshot(text)'::regprocedure,
    'public.kds_set_availability(text,text,boolean,text)'::regprocedure,
    'public.kds_snapshot(text)'::regprocedure,
    'public.kds_update_order(text,uuid,text)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

revoke all on function public.purge_orders_older_than_7_days() from public, anon, authenticated;
grant execute on function public.purge_orders_older_than_7_days() to service_role;

revoke all on function public.transfer_superadmin(text) from public, anon;
grant execute on function public.transfer_superadmin(text) to authenticated;

revoke all on function public.enforce_order_item_availability() from public, anon, authenticated;
