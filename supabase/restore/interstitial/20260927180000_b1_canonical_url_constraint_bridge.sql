-- DR interstitial prerequisite reconstructed from live production schema.
-- B1 canonical single-domain cutover removed the legacy per-domain URL locks,
-- but that transition was not present in the 2026-09-13 sanitized restore history.
-- Recovery-only: reproduces current production constraint state before B1 replay.

alter table public.site_settings
  drop constraint if exists site_settings_locked_public_url_chk,
  drop constraint if exists site_settings_locked_admin_url_chk,
  drop constraint if exists site_settings_locked_kds_url_chk;
