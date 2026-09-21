-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911053900  Name: document_sensitive_rpc_bridge
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

comment on schema internal_rpc is 'Non-exposed implementation schema for privileged Admin/KDS RPC logic. Public RPCs are SECURITY INVOKER wrappers only.';
