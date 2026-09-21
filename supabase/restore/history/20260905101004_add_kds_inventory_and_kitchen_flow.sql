-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260905101004  Name: add_kds_inventory_and_kitchen_flow
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.menu_items
  add column if not exists is_available boolean not null default true,
  add column if not exists availability_updated_at timestamptz not null default now(),
  add column if not exists availability_note text not null default '';

do $$ begin
  alter table public.menu_items add constraint menu_items_availability_note_len check (char_length(availability_note) <= 160);
exception when duplicate_object then null; end $$;

alter table public.orders
  add column if not exists kds_received_at timestamptz,
  add column if not exists preparing_at timestamptz,
  add column if not exists ready_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists kitchen_print_count integer not null default 0,
  add column if not exists kitchen_last_printed_at timestamptz;

do $$ begin
  alter table public.orders add constraint orders_kitchen_print_count_nonnegative check (kitchen_print_count >= 0);
exception when duplicate_object then null; end $$;

create or replace function public.kds_snapshot(p_token text)
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
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  select jsonb_build_object(
    'business_name',s.business_name,
    'merchant_name',s.merchant_name,
    'public_url',s.public_url,
    'admin_url',s.admin_url,
    'kds_url',s.kds_url
  ) into v_settings
  from public.site_settings s where s.id=1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',m.id,
    'name',m.name,
    'category',m.category,
    'price',m.price,
    'image_url',m.image_url,
    'is_visible',m.is_visible,
    'is_available',m.is_available,
    'availability_note',m.availability_note,
    'availability_updated_at',m.availability_updated_at,
    'display_order',m.display_order
  ) order by m.display_order,m.name),'[]'::jsonb)
  into v_menu
  from public.menu_items m;

  select coalesce(jsonb_agg(to_jsonb(o) order by o.created_at desc),'[]'::jsonb)
  into v_orders
  from (
    select * from public.orders
    where payment_status='verified'
      and (
        order_status in ('confirmed','preparing','ready')
        or ((created_at at time zone 'Asia/Jakarta')::date = v_today and order_status='completed')
      )
    order by created_at desc
    limit 150
  ) o;

  return jsonb_build_object('ok',true,'settings',coalesce(v_settings,'{}'::jsonb),'menu',v_menu,'orders',v_orders,'actor',v_email::text);
end;
$$;

create or replace function public.kds_set_availability(p_token text,p_id text,p_available boolean,p_note text default '')
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_row public.menu_items%rowtype;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  update public.menu_items
  set is_available=coalesce(p_available,false),
      availability_note=left(trim(coalesce(p_note,'')),160),
      availability_updated_at=now(),
      updated_at=now(),
      updated_by=null
  where id=p_id
  returning * into v_row;

  if v_row.id is null then return jsonb_build_object('ok',false,'error','menu_not_found'); end if;
  return jsonb_build_object('ok',true,'menu',to_jsonb(v_row));
end;
$$;

create or replace function public.kds_update_order(p_token text,p_id uuid,p_action text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_old public.orders%rowtype;
  v_row public.orders%rowtype;
  v_now timestamptz := now();
  v_to text;
  v_event text;
  v_note text;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  select * into v_old from public.orders where id=p_id for update;
  if v_old.id is null then return jsonb_build_object('ok',false,'error','order_not_found'); end if;
  if v_old.payment_status <> 'verified' then return jsonb_build_object('ok',false,'error','payment_not_verified'); end if;

  if p_action='start' then
    if v_old.order_status not in ('confirmed','preparing') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set
      order_status='preparing',
      kds_received_at=coalesce(kds_received_at,v_now),
      preparing_at=coalesce(preparing_at,v_now),
      updated_at=v_now
    where id=p_id returning * into v_row;
    v_to:='preparing'; v_event:='kds_preparing'; v_note:='Pesanan diterima dapur dan mulai diproses.';
  elsif p_action='ready' then
    if v_old.order_status not in ('confirmed','preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set
      order_status='ready',
      kds_received_at=coalesce(kds_received_at,v_now),
      preparing_at=coalesce(preparing_at,v_now),
      ready_at=coalesce(ready_at,v_now),
      updated_at=v_now
    where id=p_id returning * into v_row;
    v_to:='ready'; v_event:='kds_ready'; v_note:='Pesanan siap disajikan atau diserahkan.';
  elsif p_action='complete' then
    if v_old.order_status not in ('ready','completed') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set
      order_status='completed',
      completed_at=coalesce(completed_at,v_now),
      updated_at=v_now
    where id=p_id returning * into v_row;
    v_to:='completed'; v_event:='kds_completed'; v_note:='Pesanan selesai.';
  elsif p_action='reopen' then
    if v_old.order_status <> 'completed' then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='ready',completed_at=null,updated_at=v_now where id=p_id returning * into v_row;
    v_to:='ready'; v_event:='kds_reopened'; v_note:='Pesanan dibuka kembali ke status siap disajikan.';
  elsif p_action='print' then
    update public.orders set
      kitchen_print_count=kitchen_print_count+1,
      kitchen_last_printed_at=v_now,
      kds_received_at=coalesce(kds_received_at,v_now),
      updated_at=v_now
    where id=p_id returning * into v_row;
    v_to:=v_old.order_status; v_event:='kitchen_ticket_printed'; v_note:='Kitchen ticket dicetak.';
  else
    return jsonb_build_object('ok',false,'error','invalid_action');
  end if;

  insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id)
  values(p_id,v_event,v_old.order_status,v_to,v_note,null);

  return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
end;
$$;

grant execute on function public.kds_snapshot(text) to anon, authenticated;
grant execute on function public.kds_set_availability(text,text,boolean,text) to anon, authenticated;
grant execute on function public.kds_update_order(text,uuid,text) to anon, authenticated;
