-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909120802  Name: lock_transfer_superadmin_service_only
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

revoke all on function public.admin_console_transfer_superadmin(text,text,text) from public, anon, authenticated;
grant execute on function public.admin_console_transfer_superadmin(text,text,text) to service_role;
