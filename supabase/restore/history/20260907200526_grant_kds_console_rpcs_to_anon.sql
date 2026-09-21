-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260907200526  Name: grant_kds_console_rpcs_to_anon
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

grant execute on function public.kds_console_snapshot(text) to anon, authenticated;
grant execute on function public.kds_console_set_available(text,text,boolean) to anon, authenticated;
grant execute on function public.kds_console_order_action(text,uuid,text) to anon, authenticated;
