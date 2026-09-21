-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260908091930  Name: add_kds_live_design_url_marker
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

comment on column public.site_settings.kds_design is 'Per-page KDS visual configuration consumed by rohmat-kds-live; operational KDS logic remains separate.';
