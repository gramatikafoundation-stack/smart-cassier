-- ROHMAT MASTER PROTOTIPE v1
-- Phase 6: exact tenant-scoped KDS compatibility RPCs matching the current KDS client contract.

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
    and (
      (o.payment_status='submitted' and o.order_status='payment_review')
      or (o.payment_status='verified' and o.order_status in ('confirmed','preparing','ready'))
      or (
        o.payment_status='verified' and o.order_status='completed'
        and (o.created_at at time zone v_tz)::date=v_today
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

create or replace function public.kds_set_availability_tenant(
  p_tenant_id uuid,p_token text,p_id text,p_available boolean,p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_row public.menu_items%rowtype;
  v_note text;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_available is null then return jsonb_build_object('ok',false,'error','invalid_availability'); end if;

  select * into v_row from public.menu_items
   where tenant_id=p_tenant_id and id=p_id for update;
  if v_row.id is null then return jsonb_build_object('ok',false,'error','menu_not_found'); end if;

  v_note:=case when p_available then '' else left(coalesce(nullif(trim(p_note),''),'Habis'),160) end;
  if v_row.is_available is not distinct from p_available
     and coalesce(v_row.availability_note,'')=v_note then
    return jsonb_build_object(
      'ok',true,'tenant_id',p_tenant_id,'menu',to_jsonb(v_row),
      'toggle_applied',false,'effective_available',v_row.is_available
    );
  end if;

  update public.menu_items
     set is_available=p_available,availability_note=v_note,
         availability_updated_at=now(),updated_at=now(),updated_by=null
   where tenant_id=p_tenant_id and id=p_id
  returning * into v_row;

  return jsonb_build_object(
    'ok',true,'tenant_id',p_tenant_id,'menu',to_jsonb(v_row),
    'toggle_applied',true,'effective_available',v_row.is_available
  );
end
$$;
revoke all on function public.kds_set_availability_tenant(uuid,text,text,boolean,text) from public,anon,authenticated;
grant execute on function public.kds_set_availability_tenant(uuid,text,text,boolean,text) to service_role;

create or replace function public.kds_update_order_tenant(
  p_tenant_id uuid,p_token text,p_id uuid,p_action text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext; v_actor_id uuid; v_role text;
  v_old public.orders%rowtype; v_row public.orders%rowtype;
  v_now timestamptz:=now(); v_to text; v_event text; v_note text;
begin
  select a.email,a.actor_id,a.role into v_email,v_actor_id,v_role
    from private.tenant_actor_context(p_tenant_id,p_token) a;
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  select * into v_old from public.orders
   where id=p_id and tenant_id=p_tenant_id for update;
  if v_old.id is null then return jsonb_build_object('ok',false,'error','order_not_found'); end if;

  if p_action='verify_start' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then
      return jsonb_build_object('ok',false,'error','invalid_payment_state'); end if;
    update public.orders
       set payment_status='verified',order_status='preparing',
           verified_at=coalesce(verified_at,v_now),verified_by=v_actor_id,verified_by_email=v_email,
           kitchen_sent_at=coalesce(kitchen_sent_at,v_now),kds_received_at=coalesce(kds_received_at,v_now),
           preparing_at=coalesce(preparing_at,v_now),updated_at=v_now
     where id=p_id and tenant_id=p_tenant_id
    returning * into v_row;
    v_to:='preparing'; v_event:='payment_verified_and_kds_started';
    v_note:='Pembayaran diverifikasi dan pesanan langsung masuk tahap Sedang Diproses.';
  elsif p_action='verify_payment' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then
      return jsonb_build_object('ok',false,'error','invalid_payment_state'); end if;
    update public.orders
       set payment_status='verified',order_status='confirmed',
           verified_at=coalesce(verified_at,v_now),verified_by=v_actor_id,verified_by_email=v_email,
           kitchen_sent_at=coalesce(kitchen_sent_at,v_now),updated_at=v_now
     where id=p_id and tenant_id=p_tenant_id
    returning * into v_row;
    v_to:='confirmed'; v_event:='payment_verified_kds'; v_note:='Pembayaran diverifikasi oleh petugas KDS.';
  elsif p_action='reject_payment' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then
      return jsonb_build_object('ok',false,'error','invalid_payment_state'); end if;
    update public.orders
       set payment_status='rejected',order_status='awaiting_payment',
           verified_at=null,verified_by=null,verified_by_email=null,kitchen_sent_at=null,updated_at=v_now
     where id=p_id and tenant_id=p_tenant_id
    returning * into v_row;
    v_to:='awaiting_payment'; v_event:='payment_rejected_kds';
    v_note:='Bukti pembayaran ditolak oleh petugas KDS untuk diperiksa atau diulang.';
  else
    if v_old.payment_status<>'verified' then return jsonb_build_object('ok',false,'error','payment_not_verified'); end if;
    if p_action='start' then
      if v_old.order_status not in ('confirmed','preparing') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
      update public.orders set order_status='preparing',kds_received_at=coalesce(kds_received_at,v_now),
        preparing_at=coalesce(preparing_at,v_now),updated_at=v_now
       where id=p_id and tenant_id=p_tenant_id returning * into v_row;
      v_to:='preparing';v_event:='kds_preparing';v_note:='Pesanan diterima dapur dan mulai diproses.';
    elsif p_action='finish' then
      if v_old.order_status not in ('preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
      update public.orders set order_status='completed',kds_received_at=coalesce(kds_received_at,v_now),
        preparing_at=coalesce(preparing_at,v_now),completed_at=coalesce(completed_at,v_now),updated_at=v_now
       where id=p_id and tenant_id=p_tenant_id returning * into v_row;
      v_to:='completed';v_event:='kds_completed';v_note:='Pesanan selesai dari alur KDS tiga tahap.';
    elsif p_action='ready' then
      if v_old.order_status not in ('confirmed','preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
      update public.orders set order_status='ready',kds_received_at=coalesce(kds_received_at,v_now),
        preparing_at=coalesce(preparing_at,v_now),ready_at=coalesce(ready_at,v_now),updated_at=v_now
       where id=p_id and tenant_id=p_tenant_id returning * into v_row;
      v_to:='ready';v_event:='kds_ready';v_note:='Pesanan siap disajikan atau diserahkan.';
    elsif p_action='complete' then
      if v_old.order_status not in ('ready','completed') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
      update public.orders set order_status='completed',completed_at=coalesce(completed_at,v_now),updated_at=v_now
       where id=p_id and tenant_id=p_tenant_id returning * into v_row;
      v_to:='completed';v_event:='kds_completed';v_note:='Pesanan selesai.';
    elsif p_action='reopen' then
      if v_old.order_status<>'completed' then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
      update public.orders set order_status='ready',completed_at=null,kds_dismissed_at=null,updated_at=v_now
       where id=p_id and tenant_id=p_tenant_id returning * into v_row;
      v_to:='ready';v_event:='kds_reopened';v_note:='Pesanan dibuka kembali ke status siap disajikan.';
    elsif p_action='print' then
      update public.orders set kitchen_print_count=coalesce(kitchen_print_count,0)+1,
        kitchen_last_printed_at=v_now,kds_received_at=coalesce(kds_received_at,v_now),
        kds_dismissed_at=case when order_status='completed' then coalesce(kds_dismissed_at,v_now) else kds_dismissed_at end,
        updated_at=v_now
       where id=p_id and tenant_id=p_tenant_id returning * into v_row;
      v_to:=v_old.order_status;v_event:='kitchen_ticket_printed';v_note:='Kitchen ticket dicetak.';
    elsif p_action='dismiss' then
      if v_old.order_status<>'completed' then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
      update public.orders set kds_dismissed_at=coalesce(kds_dismissed_at,v_now),updated_at=v_now
       where id=p_id and tenant_id=p_tenant_id returning * into v_row;
      v_to:='completed';v_event:='kds_completed_dismissed';
      v_note:='Pesanan selesai dihilangkan dari tampilan KDS tanpa menghapus riwayat transaksi.';
    else
      return jsonb_build_object('ok',false,'error','invalid_action');
    end if;
  end if;

  insert into public.order_events(
    order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id,tenant_id
  ) values(
    p_id,v_event,v_old.order_status,v_to,v_note,v_actor_id,v_email,v_role,'kds',v_old.request_id,p_tenant_id
  );

  return jsonb_build_object(
    'ok',true,'tenant_id',p_tenant_id,'request_id',v_old.request_id,'order',to_jsonb(v_row)
  );
end
$$;
revoke all on function public.kds_update_order_tenant(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.kds_update_order_tenant(uuid,text,uuid,text) to service_role;
