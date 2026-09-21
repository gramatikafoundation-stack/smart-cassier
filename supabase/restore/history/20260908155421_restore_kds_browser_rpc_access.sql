-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260908155421  Name: restore_kds_browser_rpc_access
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

grant execute on function public.kds_snapshot(text) to anon, authenticated;
grant execute on function public.kds_update_order(text, uuid, text) to anon, authenticated;
grant execute on function public.kds_set_availability(text, text, boolean, text) to anon, authenticated;
