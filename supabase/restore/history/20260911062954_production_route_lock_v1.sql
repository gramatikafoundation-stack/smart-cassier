-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911062954  Name: production_route_lock_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

ALTER TABLE public.site_settings DROP CONSTRAINT IF EXISTS site_settings_locked_public_url_chk;
ALTER TABLE public.site_settings DROP CONSTRAINT IF EXISTS site_settings_locked_admin_url_chk;
ALTER TABLE public.site_settings DROP CONSTRAINT IF EXISTS site_settings_locked_kds_url_chk;
ALTER TABLE public.site_settings ADD CONSTRAINT site_settings_locked_public_url_chk CHECK (public_url = 'https://rohmat-pesan-bayar-publik.vercel.app/');
ALTER TABLE public.site_settings ADD CONSTRAINT site_settings_locked_admin_url_chk CHECK (admin_url = 'https://studio-pengelola-rohmat.vercel.app');
ALTER TABLE public.site_settings ADD CONSTRAINT site_settings_locked_kds_url_chk CHECK (kds_url = 'https://rohmat-kds-printer.vercel.app');
