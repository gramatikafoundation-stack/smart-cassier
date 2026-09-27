-- SMART ORDER B1: Canonical Identity & Domain Consolidation v1
-- Scope: identity/origin/resource registry only. No order/payment/RLS business logic changes.
begin;

update private.platform_tenants
set metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
  'master_candidate', true,
  'candidate_prototype_key', 'smart-order-sdb-platform-v1',
  'canonical_origin', 'https://smart-order-sdb.vercel.app',
  'architecture_model', 'single_domain_four_surface_v1',
  'surface_routes', jsonb_build_object(
    'public','/','admin','/admin','kds','/kds','database','/database'
  ),
  'legacy_master_prototype', 'rohmat-master-prototype-v1'
), updated_at=now()
where id='d8bb901c-7399-485b-8743-b319fde148ac';

update private.tenant_runtime_config
set public_origin='https://smart-order-sdb.vercel.app',
    admin_origin='https://smart-order-sdb.vercel.app',
    kds_origin='https://smart-order-sdb.vercel.app',
    settings=coalesce(settings,'{}'::jsonb) || jsonb_build_object(
      'canonical_origin','https://smart-order-sdb.vercel.app',
      'public_url','https://smart-order-sdb.vercel.app/',
      'admin_url','https://smart-order-sdb.vercel.app/admin',
      'kds_url','https://smart-order-sdb.vercel.app/kds',
      'database_url','https://smart-order-sdb.vercel.app/database',
      'surface_routes',jsonb_build_object('public','/','admin','/admin','kds','/kds','database','/database')
    ),
    updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac';
update public.site_settings
set public_url='https://smart-order-sdb.vercel.app/',
    admin_url='https://smart-order-sdb.vercel.app/admin',
    kds_url='https://smart-order-sdb.vercel.app/kds',
    updated_at=now()
where id=1;

update private.tenant_origin_aliases
set app_kind='public',
    alias_kind='canonical',
    enabled=true,
    metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'architecture','single_domain_four_surface_v1',
      'unified_routes',jsonb_build_array('/','/admin','/kds','/database')
    ),
    updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac'
  and origin='https://smart-order-sdb.vercel.app';

update private.tenant_origin_aliases
set alias_kind='custom',
    enabled=true,
    metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'status','legacy_redirect',
      'redirect_to','https://smart-order-sdb.vercel.app',
      'canonical',false
    ),
    updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac'
  and origin='https://smart-cassier.vercel.app';

update private.tenant_origin_aliases
set enabled=false,
    metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object('status','stale_preview_disabled_b1'),
    updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac'
  and alias_kind='preview';
update private.integration_registry
set canonical_url='https://smart-order-sdb.vercel.app',
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('surface','public','canonical_origin','https://smart-order-sdb.vercel.app'),
    updated_at=now()
where service_key='public_web';

update private.integration_registry
set canonical_url='https://smart-order-sdb.vercel.app/admin',
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('surface','admin','canonical_origin','https://smart-order-sdb.vercel.app'),
    updated_at=now()
where service_key='admin_web';

update private.integration_registry
set canonical_url='https://smart-order-sdb.vercel.app/kds',
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('surface','kds','canonical_origin','https://smart-order-sdb.vercel.app'),
    updated_at=now()
where service_key='kds_web';

insert into private.integration_registry
(service_key,display_name,service_type,canonical_url,contract_version,critical,auth_mode,dependencies,enabled,metadata,updated_at)
values
('database_web','Database / Google Sheets','frontend','https://smart-order-sdb.vercel.app/database','database-route-v1',true,'custom_session',array['postgres_core','sheet_worker'],true,
 jsonb_build_object('surface','database','canonical_origin','https://smart-order-sdb.vercel.app','spreadsheet_provider','google_drive'),now())
on conflict (service_key) do update
set canonical_url=excluded.canonical_url, contract_version=excluded.contract_version,
    enabled=true, metadata=excluded.metadata, updated_at=now();
update private.production_change_control
set canonical_target=case component
  when 'public-site' then 'https://smart-order-sdb.vercel.app/'
  when 'admin-site' then 'https://smart-order-sdb.vercel.app/admin'
  when 'kds-site' then 'https://smart-order-sdb.vercel.app/kds'
  when 'kds-redirect' then 'https://smart-order-sdb.vercel.app/kds'
  else canonical_target end,
  note=coalesce(note,'') || E'\nB1 canonical identity: smart-order-sdb.vercel.app.',
  updated_at=now()
where component in ('public-site','admin-site','kds-site','kds-redirect');

insert into private.production_change_control
(component,component_type,locked,baseline_version,baseline_sha256,canonical_target,allowed_change_scope,note,updated_at)
values
('database-site','vercel-production',true,'candidate-b1',null,'https://smart-order-sdb.vercel.app/database','database-route-only',
 'B1 candidate fourth surface; protected Admin database/Google Sheets control route.',now())
on conflict (component) do update
set canonical_target=excluded.canonical_target, note=excluded.note, updated_at=now();

update private.release_component_registry
set canonical_target=case component_key
  when 'public_site' then 'https://smart-order-sdb.vercel.app/'
  when 'admin_site' then 'https://smart-order-sdb.vercel.app/admin'
  when 'kds_site' then 'https://smart-order-sdb.vercel.app/kds'
  when 'kds_redirect' then 'https://smart-order-sdb.vercel.app/kds'
  else canonical_target end,
  last_verified_at=now(),
  notes=coalesce(notes,'') || E'\nB1 canonical identity target migrated to smart-order-sdb.vercel.app.'
where component_key in ('public_site','admin_site','kds_site','kds_redirect');
insert into private.release_component_registry
(component_key,display_name,component_type,canonical_target,expected_version,expected_sha256,deployment_ref,rollback_ref,lifecycle,critical,change_control_component,source_mode,last_verified_at,notes)
values
('database_site','Database / Google Sheets','vercel-production','https://smart-order-sdb.vercel.app/database','candidate-b1',null,null,
 'legacy-admin-database-surface','canonical',true,'database-site','vercel-route',now(),
 'B1 candidate fourth surface. Final immutable deployment pin is deferred to final freeze.')
on conflict (component_key) do update
set canonical_target=excluded.canonical_target, expected_version=excluded.expected_version,
    lifecycle='canonical', critical=true, change_control_component='database-site',
    source_mode='vercel-route', last_verified_at=now(), notes=excluded.notes;

update private.public_warmup_state
set target_url='https://smart-order-sdb.vercel.app/', updated_at=now()
where id=1;

update private.platform_tenant_resources
set external_id='xrepmvbccalzhlcznrff', external_name='SMART ORDER Production',
    url='https://xrepmvbccalzhlcznrff.supabase.co',
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('status','active','architecture','single_domain_four_surface_v1'),
    updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac' and provider='supabase' and role='database';

update private.platform_tenant_resources
set external_name='gramatikafoundation-stack/smart-cassier',
    url='https://github.com/gramatikafoundation-stack/smart-cassier',
    metadata=jsonb_build_object('branch','batch5-integrated-qa-security-freeze-20260926','status','active'),
    updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac' and provider='github' and role='source';
update private.platform_tenant_resources
set is_primary=false,
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'status','legacy_multi_domain','deprecated_for_new_tenants',true
    ),
    updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac'
  and provider='vercel' and role in ('public','admin','kds');

insert into private.platform_tenant_resources
(tenant_id,provider,resource_type,role,external_id,external_name,url,is_primary,metadata,created_at,updated_at)
values
('d8bb901c-7399-485b-8743-b319fde148ac','vercel','project','unified_app',
 'prj_5xph62xWBNqRRR3MZ3bgA0qZU9NK','smart-order-sdb','https://smart-order-sdb.vercel.app',true,
 jsonb_build_object('architecture','single_domain_four_surface_v1','routes',jsonb_build_object('public','/','admin','/admin','kds','/kds','database','/database')),now(),now())
on conflict (tenant_id,provider,resource_type,role) do update
set external_id=excluded.external_id,external_name=excluded.external_name,url=excluded.url,is_primary=true,metadata=excluded.metadata,updated_at=now();

insert into private.platform_tenant_resources
(tenant_id,provider,resource_type,role,external_id,external_name,url,is_primary,metadata,created_at,updated_at)
values
('d8bb901c-7399-485b-8743-b319fde148ac','google','spreadsheet_collection','database',
 'tenant_sheet_targets','SMART ORDER Google Sheets 2026-2030','https://smart-order-sdb.vercel.app/database',true,
 jsonb_build_object('provider','google_drive','target_table','private.tenant_sheet_targets','years',jsonb_build_array(2026,2027,2028,2029,2030)),now(),now())
on conflict (tenant_id,provider,resource_type,role) do update
set external_id=excluded.external_id,external_name=excluded.external_name,url=excluded.url,is_primary=true,metadata=excluded.metadata,updated_at=now();
insert into private.platform_prototypes
(organization_id,prototype_key,name,reference_tenant_id,status,github_repo,github_branch,release_tag,supabase_project_ref,tenancy_mode,metadata,created_at,updated_at)
values
('35f13d7e-8bca-4245-be49-e083555832db','smart-order-sdb-platform-v1','SMART ORDER SDB Master Candidate',
 'd8bb901c-7399-485b-8743-b319fde148ac','draft','gramatikafoundation-stack/smart-cassier',
 'batch5-integrated-qa-security-freeze-20260926',null,'xrepmvbccalzhlcznrff','shared_database_rls',
 jsonb_build_object(
   'apps',jsonb_build_array('public','admin','kds','database'),
   'freeze_state','candidate_b1',
   'canonical_origin','https://smart-order-sdb.vercel.app',
   'deployment_topology','single_domain_four_surface',
   'surface_routes',jsonb_build_object('public','/','admin','/admin','kds','/kds','database','/database'),
   'spreadsheet_provider','google_drive',
   'legacy_master_key','rohmat-master-prototype-v1',
   'source_of_truth','github',
   'operational_source_of_truth','supabase'
 ),now(),now())
on conflict (organization_id,prototype_key) do update
set name=excluded.name,reference_tenant_id=excluded.reference_tenant_id,status='draft',
    github_repo=excluded.github_repo,github_branch=excluded.github_branch,
    release_tag=null,supabase_project_ref=excluded.supabase_project_ref,
    tenancy_mode=excluded.tenancy_mode,metadata=excluded.metadata,updated_at=now();

-- Compatibility RPC wrappers accept the new canonical origin without removing rollback origins yet.
do $$
declare r record; ddl text; old_tuple text; new_tuple text;
begin
  old_tuple := '(''https://rohmat-kds-printer.vercel.app'',''https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app'')';
  new_tuple := '(''https://smart-order-sdb.vercel.app'',''https://smart-cassier.vercel.app'',''https://rohmat-kds-printer.vercel.app'',''https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app'')';
  for r in
    select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where p.prokind='f' and n.nspname='public'
      and p.proname in ('admin_password_login','admin_password_logout','admin_password_session_info','kds_set_availability','kds_snapshot','kds_update_order')
  loop
    ddl := pg_get_functiondef(r.oid);
    if position(old_tuple in ddl)>0 then
      execute replace(ddl,old_tuple,new_tuple);
    end if;
  end loop;
end $$;

commit;
