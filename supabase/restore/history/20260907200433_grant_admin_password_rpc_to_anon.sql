-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260907200433  Name: grant_admin_password_rpc_to_anon
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

grant execute on function public.admin_password_login(text,text) to anon, authenticated;
grant execute on function public.admin_password_session_info(text) to anon, authenticated;
grant execute on function public.admin_password_logout(text) to anon, authenticated;
