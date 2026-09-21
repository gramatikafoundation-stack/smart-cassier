-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260907191809  Name: revise_order_notes_payment_and_7d_archive
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.orders
  add column if not exists paid_amount integer,
  add column if not exists payment_difference integer not null default 0,
  add column if not exists producer_note text not null default '',
  add column if not exists proof_ocr_text text not null default '';

alter table public.orders
  drop constraint if exists orders_paid_amount_nonnegative,
  add constraint orders_paid_amount_nonnegative check (paid_amount is null or paid_amount >= 0);

create or replace function public.coalesce_menu_image_url()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.image_url := coalesce(new.image_url, '');
  return new;
end;
$$;

drop trigger if exists trg_menu_image_url_not_null on public.menu_items;
create trigger trg_menu_image_url_not_null
before insert or update of image_url on public.menu_items
for each row execute function public.coalesce_menu_image_url();

update public.menu_items set image_url = '' where image_url is null;

update public.site_settings
set element_order = '["business_name","welcome","motto","service"]'::jsonb,
    payment_instructions = E'1. Unduh QRIS ke perangkat Anda.\n2. Buka aplikasi bank atau dompet digital, lalu pilih gambar QRIS dari galeri.\n3. Periksa nama UMKM dan nominal, lalu selesaikan pembayaran.\n4. Unggah bukti pembayaran, lalu kirim pesanan.',
    updated_at = now()
where id = 1;

create or replace view public.order_archive_7d
with (security_invoker = true)
as
select
  o.id,
  o.public_order_code,
  o.created_at,
  o.customer_name,
  coalesce((
    select string_agg((x->>'quantity') || '× ' || (x->>'name'), ', ' order by x->>'name')
    from jsonb_array_elements(o.items) x
    left join public.menu_items m on m.id = x->>'menuId'
    where lower(coalesce(m.category,'')) in ('nasi','lauk','paket','promo','makanan')
       or (lower(coalesce(m.category,'')) not in ('minuman','jus buah','jus') and lower(coalesce(m.category,'')) <> '')
  ), '') as food_items,
  coalesce((
    select string_agg((x->>'quantity') || '× ' || (x->>'name'), ', ' order by x->>'name')
    from jsonb_array_elements(o.items) x
    left join public.menu_items m on m.id = x->>'menuId'
    where lower(coalesce(m.category,'')) in ('minuman','jus buah','jus')
  ), '') as drink_items,
  o.item_count,
  coalesce((
    select string_agg((x->>'name') || ': Rp' || to_char((x->>'price')::numeric, 'FM999G999G999'), '; ' order by x->>'name')
    from jsonb_array_elements(o.items) x
  ), '') as unit_prices,
  o.total_amount,
  o.customer_note,
  o.paid_amount,
  o.payment_difference,
  o.producer_note
from public.orders o
where o.created_at >= now() - interval '7 days';

grant select on public.order_archive_7d to authenticated;

create or replace function public.purge_orders_older_than_7_days()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_count integer;
begin
  delete from public.orders
  where created_at < now() - interval '7 days';
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;
revoke all on function public.purge_orders_older_than_7_days() from public;
grant execute on function public.purge_orders_older_than_7_days() to authenticated;

create extension if not exists pg_cron;
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'rohmat_purge_orders_7d') then
    perform cron.schedule(
      'rohmat_purge_orders_7d',
      '17 3 * * *',
      'select public.purge_orders_older_than_7_days();'
    );
  end if;
end $$;
