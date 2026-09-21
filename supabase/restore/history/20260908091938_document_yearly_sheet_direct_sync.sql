-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260908091938  Name: document_yearly_sheet_direct_sync
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

comment on column public.site_settings.google_sheet_url is 'Folder containing yearly Google Sheets 2026-2030; Sheets are synchronized by direct writer rather than IMPORTDATA.';
