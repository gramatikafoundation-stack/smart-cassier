-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260907191920  Name: add_google_sheet_link_to_site_settings
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.site_settings add column if not exists google_sheet_url text not null default '';
update public.site_settings set google_sheet_url='https://docs.google.com/spreadsheets/d/1i6wmLH7rS9rWLDLs1H9RqzmBMHCJKD08qTgv_-9QZeQ/edit', updated_at=now() where id=1;
