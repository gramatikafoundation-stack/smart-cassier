-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260908160254  Name: add_payment_details_to_kds_print_data
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.kds_snapshot(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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
    'id',m.id,'name',m.name,'category',m.category,'price',m.price,
    'image_url',m.image_url,'is_visible',m.is_visible,'is_available',m.is_available,
    'availability_note',m.availability_note,'availability_updated_at',m.availability_updated_at,
    'display_order',m.display_order
  ) order by m.display_order,m.name),'[]'::jsonb)
  into v_menu
  from public.menu_items m;

  select coalesce(
    jsonb_agg(
      to_jsonb(o) || jsonb_build_object(
        'producer_note',
        concat_ws(' | ',
          nullif(trim(o.producer_note),''),
          'Tanggal pembayaran: ' || coalesce(
            case when coalesce(o.proof_date_detected,'') ~ '^\d{4}-\d{2}-\d{2}$'
              then to_char(to_date(o.proof_date_detected,'YYYY-MM-DD'),'DD/MM/YYYY') end,
            case when o.payment_submitted_at is not null
              then to_char(o.payment_submitted_at at time zone 'Asia/Jakarta','DD/MM/YYYY') end,
            '—'
          ),
          'Waktu pembayaran: ' || coalesce(
            nullif(trim(o.proof_time_detected),''),
            case when o.payment_submitted_at is not null
              then to_char(o.payment_submitted_at at time zone 'Asia/Jakarta','HH24:MI') end,
            '—'
          ) || case when coalesce(nullif(trim(o.proof_time_detected),''), case when o.payment_submitted_at is not null then to_char(o.payment_submitted_at at time zone 'Asia/Jakarta','HH24:MI') end) is not null then ' WIB' else '' end,
          'Nominal pembayaran: Rp ' || replace(to_char(coalesce(o.paid_amount,o.total_amount,0),'FM999,999,999,999'),',','.')
        )
      ) order by o.created_at desc
    ),
    '[]'::jsonb
  ) into v_orders
  from (
    select * from public.orders
    where
      (payment_status='submitted' and order_status='payment_review')
      or
      (payment_status='verified' and (
        order_status in ('confirmed','preparing','ready')
        or ((created_at at time zone 'Asia/Jakarta')::date = v_today and order_status='completed')
      ))
    order by created_at desc
    limit 200
  ) o;

  return jsonb_build_object('ok',true,'settings',coalesce(v_settings,'{}'::jsonb),'menu',v_menu,'orders',v_orders,'actor',v_email::text);
end;
$function$;

create or replace function public.kds_console_snapshot(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_email extensions.citext;
  v_orders jsonb;
  v_menu jsonb;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  select coalesce(
    jsonb_agg(
      to_jsonb(o) || jsonb_build_object(
        'producer_note',
        concat_ws(' | ',
          nullif(trim(o.producer_note),''),
          'Tanggal pembayaran: ' || coalesce(
            case when coalesce(o.proof_date_detected,'') ~ '^\d{4}-\d{2}-\d{2}$'
              then to_char(to_date(o.proof_date_detected,'YYYY-MM-DD'),'DD/MM/YYYY') end,
            case when o.payment_submitted_at is not null
              then to_char(o.payment_submitted_at at time zone 'Asia/Jakarta','DD/MM/YYYY') end,
            '—'
          ),
          'Waktu pembayaran: ' || coalesce(
            nullif(trim(o.proof_time_detected),''),
            case when o.payment_submitted_at is not null
              then to_char(o.payment_submitted_at at time zone 'Asia/Jakarta','HH24:MI') end,
            '—'
          ) || case when coalesce(nullif(trim(o.proof_time_detected),''), case when o.payment_submitted_at is not null then to_char(o.payment_submitted_at at time zone 'Asia/Jakarta','HH24:MI') end) is not null then ' WIB' else '' end,
          'Nominal pembayaran: Rp ' || replace(to_char(coalesce(o.paid_amount,o.total_amount,0),'FM999,999,999,999'),',','.')
        )
      ) order by o.created_at asc
    ),
    '[]'::jsonb
  ) into v_orders
  from (
    select * from public.orders
    where (
      (payment_status='submitted' and order_status='payment_review')
      or
      (payment_status='verified' and order_status in ('confirmed','preparing','ready','completed'))
    )
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
