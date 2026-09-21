-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909113724  Name: visual_editor_element_registry
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists public.design_element_registry(
  site text not null,
  page text not null,
  element_id text not null,
  label text not null,
  sort_order integer not null default 0,
  primary key(site,page,element_id),
  constraint design_element_registry_site check(site in ('public','admin','kds')),
  constraint design_element_registry_key check(page ~ '^[a-z0-9_-]{1,40}$' and element_id ~ '^[a-z0-9_-]{1,60}$')
);
alter table public.design_element_registry enable row level security;
do $$ begin if not exists(select 1 from pg_policies where schemaname='public' and tablename='design_element_registry' and policyname='deny_client_write') then create policy deny_client_write on public.design_element_registry for all to anon,authenticated using(false) with check(false); end if; end $$;

insert into public.design_element_registry(site,page,element_id,label,sort_order) values
('public','home','business_name','Nama Usaha',10),('public','home','welcome','Salam Pembuka',20),('public','home','motto','Motto',30),('public','home','service_option','Pilihan Dine In / Take Away',40),('public','home','next_button','Tombol Lanjut Pilih Menu',50),
('public','menu','page_title','Judul Pilih Menu',10),('public','menu','category_tab','Tab Kategori',20),('public','menu','menu_card','Kartu Menu',30),('public','menu','menu_name','Nama Menu',40),('public','menu','price','Harga Menu',50),('public','menu','add_button','Tombol Tambah',60),('public','menu','cart_button','Tombol Konfirmasi Menu',70),
('public','confirm','title','Judul Konfirmasi',10),('public','confirm','item_line','Baris Pesanan',20),('public','confirm','name_input','Input Nama Pemesan',30),('public','confirm','whatsapp_input','Input WhatsApp',40),('public','confirm','note_input','Input Keterangan',50),('public','confirm','pay_button','Tombol Lanjut Pembayaran',60),
('public','payment','page_title','Judul Pembayaran',10),('public','payment','summary_card','Ringkasan Pesanan',20),('public','payment','qris_panel','Panel QRIS',30),('public','payment','choose_file','Pilih File Bukti Pembayaran',40),('public','payment','paid_checkbox','Saya Telah Membayar',50),('public','payment','send_button','Kirim Pesanan & Konfirmasi',60),
('public','success','title','Judul Pesanan Terkirim',10),('public','success','order_code','Kode Pesanan',20),('public','success','new_order_button','Tombol Buat Pesanan Baru',30),
('admin','login','title','Judul Login',10),('admin','login','login_card','Kartu Login',20),('admin','login','input','Input Login',30),('admin','login','button','Tombol Masuk',40),
('admin','dashboard','sidebar','Sidebar',10),('admin','dashboard','navigation','Navigasi',20),('admin','dashboard','topbar','Topbar',30),('admin','dashboard','stat_card','Kartu Statistik',40),
('admin','orders','table','Tabel Pesanan',10),('admin','orders','table_header','Header Tabel',20),('admin','orders','table_row','Baris Tabel',30),
('admin','qris','panel','Panel QRIS',10),('admin','qris','input','Input QRIS',20),('admin','qris','button','Tombol Simpan QRIS',30),
('admin','team','table','Tabel Tim Admin',10),('admin','team','table_header','Header Tabel Tim',20),
('admin','security','form','Form Keamanan',10),('admin','security','input','Input Password',20),('admin','security','button','Tombol Ubah Password',30),
('kds','login','brand','Panel Brand KDS',10),('kds','login','login_card','Kartu Login KDS',20),('kds','login','input','Input Login KDS',30),('kds','login','button','Tombol Masuk KDS',40),
('kds','orders','header','Header KDS',10),('kds','orders','tab','Tab KDS',20),('kds','orders','stat_card','Kartu Statistik',30),('kds','orders','ticket','Tiket Pesanan',40),('kds','orders','action_button','Tombol Aksi Pesanan',50),
('kds','stock','search','Pencarian Stok',10),('kds','stock','stock_card','Kartu Stok',20),('kds','stock','switch','Saklar Ketersediaan',30)
on conflict(site,page,element_id) do update set label=excluded.label,sort_order=excluded.sort_order;

create or replace function private.design_sanitize_element_config(p jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare o jsonb:='{}'::jsonb; t jsonb:=coalesce(p->'typography','{}'::jsonb); c jsonb:=coalesce(p->'colors','{}'::jsonb); l jsonb:=coalesce(p->'layout','{}'::jsonb); x jsonb:='{}'::jsonb; v text; n numeric;
begin
 if p is null or jsonb_typeof(p)<>'object' then return '{}'::jsonb; end if;
 if jsonb_typeof(t)='object' then
   v:=t->>'family'; if v=any(array['system-ui','Inter','Manrope','Segoe UI','Arial','Helvetica','Calibri','Georgia','Times New Roman','Garamond','Palatino Linotype','Courier New']) then x:=x||jsonb_build_object('family',v); end if;
   if jsonb_typeof(t->'size')='number' then n:=(t->>'size')::numeric; if n between 10 and 72 then x:=x||jsonb_build_object('size',n); end if; end if;
   if jsonb_typeof(t->'weight')='number' then n:=(t->>'weight')::numeric; if n between 300 and 900 then x:=x||jsonb_build_object('weight',n); end if; end if;
   if jsonb_typeof(t->'italic')='boolean' then x:=x||jsonb_build_object('italic',(t->>'italic')::boolean); end if;
   v:=t->>'align'; if v=any(array['left','center','right','justify']) then x:=x||jsonb_build_object('align',v); end if;
   if jsonb_typeof(t->'lineHeight')='number' then n:=(t->>'lineHeight')::numeric; if n between 1 and 2 then x:=x||jsonb_build_object('lineHeight',n); end if; end if;
   if jsonb_typeof(t->'letterSpacing')='number' then n:=(t->>'letterSpacing')::numeric; if n between -2 and 6 then x:=x||jsonb_build_object('letterSpacing',n); end if; end if;
   if x<>'{}'::jsonb then o:=o||jsonb_build_object('typography',x); end if;
 end if;
 x:='{}'::jsonb;
 if jsonb_typeof(c)='object' then
   foreach v in array array['background','panel','primary','accent','text','muted'] loop if coalesce(c->>v,'') ~ '^#[0-9A-Fa-f]{6}$' then x:=x||jsonb_build_object(v,c->>v); end if; end loop;
   if x<>'{}'::jsonb then o:=o||jsonb_build_object('colors',x); end if;
 end if;
 x:='{}'::jsonb;
 if jsonb_typeof(l)='object' then
   if jsonb_typeof(l->'radius')='number' then n:=(l->>'radius')::numeric; if n between 0 and 40 then x:=x||jsonb_build_object('radius',n); end if; end if;
   if jsonb_typeof(l->'padding')='number' then n:=(l->>'padding')::numeric; if n between 0 and 48 then x:=x||jsonb_build_object('padding',n); end if; end if;
   if jsonb_typeof(l->'minHeight')='number' then n:=(l->>'minHeight')::numeric; if n between 20 and 160 then x:=x||jsonb_build_object('minHeight',n); end if; end if;
   if x<>'{}'::jsonb then o:=o||jsonb_build_object('layout',x); end if;
 end if;
 return o;
end $$;

create or replace function public.admin_design_system_set_element(p_token text,p_site text,p_page text,p_element text,p_config jsonb,p_publish boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare em extensions.citext; st jsonb; base jsonb; clean jsonb; path text[]; res jsonb;
begin
 em:=private.admin_email_from_token(p_token); if em is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
 if not exists(select 1 from public.design_element_registry r where r.site=p_site and r.page=p_page and r.element_id=p_element) then return jsonb_build_object('ok',false,'error','element_not_allowed'); end if;
 clean:=private.design_sanitize_element_config(p_config); if clean='{}'::jsonb then return jsonb_build_object('ok',false,'error','empty_or_invalid_config'); end if;
 select design_system into st from public.site_settings where id=1 for update;
 base:=case when coalesce(p_publish,false) then coalesce(st->'published','{}'::jsonb) else coalesce(st->'draft',st->'published','{}'::jsonb) end;
 path:=array['elements',p_site,p_page,p_element]; base:=jsonb_set(base,path,clean,true);
 if coalesce(p_publish,false) then res:=private.design_system_apply_payload(em::text,base,'published',null); return res; end if;
 return public.admin_design_system_save_draft(p_token,base);
end $$;

create or replace function public.admin_design_system_reset_element(p_token text,p_site text,p_page text,p_element text,p_publish boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare em extensions.citext; st jsonb; base jsonb; path text[]; res jsonb;
begin
 em:=private.admin_email_from_token(p_token); if em is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
 if not exists(select 1 from public.design_element_registry r where r.site=p_site and r.page=p_page and r.element_id=p_element) then return jsonb_build_object('ok',false,'error','element_not_allowed'); end if;
 select design_system into st from public.site_settings where id=1 for update;
 base:=case when coalesce(p_publish,false) then coalesce(st->'published','{}'::jsonb) else coalesce(st->'draft',st->'published','{}'::jsonb) end;
 path:=array['elements',p_site,p_page,p_element]; base:=base #- path;
 if coalesce(p_publish,false) then res:=private.design_system_apply_payload(em::text,base,'published',null); return res; end if;
 return public.admin_design_system_save_draft(p_token,base);
end $$;

revoke all on function public.admin_design_system_set_element(text,text,text,text,jsonb,boolean) from public;
revoke all on function public.admin_design_system_reset_element(text,text,text,text,boolean) from public;
grant execute on function public.admin_design_system_set_element(text,text,text,text,jsonb,boolean) to anon,authenticated,service_role;
grant execute on function public.admin_design_system_reset_element(text,text,text,text,boolean) to anon,authenticated,service_role;
revoke all on public.design_element_registry from anon,authenticated;
grant select on public.design_element_registry to service_role;
