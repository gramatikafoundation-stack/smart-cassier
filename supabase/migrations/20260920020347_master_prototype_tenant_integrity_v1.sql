-- ROHMAT MASTER PROTOTIPE v1
-- Phase 3: tenant-scoped integrity for core transactional tables.
-- Existing Rohmat rows remain unchanged; uniqueness and triggers become tenant-aware.

alter table private.admin_sessions
  add column if not exists tenant_id uuid;
update private.admin_sessions
set tenant_id=private.reference_tenant_id()
where tenant_id is null;
alter table private.admin_sessions
  alter column tenant_id set default private.reference_tenant_id(),
  alter column tenant_id set not null;
do $$
begin
  begin
    alter table private.admin_sessions
      add constraint admin_sessions_tenant_id_fkey
      foreign key(tenant_id) references private.platform_tenants(id) on delete cascade;
  exception when duplicate_object then null;
  end;
end $$;
create index if not exists admin_sessions_tenant_email_idx
  on private.admin_sessions(tenant_id,email,expires_at desc);

-- Menu ordering is tenant-local, while menu ids remain globally unique.
drop index if exists public.menu_items_display_order_key;
create unique index if not exists menu_items_tenant_display_order_uidx
  on public.menu_items(tenant_id,display_order);
drop index if exists public.menu_items_public_catalog_idx;
create index if not exists menu_items_tenant_public_catalog_idx
  on public.menu_items(tenant_id,is_visible,display_order);

-- Client order ids and proof hashes are unique within a tenant.
drop index if exists public.orders_client_order_id_key;
create unique index if not exists orders_tenant_client_order_uidx
  on public.orders(tenant_id,client_order_id)
  where client_order_id is not null;
drop index if exists public.orders_payment_proof_sha256_unique;
create unique index if not exists orders_tenant_payment_proof_uidx
  on public.orders(tenant_id,payment_proof_sha256)
  where payment_proof_sha256 is not null and payment_proof_sha256<>'';

drop index if exists public.order_history_archive_client_order_id_key;
create unique index if not exists order_history_tenant_client_order_uidx
  on public.order_history_archive(tenant_id,client_order_id)
  where client_order_id is not null;
drop index if exists public.order_history_archive_payment_proof_sha256_key;
create unique index if not exists order_history_tenant_payment_proof_uidx
  on public.order_history_archive(tenant_id,payment_proof_sha256)
  where payment_proof_sha256 is not null and payment_proof_sha256<>'';

drop index if exists private.order_identity_registry_client_uidx;
create unique index if not exists order_identity_registry_tenant_client_uidx
  on private.order_identity_registry(tenant_id,client_order_id)
  where client_order_id is not null;
drop index if exists private.order_identity_registry_proof_uidx;
create unique index if not exists order_identity_registry_tenant_proof_uidx
  on private.order_identity_registry(tenant_id,payment_proof_sha256)
  where payment_proof_sha256 is not null and payment_proof_sha256<>'';

create or replace function public.enforce_archived_order_dedupe()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.client_order_id is not null and exists (
    select 1
    from public.order_history_archive a
    where a.tenant_id=new.tenant_id
      and a.client_order_id=new.client_order_id
  ) then
    raise exception using errcode='23505', message='Identitas pesanan ini sudah pernah diproses.';
  end if;
  if new.payment_proof_sha256 is not null and new.payment_proof_sha256<>'' and exists (
    select 1
    from public.order_history_archive a
    where a.tenant_id=new.tenant_id
      and a.payment_proof_sha256=new.payment_proof_sha256
  ) then
    raise exception using errcode='23505', message='Bukti pembayaran ini sudah pernah digunakan pada pesanan lain.';
  end if;
  return new;
end
$$;

create or replace function public.enforce_order_item_availability()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_bad_count integer;
begin
  select count(*) into v_bad_count
  from jsonb_array_elements(new.items) x
  left join public.menu_items m
    on m.id=x->>'menuId'
   and m.tenant_id=new.tenant_id
  where m.id is null
     or m.is_visible is not true
     or m.is_available is not true;
  if v_bad_count>0 then
    raise exception 'Salah satu menu sedang habis atau tidak tersedia. Silakan perbarui menu dan pilih kembali.'
      using errcode='P0001';
  end if;
  return new;
end
$$;

create or replace function private.enforce_order_menu_availability()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_item jsonb;
  v_menu_id text;
  v_bad text[]:='{}';
begin
  if new.items is null or jsonb_typeof(new.items)<>'array' then return new; end if;
  for v_item in select * from jsonb_array_elements(new.items)
  loop
    v_menu_id:=coalesce(v_item->>'menuId',v_item->>'id');
    if v_menu_id is null or not exists(
      select 1 from public.menu_items m
      where m.id=v_menu_id
        and m.tenant_id=new.tenant_id
        and m.is_visible=true
        and coalesce(m.is_available,true)=true
    ) then
      v_bad:=array_append(v_bad,coalesce(v_menu_id,'menu-tidak-valid'));
    end if;
  end loop;
  if array_length(v_bad,1) is not null then
    raise exception using errcode='P0001',
      message='Salah satu menu sedang habis atau tidak tersedia: '||array_to_string(v_bad,', ');
  end if;
  return new;
end
$$;

create or replace function private.reserve_order_identity()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  insert into private.order_identity_registry(
    order_id,public_order_code,client_order_id,payment_proof_sha256,reserved_at,tenant_id
  )
  values(
    new.id,new.public_order_code,new.client_order_id,nullif(new.payment_proof_sha256,''),
    coalesce(new.created_at,now()),new.tenant_id
  );
  return new;
exception
  when unique_violation then
    raise exception using errcode='23505',
      message='Identitas pesanan, client order, atau bukti pembayaran sudah pernah digunakan.';
end
$$;

create or replace function private.record_initial_order_event()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor_id uuid;
  v_actor_role text;
  v_actor_email extensions.citext;
begin
  if new.order_source in ('cashier_admin','cashier_kds') then
    v_actor_email:=nullif(new.cashier_actor,'')::extensions.citext;
    select u.id into v_actor_id from auth.users u
      where lower(u.email)=lower(v_actor_email::text) limit 1;
    select tm.role into v_actor_role
      from private.tenant_memberships tm
      where tm.tenant_id=new.tenant_id
        and lower(tm.email)=lower(v_actor_email::text)
        and tm.is_active
      limit 1;
    insert into public.order_events(
      order_id,event_type,from_status,to_status,note,actor_id,actor_email,
      actor_role,source_app,request_id,tenant_id
    )
    values(
      new.id,'cashier_order_created',null,new.order_status,
      case when new.payment_method='cash'
        then 'Pesanan kasir dibuat dan dibayar tunai.'
        else 'Pesanan kasir dibuat dan dibayar QRIS.' end,
      v_actor_id,v_actor_email,v_actor_role,new.order_source,new.request_id,new.tenant_id
    )
    on conflict do nothing;
  elsif new.order_source='public'
    and new.payment_status='submitted'
    and new.order_status='payment_review' then
    insert into public.order_events(
      order_id,event_type,from_status,to_status,note,source_app,request_id,tenant_id
    )
    values(
      new.id,'payment_submitted','awaiting_payment','payment_review',
      case when new.proof_check_status='matched'
        then 'Bukti pembayaran lolos pemeriksaan awal otomatis dan menunggu verifikasi KDS.'
        else 'Bukti pembayaran diterima dan memerlukan pemeriksaan petugas KDS.' end,
      'public',new.request_id,new.tenant_id
    )
    on conflict do nothing;
  end if;
  return new;
end
$$;

create or replace function private.enqueue_sheet_sync_event()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_row jsonb;
  v_entity_type text;
  v_entity_id text;
  v_operation text;
  v_target_year integer;
  v_updated_at timestamptz;
  v_tabs jsonb;
  v_key text;
  v_request_id uuid;
  v_tenant_id uuid;
begin
  v_row:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  begin v_request_id:=nullif(v_row->>'request_id','')::uuid; exception when others then v_request_id:=null; end;
  begin v_tenant_id:=nullif(v_row->>'tenant_id','')::uuid; exception when others then v_tenant_id:=null; end;
  v_tenant_id:=coalesce(v_tenant_id,private.reference_tenant_id());
  v_request_id:=coalesce(v_request_id,gen_random_uuid());

  if tg_table_name='menu_items' then
    v_entity_type:='menu';
    v_entity_id:=coalesce(v_row->>'id','unknown');
    v_operation:=tg_op;
    v_target_year:=null;
    v_updated_at:=coalesce((v_row->>'updated_at')::timestamptz,now());
    v_tabs:='["MENU & STOK","DASHBOARD"]'::jsonb;
  elsif tg_table_name='order_history_archive' then
    v_entity_type:='order';
    v_entity_id:=coalesce(v_row->>'id','unknown');
    v_operation:='ARCHIVE';
    v_target_year:=extract(year from ((v_row->>'created_at')::timestamptz at time zone 'Asia/Jakarta'))::integer;
    v_updated_at:=coalesce((v_row->>'archived_at')::timestamptz,(v_row->>'created_at')::timestamptz,now());
    v_tabs:='["PEMESAN","PESANAN","MENU & STOK","KEUANGAN","DASHBOARD"]'::jsonb;
  else
    v_entity_type:='order';
    v_entity_id:=coalesce(v_row->>'id','unknown');
    v_operation:=tg_op;
    v_target_year:=extract(year from ((v_row->>'created_at')::timestamptz at time zone 'Asia/Jakarta'))::integer;
    v_updated_at:=coalesce((v_row->>'updated_at')::timestamptz,(v_row->>'created_at')::timestamptz,now());
    v_tabs:='["PEMESAN","PESANAN","MENU & STOK","KEUANGAN","DASHBOARD"]'::jsonb;
  end if;

  v_key:=v_tenant_id::text||':'||tg_table_name||':'||v_entity_id||':'||v_operation||':'||md5(v_row::text);

  update public.sheet_sync_outbox
     set status='superseded',
         last_error='Superseded by a newer event for the same tenant/entity.'
   where tenant_id=v_tenant_id
     and entity_type=v_entity_type
     and entity_id=v_entity_id
     and target_year is not distinct from v_target_year
     and status in ('pending','failed');

  insert into public.sheet_sync_outbox(
    request_id,idempotency_key,entity_type,entity_id,operation,target_year,
    affected_tabs,payload,source_updated_at,tenant_id
  )
  values(
    v_request_id,v_key,v_entity_type,v_entity_id,v_operation,v_target_year,
    v_tabs,
    jsonb_build_object(
      'request_id',v_request_id,
      'tenant_id',v_tenant_id,
      'source_table',tg_table_name,
      'entity_id',v_entity_id,
      'operation',v_operation,
      'target_year',v_target_year,
      'source_updated_at',v_updated_at,
      'affected_tabs',v_tabs
    ),
    v_updated_at,v_tenant_id
  )
  on conflict(idempotency_key) do nothing;

  return case when tg_op='DELETE' then old else new end;
end
$$;

create or replace function public.archive_orders_older_than_7d()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare v_count integer:=0;
begin
  insert into public.order_history_archive(
    id,public_order_code,created_at,customer_name,customer_whatsapp,service_mode,table_number,items,item_count,total_amount,customer_note,
    paid_amount,payment_difference,producer_note,archived_at,payment_method,payment_status,order_status,payment_proof_url,client_order_id,
    payment_submitted_at,verified_at,verified_by,kitchen_sent_at,updated_at,kds_received_at,preparing_at,ready_at,completed_at,
    kitchen_print_count,kitchen_last_printed_at,payment_proof_sha256,proof_check_status,proof_merchant_match,proof_amount_match,proof_date_match,
    proof_time_match,proof_amount_detected,proof_date_detected,proof_time_detected,proof_checked_at,order_source,cashier_actor,cash_received,
    change_amount,events,request_id,proof_ocr_text,verified_by_email,tenant_id
  )
  select
    o.id,o.public_order_code,o.created_at,o.customer_name,o.customer_whatsapp,o.service_mode,o.table_number,o.items,o.item_count,o.total_amount,o.customer_note,
    o.paid_amount,o.payment_difference,o.producer_note,now(),o.payment_method,o.payment_status,o.order_status,o.payment_proof_url,o.client_order_id,
    o.payment_submitted_at,o.verified_at,o.verified_by,o.kitchen_sent_at,o.updated_at,o.kds_received_at,o.preparing_at,o.ready_at,o.completed_at,
    o.kitchen_print_count,o.kitchen_last_printed_at,o.payment_proof_sha256,o.proof_check_status,o.proof_merchant_match,o.proof_amount_match,o.proof_date_match,
    o.proof_time_match,o.proof_amount_detected,o.proof_date_detected,o.proof_time_detected,o.proof_checked_at,o.order_source,o.cashier_actor,o.cash_received,
    o.change_amount,
    coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at) from public.order_events e where e.order_id=o.id and e.tenant_id=o.tenant_id),'[]'::jsonb),
    o.request_id,o.proof_ocr_text,o.verified_by_email::text,o.tenant_id
  from public.orders o
  where o.created_at<now()-interval '7 days'
    and lower(coalesce(o.order_status,'')) in ('completed','cancelled','canceled','rejected','payment_rejected')
  on conflict(id) do update set
    customer_name=excluded.customer_name,
    customer_whatsapp=excluded.customer_whatsapp,
    service_mode=excluded.service_mode,
    table_number=excluded.table_number,
    items=excluded.items,
    item_count=excluded.item_count,
    total_amount=excluded.total_amount,
    customer_note=excluded.customer_note,
    paid_amount=excluded.paid_amount,
    payment_difference=excluded.payment_difference,
    producer_note=excluded.producer_note,
    archived_at=excluded.archived_at,
    payment_method=excluded.payment_method,
    payment_status=excluded.payment_status,
    order_status=excluded.order_status,
    payment_proof_url=excluded.payment_proof_url,
    client_order_id=excluded.client_order_id,
    payment_submitted_at=excluded.payment_submitted_at,
    verified_at=excluded.verified_at,
    verified_by=excluded.verified_by,
    kitchen_sent_at=excluded.kitchen_sent_at,
    updated_at=excluded.updated_at,
    kds_received_at=excluded.kds_received_at,
    preparing_at=excluded.preparing_at,
    ready_at=excluded.ready_at,
    completed_at=excluded.completed_at,
    kitchen_print_count=excluded.kitchen_print_count,
    kitchen_last_printed_at=excluded.kitchen_last_printed_at,
    payment_proof_sha256=excluded.payment_proof_sha256,
    proof_check_status=excluded.proof_check_status,
    proof_merchant_match=excluded.proof_merchant_match,
    proof_amount_match=excluded.proof_amount_match,
    proof_date_match=excluded.proof_date_match,
    proof_time_match=excluded.proof_time_match,
    proof_amount_detected=excluded.proof_amount_detected,
    proof_date_detected=excluded.proof_date_detected,
    proof_time_detected=excluded.proof_time_detected,
    proof_checked_at=excluded.proof_checked_at,
    order_source=excluded.order_source,
    cashier_actor=excluded.cashier_actor,
    cash_received=excluded.cash_received,
    change_amount=excluded.change_amount,
    events=excluded.events,
    request_id=excluded.request_id,
    proof_ocr_text=excluded.proof_ocr_text,
    verified_by_email=excluded.verified_by_email,
    tenant_id=excluded.tenant_id;

  with doomed as (
    select o.id,o.tenant_id
    from public.orders o
    join public.order_history_archive a on a.id=o.id and a.tenant_id=o.tenant_id
    where o.created_at<now()-interval '7 days'
      and lower(coalesce(o.order_status,'')) in ('completed','cancelled','canceled','rejected','payment_rejected')
  )
  delete from public.order_events e using doomed d
   where e.order_id=d.id and e.tenant_id=d.tenant_id;

  with doomed as (
    select o.id,o.tenant_id
    from public.orders o
    join public.order_history_archive a on a.id=o.id and a.tenant_id=o.tenant_id
    where o.created_at<now()-interval '7 days'
      and lower(coalesce(o.order_status,'')) in ('completed','cancelled','canceled','rejected','payment_rejected')
  )
  delete from public.orders o using doomed d
   where o.id=d.id and o.tenant_id=d.tenant_id;
  get diagnostics v_count=row_count;
  return v_count;
end
$$;

create or replace function private.sheet_sync_expected_rows_tenant(p_tenant_id uuid,p_year integer)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
with bounds as (
  select make_timestamptz(p_year,1,1,0,0,0,'Asia/Jakarta') s,
         make_timestamptz(p_year+1,1,1,0,0,0,'Asia/Jakarta') e
), ids as (
  select o.id from public.orders o,bounds b
   where o.tenant_id=p_tenant_id and o.created_at>=b.s and o.created_at<b.e
  union
  select a.id from public.order_history_archive a,bounds b
   where a.tenant_id=p_tenant_id and a.created_at>=b.s and a.created_at<b.e
), c as (select count(*)::integer orders_count from ids),
m as (select count(*)::integer menu_count from public.menu_items where tenant_id=p_tenant_id)
select jsonb_build_object(
  'PEMESAN',c.orders_count,'PESANAN',c.orders_count,
  'MENU & STOK',m.menu_count,'KEUANGAN',c.orders_count
) from c,m
$$;
revoke all on function private.sheet_sync_expected_rows_tenant(uuid,integer) from public,anon,authenticated;
grant execute on function private.sheet_sync_expected_rows_tenant(uuid,integer) to service_role;

create or replace function private.sheet_sync_source_max_updated_at_tenant(p_tenant_id uuid,p_year integer)
returns timestamptz
language sql
stable
security definer
set search_path=''
as $$
with bounds as (
  select make_timestamptz(p_year,1,1,0,0,0,'Asia/Jakarta') s,
         make_timestamptz(p_year+1,1,1,0,0,0,'Asia/Jakarta') e
), x as (
  select max(o.updated_at) t from public.orders o,bounds b
   where o.tenant_id=p_tenant_id and o.created_at>=b.s and o.created_at<b.e
  union all
  select max(coalesce(a.updated_at,a.archived_at)) from public.order_history_archive a,bounds b
   where a.tenant_id=p_tenant_id and a.created_at>=b.s and a.created_at<b.e
  union all
  select max(m.updated_at) from public.menu_items m where m.tenant_id=p_tenant_id
)
select max(t) from x
$$;
revoke all on function private.sheet_sync_source_max_updated_at_tenant(uuid,integer) from public,anon,authenticated;
grant execute on function private.sheet_sync_source_max_updated_at_tenant(uuid,integer) to service_role;
