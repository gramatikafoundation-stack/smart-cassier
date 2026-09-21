-- Harden SMART DIGITAL INDONESIA control-plane tables.

create index if not exists platform_clone_templates_source_tenant_idx
  on private.platform_clone_templates(source_tenant_id);

drop policy if exists platform_organizations_service_role_all on private.platform_organizations;
create policy platform_organizations_service_role_all
  on private.platform_organizations
  for all to service_role
  using (true) with check (true);

drop policy if exists platform_tenants_service_role_all on private.platform_tenants;
create policy platform_tenants_service_role_all
  on private.platform_tenants
  for all to service_role
  using (true) with check (true);

drop policy if exists platform_tenant_resources_service_role_all on private.platform_tenant_resources;
create policy platform_tenant_resources_service_role_all
  on private.platform_tenant_resources
  for all to service_role
  using (true) with check (true);

drop policy if exists platform_clone_templates_service_role_all on private.platform_clone_templates;
create policy platform_clone_templates_service_role_all
  on private.platform_clone_templates
  for all to service_role
  using (true) with check (true);
