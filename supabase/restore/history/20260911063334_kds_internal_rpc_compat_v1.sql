-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911063334  Name: kds_internal_rpc_compat_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

GRANT USAGE ON SCHEMA internal_rpc TO anon;
GRANT EXECUTE ON FUNCTION internal_rpc.admin_password_login(text,text) TO anon;
GRANT EXECUTE ON FUNCTION internal_rpc.admin_password_logout(text) TO anon;
GRANT EXECUTE ON FUNCTION internal_rpc.admin_password_session_info(text) TO anon;
GRANT EXECUTE ON FUNCTION internal_rpc.kds_snapshot(text) TO anon;
GRANT EXECUTE ON FUNCTION internal_rpc.kds_update_order(text,uuid,text) TO anon;
GRANT EXECUTE ON FUNCTION internal_rpc.kds_set_availability(text,text,boolean,text) TO anon;
