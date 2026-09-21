-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260913065031  Name: replace_public_settings_view_with_rls_cache
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

drop view if exists public.site_settings_public_v2;

create table public.site_settings_public_v2 (
  id smallint primary key,
  business_name text,
  welcome_text text,
  motto text,
  hero_image_url text,
  public_url text,
  merchant_name text,
  payment_instructions text,
  qris_image_url text,
  qris_enabled boolean,
  require_table_qr_signature boolean,
  typography jsonb,
  design_system jsonb,
  updated_at timestamptz not null default now(),
  constraint site_settings_public_v2_singleton check (id = 1)
);

alter table public.site_settings_public_v2 enable row level security;
revoke all on table public.site_settings_public_v2 from public, anon, authenticated;
grant select on table public.site_settings_public_v2 to anon, authenticated;
create policy site_settings_public_v2_read on public.site_settings_public_v2 for select to anon, authenticated using (id = 1);

create or replace function private.sync_site_settings_public_v2()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  projected jsonb;
begin
  projected := jsonb_strip_nulls(jsonb_build_object(
    'version', new.design_system -> 'version',
    'publishedVersionId', new.design_system -> 'publishedVersionId',
    'updatedAt', new.design_system -> 'updatedAt',
    'published', jsonb_strip_nulls(jsonb_build_object(
      'schemaVersion', (new.design_system -> 'published') -> 'schemaVersion',
      'status', (new.design_system -> 'published') -> 'status',
      'publishedAt', (new.design_system -> 'published') -> 'publishedAt',
      'theme', (new.design_system -> 'published') -> 'theme',
      'general', (new.design_system -> 'published') -> 'general',
      'sites', case when coalesce((new.design_system -> 'published') -> 'sites','{}'::jsonb) ? 'public'
        then jsonb_build_object('public', ((new.design_system -> 'published') -> 'sites') -> 'public') else '{}'::jsonb end,
      'pages', case when coalesce((new.design_system -> 'published') -> 'pages','{}'::jsonb) ? 'public'
        then jsonb_build_object('public', ((new.design_system -> 'published') -> 'pages') -> 'public') else '{}'::jsonb end,
      'elements', case when coalesce((new.design_system -> 'published') -> 'elements','{}'::jsonb) ? 'public'
        then jsonb_build_object('public', ((new.design_system -> 'published') -> 'elements') -> 'public') else '{}'::jsonb end
    ))
  ));

  insert into public.site_settings_public_v2(
    id,business_name,welcome_text,motto,hero_image_url,public_url,merchant_name,payment_instructions,
    qris_image_url,qris_enabled,require_table_qr_signature,typography,design_system,updated_at
  ) values (
    new.id,new.business_name,new.welcome_text,new.motto,new.hero_image_url,new.public_url,new.merchant_name,new.payment_instructions,
    new.qris_image_url,new.qris_enabled,new.require_table_qr_signature,new.typography,projected,new.updated_at
  )
  on conflict (id) do update set
    business_name=excluded.business_name,
    welcome_text=excluded.welcome_text,
    motto=excluded.motto,
    hero_image_url=excluded.hero_image_url,
    public_url=excluded.public_url,
    merchant_name=excluded.merchant_name,
    payment_instructions=excluded.payment_instructions,
    qris_image_url=excluded.qris_image_url,
    qris_enabled=excluded.qris_enabled,
    require_table_qr_signature=excluded.require_table_qr_signature,
    typography=excluded.typography,
    design_system=excluded.design_system,
    updated_at=excluded.updated_at;
  return new;
end $$;

revoke all on function private.sync_site_settings_public_v2() from public, anon, authenticated;

drop trigger if exists trg_sync_site_settings_public_v2 on public.site_settings;
create trigger trg_sync_site_settings_public_v2
after insert or update of business_name,welcome_text,motto,hero_image_url,public_url,merchant_name,payment_instructions,qris_image_url,qris_enabled,require_table_qr_signature,typography,design_system,updated_at
on public.site_settings
for each row execute function private.sync_site_settings_public_v2();

insert into public.site_settings_public_v2(
  id,business_name,welcome_text,motto,hero_image_url,public_url,merchant_name,payment_instructions,
  qris_image_url,qris_enabled,require_table_qr_signature,typography,design_system,updated_at
)
select
  s.id,s.business_name,s.welcome_text,s.motto,s.hero_image_url,s.public_url,s.merchant_name,s.payment_instructions,
  s.qris_image_url,s.qris_enabled,s.require_table_qr_signature,s.typography,
  jsonb_strip_nulls(jsonb_build_object(
    'version', s.design_system -> 'version',
    'publishedVersionId', s.design_system -> 'publishedVersionId',
    'updatedAt', s.design_system -> 'updatedAt',
    'published', jsonb_strip_nulls(jsonb_build_object(
      'schemaVersion', (s.design_system -> 'published') -> 'schemaVersion',
      'status', (s.design_system -> 'published') -> 'status',
      'publishedAt', (s.design_system -> 'published') -> 'publishedAt',
      'theme', (s.design_system -> 'published') -> 'theme',
      'general', (s.design_system -> 'published') -> 'general',
      'sites', case when coalesce((s.design_system -> 'published') -> 'sites','{}'::jsonb) ? 'public'
        then jsonb_build_object('public', ((s.design_system -> 'published') -> 'sites') -> 'public') else '{}'::jsonb end,
      'pages', case when coalesce((s.design_system -> 'published') -> 'pages','{}'::jsonb) ? 'public'
        then jsonb_build_object('public', ((s.design_system -> 'published') -> 'pages') -> 'public') else '{}'::jsonb end,
      'elements', case when coalesce((s.design_system -> 'published') -> 'elements','{}'::jsonb) ? 'public'
        then jsonb_build_object('public', ((s.design_system -> 'published') -> 'elements') -> 'public') else '{}'::jsonb end
    ))
  )),
  s.updated_at
from public.site_settings s where s.id=1
on conflict (id) do nothing;
