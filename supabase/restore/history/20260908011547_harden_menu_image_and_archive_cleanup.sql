-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260908011547  Name: harden_menu_image_and_archive_cleanup
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.menu_items alter column image_url set default '';
update public.menu_items set image_url='' where image_url is null;

create or replace function public.archive_orders_older_than_7d()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare v_count integer:=0;
begin
  insert into public.order_history_archive(id,public_order_code,created_at,customer_name,service_mode,table_number,items,item_count,total_amount,customer_note,paid_amount,payment_difference,producer_note,archived_at)
  select o.id,o.public_order_code,o.created_at,o.customer_name,o.service_mode,o.table_number,o.items,o.item_count,o.total_amount,o.customer_note,o.paid_amount,o.payment_difference,o.producer_note,now()
  from public.orders o
  where o.created_at < now()-interval '7 days'
  on conflict (id) do nothing;
  get diagnostics v_count = row_count;
  delete from public.order_events e using public.orders o where e.order_id=o.id and o.created_at < now()-interval '7 days';
  delete from public.orders where created_at < now()-interval '7 days';
  return v_count;
end;
$$;
revoke all on function public.archive_orders_older_than_7d() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from cron.job where jobname='archive_orders_older_than_7d') then
    perform cron.unschedule('archive_orders_older_than_7d');
  end if;
  perform cron.schedule('archive_orders_older_than_7d','17 * * * *','select public.archive_orders_older_than_7d();');
end $$;
