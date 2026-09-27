-- B4 disposable clone rehearsal. Creates a real tenant clone, proves isolation/template
-- invariants, then rolls everything back. Final queries assert zero residue.

begin;

create temp table b4_clone_result(payload jsonb) on commit drop;

do $$
declare
  v_clone jsonb;
  v_clone_id uuid;
  v_ref uuid;
  v_origin text:='https://b4-clone-rehearsal.invalid';
  v_ref_menu_sig text;
  v_clone_menu_sig text;
begin
  select reference_tenant_id into v_ref
  from private.platform_prototypes where prototype_key='smart-order-sdb-platform-v1';

  v_clone:=private.provision_tenant_from_master_v1(
    'smart-order-sdb-platform-v1',
    'b4-clone-rehearsal',
    'B4 Clone Rehearsal',
    v_origin,
    'b4.clone.rehearsal@example.invalid',
    jsonb_build_object(
      '2026','b4-rehearsal-sheet-2026',
      '2027','b4-rehearsal-sheet-2027',
      '2028','b4-rehearsal-sheet-2028',
      '2029','b4-rehearsal-sheet-2029',
      '2030','b4-rehearsal-sheet-2030'
    ),
    null
  );

  if not coalesce((v_clone->>'ok')::boolean,false) then raise exception 'b4_clone_failed'; end if;
  v_clone_id:=(v_clone->>'tenant_id')::uuid;

  if v_clone_id=v_ref then raise exception 'b4_clone_identity_not_unique'; end if;

  if not exists(
    select 1 from private.platform_tenants
    where id=v_clone_id and status='active'
      and isolation_mode='shared_database_rls'
      and source_prototype_key='smart-order-sdb-platform-v1'
  ) then raise exception 'b4_clone_tenant_contract_failed'; end if;

  if not exists(
    select 1 from private.tenant_runtime_config c
    where c.tenant_id=v_clone_id and c.enabled
      and c.public_origin=v_origin and c.admin_origin=v_origin and c.kds_origin=v_origin
      and c.settings->>'canonical_origin'=v_origin
      and c.settings->>'database_url'=v_origin||'/database'
      and c.settings->'surface_routes'->>'public'='/'
      and c.settings->'surface_routes'->>'admin'='/admin'
      and c.settings->'surface_routes'->>'kds'='/kds'
      and c.settings->'surface_routes'->>'database'='/database'
  ) then raise exception 'b4_clone_runtime_contract_failed'; end if;

  if (select count(*) from public.menu_items where tenant_id=v_clone_id) <>
     (select count(*) from public.menu_items where tenant_id=v_ref)
  then raise exception 'b4_clone_menu_count_mismatch'; end if;

  select md5(string_agg(name||'|'||category||'|'||price||'|'||display_order,';' order by display_order,name))
    into v_ref_menu_sig from public.menu_items where tenant_id=v_ref;
  select md5(string_agg(name||'|'||category||'|'||price||'|'||display_order,';' order by display_order,name))
    into v_clone_menu_sig from public.menu_items where tenant_id=v_clone_id;
  if v_ref_menu_sig is distinct from v_clone_menu_sig then raise exception 'b4_clone_menu_semantics_mismatch'; end if;

  if exists(
    select 1 from public.menu_items c
    join public.menu_items m on m.id=c.id
    where c.tenant_id=v_clone_id and m.tenant_id=v_ref
  ) then raise exception 'b4_clone_menu_id_collision'; end if;

  if (select count(*) from private.tenant_sheet_targets where tenant_id=v_clone_id and enabled)<>5
  then raise exception 'b4_clone_sheet_target_count'; end if;

  if exists(
    select 1
    from private.tenant_sheet_targets c
    join private.tenant_sheet_targets m
      on m.tenant_id=v_ref and m.spreadsheet_id=c.spreadsheet_id
    where c.tenant_id=v_clone_id
  ) then raise exception 'b4_master_sheet_id_leaked'; end if;

  if not exists(
    select 1 from private.tenant_writer_config
    where tenant_id=v_clone_id and not enabled and writer_url is null and writer_secret_id is null
  ) then raise exception 'b4_writer_secret_or_url_cloned'; end if;

  if (select count(*) from private.tenant_table_qr_signatures where tenant_id=v_clone_id and is_active) <>
     (select table_count from private.tenant_runtime_config where tenant_id=v_clone_id)
  then raise exception 'b4_clone_qr_count_mismatch'; end if;

  if exists(
    select 1
    from private.tenant_table_qr_signatures c
    join private.tenant_table_qr_signatures m
      on m.tenant_id=v_ref
     and m.table_number=c.table_number
     and m.signature_hash=c.signature_hash
    where c.tenant_id=v_clone_id
  ) then raise exception 'b4_master_qr_signature_leaked'; end if;

  if exists(select 1 from public.orders where tenant_id=v_clone_id)
    or exists(select 1 from public.order_events where tenant_id=v_clone_id)
    or exists(select 1 from public.order_history_archive where tenant_id=v_clone_id)
    or exists(select 1 from public.sheet_sync_outbox where tenant_id=v_clone_id)
    or exists(select 1 from private.admin_sessions where tenant_id=v_clone_id)
  then raise exception 'b4_operational_history_cloned'; end if;

  if (select qris_asset from private.tenant_runtime_config where tenant_id=v_clone_id) is not null
  then raise exception 'b4_qris_asset_cloned'; end if;

  if not coalesce((public.master_prototype_runtime_context(null,v_origin,'public')->>'ok')::boolean,false)
     or (public.master_prototype_runtime_context(null,v_origin,'public')->>'tenant_id')::uuid<>v_clone_id
  then raise exception 'b4_clone_origin_resolution_failed'; end if;

  if (public.master_prototype_runtime_context(null,
       (select public_origin from private.tenant_runtime_config where tenant_id=v_ref),'public')->>'tenant_id')::uuid<>v_ref
  then raise exception 'b4_master_origin_isolation_failed'; end if;

  insert into b4_clone_result(payload)
  values(jsonb_build_object(
    'ok',true,
    'contract','smart-order-b4-disposable-clone-rehearsal-v1',
    'clone_tenant_id',v_clone_id,
    'master_tenant_id',v_ref,
    'identity_unique',true,
    'single_domain_four_surface',true,
    'menu_semantics_preserved',true,
    'menu_ids_isolated',true,
    'sheet_targets',5,
    'master_sheet_ids_reused',false,
    'writer_secret_cloned',false,
    'writer_url_cloned',false,
    'qris_asset_cloned',false,
    'qr_signatures_unique',true,
    'operational_history_cloned',false,
    'origin_isolation',true,
    'source_edits_required',false,
    'source_clone_required',false,
    'database_project_clone_required',false,
    'fixture_persistence','rollback'
  ));
end $$;

select payload from b4_clone_result;
rollback;

select jsonb_build_object(
  'ok',
    (select count(*)=0 from private.platform_tenants where slug='b4-clone-rehearsal')
    and (select count(*)=0 from private.tenant_origin_aliases where origin='https://b4-clone-rehearsal.invalid'),
  'tenant_residue',(select count(*) from private.platform_tenants where slug='b4-clone-rehearsal'),
  'origin_residue',(select count(*) from private.tenant_origin_aliases where origin='https://b4-clone-rehearsal.invalid')
) b4_clone_cleanup;
