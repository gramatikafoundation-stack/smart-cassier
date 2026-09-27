-- DR-only deterministic identity bridge.
-- Production's Sep-18 platform foundation generated these IDs once, while B1 later
-- referenced them as stable IDs. Replaying the original INSERTs on a fresh database
-- would generate different UUIDs, so recovery must seed the production identities first.

create table if not exists private.platform_organizations (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null unique,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  provider_organization_id text,
  provider_organization_name text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_organizations_slug_chk check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

create table if not exists private.platform_tenants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references private.platform_organizations(id) on delete restrict,
  slug text not null,
  name text not null,
  tenant_type text not null default 'umkm' check (tenant_type in ('umkm','internal','demo')),
  status text not null default 'active' check (status in ('onboarding','active','suspended','archived')),
  isolation_mode text not null default 'project_per_tenant' check (isolation_mode in ('project_per_tenant','shared_project')),
  source_template_key text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,slug),
  constraint platform_tenants_slug_chk check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

insert into private.platform_organizations(
  id,slug,name,status,provider_organization_id,provider_organization_name,metadata
) values(
  '35f13d7e-8bca-4245-be49-e083555832db',
  'smart-digital-indonesia','SMART DIGITAL INDONESIA','active',
  null,'sanitized-recovery',
  jsonb_build_object('dr_seed',true,'identity_source','production_stable_id')
)
on conflict(slug) do update set id=excluded.id;

insert into private.platform_tenants(
  id,organization_id,slug,name,tenant_type,status,isolation_mode,source_template_key,metadata
) values(
  'd8bb901c-7399-485b-8743-b319fde148ac',
  '35f13d7e-8bca-4245-be49-e083555832db',
  'rohmat-nasi-uduk','Rohmat Nasi Uduk','umkm','active','project_per_tenant','rohmat-master-v1',
  jsonb_build_object('role','reference_tenant','production',true,'legacy_site_settings_id',1,'dr_seed',true)
)
on conflict(organization_id,slug) do update
set id=excluded.id,name=excluded.name,status='active',metadata=private.platform_tenants.metadata||excluded.metadata;
