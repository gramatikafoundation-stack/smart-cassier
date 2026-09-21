-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911025652  Name: restrict_archived_order_dedupe_rpc
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

revoke all on function public.enforce_archived_order_dedupe() from public;
revoke all on function public.enforce_archived_order_dedupe() from anon;
revoke all on function public.enforce_archived_order_dedupe() from authenticated;
grant execute on function public.enforce_archived_order_dedupe() to service_role;
