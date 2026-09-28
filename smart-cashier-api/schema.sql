create extension if not exists pgcrypto;

do $$ begin
  create type smart_cashier_role as enum ('OWNER','ADMIN','CASHIER','KITCHEN','VIEWER');
exception when duplicate_object then null; end $$;

do $$ begin
  create type smart_cashier_order_status as enum ('DRAFT','AWAITING_PAYMENT','PAID','NEW','PROCESSING','READY','COMPLETED','CANCELLED','REFUNDED');
exception when duplicate_object then null; end $$;

create table if not exists tenants (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,62}$'),
  name text not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','SUSPENDED','ARCHIVED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists outlets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  code text not null,
  name text not null,
  timezone text not null default 'Asia/Jakarta',
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code)
);

create table if not exists app_users (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  outlet_id uuid references outlets(id) on delete set null,
  email text not null,
  display_name text not null,
  password_hash text not null,
  role smart_cashier_role not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','DISABLED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, lower(email))
);

create table if not exists sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app_users(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  outlet_id uuid references outlets(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists sessions_user_idx on sessions(user_id);
create index if not exists sessions_expiry_idx on sessions(expires_at);

create table if not exists settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  outlet_id uuid not null references outlets(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  unique (tenant_id, outlet_id)
);

create table if not exists categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  outlet_id uuid not null references outlets(id) on delete cascade,
  name text not null,
  sort_order integer not null default 0,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, outlet_id, lower(name))
);

create table if not exists menu_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  outlet_id uuid not null references outlets(id) on delete cascade,
  category_id uuid references categories(id) on delete set null,
  sku text not null,
  name text not null,
  price numeric(14,2) not null check (price >= 0),
  cost numeric(14,2),
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  station text not null default 'LAINNYA',
  stock numeric(14,3),
  sort_order integer not null default 0,
  image_url text,
  description text,
  internal_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, outlet_id, lower(sku))
);
create index if not exists menu_items_tenant_outlet_idx on menu_items(tenant_id,outlet_id,status);

create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  outlet_id uuid not null references outlets(id) on delete cascade,
  order_code text not null,
  idempotency_key text not null,
  customer_name text not null,
  service_mode text not null check (service_mode in ('DINE_IN','TAKE_AWAY')),
  table_number text,
  subtotal numeric(14,2) not null check (subtotal >= 0),
  discount numeric(14,2) not null default 0 check (discount >= 0),
  tax numeric(14,2) not null default 0 check (tax >= 0),
  grand_total numeric(14,2) not null check (grand_total >= 0),
  payment_method text not null check (payment_method in ('CASH','QRIS','TRANSFER')),
  payment_status text not null default 'PAID' check (payment_status in ('UNPAID','PAID','REFUNDED')),
  order_status smart_cashier_order_status not null default 'NEW',
  cashier_user_id uuid references app_users(id) on delete set null,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (tenant_id, outlet_id, order_code),
  unique (tenant_id, outlet_id, idempotency_key),
  check ((service_mode='TAKE_AWAY') or table_number is not null)
);
create index if not exists orders_tenant_outlet_created_idx on orders(tenant_id,outlet_id,created_at desc);
create index if not exists orders_kds_idx on orders(tenant_id,outlet_id,order_status,created_at);

create table if not exists order_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  outlet_id uuid not null references outlets(id) on delete cascade,
  order_id uuid not null references orders(id) on delete cascade,
  menu_id uuid references menu_items(id) on delete set null,
  menu_name text not null,
  station text not null,
  qty numeric(14,3) not null check (qty > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  subtotal numeric(14,2) not null check (subtotal >= 0),
  note text,
  created_at timestamptz not null default now()
);
create index if not exists order_items_order_idx on order_items(order_id);

create table if not exists payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  outlet_id uuid not null references outlets(id) on delete cascade,
  order_id uuid not null unique references orders(id) on delete cascade,
  method text not null check (method in ('CASH','QRIS','TRANSFER')),
  amount numeric(14,2) not null check (amount >= 0),
  cash_received numeric(14,2),
  change_amount numeric(14,2),
  reference text,
  verified boolean not null default false,
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists kds_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  outlet_id uuid not null references outlets(id) on delete cascade,
  order_id uuid not null references orders(id) on delete cascade,
  previous_status smart_cashier_order_status,
  new_status smart_cashier_order_status not null,
  station text,
  actor_user_id uuid references app_users(id) on delete set null,
  note text,
  occurred_at timestamptz not null default now()
);
create index if not exists kds_events_order_idx on kds_events(order_id,occurred_at);

create table if not exists activity_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  outlet_id uuid references outlets(id) on delete set null,
  actor_user_id uuid references app_users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists activity_logs_scope_idx on activity_logs(tenant_id,outlet_id,created_at desc);

create table if not exists realtime_events (
  id bigserial primary key,
  tenant_id uuid not null references tenants(id) on delete cascade,
  outlet_id uuid not null references outlets(id) on delete cascade,
  topic text not null,
  entity_id text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists realtime_events_scope_idx on realtime_events(tenant_id,outlet_id,id);

create or replace function app_tenant_id() returns uuid language sql stable as $$
  select nullif(current_setting('app.tenant_id',true),'')::uuid
$$;
create or replace function app_outlet_id() returns uuid language sql stable as $$
  select nullif(current_setting('app.outlet_id',true),'')::uuid
$$;
create or replace function app_user_id() returns uuid language sql stable as $$
  select nullif(current_setting('app.user_id',true),'')::uuid
$$;
create or replace function app_role() returns text language sql stable as $$
  select nullif(current_setting('app.role',true),'')
$$;

do $$ begin
  create role smart_cashier_app nologin;
exception when duplicate_object then null; end $$;

grant usage on schema public to smart_cashier_app;
grant select,insert,update,delete on tenants,outlets,app_users,sessions,settings,categories,menu_items,orders,order_items,payments,kds_events,activity_logs,realtime_events to smart_cashier_app;
grant usage,select on all sequences in schema public to smart_cashier_app;

alter table tenants enable row level security; alter table tenants force row level security;
alter table outlets enable row level security; alter table outlets force row level security;
alter table app_users enable row level security; alter table app_users force row level security;
alter table sessions enable row level security; alter table sessions force row level security;
alter table settings enable row level security; alter table settings force row level security;
alter table categories enable row level security; alter table categories force row level security;
alter table menu_items enable row level security; alter table menu_items force row level security;
alter table orders enable row level security; alter table orders force row level security;
alter table order_items enable row level security; alter table order_items force row level security;
alter table payments enable row level security; alter table payments force row level security;
alter table kds_events enable row level security; alter table kds_events force row level security;
alter table activity_logs enable row level security; alter table activity_logs force row level security;
alter table realtime_events enable row level security; alter table realtime_events force row level security;

drop policy if exists tenant_scope on tenants;
create policy tenant_scope on tenants using (id=app_tenant_id()) with check (id=app_tenant_id());

do $$
declare t text;
begin
  foreach t in array array['outlets','app_users','sessions','settings','categories','menu_items','orders','order_items','payments','kds_events','activity_logs','realtime_events']
  loop
    execute format('drop policy if exists tenant_outlet_scope on %I',t);
    if t in ('outlets','app_users','sessions','activity_logs') then
      execute format('create policy tenant_outlet_scope on %I using (tenant_id=app_tenant_id() and (app_outlet_id() is null or outlet_id is null or outlet_id=app_outlet_id())) with check (tenant_id=app_tenant_id() and (app_outlet_id() is null or outlet_id is null or outlet_id=app_outlet_id()))',t);
    else
      execute format('create policy tenant_outlet_scope on %I using (tenant_id=app_tenant_id() and outlet_id=app_outlet_id()) with check (tenant_id=app_tenant_id() and outlet_id=app_outlet_id())',t);
    end if;
  end loop;
end $$;

create or replace function authenticate_user(p_email text,p_password text)
returns table(user_id uuid,tenant_id uuid,outlet_id uuid,role smart_cashier_role,display_name text)
language sql security definer set search_path=public as $$
  select id,tenant_id,outlet_id,role,display_name
  from app_users
  where lower(email)=lower(trim(p_email))
    and status='ACTIVE'
    and password_hash=crypt(p_password,password_hash)
  limit 1
$$;
revoke all on function authenticate_user(text,text) from public;
grant execute on function authenticate_user(text,text) to smart_cashier_app;

create or replace function bootstrap_master(
  p_bootstrap_key text,p_expected_key text,p_tenant_slug text,p_tenant_name text,p_outlet_code text,p_outlet_name text,
  p_owner_email text,p_owner_name text,p_owner_password text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_tenant uuid; v_outlet uuid; v_user uuid;
begin
  if p_bootstrap_key is null or p_expected_key is null or p_bootstrap_key<>p_expected_key then raise exception 'invalid bootstrap key'; end if;
  if exists(select 1 from tenants) then raise exception 'bootstrap already completed'; end if;
  insert into tenants(slug,name) values(lower(trim(p_tenant_slug)),trim(p_tenant_name)) returning id into v_tenant;
  insert into outlets(tenant_id,code,name) values(v_tenant,upper(trim(p_outlet_code)),trim(p_outlet_name)) returning id into v_outlet;
  insert into app_users(tenant_id,outlet_id,email,display_name,password_hash,role)
  values(v_tenant,v_outlet,lower(trim(p_owner_email)),trim(p_owner_name),crypt(p_owner_password,gen_salt('bf',12)),'OWNER')
  returning id into v_user;
  insert into settings(tenant_id,outlet_id,payload) values(v_tenant,v_outlet,'{}'::jsonb);
  return jsonb_build_object('tenant_id',v_tenant,'outlet_id',v_outlet,'user_id',v_user);
end $$;
revoke all on function bootstrap_master(text,text,text,text,text,text,text,text,text) from public;
grant execute on function bootstrap_master(text,text,text,text,text,text,text,text,text) to smart_cashier_app;
