create or replace function public.smart_cashier_create(p_token text, p_source text, p_customer_name text, p_service_mode text, p_table_number smallint, p_items jsonb, p_payment_method text, p_cash_received integer default null::integer, p_note text default ''::text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_email extensions.citext; v_actor_id uuid; v_role text; v_req jsonb; v_menu public.menu_items%rowtype;
  v_qty integer; v_total integer:=0; v_count integer:=0; v_items jsonb:='[]'::jsonb; v_order public.orders%rowtype;
  v_name text; v_change integer:=0; v_now timestamptz:=now(); v_request_id uuid:=gen_random_uuid();
begin
  select a.email,a.actor_id,a.role into v_email,v_actor_id,v_role from private.admin_actor_context(p_token) a;
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_source not in ('cashier_admin','cashier_kds') then return jsonb_build_object('ok',false,'error','invalid_source'); end if;
  if p_service_mode not in ('dine-in','take-away') then return jsonb_build_object('ok',false,'error','invalid_service_mode'); end if;
  if p_service_mode='dine-in' and (p_table_number is null or p_table_number<1 or p_table_number>20) then return jsonb_build_object('ok',false,'error','invalid_table'); end if;
  if p_service_mode='take-away' then p_table_number:=null; end if;
  if p_payment_method not in ('cash','qris_cashier') then return jsonb_build_object('ok',false,'error','invalid_payment_method'); end if;

  v_name:=left(trim(coalesce(p_customer_name,'')),60);
  if v_name='' then return jsonb_build_object('ok',false,'error','customer_name_required'); end if;

  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then return jsonb_build_object('ok',false,'error','empty_cart'); end if;
  for v_req in select value from jsonb_array_elements(p_items) loop
    v_qty:=greatest(0,least(50,coalesce((v_req->>'quantity')::integer,0)));
    if v_qty<1 then return jsonb_build_object('ok',false,'error','invalid_quantity'); end if;
    select * into v_menu from public.menu_items where id=(v_req->>'menuId') and is_visible and is_available;
    if v_menu.id is null then return jsonb_build_object('ok',false,'error','menu_unavailable','menuId',v_req->>'menuId'); end if;
    v_total:=v_total+(v_menu.price*v_qty); v_count:=v_count+v_qty;
    if v_count>200 or v_total>100000000 then return jsonb_build_object('ok',false,'error','order_limit_exceeded'); end if;
    v_items:=v_items||jsonb_build_array(jsonb_build_object('menuId',v_menu.id,'name',v_menu.name,'price',v_menu.price,'quantity',v_qty,'subtotal',v_menu.price*v_qty));
  end loop;
  if p_payment_method='cash' then
    if p_cash_received is null or p_cash_received<v_total then return jsonb_build_object('ok',false,'error','insufficient_cash','total',v_total); end if;
    v_change:=p_cash_received-v_total;
  else p_cash_received:=null; v_change:=0; end if;

  insert into public.orders(request_id,service_mode,table_number,customer_name,items,item_count,total_amount,payment_method,payment_status,order_status,payment_submitted_at,verified_at,verified_by,verified_by_email,kitchen_sent_at,customer_note,client_order_id,paid_amount,payment_difference,producer_note,proof_check_status,order_source,cashier_actor,cash_received,change_amount,created_at,updated_at)
  values(v_request_id,p_service_mode,p_table_number,v_name,v_items,v_count,v_total,p_payment_method,'verified','confirmed',v_now,v_now,v_actor_id,v_email,v_now,left(trim(coalesce(p_note,'')),500),'cashier-'||replace(gen_random_uuid()::text,'-',''),v_total,0,case when p_payment_method='cash' then 'Pembayaran CASH dikonfirmasi oleh kasir.' else 'Pembayaran QRIS kasir dikonfirmasi oleh petugas.' end,'cashier_confirmed',p_source,v_email::text,p_cash_received,v_change,v_now,v_now)
  returning * into v_order;

  return jsonb_build_object(
    'ok',true,
    'request_id',v_request_id,
    'order',to_jsonb(v_order),
    'change_amount',v_change,
    'receipt',jsonb_build_object(
      'payment_code',v_order.public_order_code,
      'customer_name',v_order.customer_name,
      'service_mode',v_order.service_mode,
      'table_number',v_order.table_number,
      'created_at',v_order.created_at,
      'items',v_order.items,
      'total_amount',v_order.total_amount
    )
  );
exception when others then return jsonb_build_object('ok',false,'error','cashier_create_failed','detail',sqlerrm);
end
$function$;
