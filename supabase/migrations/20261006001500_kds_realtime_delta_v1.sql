-- SMART ORDER realtime delivery v1
-- Surgical, additive: enrich KDS broadcasts and add tenant-scoped delta/visibility RPCs.
begin;

create or replace function private.kds_realtime_broadcast()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_tenant uuid;
  v_topic text;
  v_kind text;
  v_entity_id text;
  v_version timestamptz;
  v_payload jsonb;
begin
  v_tenant := case when tg_op='DELETE' then old.tenant_id else new.tenant_id end;
  if v_tenant is null then
    return case when tg_op='DELETE' then old else new end;
  end if;

  select c.topic into v_topic
  from private.kds_realtime_channels c
  where c.tenant_id=v_tenant and c.enabled;

  if v_topic is not null then
    if tg_table_name='orders' then
      v_kind:='orders';
      v_entity_id:=(case when tg_op='DELETE' then old.id else new.id end)::text;
      v_version:=case when tg_op='DELETE' then coalesce(old.updated_at,clock_timestamp()) else coalesce(new.updated_at,clock_timestamp()) end;
      v_payload:=jsonb_build_object(
        'kind',v_kind,
        'operation',lower(tg_op),
        'entity_id',v_entity_id,
        'tenant_id',v_tenant,
        'version',v_version,
        'order_status',case when tg_op='DELETE' then old.order_status else new.order_status end,
        'payment_status',case when tg_op='DELETE' then old.payment_status else new.payment_status end,
        'order_source',case when tg_op='DELETE' then old.order_source else new.order_source end,
        'at',clock_timestamp()
      );
    else
      v_kind:='menu';
      v_entity_id:=(case when tg_op='DELETE' then old.id else new.id end)::text;
      v_version:=case when tg_op='DELETE' then coalesce(old.updated_at,clock_timestamp()) else coalesce(new.updated_at,clock_timestamp()) end;
      v_payload:=jsonb_build_object(
        'kind',v_kind,
        'operation',lower(tg_op),
        'entity_id',v_entity_id,
        'tenant_id',v_tenant,
        'version',v_version,
        'at',clock_timestamp()
      );
    end if;

    perform realtime.send(v_payload,'kds_change',v_topic,false);
  end if;

  return case when tg_op='DELETE' then old else new end;
end
$$;

revoke all on function private.kds_realtime_broadcast() from public,anon,authenticated;

create or replace function public.kds_delta_tenant(
  p_tenant_id uuid,
  p_token text,
  p_order_id uuid default null,
  p_menu_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_order jsonb;
  v_menu jsonb;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  if p_order_id is null and nullif(trim(coalesce(p_menu_id,'')),'') is null then
    return jsonb_build_object('ok',false,'error','invalid_delta_target');
  end if;

  if p_order_id is not null then
    select to_jsonb(o) into v_order
    from public.orders o
    where o.tenant_id=p_tenant_id
      and o.id=p_order_id
      and (
        (o.payment_status='submitted' and o.order_status='payment_review')
        or (o.payment_status='verified' and o.order_status in ('confirmed','preparing','ready'))
      )
    limit 1;

    return jsonb_build_object(
      'ok',true,
      'tenant_id',p_tenant_id,
      'kind','orders',
      'entity_id',p_order_id::text,
      'order',v_order,
      'version',coalesce(v_order->>'updated_at',null)
    );
  end if;

  select to_jsonb(m) into v_menu
  from public.menu_items m
  where m.tenant_id=p_tenant_id and m.id=p_menu_id
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'tenant_id',p_tenant_id,
    'kind','menu',
    'entity_id',p_menu_id,
    'menu',v_menu,
    'version',coalesce(v_menu->>'updated_at',null)
  );
end
$$;

revoke all on function public.kds_delta_tenant(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.kds_delta_tenant(uuid,text,uuid,text) to service_role;

create or replace function public.kds_ack_visible_tenant(
  p_tenant_id uuid,
  p_token text,
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_row public.orders%rowtype;
  v_changed boolean:=false;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;

  select * into v_row
  from public.orders
  where tenant_id=p_tenant_id and id=p_order_id
  for update;

  if v_row.id is null then
    return jsonb_build_object('ok',false,'error','order_not_found');
  end if;

  if v_row.kds_received_at is null and (
    (v_row.payment_status='submitted' and v_row.order_status='payment_review')
    or (v_row.payment_status='verified' and v_row.order_status in ('confirmed','preparing','ready'))
  ) then
    update public.orders
       set kds_received_at=now(),updated_at=now()
     where tenant_id=p_tenant_id and id=p_order_id
     returning * into v_row;
    v_changed:=true;
  end if;

  return jsonb_build_object(
    'ok',true,
    'tenant_id',p_tenant_id,
    'order_id',p_order_id,
    'changed',v_changed,
    'kds_received_at',v_row.kds_received_at,
    'request_id',v_row.request_id
  );
end
$$;

revoke all on function public.kds_ack_visible_tenant(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.kds_ack_visible_tenant(uuid,text,uuid) to service_role;

commit;
