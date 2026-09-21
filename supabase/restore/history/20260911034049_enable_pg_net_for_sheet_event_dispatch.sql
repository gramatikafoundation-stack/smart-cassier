-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911034049  Name: enable_pg_net_for_sheet_event_dispatch
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create extension if not exists pg_net;
