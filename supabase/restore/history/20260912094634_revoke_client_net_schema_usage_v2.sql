-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912094634  Name: revoke_client_net_schema_usage_v2
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

revoke usage on schema net from public, anon, authenticated;
grant usage on schema net to service_role;
