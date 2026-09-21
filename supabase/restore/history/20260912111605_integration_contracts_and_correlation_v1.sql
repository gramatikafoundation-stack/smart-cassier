-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912111605  Name: integration_contracts_and_correlation_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.orders add column if not exists request_id uuid;
update public.orders set request_id=gen_random_uuid() where request_id is null;
alter table public.orders alter column request_id set default gen_random_uuid();
alter table public.orders alter column request_id set not null;
create index if not exists orders_request_id_idx on public.orders(request_id);

alter table public.order_history_archive add column if not exists request_id uuid;
update public.order_history_archive a
set request_id=coalesce(
  (select (e->>'request_id')::uuid from jsonb_array_elements(a.events) e where coalesce(e->>'request_id','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' limit 1),
  gen_random_uuid()
)
where request_id is null;
alter table public.order_history_archive alter column request_id set default gen_random_uuid();
alter table public.order_history_archive alter column request_id set not null;
create index if not exists order_history_archive_request_id_idx on public.order_history_archive(request_id);

alter table public.sheet_sync_outbox add column if not exists request_id uuid;
update public.sheet_sync_outbox set request_id=gen_random_uuid() where request_id is null;
alter table public.sheet_sync_outbox alter column request_id set default gen_random_uuid();
alter table public.sheet_sync_outbox alter column request_id set not null;
create index if not exists sheet_sync_outbox_request_id_idx on public.sheet_sync_outbox(request_id);
create index if not exists order_events_request_id_idx on public.order_events(request_id) where request_id is not null;

create table if not exists private.integration_registry(
  service_key text primary key check(service_key ~ '^[a-z0-9_]{3,64}$'),
  display_name text not null,
  service_type text not null check(service_type in ('frontend','edge_function','external','database','worker')),
  canonical_url text not null,
  contract_version text not null,
  critical boolean not null default true,
  auth_mode text not null default 'internal',
  dependencies text[] not null default '{}',
  enabled boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table private.integration_registry enable row level security;
drop policy if exists deny_client_all on private.integration_registry;
create policy deny_client_all on private.integration_registry as restrictive for all to anon, authenticated using(false) with check(false);
revoke all on private.integration_registry from public, anon, authenticated;

insert into private.integration_registry(service_key,display_name,service_type,canonical_url,contract_version,critical,auth_mode,dependencies,metadata)
values
('public_web','Public Ordering','frontend','https://rohmat-pesan-bayar-publik.vercel.app','public-v21',true,'publishable',array['order_gateway'],jsonb_build_object('source_of_truth',false)),
('admin_web','Admin Studio','frontend','https://studio-pengelola-rohmat.vercel.app','admin-v28',true,'custom_session',array['postgres_core'],jsonb_build_object('source_of_truth',false)),
('kds_web','Kitchen Display','frontend','https://rohmat-kds-printer.vercel.app','kds-static',true,'custom_session',array['kds_api','postgres_core'],jsonb_build_object('source_of_truth',false)),
('order_gateway','Order Gateway','edge_function','http://127.0.0.1:54321/functions/v1/create-order','order-gateway-v8',true,'publishable_origin_bound',array['postgres_core'],jsonb_build_object('idempotent',true)),
('kds_api','KDS API','edge_function','http://127.0.0.1:54321/functions/v1/rohmat-kds-api','kds-api-v4',true,'fingerprint_session',array['postgres_core'],jsonb_build_object('bff_ready',true)),
('smart_cashier','Smart Cashier','edge_function','http://127.0.0.1:54321/functions/v1/rohmat-smart-cashier-v1','smart-cashier-v4',true,'fingerprint_session',array['postgres_core'],jsonb_build_object('idempotency_scope','database_order_identity')),
('sheet_worker','Sheets Sync Worker','worker','http://127.0.0.1:54321/functions/v1/rohmat-sheet-sync-worker-v1','sheet-worker-v4',true,'cron_token',array['postgres_core','sheet_writer'],jsonb_build_object('outbox',true)),
('sheet_writer','Google Sheets Writer','external',(select writer_url from public.sheet_sync_config where id=1),'apps-script-writer-v2',true,'writer_token',array[]::text[],jsonb_build_object('authoritative',false)),
('postgres_core','Supabase PostgreSQL','database','postgres://supabase-managed','schema-contract-v1',true,'server_only',array[]::text[],jsonb_build_object('source_of_truth',true))
on conflict(service_key) do update set
 display_name=excluded.display_name,service_type=excluded.service_type,canonical_url=excluded.canonical_url,
 contract_version=excluded.contract_version,critical=excluded.critical,auth_mode=excluded.auth_mode,
 dependencies=excluded.dependencies,enabled=true,metadata=excluded.metadata,updated_at=now();

create table if not exists private.integration_events(
  id bigint generated always as identity primary key,
  request_id uuid not null,
  service_key text not null references private.integration_registry(service_key),
  operation text not null,
  direction text not null check(direction in ('inbound','outbound','internal')),
  outcome text not null check(outcome in ('success','rejected','failed','started')),
  http_status integer,
  latency_ms integer check(latency_ms is null or latency_ms>=0),
  entity_type text,
  entity_id text,
  error_code text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table private.integration_events enable row level security;
drop policy if exists deny_client_all on private.integration_events;
create policy deny_client_all on private.integration_events as restrictive for all to anon, authenticated using(false) with check(false);
revoke all on private.integration_events from public, anon, authenticated;
create index if not exists integration_events_request_idx on private.integration_events(request_id,created_at desc);
create index if not exists integration_events_service_created_idx on private.integration_events(service_key,created_at desc);

create or replace function public.integration_record_event(
  p_request_id uuid,
  p_service_key text,
  p_operation text,
  p_direction text,
  p_outcome text,
  p_http_status integer default null,
  p_latency_ms integer default null,
  p_entity_type text default null,
  p_entity_id text default null,
  p_error_code text default null,
  p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path=''
as $function$
declare v_id bigint;
begin
  if p_request_id is null then raise exception 'request_id_required'; end if;
  if not exists(select 1 from private.integration_registry where service_key=p_service_key and enabled) then raise exception 'unknown_service_key'; end if;
  insert into private.integration_events(request_id,service_key,operation,direction,outcome,http_status,latency_ms,entity_type,entity_id,error_code,metadata)
  values(p_request_id,p_service_key,left(coalesce(p_operation,''),100),p_direction,p_outcome,p_http_status,p_latency_ms,left(p_entity_type,50),left(p_entity_id,160),left(p_error_code,100),coalesce(p_metadata,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end
$function$;
revoke all on function public.integration_record_event(uuid,text,text,text,text,integer,integer,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.integration_record_event(uuid,text,text,text,text,integer,integer,text,text,text,jsonb) to service_role;

create or replace function private.integration_contract_status() returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_public text; v_admin text; v_kds text; v_writer text;
  v_registry_ok boolean; v_routes_ok boolean; v_cron_worker boolean; v_health_cron boolean;
  v_corr_orders boolean; v_corr_outbox boolean; v_corr_events boolean;
  v_critical_count integer; v_expected integer:=9;
begin
  select public_url,admin_url,kds_url into v_public,v_admin,v_kds from public.site_settings where id=1;
  select writer_url into v_writer from public.sheet_sync_config where id=1;
  select count(*) into v_critical_count from private.integration_registry where critical and enabled and canonical_url<>'' and contract_version<>'';
  v_registry_ok := v_critical_count=v_expected;
  v_routes_ok :=
    exists(select 1 from private.integration_registry where service_key='public_web' and rtrim(canonical_url,'/')=rtrim(v_public,'/')) and
    exists(select 1 from private.integration_registry where service_key='admin_web' and rtrim(canonical_url,'/')=rtrim(v_admin,'/')) and
    exists(select 1 from private.integration_registry where service_key='kds_web' and rtrim(canonical_url,'/')=rtrim(v_kds,'/')) and
    exists(select 1 from private.integration_registry where service_key='sheet_writer' and canonical_url=v_writer);
  select exists(select 1 from cron.job where jobname='rohmat_sheet_sync_worker' and active) into v_cron_worker;
  select exists(select 1 from cron.job where jobname='rohmat_production_health_monitor' and active) into v_health_cron;
  select exists(select 1 from pg_catalog.pg_attribute a join pg_catalog.pg_class c on c.oid=a.attrelid join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='orders' and a.attname='request_id' and not a.attisdropped) into v_corr_orders;
  select exists(select 1 from pg_catalog.pg_attribute a join pg_catalog.pg_class c on c.oid=a.attrelid join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sheet_sync_outbox' and a.attname='request_id' and not a.attisdropped) into v_corr_outbox;
  select exists(select 1 from pg_catalog.pg_attribute a join pg_catalog.pg_class c on c.oid=a.attrelid join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='order_events' and a.attname='request_id' and not a.attisdropped) into v_corr_events;
  return jsonb_build_object(
    'ok',v_registry_ok and v_routes_ok and v_cron_worker and v_health_cron and v_corr_orders and v_corr_outbox and v_corr_events,
    'registry_ok',v_registry_ok,'critical_services',v_critical_count,'expected_services',v_expected,
    'canonical_routes_ok',v_routes_ok,'sheet_worker_cron',v_cron_worker,'health_cron',v_health_cron,
    'orders_request_id',v_corr_orders,'outbox_request_id',v_corr_outbox,'order_events_request_id',v_corr_events
  );
end
$function$;
revoke all on function private.integration_contract_status() from public, anon, authenticated;

create or replace function private.enqueue_sheet_sync_event() returns trigger
language plpgsql security definer set search_path=''
as $function$
declare
  v_row jsonb; v_entity_type text; v_entity_id text; v_operation text; v_target_year integer;
  v_updated_at timestamptz; v_tabs jsonb; v_key text; v_request_id uuid;
begin
  v_row := case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  begin v_request_id:=nullif(v_row->>'request_id','')::uuid; exception when others then v_request_id:=null; end;
  v_request_id:=coalesce(v_request_id,gen_random_uuid());
  if tg_table_name='menu_items' then
    v_entity_type:='menu'; v_entity_id:=coalesce(v_row->>'id','unknown'); v_operation:=tg_op; v_target_year:=null;
    v_updated_at:=coalesce((v_row->>'updated_at')::timestamptz,now()); v_tabs:='["MENU & STOK","DASHBOARD"]'::jsonb;
  elsif tg_table_name='order_history_archive' then
    v_entity_type:='order'; v_entity_id:=coalesce(v_row->>'id','unknown'); v_operation:='ARCHIVE';
    v_target_year:=extract(year from ((v_row->>'created_at')::timestamptz at time zone 'Asia/Jakarta'))::integer;
    v_updated_at:=coalesce((v_row->>'archived_at')::timestamptz,(v_row->>'created_at')::timestamptz,now());
    v_tabs:='["PEMESAN","PESANAN","MENU & STOK","KEUANGAN","DASHBOARD"]'::jsonb;
  else
    v_entity_type:='order'; v_entity_id:=coalesce(v_row->>'id','unknown'); v_operation:=tg_op;
    v_target_year:=extract(year from ((v_row->>'created_at')::timestamptz at time zone 'Asia/Jakarta'))::integer;
    v_updated_at:=coalesce((v_row->>'updated_at')::timestamptz,(v_row->>'created_at')::timestamptz,now());
    v_tabs:='["PEMESAN","PESANAN","MENU & STOK","KEUANGAN","DASHBOARD"]'::jsonb;
  end if;
  v_key:=tg_table_name||':'||v_entity_id||':'||v_operation||':'||md5(v_row::text);
  update public.sheet_sync_outbox set status='superseded',last_error='Superseded by a newer event for the same entity.'
   where entity_type=v_entity_type and entity_id=v_entity_id and target_year is not distinct from v_target_year and status in ('pending','failed');
  insert into public.sheet_sync_outbox(request_id,idempotency_key,entity_type,entity_id,operation,target_year,affected_tabs,payload,source_updated_at)
  values(v_request_id,v_key,v_entity_type,v_entity_id,v_operation,v_target_year,v_tabs,
    jsonb_build_object('request_id',v_request_id,'source_table',tg_table_name,'entity_id',v_entity_id,'operation',v_operation,'target_year',v_target_year,'source_updated_at',v_updated_at,'affected_tabs',v_tabs),v_updated_at)
  on conflict(idempotency_key) do nothing;
  return case when tg_op='DELETE' then old else new end;
end
$function$;

create or replace function private.record_initial_order_event() returns trigger
language plpgsql security definer set search_path=''
as $function$
declare v_actor_id uuid; v_actor_role text; v_actor_email extensions.citext;
begin
  if new.order_source in ('cashier_admin','cashier_kds') then
    v_actor_email:=nullif(new.cashier_actor,'')::extensions.citext;
    select u.id into v_actor_id from auth.users u where lower(u.email)=lower(v_actor_email::text) limit 1;
    select au.role into v_actor_role from public.admin_users au where au.email=v_actor_email limit 1;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id)
    values(new.id,'cashier_order_created',null,new.order_status,case when new.payment_method='cash' then 'Pesanan kasir dibuat dan dibayar tunai.' else 'Pesanan kasir dibuat dan dibayar QRIS.' end,v_actor_id,v_actor_email,v_actor_role,new.order_source,new.request_id)
    on conflict do nothing;
  elsif new.order_source='public' and new.payment_status='submitted' and new.order_status='payment_review' then
    insert into public.order_events(order_id,event_type,from_status,to_status,note,source_app,request_id)
    values(new.id,'payment_submitted','awaiting_payment','payment_review',case when new.proof_check_status='matched' then 'Bukti pembayaran lolos pemeriksaan awal otomatis dan menunggu verifikasi KDS.' else 'Bukti pembayaran diterima dan memerlukan pemeriksaan petugas KDS.' end,'public',new.request_id)
    on conflict do nothing;
  end if;
  return new;
end
$function$;

create or replace function public.smart_cashier_create(p_token text,p_source text,p_customer_name text,p_service_mode text,p_table_number smallint,p_items jsonb,p_payment_method text,p_cash_received integer default null,p_note text default '') returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_email extensions.citext; v_actor_id uuid; v_role text; v_req jsonb; v_menu public.menu_items%rowtype;
  v_qty integer; v_total integer:=0; v_count integer:=0; v_items jsonb:='[]'::jsonb; v_order public.orders%rowtype;
  v_name text; v_change integer:=0; v_now timestamptz:=now(); v_request_id uuid:=gen_random_uuid();
begin
  select a.email,a.actor_id,a.role into v_email,v_actor_id,v_role from private.admin_actor_context(p_token) a;
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_source not in ('cashier_admin','cashier_kds') then return jsonb_build_object('ok',false,'error','invalid_source'); end if;
  if p_service_mode not in ('dine-in','take-away') then return jsonb_build_object('ok',false,'error','invalid_service_mode'); end if;
  if p_service_mode='dine-in' and (p_table_number is null or p_table_number<1 or p_table_number>20) then return jsonb_build_object('ok',false,'error','invalid_table'); end if;
  if p_service_mode='take-away' then p_table_number:=null; end if;
  if p_payment_method not in ('cash','qris_cashier') then return jsonb_build_object('ok',false,'error','invalid_payment_method'); end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then return jsonb_build_object('ok',false,'error','empty_cart'); end if;
  for v_req in select value from jsonb_array_elements(p_items) loop
    v_qty:=greatest(0,least(50,coalesce((v_req->>'quantity')::integer,0)));
    if v_qty<1 then return jsonb_build_object('ok',false,'error','invalid_quantity'); end if;
    select * into v_menu from public.menu_items where id=(v_req->>'menuId') and is_visible and is_available;
    if v_menu.id is null then return jsonb_build_object('ok',false,'error','menu_unavailable','menuId',v_req->>'menuId'); end if;
    v_total:=v_total+(v_menu.price*v_qty); v_count:=v_count+v_qty;
    if v_count>200 or v_total>100000000 then return jsonb_build_object('ok',false,'error','order_limit_exceeded'); end if;
    v_items:=v_items||jsonb_build_array(jsonb_build_object('menuId',v_menu.id,'name',v_menu.name,'price',v_menu.price,'quantity',v_qty,'subtotal',v_menu.price*v_qty));
  end loop;
  if p_payment_method='cash' then
    if p_cash_received is null or p_cash_received<v_total then return jsonb_build_object('ok',false,'error','insufficient_cash','total',v_total); end if;
    v_change:=p_cash_received-v_total;
  else p_cash_received:=null; v_change:=0; end if;
  v_name:=left(coalesce(nullif(trim(p_customer_name),''),'Pelanggan Kasir'),60); if char_length(v_name)<2 then v_name:='Pelanggan Kasir'; end if;
  insert into public.orders(request_id,service_mode,table_number,customer_name,items,item_count,total_amount,payment_method,payment_status,order_status,payment_submitted_at,verified_at,verified_by,verified_by_email,kitchen_sent_at,customer_note,client_order_id,paid_amount,payment_difference,producer_note,proof_check_status,order_source,cashier_actor,cash_received,change_amount,created_at,updated_at)
  values(v_request_id,p_service_mode,p_table_number,v_name,v_items,v_count,v_total,p_payment_method,'verified','confirmed',v_now,v_now,v_actor_id,v_email,v_now,left(trim(coalesce(p_note,'')),500),'cashier-'||replace(gen_random_uuid()::text,'-',''),v_total,0,case when p_payment_method='cash' then 'Pembayaran CASH dikonfirmasi oleh kasir.' else 'Pembayaran QRIS kasir dikonfirmasi oleh petugas.' end,'cashier_confirmed',p_source,v_email::text,p_cash_received,v_change,v_now,v_now)
  returning * into v_order;
  return jsonb_build_object('ok',true,'request_id',v_request_id,'order',to_jsonb(v_order),'change_amount',v_change);
exception when others then return jsonb_build_object('ok',false,'error','cashier_create_failed','detail',sqlerrm);
end
$function$;

create or replace function internal_rpc.kds_update_order(p_token text,p_id uuid,p_action text) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_email extensions.citext; v_actor_id uuid; v_role text; v_old public.orders%rowtype; v_row public.orders%rowtype;
  v_now timestamptz:=now(); v_to text; v_event text; v_note text;
begin
  select a.email,a.actor_id,a.role into v_email,v_actor_id,v_role from private.admin_actor_context(p_token) a;
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select * into v_old from public.orders where id=p_id for update;
  if v_old.id is null then return jsonb_build_object('ok',false,'error','order_not_found'); end if;
  if p_action='verify_start' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_payment_state'); end if;
    update public.orders set payment_status='verified',order_status='preparing',verified_at=coalesce(verified_at,v_now),verified_by=v_actor_id,verified_by_email=v_email,kitchen_sent_at=coalesce(kitchen_sent_at,v_now),kds_received_at=coalesce(kds_received_at,v_now),preparing_at=coalesce(preparing_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id) values(p_id,'payment_verified_and_kds_started',v_old.order_status,'preparing','Pembayaran diverifikasi dan pesanan langsung masuk tahap Sedang Diproses.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
    return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row));
  elsif p_action='verify_payment' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_payment_state'); end if;
    update public.orders set payment_status='verified',order_status='confirmed',verified_at=coalesce(verified_at,v_now),verified_by=v_actor_id,verified_by_email=v_email,kitchen_sent_at=coalesce(kitchen_sent_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id) values(p_id,'payment_verified_kds',v_old.order_status,'confirmed','Pembayaran diverifikasi oleh petugas KDS.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
    return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row));
  elsif p_action='reject_payment' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_payment_state'); end if;
    update public.orders set payment_status='rejected',order_status='awaiting_payment',verified_at=null,verified_by=null,verified_by_email=null,kitchen_sent_at=null,updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id) values(p_id,'payment_rejected_kds',v_old.order_status,'awaiting_payment','Bukti pembayaran ditolak oleh petugas KDS untuk diperiksa atau diulang.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
    return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row));
  end if;
  if v_old.payment_status<>'verified' then return jsonb_build_object('ok',false,'error','payment_not_verified'); end if;
  if p_action='start' then
    if v_old.order_status not in ('confirmed','preparing') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='preparing',kds_received_at=coalesce(kds_received_at,v_now),preparing_at=coalesce(preparing_at,v_now),updated_at=v_now where id=p_id returning * into v_row; v_to:='preparing';v_event:='kds_preparing';v_note:='Pesanan diterima dapur dan mulai diproses.';
  elsif p_action='finish' then
    if v_old.order_status not in ('preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='completed',kds_received_at=coalesce(kds_received_at,v_now),preparing_at=coalesce(preparing_at,v_now),completed_at=coalesce(completed_at,v_now),updated_at=v_now where id=p_id returning * into v_row; v_to:='completed';v_event:='kds_completed';v_note:='Pesanan selesai dari alur KDS tiga tahap.';
  elsif p_action='ready' then
    if v_old.order_status not in ('confirmed','preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='ready',kds_received_at=coalesce(kds_received_at,v_now),preparing_at=coalesce(preparing_at,v_now),ready_at=coalesce(ready_at,v_now),updated_at=v_now where id=p_id returning * into v_row; v_to:='ready';v_event:='kds_ready';v_note:='Pesanan siap disajikan atau diserahkan.';
  elsif p_action='complete' then
    if v_old.order_status not in ('ready','completed') then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='completed',completed_at=coalesce(completed_at,v_now),updated_at=v_now where id=p_id returning * into v_row; v_to:='completed';v_event:='kds_completed';v_note:='Pesanan selesai.';
  elsif p_action='reopen' then
    if v_old.order_status<>'completed' then return jsonb_build_object('ok',false,'error','invalid_transition'); end if;
    update public.orders set order_status='ready',completed_at=null,updated_at=v_now where id=p_id returning * into v_row; v_to:='ready';v_event:='kds_reopened';v_note:='Pesanan dibuka kembali ke status siap disajikan.';
  elsif p_action='print' then
    update public.orders set kitchen_print_count=kitchen_print_count+1,kitchen_last_printed_at=v_now,kds_received_at=coalesce(kds_received_at,v_now),updated_at=v_now where id=p_id returning * into v_row; v_to:=v_old.order_status;v_event:='kitchen_ticket_printed';v_note:='Kitchen ticket dicetak.';
  else return jsonb_build_object('ok',false,'error','invalid_action'); end if;
  insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id) values(p_id,v_event,v_old.order_status,v_to,v_note,v_actor_id,v_email,v_role,'kds',v_old.request_id);
  return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row));
end
$function$;

create or replace function public.kds_console_order_action(p_token text,p_id uuid,p_action text) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare v_email extensions.citext; v_actor_id uuid; v_role text; v_old public.orders%rowtype; v_row public.orders%rowtype; v_now timestamptz:=now();
begin
  select a.email,a.actor_id,a.role into v_email,v_actor_id,v_role from private.admin_actor_context(p_token) a;
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select * into v_old from public.orders where id=p_id for update;
  if v_old.id is null then return jsonb_build_object('ok',false,'error','order_not_found'); end if;
  if p_action='verify' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set payment_status='verified',order_status='confirmed',verified_at=coalesce(verified_at,v_now),verified_by=v_actor_id,verified_by_email=v_email,kitchen_sent_at=coalesce(kitchen_sent_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id) values(p_id,'payment_verified_kds',v_old.order_status,'confirmed','Pembayaran diverifikasi oleh petugas KDS dan pesanan diteruskan ke dapur.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
    return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row));
  elsif p_action='reject' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set payment_status='rejected',order_status='awaiting_payment',verified_at=null,verified_by=null,verified_by_email=null,kitchen_sent_at=null,updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id) values(p_id,'payment_rejected_kds',v_old.order_status,'awaiting_payment','Bukti pembayaran ditolak oleh petugas KDS untuk diperiksa atau diulang.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
    return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row));
  end if;
  if v_old.payment_status<>'verified' then return jsonb_build_object('ok',false,'error','payment_not_verified'); end if;
  if p_action='start' then
    if v_old.order_status not in ('confirmed','preparing') then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set order_status='preparing',preparing_at=coalesce(preparing_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id) values(p_id,'kitchen_started',v_old.order_status,'preparing','Pesanan mulai diproses di dapur.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
  elsif p_action='ready' then
    if v_old.order_status not in ('confirmed','preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set order_status='ready',ready_at=coalesce(ready_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id) values(p_id,'kitchen_ready',v_old.order_status,'ready','Pesanan siap disajikan.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
  elsif p_action='complete' then
    if v_old.order_status not in ('ready','completed') then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set order_status='completed',completed_at=coalesce(completed_at,v_now),updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id) values(p_id,'kitchen_completed',v_old.order_status,'completed','Pesanan selesai disajikan.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
  elsif p_action='print' then
    update public.orders set kitchen_print_count=coalesce(kitchen_print_count,0)+1,kitchen_last_printed_at=v_now,updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id) values(p_id,'kitchen_printed',v_old.order_status,v_old.order_status,'Kitchen ticket dicetak.',v_actor_id,v_email,v_role,'kds',v_old.request_id);
  else return jsonb_build_object('ok',false,'error','invalid_action'); end if;
  return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row));
end
$function$;

create or replace function public.archive_orders_older_than_7d() returns integer
language plpgsql security definer set search_path=''
as $function$
declare v_count integer:=0;
begin
  insert into public.order_history_archive(
    id,public_order_code,created_at,customer_name,customer_whatsapp,service_mode,table_number,items,item_count,total_amount,customer_note,paid_amount,payment_difference,producer_note,archived_at,
    payment_method,payment_status,order_status,payment_proof_url,client_order_id,payment_submitted_at,verified_at,verified_by,kitchen_sent_at,updated_at,kds_received_at,preparing_at,ready_at,completed_at,kitchen_print_count,kitchen_last_printed_at,
    payment_proof_sha256,proof_check_status,proof_merchant_match,proof_amount_match,proof_date_match,proof_time_match,proof_amount_detected,proof_date_detected,proof_time_detected,proof_checked_at,order_source,cashier_actor,cash_received,change_amount,events,request_id)
  select o.id,o.public_order_code,o.created_at,o.customer_name,o.customer_whatsapp,o.service_mode,o.table_number,o.items,o.item_count,o.total_amount,o.customer_note,o.paid_amount,o.payment_difference,o.producer_note,now(),
    o.payment_method,o.payment_status,o.order_status,o.payment_proof_url,o.client_order_id,o.payment_submitted_at,o.verified_at,o.verified_by,o.kitchen_sent_at,o.updated_at,o.kds_received_at,o.preparing_at,o.ready_at,o.completed_at,o.kitchen_print_count,o.kitchen_last_printed_at,
    o.payment_proof_sha256,o.proof_check_status,o.proof_merchant_match,o.proof_amount_match,o.proof_date_match,o.proof_time_match,o.proof_amount_detected,o.proof_date_detected,o.proof_time_detected,o.proof_checked_at,o.order_source,o.cashier_actor,o.cash_received,o.change_amount,
    coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at) from public.order_events e where e.order_id=o.id),'[]'::jsonb),o.request_id
  from public.orders o where o.created_at<now()-interval '7 days'
  on conflict(id) do update set
    customer_name=excluded.customer_name,customer_whatsapp=excluded.customer_whatsapp,service_mode=excluded.service_mode,table_number=excluded.table_number,items=excluded.items,item_count=excluded.item_count,total_amount=excluded.total_amount,customer_note=excluded.customer_note,paid_amount=excluded.paid_amount,payment_difference=excluded.payment_difference,producer_note=excluded.producer_note,archived_at=excluded.archived_at,payment_method=excluded.payment_method,payment_status=excluded.payment_status,order_status=excluded.order_status,payment_proof_url=excluded.payment_proof_url,client_order_id=excluded.client_order_id,payment_submitted_at=excluded.payment_submitted_at,verified_at=excluded.verified_at,verified_by=excluded.verified_by,kitchen_sent_at=excluded.kitchen_sent_at,updated_at=excluded.updated_at,kds_received_at=excluded.kds_received_at,preparing_at=excluded.preparing_at,ready_at=excluded.ready_at,completed_at=excluded.completed_at,kitchen_print_count=excluded.kitchen_print_count,kitchen_last_printed_at=excluded.kitchen_last_printed_at,payment_proof_sha256=excluded.payment_proof_sha256,proof_check_status=excluded.proof_check_status,proof_merchant_match=excluded.proof_merchant_match,proof_amount_match=excluded.proof_amount_match,proof_date_match=excluded.proof_date_match,proof_time_match=excluded.proof_time_match,proof_amount_detected=excluded.proof_amount_detected,proof_date_detected=excluded.proof_date_detected,proof_time_detected=excluded.proof_time_detected,proof_checked_at=excluded.proof_checked_at,order_source=excluded.order_source,cashier_actor=excluded.cashier_actor,cash_received=excluded.cash_received,change_amount=excluded.change_amount,events=excluded.events,request_id=excluded.request_id;
  get diagnostics v_count=row_count;
  delete from public.order_events e using public.orders o where e.order_id=o.id and o.created_at<now()-interval '7 days';
  delete from public.orders where created_at<now()-interval '7 days';
  return v_count;
end
$function$;

create or replace function private.refresh_production_health_state() returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_routes boolean; v_writer boolean; v_locks boolean; v_outbox boolean; v_failed bigint; v_dead bigint; v_stale bigint; v_sensitive bigint;
  v_checks jsonb; v_healthy boolean; v_integration jsonb; v_integration_ok boolean;
begin
  select (public_url='https://rohmat-pesan-bayar-publik.vercel.app/' and admin_url='https://studio-pengelola-rohmat.vercel.app' and kds_url='https://rohmat-kds-printer.vercel.app') into v_routes from public.site_settings where id=1;
  select coalesce(enabled,false) and coalesce(writer_url,'') like 'https://script.google.com/macros/s/%/exec' into v_writer from public.sheet_sync_config where id=1;
  select coalesce(bool_and(locked),false) into v_locks from private.production_change_control;
  select count(*) filter(where status='failed'),count(*) filter(where status='dead'),count(*) filter(where status in ('pending','processing') and created_at<now()-interval '5 minutes') into v_failed,v_dead,v_stale from public.sheet_sync_outbox;
  v_outbox:=(v_failed=0 and v_dead=0 and v_stale=0);
  select count(*) into v_sensitive from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE');
  v_integration:=private.integration_contract_status(); v_integration_ok:=coalesce((v_integration->>'ok')::boolean,false);
  v_checks:=jsonb_build_object('canonical_routes',coalesce(v_routes,false),'writer_enabled',coalesce(v_writer,false),'change_control_locked',coalesce(v_locks,false),'sheet_outbox_clean',coalesce(v_outbox,false),'sheet_failed',coalesce(v_failed,0),'sheet_dead',coalesce(v_dead,0),'sheet_stale',coalesce(v_stale,0),'anon_public_security_definer',coalesce(v_sensitive,0),'integration_contracts',v_integration,'integration_contracts_ok',v_integration_ok);
  v_healthy:=coalesce(v_routes,false) and coalesce(v_writer,false) and coalesce(v_locks,false) and coalesce(v_outbox,false) and coalesce(v_sensitive,0)=0 and v_integration_ok;
  insert into private.production_health_state(id,healthy,checks,checked_at) values(1,v_healthy,v_checks,now()) on conflict(id) do update set healthy=excluded.healthy,checks=excluded.checks,checked_at=excluded.checked_at;
  return jsonb_build_object('healthy',v_healthy,'checks',v_checks,'checked_at',now());
end
$function$;
