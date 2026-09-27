-- SMART ORDER B3 rollback-only integrated E2E proof.
-- Validates Admin snapshot -> Cashier order create -> KDS start/ready/complete
-- plus cross-tenant read/write rejection. The entire fixture is rolled back.

begin;
create temp table b3_e2e_result(payload jsonb) on commit drop;

do $$
declare
  v_tenant uuid;
  v_other uuid:=gen_random_uuid();
  v_org uuid;
  v_email extensions.citext;
  v_admin_token text:=repeat('a',64);
  v_kds_token text:=repeat('b',64);
  v_menu_id text;
  v_price integer;
  v_created jsonb;
  v_order_id uuid;
  v_admin_snapshot jsonb;
  v_cross jsonb;
  v_start jsonb;
  v_ready jsonb;
  v_complete jsonb;
  v_events integer;
  v_final_status text;
  v_final_payment text;
begin
  select p.reference_tenant_id,t.organization_id
    into v_tenant,v_org
  from private.platform_prototypes p
  join private.platform_tenants t on t.id=p.reference_tenant_id
  where p.prototype_key='smart-order-sdb-platform-v1'
  limit 1;

  select tm.email into v_email
  from private.tenant_memberships tm
  where tm.tenant_id=v_tenant and tm.is_active
  order by tm.created_at limit 1;

  select id,price into v_menu_id,v_price
  from public.menu_items
  where tenant_id=v_tenant and is_visible and is_available and price>0
  order by display_order,name limit 1;

  if v_tenant is null or v_email is null or v_menu_id is null then
    raise exception 'b3_e2e_precondition_failed';
  end if;

  insert into private.platform_tenants(id,organization_id,slug,name,tenant_type,status,isolation_mode,metadata)
  values(v_other,v_org,'b3-isolation-'||left(replace(v_other::text,'-',''),8),
         'B3 Isolation Fixture','umkm','active','shared_database_rls','{}'::jsonb);

  insert into private.tenant_runtime_config(
    tenant_id,business_name,merchant_name,public_origin,admin_origin,kds_origin,
    settings,enabled,table_count,require_table_qr_signature
  ) values(
    v_other,'B3 Isolation Fixture','B3 Isolation Fixture',
    'https://b3-'||left(replace(v_other::text,'-',''),8)||'.invalid',
    'https://b3-'||left(replace(v_other::text,'-',''),8)||'.invalid',
    'https://b3-'||left(replace(v_other::text,'-',''),8)||'.invalid',
    '{}'::jsonb,true,1,true
  );

  insert into private.tenant_memberships(tenant_id,email,role,is_active)
  values(v_other,v_email::text,'admin',true);

  insert into private.admin_sessions(token_hash,email,expires_at,session_scope,client_fingerprint_hash,tenant_id)
  values
    (encode(extensions.digest(v_admin_token,'sha256'),'hex'),v_email,now()+interval '1 hour','admin',repeat('c',64),v_tenant),
    (encode(extensions.digest(v_kds_token,'sha256'),'hex'),v_email,now()+interval '1 hour','kds',repeat('d',64),v_tenant);

  v_admin_snapshot:=public.smart_cashier_snapshot_tenant(v_tenant,v_admin_token);
  if not coalesce((v_admin_snapshot->>'ok')::boolean,false) then
    raise exception 'b3_admin_snapshot_failed';
  end if;

  v_cross:=public.smart_cashier_snapshot_tenant(v_other,v_admin_token);
  if coalesce((v_cross->>'ok')::boolean,false) then
    raise exception 'b3_cross_tenant_read_leak';
  end if;

  v_created:=public.smart_cashier_create_tenant(
    v_tenant,v_admin_token,'cashier_admin','B3 E2E Rollback',
    'take-away',null,
    jsonb_build_array(jsonb_build_object('menuId',v_menu_id,'quantity',1)),
    'cash',v_price,'B3 rollback-only E2E'
  );
  if not coalesce((v_created->>'ok')::boolean,false) then
    raise exception 'b3_cashier_create_failed';
  end if;

  v_order_id:=(v_created->'order'->>'id')::uuid;
  v_start:=public.kds_update_order_tenant(v_tenant,v_kds_token,v_order_id,'start');
  v_ready:=public.kds_update_order_tenant(v_tenant,v_kds_token,v_order_id,'ready');
  v_complete:=public.kds_update_order_tenant(v_tenant,v_kds_token,v_order_id,'complete');

  if not coalesce((v_start->>'ok')::boolean,false)
     or not coalesce((v_ready->>'ok')::boolean,false)
     or not coalesce((v_complete->>'ok')::boolean,false) then
    raise exception 'b3_kds_chain_failed';
  end if;

  select order_status,payment_status into v_final_status,v_final_payment
  from public.orders where tenant_id=v_tenant and id=v_order_id;

  select count(*) into v_events
  from public.order_events
  where tenant_id=v_tenant and order_id=v_order_id
    and event_type in ('kds_preparing','kds_ready','kds_completed');

  if v_final_status<>'completed' or v_final_payment<>'verified' or v_events<>3 then
    raise exception 'b3_order_chain_mismatch';
  end if;

  if coalesce((public.kds_update_order_tenant(v_other,v_kds_token,v_order_id,'ready')->>'ok')::boolean,false) then
    raise exception 'b3_cross_tenant_write_leak';
  end if;

  insert into b3_e2e_result(payload) values(jsonb_build_object(
    'ok',true,
    'contract','smart-order-b3-rollback-e2e-v1',
    'admin_snapshot',true,
    'cashier_create',true,
    'kds_start',true,
    'kds_ready',true,
    'kds_complete',true,
    'final_status',v_final_status,
    'payment_status',v_final_payment,
    'expected_kds_events',3,
    'observed_kds_events',v_events,
    'cross_tenant_read_rejected',true,
    'cross_tenant_write_rejected',true,
    'fixture_persistence','rollback'
  ));
end $$;

select payload from b3_e2e_result;
rollback;
