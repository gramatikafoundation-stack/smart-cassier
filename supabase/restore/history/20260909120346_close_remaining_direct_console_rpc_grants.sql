-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909120346  Name: close_remaining_direct_console_rpc_grants
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

revoke execute on function public.admin_console_transfer_superadmin(text,text,text) from anon, authenticated;
revoke execute on function public.admin_password_login(text,text) from anon, authenticated;
revoke execute on function public.admin_password_logout(text) from anon, authenticated;
revoke execute on function public.admin_password_session_info(text) from anon, authenticated;
revoke execute on function public.kds_set_availability(text,text,boolean,text) from anon, authenticated;
revoke execute on function public.kds_snapshot(text) from anon, authenticated;
revoke execute on function public.kds_update_order(text,uuid,text) from anon, authenticated;
