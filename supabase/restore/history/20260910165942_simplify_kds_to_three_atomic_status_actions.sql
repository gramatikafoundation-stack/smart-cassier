-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260910165942  Name: simplify_kds_to_three_atomic_status_actions
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.kds_update_order(p_token text, p_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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

  if p_action='verify_start' then
    if v_old.payment_status <> 'submitted' or v_old.order_status <> 'payment_review' then
      return jsonb_build_object('ok',false,'error','invalid_payment_state');
    end if;
    update public.orders
       set payment_status='verified',
           order_status='preparing',
           verified_at=coalesce(verified_at,v_now),
           kitchen_sent_at=coalesce(kitchen_sent_at,v_now),
           kds_received_at=coalesce(kds_received_at,v_now),
           preparing_at=coalesce(preparing_at,v_now),
           updated_at=v_now
     where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id)
    values(p_id,'payment_verified_and_kds_started',v_old.order_status,'preparing','Pembayaran diverifikasi dan pesanan langsung masuk tahap Sedang Diproses.',null);
    return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
  elsif p_action='verify_payment' then
    if v_old.payment_status <> 'submitted' or v_old.order_status <> 'payment_review' then
      return jsonb_build_object('ok',false,'error','invalid_payment_state');
    end if;
    update public.orders set payment_status='verified',order_status='confirmed',verified_at=v_now,kitchen_sent_at=v_now,updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id)
    values(p_id,'payment_verified_kds',v_old.order_status,'confirmed','Pembayaran diverifikasi oleh petugas KDS.',null);
    return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
  elsif p_action='reject_payment' then
    if v_old.payment_status <> 'submitted' or v_old.order_status <> 'payment_review' then
      return jsonb_build_object('ok',false,'error','invalid_payment_state');
    end if;
    update public.orders set payment_status='rejected',order_status='payment_rejected',updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id)
    values(p_id,'payment_rejected_kds',v_old.order_status,'payment_rejected','Pembayaran ditolak oleh petugas KDS.',null);
    return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
  end if;

  if v_old.payment_status <> 'verified' then return jsonb_build_object('ok',false,'error','payment_not_verified'); end if;

  if p_action='start' then
    if v_old.order_status not in ('confirmed','preparing') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='preparing',kds_received_at=coalesce(kds_received_at,v_now),preparing_at=coalesce(preparing_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    v_to:='preparing'; v_event:='kds_preparing'; v_note:='Pesanan diterima dapur dan mulai diproses.';
  elsif p_action='finish' then
    if v_old.order_status not in ('preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='completed',kds_received_at=coalesce(kds_received_at,v_now),preparing_at=coalesce(preparing_at,v_now),completed_at=coalesce(completed_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    v_to:='completed'; v_event:='kds_completed'; v_note:='Pesanan selesai dari alur KDS tiga tahap.';
  elsif p_action='ready' then
    if v_old.order_status not in ('confirmed','preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='ready',kds_received_at=coalesce(kds_received_at,v_now),preparing_at=coalesce(preparing_at,v_now),ready_at=coalesce(ready_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    v_to:='ready'; v_event:='kds_ready'; v_note:='Pesanan siap disajikan atau diserahkan.';
  elsif p_action='complete' then
    if v_old.order_status not in ('ready','completed') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='completed',completed_at=coalesce(completed_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    v_to:='completed'; v_event:='kds_completed'; v_note:='Pesanan selesai.';
  elsif p_action='reopen' then
    if v_old.order_status <> 'completed' then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='ready',completed_at=null,updated_at=v_now where id=p_id returning * into v_row;
    v_to:='ready'; v_event:='kds_reopened'; v_note:='Pesanan dibuka kembali ke status siap disajikan.';
  elsif p_action='print' then
    update public.orders set kitchen_print_count=kitchen_print_count+1,kitchen_last_printed_at=v_now,kds_received_at=coalesce(kds_received_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    v_to:=v_old.order_status; v_event:='kitchen_ticket_printed'; v_note:='Kitchen ticket dicetak.';
  else
    return jsonb_build_object('ok',false,'error','invalid_action');
  end if;

  insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id)
  values(p_id,v_event,v_old.order_status,v_to,v_note,null);

  return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
end;
$function$;
