-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260905105155  Name: kds_separate_login_console
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.kds_console_snapshot(p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_email extensions.citext;
  v_orders jsonb;
  v_menu jsonb;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  select coalesce(jsonb_agg(to_jsonb(o) order by o.created_at asc),'[]'::jsonb)
    into v_orders
  from (
    select * from public.orders
    where payment_status='verified'
      and order_status in ('confirmed','preparing','ready','completed')
      and (order_status <> 'completed' or completed_at >= now() - interval '24 hours')
    order by created_at asc
    limit 200
  ) o;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',m.id,'name',m.name,'category',m.category,'price',m.price,
    'is_visible',m.is_visible,'is_available',m.is_available,'display_order',m.display_order
  ) order by m.display_order asc,m.name asc),'[]'::jsonb)
    into v_menu
  from public.menu_items m
  where m.is_visible=true;

  return jsonb_build_object('ok',true,'email',v_email::text,'orders',v_orders,'menu',v_menu,'server_time',now());
end;
$function$;

create or replace function public.kds_console_set_available(p_token text,p_id text,p_available boolean)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_email extensions.citext;
  v_row public.menu_items%rowtype;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  update public.menu_items
    set is_available=coalesce(p_available,false),updated_at=now(),updated_by=null
    where id=p_id
    returning * into v_row;
  if v_row.id is null then return jsonb_build_object('ok',false,'error','menu_not_found'); end if;
  return jsonb_build_object('ok',true,'menu',to_jsonb(v_row));
end;
$function$;

create or replace function public.kds_console_order_action(p_token text,p_id uuid,p_action text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_email extensions.citext;
  v_old public.orders%rowtype;
  v_row public.orders%rowtype;
  v_now timestamptz := now();
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select * into v_old from public.orders where id=p_id;
  if v_old.id is null then return jsonb_build_object('ok',false,'error','order_not_found'); end if;
  if v_old.payment_status <> 'verified' then return jsonb_build_object('ok',false,'error','payment_not_verified'); end if;

  if p_action='start' then
    if v_old.order_status not in ('confirmed','preparing') then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set order_status='preparing',preparing_at=coalesce(preparing_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id)
    values(p_id,'kitchen_started',v_old.order_status,'preparing','Pesanan mulai diproses di dapur.',null);
  elsif p_action='ready' then
    if v_old.order_status not in ('preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set order_status='ready',ready_at=coalesce(ready_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id)
    values(p_id,'kitchen_ready',v_old.order_status,'ready','Pesanan siap disajikan.',null);
  elsif p_action='complete' then
    if v_old.order_status not in ('ready','completed') then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set order_status='completed',completed_at=coalesce(completed_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id)
    values(p_id,'kitchen_completed',v_old.order_status,'completed','Pesanan selesai disajikan.',null);
  elsif p_action='print' then
    update public.orders set kitchen_print_count=coalesce(kitchen_print_count,0)+1,kitchen_last_printed_at=v_now,updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id)
    values(p_id,'kitchen_printed',v_old.order_status,v_old.order_status,'Kitchen ticket dicetak.',null);
  else
    return jsonb_build_object('ok',false,'error','invalid_action');
  end if;

  return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
end;
$function$;

grant execute on function public.kds_console_snapshot(text) to anon,authenticated,service_role;
grant execute on function public.kds_console_set_available(text,text,boolean) to anon,authenticated,service_role;
grant execute on function public.kds_console_order_action(text,uuid,text) to anon,authenticated,service_role;
