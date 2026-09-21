-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912182714  Name: restore_kds_snapshot_internal_execute_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

grant execute on function internal_rpc.kds_snapshot(text) to anon;
