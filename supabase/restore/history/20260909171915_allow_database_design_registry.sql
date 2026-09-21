-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909171915  Name: allow_database_design_registry
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.design_element_registry drop constraint if exists design_element_registry_site;
alter table public.design_element_registry add constraint design_element_registry_site check (site = any (array['public'::text,'admin'::text,'kds'::text,'database'::text]));
