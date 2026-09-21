-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260913160212  Name: revoke_public_order_archive_access
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

revoke all on public.order_archive_7d from anon, authenticated; grant select on public.order_archive_7d to service_role;
