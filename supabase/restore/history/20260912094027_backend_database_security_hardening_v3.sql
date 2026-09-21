-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912094027  Name: backend_database_security_hardening_v3
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

-- 1) Additive audit identity fields. Existing contracts remain valid.
alter table public.orders
  add column if not exists verified_by_email extensions.citext;

alter table public.order_events
  add column if not exists actor_email extensions.citext,
  add column if not exists actor_role text,
  add column if not exists source_app text,
  add column if not exists request_id uuid;

alter table public.order_events
  drop constraint if exists order_events_actor_role_check;
alter table public.order_events
  add constraint order_events_actor_role_check
  check (actor_role is null or actor_role in ('superadmin','admin')) not valid;
alter table public.order_events validate constraint order_events_actor_role_check;

alter table public.order_events
  drop constraint if exists order_events_source_app_check;
alter table public.order_events
  add constraint order_events_source_app_check
  check (source_app is null or source_app in ('public','kds','admin','cashier_admin','cashier_kds','system')) not valid;
alter table public.order_events validate constraint order_events_source_app_check;

create index if not exists order_events_actor_email_created_idx
  on public.order_events(actor_email, created_at desc)
  where actor_email is not null;

-- 2) Resolve custom-password admin identity safely while preserving auth.users UUID when available.
create or replace function private.admin_actor_context(p_token text)
returns table(email extensions.citext, actor_id uuid, role text)
language sql
stable
security definer
set search_path=''
as $fn$
  select au.email,
         u.id as actor_id,
         au.role
  from private.admin_sessions s
  join public.admin_users au on au.email=s.email
  left join auth.users u on lower(u.email)=lower(au.email::text)
  where s.token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex')
    and s.expires_at>now()
    and au.is_active
  limit 1
$fn$;

revoke all on function private.admin_actor_context(text) from public, anon, authenticated;
revoke all on function private.admin_email_from_token(text) from public, anon, authenticated;

-- 3) Defense-in-depth: private tables are RLS-protected even though direct grants are already absent.
do $do$
declare r record;
begin
  for r in
    select quote_ident(n.nspname) as s, quote_ident(c.relname) as t
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='private' and c.relkind in ('r','p')
  loop
    execute format('alter table %s.%s enable row level security',r.s,r.t);
  end loop;
end
$do$;

-- 4) Global immutable identity registry prevents collisions across active + archived orders.
create table if not exists private.order_identity_registry(
  order_id uuid primary key,
  public_order_code text not null unique,
  client_order_id text,
  payment_proof_sha256 text,
  reserved_at timestamptz not null default now()
);
alter table private.order_identity_registry enable row level security;
revoke all on table private.order_identity_registry from public, anon, authenticated;

create unique index if not exists order_identity_registry_client_uidx
  on private.order_identity_registry(client_order_id)
  where client_order_id is not null;
create unique index if not exists order_identity_registry_proof_uidx
  on private.order_identity_registry(payment_proof_sha256)
  where payment_proof_sha256 is not null and payment_proof_sha256<>'';

insert into private.order_identity_registry(order_id,public_order_code,client_order_id,payment_proof_sha256,reserved_at)
select id,public_order_code,client_order_id,nullif(payment_proof_sha256,''),created_at
from public.order_history_archive
on conflict (order_id) do nothing;

insert into private.order_identity_registry(order_id,public_order_code,client_order_id,payment_proof_sha256,reserved_at)
select id,public_order_code,client_order_id,nullif(payment_proof_sha256,''),created_at
from public.orders
on conflict (order_id) do nothing;

create or replace function private.reserve_order_identity()
returns trigger
language plpgsql
security definer
set search_path=''
as $fn$
begin
  insert into private.order_identity_registry(order_id,public_order_code,client_order_id,payment_proof_sha256,reserved_at)
  values(new.id,new.public_order_code,new.client_order_id,nullif(new.payment_proof_sha256,''),coalesce(new.created_at,now()));
  return new;
exception
  when unique_violation then
    raise exception using errcode='23505', message='Identitas pesanan, client order, atau bukti pembayaran sudah pernah digunakan.';
end
$fn$;
revoke all on function private.reserve_order_identity() from public, anon, authenticated;

drop trigger if exists trg_reserve_order_identity on public.orders;
create trigger trg_reserve_order_identity
before insert on public.orders
for each row execute function private.reserve_order_identity();

create or replace function private.prevent_order_identity_mutation()
returns trigger
language plpgsql
set search_path=''
as $fn$
begin
  if new.public_order_code is distinct from old.public_order_code
     or new.client_order_id is distinct from old.client_order_id
     or new.payment_proof_sha256 is distinct from old.payment_proof_sha256 then
    raise exception using errcode='23514', message='Identitas pesanan bersifat immutable setelah pesanan dibuat.';
  end if;
  return new;
end
$fn$;
revoke all on function private.prevent_order_identity_mutation() from public, anon, authenticated;

drop trigger if exists trg_prevent_order_identity_mutation on public.orders;
create trigger trg_prevent_order_identity_mutation
before update of public_order_code,client_order_id,payment_proof_sha256 on public.orders
for each row execute function private.prevent_order_identity_mutation();

-- Increase entropy for all NEW public order codes; old codes remain valid.
alter table public.orders alter column public_order_code
  set default ('RHM-'::text || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)));

-- 5) Canonical state invariants at database level.
alter table public.orders drop constraint if exists orders_payment_order_state_consistency;
alter table public.orders add constraint orders_payment_order_state_consistency check (
  (order_status='awaiting_payment' and payment_status in ('pending','rejected')) or
  (order_status='payment_review' and payment_status='submitted') or
  (order_status in ('confirmed','preparing','ready','completed') and payment_status='verified') or
  (order_status='cancelled' and payment_status in ('pending','submitted','verified','rejected'))
) not valid;
alter table public.orders validate constraint orders_payment_order_state_consistency;

create or replace function private.enforce_order_state_transition()
returns trigger
language plpgsql
set search_path=''
as $fn$
begin
  if new.order_status is not distinct from old.order_status then
    return new;
  end if;

  if not (
    (old.order_status='awaiting_payment' and new.order_status in ('payment_review','cancelled')) or
    (old.order_status='payment_review' and new.order_status in ('confirmed','preparing','awaiting_payment','cancelled')) or
    (old.order_status='confirmed' and new.order_status in ('preparing','ready','cancelled')) or
    (old.order_status='preparing' and new.order_status in ('ready','completed','cancelled')) or
    (old.order_status='ready' and new.order_status in ('completed','cancelled')) or
    (old.order_status='completed' and new.order_status='ready')
  ) then
    raise exception using errcode='23514', message=format('Transisi status pesanan tidak diizinkan: %s -> %s',old.order_status,new.order_status);
  end if;
  return new;
end
$fn$;
revoke all on function private.enforce_order_state_transition() from public, anon, authenticated;

drop trigger if exists trg_enforce_order_state_transition on public.orders;
create trigger trg_enforce_order_state_transition
before update of order_status,payment_status on public.orders
for each row execute function private.enforce_order_state_transition();

-- 6) Atomic initial audit event: order + first event are committed or rolled back together.
create unique index if not exists order_events_initial_once_uidx
  on public.order_events(order_id,event_type)
  where event_type in ('payment_submitted','cashier_order_created');

create or replace function private.record_initial_order_event()
returns trigger
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_actor_id uuid;
  v_actor_role text;
  v_actor_email extensions.citext;
begin
  if new.order_source in ('cashier_admin','cashier_kds') then
    v_actor_email:=nullif(new.cashier_actor,'')::extensions.citext;
    select u.id into v_actor_id from auth.users u where lower(u.email)=lower(v_actor_email::text) limit 1;
    select au.role into v_actor_role from public.admin_users au where au.email=v_actor_email limit 1;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app)
    values(new.id,'cashier_order_created',null,new.order_status,
      case when new.payment_method='cash' then 'Pesanan kasir dibuat dan dibayar tunai.' else 'Pesanan kasir dibuat dan dibayar QRIS.' end,
      v_actor_id,v_actor_email,v_actor_role,new.order_source)
    on conflict do nothing;
  elsif new.order_source='public' and new.payment_status='submitted' and new.order_status='payment_review' then
    insert into public.order_events(order_id,event_type,from_status,to_status,note,source_app)
    values(new.id,'payment_submitted','awaiting_payment','payment_review',
      case when new.proof_check_status='matched'
        then 'Bukti pembayaran lolos pemeriksaan awal otomatis dan menunggu verifikasi KDS.'
        else 'Bukti pembayaran diterima dan memerlukan pemeriksaan petugas KDS.' end,
      'public')
    on conflict do nothing;
  end if;
  return new;
end
$fn$;
revoke all on function private.record_initial_order_event() from public, anon, authenticated;

drop trigger if exists trg_record_initial_order_event on public.orders;
create trigger trg_record_initial_order_event
after insert on public.orders
for each row execute function private.record_initial_order_event();

-- 7) Fix KDS rejection bug, add row lock, and always record actor identity.
create or replace function internal_rpc.kds_update_order(p_token text,p_id uuid,p_action text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_email extensions.citext;
  v_actor_id uuid;
  v_role text;
  v_old public.orders%rowtype;
  v_row public.orders%rowtype;
  v_now timestamptz:=now();
  v_to text;
  v_event text;
  v_note text;
begin
  select a.email,a.actor_id,a.role into v_email,v_actor_id,v_role from private.admin_actor_context(p_token) a;
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  select * into v_old from public.orders where id=p_id for update;
  if v_old.id is null then return jsonb_build_object('ok',false,'error','order_not_found'); end if;

  if p_action='verify_start' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_payment_state'); end if;
    update public.orders set payment_status='verified',order_status='preparing',verified_at=coalesce(verified_at,v_now),verified_by=v_actor_id,verified_by_email=v_email,kitchen_sent_at=coalesce(kitchen_sent_at,v_now),kds_received_at=coalesce(kds_received_at,v_now),preparing_at=coalesce(preparing_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app)
    values(p_id,'payment_verified_and_kds_started',v_old.order_status,'preparing','Pembayaran diverifikasi dan pesanan langsung masuk tahap Sedang Diproses.',v_actor_id,v_email,v_role,'kds');
    return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
  elsif p_action='verify_payment' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_payment_state'); end if;
    update public.orders set payment_status='verified',order_status='confirmed',verified_at=coalesce(verified_at,v_now),verified_by=v_actor_id,verified_by_email=v_email,kitchen_sent_at=coalesce(kitchen_sent_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app)
    values(p_id,'payment_verified_kds',v_old.order_status,'confirmed','Pembayaran diverifikasi oleh petugas KDS.',v_actor_id,v_email,v_role,'kds');
    return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
  elsif p_action='reject_payment' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_payment_state'); end if;
    update public.orders set payment_status='rejected',order_status='awaiting_payment',verified_at=null,verified_by=null,verified_by_email=null,kitchen_sent_at=null,updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app)
    values(p_id,'payment_rejected_kds',v_old.order_status,'awaiting_payment','Bukti pembayaran ditolak oleh petugas KDS untuk diperiksa atau diulang.',v_actor_id,v_email,v_role,'kds');
    return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
  end if;

  if v_old.payment_status<>'verified' then return jsonb_build_object('ok',false,'error','payment_not_verified'); end if;

  if p_action='start' then
    if v_old.order_status not in ('confirmed','preparing') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='preparing',kds_received_at=coalesce(kds_received_at,v_now),preparing_at=coalesce(preparing_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    v_to:='preparing';v_event:='kds_preparing';v_note:='Pesanan diterima dapur dan mulai diproses.';
  elsif p_action='finish' then
    if v_old.order_status not in ('preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='completed',kds_received_at=coalesce(kds_received_at,v_now),preparing_at=coalesce(preparing_at,v_now),completed_at=coalesce(completed_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    v_to:='completed';v_event:='kds_completed';v_note:='Pesanan selesai dari alur KDS tiga tahap.';
  elsif p_action='ready' then
    if v_old.order_status not in ('confirmed','preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='ready',kds_received_at=coalesce(kds_received_at,v_now),preparing_at=coalesce(preparing_at,v_now),ready_at=coalesce(ready_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    v_to:='ready';v_event:='kds_ready';v_note:='Pesanan siap disajikan atau diserahkan.';
  elsif p_action='complete' then
    if v_old.order_status not in ('ready','completed') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='completed',completed_at=coalesce(completed_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    v_to:='completed';v_event:='kds_completed';v_note:='Pesanan selesai.';
  elsif p_action='reopen' then
    if v_old.order_status<>'completed' then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='ready',completed_at=null,updated_at=v_now where id=p_id returning * into v_row;
    v_to:='ready';v_event:='kds_reopened';v_note:='Pesanan dibuka kembali ke status siap disajikan.';
  elsif p_action='print' then
    update public.orders set kitchen_print_count=kitchen_print_count+1,kitchen_last_printed_at=v_now,kds_received_at=coalesce(kds_received_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    v_to:=v_old.order_status;v_event:='kitchen_ticket_printed';v_note:='Kitchen ticket dicetak.';
  else
    return jsonb_build_object('ok',false,'error','invalid_action');
  end if;

  insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app)
  values(p_id,v_event,v_old.order_status,v_to,v_note,v_actor_id,v_email,v_role,'kds');
  return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
end
$fn$;

-- 8) Harden legacy KDS action contract without changing its signature.
create or replace function public.kds_console_order_action(p_token text,p_id uuid,p_action text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_email extensions.citext;
  v_actor_id uuid;
  v_role text;
  v_old public.orders%rowtype;
  v_row public.orders%rowtype;
  v_now timestamptz:=now();
begin
  select a.email,a.actor_id,a.role into v_email,v_actor_id,v_role from private.admin_actor_context(p_token) a;
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select * into v_old from public.orders where id=p_id for update;
  if v_old.id is null then return jsonb_build_object('ok',false,'error','order_not_found'); end if;

  if p_action='verify' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set payment_status='verified',order_status='confirmed',verified_at=coalesce(verified_at,v_now),verified_by=v_actor_id,verified_by_email=v_email,kitchen_sent_at=coalesce(kitchen_sent_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app)
    values(p_id,'payment_verified_kds',v_old.order_status,'confirmed','Pembayaran diverifikasi oleh petugas KDS dan pesanan diteruskan ke dapur.',v_actor_id,v_email,v_role,'kds');
    return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
  elsif p_action='reject' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set payment_status='rejected',order_status='awaiting_payment',verified_at=null,verified_by=null,verified_by_email=null,kitchen_sent_at=null,updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app)
    values(p_id,'payment_rejected_kds',v_old.order_status,'awaiting_payment','Bukti pembayaran ditolak oleh petugas KDS untuk diperiksa atau diulang.',v_actor_id,v_email,v_role,'kds');
    return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
  end if;

  if v_old.payment_status<>'verified' then return jsonb_build_object('ok',false,'error','payment_not_verified'); end if;
  if p_action='start' then
    if v_old.order_status not in ('confirmed','preparing') then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set order_status='preparing',preparing_at=coalesce(preparing_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app) values(p_id,'kitchen_started',v_old.order_status,'preparing','Pesanan mulai diproses di dapur.',v_actor_id,v_email,v_role,'kds');
  elsif p_action='ready' then
    if v_old.order_status not in ('confirmed','preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set order_status='ready',ready_at=coalesce(ready_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app) values(p_id,'kitchen_ready',v_old.order_status,'ready','Pesanan siap disajikan.',v_actor_id,v_email,v_role,'kds');
  elsif p_action='complete' then
    if v_old.order_status not in ('ready','completed') then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set order_status='completed',completed_at=coalesce(completed_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app) values(p_id,'kitchen_completed',v_old.order_status,'completed','Pesanan selesai disajikan.',v_actor_id,v_email,v_role,'kds');
  elsif p_action='print' then
    update public.orders set kitchen_print_count=coalesce(kitchen_print_count,0)+1,kitchen_last_printed_at=v_now,updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app) values(p_id,'kitchen_printed',v_old.order_status,v_old.order_status,'Kitchen ticket dicetak.',v_actor_id,v_email,v_role,'kds');
  else
    return jsonb_build_object('ok',false,'error','invalid_action');
  end if;
  return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
end
$fn$;

-- 9) Smart cashier remains same external RPC, but audit identity is persisted and initial event is now atomic via trigger.
create or replace function public.smart_cashier_create(p_token text,p_source text,p_customer_name text,p_service_mode text,p_table_number smallint,p_items jsonb,p_payment_method text,p_cash_received integer default null,p_note text default '')
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_email extensions.citext;
  v_actor_id uuid;
  v_role text;
  v_req jsonb;
  v_menu public.menu_items%rowtype;
  v_qty integer;
  v_total integer:=0;
  v_count integer:=0;
  v_items jsonb:='[]'::jsonb;
  v_order public.orders%rowtype;
  v_name text;
  v_change integer:=0;
  v_now timestamptz:=now();
begin
  select a.email,a.actor_id,a.role into v_email,v_actor_id,v_role from private.admin_actor_context(p_token) a;
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_source not in ('cashier_admin','cashier_kds') then return jsonb_build_object('ok',false,'error','invalid_source'); end if;
  if p_service_mode not in ('dine-in','take-away') then return jsonb_build_object('ok',false,'error','invalid_service_mode'); end if;
  if p_service_mode='dine-in' and (p_table_number is null or p_table_number<1 or p_table_number>20) then return jsonb_build_object('ok',false,'error','invalid_table'); end if;
  if p_service_mode='take-away' then p_table_number:=null; end if;
  if p_payment_method not in ('cash','qris_cashier') then return jsonb_build_object('ok',false,'error','invalid_payment_method'); end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then return jsonb_build_object('ok',false,'error','empty_cart'); end if;

  for v_req in select value from jsonb_array_elements(p_items)
  loop
    v_qty:=greatest(0,least(50,coalesce((v_req->>'quantity')::integer,0)));
    if v_qty<1 then return jsonb_build_object('ok',false,'error','invalid_quantity'); end if;
    select * into v_menu from public.menu_items where id=(v_req->>'menuId') and is_visible and is_available;
    if v_menu.id is null then return jsonb_build_object('ok',false,'error','menu_unavailable','menuId',v_req->>'menuId'); end if;
    v_total:=v_total+(v_menu.price*v_qty);v_count:=v_count+v_qty;
    if v_count>200 or v_total>100000000 then return jsonb_build_object('ok',false,'error','order_limit_exceeded'); end if;
    v_items:=v_items||jsonb_build_array(jsonb_build_object('menuId',v_menu.id,'name',v_menu.name,'price',v_menu.price,'quantity',v_qty,'subtotal',v_menu.price*v_qty));
  end loop;

  if p_payment_method='cash' then
    if p_cash_received is null or p_cash_received<v_total then return jsonb_build_object('ok',false,'error','insufficient_cash','total',v_total); end if;
    v_change:=p_cash_received-v_total;
  else
    p_cash_received:=null;v_change:=0;
  end if;

  v_name:=left(coalesce(nullif(trim(p_customer_name),''),'Pelanggan Kasir'),60);
  if char_length(v_name)<2 then v_name:='Pelanggan Kasir'; end if;

  insert into public.orders(service_mode,table_number,customer_name,items,item_count,total_amount,payment_method,payment_status,order_status,payment_submitted_at,verified_at,verified_by,verified_by_email,kitchen_sent_at,customer_note,client_order_id,paid_amount,payment_difference,producer_note,proof_check_status,order_source,cashier_actor,cash_received,change_amount,created_at,updated_at)
  values(p_service_mode,p_table_number,v_name,v_items,v_count,v_total,p_payment_method,'verified','confirmed',v_now,v_now,v_actor_id,v_email,v_now,left(trim(coalesce(p_note,'')),500),'cashier-'||replace(gen_random_uuid()::text,'-',''),v_total,0,case when p_payment_method='cash' then 'Pembayaran CASH dikonfirmasi oleh kasir.' else 'Pembayaran QRIS kasir dikonfirmasi oleh petugas.' end,'cashier_confirmed',p_source,v_email::text,p_cash_received,v_change,v_now,v_now)
  returning * into v_order;

  return jsonb_build_object('ok',true,'order',to_jsonb(v_order),'change_amount',v_change);
exception when others then
  return jsonb_build_object('ok',false,'error','cashier_create_failed','detail',sqlerrm);
end
$fn$;

-- 10) Prepare a least-privilege public settings contract without breaking the existing frontend yet.
create or replace view public.site_settings_public_v1
with (security_invoker=true)
as
select id,business_name,merchant_name,qris_enabled,qris_image_url,public_url,require_table_qr_signature
from public.site_settings;

grant select on public.site_settings_public_v1 to anon,authenticated;
revoke insert,update,delete,truncate,references,trigger on public.site_settings_public_v1 from anon,authenticated;

