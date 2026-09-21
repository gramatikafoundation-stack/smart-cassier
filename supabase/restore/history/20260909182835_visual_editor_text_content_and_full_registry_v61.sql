-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909182835  Name: visual_editor_text_content_and_full_registry_v61
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.design_sanitize_element_config(p jsonb)
returns jsonb
language plpgsql
immutable
set search_path to ''
as $function$
declare
  o jsonb := '{}'::jsonb;
  t jsonb := coalesce(p->'typography','{}'::jsonb);
  c jsonb := coalesce(p->'colors','{}'::jsonb);
  l jsonb := coalesce(p->'layout','{}'::jsonb);
  ct jsonb := coalesce(p->'content','{}'::jsonb);
  x jsonb := '{}'::jsonb;
  v text;
  n numeric;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return '{}'::jsonb; end if;

  if jsonb_typeof(ct)='object' and ct ? 'text' and jsonb_typeof(ct->'text')='string' then
    v := left(coalesce(ct->>'text',''),500);
    v := regexp_replace(v, E'[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F\\u007F]', '', 'g');
    o := o || jsonb_build_object('content',jsonb_build_object('text',v));
  end if;

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
    foreach v in array array['background','panel','primary','accent','text','muted'] loop
      if coalesce(c->>v,'') ~ '^#[0-9A-Fa-f]{6}$' then x:=x||jsonb_build_object(v,c->>v); end if;
    end loop;
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
end
$function$;

insert into public.design_element_registry(site,page,element_id,label,sort_order) values
('public','home','dine_in_label','Teks Dine In',41),
('public','home','take_away_label','Teks Take Away',42),
('public','home','table_label','Label Nomor Meja',43),
('public','home','table_placeholder','Pilihan Nomor Meja',44),
('public','menu','back_button','Tombol Kembali',5),
('public','menu','context_badge','Badge Meja / Take Away',15),
('public','menu','cart_total','Total pada Tombol Konfirmasi',71),
('public','confirm','brand_label','Nama Usaha di Dialog',5),
('public','confirm','close_button','Tombol Tutup',6),
('public','confirm','name_label','Label Nama Pemesan',25),
('public','confirm','whatsapp_label','Label WhatsApp',35),
('public','confirm','note_label','Label Keterangan',45),
('public','confirm','summary_count','Jumlah Item',52),
('public','confirm','summary_total','Total Pesanan',54),
('public','payment','back_button','Tombol Kembali Pembayaran',2),
('public','payment','page_brand','Nama Usaha Pembayaran',4),
('public','payment','context_badge','Badge Meja / Take Away',8),
('public','payment','summary_eyebrow','Judul Ringkasan Pesanan',12),
('public','payment','summary_customer_label','Label Nama Pemesan',14),
('public','payment','summary_table_label','Label Meja',16),
('public','payment','summary_date_label','Label Tanggal Pesanan',18),
('public','payment','summary_time_label','Label Waktu Pesanan',20),
('public','payment','summary_items_label','Label Menu Jumlah Harga',22),
('public','payment','summary_total_label','Label Total Pesanan',24),
('public','payment','payment_eyebrow','Label Ruang Pembayaran',31),
('public','payment','payment_title','Judul Bayar dengan QRIS',32),
('public','payment','payment_intro','Pengantar Pembayaran',33),
('public','payment','merchant_name','Nama Merchant',34),
('public','payment','instruction_1','Instruksi Pembayaran 1',35),
('public','payment','instruction_2','Instruksi Pembayaran 2',36),
('public','payment','instruction_3','Instruksi Pembayaran 3',37),
('public','payment','instruction_4','Instruksi Pembayaran 4',38),
('public','payment','instruction_5','Instruksi Pembayaran 5',39),
('public','payment','download_button','Tombol Unduh QRIS',41),
('public','payment','paid_checkbox_label','Teks Konfirmasi Pembayaran',51),
('public','payment','proof_label','Label Bukti Pembayaran',52),
('public','success','success_eyebrow','Label Pesanan Terkirim',5),
('public','success','order_number_label','Label Nomor Pesanan',15),
('public','success','status_text','Pesan Status Pesanan',25),

('admin','login','brand_title','Nama Studio pada Login',2),
('admin','login','brand_subtitle','Subjudul Brand Login',4),
('admin','login','email_label','Label Email',22),
('admin','login','email_input','Input Email',24),
('admin','login','password_label','Label Password',26),
('admin','login','password_input','Input Password',28),
('admin','dashboard','brand','Nama Studio Sidebar',15),
('admin','dashboard','topbar_title','Judul Topbar Dashboard',35),
('admin','dashboard','logout_button','Tombol Keluar',36),
('admin','orders','page_title','Judul Halaman Pesanan',5),
('admin','qris','page_title','Judul Halaman QRIS',5),
('admin','qris','merchant_label','Label Nama Merchant',12),
('admin','qris','merchant_input','Input Nama Merchant',14),
('admin','qris','instruction_label','Label Instruksi Pembayaran',16),
('admin','qris','instruction_input','Input Instruksi Pembayaran',18),
('admin','qris','active_label','Label QRIS Aktif',20),
('admin','qris','upload_label','Label Unggah QRIS',22),
('admin','qris','save_button','Tombol Simpan QRIS',24),
('admin','qris','qris_preview','Preview Gambar QRIS',26),
('admin','team','page_title','Judul Halaman Tim Admin',5),
('admin','team','table_row','Baris Tim Admin',30),
('admin','security','page_title','Judul Halaman Keamanan',5),
('admin','security','current_password_label','Label Password Sekarang',12),
('admin','security','current_password_input','Input Password Sekarang',14),
('admin','security','new_password_label','Label Password Baru',16),
('admin','security','new_password_input','Input Password Baru',18),
('admin','security','save_button','Tombol Ubah Password',22),

('kds','login','brand_title','Judul Brand KDS',5),
('kds','login','brand_subtitle','Subjudul Brand KDS',7),
('kds','login','title','Judul Login KDS',15),
('kds','login','email_label','Label Email KDS',22),
('kds','login','email_input','Input Email KDS',24),
('kds','login','password_label','Label Password KDS',26),
('kds','login','password_input','Input Password KDS',28),
('kds','orders','header_title','Judul Header KDS',5),
('kds','orders','logout_button','Tombol Keluar KDS',12),
('kds','orders','tab_orders','Tab Pesanan KDS',18),
('kds','orders','tab_stock','Tab Ketersediaan Barang',19),
('kds','orders','ticket_code','Kode Pesanan KDS',42),
('kds','orders','ticket_meta','Informasi Meja dan Item',44),
('kds','stock','header_title','Judul Ketersediaan Barang',5),
('kds','stock','stock_name','Nama Barang',22),

('database','spreadsheet','page_title','Judul Spreadsheet',5),
('database','sinkronisasi','page_title','Judul Sinkronisasi',5),
('database','mapping-data','page_title','Judul Mapping Data',5),
('database','riwayat','page_title','Judul Riwayat',5)
on conflict (site,page,element_id) do update set label=excluded.label, sort_order=excluded.sort_order;
