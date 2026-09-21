-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912121023  Name: kds_reference_snapshot_cache_v2
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.kds_reference_cache(
  id smallint primary key default 1 check(id=1),
  settings jsonb not null default '{}'::jsonb,
  menu jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);
alter table private.kds_reference_cache enable row level security;
revoke all on private.kds_reference_cache from public,anon,authenticated;

create or replace function private.refresh_kds_reference_cache()
returns boolean language plpgsql security definer set search_path='' as $$
declare v_settings jsonb; v_menu jsonb;
begin
 select jsonb_build_object('business_name',s.business_name,'merchant_name',s.merchant_name,'public_url',s.public_url,'admin_url',s.admin_url,'kds_url',s.kds_url)
 into v_settings from public.site_settings s where s.id=1;
 select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'category',m.category,'price',m.price,'image_url',m.image_url,'is_visible',m.is_visible,'is_available',m.is_available,'availability_note',m.availability_note,'availability_updated_at',m.availability_updated_at,'display_order',m.display_order) order by m.display_order,m.name),'[]'::jsonb)
 into v_menu from public.menu_items m;
 insert into private.kds_reference_cache(id,settings,menu,updated_at) values(1,coalesce(v_settings,'{}'::jsonb),coalesce(v_menu,'[]'::jsonb),now())
 on conflict(id) do update set settings=excluded.settings,menu=excluded.menu,updated_at=excluded.updated_at;
 return true;
end$$;
revoke all on function private.refresh_kds_reference_cache() from public,anon,authenticated;

create or replace function private.refresh_kds_reference_cache_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform private.refresh_kds_reference_cache();
 return null;
end$$;
revoke all on function private.refresh_kds_reference_cache_trigger() from public,anon,authenticated;

drop trigger if exists trg_refresh_kds_cache_menu on public.menu_items;
create trigger trg_refresh_kds_cache_menu after insert or update or delete on public.menu_items for each statement execute function private.refresh_kds_reference_cache_trigger();
drop trigger if exists trg_refresh_kds_cache_settings on public.site_settings;
create trigger trg_refresh_kds_cache_settings after update of business_name,merchant_name,public_url,admin_url,kds_url on public.site_settings for each statement execute function private.refresh_kds_reference_cache_trigger();

select private.refresh_kds_reference_cache();

create or replace function internal_rpc.kds_snapshot(p_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_email extensions.citext;
  v_settings jsonb;
  v_menu jsonb;
  v_orders jsonb;
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_break text := chr(8232);
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select settings,menu into v_settings,v_menu from private.kds_reference_cache where id=1;
  if v_settings is null or v_menu is null then
    perform private.refresh_kds_reference_cache();
    select settings,menu into v_settings,v_menu from private.kds_reference_cache where id=1;
  end if;
  select coalesce(jsonb_agg(to_jsonb(o) || jsonb_build_object('producer_note',v_break || coalesce(nullif(trim(o.producer_note),''),'Nominal pembayaran sesuai dengan total pesanan.') || v_break || '| Tanggal pembayaran: ' || coalesce(case when coalesce(o.proof_date_detected,'') ~ '^\\d{4}-\\d{2}-\\d{2}$' then to_char(to_date(o.proof_date_detected,'YYYY-MM-DD'),'DD/MM/YYYY') end,case when o.payment_submitted_at is not null then to_char(o.payment_submitted_at at time zone 'Asia/Jakarta','DD/MM/YYYY') end,'—') || v_break || '| Waktu pembayaran: ' || coalesce(nullif(trim(o.proof_time_detected),''),case when o.payment_submitted_at is not null then to_char(o.payment_submitted_at at time zone 'Asia/Jakarta','HH24:MI') end,'—') || case when coalesce(nullif(trim(o.proof_time_detected),''),case when o.payment_submitted_at is not null then to_char(o.payment_submitted_at at time zone 'Asia/Jakarta','HH24:MI') end) is not null then ' WIB' else '' end || v_break || '| Nominal pembayaran: Rp ' || replace(to_char(coalesce(o.paid_amount,o.total_amount,0),'FM999,999,999,999'),',','.')) order by o.created_at desc),'[]'::jsonb)
  into v_orders
  from (select * from public.orders where (payment_status='submitted' and order_status='payment_review') or (payment_status='verified' and (order_status in ('confirmed','preparing','ready') or ((created_at at time zone 'Asia/Jakarta')::date=v_today and order_status='completed'))) order by created_at desc limit 200) o;
  return jsonb_build_object('ok',true,'settings',coalesce(v_settings,'{}'::jsonb),'menu',coalesce(v_menu,'[]'::jsonb),'orders',v_orders,'actor',v_email::text);
end$$;
revoke all on function internal_rpc.kds_snapshot(text) from public,anon,authenticated;

