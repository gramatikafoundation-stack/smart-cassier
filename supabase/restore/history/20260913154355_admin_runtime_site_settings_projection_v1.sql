-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260913154355  Name: admin_runtime_site_settings_projection_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists public.site_settings_admin_runtime_v1 as
select
  id,
  business_name,
  welcome_text,
  motto,
  hero_image_url,
  public_url,
  kds_url,
  photo_position,
  content_position,
  content_width,
  element_order,
  theme_preset,
  color_outer,
  color_panel,
  color_primary,
  color_accent,
  color_text,
  color_muted,
  typography,
  merchant_name,
  payment_instructions,
  qris_image_url,
  qris_enabled,
  admin_design,
  kds_design,
  design_system,
  require_table_qr_signature,
  updated_at
from public.site_settings
where id = 1;

alter table public.site_settings_admin_runtime_v1 add primary key (id);
alter table public.site_settings_admin_runtime_v1 enable row level security;

revoke all on table public.site_settings_admin_runtime_v1 from public;
grant select on table public.site_settings_admin_runtime_v1 to anon, authenticated;

create policy site_settings_admin_runtime_v1_read
on public.site_settings_admin_runtime_v1
for select
to anon, authenticated
using (id = 1);

create or replace function private.sync_site_settings_admin_runtime_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.site_settings_admin_runtime_v1(
    id,business_name,welcome_text,motto,hero_image_url,public_url,kds_url,
    photo_position,content_position,content_width,element_order,theme_preset,
    color_outer,color_panel,color_primary,color_accent,color_text,color_muted,
    typography,merchant_name,payment_instructions,qris_image_url,qris_enabled,
    admin_design,kds_design,design_system,require_table_qr_signature,updated_at
  ) values (
    new.id,new.business_name,new.welcome_text,new.motto,new.hero_image_url,new.public_url,new.kds_url,
    new.photo_position,new.content_position,new.content_width,new.element_order,new.theme_preset,
    new.color_outer,new.color_panel,new.color_primary,new.color_accent,new.color_text,new.color_muted,
    new.typography,new.merchant_name,new.payment_instructions,new.qris_image_url,new.qris_enabled,
    new.admin_design,new.kds_design,new.design_system,new.require_table_qr_signature,new.updated_at
  )
  on conflict (id) do update set
    business_name=excluded.business_name,
    welcome_text=excluded.welcome_text,
    motto=excluded.motto,
    hero_image_url=excluded.hero_image_url,
    public_url=excluded.public_url,
    kds_url=excluded.kds_url,
    photo_position=excluded.photo_position,
    content_position=excluded.content_position,
    content_width=excluded.content_width,
    element_order=excluded.element_order,
    theme_preset=excluded.theme_preset,
    color_outer=excluded.color_outer,
    color_panel=excluded.color_panel,
    color_primary=excluded.color_primary,
    color_accent=excluded.color_accent,
    color_text=excluded.color_text,
    color_muted=excluded.color_muted,
    typography=excluded.typography,
    merchant_name=excluded.merchant_name,
    payment_instructions=excluded.payment_instructions,
    qris_image_url=excluded.qris_image_url,
    qris_enabled=excluded.qris_enabled,
    admin_design=excluded.admin_design,
    kds_design=excluded.kds_design,
    design_system=excluded.design_system,
    require_table_qr_signature=excluded.require_table_qr_signature,
    updated_at=excluded.updated_at;
  return new;
end
$function$;

create trigger trg_sync_site_settings_admin_runtime_v1
after insert or update of business_name,welcome_text,motto,hero_image_url,public_url,kds_url,photo_position,content_position,content_width,element_order,theme_preset,color_outer,color_panel,color_primary,color_accent,color_text,color_muted,typography,merchant_name,payment_instructions,qris_image_url,qris_enabled,admin_design,kds_design,design_system,require_table_qr_signature,updated_at
on public.site_settings
for each row execute function private.sync_site_settings_admin_runtime_v1();
