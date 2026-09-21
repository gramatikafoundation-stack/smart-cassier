-- SMART DIGITAL INDONESIA control-plane foundation.
-- Safe additive architecture: one isolated Supabase project per UMKM tenant.

create table if not exists private.platform_organizations (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null unique,
  status text not null default 'active'
    check (status in ('active','inactive','archived')),
  provider_organization_id text,
  provider_organization_name text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_organizations_slug_chk
    check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

create table if not exists private.platform_tenants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references private.platform_organizations(id) on delete restrict,
  slug text not null,
  name text not null,
  tenant_type text not null default 'umkm'
    check (tenant_type in ('umkm','internal','demo')),
  status text not null default 'active'
    check (status in ('onboarding','active','suspended','archived')),
  isolation_mode text not null default 'project_per_tenant'
    check (isolation_mode in ('project_per_tenant','shared_project')),
  source_template_key text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, slug),
  constraint platform_tenants_slug_chk
    check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

create table if not exists private.platform_tenant_resources (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references private.platform_tenants(id) on delete cascade,
  provider text not null
    check (provider in ('supabase','github','vercel','google','other')),
  resource_type text not null,
  role text not null default 'primary',
  external_id text,
  external_name text,
  url text,
  is_primary boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, provider, resource_type, role)
);

create table if not exists private.platform_clone_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references private.platform_organizations(id) on delete restrict,
  template_key text not null,
  name text not null,
  source_tenant_id uuid references private.platform_tenants(id) on delete set null,
  status text not null default 'active'
    check (status in ('draft','active','deprecated')),
  github_repo text not null,
  github_branch text not null default 'freeze-prep',
  supabase_isolation_mode text not null default 'project_per_tenant',
  vercel_topology text not null default 'three_projects_per_tenant',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, template_key)
);

alter table private.platform_organizations enable row level security;
alter table private.platform_tenants enable row level security;
alter table private.platform_tenant_resources enable row level security;
alter table private.platform_clone_templates enable row level security;

revoke all on private.platform_organizations from anon, authenticated;
revoke all on private.platform_tenants from anon, authenticated;
revoke all on private.platform_tenant_resources from anon, authenticated;
revoke all on private.platform_clone_templates from anon, authenticated;

drop trigger if exists trg_platform_organizations_updated_at on private.platform_organizations;
create trigger trg_platform_organizations_updated_at
before update on private.platform_organizations
for each row execute function public.set_updated_at();

drop trigger if exists trg_platform_tenants_updated_at on private.platform_tenants;
create trigger trg_platform_tenants_updated_at
before update on private.platform_tenants
for each row execute function public.set_updated_at();

drop trigger if exists trg_platform_tenant_resources_updated_at on private.platform_tenant_resources;
create trigger trg_platform_tenant_resources_updated_at
before update on private.platform_tenant_resources
for each row execute function public.set_updated_at();

drop trigger if exists trg_platform_clone_templates_updated_at on private.platform_clone_templates;
create trigger trg_platform_clone_templates_updated_at
before update on private.platform_clone_templates
for each row execute function public.set_updated_at();

insert into private.platform_organizations (
  slug,name,status,provider_organization_id,provider_organization_name,metadata
)
values (
  'smart-digital-indonesia',
  'SMART DIGITAL INDONESIA',
  'active',
  'hbpcwsvpxzhqznoxxndn',
  'gramatikafoundation@gmail''s Org',
  jsonb_build_object(
    'architecture','organization_project_per_tenant',
    'target_provider_name','SMART DIGITAL INDONESIA',
    'note','Logical platform umbrella created without moving the existing Rohmat production project.'
  )
)
on conflict (slug) do update
set name=excluded.name,
    status='active',
    provider_organization_id=excluded.provider_organization_id,
    provider_organization_name=excluded.provider_organization_name,
    metadata=private.platform_organizations.metadata || excluded.metadata,
    updated_at=now();

insert into private.platform_tenants (
  organization_id,slug,name,tenant_type,status,isolation_mode,source_template_key,metadata
)
select
  o.id,'rohmat-nasi-uduk','Rohmat Nasi Uduk','umkm','active',
  'project_per_tenant','rohmat-master-v1',
  jsonb_build_object('role','reference_tenant','production',true,'legacy_site_settings_id',1)
from private.platform_organizations o
where o.slug='smart-digital-indonesia'
on conflict (organization_id,slug) do update
set name=excluded.name,
    status='active',
    isolation_mode='project_per_tenant',
    source_template_key='rohmat-master-v1',
    metadata=private.platform_tenants.metadata || excluded.metadata,
    updated_at=now();

insert into private.platform_clone_templates (
  organization_id,template_key,name,source_tenant_id,status,
  github_repo,github_branch,supabase_isolation_mode,vercel_topology,metadata
)
select
  o.id,'rohmat-master-v1','Rohmat UMKM Clone Master',t.id,'active',
  'gramatikafoundation-stack/Rohmat-Master','freeze-prep',
  'project_per_tenant','three_projects_per_tenant',
  jsonb_build_object(
    'apps',jsonb_build_array('public','admin','kds'),
    'database_strategy','fresh_supabase_project_from_migrations',
    'source_of_truth','github',
    'operational_source_of_truth','supabase'
  )
from private.platform_organizations o
join private.platform_tenants t
  on t.organization_id=o.id and t.slug='rohmat-nasi-uduk'
where o.slug='smart-digital-indonesia'
on conflict (organization_id,template_key) do update
set name=excluded.name,
    source_tenant_id=excluded.source_tenant_id,
    status='active',
    github_repo=excluded.github_repo,
    github_branch=excluded.github_branch,
    supabase_isolation_mode=excluded.supabase_isolation_mode,
    vercel_topology=excluded.vercel_topology,
    metadata=private.platform_clone_templates.metadata || excluded.metadata,
    updated_at=now();

insert into private.platform_tenant_resources (
  tenant_id,provider,resource_type,role,external_id,external_name,url,is_primary,metadata
)
select t.id,x.provider,x.resource_type,x.role,x.external_id,x.external_name,x.url,true,x.metadata
from private.platform_tenants t
join private.platform_organizations o on o.id=t.organization_id
cross join lateral (
  values
    ('supabase','project','database','yybhpmjuywjxqurrrrxl','Rohmat Production','https://yybhpmjuywjxqurrrrxl.supabase.co','{}'::jsonb),
    ('github','repository','source',null,'gramatikafoundation-stack/Rohmat-Master','https://github.com/gramatikafoundation-stack/Rohmat-Master',jsonb_build_object('branch','freeze-prep')),
    ('vercel','project','admin','prj_CIEgIyyKRSrYahxDLkiK6m78wZ9Y','studio-pengelola-rohmat','https://studio-pengelola-rohmat.vercel.app','{}'::jsonb),
    ('vercel','project','public','prj_3JC9wVT3viMvinKvdG6hBucDhEGY','rohmat-pesan-bayar-publik','https://rohmat-pesan-bayar-publik.vercel.app','{}'::jsonb),
    ('vercel','project','kds','prj_vv1eioBBQdyto7a0QdRz3v2F3oFW','rohmat-kds-printer','https://rohmat-kds-printer.vercel.app','{}'::jsonb)
) as x(provider,resource_type,role,external_id,external_name,url,metadata)
where o.slug='smart-digital-indonesia'
  and t.slug='rohmat-nasi-uduk'
on conflict (tenant_id,provider,resource_type,role) do update
set external_id=excluded.external_id,
    external_name=excluded.external_name,
    url=excluded.url,
    is_primary=true,
    metadata=private.platform_tenant_resources.metadata || excluded.metadata,
    updated_at=now();

comment on table private.platform_organizations is
  'Control-plane organizations. SMART DIGITAL INDONESIA is the umbrella platform.';
comment on table private.platform_tenants is
  'UMKM tenants under a platform organization. Operational data remains isolated per Supabase project.';
comment on table private.platform_tenant_resources is
  'External infrastructure registry for each tenant: Supabase, GitHub, Vercel, etc.';
comment on table private.platform_clone_templates is
  'Clone-master definitions used to provision new UMKM tenants from Rohmat Master.';
