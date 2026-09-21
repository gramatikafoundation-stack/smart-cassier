-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909021434  Name: enable_http_extension_for_public_snapshot
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create extension if not exists http with schema extensions;
