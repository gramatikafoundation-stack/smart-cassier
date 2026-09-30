-- SDB AI Core bootstrap. Portable private control-plane.
create schema if not exists sdb_ai;
revoke all on schema sdb_ai from public;
revoke all on schema sdb_ai from anon;
revoke all on schema sdb_ai from authenticated;
grant usage on schema sdb_ai to service_role;

create table if not exists sdb_ai.products (
  product_key text primary key check (product_key ~ '^[a-z0-9][a-z0-9_-]{1,63}$'),
  display_name text not null check (char_length(display_name) between 2 and 120),
  enabled boolean not null default true,
  risk_profile text not null default 'medium' check (risk_profile in ('low','medium','high')),
  data_policy jsonb not null default '{"allow_secrets":false,"allow_raw_payment_credentials":false,"allow_full_table_dump":false}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists sdb_ai.model_routes (
  task_class text primary key check (task_class in ('simple','standard','complex','vision')),
  primary_model text not null,
  fallback_model text,
  reasoning_effort text not null default 'low' check (reasoning_effort in ('none','low','medium','high')),
  max_output_tokens integer not null check (max_output_tokens between 128 and 32768),
  max_input_bytes integer not null default 65536 check (max_input_bytes between 1024 and 1048576),
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists sdb_ai.model_rates (
  model text primary key,
  input_usd_per_million numeric(12,6) not null check (input_usd_per_million >= 0),
  output_usd_per_million numeric(12,6) not null check (output_usd_per_million >= 0),
  source_note text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists sdb_ai.prompt_registry (
  product_key text not null references sdb_ai.products(product_key) on delete cascade,
  prompt_key text not null check (prompt_key ~ '^[a-z0-9][a-z0-9_.-]{1,95}$'),
  task_class text not null references sdb_ai.model_routes(task_class),
  instructions text not null,
  response_schema jsonb,
  active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(product_key,prompt_key,version)
);
create unique index if not exists sdb_ai_prompt_one_active_version
  on sdb_ai.prompt_registry(product_key,prompt_key) where active;
create index if not exists sdb_ai_prompt_task_class_idx
  on sdb_ai.prompt_registry(task_class);

create table if not exists sdb_ai.tool_policies (
  product_key text not null references sdb_ai.products(product_key) on delete cascade,
  tool_name text not null,
  risk_level text not null check (risk_level in ('read','safe_write','external_action','critical')),
  requires_approval boolean not null default false,
  allowed_roles text[] not null default '{}'::text[],
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key(product_key,tool_name)
);

create table if not exists sdb_ai.usage_events (
  id uuid primary key default gen_random_uuid(),
  request_id text not null unique,
  product_key text not null references sdb_ai.products(product_key),
  tenant_ref text,
  user_subject_hash text,
  task_class text not null,
  model text,
  status text not null check (status in ('accepted','completed','rejected','failed')),
  input_tokens integer,
  output_tokens integer,
  latency_ms integer,
  estimated_cost_usd numeric(14,6),
  error_code text,
  created_at timestamptz not null default now()
);
create index if not exists sdb_ai_usage_product_created_idx
  on sdb_ai.usage_events(product_key,created_at desc);
create index if not exists sdb_ai_usage_tenant_created_idx
  on sdb_ai.usage_events(tenant_ref,created_at desc) where tenant_ref is not null;

create table if not exists sdb_ai.audit_events (
  id uuid primary key default gen_random_uuid(),
  request_id text,
  product_key text,
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists sdb_ai_audit_created_idx on sdb_ai.audit_events(created_at desc);

create table if not exists sdb_ai.spend_controls (
  product_key text primary key references sdb_ai.products(product_key) on delete cascade,
  requests_per_minute integer not null default 30 check (requests_per_minute between 1 and 10000),
  daily_request_limit integer not null default 500 check (daily_request_limit between 1 and 10000000),
  monthly_input_token_limit bigint not null default 5000000 check (monthly_input_token_limit > 0),
  monthly_output_token_limit bigint not null default 1000000 check (monthly_output_token_limit > 0),
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

revoke all on all tables in schema sdb_ai from public,anon,authenticated;
grant select,insert,update,delete on all tables in schema sdb_ai to service_role;
alter default privileges in schema sdb_ai revoke all on tables from public,anon,authenticated;
alter default privileges in schema sdb_ai grant select,insert,update,delete on tables to service_role;

-- Runtime seed values and prompt contracts are intentionally versioned/configurable.
-- Apply product/model/prompt/tool/spend seed records from the bootstrap runbook or controlled migration.
