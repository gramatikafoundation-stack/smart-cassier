-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911053923  Name: restrict_sensitive_public_rpc_grants
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

revoke all on function public.admin_password_login(text,text) from authenticated;
revoke all on function public.admin_password_logout(text) from authenticated;
revoke all on function public.admin_password_session_info(text) from authenticated;
revoke all on function public.kds_snapshot(text) from authenticated;
revoke all on function public.kds_update_order(text,uuid,text) from authenticated;
revoke all on function public.kds_set_availability(text,text,boolean,text) from authenticated;
