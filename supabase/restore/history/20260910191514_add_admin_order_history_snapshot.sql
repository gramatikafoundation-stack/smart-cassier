-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260910191514  Name: add_admin_order_history_snapshot
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.admin_order_history_snapshot(p_token text, p_limit integer default 500, p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email extensions.citext;
  v_limit integer := greatest(1, least(coalesce(p_limit,500), 1000));
  v_offset integer := greatest(0, coalesce(p_offset,0));
  v_rows jsonb;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;

  with combined as (
    select o.id, o.created_at, o.customer_name, o.customer_whatsapp, o.items, o.total_amount, 2 as priority
    from public.orders o
    union all
    select a.id, a.created_at, a.customer_name, a.customer_whatsapp, a.items, a.total_amount, 1 as priority
    from public.order_history_archive a
  ), dedup as (
    select distinct on (id)
      id, created_at, customer_name, customer_whatsapp, items, total_amount
    from combined
    order by id, priority desc
  ), page as (
    select * from dedup
    order by created_at desc
    limit v_limit offset v_offset
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'created_at', p.created_at,
    'customer_name', p.customer_name,
    'customer_whatsapp', p.customer_whatsapp,
    'items', p.items,
    'total_amount', p.total_amount
  ) order by p.created_at desc),'[]'::jsonb)
  into v_rows
  from page p;

  return jsonb_build_object(
    'ok',true,
    'rows',v_rows,
    'limit',v_limit,
    'offset',v_offset,
    'generated_at',now()
  );
end;
$$;

revoke all on function public.admin_order_history_snapshot(text,integer,integer) from public, anon, authenticated;
grant execute on function public.admin_order_history_snapshot(text,integer,integer) to service_role;
