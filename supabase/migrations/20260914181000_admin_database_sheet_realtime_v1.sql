create or replace function public.admin_order_history_snapshot(p_token text,p_limit integer default 500,p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_email extensions.citext;
  v_limit integer := greatest(1,least(coalesce(p_limit,500),1000));
  v_offset integer := greatest(0,coalesce(p_offset,0));
  v_rows jsonb;
  v_total bigint;
  v_health jsonb;
begin
  v_email:=private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  with all_orders as (
    select o.id,o.public_order_code,o.created_at,o.updated_at,o.customer_name,o.customer_whatsapp,o.service_mode,o.table_number,o.items,o.item_count,o.total_amount,o.payment_method,o.payment_status,o.order_status,o.payment_submitted_at,o.verified_at,o.kitchen_sent_at,o.kds_received_at,o.preparing_at,o.ready_at,o.completed_at,o.customer_note,o.order_source,o.cashier_actor,o.cash_received,o.change_amount,'live'::text as storage_state
      from public.orders o
    union all
    select a.id,a.public_order_code,a.created_at,a.updated_at,a.customer_name,a.customer_whatsapp,a.service_mode,a.table_number,a.items,a.item_count,a.total_amount,a.payment_method,a.payment_status,a.order_status,a.payment_submitted_at,a.verified_at,a.kitchen_sent_at,a.kds_received_at,a.preparing_at,a.ready_at,a.completed_at,a.customer_note,a.order_source,a.cashier_actor,a.cash_received,a.change_amount,'archive'::text as storage_state
      from public.order_history_archive a
  ), page as (
    select * from all_orders order by created_at desc limit v_limit offset v_offset
  )
  select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc),'[]'::jsonb) into v_rows from page p;

  select count(*) into v_total from (
    select id from public.orders union all select id from public.order_history_archive
  ) q;

  begin
    v_health:=public.get_sheet_sync_health();
  exception when others then
    v_health:=jsonb_build_object('enabled',false,'error','sheet_health_unavailable');
  end;

  return jsonb_build_object(
    'ok',true,
    'rows',v_rows,
    'total',v_total,
    'limit',v_limit,
    'offset',v_offset,
    'generated_at',now(),
    'sheet_sync',v_health
  );
end;
$function$;

do $$
begin
  if exists(select 1 from cron.job where jobname='rohmat_sheet_sync_worker') then
    perform cron.unschedule('rohmat_sheet_sync_worker');
  end if;
  if exists(select 1 from cron.job where jobname='rohmat-sheet-sync-drain-10s') then
    perform cron.unschedule('rohmat-sheet-sync-drain-10s');
  end if;
  perform cron.schedule('rohmat-sheet-sync-drain-10s','10 seconds','select private.invoke_sheet_sync_worker();');
end $$;
