-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909114349  Name: revoke_direct_sensitive_rpc_access
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

do $$ declare r record; begin
 for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in (
 'admin_console_add_admin','admin_console_remove_admin','admin_console_save_menu','admin_console_set_menu_visible','admin_console_snapshot','admin_console_transfer_superadmin','admin_console_update_admin_design_page','admin_console_update_order','admin_console_update_settings',
 'admin_design_system_history','admin_design_system_publish','admin_design_system_rollback','admin_design_system_save_draft','admin_design_system_registry','admin_design_system_set_element','admin_design_system_reset_element',
 'admin_password_change','admin_password_set_for_admin','kds_console_order_action','kds_console_set_available','kds_console_snapshot','transfer_superadmin') loop
   execute format('revoke execute on function %s from anon, authenticated',r.sig);
   execute format('grant execute on function %s to service_role',r.sig);
 end loop;
end $$;
