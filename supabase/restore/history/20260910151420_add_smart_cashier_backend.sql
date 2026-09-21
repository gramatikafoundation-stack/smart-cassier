-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260910151420  Name: add_smart_cashier_backend
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.smart_cashier_create(
  p_token text,
  p_source text,
  p_customer_name text,
  p_service_mode text,
  p_table_number smallint,
  p_items jsonb,
  p_payment_method text,
  p_cash_received integer default null,
  p_note text default ''
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_req jsonb;
  v_menu public.menu_items%rowtype;
  v_qty integer;
  v_total integer := 0;
  v_count integer := 0;
  v_items jsonb := '[]'::jsonb;
  v_order public.orders%rowtype;
  v_name text;
  v_change integer := 0;
  v_now timestamptz := now();
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  if p_source not in ('cashier_admin','cashier_kds') then
    return jsonb_build_object('ok',false,'error','invalid_source');
  end if;
  if p_service_mode not in ('dine-in','take-away') then
    return jsonb_build_object('ok',false,'error','invalid_service_mode');
  end if;
  if p_service_mode='dine-in' and (p_table_number is null or p_table_number < 1 or p_table_number > 20) then
    return jsonb_build_object('ok',false,'error','invalid_table');
  end if;
  if p_service_mode='take-away' then p_table_number := null; end if;
  if p_payment_method not in ('cash','qris_cashier') then
    return jsonb_build_object('ok',false,'error','invalid_payment_method');
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then
    return jsonb_build_object('ok',false,'error','empty_cart');
  end if;

  for v_req in select value from jsonb_array_elements(p_items)
  loop
    v_qty := greatest(0, least(50, coalesce((v_req->>'quantity')::integer,0)));
    if v_qty < 1 then return jsonb_build_object('ok',false,'error','invalid_quantity'); end if;
    select * into v_menu from public.menu_items
      where id=(v_req->>'menuId') and is_visible and is_available;
    if v_menu.id is null then
      return jsonb_build_object('ok',false,'error','menu_unavailable','menuId',v_req->>'menuId');
    end if;
    v_total := v_total + (v_menu.price * v_qty);
    v_count := v_count + v_qty;
    if v_count > 200 or v_total > 100000000 then
      return jsonb_build_object('ok',false,'error','order_limit_exceeded');
    end if;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'menuId',v_menu.id,
      'name',v_menu.name,
      'price',v_menu.price,
      'quantity',v_qty,
      'subtotal',v_menu.price*v_qty
    ));
  end loop;

  if p_payment_method='cash' then
    if p_cash_received is null or p_cash_received < v_total then
      return jsonb_build_object('ok',false,'error','insufficient_cash','total',v_total);
    end if;
    v_change := p_cash_received - v_total;
  else
    p_cash_received := null;
    v_change := 0;
  end if;

  v_name := left(coalesce(nullif(trim(p_customer_name),''),'Pelanggan Kasir'),60);
  if char_length(v_name)<2 then v_name := 'Pelanggan Kasir'; end if;

  insert into public.orders(
    service_mode,table_number,customer_name,items,item_count,total_amount,
    payment_method,payment_status,order_status,payment_submitted_at,verified_at,
    kitchen_sent_at,customer_note,client_order_id,paid_amount,payment_difference,
    producer_note,proof_check_status,order_source,cashier_actor,cash_received,change_amount,
    created_at,updated_at
  ) values (
    p_service_mode,p_table_number,v_name,v_items,v_count,v_total,
    p_payment_method,'verified','confirmed',v_now,v_now,
    v_now,left(trim(coalesce(p_note,'')),500),'cashier-'||replace(gen_random_uuid()::text,'-',''),v_total,0,
    case when p_payment_method='cash' then 'Pembayaran CASH dikonfirmasi oleh kasir.' else 'Pembayaran QRIS kasir dikonfirmasi oleh petugas.' end,
    'cashier_confirmed',p_source,v_email::text,p_cash_received,v_change,
    v_now,v_now
  ) returning * into v_order;

  insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id)
  values(v_order.id,'cashier_order_created',null,'confirmed',
    case when p_payment_method='cash' then 'Pesanan kasir dibuat dan dibayar tunai.' else 'Pesanan kasir dibuat dan dibayar QRIS.' end,
    null);

  return jsonb_build_object('ok',true,'order',to_jsonb(v_order),'change_amount',v_change);
exception when others then
  return jsonb_build_object('ok',false,'error','cashier_create_failed','detail',sqlerrm);
end;
$$;

create or replace function public.smart_cashier_snapshot(p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_settings jsonb;
  v_menu jsonb;
  v_recent jsonb;
  v_top jsonb;
  v_stats jsonb;
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  select jsonb_build_object(
    'business_name',s.business_name,
    'merchant_name',s.merchant_name,
    'qris_enabled',s.qris_enabled,
    'qris_image_url',s.qris_image_url
  ) into v_settings from public.site_settings s where s.id=1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',m.id,'name',m.name,'category',m.category,'price',m.price,
    'image_url',m.image_url,'is_available',m.is_available,'is_visible',m.is_visible,
    'display_order',m.display_order
  ) order by m.display_order,m.name),'[]'::jsonb)
  into v_menu from public.menu_items m where m.is_visible;

  select jsonb_build_object(
    'transaction_count',count(*),
    'items_sold',coalesce(sum(o.item_count),0),
    'revenue_total',coalesce(sum(o.total_amount),0),
    'cash_revenue',coalesce(sum(o.total_amount) filter(where o.payment_method='cash'),0),
    'qris_revenue',coalesce(sum(o.total_amount) filter(where o.payment_method in ('qris','qris_cashier')),0),
    'cashier_revenue',coalesce(sum(o.total_amount) filter(where o.order_source in ('cashier_admin','cashier_kds')),0),
    'public_revenue',coalesce(sum(o.total_amount) filter(where o.order_source='public'),0),
    'dine_in_count',count(*) filter(where o.service_mode='dine-in'),
    'take_away_count',count(*) filter(where o.service_mode='take-away')
  ) into v_stats
  from public.orders o
  where (o.created_at at time zone 'Asia/Jakarta')::date=v_today
    and o.payment_status='verified' and o.order_status<>'cancelled';

  select coalesce(jsonb_agg(to_jsonb(x) order by x.qty desc,x.revenue desc),'[]'::jsonb)
  into v_top
  from (
    select i->>'name' as name,
           sum(coalesce((i->>'quantity')::int,0))::int as qty,
           sum(coalesce((i->>'subtotal')::int,coalesce((i->>'price')::int,0)*coalesce((i->>'quantity')::int,0)))::int as revenue
    from public.orders o cross join lateral jsonb_array_elements(o.items) i
    where (o.created_at at time zone 'Asia/Jakarta')::date=v_today
      and o.payment_status='verified' and o.order_status<>'cancelled'
    group by i->>'name'
    order by qty desc,revenue desc
    limit 10
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
  into v_recent
  from (
    select id,public_order_code,service_mode,table_number,customer_name,items,item_count,total_amount,
           payment_method,payment_status,order_status,order_source,cashier_actor,cash_received,change_amount,created_at
    from public.orders
    where (created_at at time zone 'Asia/Jakarta')::date=v_today
    order by created_at desc limit 50
  ) x;

  return jsonb_build_object('ok',true,'actor',v_email::text,'settings',coalesce(v_settings,'{}'::jsonb),
    'menu',v_menu,'stats',coalesce(v_stats,'{}'::jsonb),'top_items',v_top,'recent_orders',v_recent,'generated_at',now());
end;
$$;

revoke all on function public.smart_cashier_create(text,text,text,text,smallint,jsonb,text,integer,text) from public,anon,authenticated;
revoke all on function public.smart_cashier_snapshot(text) from public,anon,authenticated;
grant execute on function public.smart_cashier_create(text,text,text,text,smallint,jsonb,text,integer,text) to service_role;
grant execute on function public.smart_cashier_snapshot(text) to service_role;
