-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260913062832  Name: public_site_settings_least_privilege_v2
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace view public.site_settings_public_v2 as
select
  id,
  business_name,
  welcome_text,
  motto,
  hero_image_url,
  public_url,
  merchant_name,
  payment_instructions,
  qris_image_url,
  qris_enabled,
  require_table_qr_signature,
  typography,
  jsonb_strip_nulls(
    jsonb_build_object(
      'version', design_system->'version',
      'publishedVersionId', design_system->'publishedVersionId',
      'updatedAt', design_system->'updatedAt',
      'published', jsonb_strip_nulls(
        jsonb_build_object(
          'schemaVersion', design_system->'published'->'schemaVersion',
          'status', design_system->'published'->'status',
          'publishedAt', design_system->'published'->'publishedAt',
          'theme', design_system->'published'->'theme',
          'general', design_system->'published'->'general',
          'sites', case when design_system->'published'->'sites' ? 'public' then jsonb_build_object('public',design_system->'published'->'sites'->'public') else '{}'::jsonb end,
          'pages', case when design_system->'published'->'pages' ? 'public' then jsonb_build_object('public',design_system->'published'->'pages'->'public') else '{}'::jsonb end,
          'elements', case when design_system->'published'->'elements' ? 'public' then jsonb_build_object('public',design_system->'published'->'elements'->'public') else '{}'::jsonb end
        )
      )
    )
  ) as design_system
from public.site_settings;

revoke all on public.site_settings_public_v2 from public;
grant select on public.site_settings_public_v2 to anon, authenticated;
comment on view public.site_settings_public_v2 is 'Least-privilege storefront configuration contract. Excludes admin_url, kds_url, google_sheet_url, admin_design, kds_design, updated_by and non-public design-system branches.';
