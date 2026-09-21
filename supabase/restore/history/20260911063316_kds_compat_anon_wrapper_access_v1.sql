-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911063316  Name: kds_compat_anon_wrapper_access_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

GRANT EXECUTE ON FUNCTION public.admin_password_login(text,text) TO anon;
GRANT EXECUTE ON FUNCTION public.admin_password_logout(text) TO anon;
GRANT EXECUTE ON FUNCTION public.admin_password_session_info(text) TO anon;
GRANT EXECUTE ON FUNCTION public.kds_snapshot(text) TO anon;
GRANT EXECUTE ON FUNCTION public.kds_update_order(text,uuid,text) TO anon;
GRANT EXECUTE ON FUNCTION public.kds_set_availability(text,text,boolean,text) TO anon;
