-- SMART ORDER B4 live logical-clone rehearsal v2.
-- Creates two independent tenant fixtures on the real shared schema, proves the
-- single-domain/four-surface contract and Google Drive database targets, then rolls back.

begin;
create temp table b4_clone_result(payload jsonb) on commit drop;

do $$
declare
  v_org uuid := '35f13d7e-8bca-4245-be49-e083555832db';
  a uuid := '22222222-2222-4222-8222-222222222222';
  b uuid := '33333333-3333-4333-8333-333333333333';
  ref uuid := (select reference_tenant_id from private.platform_prototypes where prototype_key='smart-order-sdb-platform-v1');
  tabs jsonb := '["Dashboard","Data Pemesan","Data Pesanan Makanan","Data Pesanan Minuman","Riwayat Pembayaran"]'::jsonb;
  routes jsonb := '{"public":"/","admin":"/admin","kds":"/kds","database":"/database"}'::jsonb;
  ra jsonb;
  rb jsonb;
  mismatch jsonb;
  unresolved jsonb;
  ak text;
  a_ok boolean := true;
  b_ok boolean := true;
  a_qr int;
  b_qr int;
  a_sheets int;
  b_sheets int;
  a_menu int;
  b_menu int;
  a_writer boolean;
  b_writer boolean;
  a_style boolean;
  b_style boolean;
begin
  if ref is null then raise exception 'b4_reference_tenant_missing'; end if;

  insert into private.platform_tenants(id,organization_id,slug,name,tenant_type,status,isolation_mode,metadata)
  values
    (a,v_org,'tenant-a','Tenant A','demo','active','shared_database_rls',jsonb_build_object('b4_rehearsal',true)),
    (b,v_org,'tenant-b','Tenant B','demo','active','shared_database_rls',jsonb_build_object('b4_rehearsal',true));

  insert into private.tenant_runtime_config(
    tenant_id,business_name,merchant_name,locale,currency,timezone,
    public_origin,admin_origin,kds_origin,qris_asset,
    storage_static_bucket,storage_payment_bucket,settings,enabled,
    table_count,require_table_qr_signature
  ) values
    (
      a,'Tenant A','Tenant A','id-ID','IDR','Asia/Jakarta',
      'https://tenant-a.example.com','https://tenant-a.example.com','https://tenant-a.example.com',
      'tenant://tenant-a/qris.png','merchant-static','payment-proofs',
      jsonb_build_object(
        'canonical_origin','https://tenant-a.example.com',
        'surface_routes',routes,
        'database_url','https://tenant-a.example.com/database',
        'database_provider','google_drive',
        'storage_namespace','tenant-a',
        'architecture','single_domain_four_surface_v2'
      ),true,20,true
    ),
    (
      b,'Tenant B','Tenant B','en-SG','SGD','Asia/Singapore',
      'https://tenant-b.example.com','https://tenant-b.example.com','https://tenant-b.example.com',
      'tenant://tenant-b/qris.png','merchant-static','payment-proofs',
      jsonb_build_object(
        'canonical_origin','https://tenant-b.example.com',
        'surface_routes',routes,
        'database_url','https://tenant-b.example.com/database',
        'database_provider','google_drive',
        'storage_namespace','tenant-b',
        'architecture','single_domain_four_surface_v2'
      ),true,12,true
    );

  insert into private.tenant_origin_aliases(tenant_id,app_kind,origin,enabled,alias_kind,metadata)
  values
    (a,'public','https://tenant-a.example.com',true,'canonical',
      jsonb_build_object('unified_routes',jsonb_build_array('/','/admin','/kds','/database'),'architecture','single_domain_four_surface_v2')),
    (b,'public','https://tenant-b.example.com',true,'canonical',
      jsonb_build_object('unified_routes',jsonb_build_array('/','/admin','/kds','/database'),'architecture','single_domain_four_surface_v2'));

  insert into private.tenant_memberships(tenant_id,email,role,is_active)
  values
    (a,'owner-a@example.com','superadmin',true),
    (b,'owner-b@example.com','superadmin',true);

  insert into private.tenant_writer_config(tenant_id,enabled,writer_url,max_attempts,expected_writer_version,pii_retention_days,writer_secret_id)
  values
    (a,false,null,10,4,365,null),
    (b,false,null,10,4,365,null);

  insert into private.tenant_sheet_targets(tenant_id,year,spreadsheet_id,label,enabled,expected_tabs)
  select a,y,'b4-tenant-a-'||y,'SMART ORDER — DATABASE '||y,true,tabs
  from generate_series(2026,2030) y
  union all
  select b,y,'b4-tenant-b-'||y,'SMART ORDER — DATABASE '||y,true,tabs
  from generate_series(2026,2030) y;

  insert into private.tenant_table_qr_signatures(tenant_id,table_number,signature_hash,is_active)
  select a,n,encode(extensions.digest(a::text||':'||n::text||':b4','sha256'),'hex'),true
  from generate_series(1,20) n
  union all
  select b,n,encode(extensions.digest(b::text||':'||n::text||':b4','sha256'),'hex'),true
  from generate_series(1,12) n;

  insert into public.tenant_site_settings_public_v1(
    tenant_id,business_name,welcome_text,motto,hero_image_url,public_url,
    merchant_name,payment_instructions,qris_image_url,qris_enabled,
    require_table_qr_signature,typography,design_system,updated_at
  )
  select a,'Tenant A','Selamat datang','Prototype clone rehearsal',s.hero_image_url,
    'https://tenant-a.example.com/','Tenant A','Prototype payment flow',null,false,true,
    s.typography,s.design_system,now()
  from public.tenant_site_settings_public_v1 s where s.tenant_id=ref
  union all
  select b,'Tenant B','Welcome','Prototype clone rehearsal',s.hero_image_url,
    'https://tenant-b.example.com/','Tenant B','Prototype payment flow',null,false,true,
    s.typography,s.design_system,now()
  from public.tenant_site_settings_public_v1 s where s.tenant_id=ref;

  insert into public.menu_items(
    id,name,category,price,description,image_url,is_favorite,is_visible,
    display_order,is_available,availability_note,tenant_id
  ) values
    ('b4-tenant-a-menu-001','Contoh Menu A','Nasi',10000,'B4 clone seed','',false,true,1,true,'',a),
    ('b4-tenant-b-menu-001','Example Menu B','Minuman',12000,'B4 clone seed','',false,true,1,true,'',b);

  foreach ak in array array['public','admin','kds','database'] loop
    ra:=public.master_prototype_resolve_origin('https://tenant-a.example.com',ak);
    rb:=public.master_prototype_resolve_origin('https://tenant-b.example.com',ak);

    a_ok:=a_ok
      and coalesce((ra->>'ok')::boolean,false)
      and (ra->>'tenant_id')::uuid=a
      and ra->>'resolved_origin'='https://tenant-a.example.com'
      and ra->>'surface_route'=routes->>ak;

    b_ok:=b_ok
      and coalesce((rb->>'ok')::boolean,false)
      and (rb->>'tenant_id')::uuid=b
      and rb->>'resolved_origin'='https://tenant-b.example.com'
      and rb->>'surface_route'=routes->>ak;
  end loop;

  mismatch:=public.master_prototype_runtime_context(a,'https://tenant-b.example.com','admin');
  unresolved:=public.master_prototype_resolve_origin('https://unknown-b4.example.com','public');

  select count(*) into a_qr from private.tenant_table_qr_signatures where tenant_id=a and is_active;
  select count(*) into b_qr from private.tenant_table_qr_signatures where tenant_id=b and is_active;
  select count(*) into a_sheets from private.tenant_sheet_targets where tenant_id=a and enabled;
  select count(*) into b_sheets from private.tenant_sheet_targets where tenant_id=b and enabled;
  select count(*) into a_menu from public.menu_items where tenant_id=a;
  select count(*) into b_menu from public.menu_items where tenant_id=b;
  select not enabled and expected_writer_version=4 and writer_url is null and writer_secret_id is null
    into a_writer from private.tenant_writer_config where tenant_id=a;
  select not enabled and expected_writer_version=4 and writer_url is null and writer_secret_id is null
    into b_writer from private.tenant_writer_config where tenant_id=b;
  select jsonb_typeof(design_system)='object' into a_style from public.tenant_site_settings_public_v1 where tenant_id=a;
  select jsonb_typeof(design_system)='object' into b_style from public.tenant_site_settings_public_v1 where tenant_id=b;

  if not a_ok or not b_ok then raise exception 'b4_four_surface_resolution_failed'; end if;
  if mismatch->>'error'<>'origin_tenant_mismatch' then raise exception 'b4_cross_tenant_origin_guard_failed'; end if;
  if coalesce((unresolved->>'ok')::boolean,false) then raise exception 'b4_unknown_origin_fail_closed_failed'; end if;
  if a_qr<>20 or b_qr<>12 then raise exception 'b4_signed_qr_count_failed'; end if;
  if a_sheets<>5 or b_sheets<>5 then raise exception 'b4_sheet_target_count_failed'; end if;
  if a_menu<>1 or b_menu<>1 then raise exception 'b4_menu_isolation_failed'; end if;
  if not coalesce(a_writer,false) or not coalesce(b_writer,false) then raise exception 'b4_writer_safe_default_failed'; end if;
  if not coalesce(a_style,false) or not coalesce(b_style,false) then raise exception 'b4_style_inheritance_failed'; end if;

  insert into b4_clone_result(payload)
  values(jsonb_build_object(
    'ok',true,
    'contract','smart-order-b4-live-logical-clone-v2',
    'topology','single_domain_four_surface',
    'shared_supabase_project','xrepmvbccalzhlcznrff',
    'tenant_a',jsonb_build_object(
      'tenant_id',a,'four_surface_resolution',a_ok,'signed_qr',a_qr,
      'google_drive_targets',a_sheets,'menu_seed_rows',a_menu,
      'writer_safe_default',a_writer,'style_inherited',a_style
    ),
    'tenant_b',jsonb_build_object(
      'tenant_id',b,'four_surface_resolution',b_ok,'signed_qr',b_qr,
      'google_drive_targets',b_sheets,'menu_seed_rows',b_menu,
      'writer_safe_default',b_writer,'style_inherited',b_style
    ),
    'cross_tenant_origin_rejected',mismatch->>'error'='origin_tenant_mismatch',
    'unknown_origin_fail_closed',not coalesce((unresolved->>'ok')::boolean,false),
    'source_edits_required',false,
    'source_clone_required',false,
    'database_project_clone_required',false,
    'fixture_persistence','rollback'
  ));
end $$;

select payload from b4_clone_result;
rollback;
