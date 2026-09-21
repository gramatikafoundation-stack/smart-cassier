-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260913063246  Name: public_site_settings_contract_add_updated_at
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
          'sites', case when coalesce(design_system->'published'->'sites','{}'::jsonb) ? 'public' then jsonb_build_object('public',design_system->'published'->'sites'->'public') else '{}'::jsonb end,
          'pages', case when coalesce(design_system->'published'->'pages','{}'::jsonb) ? 'public' then jsonb_build_object('public',design_system->'published'->'pages'->'public') else '{}'::jsonb end,
          'elements', case when coalesce(design_system->'published'->'elements','{}'::jsonb) ? 'public' then jsonb_build_object('public',design_system->'published'->'elements'->'public') else '{}'::jsonb end
        )
      )
    )
  ) as design_system,
  updated_at
from public.site_settings;

revoke all on public.site_settings_public_v2 from public;
grant select on public.site_settings_public_v2 to anon, authenticated;
