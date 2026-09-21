-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911053910  Name: restrict_internal_rpc_schema_defaults
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

revoke create on schema internal_rpc from public, anon, authenticated; alter default privileges in schema internal_rpc revoke execute on functions from public;
