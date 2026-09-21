-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911014830  Name: stabilize_rohmat_integrations_and_history
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.site_settings
  add column if not exists require_table_qr_signature boolean not null default false;

create index if not exists orders_created_at_idx
  on public.orders (created_at desc);

create or replace function public.admin_order_history_snapshot(
  p_token text,
  p_limit integer default 500,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_email extensions.citext;
  v_limit integer := greatest(1, least(coalesce(p_limit,500), 500));
  v_offset integer := greatest(0, coalesce(p_offset,0));
  v_rows jsonb;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;

  with page as (
    select id, created_at, customer_name, customer_whatsapp, items, total_amount
    from (
      select o.id, o.created_at, o.customer_name, o.customer_whatsapp, o.items, o.total_amount
      from public.orders o
      union all
      select a.id, a.created_at, a.customer_name, a.customer_whatsapp, a.items, a.total_amount
      from public.order_history_archive a
    ) q
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
$function$;
