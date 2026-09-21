-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911062942  Name: production_rpc_hardening_v2
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

REVOKE ALL ON SCHEMA internal_rpc FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA internal_rpc TO service_role;
REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA internal_rpc FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal_rpc TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_password_login(text,text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_password_logout(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_password_session_info(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.kds_snapshot(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.kds_update_order(text,uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.kds_set_availability(text,text,boolean,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_password_login(text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_password_logout(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_password_session_info(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.kds_snapshot(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.kds_update_order(text,uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.kds_set_availability(text,text,boolean,text) TO service_role;

REVOKE USAGE ON SCHEMA private FROM anon;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA private FROM anon;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA private FROM authenticated;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_superadmin() TO authenticated;
