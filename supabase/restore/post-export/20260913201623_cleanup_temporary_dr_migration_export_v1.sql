-- DR replay cleanup corresponding to production migration 20260913201623.
-- Removes the temporary service-role-only migration export RPC from the isolated restore.

drop function if exists public.dr_export_migration_history_v1(integer,integer);
