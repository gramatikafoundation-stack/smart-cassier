-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260910185010  Name: add_reliable_event_driven_google_sheet_sync
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists public.sheet_sync_targets (
  year integer primary key check (year between 2026 and 2100),
  spreadsheet_id text not null,
  label text not null,
  enabled boolean not null default true,
  expected_tabs jsonb not null default '["DASHBOARD","PEMESAN","PESANAN","MENU & STOK","KEUANGAN"]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sheet_sync_config (
  id smallint primary key default 1 check (id = 1),
  enabled boolean not null default false,
  writer_url text,
  writer_secret_id uuid,
  max_attempts smallint not null default 10 check (max_attempts between 1 and 25),
  reconciliation_minutes smallint not null default 10 check (reconciliation_minutes between 5 and 60),
  updated_at timestamptz not null default now(),
  constraint sheet_sync_writer_url_https check (writer_url is null or writer_url ~ '^https://')
);

insert into public.sheet_sync_config(id, enabled)
values (1, false)
on conflict (id) do nothing;

insert into public.sheet_sync_targets(year, spreadsheet_id, label, enabled)
values
  (2026,'1rj3kXuBGjQC_bkJXJ_n6Jao7hkco7rpFF7avozcj-Ok','DATABASE UMKM HEBAT — ROHMAT NASI UDUK — 2026',true),
  (2027,'1vie6JW_Koq7QXkehtb1wZBgl-GEaNlQ68fJxsCGXYBU','DATABASE UMKM HEBAT — ROHMAT NASI UDUK — 2027',true),
  (2028,'14c-JE3s2Kws9zBYdemyNU1FSH9Z_iWU6QrqcOYznUU8','DATABASE UMKM HEBAT — ROHMAT NASI UDUK — 2028',true),
  (2029,'1efPqyinNl86iwovbZWRYL9HfOyLvn8lTQiusZNHsSsA','DATABASE UMKM HEBAT — ROHMAT NASI UDUK — 2029',true),
  (2030,'1Tjtw30thkNXKSNVn6VpBkAq_pOasGIC3CgCf5y0u9xk','DATABASE UMKM HEBAT — ROHMAT NASI UDUK — 2030',true)
on conflict (year) do update set spreadsheet_id=excluded.spreadsheet_id,label=excluded.label,enabled=excluded.enabled,updated_at=now();

create table if not exists public.sheet_sync_outbox (
  event_id uuid primary key default gen_random_uuid(),
  idempotency_key text not null unique,
  entity_type text not null check (entity_type in ('order','menu','system')),
  entity_id text not null,
  operation text not null check (operation in ('INSERT','UPDATE','DELETE','ARCHIVE','RECONCILE')),
  target_year integer check (target_year is null or target_year between 2026 and 2100),
  affected_tabs jsonb not null default '[]'::jsonb,
  payload jsonb not null default '{}'::jsonb,
  source_updated_at timestamptz,
  status text not null default 'pending' check (status in ('pending','processing','synced','failed','dead','superseded')),
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  last_attempt_at timestamptz,
  synced_at timestamptz,
  last_http_status integer,
  last_error text,
  locked_until timestamptz,
  locked_by text,
  created_at timestamptz not null default now()
);

create index if not exists sheet_sync_outbox_due_idx on public.sheet_sync_outbox(status,next_attempt_at,created_at) where status in ('pending','failed');
create index if not exists sheet_sync_outbox_entity_idx on public.sheet_sync_outbox(entity_type,entity_id,target_year,created_at desc);
create index if not exists sheet_sync_outbox_year_idx on public.sheet_sync_outbox(target_year,created_at desc);

alter table public.sheet_sync_targets enable row level security;
alter table public.sheet_sync_config enable row level security;
alter table public.sheet_sync_outbox enable row level security;
revoke all on public.sheet_sync_targets from anon, authenticated;
revoke all on public.sheet_sync_config from anon, authenticated;
revoke all on public.sheet_sync_outbox from anon, authenticated;

create or replace function private.enqueue_sheet_sync_event()
returns trigger
language plpgsql
security definer
set search_path = ''
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
begin
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  if tg_table_name = 'menu_items' then
    v_entity_type := 'menu';
    v_entity_id := coalesce(v_row->>'id','unknown');
    v_operation := tg_op;
    v_target_year := null;
    v_updated_at := coalesce((v_row->>'updated_at')::timestamptz, now());
    v_tabs := '["MENU & STOK","DASHBOARD"]'::jsonb;
  elsif tg_table_name = 'order_history_archive' then
    v_entity_type := 'order';
    v_entity_id := coalesce(v_row->>'id','unknown');
    v_operation := 'ARCHIVE';
    v_target_year := extract(year from ((v_row->>'created_at')::timestamptz at time zone 'Asia/Jakarta'))::integer;
    v_updated_at := coalesce((v_row->>'archived_at')::timestamptz,(v_row->>'created_at')::timestamptz,now());
    v_tabs := '["PEMESAN","PESANAN","MENU & STOK","KEUANGAN","DASHBOARD"]'::jsonb;
  else
    v_entity_type := 'order';
    v_entity_id := coalesce(v_row->>'id','unknown');
    v_operation := tg_op;
    v_target_year := extract(year from ((v_row->>'created_at')::timestamptz at time zone 'Asia/Jakarta'))::integer;
    v_updated_at := coalesce((v_row->>'updated_at')::timestamptz,(v_row->>'created_at')::timestamptz,now());
    v_tabs := '["PEMESAN","PESANAN","MENU & STOK","KEUANGAN","DASHBOARD"]'::jsonb;
  end if;

  v_key := tg_table_name || ':' || v_entity_id || ':' || v_operation || ':' || md5(v_row::text);

  update public.sheet_sync_outbox
     set status='superseded', last_error='Superseded by a newer event for the same entity.'
   where entity_type=v_entity_type
     and entity_id=v_entity_id
     and target_year is not distinct from v_target_year
     and status in ('pending','failed');

  insert into public.sheet_sync_outbox(
    idempotency_key,entity_type,entity_id,operation,target_year,affected_tabs,payload,source_updated_at
  ) values (
    v_key,v_entity_type,v_entity_id,v_operation,v_target_year,v_tabs,
    jsonb_build_object(
      'source_table',tg_table_name,
      'entity_id',v_entity_id,
      'operation',v_operation,
      'target_year',v_target_year,
      'source_updated_at',v_updated_at,
      'affected_tabs',v_tabs
    ),
    v_updated_at
  ) on conflict (idempotency_key) do nothing;

  return case when tg_op='DELETE' then old else new end;
end
$$;

revoke all on function private.enqueue_sheet_sync_event() from public, anon, authenticated;

-- Orders: enqueue only mutations that can change Sheets-visible data.
drop trigger if exists trg_sheet_sync_orders_insert on public.orders;
create trigger trg_sheet_sync_orders_insert
after insert on public.orders
for each row execute function private.enqueue_sheet_sync_event();

drop trigger if exists trg_sheet_sync_orders_update on public.orders;
create trigger trg_sheet_sync_orders_update
after update of public_order_code,service_mode,table_number,customer_name,customer_whatsapp,items,item_count,total_amount,payment_method,payment_status,order_status,payment_proof_url,customer_note,payment_submitted_at,verified_at,kitchen_sent_at,kds_received_at,preparing_at,ready_at,completed_at,paid_amount,payment_difference,producer_note,order_source,cashier_actor,cash_received,change_amount on public.orders
for each row execute function private.enqueue_sheet_sync_event();

-- Menu mutations affect MENU & STOK and dashboard analytics.
drop trigger if exists trg_sheet_sync_menu_insert on public.menu_items;
create trigger trg_sheet_sync_menu_insert
after insert on public.menu_items
for each row execute function private.enqueue_sheet_sync_event();

drop trigger if exists trg_sheet_sync_menu_update on public.menu_items;
create trigger trg_sheet_sync_menu_update
after update of name,category,price,image_url,is_visible,is_available,availability_note,availability_updated_at,display_order on public.menu_items
for each row execute function private.enqueue_sheet_sync_event();

drop trigger if exists trg_sheet_sync_menu_delete on public.menu_items;
create trigger trg_sheet_sync_menu_delete
after delete on public.menu_items
for each row execute function private.enqueue_sheet_sync_event();

-- Archival is also a sync event so a missed active-order event can be repaired.
drop trigger if exists trg_sheet_sync_archive_insert on public.order_history_archive;
create trigger trg_sheet_sync_archive_insert
after insert on public.order_history_archive
for each row execute function private.enqueue_sheet_sync_event();

create or replace function private.enqueue_sheet_reconciliation()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enabled boolean;
  v_count integer := 0;
  r record;
  v_bucket text;
begin
  select enabled into v_enabled from public.sheet_sync_config where id=1;
  if coalesce(v_enabled,false) is false then return 0; end if;
  v_bucket := to_char(date_trunc('hour',now()) + floor(extract(minute from now())/10)*interval '10 minutes','YYYYMMDDHH24MI');
  for r in select year from public.sheet_sync_targets where enabled order by year loop
    insert into public.sheet_sync_outbox(idempotency_key,entity_type,entity_id,operation,target_year,affected_tabs,payload,source_updated_at)
    values(
      'reconcile:'||r.year::text||':'||v_bucket,
      'system',r.year::text,'RECONCILE',r.year,
      '["DASHBOARD","PEMESAN","PESANAN","MENU & STOK","KEUANGAN"]'::jsonb,
      jsonb_build_object('reason','periodic_reconciliation','target_year',r.year,'bucket',v_bucket),now()
    ) on conflict (idempotency_key) do nothing;
    if found then v_count := v_count + 1; end if;
  end loop;
  return v_count;
end
$$;
revoke all on function private.enqueue_sheet_reconciliation() from public, anon, authenticated;

create or replace function private.process_sheet_sync_outbox(p_batch_size integer default 50)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cfg public.sheet_sync_config%rowtype;
  v_secret text;
  v_ids uuid[];
  v_payload jsonb;
  v_response extensions.http_response;
  v_attempt integer;
  v_backoff integer;
  v_count integer := 0;
begin
  select * into v_cfg from public.sheet_sync_config where id=1;
  if not found or coalesce(v_cfg.enabled,false)=false or coalesce(v_cfg.writer_url,'')='' then return 0; end if;
  if v_cfg.writer_secret_id is not null then
    select decrypted_secret into v_secret from vault.decrypted_secrets where id=v_cfg.writer_secret_id;
  end if;
  if v_cfg.writer_secret_id is not null and coalesce(v_secret,'')='' then return 0; end if;

  with due as (
    select event_id
      from public.sheet_sync_outbox
     where status in ('pending','failed')
       and next_attempt_at <= now()
       and (locked_until is null or locked_until < now())
     order by created_at
     limit greatest(1,least(coalesce(p_batch_size,50),200))
     for update skip locked
  ), claimed as (
    update public.sheet_sync_outbox o
       set status='processing',locked_until=now()+interval '2 minutes',locked_by='pg_cron',last_attempt_at=now(),attempts=attempts+1
      from due
     where o.event_id=due.event_id
     returning o.event_id
  )
  select array_agg(event_id) into v_ids from claimed;

  if v_ids is null or cardinality(v_ids)=0 then return 0; end if;

  select jsonb_build_object(
    'schema_version',1,
    'sent_at',now(),
    'targets',coalesce((select jsonb_agg(jsonb_build_object('year',t.year,'spreadsheet_id',t.spreadsheet_id,'label',t.label,'expected_tabs',t.expected_tabs) order by t.year) from public.sheet_sync_targets t where t.enabled),'[]'::jsonb),
    'events',coalesce(jsonb_agg(jsonb_build_object(
      'event_id',o.event_id,
      'idempotency_key',o.idempotency_key,
      'entity_type',o.entity_type,
      'entity_id',o.entity_id,
      'operation',o.operation,
      'target_year',o.target_year,
      'affected_tabs',o.affected_tabs,
      'payload',o.payload,
      'source_updated_at',o.source_updated_at,
      'attempt',o.attempts
    ) order by o.created_at),'[]'::jsonb)
  ) into v_payload
  from public.sheet_sync_outbox o
  where o.event_id=any(v_ids);

  begin
    perform set_config('http.timeout_msec','8000',true);
    v_response := extensions.http((
      'POST',
      v_cfg.writer_url,
      case when coalesce(v_secret,'')<>'' then array[
        row('Authorization','Bearer '||v_secret)::extensions.http_header,
        row('X-Rohmat-Sync-Schema','1')::extensions.http_header
      ] else array[row('X-Rohmat-Sync-Schema','1')::extensions.http_header] end,
      'application/json',
      v_payload::text
    )::extensions.http_request);

    if v_response.status between 200 and 299 then
      update public.sheet_sync_outbox
         set status='synced',synced_at=now(),last_http_status=v_response.status,last_error=null,locked_until=null,locked_by=null
       where event_id=any(v_ids);
      get diagnostics v_count = row_count;
      return v_count;
    end if;

    for v_attempt in select attempts from public.sheet_sync_outbox where event_id=any(v_ids) limit 1 loop
      v_backoff := least(3600, 15 * (2 ^ least(v_attempt,8)));
    end loop;
    update public.sheet_sync_outbox
       set status=case when attempts>=v_cfg.max_attempts then 'dead' else 'failed' end,
           next_attempt_at=now()+make_interval(secs=>coalesce(v_backoff,60)),
           last_http_status=v_response.status,
           last_error=left(coalesce(v_response.content,'HTTP error'),1000),
           locked_until=null,locked_by=null
     where event_id=any(v_ids);
    return 0;
  exception when others then
    update public.sheet_sync_outbox
       set status=case when attempts>=v_cfg.max_attempts then 'dead' else 'failed' end,
           next_attempt_at=now()+make_interval(secs=>least(3600,15*(2 ^ least(attempts,8)))),
           last_error=left(sqlerrm,1000),
           locked_until=null,locked_by=null
     where event_id=any(v_ids);
    return 0;
  end;
end
$$;
revoke all on function private.process_sheet_sync_outbox(integer) from public, anon, authenticated;

create or replace function public.get_sheet_sync_health()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
select jsonb_build_object(
  'enabled',coalesce((select enabled from public.sheet_sync_config where id=1),false),
  'writer_configured',coalesce((select writer_url is not null and writer_url<>'' from public.sheet_sync_config where id=1),false),
  'active_targets',(select count(*) from public.sheet_sync_targets where enabled),
  'pending',(select count(*) from public.sheet_sync_outbox where status='pending'),
  'failed',(select count(*) from public.sheet_sync_outbox where status='failed'),
  'dead',(select count(*) from public.sheet_sync_outbox where status='dead'),
  'processing',(select count(*) from public.sheet_sync_outbox where status='processing'),
  'synced',(select count(*) from public.sheet_sync_outbox where status='synced'),
  'superseded',(select count(*) from public.sheet_sync_outbox where status='superseded'),
  'oldest_pending_at',(select min(created_at) from public.sheet_sync_outbox where status in ('pending','failed')),
  'last_event_at',(select max(created_at) from public.sheet_sync_outbox),
  'last_synced_at',(select max(synced_at) from public.sheet_sync_outbox where status='synced')
)
$$;
revoke all on function public.get_sheet_sync_health() from public, anon, authenticated;

select cron.unschedule('rohmat_sheet_sync_worker') where exists (select 1 from cron.job where jobname='rohmat_sheet_sync_worker');
select cron.unschedule('rohmat_sheet_sync_reconcile') where exists (select 1 from cron.job where jobname='rohmat_sheet_sync_reconcile');
select cron.schedule('rohmat_sheet_sync_worker','* * * * *','select private.process_sheet_sync_outbox(100);');
select cron.schedule('rohmat_sheet_sync_reconcile','*/10 * * * *','select private.enqueue_sheet_reconciliation();');

-- Bootstrap one reconciliation event for every configured annual target.
insert into public.sheet_sync_outbox(idempotency_key,entity_type,entity_id,operation,target_year,affected_tabs,payload,source_updated_at)
select 'bootstrap:'||year::text||':v1','system',year::text,'RECONCILE',year,
       '["DASHBOARD","PEMESAN","PESANAN","MENU & STOK","KEUANGAN"]'::jsonb,
       jsonb_build_object('reason','bootstrap_full_reconciliation','target_year',year),now()
from public.sheet_sync_targets
where enabled
on conflict (idempotency_key) do nothing;
