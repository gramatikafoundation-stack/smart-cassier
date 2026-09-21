-- Mirrors production migration 20260913194739.
-- Browser reads use least-privilege projections; raw settings stay non-readable.

drop policy if exists "Public reads site settings" on public.site_settings;
revoke select on table public.site_settings from anon, authenticated;

-- Authenticated administrative mutations remain governed by the existing
-- UPDATE privilege and RLS policy; no direct browser SELECT is restored here.
