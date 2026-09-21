-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260913194739  Name: revoke_raw_site_settings_public_read_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

drop policy if exists "Public reads site settings" on public.site_settings;
revoke select on table public.site_settings from anon, authenticated;
-- Keep authenticated UPDATE unchanged for backward-compatible administrative mutations; browser reads use the least-privilege projections.

