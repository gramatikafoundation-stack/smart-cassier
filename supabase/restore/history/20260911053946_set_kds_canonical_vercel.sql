-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911053946  Name: set_kds_canonical_vercel
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

update public.site_settings set kds_url='https://rohmat-kds-printer.vercel.app' where id=1;
