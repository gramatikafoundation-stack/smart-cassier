-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260904024505  Name: create_rohmat_ordering_platform
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create extension if not exists citext with schema extensions;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table public.admin_users (
  email extensions.citext primary key,
  display_name text not null default '',
  role text not null check (role in ('superadmin', 'admin')),
  is_active boolean not null default true,
  is_protected boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  constraint admin_email_length check (char_length(email::text) between 5 and 254)
);

create table public.site_settings (
  id smallint primary key default 1 check (id = 1),
  business_name text not null default 'MIE SUPER',
  welcome_text text not null default 'Selamat datang, Sobat Rohmat',
  motto text not null default 'Kepuasan Anda Adalah Prioritas Kami',
  hero_image_url text not null default '/images/hero.jpg',
  public_url text not null default 'https://rohmat-pesan-bayar-publik.vercel.app',
  admin_url text not null default '',
  kds_url text not null default '',
  photo_position text not null default 'left' check (photo_position in ('left', 'right', 'top')),
  content_position text not null default 'center' check (content_position in ('left', 'center', 'right')),
  content_width text not null default 'balanced' check (content_width in ('compact', 'balanced', 'wide')),
  element_order jsonb not null default '["welcome","business_name","motto","service"]'::jsonb,
  theme_preset text not null default 'warm-green' check (theme_preset in ('warm-green', 'elegant-red', 'modern-yellow', 'custom')),
  color_outer text not null default '#F4EFE6',
  color_panel text not null default '#FFFDF8',
  color_primary text not null default '#244A3B',
  color_accent text not null default '#D35D3A',
  color_text text not null default '#223A30',
  color_muted text not null default '#737D76',
  typography jsonb not null default '{"welcome":{"family":"Manrope","size":14,"weight":700,"style":"normal","align":"left"},"business_name":{"family":"Manrope","size":80,"weight":900,"style":"normal","align":"left"},"motto":{"family":"Manrope","size":16,"weight":700,"style":"normal","align":"left"},"service":{"family":"Manrope","size":14,"weight":700,"style":"normal","align":"left"}}'::jsonb,
  merchant_name text not null default 'Rohmat Nasi Uduk',
  payment_instructions text not null default 'Pindai QRIS, periksa nominal, lalu tekan konfirmasi pembayaran.',
  qris_image_url text,
  qris_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint settings_business_name_length check (char_length(business_name) between 1 and 80),
  constraint settings_welcome_length check (char_length(welcome_text) between 1 and 140),
  constraint settings_motto_length check (char_length(motto) between 1 and 240),
  constraint settings_element_order_array check (jsonb_typeof(element_order) = 'array'),
  constraint settings_typography_object check (jsonb_typeof(typography) = 'object')
);

create table public.menu_items (
  id text primary key check (id ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  name text not null,
  category text not null check (category in ('Nasi', 'Lauk', 'Minuman', 'Jus Buah')),
  price integer not null check (price >= 0 and price <= 10000000),
  description text not null default '',
  image_url text not null default '',
  is_favorite boolean not null default false,
  is_visible boolean not null default true,
  display_order integer not null check (display_order >= 1),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint menu_name_length check (char_length(name) between 1 and 100),
  constraint menu_description_length check (char_length(description) <= 500)
);

create unique index menu_items_display_order_key on public.menu_items(display_order);
create index menu_items_public_catalog_idx on public.menu_items(is_visible, display_order);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  public_order_code text not null unique default ('RHM-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  service_mode text not null check (service_mode in ('dine-in', 'take-away')),
  table_number smallint,
  customer_name text not null,
  items jsonb not null,
  item_count integer not null check (item_count > 0 and item_count <= 200),
  total_amount integer not null check (total_amount > 0 and total_amount <= 100000000),
  payment_method text not null default 'qris' check (payment_method = 'qris'),
  payment_status text not null default 'pending' check (payment_status in ('pending', 'submitted', 'verified', 'rejected')),
  order_status text not null default 'awaiting_payment' check (order_status in ('awaiting_payment', 'payment_review', 'confirmed', 'preparing', 'ready', 'completed', 'cancelled')),
  payment_proof_url text,
  customer_note text not null default '',
  client_order_id text,
  payment_submitted_at timestamptz,
  verified_at timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  kitchen_sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orders_customer_name_length check (char_length(customer_name) between 2 and 60),
  constraint orders_items_array check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) > 0),
  constraint orders_service_table check (
    (service_mode = 'dine-in' and table_number between 1 and 20)
    or (service_mode = 'take-away' and table_number is null)
  )
);

create unique index orders_client_order_id_key on public.orders(client_order_id) where client_order_id is not null;
create index orders_active_queue_idx on public.orders(order_status, created_at desc)
  where order_status not in ('completed', 'cancelled');
create index orders_payment_queue_idx on public.orders(payment_status, created_at desc);

create table public.order_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  event_type text not null,
  from_status text,
  to_status text,
  note text not null default '',
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint order_event_type_length check (char_length(event_type) between 2 and 60),
  constraint order_event_note_length check (char_length(note) <= 500)
);

create index order_events_order_created_idx on public.order_events(order_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.set_updated_at() from public;

create trigger site_settings_updated_at
before update on public.site_settings
for each row execute function public.set_updated_at();

create trigger menu_items_updated_at
before update on public.menu_items
for each row execute function public.set_updated_at();

create trigger orders_updated_at
before update on public.orders
for each row execute function public.set_updated_at();

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.admin_users au
      where au.email = lower(coalesce((select auth.jwt() ->> 'email'), ''))::extensions.citext
        and au.is_active
    );
$$;

create or replace function private.is_superadmin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.admin_users au
      where au.email = lower(coalesce((select auth.jwt() ->> 'email'), ''))::extensions.citext
        and au.is_active
        and au.role = 'superadmin'
    );
$$;

revoke all on function private.is_admin() from public;
revoke all on function private.is_superadmin() from public;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.is_superadmin() to authenticated;

alter table public.admin_users enable row level security;
alter table public.site_settings enable row level security;
alter table public.menu_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_events enable row level security;

create policy "Public reads site settings"
on public.site_settings for select
to anon, authenticated
using (true);

create policy "Admins update site settings"
on public.site_settings for update
to authenticated
using ((select private.is_admin()))
with check ((select private.is_admin()));

create policy "Public reads visible menu"
on public.menu_items for select
to anon, authenticated
using (is_visible);

create policy "Admins read all menu"
on public.menu_items for select
to authenticated
using ((select private.is_admin()));

create policy "Admins insert menu"
on public.menu_items for insert
to authenticated
with check ((select private.is_admin()));

create policy "Admins update menu"
on public.menu_items for update
to authenticated
using ((select private.is_admin()))
with check ((select private.is_admin()));

create policy "Admins delete menu"
on public.menu_items for delete
to authenticated
using ((select private.is_admin()));

create policy "Admins read orders"
on public.orders for select
to authenticated
using ((select private.is_admin()));

create policy "Admins create orders"
on public.orders for insert
to authenticated
with check ((select private.is_admin()));

create policy "Admins update orders"
on public.orders for update
to authenticated
using ((select private.is_admin()))
with check ((select private.is_admin()));

create policy "Admins read order events"
on public.order_events for select
to authenticated
using ((select private.is_admin()));

create policy "Admins create order events"
on public.order_events for insert
to authenticated
with check ((select private.is_admin()));

create policy "Admins read team"
on public.admin_users for select
to authenticated
using ((select private.is_admin()));

create policy "Superadmins add team"
on public.admin_users for insert
to authenticated
with check ((select private.is_superadmin()));

create policy "Superadmins update team"
on public.admin_users for update
to authenticated
using ((select private.is_superadmin()))
with check ((select private.is_superadmin()));

create policy "Superadmins delete team"
on public.admin_users for delete
to authenticated
using ((select private.is_superadmin()) and not is_protected);

grant usage on schema public to anon, authenticated;
grant select (
  id, business_name, welcome_text, motto, hero_image_url, public_url,
  photo_position, content_position, content_width, element_order,
  theme_preset, color_outer, color_panel, color_primary, color_accent,
  color_text, color_muted, typography, merchant_name,
  payment_instructions, qris_image_url, qris_enabled, updated_at
) on public.site_settings to anon;
grant select (
  id, name, category, price, description, image_url,
  is_favorite, is_visible, display_order, updated_at
) on public.menu_items to anon;
grant select on public.site_settings, public.menu_items, public.orders, public.order_events, public.admin_users to authenticated;
grant insert, update, delete on public.menu_items to authenticated;
grant update on public.site_settings to authenticated;
grant insert, update on public.orders to authenticated;
grant insert on public.order_events to authenticated;
grant insert, update, delete on public.admin_users to authenticated;
grant usage, select on sequence public.order_events_id_seq to authenticated;

insert into public.site_settings (id)
values (1)
on conflict (id) do nothing;

insert into public.admin_users (email, display_name, role, is_active, is_protected)
values
  ('restore-superadmin@example.invalid', 'Gramatika Foundation', 'superadmin', true, true),
  ('restore-admin@example.invalid', 'Probolinggo Raya Info', 'admin', true, true)
on conflict (email) do update set
  display_name = excluded.display_name,
  role = excluded.role,
  is_active = excluded.is_active,
  is_protected = excluded.is_protected;

insert into public.menu_items (id, name, category, price, description, image_url, is_favorite, is_visible, display_order)
values
  ('nasi-uduk', 'Nasi Uduk', 'Nasi', 9000, 'Pilihan nasi hangat untuk memulai pesanan Anda.', '/images/menu/nasi-uduk.jpg', true, true, 1),
  ('nasi-putih', 'Nasi Putih', 'Nasi', 5000, 'Pilihan nasi hangat untuk memulai pesanan Anda.', '/images/menu/nasi-putih.jpg', false, true, 2),
  ('bebek-super', 'Bebek Super', 'Lauk', 23000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '/images/menu/bebek-goreng.jpg', true, true, 3),
  ('ayam-goreng', 'Ayam Goreng', 'Lauk', 19000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '/images/menu/ayam-goreng.jpg', true, true, 4),
  ('ampela-ati', 'Ampela Ati', 'Lauk', 10000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '/images/menu/ampela-ati.jpg', false, true, 5),
  ('usus-ayam', 'Usus Ayam', 'Lauk', 10000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '', false, true, 6),
  ('kepala-bebek', 'Kepala Bebek', 'Lauk', 5000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '', false, true, 7),
  ('kepala-ayam', 'Kepala Ayam', 'Lauk', 2000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '/images/menu/kepala-ayam.jpg', false, true, 8),
  ('bandeng-presto', 'Bandeng Presto', 'Lauk', 16000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '/images/menu/bandeng-presto.jpg', false, true, 9),
  ('telor-dadar', 'Telor Dadar', 'Lauk', 8000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '', false, true, 10),
  ('pete', 'Pete', 'Lauk', 10000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '', false, true, 11),
  ('terong', 'Terong', 'Lauk', 1000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '', false, true, 12),
  ('tahu', 'Tahu', 'Lauk', 2000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '/images/menu/tahu.jpg', false, true, 13),
  ('tempe', 'Tempe', 'Lauk', 2000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '/images/menu/tempe.jpg', false, true, 14),
  ('babat-sapi', 'Babat Sapi', 'Lauk', 19000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '/images/menu/babat-sapi.jpg', false, true, 15),
  ('paru-sapi', 'Paru Sapi', 'Lauk', 19000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '/images/menu/paru-sapi.jpg', false, true, 16),
  ('limpa-sapi', 'Limpa Sapi', 'Lauk', 19000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '', false, true, 17),
  ('empal-sapi', 'Empal Sapi', 'Lauk', 20000, 'Lauk pilihan Rohmat Nasi Uduk, siap menemani santapan.', '/images/menu/empal-sapi.jpg', false, true, 18),
  ('teh-hangat', 'Teh Hangat', 'Minuman', 6000, 'Minuman pendamping yang pas dinikmati bersama hidangan.', '/images/menu/teh-hangat.jpg', false, true, 19),
  ('es-teh', 'Es Teh', 'Minuman', 6000, 'Minuman pendamping yang pas dinikmati bersama hidangan.', '/images/menu/es-teh.jpg', false, true, 20),
  ('jeruk-hangat', 'Jeruk Hangat', 'Minuman', 9000, 'Minuman pendamping yang pas dinikmati bersama hidangan.', '/images/menu/jeruk-hangat.jpg', false, true, 21),
  ('es-jeruk', 'Es Jeruk', 'Minuman', 9000, 'Minuman pendamping yang pas dinikmati bersama hidangan.', '/images/menu/es-jeruk.jpg', false, true, 22),
  ('kopi', 'Kopi', 'Minuman', 6000, 'Minuman pendamping yang pas dinikmati bersama hidangan.', '', false, true, 23),
  ('aqua', 'Air Mineral AQUA', 'Minuman', 5000, 'Minuman pendamping yang pas dinikmati bersama hidangan.', '/images/menu/aqua.jpg', false, true, 24),
  ('jus-alpukat', 'Jus Alpukat', 'Jus Buah', 16000, 'Jus buah segar untuk melengkapi pesanan Anda.', '/images/menu/jus-alpukat.jpg', false, true, 25),
  ('jus-jambu', 'Jus Jambu', 'Jus Buah', 13000, 'Jus buah segar untuk melengkapi pesanan Anda.', '/images/menu/jus-jambu.jpg', false, true, 26),
  ('jus-melon', 'Jus Melon', 'Jus Buah', 13000, 'Jus buah segar untuk melengkapi pesanan Anda.', '', false, true, 27),
  ('jus-sirsat', 'Jus Sirsat', 'Jus Buah', 13000, 'Jus buah segar untuk melengkapi pesanan Anda.', '/images/menu/jus-sirsat.jpg', false, true, 28),
  ('jus-belimbing', 'Jus Belimbing', 'Jus Buah', 13000, 'Jus buah segar untuk melengkapi pesanan Anda.', '', false, true, 29),
  ('jus-buah-naga', 'Jus Buah Naga', 'Jus Buah', 13000, 'Jus buah segar untuk melengkapi pesanan Anda.', '', false, true, 30),
  ('jus-mangga', 'Jus Mangga', 'Jus Buah', 13000, 'Jus buah segar untuk melengkapi pesanan Anda.', '/images/menu/jus-mangga.jpg', false, true, 31),
  ('jus-apel', 'Jus Apel', 'Jus Buah', 13000, 'Jus buah segar untuk melengkapi pesanan Anda.', '', false, true, 32),
  ('jus-stroberi', 'Jus Stroberi', 'Jus Buah', 13000, 'Jus buah segar untuk melengkapi pesanan Anda.', '', false, true, 33),
  ('jus-wortel', 'Jus Wortel', 'Jus Buah', 13000, 'Jus buah segar untuk melengkapi pesanan Anda.', '', false, true, 34),
  ('jus-tomat', 'Jus Tomat', 'Jus Buah', 13000, 'Jus buah segar untuk melengkapi pesanan Anda.', '', false, true, 35),
  ('jus-mix', 'Jus Mix', 'Jus Buah', 17000, 'Campuran buah segar untuk rasa yang lebih lengkap.', '', false, true, 36)
on conflict (id) do update set
  name = excluded.name,
  category = excluded.category,
  price = excluded.price,
  description = excluded.description,
  image_url = excluded.image_url,
  is_favorite = excluded.is_favorite,
  is_visible = excluded.is_visible,
  display_order = excluded.display_order;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'rohmat-assets',
  'rohmat-assets',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Admins read asset objects"
on storage.objects for select
to authenticated
using (bucket_id = 'rohmat-assets' and (select private.is_admin()));

create policy "Admins upload asset objects"
on storage.objects for insert
to authenticated
with check (bucket_id = 'rohmat-assets' and (select private.is_admin()));

create policy "Admins update asset objects"
on storage.objects for update
to authenticated
using (bucket_id = 'rohmat-assets' and (select private.is_admin()))
with check (bucket_id = 'rohmat-assets' and (select private.is_admin()));

create policy "Admins delete asset objects"
on storage.objects for delete
to authenticated
using (bucket_id = 'rohmat-assets' and (select private.is_admin()));

do $$
declare
  relation_name text;
begin
  foreach relation_name in array array['site_settings', 'menu_items', 'orders']
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = relation_name
    ) then
      execute format('alter publication supabase_realtime add table public.%I', relation_name);
    end if;
  end loop;
end;
$$;

