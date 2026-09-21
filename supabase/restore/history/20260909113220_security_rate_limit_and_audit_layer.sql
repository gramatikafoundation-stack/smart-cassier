-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909113220  Name: security_rate_limit_and_audit_layer
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists public.security_rate_limits (
  bucket text not null,
  key_hash text not null,
  window_started_at timestamptz not null default now(),
  hits integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (bucket,key_hash),
  constraint security_rate_limits_hits_nonnegative check (hits >= 0),
  constraint security_rate_limits_key_len check (char_length(key_hash) between 32 and 128)
);
alter table public.security_rate_limits enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='security_rate_limits' and policyname='deny_client_access') then
    create policy deny_client_access on public.security_rate_limits for all to anon, authenticated using(false) with check(false);
  end if;
end $$;

create table if not exists public.security_audit_events (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  event_type text not null,
  action text,
  principal_hash text,
  ip_hash text,
  success boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  constraint security_audit_metadata_object check (jsonb_typeof(metadata)='object')
);
alter table public.security_audit_events enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='security_audit_events' and policyname='deny_client_access') then
    create policy deny_client_access on public.security_audit_events for all to anon, authenticated using(false) with check(false);
  end if;
end $$;
create index if not exists security_audit_events_created_at_idx on public.security_audit_events(created_at desc);
create index if not exists security_audit_events_event_created_idx on public.security_audit_events(event_type,created_at desc);

create or replace function public.security_consume_rate_limit(
  p_bucket text,
  p_key_hash text,
  p_limit integer,
  p_window_seconds integer,
  p_lock_seconds integer
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v public.security_rate_limits%rowtype;
  v_now timestamptz := now();
  v_limit integer := greatest(1,least(coalesce(p_limit,10),10000));
  v_window integer := greatest(10,least(coalesce(p_window_seconds,900),86400));
  v_lock integer := greatest(0,least(coalesce(p_lock_seconds,900),86400));
begin
  if coalesce(length(p_bucket),0) < 1 or coalesce(length(p_key_hash),0) < 32 then
    return jsonb_build_object('ok',false,'allowed',false,'error','invalid_rate_key');
  end if;
  insert into public.security_rate_limits(bucket,key_hash,window_started_at,hits,updated_at)
  values(left(p_bucket,80),left(p_key_hash,128),v_now,0,v_now)
  on conflict(bucket,key_hash) do nothing;
  select * into v from public.security_rate_limits where bucket=left(p_bucket,80) and key_hash=left(p_key_hash,128) for update;
  if v.locked_until is not null and v.locked_until > v_now then
    return jsonb_build_object('ok',true,'allowed',false,'retry_after',greatest(1,ceil(extract(epoch from (v.locked_until-v_now)))::int));
  end if;
  if v.window_started_at + make_interval(secs=>v_window) <= v_now then
    update public.security_rate_limits set window_started_at=v_now,hits=1,locked_until=null,updated_at=v_now where bucket=v.bucket and key_hash=v.key_hash returning * into v;
    return jsonb_build_object('ok',true,'allowed',true,'remaining',v_limit-1);
  end if;
  v.hits := v.hits + 1;
  if v.hits > v_limit then
    update public.security_rate_limits set hits=v.hits,locked_until=case when v_lock>0 then v_now+make_interval(secs=>v_lock) else v_now+make_interval(secs=>v_window) end,updated_at=v_now where bucket=v.bucket and key_hash=v.key_hash returning * into v;
    return jsonb_build_object('ok',true,'allowed',false,'retry_after',greatest(1,ceil(extract(epoch from (v.locked_until-v_now)))::int));
  end if;
  update public.security_rate_limits set hits=v.hits,updated_at=v_now where bucket=v.bucket and key_hash=v.key_hash;
  return jsonb_build_object('ok',true,'allowed',true,'remaining',greatest(0,v_limit-v.hits));
end;
$$;

revoke all on function public.security_consume_rate_limit(text,text,integer,integer,integer) from public,anon,authenticated;
grant execute on function public.security_consume_rate_limit(text,text,integer,integer,integer) to service_role;
revoke all on public.security_rate_limits from anon,authenticated;
revoke all on public.security_audit_events from anon,authenticated;
grant select,insert,update,delete on public.security_rate_limits to service_role;
grant select,insert,update,delete on public.security_audit_events to service_role;
