-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909060121  Name: align_site_settings_text_limits_with_admin
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.site_settings drop constraint if exists settings_business_name_length;
alter table public.site_settings add constraint settings_business_name_length check (char_length(business_name) between 1 and 120);
alter table public.site_settings drop constraint if exists settings_welcome_length;
alter table public.site_settings add constraint settings_welcome_length check (char_length(welcome_text) between 1 and 240);
