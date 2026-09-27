-- SMART ORDER B4.1: immutable clone-template snapshot + safe tenant provisioning contract.
-- Scope: cloneability only. Does NOT promote the candidate.

begin;

create table if not exists private.master_template_snapshots (
  prototype_key text primary key,
  snapshot_version text not null,
  source_tenant_id uuid not null references private.platform_tenants(id) on delete restrict,
  source_git_sha text not null check (source_git_sha ~ '^[0-9a-f]{40}$'),
  source_migration_head text not null check (source_migration_head ~ '^[0-9]{14}$'),
  snapshot jsonb not null,
  snapshot_sha256 text not null check (snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  frozen boolean not null default true,
  check (jsonb_typeof(snapshot)='object')
);
alter table private.master_template_snapshots enable row level security;
revoke all on private.master_template_snapshots from public,anon,authenticated;
grant select on private.master_template_snapshots to service_role;

create or replace function private.master_template_snapshot_guard_b4()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  raise exception 'master_template_snapshot_immutable';
end
$$;
revoke all on function private.master_template_snapshot_guard_b4() from public,anon,authenticated;

drop trigger if exists trg_master_template_snapshot_immutable_b4 on private.master_template_snapshots;
create trigger trg_master_template_snapshot_immutable_b4
before update or delete on private.master_template_snapshots
for each row execute function private.master_template_snapshot_guard_b4();

do $$
declare
  v_tenant uuid;
  v_snapshot jsonb;
  v_sha text;
begin
  select reference_tenant_id into v_tenant
  from private.platform_prototypes
  where prototype_key='smart-order-sdb-platform-v1'
    and status='draft'
    and metadata->>'b3_gate'='passed'
  limit 1;
  if v_tenant is null then raise exception 'b4_candidate_b3_missing'; end if;

  if not coalesce((private.release_engineering_status()->>'ok')::boolean,false) then
    raise exception 'b4_release_engineering_not_ready';
  end if;

  select jsonb_build_object(
    'contract','smart-order-master-template-v1',
    'architecture','single_domain_four_surface_v1',
    'source_tenant_id',v_tenant,
    'surface_routes',jsonb_build_object('public','/','admin','/admin','kds','/kds','database','/database'),
    'runtime',jsonb_build_object(
      'locale',c.locale,'currency',c.currency,'timezone',c.timezone,
      'storage_static_bucket',c.storage_static_bucket,
      'storage_payment_bucket',c.storage_payment_bucket,
      'table_count',c.table_count,
      'require_table_qr_signature',c.require_table_qr_signature,
      'settings',coalesce(c.settings,'{}'::jsonb)
        - 'canonical_origin' - 'database_url'
        - 'public_url' - 'admin_url' - 'kds_url'
        - 'google_sheet_url'
        - 'qris_image_url' - 'qris_enabled' - 'payment_instructions'
        - 'business_name' - 'merchant_name'
        - 'updated_at' - 'updated_by'
        - 'security_contract'
    ),
    'menu',coalesce((
      select jsonb_agg(jsonb_build_object(
        'source_id',m.id,'name',m.name,'category',m.category,'price',m.price,
        'description',m.description,'image_url',m.image_url,'is_favorite',m.is_favorite,
        'is_visible',m.is_visible,'display_order',m.display_order,
        'is_available',m.is_available,'availability_note',m.availability_note
      ) order by m.display_order,m.id)
      from public.menu_items m where m.tenant_id=v_tenant
    ),'[]'::jsonb),
    'sheet_blueprint',coalesce((
      select jsonb_agg(jsonb_build_object(
        'year',s.year,'label',s.label,'expected_tabs',s.expected_tabs
      ) order by s.year)
      from private.tenant_sheet_targets s
      where s.tenant_id=v_tenant and s.enabled
    ),'[]'::jsonb),
    'writer_blueprint',coalesce((
      select jsonb_build_object(
        'max_attempts',w.max_attempts,
        'expected_writer_version',w.expected_writer_version,
        'pii_retention_days',w.pii_retention_days,
        'clone_enabled',false,
        'clone_writer_url',null,
        'clone_writer_secret_id',null
      )
      from private.tenant_writer_config w where w.tenant_id=v_tenant
    ),jsonb_build_object(
      'max_attempts',10,'expected_writer_version',4,'pii_retention_days',365,
      'clone_enabled',false,'clone_writer_url',null,'clone_writer_secret_id',null
    )),
    'design_system',coalesce(c.settings->'design_system','{}'::jsonb),
    'clone_exclusions',jsonb_build_array(
      'orders','order_events','order_history_archive','admin_sessions',
      'payment_proofs','sheet_sync_outbox','reliability_history',
      'spreadsheet_ids','writer_url','writer_secret','admin_passwords',
      'qris_asset','qris_image_url','payment_instructions','table_qr_signature_hashes'
    )
  )
  into v_snapshot
  from private.tenant_runtime_config c
  where c.tenant_id=v_tenant and c.enabled;

  if v_snapshot is null then raise exception 'b4_snapshot_build_failed'; end if;
  v_sha:=encode(extensions.digest(convert_to(v_snapshot::text,'UTF8'),'sha256'),'hex');

  insert into private.master_template_snapshots(
    prototype_key,snapshot_version,source_tenant_id,source_git_sha,
    source_migration_head,snapshot,snapshot_sha256,frozen
  )
  values(
    'smart-order-sdb-platform-v1','v1',v_tenant,
    '91ccddb8f90d1aa56dbd7335c2952bd0af98d36c',
    '20260927144325',v_snapshot,v_sha,true
  )
  on conflict(prototype_key) do nothing;

  if not exists(
    select 1 from private.master_template_snapshots
    where prototype_key='smart-order-sdb-platform-v1'
      and frozen and source_tenant_id=v_tenant
      and source_git_sha='91ccddb8f90d1aa56dbd7335c2952bd0af98d36c'
      and source_migration_head='20260927144325'
      and snapshot_sha256=v_sha
  ) then raise exception 'b4_snapshot_conflict'; end if;
end $$;

create or replace function private.provision_tenant_from_master_v1(
  p_prototype_key text,
  p_slug text,
  p_business_name text,
  p_origin text,
  p_admin_email text,
  p_sheet_targets jsonb default '{}'::jsonb,
  p_qris_asset text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_snap private.master_template_snapshots%rowtype;
  v_ref private.platform_tenants%rowtype;
  v_tenant uuid:=extensions.gen_random_uuid();
  v_origin text;
  v_runtime jsonb;
  v_writer jsonb;
  v_menu jsonb;
  v_item jsonb;
  v_sheet jsonb;
  v_year integer;
  v_sheet_id text;
  v_menu_count integer:=0;
  v_sheet_count integer:=0;
  v_table_count integer;
  v_email text;
begin
  if coalesce(p_slug,'') !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'invalid_tenant_slug';
  end if;
  if length(trim(coalesce(p_business_name,'')))<1 then raise exception 'invalid_business_name'; end if;
  v_origin:=private.normalize_https_origin(p_origin);
  if v_origin is null then raise exception 'invalid_origin'; end if;
  v_email:=lower(trim(coalesce(p_admin_email,'')));
  if v_email='' or position('@' in v_email)<2 then raise exception 'invalid_admin_email'; end if;
  if coalesce(jsonb_typeof(p_sheet_targets),'null')<>'object' then raise exception 'invalid_sheet_targets'; end if;

  select * into v_snap
  from private.master_template_snapshots
  where prototype_key=p_prototype_key and frozen;
  if v_snap.prototype_key is null then raise exception 'master_snapshot_unavailable'; end if;

  select * into v_ref from private.platform_tenants where id=v_snap.source_tenant_id;
  if v_ref.id is null then raise exception 'master_source_tenant_unavailable'; end if;

  v_runtime:=v_snap.snapshot->'runtime';
  v_writer:=v_snap.snapshot->'writer_blueprint';
  v_menu:=v_snap.snapshot->'menu';
  v_table_count:=coalesce((v_runtime->>'table_count')::integer,20);

  insert into private.platform_tenants(
    id,organization_id,slug,name,tenant_type,status,isolation_mode,
    source_template_key,source_prototype_key,metadata
  ) values(
    v_tenant,v_ref.organization_id,p_slug,trim(p_business_name),'umkm','active','shared_database_rls',
    p_prototype_key,p_prototype_key,
    jsonb_build_object(
      'cloned_from_prototype',p_prototype_key,
      'master_snapshot_sha256',v_snap.snapshot_sha256,
      'architecture_model','single_domain_four_surface_v1',
      'canonical_origin',v_origin,
      'surface_routes',v_snap.snapshot->'surface_routes',
      'provisioned_at',now()
    )
  );

  insert into private.tenant_runtime_config(
    tenant_id,business_name,merchant_name,locale,currency,timezone,
    public_origin,admin_origin,kds_origin,qris_asset,
    storage_static_bucket,storage_payment_bucket,settings,enabled,
    table_count,require_table_qr_signature
  ) values(
    v_tenant,trim(p_business_name),trim(p_business_name),
    coalesce(v_runtime->>'locale','id-ID'),
    coalesce(v_runtime->>'currency','IDR'),
    coalesce(v_runtime->>'timezone','Asia/Jakarta'),
    v_origin,v_origin,v_origin,p_qris_asset,
    v_runtime->>'storage_static_bucket',v_runtime->>'storage_payment_bucket',
    coalesce(v_runtime->'settings','{}'::jsonb)
      || jsonb_build_object(
        'canonical_origin',v_origin,
        'database_url',v_origin||'/database',
        'surface_routes',v_snap.snapshot->'surface_routes',
        'cloned_from_prototype',p_prototype_key,
        'master_snapshot_sha256',v_snap.snapshot_sha256,
        'require_table_qr_signature',true,
        'business_name',trim(p_business_name),
        'merchant_name',trim(p_business_name),
        'public_url',v_origin,
        'admin_url',v_origin,
        'kds_url',v_origin,
        'google_sheet_url',null,
        'qris_image_url',null,
        'qris_enabled',false,
        'payment_instructions','',
        'security_contract',jsonb_build_object(
          'version','smart-order-master-runtime-security-v2',
          'hardened_at',now(),
          'client_rls','required',
          'admin_session_ttl_hours',6,
          'kds_session_ttl_hours',4,
          'admin_gateway_fingerprint_binding',true,
          'kds_fingerprint_binding',true,
          'signed_table_qr',true,
          'legacy_internal_rpc_direct_access',false
        )
      ),
    true,v_table_count,true
  );

  insert into private.tenant_origin_aliases(
    tenant_id,app_kind,origin,enabled,alias_kind,metadata
  ) values(
    v_tenant,'public',v_origin,true,'canonical',
    jsonb_build_object(
      'architecture','single_domain_four_surface_v1',
      'unified_routes',jsonb_build_array('/','/admin','/kds','/database'),
      'cloned_from_prototype',p_prototype_key
    )
  );

  insert into private.tenant_memberships(tenant_id,email,role,is_active)
  values(v_tenant,v_email,'superadmin',true);

  insert into private.tenant_writer_config(
    tenant_id,enabled,writer_url,max_attempts,expected_writer_version,
    pii_retention_days,writer_secret_id
  ) values(
    v_tenant,false,null,
    coalesce((v_writer->>'max_attempts')::integer,10),
    coalesce((v_writer->>'expected_writer_version')::integer,4),
    coalesce((v_writer->>'pii_retention_days')::integer,365),
    null
  );

  for v_sheet in select value from jsonb_array_elements(coalesce(v_snap.snapshot->'sheet_blueprint','[]'::jsonb))
  loop
    v_year:=(v_sheet->>'year')::integer;
    v_sheet_id:=nullif(p_sheet_targets->>v_year::text,'');
    if v_sheet_id is null then
      v_sheet_id:='provision://google-drive/'||v_tenant::text||'/'||v_year::text;
    end if;
    insert into private.tenant_sheet_targets(
      tenant_id,year,spreadsheet_id,label,enabled,expected_tabs
    ) values(
      v_tenant,v_year,v_sheet_id,
      coalesce(v_sheet->>'label','SMART ORDER — DATABASE '||v_year),
      true,coalesce(v_sheet->'expected_tabs','[]'::jsonb)
    );
    v_sheet_count:=v_sheet_count+1;
  end loop;

  for v_item in select value from jsonb_array_elements(coalesce(v_menu,'[]'::jsonb))
  loop
    insert into public.menu_items(
      id,name,category,price,description,image_url,is_favorite,is_visible,
      display_order,updated_by,is_available,availability_note,tenant_id
    ) values(
      left(v_item->>'source_id',45)||'-'||substr(md5(v_tenant::text||':'||(v_item->>'source_id')),1,8),
      v_item->>'name',v_item->>'category',(v_item->>'price')::integer,
      coalesce(v_item->>'description',''),coalesce(v_item->>'image_url',''),
      coalesce((v_item->>'is_favorite')::boolean,false),
      coalesce((v_item->>'is_visible')::boolean,true),
      (v_item->>'display_order')::integer,null,
      coalesce((v_item->>'is_available')::boolean,true),
      coalesce(v_item->>'availability_note',''),
      v_tenant
    );
    v_menu_count:=v_menu_count+1;
  end loop;

  insert into private.tenant_table_qr_signatures(tenant_id,table_number,signature_hash,is_active)
  select v_tenant,g,
         encode(extensions.digest(convert_to(v_tenant::text||':'||g::text||':'||encode(extensions.gen_random_bytes(32),'hex'),'UTF8'),'sha256'),'hex'),
         true
  from generate_series(1,v_table_count) g;

  perform private.sync_tenant_public_settings_projection(v_tenant);

  return jsonb_build_object(
    'ok',true,
    'contract','smart-order-master-clone-v1',
    'tenant_id',v_tenant,
    'slug',p_slug,
    'origin',v_origin,
    'source_prototype_key',p_prototype_key,
    'snapshot_sha256',v_snap.snapshot_sha256,
    'menu_count',v_menu_count,
    'sheet_target_count',v_sheet_count,
    'table_signature_count',v_table_count,
    'writer_enabled',false,
    'secrets_cloned',false,
    'history_cloned',false,
    'source_edits_required',false,
    'source_clone_required',false,
    'database_project_clone_required',false
  );
end
$$;
revoke all on function private.provision_tenant_from_master_v1(text,text,text,text,text,jsonb,text)
from public,anon,authenticated;
grant execute on function private.provision_tenant_from_master_v1(text,text,text,text,text,jsonb,text)
to service_role;

-- Keep release engineering exact while this is still a draft B4 foundation.
update private.release_policy
set source_control_mode='git_b4_clone_foundation',
    ci_status='github_actions_b4_clone_foundation_candidate',
    notes=coalesce(notes,'') || E'\n2026-09-27 B4.1: immutable template snapshot + safe clone provisioning contract. Candidate remains draft; promotion forbidden until disposable clone rehearsal passes.',
    updated_at=now()
where id=1;

insert into private.release_baseline(
  id,release_label,migration_head,schema_fingerprint,cron_fingerprint,
  manifest_fingerprint,captured_at,notes
)
values(
  1,'b4-clone-foundation-20260927','20260927160000',
  private.release_schema_fingerprint(),private.release_cron_fingerprint(),
  private.release_manifest_fingerprint(),now(),
  'B4.1 clone foundation baseline. Candidate remains draft; no master promotion.'
)
on conflict(id) do update
set release_label=excluded.release_label,
    migration_head=excluded.migration_head,
    schema_fingerprint=excluded.schema_fingerprint,
    cron_fingerprint=excluded.cron_fingerprint,
    manifest_fingerprint=excluded.manifest_fingerprint,
    captured_at=excluded.captured_at,
    notes=excluded.notes;

commit;
