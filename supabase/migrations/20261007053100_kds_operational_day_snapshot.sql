-- SMART ORDER: KDS operational-day snapshot fix
-- Prevent historical unresolved orders from previous business dates appearing as duplicate live tickets.

create or replace function public.kds_snapshot_tenant(p_tenant_id uuid,p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_settings jsonb;
  v_menu jsonb;
  v_orders jsonb;
  v_today date;
  v_tz text;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select timezone into v_tz from private.tenant_runtime_config where tenant_id=p_tenant_id and enabled;
  if v_tz is null then return jsonb_build_object('ok',false,'error','tenant_unavailable'); end if;
  v_today:=(now() at time zone v_tz)::date;
  v_settings:=coalesce(private.tenant_settings_json(p_tenant_id),'{}'::jsonb);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',m.id,'name',m.name,'category',m.category,'price',m.price,
    'description',m.description,'image_url',m.image_url,'is_favorite',m.is_favorite,
    'is_visible',m.is_visible,'is_available',m.is_available,
    'availability_note',m.availability_note,'availability_updated_at',m.availability_updated_at,
    'display_order',m.display_order,'updated_at',m.updated_at
  ) order by m.display_order,m.name),'[]'::jsonb)
  into v_menu
  from public.menu_items m
  where m.tenant_id=p_tenant_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',o.id,'public_order_code',o.public_order_code,'service_mode',o.service_mode,
      'table_number',o.table_number,'customer_name',o.customer_name,'items',o.items,
      'total_amount',o.total_amount,'payment_method',o.payment_method,
      'payment_status',o.payment_status,'order_status',o.order_status,
      'payment_proof_url',o.payment_proof_url,'customer_note',o.customer_note,
      'payment_submitted_at',o.payment_submitted_at,'verified_at',o.verified_at,
      'kitchen_sent_at',o.kitchen_sent_at,'created_at',o.created_at,'updated_at',o.updated_at,
      'preparing_at',o.preparing_at,'ready_at',o.ready_at,'completed_at',o.completed_at,
      'kitchen_print_count',coalesce(o.kitchen_print_count,0),'kds_dismissed_at',o.kds_dismissed_at,
      'tenant_id',o.tenant_id
    ) order by o.created_at desc
  ),'[]'::jsonb)
  into v_orders
  from public.orders o
  where o.tenant_id=p_tenant_id
    and (o.created_at at time zone v_tz)::date=v_today
    and (
      (o.payment_status='submitted' and o.order_status='payment_review')
      or (o.payment_status='verified' and o.order_status in ('confirmed','preparing','ready'))
      or (
        o.payment_status='verified' and o.order_status='completed'
        and coalesce(o.kitchen_print_count,0)=0 and o.kds_dismissed_at is null
      )
    );

  return jsonb_build_object(
    'ok',true,'tenant_id',p_tenant_id,'settings',v_settings,
    'menu',v_menu,'orders',v_orders,'actor',v_email::text
  );
end
$$;

revoke all on function public.kds_snapshot_tenant(uuid,text) from public,anon,authenticated;
grant execute on function public.kds_snapshot_tenant(uuid,text) to service_role;
