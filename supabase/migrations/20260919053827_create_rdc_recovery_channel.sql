create table if not exists public.rdc_recovery_devices (
  device_id text primary key,
  device_name text not null,
  recovery_key_hash text not null,
  command text not null default 'none',
  command_seq bigint not null default 0,
  last_handled_seq bigint not null default 0,
  request_state text not null default 'idle',
  verification_url text,
  user_code text,
  request_expires_at timestamptz,
  message text,
  last_seen timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.rdc_recovery_devices enable row level security;

revoke all on table public.rdc_recovery_devices from anon, authenticated;

create index if not exists rdc_recovery_devices_state_idx
  on public.rdc_recovery_devices (request_state, updated_at);
