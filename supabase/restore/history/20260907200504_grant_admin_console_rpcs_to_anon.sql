-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260907200504  Name: grant_admin_console_rpcs_to_anon
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

grant execute on function public.admin_console_snapshot(text) to anon, authenticated;
grant execute on function public.admin_console_save_menu(text,jsonb) to anon, authenticated;
grant execute on function public.admin_console_set_menu_visible(text,text,boolean) to anon, authenticated;
grant execute on function public.admin_console_update_settings(text,jsonb) to anon, authenticated;
grant execute on function public.admin_console_add_admin(text,text,text) to anon, authenticated;
grant execute on function public.admin_console_remove_admin(text,text) to anon, authenticated;
grant execute on function public.admin_console_update_order(text,uuid,text) to anon, authenticated;
