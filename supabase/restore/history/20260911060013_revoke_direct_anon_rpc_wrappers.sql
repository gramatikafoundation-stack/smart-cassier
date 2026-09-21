-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911060013  Name: revoke_direct_anon_rpc_wrappers
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

revoke execute on function public.admin_password_login(text,text) from anon, authenticated;
revoke execute on function public.admin_password_logout(text) from anon, authenticated;
revoke execute on function public.admin_password_session_info(text) from anon, authenticated;
revoke execute on function public.kds_snapshot(text) from anon, authenticated;
revoke execute on function public.kds_update_order(text,uuid,text) from anon, authenticated;
revoke execute on function public.kds_set_availability(text,text,boolean,text) from anon, authenticated;
grant execute on function public.admin_password_login(text,text) to service_role;
grant execute on function public.admin_password_logout(text) to service_role;
grant execute on function public.admin_password_session_info(text) to service_role;
grant execute on function public.kds_snapshot(text) to service_role;
grant execute on function public.kds_update_order(text,uuid,text) to service_role;
grant execute on function public.kds_set_availability(text,text,boolean,text) to service_role;
