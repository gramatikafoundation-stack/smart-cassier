-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909111731  Name: design_system_v2_hardening
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.site_settings drop constraint if exists site_settings_design_system_object;
alter table public.site_settings add constraint site_settings_design_system_object check (jsonb_typeof(design_system)='object');

alter table public.design_system_versions drop constraint if exists design_system_versions_payload_object;
alter table public.design_system_versions add constraint design_system_versions_payload_object check (jsonb_typeof(payload)='object');

create index if not exists design_system_versions_created_at_idx on public.design_system_versions(created_at desc);
create index if not exists design_system_versions_kind_created_at_idx on public.design_system_versions(kind,created_at desc);
create index if not exists design_system_versions_theme_created_at_idx on public.design_system_versions(theme_id,created_at desc);

comment on table public.design_system_versions is 'Immutable design-system version history. Contains design configuration only; operational orders/menu data are not stored here.';
comment on column public.site_settings.design_system is 'Published/draft design state for Theme -> General -> Site -> Page -> Element inheritance.';
