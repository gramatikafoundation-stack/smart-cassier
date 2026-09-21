-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909034318  Name: restrict_admin_design_page_rpc_execute
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

revoke all on function public.admin_console_update_admin_design_page(text,text,jsonb) from public;
grant execute on function public.admin_console_update_admin_design_page(text,text,jsonb) to anon, authenticated;
